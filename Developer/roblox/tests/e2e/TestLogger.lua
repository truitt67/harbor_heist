--[[
	TestLogger.lua — Structured JSONL logging for E2E integration tests.

	Pure Luau; no external dependencies. Designed to run both inside a Roblox
	DataModel (where file writes are unavailable) and under lune/run-in-roblox
	(where file writes are available). When file writes are unavailable, events
	are still emitted to stdout via print() so the runner can capture them.

	Required features (TASK 19.1.1):
	  1. JSONL events: {ts, level, scenario, step, msg, data}
	  2. Scenario lifecycle: startScenario, step, assertEq/assertTrue/assertNear,
	     finish — failed assertions also log a full state dump.
	  3. Remote-call wrapper: wrapRemote logs args, response, latency.
	  4. Sinks: print() + file append under testlogs/<scenario>-<runid>.jsonl
	  5. Summary report: per-run totals written to testlogs/summary-<runid>.json
	  6. Timer API: timeIt for perf-sensitive flows.
]]

local TestLogger = {}
TestLogger.__index = TestLogger

local LEVELS = {
	DEBUG = "DEBUG",
	INFO = "INFO",
	STEP = "STEP",
	ASSERT = "ASSERT",
	ERROR = "ERROR",
}

-- ============================================================================
-- Minimal pure-Luau JSON encoder (no external dependencies).
-- Handles strings, numbers, booleans, nil, arrays, and objects.
-- ============================================================================
local function escapeJsonString(s)
	s = tostring(s)
	return '"' .. s:gsub('[\\"%c]', function(c)
		local escapes = {
			['\\'] = '\\\\',
			['"'] = '\\"',
			['\b'] = '\\b',
			['\f'] = '\\f',
			['\n'] = '\\n',
			['\r'] = '\\r',
			['\t'] = '\\t',
		}
		local escaped = escapes[c]
		if escaped then
			return escaped
		end
		return string.format('\\u%04x', string.byte(c))
	end) .. '"'
end

