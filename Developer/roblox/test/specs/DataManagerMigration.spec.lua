-- DataManager v1->v2 migration fidelity unit tests (DataModel / TestEZ bucket).
--
-- Covers k5wz.4.2 cases 1-5: full-fidelity migration, idempotence, empty/absent
-- v1, partially corrupt v1, and quest key survival.
--
-- The migration path is: v1 data (flat cash/rodLevel/baitLevel/liveWell) enters
-- sanitize() which converts legacy fields to the structured v2 PlayerProfile.
-- sanitize() is the migration function — it handles the flat->structured
-- conversion in its "Legacy v1 fallback" block (lines 142-163).
--
-- Fixtures are hand-built v1 tables matching the historical flat shape
-- (documented in DataManager.lua comments and git history). No mocks.
--
-- Run: scripts/run_tests.sh --datamodel (requires Roblox Studio)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerProfile = require(Shared:WaitForChild("PlayerProfile"))
local FishDefinitions = require(Shared:WaitForChild("FishDefinitions"))
local FishInstance = require(Shared:WaitForChild("FishInstance"))
local DataManager = require(ServerScriptService:WaitForChild("HarborHeist"):WaitForChild("DataManager"))

local sanitize = DataManager._sanitize

-- Helper: build a realistic v1 profile fixture (the historical flat shape).
-- v1 had: cash, rodLevel, baitLevel, capacityLevel, lockLevel, alarmLevel,
-- liveWell (array of rarity indexes 1-5), carried (array of rarity indexes).
local function makeV1Fixture(overrides)
	local fixture = {
		cash = 5000,
		rodLevel = 2,
		baitLevel = 1,
		capacityLevel = 1,
		lockLevel = 0,
		alarmLevel = 0,
		liveWell = { 1, 3, 5 }, -- Common, Rare, Legendary
		carried = { 2, 4 }, -- Uncommon, Epic
	}
	if overrides then
		for k, v in pairs(overrides) do
			fixture[k] = v
		end
	end
	return fixture
end

