-- DataManager.sanitize() unit tests (DataModel / TestEZ bucket).
--
-- Covers k5wz.4.1 cases 1-5: valid v2 pass-through, type coercion, timestamp
-- handling, equipment list clamping, and aquarium invariants.
--
-- sanitize() is a local function in DataManager; a test-only export
-- (DataManager._sanitize) makes it accessible without changing production
-- behavior. sanitize() calls game:GetService internally (for FishInstance
-- and FishDefinitions requires), so it MUST run in the DataModel bucket.
--
-- Run: scripts/run_tests.sh --datamodel (requires Roblox Studio)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PlayerProfile = require(Shared:WaitForChild("PlayerProfile"))
local FishDefinitions = require(Shared:WaitForChild("FishDefinitions"))
local DataManager = require(ServerScriptService:WaitForChild("HarborHeist"):WaitForChild("DataManager"))

local sanitize = DataManager._sanitize

return function()
	local function defaultProfile()
		return PlayerProfile.default()
	end

	describe("sanitize — case 1: valid v2 profile passes through semantically unchanged", function()
		it("should preserve a complete v2 profile's core fields", function()
			local input = defaultProfile()
			input.Coins = 5000
			input.TotalCoinsEarned = 10000
			input.Equipment.EquippedRodLevel = 3
			input.Equipment.EquippedBaitLevel = 2
			input.Equipment.OwnedRodLevels = { 1, 2, 3 }

			local result = sanitize(input)
			expect(result.Coins).to.equal(5000)
			expect(result.TotalCoinsEarned).to.equal(10000)
			expect(result.Equipment.EquippedRodLevel).to.equal(3)
			expect(result.Equipment.EquippedBaitLevel).to.equal(2)
			expect(#result.Equipment.OwnedRodLevels).to.equal(3)
		end)

		it("should preserve Aquarium fields on a valid v2 profile", function()
			local input = defaultProfile()
			input.Aquarium.UpgradeLevel = 2
			input.Aquarium.UnclaimedIncome = 500
			input.Aquarium.LastIncomeTimestamp = 1234567890
			input.Aquarium.RaidOptIn = true
			input.Aquarium.LockLevel = 1
			input.Aquarium.AlarmLevel = 1

			local result = sanitize(input)
			expect(result.Aquarium.UpgradeLevel).to.equal(2)
			expect(result.Aquarium.UnclaimedIncome).to.equal(500)
			expect(result.Aquarium.LastIncomeTimestamp).to.equal(1234567890)
			expect(result.Aquarium.RaidOptIn).to.equal(true)
			expect(result.Aquarium.LockLevel).to.equal(1)
			expect(result.Aquarium.AlarmLevel).to.equal(1)
		end)

		it("should preserve Collection discovery and milestones", function()
			local input = defaultProfile()
			-- Discover a species that exists in FishDefinitions
			local firstSpeciesId = nil
			for _, def in pairs(FishDefinitions.Species) do
				firstSpeciesId = def.SpeciesId
				break
			end
			input.Collection.DiscoveredSpecies[firstSpeciesId] = true
			input.Collection.MilestonesClaimed["count_5"] = true

			local result = sanitize(input)
			expect(result.Collection.DiscoveredSpecies[firstSpeciesId]).to.equal(true)
			expect(result.Collection.MilestonesClaimed["count_5"]).to.equal(true)
		end)

		it("should preserve Onboarding flags", function()
			local input = defaultProfile()
			input.Onboarding.HasCaughtFirstFish = true
			input.Onboarding.HasClaimedIncome = true

			local result = sanitize(input)
			expect(result.Onboarding.HasCaughtFirstFish).to.equal(true)
			expect(result.Onboarding.HasClaimedIncome).to.equal(true)
			expect(result.Onboarding.HasCompletedIntro).to.equal(false)
		end)

		it("should preserve PvP stats", function()
			local input = defaultProfile()
			input.PvP.RaidAttemptsToday = 3
			input.PvP.RaidsWon = 5
			input.PvP.RaidsLost = 2

			local result = sanitize(input)
			expect(result.PvP.RaidAttemptsToday).to.equal(3)
			expect(result.PvP.RaidsWon).to.equal(5)
			expect(result.PvP.RaidsLost).to.equal(2)
		end)

		it("should preserve Defense state", function()
			local input = defaultProfile()
			input.Defense.LockFreeUsesRemaining = 2
			input.Defense.LockFreeUsesMax = 5

			local result = sanitize(input)
			expect(result.Defense.LockFreeUsesRemaining).to.equal(2)
			expect(result.Defense.LockFreeUsesMax).to.equal(5)
		end)

		it("should preserve Dock state", function()
			local input = defaultProfile()
			input.Dock.UpgradeLevel = 2
			input.Dock.CosmeticUnlocks = { "LampPost" }

			local result = sanitize(input)
			expect(result.Dock.UpgradeLevel).to.equal(2)
			expect(result.Dock.CosmeticUnlocks[1]).to.equal("LampPost")
		end)
	end)

	describe("sanitize — case 2: type coercion", function()
		it("should return defaults for non-table input", function()
			local result = sanitize(nil)
			local dflt = defaultProfile()
			expect(result.Coins).to.equal(dflt.Coins)
			expect(result.Equipment.EquippedRodLevel).to.equal(1)
		end)

		it("should return defaults for string input", function()
			local result = sanitize("not a table")
			expect(result.Coins).to.equal(defaultProfile().Coins)
		end)

		it("should return defaults for number input", function()
			local result = sanitize(42)
			expect(result.Coins).to.equal(defaultProfile().Coins)
		end)

		it("should zero out non-numeric Coins", function()
			local input = defaultProfile()
			input.Coins = "lots"
			local result = sanitize(input)
			expect(result.Coins).to.equal(defaultProfile().Coins)
		end)

		it("should clamp negative coins to 0 (via clampCoins)", function()
			local input = defaultProfile()
			input.Coins = -500
			local result = sanitize(input)
			expect(result.Coins).to.equal(0)
		end)

		it("should clamp coins exceeding MAX_COINS", function()
			local input = defaultProfile()
			input.Coins = PlayerProfile.MAX_COINS + 1000
			local result = sanitize(input)
			expect(result.Coins).to.equal(PlayerProfile.MAX_COINS)
		end)

		it("should zero out NaN coins (R1.2 fix)", function()
			local input = defaultProfile()
			input.Coins = 0 / 0
			local result = sanitize(input)
			expect(result.Coins).to.equal(0)
		end)

		it("should rebuild Equipment to defaults when non-table", function()
			local input = defaultProfile()
			input.Equipment = "broken"
			local result = sanitize(input)
			expect(result.Equipment.EquippedRodLevel).to.equal(1)
			expect(result.Equipment.EquippedBaitLevel).to.equal(1)
		end)

		it("should reject invalid rod level (out of range)", function()
			local input = defaultProfile()
			input.Equipment.EquippedRodLevel = 999
			local result = sanitize(input)
			expect(result.Equipment.EquippedRodLevel).to.equal(1)
		end)

		it("should reject non-numeric rod level", function()
			local input = defaultProfile()
			input.Equipment.EquippedRodLevel = "three"
			local result = sanitize(input)
			expect(result.Equipment.EquippedRodLevel).to.equal(1)
		end)

		it("should reject invalid bait level", function()
			local input = defaultProfile()
			input.Equipment.EquippedBaitLevel = 999
			local result = sanitize(input)
			expect(result.Equipment.EquippedBaitLevel).to.equal(1)
		end)

		it("should filter OwnedRodLevels to valid entries only", function()
			local input = defaultProfile()
			input.Equipment.OwnedRodLevels = { 1, 2, 999, "bad", -1 }
			local result = sanitize(input)
			-- Only valid rod levels 1 and 2 should survive; 999/"bad"/-1 dropped
			expect(#result.Equipment.OwnedRodLevels).to.equal(2)
			expect(result.Equipment.OwnedRodLevels[1]).to.equal(1)
			expect(result.Equipment.OwnedRodLevels[2]).to.equal(2)
		end)

		it("should clamp TotalCoinsEarned to >= 0", function()
			local input = defaultProfile()
			input.TotalCoinsEarned = -100
			local result = sanitize(input)
			expect(result.TotalCoinsEarned).to.equal(0)
		end)

		it("should floor TotalCoinsEarned to integer", function()
			local input = defaultProfile()
			input.TotalCoinsEarned = 100.7
			local result = sanitize(input)
			expect(result.TotalCoinsEarned).to.equal(100)
		end)
	end)

	describe("sanitize — case 3: timestamp handling", function()
		-- FINDING: sanitize() does NOT clamp LockUntilTimestamp or
		-- LockCooldownUntilTimestamp. It passes them through as-is.
		-- The 600s clamping happens in rehydrateTimer() inside DataManager.load(),
		-- NOT in sanitize(). This is the REAL behavior — encoded here, not
		-- expected from sanitize per se.
		it("should pass through LockUntilTimestamp as-is (no clamping in sanitize)", function()
			local input = defaultProfile()
			local farFuture = os.time() + 999999
			input.Aquarium.LockUntilTimestamp = farFuture
			local result = sanitize(input)
			expect(result.Aquarium.LockUntilTimestamp).to.equal(farFuture)
		end)

		it("should pass through LockCooldownUntilTimestamp as-is", function()
			local input = defaultProfile()
			local farFuture = os.time() + 999999
			input.Aquarium.LockCooldownUntilTimestamp = farFuture
			local result = sanitize(input)
			expect(result.Aquarium.LockCooldownUntilTimestamp).to.equal(farFuture)
		end)

		it("should pass through LastIncomeTimestamp as-is", function()
			local input = defaultProfile()
			input.Aquarium.LastIncomeTimestamp = 1234567890
			local result = sanitize(input)
			expect(result.Aquarium.LastIncomeTimestamp).to.equal(1234567890)
		end)

		it("should reject non-numeric LockUntilTimestamp", function()
			local input = defaultProfile()
			input.Aquarium.LockUntilTimestamp = "soon"
			local result = sanitize(input)
			expect(result.Aquarium.LockUntilTimestamp).to.equal(0)
		end)

		it("should reject non-numeric LockCooldownUntilTimestamp", function()
			local input = defaultProfile()
			input.Aquarium.LockCooldownUntilTimestamp = true
			local result = sanitize(input)
			expect(result.Aquarium.LockCooldownUntilTimestamp).to.equal(0)
		end)

		it("should preserve RaidProtectionUntilTimestamp", function()
			local input = defaultProfile()
			input.Aquarium.RaidProtectionUntilTimestamp = os.time() + 300
			local result = sanitize(input)
			expect(result.Aquarium.RaidProtectionUntilTimestamp).to.equal(input.Aquarium.RaidProtectionUntilTimestamp)
		end)
	end)

	describe("sanitize — case 4: equipment list clamping", function()
		it("should clamp OwnedRodLevels to only valid rod levels", function()
			local input = defaultProfile()
			input.Equipment.OwnedRodLevels = { 1, 2, 3, 4, 5, 6, 7, 8 }
			local result = sanitize(input)
			-- Only levels that exist in GameConfig.Rods survive
			for _, lvl in ipairs(result.Equipment.OwnedRodLevels) do
				expect(GameConfig.Rods[lvl]).to.be.ok()
			end
		end)

		it("should handle non-table OwnedRodLevels", function()
			local input = defaultProfile()
			input.Equipment.OwnedRodLevels = "not a list"
			-- When OwnedRodLevels is non-table, the `if type(eq.OwnedRodLevels) == "table"`
			-- guard skips it entirely, so it keeps the default { 1 }
			local result = sanitize(input)
			expect(result.Equipment.OwnedRodLevels[1]).to.equal(1)
		end)

		it("should filter out non-number entries in OwnedRodLevels", function()
			local input = defaultProfile()
			input.Equipment.OwnedRodLevels = { 1, "two", true, nil, 2 }
			local result = sanitize(input)
			for _, lvl in ipairs(result.Equipment.OwnedRodLevels) do
				expect(type(lvl)).to.equal("number")
			end
		end)
	end)

	describe("sanitize — case 5: aquarium invariants", function()
		it("should recompute Capacity from UpgradeLevel (N6 fix)", function()
			local input = defaultProfile()
			input.Aquarium.UpgradeLevel = 2
			input.Aquarium.Capacity = 999 -- crafted/exploited
			local result = sanitize(input)
			-- Capacity should be recomputed from the tier table, not honored
			local tiers = GameConfig.AquariumUpgradeTiers
			if tiers and #tiers > 0 then
				expect(result.Aquarium.Capacity).to.equal(tiers[2].capacity)
				expect(result.Aquarium.Capacity).never.to.equal(999)
			end
		end)

		it("should clamp UpgradeLevel to valid tier range", function()
			local input = defaultProfile()
			input.Aquarium.UpgradeLevel = 999
			local result = sanitize(input)
			local tiers = GameConfig.AquariumUpgradeTiers
			if tiers and #tiers > 0 then
				expect(result.Aquarium.UpgradeLevel).to.equal(#tiers)
			end
		end)

		it("should clamp UpgradeLevel minimum to 1", function()
			local input = defaultProfile()
			input.Aquarium.UpgradeLevel = -5
			local result = sanitize(input)
			expect(result.Aquarium.UpgradeLevel).to.equal(1)
		end)

		it("should clamp UnclaimedIncome to [0, MaxUnclaimedIncome]", function()
			local input = defaultProfile()
			input.Aquarium.UnclaimedIncome = -100
			local result = sanitize(input)
			expect(result.Aquarium.UnclaimedIncome).to.equal(0)

			input.Aquarium.UnclaimedIncome = GameConfig.Economy.MaxUnclaimedIncome + 5000
			result = sanitize(input)
			expect(result.Aquarium.UnclaimedIncome).to.equal(GameConfig.Economy.MaxUnclaimedIncome)
		end)

		it("should clamp LockLevel to valid range", function()
			local input = defaultProfile()
			input.Aquarium.LockLevel = 999
			local result = sanitize(input)
			expect(result.Aquarium.LockLevel).to.equal(#GameConfig.Upgrades.Lock)
		end)

		it("should clamp AlarmLevel to valid range", function()
			local input = defaultProfile()
			input.Aquarium.AlarmLevel = 999
			local result = sanitize(input)
			expect(result.Aquarium.AlarmLevel).to.equal(#GameConfig.Upgrades.Alarm)
		end)

		it("should reject non-boolean RaidOptIn", function()
			local input = defaultProfile()
			input.Aquarium.RaidOptIn = "yes"
			local result = sanitize(input)
			expect(result.Aquarium.RaidOptIn).to.equal(false)
		end)

		it("should preserve valid RaidOptIn boolean", function()
			local input = defaultProfile()
			input.Aquarium.RaidOptIn = true
			local result = sanitize(input)
			expect(result.Aquarium.RaidOptIn).to.equal(true)
		end)
	end)

	describe("sanitize — v1 -> v2 migration (legacy fallback)", function()
		it("should convert legacy 'cash' field to Coins", function()
			local input = defaultProfile()
			input.cash = 7500
			input.Coins = nil -- simulate v1 (no Coins field)
			local result = sanitize(input)
			expect(result.Coins).to.equal(7500)
		end)

		it("should convert legacy 'rodLevel' to Equipment.EquippedRodLevel", function()
			local input = defaultProfile()
			input.rodLevel = 2
			local result = sanitize(input)
			expect(result.Equipment.EquippedRodLevel).to.equal(2)
		end)

		it("should reject legacy rodLevel that doesn't exist in Rods table", function()
			local input = defaultProfile()
			input.rodLevel = 999
			local result = sanitize(input)
			expect(result.Equipment.EquippedRodLevel).to.equal(1)
		end)

		it("should convert legacy 'baitLevel' to Equipment.EquippedBaitLevel", function()
			local input = defaultProfile()
			input.baitLevel = 2
			local result = sanitize(input)
			expect(result.Equipment.EquippedBaitLevel).to.equal(2)
		end)

		it("should convert legacy 'capacityLevel' to Aquarium.UpgradeLevel", function()
			local input = defaultProfile()
			input.capacityLevel = 2
			local result = sanitize(input)
			expect(result.Aquarium.UpgradeLevel).to.equal(3) -- math.floor(2) + 1
		end)

		it("should prefer v2 Coins over legacy cash (v2 takes priority)", function()
			local input = defaultProfile()
			input.cash = 100
			input.Coins = 500
			local result = sanitize(input)
			expect(result.Coins).to.equal(500)
		end)
	end)

	describe("sanitize — Onboarding whitelist", function()
		it("should reject unknown Onboarding keys", function()
			local input = defaultProfile()
			input.Onboarding.EvilFlag = true
			local result = sanitize(input)
			expect(result.Onboarding.EvilFlag).to.equal(nil)
		end)

		it("should reject non-boolean Onboarding values", function()
			local input = defaultProfile()
			input.Onboarding.HasCaughtFirstFish = 1
			local result = sanitize(input)
			expect(result.Onboarding.HasCaughtFirstFish).to.equal(false)
		end)

		it("should accept all 6 valid Onboarding flags", function()
			local input = defaultProfile()
			input.Onboarding.HasCompletedIntro = true
			input.Onboarding.HasCaughtFirstFish = true
			input.Onboarding.HasStoredFirstFish = true
			input.Onboarding.HasClaimedIncome = true
			input.Onboarding.HasSeenRaidExplanation = true
			input.Onboarding.HasSeenSellStoreComparison = true
			local result = sanitize(input)
			expect(result.Onboarding.HasCompletedIntro).to.equal(true)
			expect(result.Onboarding.HasCaughtFirstFish).to.equal(true)
			expect(result.Onboarding.HasStoredFirstFish).to.equal(true)
			expect(result.Onboarding.HasClaimedIncome).to.equal(true)
			expect(result.Onboarding.HasSeenRaidExplanation).to.equal(true)
			expect(result.Onboarding.HasSeenSellStoreComparison).to.equal(true)
		end)
	end)

	describe("sanitize — Defense clamping", function()
		it("should clamp LockFreeUsesRemaining to [0, 10]", function()
			local input = defaultProfile()
			input.Defense.LockFreeUsesRemaining = 999
			local result = sanitize(input)
			expect(result.Defense.LockFreeUsesRemaining).to.equal(10)
		end)

		it("should clamp LockFreeUsesRemaining negative to 0", function()
			local input = defaultProfile()
			input.Defense.LockFreeUsesRemaining = -5
			local result = sanitize(input)
			expect(result.Defense.LockFreeUsesRemaining).to.equal(0)
		end)

		it("should clamp LockFreeUsesMax to [1, 10]", function()
			local input = defaultProfile()
			input.Defense.LockFreeUsesMax = 999
			local result = sanitize(input)
			expect(result.Defense.LockFreeUsesMax).to.equal(10)
		end)

		it("should floor fractional Defense values", function()
			local input = defaultProfile()
			input.Defense.LockFreeUsesRemaining = 3.7
			local result = sanitize(input)
			expect(result.Defense.LockFreeUsesRemaining).to.equal(3)
		end)
	end)

	describe("sanitize — Dock clamping", function()
		it("should clamp Dock.UpgradeLevel against DockUpgradeTiers", function()
			local input = defaultProfile()
			input.Dock.UpgradeLevel = 999
			local result = sanitize(input)
			local tiers = GameConfig.DockUpgradeTiers
			if tiers and #tiers > 0 then
				expect(result.Dock.UpgradeLevel).to.equal(#tiers)
			end
		end)

		it("should filter Dock.CosmeticUnlocks to strings only", function()
			local input = defaultProfile()
			input.Dock.CosmeticUnlocks = { "LampPost", 123, true, "Planters" }
			local result = sanitize(input)
			expect(#result.Dock.CosmeticUnlocks).to.equal(2)
			expect(result.Dock.CosmeticUnlocks[1]).to.equal("LampPost")
			expect(result.Dock.CosmeticUnlocks[2]).to.equal("Planters")
		end)
	end)

	describe("sanitize — Collection discovery validation", function()
		it("should drop unknown species IDs from DiscoveredSpecies", function()
			local input = defaultProfile()
			input.Collection.DiscoveredSpecies = {
				["TotallyFakeSpecies"] = true,
				["AnotherFakeOne"] = true,
			}
			local result = sanitize(input)
			expect(result.Collection.DiscoveredSpecies["TotallyFakeSpecies"]).to.equal(nil)
			expect(result.Collection.DiscoveredSpecies["AnotherFakeOne"]).to.equal(nil)
		end)

		it("should keep only species that exist in FishDefinitions", function()
			local input = defaultProfile()
			local firstId = nil
			for _, def in pairs(FishDefinitions.Species) do
				firstId = def.SpeciesId
				break
			end
			input.Collection.DiscoveredSpecies[firstId] = true
			input.Collection.DiscoveredSpecies["FakeSpecies"] = true
			local result = sanitize(input)
			expect(result.Collection.DiscoveredSpecies[firstId]).to.equal(true)
			expect(result.Collection.DiscoveredSpecies["FakeSpecies"]).to.equal(nil)
		end)

		it("should reject non-boolean discovery values", function()
			local input = defaultProfile()
			input.Collection.DiscoveredSpecies = { ["SomeSpecies"] = 1 }
			local result = sanitize(input)
			-- Only val == true is kept
			expect(next(result.Collection.DiscoveredSpecies)).to.equal(nil)
		end)

		it("should handle both map and array forms of MilestonesClaimed", function()
			local input = defaultProfile()
			-- Map form (current): { ["count_5"] = true }
			input.Collection.MilestonesClaimed["count_5"] = true
			-- Legacy array form: { "count_10" } (number index -> string value)
			table.insert(input.Collection.MilestonesClaimed, "count_10")
			local result = sanitize(input)
			expect(result.Collection.MilestonesClaimed["count_5"]).to.equal(true)
			expect(result.Collection.MilestonesClaimed["count_10"]).to.equal(true)
		end)
	end)

	describe("sanitize — PvP stat clamping", function()
		it("should clamp negative RaidAttemptsToday to 0", function()
			local input = defaultProfile()
			input.PvP.RaidAttemptsToday = -3
			local result = sanitize(input)
			expect(result.PvP.RaidAttemptsToday).to.equal(0)
		end)

		it("should floor fractional PvP values", function()
			local input = defaultProfile()
			input.PvP.RaidAttemptsToday = 2.9
			input.PvP.RaidsWon = 3.1
			local result = sanitize(input)
			expect(result.PvP.RaidAttemptsToday).to.equal(2)
			expect(result.PvP.RaidsWon).to.equal(3)
		end)

		it("should filter RecentTargetUserIds to numbers only", function()
			local input = defaultProfile()
			input.PvP.RecentTargetUserIds = { 12345, "bad", true, 67890 }
			local result = sanitize(input)
			expect(#result.PvP.RecentTargetUserIds).to.equal(2)
			expect(result.PvP.RecentTargetUserIds[1]).to.equal(12345)
			expect(result.PvP.RecentTargetUserIds[2]).to.equal(67890)
		end)
	end)

	describe("sanitize — Quest sanitization", function()
		it("should sanitize quest list with valid structure", function()
			local input = defaultProfile()
			input.dailyQuests = {
				{
					id = "daily_1",
					type = "catch_rarity",
					target = 5,
					rarity = 3,
					reward = 200,
					progress = 2,
					claimed = false,
					desc = "Catch 5 Rare fish",
				}
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(1)
			expect(result.dailyQuests[1].type).to.equal("catch_rarity")
			expect(result.dailyQuests[1].target).to.equal(5)
			expect(result.dailyQuests[1].reward).to.equal(200)
		end)

		it("should reject quests with invalid structure", function()
			local input = defaultProfile()
			input.dailyQuests = {
				"not a table",
				{ type = "catch_rarity", target = "five", reward = 200 }, -- non-number target
				{ type = 123, target = 5, reward = 200 }, -- non-string type
				{ type = "catch_rarity", target = 5, reward = -100 }, -- negative reward
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(0)
		end)

		it("should clamp quest progress to [0, target]", function()
			local input = defaultProfile()
			input.dailyQuests = {
				{
					id = "daily_1",
					type = "catch_rarity",
					target = 5,
					rarity = 3,
					reward = 200,
					progress = 99,
					claimed = false,
					desc = "Test",
				}
			}
			local result = sanitize(input)
			expect(result.dailyQuests[1].progress).to.equal(5)
		end)

		it("should default claimed to false for non-boolean values", function()
			local input = defaultProfile()
			input.dailyQuests = {
				{
					id = "daily_1",
					type = "catch_rarity",
					target = 5,
					reward = 200,
					progress = 0,
					claimed = 1,
					desc = "Test",
				}
			}
			local result = sanitize(input)
			expect(result.dailyQuests[1].claimed).to.equal(false)
		end)

		it("should preserve quest key strings", function()
			local input = defaultProfile()
			input.dailyQuestKey = "2026-07-22"
			input.weeklyQuestKey = "2026-W30"
			local result = sanitize(input)
			expect(result.dailyQuestKey).to.equal("2026-07-22")
			expect(result.weeklyQuestKey).to.equal("2026-W30")
		end)

		it("should reject non-string quest keys", function()
			local input = defaultProfile()
			input.dailyQuestKey = 12345
			local result = sanitize(input)
			expect(result.dailyQuestKey).to.equal(nil)
		end)
	end)

	describe("sanitize — Version field", function()
		it("should accept a valid version number", function()
			local input = defaultProfile()
			input.Version = 2
			local result = sanitize(input)
			expect(result.Version).to.equal(2)
		end)

		it("should default version when non-numeric", function()
			local input = defaultProfile()
			input.Version = "two"
			local result = sanitize(input)
			expect(result.Version).to.equal(PlayerProfile.CURRENT_VERSION)
		end)

		it("should default version when < 1", function()
			local input = defaultProfile()
			input.Version = 0
			local result = sanitize(input)
			expect(result.Version).to.equal(PlayerProfile.CURRENT_VERSION)
		end)
	end)

	describe("sanitize — Stats and TotalCatches", function()
		it("should preserve Stats.TotalCatches", function()
			local input = defaultProfile()
			input.Stats.TotalCatches = 42
			local result = sanitize(input)
			expect(result.Stats.TotalCatches).to.equal(42)
		end)

		it("should clamp negative TotalCatches to 0", function()
			local input = defaultProfile()
			input.Stats.TotalCatches = -10
			local result = sanitize(input)
			expect(result.Stats.TotalCatches).to.equal(0)
		end)

		it("should floor fractional TotalCatches", function()
			local input = defaultProfile()
			input.Stats.TotalCatches = 15.8
			local result = sanitize(input)
			expect(result.Stats.TotalCatches).to.equal(15)
		end)

		it("should accept legacy top-level TotalCatches", function()
			local input = defaultProfile()
			input.TotalCatches = 100
			local result = sanitize(input)
			expect(result.Stats.TotalCatches).to.equal(100)
			expect(result.PvP.TotalCatches).to.equal(100)
		end)

		it("should take max of Stats and legacy top-level TotalCatches", function()
			local input = defaultProfile()
			input.Stats.TotalCatches = 50
			input.TotalCatches = 80
			local result = sanitize(input)
			expect(result.Stats.TotalCatches).to.equal(80)
		end)
	end)
end
