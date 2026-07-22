-- TestEZ bootstrap runner for Harbor Heist.
-- Discovers and runs all *.spec ModuleScripts under ServerScriptService.Tests.
--
-- TestEZ v0.4.2 — pinned at commit 6c424186fde426c53541c0c848aa76f2da2bc22c
-- Source: github.com/Roblox/testez (archived Sep 2024, Apache 2.0 license)
-- Vendored at Packages/TestEZ/ — see Packages/TestEZ/LICENSE for full text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestEZ = require(ReplicatedStorage:WaitForChild("TestEZ"))

local tests = ServerScriptService:WaitForChild("Tests")

local results = TestEZ.TestBootstrap:run({ tests }, TestEZ.Reporters.TextReporter)

print(string.format("Harbor Heist tests: %d passed, %d failed, %d skipped",
	results.successCount, results.failureCount, results.skippedCount))

if results.failureCount > 0 then
	error(string.format("Test run failed: %d test(s) failed", results.failureCount), 0)
end