local function encodeJson(value)
	if value == nil then
		return "null"
	end

	local t = type(value)
	if t == "string" then
		return escapeJsonString(value)
	elseif t == "number" then
		if value ~= value then
			return "null" -- NaN
		end
		if value == math.huge or value == -math.huge then
			return "null"
		end
		return tostring(value)
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "table" then
		-- Determine whether the table is an array (sequential integer keys 1..n).
		local maxIndex = 0
		local count = 0
		local isArray = true
		for k, _ in pairs(value) do
			if type(k) ~= "number" or k % 1 ~= 0 or k <= 0 then
				isArray = false
				break
			end
			count += 1
			if k > maxIndex then
				maxIndex = k
			end
		end

		if isArray and maxIndex == count then
			local parts = {}
			for i = 1, maxIndex do
				parts[i] = encodeJson(value[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(value) do
				table.insert(parts, escapeJsonString(tostring(k)) .. ":" .. encodeJson(v))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end

	return "null"
end

-- ============================================================================
-- Helpers
-- ============================================================================
local function isoTimestamp()
	return os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	local ta, tb = type(a), type(b)
	if ta ~= tb or ta ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k, _ in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function tryAppend(path, content)
	-- Prefer lune's @lune/fs module when running under lune; io may not be
	-- available there. In a Roblox DataModel neither exists, so we degrade
	-- gracefully to stdout-only logging.
	local fsOk, fs = pcall(function()
		return require("@lune/fs")
	end)
	if fsOk and fs then
		local dir = path:match("^(.*)/[^/]+$")
		if dir and dir ~= "" and not fs.isDir(dir) then
			fs.writeDir(dir)
		end
		local existing = ""
		if fs.isFile(path) then
			existing = fs.readFile(path)
		end
		fs.writeFile(path, existing .. content .. "\n")
		return true
	end

	if not io or not io.open then
		return false
	end
	local ok, file = pcall(io.open, path, "a")
	if not ok or not file then
		return false
	end
	file:write(content)
	file:write("\n")
	file:close()
	return true
end

local function makeEvent(level, scenario, step, msg, data)
	return {
		ts = isoTimestamp(),
		level = level,
		scenario = scenario or "",
		step = step or "",
		msg = msg or "",
		data = data,
	}
end

-- ============================================================================
-- Constructor
-- ============================================================================
function TestLogger.new(config)
	config = config or {}
	local self = setmetatable({}, TestLogger)

	self.runId = config.runId or tostring(os.time())
	self.logDir = config.logDir or "testlogs"
	self.getState = config.getState -- optional callback returning state snapshot

	self.scenarios = {}
	self.currentScenario = nil
	self.currentStep = nil

	self.totalAsserts = 0
	self.totalFailures = 0

	-- Probe whether file writes are available in this environment.
	self.fileEnabled = false
	local probePath = self.logDir .. "/.logger_probe"
	if tryAppend(probePath, "") then
		self.fileEnabled = true
	end

	return self
end

-- ============================================================================
-- Internal emit: prints JSONL to stdout and, if possible, appends to the
-- scenario-specific JSONL file.
-- ============================================================================
function TestLogger:_emit(level, msg, data)
	local event = makeEvent(level, self.currentScenario and self.currentScenario.id, self.currentStep, msg, data)
	local line = encodeJson(event)

	print(line)

	if self.fileEnabled and self.currentScenario then
		local path = self.logDir .. "/" .. self.currentScenario.id .. "-" .. self.runId .. ".jsonl"
		tryAppend(path, line)
	end

	return event
end

-- ============================================================================
-- Scenario lifecycle
-- ============================================================================
function TestLogger:startScenario(id, description)
	local scenario = {
		id = id,
		description = description,
		startTime = os.clock(),
		stepCount = 0,
		assertCount = 0,
		failureCount = 0,
		passed = true,
	}
	self.scenarios[id] = scenario
	self.currentScenario = scenario
	self.currentStep = "setup"

	self:_emit(LEVELS.INFO, "Scenario started", { description = description })
end

function TestLogger:step(id, description)
	if not self.currentScenario then
		self:startScenario("orphan", "orphan scenario")
	end
	self.currentStep = id
	self.currentScenario.stepCount += 1
	self:_emit(LEVELS.STEP, description or id, {})
end

function TestLogger:finish()
	local scenario = self.currentScenario
	if not scenario then
		return
	end

	local durationMs = (os.clock() - scenario.startTime) * 1000
	scenario.durationMs = durationMs

	self:_emit(LEVELS.INFO, "Scenario finished", {
		passed = scenario.passed,
		durationMs = durationMs,
		asserts = scenario.assertCount,
		failures = scenario.failureCount,
	})

	self.currentScenario = nil
	self.currentStep = nil
end

-- ============================================================================
-- State dump helper
-- ============================================================================
function TestLogger:_getStateDump()
	if not self.getState then
		return nil
	end
	local ok, state = pcall(self.getState)
	if ok then
		return state
	end
	return { error = "state provider failed: " .. tostring(state) }
end

-- ============================================================================
-- Assertions
-- ============================================================================
function TestLogger:assertEq(name, expected, actual)
	if not self.currentScenario then
		self:startScenario("orphan", "orphan scenario")
	end

	self.totalAsserts += 1
	self.currentScenario.assertCount += 1

	local passed = deepEqual(expected, actual)
	if not passed then
		self.currentScenario.passed = false
		self.currentScenario.failureCount += 1
		self.totalFailures += 1
	end

	local data = {
		name = name,
		expected = expected,
		actual = actual,
		passed = passed,
	}
	if not passed then
		data.stateDump = self:_getStateDump()
	end

	self:_emit(LEVELS.ASSERT, (passed and "PASS" or "FAIL") .. ": " .. name, data)
	return passed
end

function TestLogger:assertTrue(name, value)
	return self:assertEq(name, true, not not value)
end

function TestLogger:assertNear(name, expected, actual, tolerance)
	tolerance = tolerance or 0.0001
	local diff = math.abs(expected - actual)
	local passed = diff <= tolerance

	if not self.currentScenario then
		self:startScenario("orphan", "orphan scenario")
	end

	self.totalAsserts += 1
	self.currentScenario.assertCount += 1
	if not passed then
		self.currentScenario.passed = false
		self.currentScenario.failureCount += 1
		self.totalFailures += 1
	end

	local data = {
		name = name,
		expected = expected,
		actual = actual,
		tolerance = tolerance,
		diff = diff,
		passed = passed,
	}
	if not passed then
		data.stateDump = self:_getStateDump()
	end

	self:_emit(LEVELS.ASSERT, (passed and "PASS" or "FAIL") .. ": " .. name, data)
	return passed
end

-- ============================================================================
-- Remote-call wrapper
-- ============================================================================
function TestLogger:wrapRemote(name, fn, ...)
	if not self.currentScenario then
		self:startScenario("orphan", "orphan scenario")
	end

	local args = {...}
	local start = os.clock()
	local ok, result = pcall(fn, ...)
	local elapsedMs = (os.clock() - start) * 1000

	local response
	if ok then
		response = result
	else
		response = { error = tostring(result) }
	end

	self:_emit(LEVELS.INFO, "Remote call: " .. name, {
		remote = name,
		args = args,
		response = response,
		latencyMs = elapsedMs,
		success = ok,
	})

	if not ok then
		error(result, 2)
	end

	return result
end

-- ============================================================================
-- Timer helper
-- ============================================================================
function TestLogger:timeIt(name, fn)
	if not self.currentScenario then
		self:startScenario("orphan", "orphan scenario")
	end

	local start = os.clock()
	local ok, result = pcall(fn)
	local elapsedMs = (os.clock() - start) * 1000

	self:_emit(LEVELS.INFO, "Timed: " .. name, {
		name = name,
		durationMs = elapsedMs,
		success = ok,
	})

	if not ok then
		error(result, 2)
	end

	return result
end

-- ============================================================================
-- Generic log
-- ============================================================================
function TestLogger:log(level, msg, data)
	level = LEVELS[level] or level or LEVELS.INFO
	self:_emit(level, msg, data)
end

-- ============================================================================
-- Summary report
-- ============================================================================
function TestLogger:summary()
	local total = 0
	local passed = 0
	local failed = 0
	local scenarioList = {}

	for id, s in pairs(self.scenarios) do
		total += 1
		if s.passed then
			passed += 1
		else
			failed += 1
		end
		table.insert(scenarioList, {
			id = id,
			description = s.description,
			passed = s.passed,
			asserts = s.assertCount,
			failures = s.failureCount,
			durationMs = s.durationMs,
		})
	end

	local summary = {
		runId = self.runId,
		generatedAt = isoTimestamp(),
		totalScenarios = total,
		passedScenarios = passed,
		failedScenarios = failed,
		totalAsserts = self.totalAsserts,
		totalFailures = self.totalFailures,
		scenarios = scenarioList,
	}

	local line = encodeJson(summary)
	print(line)

	if self.fileEnabled then
		tryAppend(self.logDir .. "/summary-" .. self.runId .. ".json", line)
	end

	return summary
end

return TestLogger
