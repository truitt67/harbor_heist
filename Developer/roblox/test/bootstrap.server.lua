-- TestEZ bootstrap runner for Harbor Heist.
-- Discovers and runs all *.spec ModuleScripts under ServerScriptService.Tests.
--
-- TestEZ v0.4.2 — pinned at commit 6c424186fde426c53541c0c848aa76f2da2bc22c
-- Source: github.com/Roblox/testez (archived Sep 2024, Apache 2.0 license)
-- Vendored at Packages/TestEZ/ — see Packages/TestEZ/LICENSE for full text.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Safety guard: refuse to run in a production place.
-- The TestFlag module is only mapped in test.project.json, not
-- default.project.json, so its absence means we're in production.
local testFlag = ReplicatedStorage:FindFirstChild("TestFlag")
if not testFlag then
	warn("[HarborHeist] Test bootstrap loaded in a NON-TEST place — refusing to run.")
	warn("TestFlag module is absent (production build or misconfigured project).")
	return
end
require(testFlag) -- returns true — confirms test build

if not RunService:IsStudio() then
	warn("[HarborHeist] Test bootstrap loaded outside Studio — proceeding anyway.")
	warn("Expected when running via run-in-roblox or similar headless runner.")
end

local TestEZ = require(ReplicatedStorage:WaitForChild("TestEZ"))

local tests = ServerScriptService:WaitForChild("Tests")

local results = TestEZ.TestBootstrap:run({ tests }, TestEZ.Reporters.TextReporter)

print(string.format("Harbor Heist tests: %d passed, %d failed, %d skipped",
	results.successCount, results.failureCount, results.skippedCount))

if results.failureCount > 0 then
	error(string.format("Test run failed: %d test(s) failed", results.failureCount), 0)
end
