--[[
	LockDefense.lua — E2E scenario: lock/defense flow (activate, cooldown,
	free uses, expiry). TASK 19.7, migrated to the modular scenario
	architecture under EPIC 43 (tbvq).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, scenario place built from e2e_scenarios.project.json). NO stubs of
	game code — only the Players are table-fakes (services only need
	UserId/Name/DisplayName/Parent). Every step is logged through TestLogger
	(JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }.

	What this verifies (through the REAL AquariumService lock handler,
	exposed as _G.HARBORHEIST_TEST.aquariumActivateLock):
	  Player A — basic activate (base 60s duration, 120s cooldown chained,
	    free use 3->2, lockGeneration 1, epoch mirror persisted to
	    profile.Aquarium.LockUntilTimestamp); already_locked gate (clean
	    return, asserted directly); cooldown gate (notify throws on fake
	    players AFTER/without mutating — verified by UNCHANGED state);
	    re-activate after both timers expire (generation 2).
	  Player B — free-use exhaustion: 3 activations burn LockFreeUsesMax,
	    the 4th still locks but cooldown DOUBLES (soft gate); Lock I tier
	    scaling (90s duration, 90s cooldown tier-scaled then doubled to 180
	    while exhausted); lockGeneration counts all 5 activations.

	Preserved verbatim from runner.server.lua 19.7: timer fields are
	session-local os.clock() values; epoch mirrors persist to the profile.
	Base config: duration 60s / cooldown 120s; Lock I: 90s / 90s.
	Rate-limit budget note: "lock" is 5 calls/10s per player -> two players.

	NOTE: like 19.5, the original 19.7 treats a missing activateLock seam
	as a hard FAILURE (not an informational skip) — preserved.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LockDefense = {}

-- Pull the already-wired services so assertions read the SAME module
-- instances the game wired (no re-require drift).
local function getServices()
	local harbor = ServerScriptService:WaitForChild("HarborHeist", 10)
	assert(harbor, "ServerScriptService.HarborHeist missing — game did not boot")
	return {
		DataManager = require(harbor:WaitForChild("DataManager")),
	}
end

local function resetLockTimers(s)
	s.lockedUntil = 0
	s.lockCooldownUntil = 0
end

function LockDefense.run(harness)
	local logger = harness.logger

	logger:startScenario("lock_defense", "activate, already_locked/cooldown gates, free-use exhaustion doubling, Lock I scaling")

	local svc = getServices()
	local DataManager = svc.DataManager
	local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

	local testBridge = _G.HARBORHEIST_TEST
	local activateLock = testBridge and testBridge.aquariumActivateLock
	-- Original 19.7 semantics: missing seam is a hard failure, not a skip.
	logger:assertTrue("activateLock test seam available", activateLock ~= nil)

	-- Base config (no Lock upgrade): duration 60s, cooldown 120s.
	-- Lock I tier: duration 90s, cooldown 90s.
	local BASE_DURATION = GameConfig.Aquarium.lockDuration
	local BASE_COOLDOWN = GameConfig.Aquarium.lockCooldown
	local LOCK1 = GameConfig.Upgrades.Lock[1]

	if activateLock then
		-- ----------------------------------------------------------
		-- STEP 1: Player A — activate / already_locked / cooldown /
		-- re-activate
		-- ----------------------------------------------------------
		logger:step("lock_a", "basic activate, gates, re-activate")
		local lockA = {
			UserId = 777888999,
			Name = "E2ELockA",
			DisplayName = "E2ELockA",
			Parent = Players,
			Character = nil,
		}
		local sessionA = DataManager.load(lockA)
		logger:assertTrue("lockA session created", sessionA ~= nil)
		if sessionA then
			local defenseA = sessionA.profile.Defense
			logger:assertTrue("Defense exists after load (sanitize contract)", defenseA ~= nil)
			logger:assertEq("free uses start at max", GameConfig.Defense.LockFreeUsesMax, defenseA.LockFreeUsesRemaining)
			logger:assertEq("not locked initially", 0, sessionA.lockedUntil or 0)

			-- Activate #1 (success)
			pcall(activateLock, lockA)
			logger:assertTrue("lock engaged (lockedUntil in future)", (sessionA.lockedUntil or 0) > os.clock())
			local durA = sessionA.lockedUntil - os.clock()
			logger:assertTrue("base duration ~60s", durA > BASE_DURATION - 5 and durA <= BASE_DURATION + 1)
			logger:assertEq("free use consumed (3->2)", GameConfig.Defense.LockFreeUsesMax - 1, defenseA.LockFreeUsesRemaining)
			logger:assertEq("cooldown chained after lock", BASE_COOLDOWN, sessionA.lockCooldownUntil - sessionA.lockedUntil)
			logger:assertEq("lockGeneration incremented", 1, sessionA.lockGeneration)
			logger:assertTrue("epoch mirror persisted", (sessionA.profile.Aquarium.LockUntilTimestamp or 0) > os.time())

			-- Activate while locked -> already_locked (clean return, no notify)
			local okAL, resAL = pcall(activateLock, lockA)
			logger:assertTrue("already_locked: handler did not throw", okAL)
			logger:assertEq("already_locked: reason", "already_locked", resAL and resAL.reason)
			logger:assertEq("already_locked: free uses unchanged", GameConfig.Defense.LockFreeUsesMax - 1, defenseA.LockFreeUsesRemaining)

			-- Expire the lock but not the cooldown -> cooldown gate
			sessionA.lockedUntil = 0
			pcall(activateLock, lockA) -- notify throws; state must be untouched
			logger:assertEq("cooldown: lock not re-engaged", 0, sessionA.lockedUntil)
			logger:assertEq("cooldown: free uses unchanged", GameConfig.Defense.LockFreeUsesMax - 1, defenseA.LockFreeUsesRemaining)
			logger:assertEq("cooldown: generation unchanged", 1, sessionA.lockGeneration)

			-- Expire both -> activate #2 succeeds
			resetLockTimers(sessionA)
			pcall(activateLock, lockA)
			logger:assertTrue("re-lock after cooldown", (sessionA.lockedUntil or 0) > os.clock())
			logger:assertEq("second free use consumed (2->1)", GameConfig.Defense.LockFreeUsesMax - 2, defenseA.LockFreeUsesRemaining)
			logger:assertEq("generation incremented again", 2, sessionA.lockGeneration)
		end
		DataManager.remove(lockA)

		-- ----------------------------------------------------------
		-- STEP 2: Player B — free-use exhaustion (2x cooldown) +
		-- Lock I tier scaling
		-- ----------------------------------------------------------
		logger:step("lock_b", "exhaustion doubling + Lock I tier scaling")
		local lockB = {
			UserId = 888999000,
			Name = "E2ELockB",
			DisplayName = "E2ELockB",
			Parent = Players,
			Character = nil,
		}
		local sessionB = DataManager.load(lockB)
		logger:assertTrue("lockB session created", sessionB ~= nil)
		if sessionB then
			local defenseB = sessionB.profile.Defense

			-- Burn all 3 free uses (reset timers between activations)
			pcall(activateLock, lockB)
			logger:assertEq("B free use 1 consumed", 2, defenseB.LockFreeUsesRemaining)
			resetLockTimers(sessionB)
			pcall(activateLock, lockB)
			logger:assertEq("B free use 2 consumed", 1, defenseB.LockFreeUsesRemaining)
			resetLockTimers(sessionB)
			pcall(activateLock, lockB)
			logger:assertEq("B free use 3 consumed (exhausted)", 0, defenseB.LockFreeUsesRemaining)
			resetLockTimers(sessionB)

			-- 4th activation: still allowed but cooldown DOUBLES (soft gate)
			pcall(activateLock, lockB)
			logger:assertTrue("B lock still works with 0 free uses", (sessionB.lockedUntil or 0) > os.clock())
			logger:assertEq("B exhausted: cooldown doubled", BASE_COOLDOWN * 2, sessionB.lockCooldownUntil - sessionB.lockedUntil)
			logger:assertEq("B free uses stay 0", 0, defenseB.LockFreeUsesRemaining)
			resetLockTimers(sessionB)

			-- Lock I tier: duration 90 (not base 60); cooldown 90 but doubled
			-- to 180 because free uses are still exhausted.
			sessionB.profile.Aquarium.LockLevel = 1
			pcall(activateLock, lockB)
			local durB = sessionB.lockedUntil - os.clock()
			logger:assertTrue("B Lock I duration ~90s", durB > LOCK1.lockDuration - 5 and durB <= LOCK1.lockDuration + 1)
			logger:assertEq("B Lock I cooldown tier-scaled + doubled", LOCK1.lockCooldown * 2, sessionB.lockCooldownUntil - sessionB.lockedUntil)
			logger:assertEq("B generation counted all activations", 5, sessionB.lockGeneration)
		end
		DataManager.remove(lockB)
	end

	logger:finish()
end

return LockDefense
