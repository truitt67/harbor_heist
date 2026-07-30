--[[
	E2E bootstrap runner for Harbor Heist (TASK 19.2+, pe9a).

	Mapped ONLY in test.project.json -> ServerScriptService.RunE2E. Refuses to
	load in a production place (TestFlag absent). Builds the harness (TestLogger
	+ the real test Player + real Remotes) and runs every scenario module under
	ServerScriptService.E2ETests.scenarios, then prints a summary and exits
	non-zero on any failure so run-in-roblox propagates exit 1.

	Invoke:  scripts/run_e2e.sh ServerScriptService.RunE2E
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Safety guard: refuse to run in a production place (same pattern as
-- test/bootstrap.server.lua). TestFlag exists only in test.project.json.
local testFlag = ReplicatedStorage:FindFirstChild("TestFlag")
if not testFlag then
	warn("[HarborHeist] E2E bootstrap loaded in a NON-TEST place — refusing to run.")
	return
end
require(testFlag)

if not RunService:IsStudio() then
	warn("[HarborHeist] E2E bootstrap outside Studio — proceeding (headless runner).")
end

local e2eFolder = ServerScriptService:WaitForChild("E2ETests", 15)
assert(e2eFolder, "ServerScriptService.E2ETests missing — test place mapping broken")
local TestLogger = require(e2eFolder:WaitForChild("TestLogger"))
local scenariosFolder = e2eFolder:WaitForChild("scenarios")

-- run id shared with the file sink naming (matches run_e2e.sh's RUN_ID format).
local runId = os.date("!%Y%m%dT%H%M%SZ", os.time())

-- The real test player is the first (only) Studio player. onPlayerAdded in
-- init.server.lua runs its full yieldy load; wait until a session exists via
-- the scenario itself (it polls). Here we only need the Player object.
local player = Players:GetPlayers()[1]
if not player then
	player = Players.PlayerAdded:Wait()
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)

local logger = TestLogger.new({ runId = runId, logDir = "testlogs" })

local harness = {
	logger = logger,
	player = player,
	remotes = remotes,
}

print(("[E2E] run id %s — running scenarios under %s"):format(runId, scenariosFolder:GetFullName()))

local failures = 0
for _, module in ipairs(scenariosFolder:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, err = pcall(function()
			local scenario = require(module)
			assert(type(scenario.run) == "function", module.Name .. " has no run(harness)")
			scenario.run(harness)
		end)
		if not ok then
			failures += 1
			logger:log("ERROR", "scenario crashed: " .. module.Name, { error = tostring(err) })
		end
	end
end

local summary = logger:summary()
print(("[E2E] complete: %d/%d scenarios passed, %d asserts, %d failures"):format(
	summary.passedScenarios, summary.totalScenarios, summary.totalAsserts, summary.totalFailures))

if failures > 0 or summary.totalFailures > 0 then
	error(("[E2E] FAILED: %d scenario crash(es), %d assert failure(s)"):format(failures, summary.totalFailures), 0)
end
