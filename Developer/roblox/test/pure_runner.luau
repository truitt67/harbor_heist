-- pure_runner.luau — Lune-compatible test runner for pure-Luau modules.
--
-- This runner provides a minimal describe/it/expect test framework that
-- mirrors TestEZ's API surface, so spec files use the same patterns in
-- both environments. Specs for the pure bucket live in test/pure_specs/
-- and use lune filesystem require() paths (not game:GetService).
--
-- Pure bucket modules (no Roblox globals at top level):
--   src/server/AntiExploitService.lua
--   src/server/OnboardingService.lua
--   src/server/AuditLogService.lua
--
-- Run: scripts/run_tests.sh --pure
-- Or:  lune run test/pure_runner

-- =========================================================================
-- Minimal test framework (describe/it/expect)
-- =========================================================================

local _results = {
	passCount = 0,
	failCount = 0,
	skipCount = 0,
	failures = {},
}

local _currentDescribe = ""
local _skipAll = false

local function _expect(value)
	-- Build the assertion API with a negation flag. Two separate "to" tables
	-- (positive and negative) are created so expect(x).never.to.equal(y) works
	-- through table indexing — no metatables needed.

	local function makeTo(negated)
		local be = {}

		function be.a(typeName)
			local vt = typeof(value)
			if negated then
				if vt == typeName then
					error(string.format("Expected %s to NOT be a %s", tostring(value), typeName), 2)
				end
			else
				if vt ~= typeName then
					error(string.format("Expected %s to be a %s, got %s", tostring(value), typeName, vt), 2)
				end
			end
		end

		function be.ok()
			if negated then
				if value then
					error(string.format("Expected %s to NOT be ok (truthy)", tostring(value)), 2)
				end
			else
				if not value then
					error(string.format("Expected %s to be ok (truthy), got falsy", tostring(value)), 2)
				end
			end
		end

		local to = {}

		function to.equal(expected)
			if negated then
				if value == expected then
					error(string.format("Expected %s to NOT equal %s", tostring(value), tostring(expected)), 2)
				end
			else
				if value ~= expected then
					error(string.format("Expected %s to equal %s, got %s", tostring(expected), tostring(expected), tostring(value)), 2)
				end
			end
		end

		to.be = {
			a = be.a,
			ok = be.ok,
		}

		function to.throw()
			local fn = value
			if typeof(fn) ~= "function" then
				error("expect(fn).to.throw() requires a function", 2)
			end
			local ok = pcall(fn)
			if negated then
				if ok then
					error("Expected function to NOT throw, but it did not throw", 2)
				end
			else
				if not ok then
					error("Expected function to throw, but it did not", 2)
				end
			end
		end

		return to
	end

	return {
		to = makeTo(false),
		never = { to = makeTo(true) },
	}
end

-- Test framework functions (passed to spec files as arguments)
local describe = function(name, fn)
	_currentDescribe = name
	local ok, err = pcall(fn)
	if not ok then
		-- A describe-level failure (e.g. require error) is a test failure
		table.insert(_results.failures, string.format("DESCRIBE '%s': %s", name, tostring(err)))
		_results.failCount = _results.failCount + 1
	end
	_currentDescribe = ""
end

local it = function(name, fn)
	if _skipAll then
		_results.skipCount = _results.skipCount + 1
		return
	end
	local ok, err = pcall(fn)
	if ok then
		_results.passCount = _results.passCount + 1
	else
		table.insert(_results.failures, string.format("[%s] %s: %s", _currentDescribe, name, tostring(err)))
		_results.failCount = _results.failCount + 1
	end
end

local expect = _expect
local beforeEach = function(_fn) end
local afterEach = function(_fn) end

-- =========================================================================
-- Spec discovery
-- =========================================================================

local fs = require("@lune/fs")
local process = require("@lune/process")

-- SPECS_DIR is CWD-relative (we run from project root via scripts/run_tests.sh).
-- require() paths are resolved relative to this file's location (test/), so
-- we must convert CWD-relative paths to runner-relative paths before requiring.
local SPECS_DIR_CWD = "./test/pure_specs"
local specFiles = {}

-- Recursively scan a directory for .spec.lua / .spec.luau files.
-- fs.readDir is not recursive, so we walk subdirectories manually.
local function findSpecs(dirPath)
	local ok, entries = pcall(fs.readDir, dirPath)
	if not ok or typeof(entries) ~= "table" then
		return
	end
	for _, name in ipairs(entries) do
		local fullPath = dirPath .. "/" .. name
		-- fs.isDir tells us whether to recurse or check the file extension
		local isDir = fs.isDir(fullPath)
		if isDir then
			findSpecs(fullPath)
		else
			if name:match("%.spec%.lua$") or name:match("%.spec%.luau$") then
				table.insert(specFiles, fullPath)
			end
		end
	end
end

findSpecs(SPECS_DIR_CWD)
table.sort(specFiles)

-- Convert a CWD-relative file path to a require path relative to this runner.
-- This runner lives at test/pure_runner.luau, so paths under test/ have the
-- "test/" component stripped and "./" prepended.
-- lune appends .lua/.luau to require paths, so we keep the .spec part:
--   "./test/pure_specs/Smoke.spec.lua" → "./pure_specs/Smoke.spec"
local function toRequirePath(cwdPath)
	local stripped = cwdPath:gsub("^%./", ""):gsub("^test/", "")
	stripped = stripped:gsub("%.lua$", ""):gsub("%.luau$", "")
	return "./" .. stripped
end

-- =========================================================================
-- Run specs
-- =========================================================================

if #specFiles == 0 then
	print("No spec files found in " .. SPECS_DIR .. "/")
	print("Create .spec.lua files there to add pure-bucket tests.")
	print("")
	print("Pure-bucket modules (testable without Roblox Studio):")
	print("  - src/server/AntiExploitService.lua")
	print("  - src/server/OnboardingService.lua")
	print("  - src/server/AuditLogService.lua")
	print("")
	print("Result: 0 passed, 0 failed, 0 skipped (no specs found)")
	process.exit(0)
end

print("Running " .. #specFiles .. " spec file(s)")
print(string.rep("=", 60))

for _, specPath in ipairs(specFiles) do
	-- Convert CWD-relative path to runner-relative require path
	local requirePath = toRequirePath(specPath)

	-- Spec files return a function that calls describe/it/expect
	local ok, specFn = pcall(require, requirePath)
	if not ok then
		print(string.format("FAIL: Failed to load %s: %s", specPath, tostring(specFn)))
		_results.failCount = _results.failCount + 1
		table.insert(_results.failures, string.format("LOAD ERROR: %s: %s", specPath, tostring(specFn)))
	else
		print("Running: " .. specPath)
		if typeof(specFn) == "function" then
			local runOk, runErr = pcall(specFn, describe, it, expect, beforeEach, afterEach)
			if not runOk then
				print(string.format("FAIL: Error running %s: %s", specPath, tostring(runErr)))
				_results.failCount = _results.failCount + 1
				table.insert(_results.failures, string.format("RUN ERROR: %s: %s", specPath, tostring(runErr)))
			end
		end
	end
end

-- =========================================================================
-- Report results
-- =========================================================================

print(string.rep("=", 60))
print("")

if #_results.failures > 0 then
	print("FAILURES:")
	for _, fail in ipairs(_results.failures) do
		print("  " .. fail)
	end
	print("")
end

print(string.format("Result: %d passed, %d failed, %d skipped",
	_results.passCount, _results.failCount, _results.skipCount))

if _results.failCount > 0 then
	process.exit(1)
else
	process.exit(0)
end