return function()
	describe("migration — case 1: full-fidelity v1 -> v2 conversion", function()
		it("should convert legacy 'cash' to Coins preserving exact value", function()
			local v1 = makeV1Fixture({ cash = 12345 })
			local v2 = sanitize(v1)
			expect(v2.Coins).to.equal(12345)
		end)

		it("should convert legacy 'rodLevel' to Equipment.EquippedRodLevel", function()
			local v1 = makeV1Fixture({ rodLevel = 3 })
			local v2 = sanitize(v1)
			expect(v2.Equipment.EquippedRodLevel).to.equal(3)
		end)

		it("should convert legacy 'baitLevel' to Equipment.EquippedBaitLevel", function()
			local v1 = makeV1Fixture({ baitLevel = 2 })
			local v2 = sanitize(v1)
			expect(v2.Equipment.EquippedBaitLevel).to.equal(2)
		end)

		it("should convert legacy 'capacityLevel' to Aquarium.UpgradeLevel (+1 offset)", function()
			local v1 = makeV1Fixture({ capacityLevel = 2 })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.UpgradeLevel).to.equal(3) -- math.floor(2) + 1
		end)

		it("should convert legacy 'lockLevel' to Aquarium.LockLevel", function()
			local v1 = makeV1Fixture({ lockLevel = 1 })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.LockLevel).to.equal(1)
		end)

		it("should convert legacy 'alarmLevel' to Aquarium.AlarmLevel", function()
			local v1 = makeV1Fixture({ alarmLevel = 2 })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.AlarmLevel).to.equal(2)
		end)

		it("should convert liveWell rarity indexes to StoredFish FishInstance records", function()
			local v1 = makeV1Fixture({ liveWell = { 1, 2, 3, 4, 5 } })
			local v2 = sanitize(v1)
			expect(#v2.Aquarium.StoredFish).to.equal(5)
			-- Each converted record should have required FishInstance fields
			for _, fish in ipairs(v2.Aquarium.StoredFish) do
				expect(type(fish.SpeciesId)).to.equal("string")
				expect(type(fish.Rarity)).to.equal("string")
				expect(type(fish.BaseSellValue)).to.equal("number")
				expect(FishInstance.validate(fish)).to.equal(true)
			end
		end)

		it("should map rarity index 1 to Common rarity in converted fish", function()
			local v1 = makeV1Fixture({ liveWell = { 1 } })
			local v2 = sanitize(v1)
			expect(#v2.Aquarium.StoredFish).to.equal(1)
			expect(v2.Aquarium.StoredFish[1].Rarity).to.equal("Common")
		end)

		it("should map rarity index 2 to Uncommon rarity", function()
			local v1 = makeV1Fixture({ liveWell = { 2 } })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.StoredFish[1].Rarity).to.equal("Uncommon")
		end)

		it("should map rarity index 3 to Rare rarity", function()
			local v1 = makeV1Fixture({ liveWell = { 3 } })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.StoredFish[1].Rarity).to.equal("Rare")
		end)

		it("should map rarity index 4 to Epic rarity", function()
			local v1 = makeV1Fixture({ liveWell = { 4 } })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.StoredFish[1].Rarity).to.equal("Epic")
		end)

		it("should map rarity index 5 to Legendary rarity", function()
			local v1 = makeV1Fixture({ liveWell = { 5 } })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.StoredFish[1].Rarity).to.equal("Legendary")
		end)

		it("should preserve exact Coins value without rounding for integer cash", function()
			local v1 = makeV1Fixture({ cash = 1000000 })
			local v2 = sanitize(v1)
			expect(v2.Coins).to.equal(1000000)
		end)

		it("should floor non-integer cash values (via clampCoins)", function()
			local v1 = makeV1Fixture({ cash = 500.7 })
			local v2 = sanitize(v1)
			expect(v2.Coins).to.equal(500)
		end)

		it("should reject legacy rodLevel that doesn't exist in GameConfig.Rods", function()
			local v1 = makeV1Fixture({ rodLevel = 999 })
			local v2 = sanitize(v1)
			expect(v2.Equipment.EquippedRodLevel).to.equal(1)
		end)

		it("should reject legacy baitLevel that doesn't exist in GameConfig.Baits", function()
			local v1 = makeV1Fixture({ baitLevel = 999 })
			local v2 = sanitize(v1)
			expect(v2.Equipment.EquippedBaitLevel).to.equal(1)
		end)

		it("should reject out-of-range rarity indexes in liveWell (>5)", function()
			local v1 = makeV1Fixture({ liveWell = { 1, 99, 3 } })
			local v2 = sanitize(v1)
			-- Only valid indexes (1=#Rarities) survive; 99 is dropped
			expect(#v2.Aquarium.StoredFish).to.equal(2)
		end)

		it("should reject negative rarity indexes in liveWell", function()
			local v1 = makeV1Fixture({ liveWell = { 1, -1, 3 } })
			local v2 = sanitize(v1)
			expect(#v2.Aquarium.StoredFish).to.equal(2)
		end)

		it("should handle empty liveWell array", function()
			local v1 = makeV1Fixture({ liveWell = {} })
			local v2 = sanitize(v1)
			expect(#v2.Aquarium.StoredFish).to.equal(0)
		end)

		it("should handle non-table liveWell (string)", function()
			local v1 = makeV1Fixture({ liveWell = "not a list" })
			local v2 = sanitize(v1)
			expect(#v2.Aquarium.StoredFish).to.equal(0)
		end)
	end)

	describe("migration — case 2: idempotence (already-v2 not re-migrated)", function()
		it("should not re-migrate when v2 Coins is present (v2 takes priority over legacy cash)", function()
			local input = makeV1Fixture({ cash = 100, Coins = 500 })
			local v2 = sanitize(input)
			expect(v2.Coins).to.equal(500)
		end)

		it("should not re-migrate v2 Equipment when already present", function()
			local input = makeV1Fixture({ rodLevel = 2 })
			input.Equipment = { EquippedRodLevel = 4, EquippedBaitLevel = 3, OwnedRodLevels = { 1, 2, 3, 4 } }
			local v2 = sanitize(input)
			expect(v2.Equipment.EquippedRodLevel).to.equal(4)
			expect(v2.Equipment.EquippedBaitLevel).to.equal(3)
		end)

		it("should not re-migrate v2 Aquarium.StoredFish when already present", function()
			local input = makeV1Fixture({ liveWell = { 1, 2 } })
			-- Pre-existing v2 StoredFish should take priority over legacy liveWell
			input.Aquarium = {
				StoredFish = {
					{ SpeciesId = "TestFish", Rarity = "Common", BaseSellValue = 10 },
				}
			}
			local v2 = sanitize(input)
			-- N3 fix: v2 StoredFish takes priority IF it exists
			expect(#v2.Aquarium.StoredFish).to.equal(1)
		end)

		it("should produce stable output on double-sanitize (sanitize(sanitize(v1)) == sanitize(v1))", function()
			local v1 = makeV1Fixture()
			local firstPass = sanitize(v1)
			local secondPass = sanitize(firstPass)
			-- Coins should be the same
			expect(secondPass.Coins).to.equal(firstPass.Coins)
			-- Equipment should be the same
			expect(secondPass.Equipment.EquippedRodLevel).to.equal(firstPass.Equipment.EquippedRodLevel)
			expect(secondPass.Equipment.EquippedBaitLevel).to.equal(firstPass.Equipment.EquippedBaitLevel)
			-- Aquarium fish count should be the same
			expect(#secondPass.Aquarium.StoredFish).to.equal(#firstPass.Aquarium.StoredFish)
			-- StoredFish from firstPass are already FishInstance records (tables),
			-- so sanitizeStoredFish should validate and keep them
			for _, fish in ipairs(secondPass.Aquarium.StoredFish) do
				expect(FishInstance.validate(fish)).to.equal(true)
			end
		end)

		it("should not lose fish on double-sanitize through N3 guard", function()
			-- N3 (CRITICAL): only migrate v2 StoredFish when it actually exists.
			-- A v1 save with a partial Aquarium table but no StoredFish would
			-- have lost fish on first load if N3 weren't fixed.
			local v1 = makeV1Fixture({ liveWell = { 1, 2, 3, 4, 5 } })
			-- First pass: liveWell -> StoredFish
			local firstPass = sanitize(v1)
			local firstCount = #firstPass.Aquarium.StoredFish
			expect(firstCount).to.equal(5)
			-- Second pass: StoredFish already exists, should be preserved
			local secondPass = sanitize(firstPass)
			expect(#secondPass.Aquarium.StoredFish).to.equal(firstCount)
		end)
	end)

	describe("migration — case 3: empty/absent v1 → fresh default v2", function()
		it("should return defaults for nil input", function()
			local v2 = sanitize(nil)
			local dflt = PlayerProfile.default()
			expect(v2.Coins).to.equal(dflt.Coins)
			expect(v2.Equipment.EquippedRodLevel).to.equal(1)
			expect(v2.Equipment.EquippedBaitLevel).to.equal(1)
		end)

		it("should return defaults for empty table input", function()
			local v2 = sanitize({})
			local dflt = PlayerProfile.default()
			expect(v2.Coins).to.equal(dflt.Coins)
			expect(v2.Equipment.EquippedRodLevel).to.equal(1)
		end)

		it("should return defaults for string input", function()
			local v2 = sanitize("garbage")
			expect(v2.Coins).to.equal(PlayerProfile.default().Coins)
		end)

		it("should return defaults for number input", function()
			local v2 = sanitize(42)
			expect(v2.Coins).to.equal(PlayerProfile.default().Coins)
		end)

		it("should return defaults for empty v1 fixture (all fields nil)", function()
			local v2 = sanitize({})
			expect(#v2.Aquarium.StoredFish).to.equal(0)
			expect(v2.Aquarium.UpgradeLevel).to.equal(1)
			expect(v2.Aquarium.LockLevel).to.equal(0)
		end)
	end)

	describe("migration — case 4: partially-corrupt v1 → defaults for missing, preserved for present", function()
		it("should use default Coins when cash field is missing", function()
			local v1 = { rodLevel = 2 }
			local v2 = sanitize(v1)
			expect(v2.Coins).to.equal(PlayerProfile.default().Coins)
			expect(v2.Equipment.EquippedRodLevel).to.equal(2)
		end)

		it("should use default rod level when rodLevel is missing", function()
			local v1 = { cash = 1000 }
			local v2 = sanitize(v1)
			expect(v2.Equipment.EquippedRodLevel).to.equal(1)
			expect(v2.Coins).to.equal(1000)
		end)

		it("should use default bait level when baitLevel is non-numeric", function()
			local v1 = makeV1Fixture({ baitLevel = "two" })
			local v2 = sanitize(v1)
			expect(v2.Equipment.EquippedBaitLevel).to.equal(1)
		end)

		it("should use default capacity when capacityLevel is out of range", function()
			local v1 = makeV1Fixture({ capacityLevel = 999 })
			local v2 = sanitize(v1)
			-- capacityLevelOutOfRange falls through; default UpgradeLevel stays at 1
			-- but then the AquariumUpgradeTiers recompute sets it to 1
			expect(v2.Aquarium.UpgradeLevel).to.equal(1)
		end)

		it("should handle partially corrupt liveWell (mix of valid and garbage)", function()
			local v1 = makeV1Fixture({ liveWell = { 1, "garbage", 3, nil, 5, true } })
			local v2 = sanitize(v1)
			-- Only numeric rarity indexes 1-5 are converted; "garbage", nil, true dropped
			expect(#v2.Aquarium.StoredFish).to.equal(3)
		end)

		it("should handle lockLevel in valid range", function()
			local v1 = makeV1Fixture({ lockLevel = 1 })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.LockLevel).to.equal(1)
		end)

		it("should reject lockLevel out of range (> #Upgrades.Lock)", function()
			local v1 = makeV1Fixture({ lockLevel = 999 })
			local v2 = sanitize(v1)
			-- Out of range lockLevel is dropped; default is 0
			expect(v2.Aquarium.LockLevel).to.equal(0)
		end)

		it("should reject alarmLevel out of range", function()
			local v1 = makeV1Fixture({ alarmLevel = 999 })
			local v2 = sanitize(v1)
			expect(v2.Aquarium.AlarmLevel).to.equal(0)
		end)

		it("should preserve present fields while restoring defaults for absent ones", function()
			local v1 = {
				cash = 7500,
				rodLevel = 3,
				-- baitLevel ABSENT → should default to 1
				-- liveWell ABSENT → should default to empty
			}
			local v2 = sanitize(v1)
			expect(v2.Coins).to.equal(7500)
			expect(v2.Equipment.EquippedRodLevel).to.equal(3)
			expect(v2.Equipment.EquippedBaitLevel).to.equal(1)
			expect(#v2.Aquarium.StoredFish).to.equal(0)
		end)
	end)

	describe("migration — case 5: quest key survival", function()
		it("should preserve dailyQuestKey string when present in v1-like data", function()
			local v1 = makeV1Fixture()
			v1.dailyQuestKey = "2026-07-22"
			local v2 = sanitize(v1)
			expect(v2.dailyQuestKey).to.equal("2026-07-22")
		end)

		it("should preserve weeklyQuestKey string when present", function()
			local v1 = makeV1Fixture()
			v1.weeklyQuestKey = "2026-W30"
			local v2 = sanitize(v1)
			expect(v2.weeklyQuestKey).to.equal("2026-W30")
		end)

		it("should default quest keys to nil when absent from input", function()
			local v1 = makeV1Fixture()
			local v2 = sanitize(v1)
			expect(v2.dailyQuestKey).to.equal(nil)
			expect(v2.weeklyQuestKey).to.equal(nil)
		end)

		it("should reject non-string dailyQuestKey", function()
			local v1 = makeV1Fixture()
			v1.dailyQuestKey = 12345
			local v2 = sanitize(v1)
			expect(v2.dailyQuestKey).to.equal(nil)
		end)

		it("should reject non-string weeklyQuestKey", function()
			local v1 = makeV1Fixture()
			v1.weeklyQuestKey = true
			local v2 = sanitize(v1)
			expect(v2.weeklyQuestKey).to.equal(nil)
		end)

		it("should sanitize quest lists from v1 input", function()
			local v1 = makeV1Fixture()
			v1.dailyQuests = {
				{
					id = "daily_1",
					type = "catch_rarity",
					target = 5,
					rarity = 3,
					reward = 200,
					progress = 3,
					claimed = false,
					desc = "Catch 5 Rare fish",
				}
			}
			local v2 = sanitize(v1)
			expect(#v2.dailyQuests).to.equal(1)
			expect(v2.dailyQuests[1].id).to.equal("daily_1")
			expect(v2.dailyQuests[1].progress).to.equal(3)
		end)

		it("should default quest lists to empty when absent", function()
			local v1 = makeV1Fixture()
			local v2 = sanitize(v1)
			expect(#v2.dailyQuests).to.equal(0)
			expect(#v2.weeklyQuests).to.equal(0)
		end)

		it("should preserve quest lists through double-sanitize (idempotent quest migration)", function()
			local v1 = makeV1Fixture()
			v1.dailyQuestKey = "2026-07-22"
			v1.dailyQuests = {
				{
					id = "daily_1",
					type = "catch_rarity",
					target = 5,
					rarity = 3,
					reward = 200,
					progress = 3,
					claimed = false,
					desc = "Catch 5 Rare fish",
				}
			}
			local firstPass = sanitize(v1)
			local secondPass = sanitize(firstPass)
			expect(secondPass.dailyQuestKey).to.equal("2026-07-22")
			expect(#secondPass.dailyQuests).to.equal(1)
			expect(secondPass.dailyQuests[1].progress).to.equal(3)
		end)
	end)

	describe("migration — v2 coin priority over legacy cash (regression for 14.2 class)", function()
		it("v2 Coins should win over legacy cash when BOTH are present", function()
			-- This is the migration-overwrite prevention: a v2 profile that
			-- somehow still carries legacy fields should use the v2 value.
			local input = makeV1Fixture({ cash = 100 })
			input.Coins = 5000
			input.Version = 2
			local v2 = sanitize(input)
			expect(v2.Coins).to.equal(5000)
			expect(v2.Coins).never.to.equal(100)
		end)

		it("v2 Equipment should win over legacy rodLevel when BOTH are present", function()
			local input = makeV1Fixture({ rodLevel = 2 })
			input.Equipment = { EquippedRodLevel = 4, EquippedBaitLevel = 1 }
			local v2 = sanitize(input)
			expect(v2.Equipment.EquippedRodLevel).to.equal(4)
		end)

		it("v2 Aquarium.StoredFish should win over legacy liveWell (N3 fix)", function()
			local input = makeV1Fixture({ liveWell = { 1, 2, 3 } })
			input.Aquarium = {
				StoredFish = {
					{ SpeciesId = "PreExisting", Rarity = "Common", BaseSellValue = 10 },
				}
			}
			local v2 = sanitize(input)
			-- N3: v2 StoredFish is only overwritten if it actually exists.
			-- Since it exists here, the legacy liveWell is NOT applied.
			expect(#v2.Aquarium.StoredFish).to.equal(1)
		end)

		it("legacy liveWell IS applied when v2 StoredFish is absent (the N3 regression case)", function()
			-- This is the case N3 fixed: a v1 save with a partial Aquarium
			-- table (but no StoredFish key) should still get fish from liveWell.
			local input = makeV1Fixture({ liveWell = { 1, 2, 3 } })
			-- Partial Aquarium WITHOUT StoredFish — just other fields
			input.Aquarium = { UpgradeLevel = 2 }
			local v2 = sanitize(input)
			-- liveWell fish survive because Aquarium.StoredFish is absent
			expect(#v2.Aquarium.StoredFish).to.equal(3)
		end)
	end)
end
