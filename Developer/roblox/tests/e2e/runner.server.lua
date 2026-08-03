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
local AntiExploitService = require(hh:WaitForChild("AntiExploitService"))
local PlayerProfile = require(ReplicatedStorage.Shared:WaitForChild("PlayerProfile"))
local GameConfig = require(ReplicatedStorage.Shared:WaitForChild("GameConfig"))

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

-- TASK 19.7 (Lock/Defense Flow) MIGRATED to tests/e2e/scenarios/LockDefense.lua (EPIC 43, tbvq)

-- TASK 19.8 (Raid System, incl. r7an no_session) MIGRATED to tests/e2e/scenarios/Raid.lua (EPIC 43, xpei)

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
