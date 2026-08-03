-- E2E Runner — server-side E2E tests for Harbor Heist.
-- Runs as a SERVER SCRIPT in a place booted via RunService:Run().
--
-- Architecture: the server VM boots (init.server.lua), building the real
-- world, docks, remotes, and all services. This script then exercises the
-- REAL service APIs directly (DataManager.load, DockManager.claim, etc.)
-- against a table-fake player (same pattern as the datamodel TestEZ specs),
-- verifying real service behavior end-to-end through the actual DataModel.
--
-- What this verifies that the pure/datanode specs can't:
--   - Real WorldBuilder output (docks exist in workspace)
--   - Real DockManager.buildAll + claim against actual Part instances
--   - Real service init ordering (all 17 services boot without error)
--   - Real AquariumService income loop (task.spawn from real init)
--   - Real RaidService scheduler boot
--   - Full service interconnection via the production deps table
--
-- Usage: run-in-roblox --place HarborHeist_e2e.rbxlx --script <stub>

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- Results tracking
-- ============================================================
local PASS = 0
local FAIL = 0
local function report(name, passed, detail)
	local status = passed and "PASS" or "FAIL"
	local line = string.format("[E2E] %s: %s", status, name)
	if detail then
		line = line .. " — " .. tostring(detail)
	end
	print(line)
	if passed then PASS += 1 else FAIL += 1 end
end

