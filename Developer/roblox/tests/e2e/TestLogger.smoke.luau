-- Smoke test for TestLogger.lua (lune-compatible)
local TestLogger = require("./TestLogger")

local logger = TestLogger.new({
	runId = "smoke-run",
	logDir = "testlogs",
	getState = function()
		return { coins = 123, carried = { "fish1", "fish2" } }
	end,
})

logger:startScenario("login", "Player joins and loads state")
logger:step("join", "Simulate player added")
logger:assertEq("player has default cash", 50, 50)
logger:assertTrue("state snapshot returned", true)
logger:assertNear("near check", 1.0, 1.00001, 0.001)

logger:step("remote", "Simulate remote call")
local result = logger:wrapRemote("GetState", function()
	return { ok = true, cash = 50 }
end)

logger:step("perf", "Simulate timed flow")
logger:timeIt("short delay", function()
	local x = 0
	for i = 1, 1000 do
		x += i
	end
	return x
end)

logger:log("INFO", "Custom log message", { custom = "data" })

logger:finish()

logger:startScenario("negative", "Intentional failure to test dump")
logger:step("fail", "This assertion fails")
logger:assertEq("bad value", 1, 2)
logger:finish()

local summary = logger:summary()

-- Validate summary
assert(summary.totalScenarios == 2, "expected 2 scenarios")
assert(summary.passedScenarios == 1, "expected 1 passed")
assert(summary.failedScenarios == 1, "expected 1 failed")
assert(summary.totalAsserts >= 4, "expected at least 4 asserts")
assert(summary.totalFailures == 1, "expected 1 failure")

print("SMOKE TEST PASSED")
