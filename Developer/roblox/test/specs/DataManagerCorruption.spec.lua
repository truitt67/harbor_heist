-- DataManagerCorruption.spec.lua
-- TASK 18.4.3: DataManager corruption-resilience unit tests (DataModel / TestEZ).
--
-- Exercises the real DataManager._sanitize function with adversarial inputs:
-- 1) corrupted quest entries are filtered while valid siblings survive,
-- 2) Onboarding whitelist drops unknown/non-boolean keys,
-- 3) garbage top-level input never throws and returns a safe default profile,
-- 4) unknown top-level fields are dropped,
-- 5) malformed / impossible StoredFish records are filtered.
--
-- No mocks or stubs: uses real PlayerProfile, GameConfig, FishDefinitions,
-- and FishInstance. All sanitize() calls are direct (no pcall wrapping) so
-- any unexpected throw fails the spec.
--
-- Run: scripts/run_tests.sh --datamodel (requires Roblox Studio)

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local GameConfig = require(Shared:WaitForChild("GameConfig"))
	local PlayerProfile = require(Shared:WaitForChild("PlayerProfile"))
	local FishDefinitions = require(Shared:WaitForChild("FishDefinitions"))
	local FishInstance = require(Shared:WaitForChild("FishInstance"))
	local DataManager = require(ServerScriptService:WaitForChild("HarborHeist"):WaitForChild("DataManager"))

	local sanitize = DataManager._sanitize

	local function defaultProfile()
		return PlayerProfile.default()
	end

	local function validFish()
		return FishInstance.new("Bluegill", "StarterPier")
	end

	local function validQuest(id)
		return {
			id = id or "q_good",
			type = "catch_rarity",
			target = 5,
			rarity = 2,
			reward = 100,
			progress = 1,
			claimed = false,
			desc = "Catch 5 Uncommon fish",
		}
	end

	-- ════════════════════════════════════════════════════════════════════════
	-- CASE 1: corrupted quest entries are filtered; valid siblings kept.
	-- ════════════════════════════════════════════════════════════════════════
	describe("Corrupted quest entries", function()
		it("filters quests with missing type while keeping valid siblings", function()
			local input = defaultProfile()
			input.dailyQuests = {
				validQuest("good"),
				{ id = "bad", target = 5, reward = 100, progress = 0, claimed = false, desc = "No type" },
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(1)
			expect(result.dailyQuests[1].id).to.equal("good")
		end)

		it("filters quests with non-positive target", function()
			local input = defaultProfile()
			input.dailyQuests = {
				validQuest("good"),
				{ id = "bad", type = "catch_rarity", target = 0, reward = 100, progress = 0, claimed = false, desc = "Zero target" },
				{ id = "bad2", type = "catch_rarity", target = -3, reward = 100, progress = 0, claimed = false, desc = "Negative target" },
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(1)
			expect(result.dailyQuests[1].id).to.equal("good")
		end)

		it("filters quests with negative reward", function()
			local input = defaultProfile()
			input.dailyQuests = {
				validQuest("good"),
				{ id = "bad", type = "catch_rarity", target = 5, reward = -50, progress = 0, claimed = false, desc = "Negative reward" },
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(1)
			expect(result.dailyQuests[1].reward).to.equal(100)
		end)

		it("filters quests with non-string type", function()
			local input = defaultProfile()
			input.dailyQuests = {
				validQuest("good"),
				{ id = "bad", type = 123, target = 5, reward = 100, progress = 0, claimed = false, desc = "Bad type" },
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(1)
		end)

		it("filters quests with non-number target or reward", function()
			local input = defaultProfile()
			input.dailyQuests = {
				validQuest("good"),
				{ id = "bad", type = "catch_rarity", target = "five", reward = 100, progress = 0, claimed = false, desc = "String target" },
				{ id = "bad2", type = "catch_rarity", target = 5, reward = "free", progress = 0, claimed = false, desc = "String reward" },
			}
			local result = sanitize(input)
			expect(#result.dailyQuests).to.equal(1)
		end)

		it("applies the same filtering rules to weekly quests", function()
			local input = defaultProfile()
			input.weeklyQuests = {
				validQuest("good_weekly"),
				{ id = "bad", type = "catch_count", target = -1, reward = 500, progress = 0, claimed = false, desc = "Bad weekly" },
			}
			local result = sanitize(input)
			expect(#result.weeklyQuests).to.equal(1)
			expect(result.weeklyQuests[1].id).to.equal("good_weekly")
		end)

		it("preserves quest keys even when the associated list is corrupt", function()
			local input = defaultProfile()
			input.dailyQuestKey = "2026-07-22"
			input.weeklyQuestKey = "2026-W30"
			input.dailyQuests = { "not a quest", { type = 123, target = 5, reward = 100 } }
			input.weeklyQuests = { nil, { type = "catch_rarity", target = 0, reward = 200 } }
			local result = sanitize(input)
			expect(result.dailyQuestKey).to.equal("2026-07-22")
			expect(result.weeklyQuestKey).to.equal("2026-W30")
			expect(#result.dailyQuests).to.equal(0)
			expect(#result.weeklyQuests).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════════
	-- CASE 2: Onboarding whitelist — unknown keys dropped, known keys kept.
	-- ════════════════════════════════════════════════════════════════════════
	describe("Onboarding whitelist", function()
		it("drops unknown keys and preserves the six known flags", function()
			local input = defaultProfile()
			input.Onboarding.HasCompletedIntro = true
			input.Onboarding.HasCaughtFirstFish = true
			input.Onboarding.EvilFlag = true
			input.Onboarding.AlsoEvil = "yes"
			local result = sanitize(input)
			expect(result.Onboarding.HasCompletedIntro).to.equal(true)
			expect(result.Onboarding.HasCaughtFirstFish).to.equal(true)
			expect(result.Onboarding.HasStoredFirstFish).to.equal(false)
			expect(result.Onboarding.EvilFlag).to.equal(nil)
			expect(result.Onboarding.AlsoEvil).to.equal(nil)
		end)

		it("rejects non-boolean values for known Onboarding keys", function()
			local input = defaultProfile()
			input.Onboarding.HasClaimedIncome = 1
			input.Onboarding.HasSeenRaidExplanation = "true"
			local result = sanitize(input)
			expect(result.Onboarding.HasClaimedIncome).to.equal(false)
			expect(result.Onboarding.HasSeenRaidExplanation).to.equal(false)
		end)

		it("replaces a non-table Onboarding value with the default flags", function()
			local input = defaultProfile()
			input.Onboarding = "corrupt"
			local result = sanitize(input)
			expect(result.Onboarding).to.be.a("table")
			expect(result.Onboarding.HasCompletedIntro).to.equal(false)
			expect(result.Onboarding.HasCaughtFirstFish).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════════
	-- CASE 3: garbage top-level input never throws and returns a safe profile.
	-- ════════════════════════════════════════════════════════════════════════
	describe("Garbage top-level input", function()
		local function assertSafeDefault(input)
			local result = sanitize(input)
			expect(result).to.be.a("table")
			expect(result.Version).to.equal(PlayerProfile.CURRENT_VERSION)
			expect(result.Coins).to.equal(GameConfig.StartingCash)
			expect(result.Equipment.EquippedRodLevel).to.equal(1)
			expect(result.Aquarium).to.be.a("table")
			expect(result.Aquarium.StoredFish).to.be.a("table")
			expect(#result.Aquarium.StoredFish).to.equal(0)
		end

		it("returns defaults for nil", function()
			assertSafeDefault(nil)
		end)

		it("returns defaults for a string", function()
			assertSafeDefault("corrupt save")
		end)

		it("returns defaults for a number", function()
			assertSafeDefault(42)
		end)

		it("returns defaults for a boolean", function()
			assertSafeDefault(true)
		end)

		it("returns defaults for a function", function()
			assertSafeDefault(function() end)
		end)

		it("returns defaults for a sparse array", function()
			assertSafeDefault({ [1] = "a", [3] = "b" })
		end)

		it("returns defaults for self-referential junk", function()
			local t = {}
			t.self = t
			assertSafeDefault(t)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════════
	-- CASE 4: unknown top-level fields are dropped; known fields are kept.
	-- ════════════════════════════════════════════════════════════════════════
	describe("Unknown top-level fields", function()
		it("drops arbitrary top-level keys and preserves the schema fields", function()
			local input = defaultProfile()
			input.Coins = 7500
			input.TotalCoinsEarned = 12000
			input.Version = 1
			input.EvilCoins = 999999999
			input.CheatField = { foo = "bar" }
			input.legacyJunk = true
			local result = sanitize(input)
			expect(result.Coins).to.equal(7500)
			expect(result.TotalCoinsEarned).to.equal(12000)
			expect(result.Version).to.equal(1)
			expect(result.EvilCoins).to.equal(nil)
			expect(result.CheatField).to.equal(nil)
			expect(result.legacyJunk).to.equal(nil)
		end)

		it("treats legacy v1 'cash' as a known migration field, not as unknown", function()
			local input = defaultProfile()
			input.cash = 5555
			input.Coins = nil
			local result = sanitize(input)
			expect(result.Coins).to.equal(5555)
			expect(result.cash).to.equal(nil)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════════
	-- CASE 5: StoredFish corruption — holes, duplicates, impossible species.
	-- ════════════════════════════════════════════════════════════════════════
	describe("StoredFish corruption", function()
		it("replaces a non-table StoredFish with an empty list", function()
			local input = defaultProfile()
			input.Aquarium.StoredFish = "fish"
			local result = sanitize(input)
			expect(result.Aquarium.StoredFish).to.be.a("table")
			expect(#result.Aquarium.StoredFish).to.equal(0)
		end)

		it("drops entries with an unknown species id", function()
			local input = defaultProfile()
			local bad = validFish()
			bad.SpeciesId = "TotallyFakeFish"
			input.Aquarium.StoredFish = {
				validFish(),
				bad,
				validFish(),
			}
			local result = sanitize(input)
			expect(#result.Aquarium.StoredFish).to.equal(2)
			expect(result.Aquarium.StoredFish[1].SpeciesId).to.equal("Bluegill")
			expect(result.Aquarium.StoredFish[2].SpeciesId).to.equal("Bluegill")
		end)

		it("drops entries with missing required fields", function()
			local input = defaultProfile()
			input.Aquarium.StoredFish = {
				validFish(),
				{ InstanceId = "x", SpeciesId = "Bluegill" },
				validFish(),
			}
			local result = sanitize(input)
			expect(#result.Aquarium.StoredFish).to.equal(2)
		end)

		it("drops entries with negative numeric fields", function()
			local input = defaultProfile()
			local bad = validFish()
			bad.BaseSellValue = -10
			input.Aquarium.StoredFish = {
				validFish(),
				bad,
			}
			local result = sanitize(input)
			expect(#result.Aquarium.StoredFish).to.equal(1)
		end)

		it("stops at holes in a sparse StoredFish list (ipairs behavior)", function()
			local input = defaultProfile()
			local a = validFish()
			local b = validFish()
			input.Aquarium.StoredFish = { [1] = a, [3] = b }
			local result = sanitize(input)
			expect(#result.Aquarium.StoredFish).to.equal(1)
			expect(result.Aquarium.StoredFish[1].SpeciesId).to.equal("Bluegill")
		end)

		it("keeps duplicate valid entries (sanitize does not dedupe)", function()
			local input = defaultProfile()
			local a = validFish()
			local b = validFish()
			input.Aquarium.StoredFish = { a, b }
			local result = sanitize(input)
			expect(#result.Aquarium.StoredFish).to.equal(2)
			expect(result.Aquarium.StoredFish[1].SpeciesId).to.equal("Bluegill")
			expect(result.Aquarium.StoredFish[2].SpeciesId).to.equal("Bluegill")
		end)

		it("converts valid legacy rarity indexes and drops invalid ones", function()
			local input = defaultProfile()
			input.Aquarium.StoredFish = { 1, 6, 0, 3, "bad" }
			local result = sanitize(input)
			expect(#result.Aquarium.StoredFish).to.equal(2)
			expect(result.Aquarium.StoredFish[1].Rarity).to.equal("Common")
			expect(result.Aquarium.StoredFish[2].Rarity).to.equal("Rare")
		end)
	end)
end