local function assertEq(name, expected, actual)
	if expected == actual then
		report(name, true)
	else
		report(name, false, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
	end
end

local function assertTrue(name, value)
	report(name, not not value)
end

-- ============================================================
-- Wait for server boot to complete
-- ============================================================
print("[E2E] waiting for server boot...")

local deadline = os.clock() + 30
repeat
	task.wait(0.5)
until workspace:FindFirstChild("HarborWorld") or os.clock() > deadline

local harborWorld = workspace:FindFirstChild("HarborWorld")
local remotes = ReplicatedStorage:FindFirstChild("Remotes")

if not harborWorld or not remotes then
	print("[E2E] FATAL: server did not boot within 30s")
	return
end

task.wait(1) -- settle for service init completion
print("[E2E] server booted — HarborWorld + Remotes present")

-- ============================================================
-- Access the real initialized services
-- ============================================================
local hh = ServerScriptService:FindFirstChild("HarborHeist")
if not hh then
	print("[E2E] FATAL: HarborHeist service container not found")
	return
end

local DataManager = require(hh:WaitForChild("DataManager"))
local DockManager = require(hh:WaitForChild("DockManager"))
local StateSync = require(hh:WaitForChild("StateSync"))
local AquariumService = require(hh:WaitForChild("AquariumService"))
local RaidService = require(hh:WaitForChild("RaidService"))
local AntiExploitService = require(hh:WaitForChild("AntiExploitService"))
local PlayerProfile = require(ReplicatedStorage.Shared:WaitForChild("PlayerProfile"))
local GameConfig = require(ReplicatedStorage.Shared:WaitForChild("GameConfig"))
-- Hoisted from the migrated 19.4 section (EPIC 43, 8hnx): 19.6/19.7/19.8
-- build fish records and previously relied on 19.4's chunk-local require.
local FishInstance = require(ReplicatedStorage.Shared:WaitForChild("FishInstance"))

print("[E2E] services acquired")

-- ============================================================
-- Verify server boot integrity
-- ============================================================
print("[E2E 19.2] === Player Lifecycle ===")

-- Boot verification: real world built with docks
local dockCount = 0
for _, child in ipairs(harborWorld:GetChildren()) do
	if child.Name:match("^Dock") then
		dockCount += 1
	end
end
assertTrue("19.2 world has docks", dockCount > 0)
print("[E2E 19.2] dock count = " .. dockCount)

-- Remotes present (real init.server created them)
local eventCount, funcCount = 0, 0
for _, child in ipairs(remotes:GetChildren()) do
	if child:IsA("RemoteEvent") then eventCount += 1
	elseif child:IsA("RemoteFunction") then funcCount += 1 end
end
assertTrue("19.2 remotes built (11 events)", eventCount >= 11)
assertTrue("19.2 remotes built (17 functions)", funcCount >= 17)
print(string.format("[E2E 19.2] remotes: %d events, %d functions", eventCount, funcCount))

-- ============================================================
-- Player lifecycle using a fake player + real service APIs
-- ============================================================
-- We can't create a real Player Instance from server scripts started via
-- plugin Run() (CreateLocalPlayer needs LocalUser capability). But the
-- services only need a table with UserId/Name/DisplayName/Parent for their
-- player reference. We test the REAL service behavior (DataManager.load
-- against the real DataStore, DockManager.claim against real dock Parts,
-- StateSync.snapshot against the real profile) using this fake.

local player = {
	UserId = 123456789,
	Name = "E2ETestPlayer",
	DisplayName = "E2ETestPlayer",
	Parent = Players, -- truthy so `if not player.Parent` checks pass
	Character = nil,
}

-- Phase 1: DataManager.load (creates session from DataStore/profile defaults)
print("[E2E 19.2] phase=load")
local session = DataManager.load(player)
assertTrue("19.2 DataManager.load creates session", session ~= nil)

if session then
	-- Profile fields
	assertTrue("19.2 session has profile", session.profile ~= nil)
	assertTrue("19.2 session.player is our fake", session.player == player)

	-- New player defaults
	local profile = session.profile
	assertEq("19.2 profile.Coins == 0 (starting cash is 0)", 0, profile.Coins)
	print("[E2E 19.2] starting coins = " .. tostring(profile.Coins))
	assertEq("19.2 profile.Equipment.EquippedRodLevel == 1", 1, profile.Equipment.EquippedRodLevel)
	assertEq("19.2 profile.Equipment.EquippedBaitLevel == 1", 1, profile.Equipment.EquippedBaitLevel)
	assertEq("19.2 profile.Aquarium.StoredFish is empty", 0, #profile.Aquarium.StoredFish)
	assertEq("19.2 profile.Aquarium.UpgradeLevel == 1", 1, profile.Aquarium.UpgradeLevel)
	assertEq("19.2 profile.Aquarium.UnclaimedIncome == 0", 0, profile.Aquarium.UnclaimedIncome)

	-- Session runtime fields
	assertEq("19.2 session.carried is empty", 0, #session.carried)
	assertTrue("19.2 session.casting == false", session.casting == false)
	assertTrue("19.2 session.dockIndex == nil (not claimed yet)", session.dockIndex == nil)
end

-- Phase 2: DockManager.claim (assigns a real dock with Parts)
print("[E2E 19.2] phase=dock_claim")
local dock = DockManager.claim(player)
assertTrue("19.2 DockManager.claim returns dock", dock ~= nil)
if dock then
	print("[E2E 19.2] claimed dock index = " .. tostring(dock.index))
	assertTrue("19.2 dock has owner", dock.owner == player)
	assertTrue("19.2 dock has aquarium Part", dock.aquarium ~= nil)
	assertTrue("19.2 dock has spawnCFrame", dock.spawnCFrame ~= nil)

	-- Verify sign updated (real GUI text on a real Part)
	local sign = dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
	if sign then
		local label = sign:FindFirstChild("OwnerLabel")
		if label then
			print("[E2E 19.2] dock sign text = " .. tostring(label.Text))
			assertTrue("19.2 dock sign updated with player name", label.Text:match("E2ETest") ~= nil)
		end
	end
end

-- Phase 3: StateSync.snapshot (real profile → real snapshot)
print("[E2E 19.2] phase=snapshot")
local snapshot = StateSync.snapshot(session)
assertTrue("19.2 StateSync.snapshot returns table", snapshot ~= nil)
if snapshot then
	assertEq("19.2 snapshot.cash == 0 (starting)", 0, snapshot.cash or -1)
	assertEq("19.2 snapshot.rodLevel == 1", 1, snapshot.rodLevel)
	assertEq("19.2 snapshot.liveWellCount == 0 (new player)", 0, snapshot.liveWellCount or -1)
	assertEq("19.2 snapshot.carried == 0 (new player)", 0, snapshot.carried or -1)
	assertEq("19.2 snapshot.upgradeLevel == 1", 1, snapshot.upgradeLevel)
	assertTrue("19.2 snapshot.incomePerSec >= 0", (snapshot.incomePerSec or -1) >= 0)
	assertTrue("19.2 snapshot.capacity > 0", (snapshot.capacity or 0) > 0)
	assertTrue("19.2 snapshot.onboarding is table", type(snapshot.onboarding) == "table")
	print("[E2E 19.2] snapshot.capacity = " .. tostring(snapshot.capacity))
	print("[E2E 19.2] snapshot.incomePerSec = " .. tostring(snapshot.incomePerSec))
end

-- Phase 4: Save (DataStore write, real DataStore v2 in Studio)
print("[E2E 19.2] phase=save")
local saveOk, saveErr = pcall(function()
	DataManager.save(player)
end)
assertTrue("19.2 DataManager.save succeeds", saveOk)
if not saveOk then
	print("[E2E 19.2] save error: " .. tostring(saveErr))
end

-- Phase 5: Reload (verify save → load round-trip)
print("[E2E 19.2] phase=reload")
-- Remove session first so load doesn't return the cached one
DataManager.remove(player)
task.wait(0.5)
local session2 = DataManager.load(player)
assertTrue("19.2 reload creates session", session2 ~= nil)
if session2 then
	-- Should have same coins (was saved)
	assertEq("19.2 reload profile.Coins matches saved", session.profile.Coins, session2.profile.Coins)
	print("[E2E 19.2] reloaded coins = " .. tostring(session2.profile.Coins))
end

-- Phase 6: Dock release (cleanup)
print("[E2E 19.2] phase=dock_release")
DockManager.release(player)
if dock then
	assertTrue("19.2 dock released (owner nil)", dock.owner == nil)
	local sign = dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
	if sign then
		local label = sign:FindFirstChild("OwnerLabel")
		if label then
			print("[E2E 19.2] dock sign after release = " .. tostring(label.Text))
			assertTrue("19.2 dock sign reset", not label.Text:match("E2ETest"))
		end
	end
end

-- Phase 7: Cleanup
DataManager.remove(player)

-- TASK 19.3 (Fishing Loop) MIGRATED to tests/e2e/scenarios/Fishing.lua (EPIC 43, c4fs)

-- TASK 19.4 (Aquarium Economy) MIGRATED to tests/e2e/scenarios/Aquarium.lua (EPIC 43, 8hnx)

-- TASK 19.5 (Shop Purchases) MIGRATED to tests/e2e/scenarios/Shop.lua (EPIC 43, 7dho)

-- TASK 19.6 (Persistence & Migration) MIGRATED to tests/e2e/scenarios/Persistence.lua (EPIC 43, z9mz)

-- ============================================================
-- TASK 19.7: Lock/Defense flow (activate, cooldown, free uses, expiry)
-- ============================================================
print("[E2E 19.7] === Lock/Defense Flow ===")

local activateLock = _G.HARBORHEIST_TEST and _G.HARBORHEIST_TEST.aquariumActivateLock
assertTrue("19.7 activateLock test seam available", activateLock ~= nil)

-- Base config (no Lock upgrade): duration 60s, cooldown 120s.
-- Lock I tier: duration 90s, cooldown 90s.
-- Free uses: LockFreeUsesMax (3) per session; exhausted -> cooldown DOUBLES
-- (soft gate). Timer fields are session-local os.clock() values; epoch
-- mirrors persist to profile.Aquarium.LockUntilTimestamp etc.
-- Success + cooldown paths call remotes.notify (throws on fake players)
-- AFTER/without mutating — verify via state; already_locked returns before
-- notify so its return table is asserted directly.
-- Rate-limit budget: "lock" is 5 calls/10s per player -> two players.

local BASE_DURATION = GameConfig.Aquarium.lockDuration
local BASE_COOLDOWN = GameConfig.Aquarium.lockCooldown
local LOCK1 = GameConfig.Upgrades.Lock[1]

local function resetLockTimers(s)
	s.lockedUntil = 0
	s.lockCooldownUntil = 0
end

if activateLock then
	-- ---- Player A: basic activate / already_locked / cooldown / re-activate
	local lockA = {
		UserId = 777888999,
		Name = "E2ELockA",
		DisplayName = "E2ELockA",
		Parent = Players,
		Character = nil,
	}
	local sessionA = DataManager.load(lockA)
	assertTrue("19.7 lockA session created", sessionA ~= nil)
	if sessionA then
		local defenseA = sessionA.profile.Defense
		assertTrue("19.7 Defense exists after load (sanitize contract)", defenseA ~= nil)
		assertEq("19.7 free uses start at max", GameConfig.Defense.LockFreeUsesMax, defenseA.LockFreeUsesRemaining)
		assertEq("19.7 not locked initially", 0, sessionA.lockedUntil or 0)

		-- Activate #1 (success)
		pcall(activateLock, lockA)
		assertTrue("19.7 lock engaged (lockedUntil in future)", (sessionA.lockedUntil or 0) > os.clock())
		local durA = sessionA.lockedUntil - os.clock()
		assertTrue("19.7 base duration ~60s", durA > BASE_DURATION - 5 and durA <= BASE_DURATION + 1)
		assertEq("19.7 free use consumed (3->2)", GameConfig.Defense.LockFreeUsesMax - 1, defenseA.LockFreeUsesRemaining)
		assertEq("19.7 cooldown chained after lock", BASE_COOLDOWN, sessionA.lockCooldownUntil - sessionA.lockedUntil)
		assertEq("19.7 lockGeneration incremented", 1, sessionA.lockGeneration)
		assertTrue("19.7 epoch mirror persisted", (sessionA.profile.Aquarium.LockUntilTimestamp or 0) > os.time())

		-- Activate while locked -> already_locked (clean return, no notify)
		local okAL, resAL = pcall(activateLock, lockA)
		assertTrue("19.7 already_locked: handler did not throw", okAL)
		assertEq("19.7 already_locked: reason", "already_locked", resAL and resAL.reason)
		assertEq("19.7 already_locked: free uses unchanged", GameConfig.Defense.LockFreeUsesMax - 1, defenseA.LockFreeUsesRemaining)

		-- Expire the lock but not the cooldown -> cooldown gate
		sessionA.lockedUntil = 0
		pcall(activateLock, lockA) -- notify throws; state must be untouched
		assertEq("19.7 cooldown: lock not re-engaged", 0, sessionA.lockedUntil)
		assertEq("19.7 cooldown: free uses unchanged", GameConfig.Defense.LockFreeUsesMax - 1, defenseA.LockFreeUsesRemaining)
		assertEq("19.7 cooldown: generation unchanged", 1, sessionA.lockGeneration)

		-- Expire both -> activate #2 succeeds
		resetLockTimers(sessionA)
		pcall(activateLock, lockA)
		assertTrue("19.7 re-lock after cooldown", (sessionA.lockedUntil or 0) > os.clock())
		assertEq("19.7 second free use consumed (2->1)", GameConfig.Defense.LockFreeUsesMax - 2, defenseA.LockFreeUsesRemaining)
		assertEq("19.7 generation incremented again", 2, sessionA.lockGeneration)
	end
	DataManager.remove(lockA)

	-- ---- Player B: free-use exhaustion (2x cooldown) + Lock I tier scaling
	local lockB = {
		UserId = 888999000,
		Name = "E2ELockB",
		DisplayName = "E2ELockB",
		Parent = Players,
		Character = nil,
	}
	local sessionB = DataManager.load(lockB)
	assertTrue("19.7 lockB session created", sessionB ~= nil)
	if sessionB then
		local defenseB = sessionB.profile.Defense

		-- Burn all 3 free uses (reset timers between activations)
		pcall(activateLock, lockB)
		assertEq("19.7B free use 1 consumed", 2, defenseB.LockFreeUsesRemaining)
		resetLockTimers(sessionB)
		pcall(activateLock, lockB)
		assertEq("19.7B free use 2 consumed", 1, defenseB.LockFreeUsesRemaining)
		resetLockTimers(sessionB)
		pcall(activateLock, lockB)
		assertEq("19.7B free use 3 consumed (exhausted)", 0, defenseB.LockFreeUsesRemaining)
		resetLockTimers(sessionB)

		-- 4th activation: still allowed but cooldown DOUBLES (soft gate)
		pcall(activateLock, lockB)
		assertTrue("19.7B lock still works with 0 free uses", (sessionB.lockedUntil or 0) > os.clock())
		assertEq("19.7B exhausted: cooldown doubled", BASE_COOLDOWN * 2, sessionB.lockCooldownUntil - sessionB.lockedUntil)
		assertEq("19.7B free uses stay 0", 0, defenseB.LockFreeUsesRemaining)
		resetLockTimers(sessionB)

		-- Lock I tier: duration 90 (not base 60); cooldown 90 but doubled to
		-- 180 because free uses are still exhausted.
		sessionB.profile.Aquarium.LockLevel = 1
		pcall(activateLock, lockB)
		local durB = sessionB.lockedUntil - os.clock()
		assertTrue("19.7B Lock I duration ~90s", durB > LOCK1.lockDuration - 5 and durB <= LOCK1.lockDuration + 1)
		assertEq("19.7B Lock I cooldown tier-scaled + doubled", LOCK1.lockCooldown * 2, sessionB.lockCooldownUntil - sessionB.lockedUntil)
		assertEq("19.7B generation counted all activations", 5, sessionB.lockGeneration)
	end
	DataManager.remove(lockB)
end

-- ============================================================
-- TASK 19.8.1: Raid system (automated single-player)
-- ============================================================
print("[E2E 19.8] === Raid System ===")

-- Two fake players through the REAL RaidService module functions
-- (requestRaidAttempt / submitRaidResult are public — the remote wrappers
-- only add rate limiting, which is datamodel-spec territory). Victim
-- resolution enumerates getPlayers(), so _setPlayersProvider swaps in our
-- fakes. The raid window is forced via _setWindowOpen (real scheduler waits
-- 20-30min; its first transition is >= 20min after boot so a short test
-- cannot race it). Notify throws on fake players, but always AFTER the
-- mutation it announces — profile/session state is authoritative.
-- The too_fast reason-string path notifies before returning, so it can't be
-- asserted by return value here (datamodel specs cover it); E2E asserts the
-- observable: an instant forged submit transfers nothing and consumes the
-- raid.

local raider = {
	UserId = 111000111,
	Name = "E2ERaider",
	DisplayName = "E2ERaider",
	Parent = Players,
	Character = nil,
}
local raidVictim = {
	UserId = 222000222,
	Name = "E2EVictim",
	DisplayName = "E2EVictim",
	Parent = Players,
	Character = nil,
}
local atkS = DataManager.load(raider)
local vicS = DataManager.load(raidVictim)
assertTrue("19.8 attacker session created", atkS ~= nil)
assertTrue("19.8 victim session created", vicS ~= nil)

if atkS and vicS then
	-- Make both sides raid-legal: an aquarium upgrade bypasses new-player
	-- protection (hasUpgrade), both opt in, victim stocks a stealable fish.
	atkS.profile.Aquarium.UpgradeLevel = 2
	vicS.profile.Aquarium.UpgradeLevel = 2
	atkS.profile.Aquarium.RaidOptIn = true
	vicS.profile.Aquarium.RaidOptIn = true
	table.insert(vicS.profile.Aquarium.StoredFish, FishInstance.new("Tuna", "StarterPier"))

	RaidService._setPlayersProvider(function()
		return { raider, raidVictim }
	end)

	-- Gate: window closed (scheduler's first real window is >= 20min out)
	assertTrue("19.8 window closed before force", not RaidService.isWindowOpen())
	local rClosed = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: window_closed", "window_closed", rClosed and rClosed.reason)

	RaidService._setWindowOpen(true, 300)
	assertTrue("19.8 window forced open", RaidService.isWindowOpen())

	-- Gate: attacker not opted in
	atkS.profile.Aquarium.RaidOptIn = false
	local rNoOpt = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: attacker not_opted_in", "not_opted_in", rNoOpt and rNoOpt.reason)
	atkS.profile.Aquarium.RaidOptIn = true

	-- Gate: victim not opted in
	vicS.profile.Aquarium.RaidOptIn = false
	local rVNoOpt = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: victim not_opted_in", "not_opted_in", rVNoOpt and rVNoOpt.reason)
	vicS.profile.Aquarium.RaidOptIn = true

	-- Gate: victim new-player-protected (downgrade, no catches)
	vicS.profile.Aquarium.UpgradeLevel = 1
	local rNewb = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: victim new_player_protected", "new_player_protected", rNewb and rNewb.reason)
	vicS.profile.Aquarium.UpgradeLevel = 2

	-- Target enumeration: victim listed, available, 1 stealable fish
	local targetsPayload = RaidService.getRaidTargets(raider)
	assertTrue("19.8 getRaidTargets canRaid", targetsPayload and targetsPayload.canRaid == true)
	local targetInfo = nil
	for _, t in ipairs(targetsPayload and targetsPayload.targets or {}) do
		if t.userId == raidVictim.UserId then
			targetInfo = t
			break
		end
	end
	assertTrue("19.8 victim listed as target", targetInfo ~= nil)
	if targetInfo then
		assertTrue("19.8 victim target available", targetInfo.available == true)
		assertEq("19.8 victim stealableCount == 1", 1, targetInfo.stealableCount)
	end

	-- RNG seeding: raid rng call sequence for an attempt is
	--   call 1: challenge center pick (requestRaidAttempt)
	--   call 2: success roll (submitRaidResult)
	--   call 3: steal-weight roll (resolveRaidSuccess)
	-- Seed so call 2 <= threshold (perfect chance 0.85) for the success run,
	-- or > 0.85 for the forged-submit run (even a broken timing gate could
	-- then only "miss", never steal).
	local function seedRaidRng(call2AtMost)
		for seed = 1, 200 do
			local probe = Random.new(seed)
			probe:NextNumber() -- call 1
			local call2 = probe:NextNumber()
			if call2AtMost == nil or call2 <= call2AtMost then
				if call2AtMost ~= nil or call2 > 0.85 then
					RaidService._setRng(Random.new(seed))
					return true
				end
			end
		end
		return false
	end

	-- ===== SUCCESS FLOW =====
	assertTrue("19.8 rng seeded for success", seedRaidRng(0.85))
	local challenge = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertTrue("19.8 attempt accepted", challenge and challenge.ok == true)
	if challenge and challenge.ok then
		assertTrue("19.8 challenge has perfect zone", challenge.perfectStart ~= nil and challenge.perfectStart < challenge.perfectEnd)
		assertTrue("19.8 good zone contains perfect zone",
			challenge.goodStart <= challenge.perfectStart and challenge.goodEnd >= challenge.perfectEnd)
		assertTrue("19.8 attacker cooldown committed at request", atkS.raidAttackLastAt ~= nil)

		-- One raid in flight per attacker
		local rInFlight = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
		assertEq("19.8 re-attempt blocked: raid_in_progress", "raid_in_progress", rInFlight and rInFlight.reason)

		-- TOCTOU design point: the window closing mid-minigame must NOT void
		-- a committed raid (submitRaidResult deliberately skips the window
		-- re-check). Force it closed before submitting.
		RaidService._setWindowOpen(false)

		-- Anti-forgery minimum time: the marker sweeps 0->1 over
		-- durationSeconds, so position p requires p*duration elapsed (-0.5s
		-- grace). Wait it out, then submit at the perfect-zone center.
		local center = (challenge.perfectStart + challenge.perfectEnd) / 2
		local waitNeeded = center * challenge.durationSeconds - 0.5 + 0.3
		if waitNeeded > 0 then
			task.wait(waitNeeded)
		end
		pcall(RaidService.submitRaidResult, raider, center)

		assertEq("19.8 victim fish stolen (1->0)", 0, #vicS.profile.Aquarium.StoredFish)
		assertEq("19.8 attacker received fish (0->1)", 1, #atkS.profile.Aquarium.StoredFish)
		if #atkS.profile.Aquarium.StoredFish > 0 then
			assertEq("19.8 stolen fish is the Tuna", "Tuna", atkS.profile.Aquarium.StoredFish[1].SpeciesId)
		end
		assertTrue("19.8 victim immunity written (raid protection)",
			(vicS.profile.Aquarium.RaidProtectionUntilTimestamp or 0) > os.time())
		assertEq("19.8 attacker RaidsWon == 1", 1, atkS.profile.PvP.RaidsWon)
		assertEq("19.8 victim RaidsLost == 1", 1, vicS.profile.PvP.RaidsLost)
		assertTrue("19.8 victim window loss counted",
			vicS.raidWindowLosses ~= nil and vicS.raidWindowLosses.count == 1)
		print("[E2E 19.8] success: fish transferred despite window closing mid-minigame")
	end

	-- Re-open for the remaining gate tests (new serial for loss-cap keying)
	local serial2 = RaidService._setWindowOpen(true, 300)

	-- Gate: attacker cooldown (committed by the successful raid)
	local rAtkCd = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: attacker_cooldown", "attacker_cooldown", rAtkCd and rAtkCd.reason)
	assertTrue("19.8 attacker cooldownRemaining reported", (rAtkCd and rAtkCd.cooldownRemaining or 0) > 0)

	-- Gate: per-victim cooldown (clear only the attacker-side stamp;
	-- restock + de-immune the victim so eligibility passes first)
	atkS.raidAttackLastAt = nil
	vicS.profile.Aquarium.RaidProtectionUntilTimestamp = 0
	table.insert(vicS.profile.Aquarium.StoredFish, FishInstance.new("Perch", "StarterPier"))
	local rVicCd = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: victim_cooldown", "victim_cooldown", rVicCd and rVicCd.reason)

	-- Gate: raid protection immunity (eligibility check, before victim cd)
	atkS.raidTargetCooldowns = nil
	vicS.profile.Aquarium.RaidProtectionUntilTimestamp = os.time() + 600
	local rProt = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: raid_protection", "raid_protection", rProt and rProt.reason)
	vicS.profile.Aquarium.RaidProtectionUntilTimestamp = 0

	-- Gate: per-window loss cap (2 losses this window)
	vicS.raidWindowLosses = { serial = serial2, count = GameConfig.Raid.maxLossesPerWindow, value = 0 }
	local rCap = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertEq("19.8 gate: loss_capped", "loss_capped", rCap and rCap.reason)
	vicS.raidWindowLosses = nil

	-- Gate: input validation
	local rBadType = RaidService.requestRaidAttempt(raider, "not-a-number")
	assertEq("19.8 gate: bad targetUserId type", "bad_input", rBadType and rBadType.reason)
	local rSelf = RaidService.requestRaidAttempt(raider, raider.UserId)
	assertEq("19.8 gate: self-raid rejected", "target_unavailable", rSelf and rSelf.reason)

	-- ===== FORGED INSTANT SUBMIT (timing anti-forgery) =====
	-- High seed: even if the timing gate were broken, the roll would miss —
	-- so "victim keeps fish" can ONLY mean the forged submit did not steal.
	assertTrue("19.8 rng seeded high for forge test", seedRaidRng(nil))
	local ch2 = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
	assertTrue("19.8 forge-test attempt accepted", ch2 and ch2.ok == true)
	if ch2 and ch2.ok then
		local fishBefore = #vicS.profile.Aquarium.StoredFish
		pcall(RaidService.submitRaidResult, raider, 1.0) -- instant max-position submit
		assertEq("19.8 forged instant submit stole nothing", fishBefore, #vicS.profile.Aquarium.StoredFish)
		-- The raid was consumed (single-resolution) either way
		local resNA = RaidService.submitRaidResult(raider, 0.5)
		assertEq("19.8 raid consumed after forged submit", "no_active_raid", resNA and resNA.reason)
	end

	-- Cleanup
	RaidService._setWindowOpen(false)
	RaidService._setPlayersProvider(nil)
end
DataManager.remove(raider)
DataManager.remove(raidVictim)

-- harborheist-r7an: no_session raid attempt — a player with no loaded
-- session (DataManager.get returns nil) must be rejected cleanly by both
-- requestRaidAttempt and submitRaidResult without crashing or corrupting
-- state. Covers the exploit path where a client tries to raid before their
-- profile has loaded or after it was removed.
local noSessionPlayer = {
	UserId = 444000444,
	Name = "E2ENoSession",
	DisplayName = "E2ENoSession",
	Parent = Players,
	Character = nil,
}
assertTrue("19.8 no_session: player has no DataManager session",
	DataManager.get(noSessionPlayer) == nil)

local rNoSess = RaidService.requestRaidAttempt(noSessionPlayer, 222000222)
assertEq("19.8 no_session: requestRaidAttempt rejected",
	"no_session", rNoSess and rNoSess.reason)

local sNoSess = RaidService.submitRaidResult(noSessionPlayer, 0.5)
assertEq("19.8 no_session: submitRaidResult rejected",
	"no_session", sNoSess and sNoSess.reason)

-- ============================================================
-- TASK 19.9: Abuse & anti-exploit battery (spam, forgery, bad payloads)
-- ============================================================
print("[E2E 19.9] === Abuse & Anti-Exploit Battery ===")

-- One abuser pokes every validation surface with malformed/rushed/forged
-- input. Handlers under test are the SAME code production remotes run
-- (checkRate lives inside the handlers, so the _G seams carry it).
-- Raid-side forgery (instant submit, no_active_raid, bad_input, self-raid)
-- is covered in 19.8 and not duplicated here.

local abuser = {
	UserId = 333000333,
	Name = "E2EAbuser",
	DisplayName = "E2EAbuser",
	Parent = Players,
	Character = nil,
}
local abuS = DataManager.load(abuser)
assertTrue("19.9 abuser session created", abuS ~= nil)

if abuS then
	abuS.profile.Coins = 100000 -- prove rejects never charge

	-- ===== 1. SPAM: rate limiting (lock action, 5 calls / 10s) =====
	-- harborheist-sfb4: nil-guard prevents cryptic "attempt to index nil"
	-- crash when the test seam is missing (e.g. server init didn't expose
	-- _G.HARBORHEIST_TEST). Provides an actionable failure message instead.
	local activateLock99 = _G.HARBORHEIST_TEST and _G.HARBORHEIST_TEST.aquariumActivateLock
	if activateLock99 then
		local lastRes = nil
		for _ = 1, 6 do
			local _, res = pcall(activateLock99, abuser)
			lastRes = res -- calls may throw at notify (fake player); 6th returns cleanly
		end
		assertEq("19.9 spam: 6th lock call rate_limited", "rate_limited", lastRes and lastRes.reason)
		-- These assertions depend on the lock calls above having executed
		local spamLog = AntiExploitService.getLog(abuser.UserId)
		assertTrue("19.9 spam: rate breach recorded in suspicious log", #spamLog >= 1)
		if #spamLog >= 1 then
			assertEq("19.9 spam: log entry names the action", "lock", spamLog[#spamLog].action)
		end
	else
		report("19.9 spam: aquariumActivateLock seam available", false,
			"seam is nil — _G.HARBORHEIST_TEST not exposed by server init")
	end
	-- Unknown actions warn but ALLOW (fail-open by design — independent of lock seam)
	local unknownOk = AntiExploitService.checkRate(abuser, "definitely_not_a_real_action")
	assertTrue("19.9 unknown rate-limit action allowed (warn-only)", unknownOk == true)

	-- ===== 2. BAD PAYLOADS: shop purchases =====
	-- harborheist-sfb4: nil-guard prevents cryptic crash when seam missing
	local shopPurchase99 = _G.HARBORHEIST_TEST and _G.HARBORHEIST_TEST.shopPurchase
	if shopPurchase99 then
		local coinsBefore = abuS.profile.Coins
		local s1 = shopPurchase99(abuser, nil, 1)
		assertEq("19.9 shop: nil kind rejected", "bad_args", s1 and s1.reason)
		local s2 = shopPurchase99(abuser, "rod", "two")
		assertEq("19.9 shop: non-number level rejected", "bad_args", s2 and s2.reason)
		local s3 = shopPurchase99(abuser, "yacht", 1)
		assertEq("19.9 shop: unknown kind rejected", "bad_kind", s3 and s3.reason)
		local s4 = shopPurchase99(abuser, "rod", 99)
		assertEq("19.9 shop: out-of-range level rejected", "bad_level", s4 and s4.reason)
		-- Tier-skip forgery: at rod 1, try to buy rod 3 directly (notify throws
		-- on fakes BEFORE the return — verify via state instead)
		pcall(shopPurchase99, abuser, "rod", 3)
		assertEq("19.9 shop: tier-skip forgery does not apply", 1, abuS.profile.Equipment.EquippedRodLevel)
		assertEq("19.9 shop: all rejects charged nothing", coinsBefore, abuS.profile.Coins)
	else
		report("19.9 shop: shopPurchase seam available", false,
			"seam is nil — _G.HARBORHEIST_TEST not exposed by server init")
	end

	-- ===== 3. FORGERY: fishing submit-catch =====
	-- harborheist-sfb4: nil-guarded — safe access prevents indexing crash,
	-- conditional wrapper prevents call/use crash when seams are absent
	local ht = _G.HARBORHEIST_TEST
	local submitCatch99 = ht and ht.submitCatch
	local activeBites99 = ht and ht.activeBites
	local setFishingRng99 = ht and ht.setFishingRng
	if submitCatch99 and activeBites99 and setFishingRng99 then
		assertTrue("19.9 fishing test seams available", true)

		-- Submit with no active bite (clean table return)
		local f1 = submitCatch99(abuser, { hit = true })
		assertEq("19.9 fish: submit with no active bite", "no_active_bite", f1 and f1.reason)

		-- Garbage payload type with a fresh injected bite (clean return; the
		-- bite must NOT be consumed — the player may still legitimately submit)
		activeBites99[abuser] = {
			zoneId = "StarterPier", rodLevel = 1, baitLevel = 1,
			biteTime = os.clock(), luckBonus = 0,
		}
		local f2 = submitCatch99(abuser, "garbage")
		assertEq("19.9 fish: garbage timingResult rejected", "bad_input", f2 and f2.reason)
		assertTrue("19.9 fish: bad_input does not consume the bite", activeBites99[abuser] ~= nil)

		-- Stale bite (submitted long after the window) — notify throws on fakes
		-- after clearing; the observable is the consumed bite
		activeBites99[abuser].biteTime = os.clock() - 999
		pcall(submitCatch99, abuser, { hit = true })
		assertTrue("19.9 fish: stale bite consumed (too_slow)", activeBites99[abuser] == nil)

		-- Always-hit exploiter: the client hit claim is only a REQUEST — the
		-- server re-rolls against effectiveZone (rod-1 base 0.30 with no cast
		-- luck). Seed the fishing rng above the zone -> miss, no fish granted.
		local rod1Zone = (GameConfig.RodDefinitions[1] and GameConfig.RodDefinitions[1].minigameZoneSize) or 0.30
		local function seedFishingRng99(wantMiss)
			for seed = 1, 200 do
				local probe = Random.new(seed)
				local roll = probe:NextNumber() -- call 1: the server re-roll
				if (wantMiss and roll > rod1Zone) or (not wantMiss and roll <= rod1Zone) then
					setFishingRng99(Random.new(seed))
					return true
				end
			end
			return false
		end
		assertTrue("19.9 fishing rng seeded for miss", seedFishingRng99(true))
		activeBites99[abuser] = {
			zoneId = "StarterPier", rodLevel = 1, baitLevel = 1,
			biteTime = os.clock(), luckBonus = 0,
		}
		pcall(submitCatch99, abuser, { hit = true }) -- exploiter claims a hit
		assertEq("19.9 fish: always-hit exploiter gains nothing on missed re-roll", 0, #abuS.carried)

		-- Contrast: same claim with a roll inside the zone lands a SERVER-ROLLED
		-- fish (species/rarity/value are never client-controlled)
		assertTrue("19.9 fishing rng seeded for catch", seedFishingRng99(false))
		activeBites99[abuser] = {
			zoneId = "StarterPier", rodLevel = 1, baitLevel = 1,
			biteTime = os.clock(), luckBonus = 0,
		}
		pcall(submitCatch99, abuser, { hit = true })
		assertEq("19.9 fish: successful re-roll lands one carried fish", 1, #abuS.carried)
		if #abuS.carried == 1 then
			local caught = abuS.carried[1]
			assertTrue("19.9 fish: caught fish is server-constructed",
				caught.SpeciesId ~= nil and caught.BaseSellValue ~= nil and caught.BaseSellValue > 0)
		end
	else
		report("19.9 fishing test seams available", false,
			"seam is nil — _G.HARBORHEIST_TEST not exposed by server init")
	end
end
DataManager.remove(abuser)

-- ============================================================
-- Summary
-- ============================================================
print(string.format("[E2E] SUMMARY: %d passed, %d failed", PASS, FAIL))
if FAIL > 0 then
	error(string.format("[E2E] FAILED: %d assertion(s) failed", FAIL), 0)
end
print("[E2E] COMPLETE")
