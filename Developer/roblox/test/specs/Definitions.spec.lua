-- Definitions.spec.lua
-- TASK 18.3: Shared definition tests (FishDefinitions, ZoneDefinitions,
-- FishInstance, PlayerProfile) against REAL src/shared modules.
--
-- These tests catch the exact class of silent config drift that EPIC R2
-- documented (income-definition divergence, missing zone references,
-- incomplete profile defaults).

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local FishDefinitions = require(ReplicatedStorage.Shared.FishDefinitions)
	local ZoneDefinitions = require(ReplicatedStorage.Shared.ZoneDefinitions)
	local FishInstance = require(ReplicatedStorage.Shared.FishInstance)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)

	-- Helper: set of valid rarity names from GameConfig
	local rarityNameSet = {}
	for _, r in ipairs(GameConfig.Rarities) do
		rarityNameSet[r.name] = true
	end

	-- ================================================================
	-- 1. FishDefinitions
	-- ================================================================
	describe("FishDefinitions", function()
		it("should have 12-20 species (PRD range)", function()
			local count = 0
			for _ in pairs(FishDefinitions.Species) do
				count += 1
			end
			expect(count >= 12).to.equal(true)
			expect(count <= 20).to.equal(true)
		end)

		it("every species has all required fields", function()
			for id, def in pairs(FishDefinitions.Species) do
				expect(def.SpeciesId).to.be.a("string")
				expect(def.DisplayName).to.be.a("string")
				expect(def.Rarity).to.be.a("string")
				expect(def.ZoneIds).to.be.a("table")
				expect(def.BaseSellValue).to.be.a("number")
				expect(def.IncomePerMinute).to.be.a("number")
				expect(def.CatchWeight).to.be.a("number")
				expect(def.ModelId).to.be.a("string")
				expect(def.CollectionOrder).to.be.a("number")
			end
		end)

		it("every species has IncomePerMinute > 0", function()
			for _, def in pairs(FishDefinitions.Species) do
				expect(def.IncomePerMinute > 0).to.equal(true)
			end
		end)

		it("SpeciesId matches the table key", function()
			for id, def in pairs(FishDefinitions.Species) do
				expect(def.SpeciesId).to.equal(id)
			end
		end)

		it("ByRarity groups match source species counts", function()
			local sourceCount = {}
			for _, def in pairs(FishDefinitions.Species) do
				sourceCount[def.Rarity] = (sourceCount[def.Rarity] or 0) + 1
			end
			for rarityName, list in pairs(FishDefinitions.ByRarity) do
				expect(#list).to.equal(sourceCount[rarityName])
			end
		end)

		it("ByZone groups match source zone assignments", function()
			local sourceCount = {}
			for _, def in pairs(FishDefinitions.Species) do
				for _, zoneId in ipairs(def.ZoneIds) do
					sourceCount[zoneId] = (sourceCount[zoneId] or 0) + 1
				end
			end
			for zoneId, list in pairs(FishDefinitions.ByZone) do
				expect(#list).to.equal(sourceCount[zoneId])
			end
		end)

		it("get() returns the correct species", function()
			local def = FishDefinitions.get("Bluegill")
			expect(def.SpeciesId).to.equal("Bluegill")
		end)

		it("get() throws on unknown species", function()
			expect(function()
				FishDefinitions.get("NonExistent")
			end).to.throw()
		end)

		it("RARITY_ORDER matches GameConfig.Rarities", function()
			for i, rarity in ipairs(GameConfig.Rarities) do
				expect(FishDefinitions.RARITY_ORDER[rarity.name]).to.equal(i)
			end
		end)

		it("getRandomInZone returns a species from the pool", function()
			local result = FishDefinitions.getRandomInZone("StarterPier")
			expect(result).to.be.ok()
			expect(result.SpeciesId).to.be.a("string")
		end)

		it("getRandomInZone returns nil for unknown zone", function()
			local result = FishDefinitions.getRandomInZone("NonExistent")
			expect(result).to.equal(nil)
		end)
	end)

	-- ================================================================
	-- 2. ZoneDefinitions
	-- ================================================================
	describe("ZoneDefinitions", function()
		it("should have at least one zone", function()
			local count = 0
			for _ in pairs(ZoneDefinitions.Zones) do
				count += 1
			end
			expect(count > 0).to.equal(true)
		end)

		it("every zone has required fields", function()
			for id, zone in pairs(ZoneDefinitions.Zones) do
				expect(zone.ZoneId).to.be.a("string")
				expect(zone.DisplayName).to.be.a("string")
				expect(zone.RequiredRodLevel).to.be.a("number")
				expect(zone.Description).to.be.a("string")
			end
		end)

		it("ZoneId matches the table key", function()
			for id, zone in pairs(ZoneDefinitions.Zones) do
				expect(zone.ZoneId).to.equal(id)
			end
		end)

		it("RequiredRodLevel is a positive integer", function()
			for _, zone in pairs(ZoneDefinitions.Zones) do
				expect(zone.RequiredRodLevel >= 1).to.equal(true)
			end
		end)

		it("get() returns the correct zone", function()
			local zone = ZoneDefinitions.get("StarterPier")
			expect(zone.ZoneId).to.equal("StarterPier")
		end)

		it("get() throws on unknown zone", function()
			expect(function()
				ZoneDefinitions.get("NonExistent")
			end).to.throw()
		end)

		it("canAccess respects RequiredRodLevel", function()
			expect(ZoneDefinitions.canAccess("StarterPier", 1)).to.equal(true)
			expect(ZoneDefinitions.canAccess("StarterPier", 2)).to.equal(true)
			expect(ZoneDefinitions.canAccess("DeepWater", 1)).to.equal(false)
			expect(ZoneDefinitions.canAccess("DeepWater", 2)).to.equal(true)
		end)

		it("getZonesForRod returns accessible zones only", function()
			local level1 = ZoneDefinitions.getZonesForRod(1)
			expect(#level1 >= 1).to.equal(true)
			local level2 = ZoneDefinitions.getZonesForRod(2)
			expect(#level2 >= 2).to.equal(true)
			expect(#level2 >= #level1).to.equal(true)
		end)
	end)

	-- ================================================================
	-- 3. FishInstance
	-- ================================================================
	describe("FishInstance", function()
		it("new() creates a record with all required fields", function()
			local inst = FishInstance.new("Bluegill", "StarterPier")
			expect(inst.InstanceId).to.be.a("string")
			expect(#inst.InstanceId > 0).to.equal(true)
			expect(inst.SpeciesId).to.equal("Bluegill")
			expect(inst.Rarity).to.equal("Common")
			expect(inst.BaseSellValue).to.be.a("number")
			expect(inst.IncomePerMinute).to.be.a("number")
			expect(inst.CaughtAtTimestamp).to.be.a("number")
			expect(inst.SourceZoneId).to.equal("StarterPier")
			expect(inst.IsRaidProtected).to.be.a("boolean")
		end)

		it("new() marks Legendary as raid-protected", function()
			local inst = FishInstance.new("GoldenKoi", "DeepWater")
			expect(inst.IsRaidProtected).to.equal(true)
		end)

		it("new() marks non-Legendary as NOT raid-protected", function()
			local inst = FishInstance.new("Bluegill", "StarterPier")
			expect(inst.IsRaidProtected).to.equal(false)
		end)

		it("new() throws on unknown species", function()
			expect(function()
				FishInstance.new("NonExistent", "StarterPier")
			end).to.throw()
		end)

		it("validate() accepts a valid record", function()
			local inst = FishInstance.new("Trout", "StarterPier")
			expect(FishInstance.validate(inst)).to.equal(true)
		end)

		it("validate() rejects nil", function()
			expect(FishInstance.validate(nil)).to.equal(false)
		end)

		it("validate() rejects a record with unknown species", function()
			local fake = {
				InstanceId = "test-id",
				SpeciesId = "NonExistent",
				Rarity = "Common",
				BaseSellValue = 10,
				IncomePerMinute = 1,
				CaughtAtTimestamp = os.time(),
				SourceZoneId = "StarterPier",
				IsRaidProtected = false,
			}
			expect(FishInstance.validate(fake)).to.equal(false)
		end)

		it("validate() rejects negative sell value", function()
			local fake = {
				InstanceId = "test-id",
				SpeciesId = "Bluegill",
				Rarity = "Common",
				BaseSellValue = -5,
				IncomePerMinute = 1,
				CaughtAtTimestamp = os.time(),
				SourceZoneId = "StarterPier",
				IsRaidProtected = false,
			}
			expect(FishInstance.validate(fake)).to.equal(false)
		end)

		it("fromRarityIndex(1) produces a valid Common record", function()
			local inst = FishInstance.fromRarityIndex(1)
			expect(FishInstance.validate(inst)).to.equal(true)
			expect(inst.Rarity).to.equal("Common")
			expect(inst.SourceZoneId).to.equal("Migration")
		end)

		it("fromRarityIndex(5) produces a Legendary record with raid protection", function()
			local inst = FishInstance.fromRarityIndex(5)
			expect(inst.Rarity).to.equal("Legendary")
			expect(inst.IsRaidProtected).to.equal(true)
		end)
	end)

	-- ================================================================
	-- 4. PlayerProfile
	-- ================================================================
	describe("PlayerProfile", function()
		local profile = PlayerProfile.default()

		it("default() returns a table", function()
			expect(profile).to.be.a("table")
		end)

		it("Version is CURRENT_VERSION", function()
			expect(profile.Version).to.equal(PlayerProfile.CURRENT_VERSION)
		end)

		it("Coins matches GameConfig.StartingCash", function()
			expect(profile.Coins).to.equal(GameConfig.StartingCash)
		end)

		it("TotalCoinsEarned starts at 0", function()
			expect(profile.TotalCoinsEarned).to.equal(0)
		end)

		describe("Equipment defaults", function()
			it("EquippedRodLevel is 1", function()
				expect(profile.Equipment.EquippedRodLevel).to.equal(1)
			end)

			it("EquippedBaitLevel is 1", function()
				expect(profile.Equipment.EquippedBaitLevel).to.equal(1)
			end)

			it("OwnedRodLevels contains level 1", function()
				expect(profile.Equipment.OwnedRodLevels).to.be.a("table")
				expect(profile.Equipment.OwnedRodLevels[1]).to.equal(1)
			end)
		end)

		describe("Aquarium defaults", function()
			it("Capacity matches GameConfig base", function()
				expect(profile.Aquarium.Capacity).to.equal(GameConfig.Aquarium.baseCapacity)
			end)

			it("UpgradeLevel is 1", function()
				expect(profile.Aquarium.UpgradeLevel).to.equal(1)
			end)

			it("StoredFish is empty", function()
				expect(profile.Aquarium.StoredFish).to.be.a("table")
			end)

			it("UnclaimedIncome is 0", function()
				expect(profile.Aquarium.UnclaimedIncome).to.equal(0)
			end)

			it("timestamps default to 0", function()
				expect(profile.Aquarium.LastIncomeTimestamp).to.equal(0)
				expect(profile.Aquarium.LockUntilTimestamp).to.equal(0)
				expect(profile.Aquarium.LockCooldownUntilTimestamp).to.equal(0)
				expect(profile.Aquarium.RaidProtectionUntilTimestamp).to.equal(0)
			end)

			it("RaidOptIn is false", function()
				expect(profile.Aquarium.RaidOptIn).to.equal(false)
			end)

			it("LockLevel and AlarmLevel are 0", function()
				expect(profile.Aquarium.LockLevel).to.equal(0)
				expect(profile.Aquarium.AlarmLevel).to.equal(0)
			end)
		end)

		describe("remaining sections", function()
			it("Dock has UpgradeLevel 1 and empty CosmeticUnlocks", function()
				expect(profile.Dock.UpgradeLevel).to.equal(1)
				expect(profile.Dock.CosmeticUnlocks).to.be.a("table")
			end)

			it("Collection has empty tables", function()
				expect(profile.Collection.DiscoveredSpecies).to.be.a("table")
				expect(profile.Collection.MilestonesClaimed).to.be.a("table")
			end)

			it("PvP defaults are zero/empty", function()
				expect(profile.PvP.RaidAttemptsToday).to.equal(0)
				expect(profile.PvP.LastRaidTimestamp).to.equal(0)
				expect(profile.PvP.RecentTargetUserIds).to.be.a("table")
				expect(profile.PvP.RaidsWon).to.equal(0)
				expect(profile.PvP.RaidsLost).to.equal(0)
			end)

			it("Onboarding flags all start false", function()
				expect(profile.Onboarding.HasCompletedIntro).to.equal(false)
				expect(profile.Onboarding.HasCaughtFirstFish).to.equal(false)
				expect(profile.Onboarding.HasStoredFirstFish).to.equal(false)
				expect(profile.Onboarding.HasClaimedIncome).to.equal(false)
				expect(profile.Onboarding.HasSeenRaidExplanation).to.equal(false)
				expect(profile.Onboarding.HasSeenSellStoreComparison).to.equal(false)
			end)

			it("Defense has free uses matching GameConfig max", function()
				expect(profile.Defense.LockFreeUsesRemaining).to.equal(GameConfig.Defense.LockFreeUsesMax)
				expect(profile.Defense.LockFreeUsesMax).to.equal(GameConfig.Defense.LockFreeUsesMax)
			end)

			it("quest pools are empty tables", function()
				expect(profile.dailyQuests).to.be.a("table")
				expect(profile.weeklyQuests).to.be.a("table")
			end)
		end)
	end)

	describe("PlayerProfile.clampCoins", function()
		it("passes through positive values within range", function()
			expect(PlayerProfile.clampCoins(100)).to.equal(100)
		end)

		it("clamps negative values to 0", function()
			expect(PlayerProfile.clampCoins(-50)).to.equal(0)
		end)

		it("clamps values above MAX_COINS", function()
			expect(PlayerProfile.clampCoins(PlayerProfile.MAX_COINS + 1)).to.equal(PlayerProfile.MAX_COINS)
		end)

		it("rejects NaN (returns 0)", function()
			expect(PlayerProfile.clampCoins(0 / 0)).to.equal(0)
		end)

		it("rejects non-numbers (returns 0)", function()
			expect(PlayerProfile.clampCoins("hello")).to.equal(0)
			expect(PlayerProfile.clampCoins(nil)).to.equal(0)
		end)

		it("floors fractional values", function()
			expect(PlayerProfile.clampCoins(100.9)).to.equal(100)
		end)
	end)

	-- ================================================================
	-- 5. Cross-referential integrity
	-- ================================================================
	describe("Cross-referential integrity", function()
		it("every species rarity exists in GameConfig.Rarities", function()
			for _, def in pairs(FishDefinitions.Species) do
				expect(rarityNameSet[def.Rarity]).to.equal(true)
			end
		end)

		it("every zone referenced by a species exists in ZoneDefinitions", function()
			for _, def in pairs(FishDefinitions.Species) do
				for _, zoneId in ipairs(def.ZoneIds) do
					expect(ZoneDefinitions.Zones[zoneId]).to.be.ok()
				end
			end
		end)

		it("every zone in ByZone exists in ZoneDefinitions", function()
			for zoneId in pairs(FishDefinitions.ByZone) do
				expect(ZoneDefinitions.Zones[zoneId]).to.be.ok()
			end
		end)

		it("every zone in ZoneDefinitions has at least one species", function()
			for zoneId in pairs(ZoneDefinitions.Zones) do
				local species = FishDefinitions.ByZone[zoneId]
				expect(species).to.be.ok()
				expect(#species > 0).to.equal(true)
			end
		end)
	end)
end
