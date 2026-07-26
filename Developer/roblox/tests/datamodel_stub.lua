-- Datamodel TestEZ stub for run-in-roblox: runs the suite in the PLUGIN
-- context. REQUIRED because several specs (FishingService.spec,
-- RaidServiceOutcome.spec) read ModuleScript.Source for static source
-- guards, and Script.Source needs PluginOrOpenCloud capability — available
-- in the plugin VM, NOT in the run-mode server VM. Running TestEZ from a
-- server bootstrap loses those specs (and silently drops whole spec files
-- on planning errors).
--
-- Usage: run-in-roblox --place HarborHeist_tests.rbxlx --script tests/datamodel_stub.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestEZ = require(ReplicatedStorage:WaitForChild("TestEZ"))
local tests = ServerScriptService:WaitForChild("Tests")

local results = TestEZ.TestBootstrap:run({ tests }, TestEZ.Reporters.TextReporter)

print(string.format(
	"Harbor Heist tests: %d passed, %d failed, %d skipped",
	results.successCount,
	results.failureCount,
	results.skippedCount
))

if #results.errors > 0 then
	print(("Errors reported by TestEZ (%d):"):format(#results.errors))
	for _, err in ipairs(results.errors) do
		print(err)
	end
end
