-- PlayerProfile pure-logic unit tests (harborheist-y8d8).
--
-- PlayerProfile.lua has game:GetService at the top level (require GameConfig)
-- so it cannot be required directly in the lune pure runner. The clampCoins
-- security guard and default-profile structure are mirrored as pure Luau
-- functions and exercised against expected behaviour. Source-contract
-- assertions verify that the production code still contains the schema
-- fields and security checks tested here.
--
-- Covers: clampCoins (normal values, negative clamping, overflow, NaN
-- rejection, non-number, ±Inf, floor), profile version, and source-
-- contract checks for default() schema fields.

local fs = require("@lune/fs")

return function(describe, it, expect)
	-- ──────────────────────────────────────────────────────────────────
	-- Config mirrors (must match src/shared/PlayerProfile.lua)
	-- ──────────────────────────────────────────────────────────────────

	local MAX_COINS = 999999999

	-- ──────────────────────────────────────────────────────────────────
	-- clampCoins logic mirror (verbatim from PlayerProfile.lua)
	-- ──────────────────────────────────────────────────────────────────

	-- Mirrors PlayerProfile.clampCoins(value) — the security-critical coin
	-- clamp. NaN rejection prevents the "buy everything for free" exploit:
	-- (NaN < cost) is always false in Lua, so a NaN-coined player bypasses
	-- every purchase gate. The guard checks value ~= value (the only number
	-- not equal to itself) before the clamp.
	local function clampCoins(value)
		if type(value) ~= "number" then
			return 0
		end
		if value ~= value then
			return 0
		end
		return math.floor(math.max(0, math.min(MAX_COINS, value)))
	end

	-- ──────────────────────────────────────────────────────────────────
	-- clampCoins tests
	-- ──────────────────────────────────────────────────────────────────

	describe("clampCoins", function()
		it("returns 0 for nil", function()
			expect(clampCoins(nil)).to.equal(0)
		end)

		it("returns 0 for string", function()
			expect(clampCoins("100")).to.equal(0)
		end)

		it("returns 0 for boolean", function()
			expect(clampCoins(true)).to.equal(0)
		end)

		it("returns 0 for table", function()
			expect(clampCoins({})).to.equal(0)
		end)

		it("returns 0 for negative values", function()
			expect(clampCoins(-1)).to.equal(0)
			expect(clampCoins(-100)).to.equal(0)
			expect(clampCoins(-0.5)).to.equal(0)
		end)

		it("returns the value for valid positive numbers (floored)", function()
			expect(clampCoins(0)).to.equal(0)
			expect(clampCoins(100)).to.equal(100)
			expect(clampCoins(500.0)).to.equal(500)
		end)

		it("floors fractional values", function()
			expect(clampCoins(99.9)).to.equal(99)
			expect(clampCoins(500.99)).to.equal(500)
			expect(clampCoins(0.9)).to.equal(0)
		end)

		it("clamps to MAX_COINS on overflow", function()
			expect(clampCoins(MAX_COINS)).to.equal(MAX_COINS)
			expect(clampCoins(MAX_COINS + 1)).to.equal(MAX_COINS)
			expect(clampCoins(MAX_COINS * 2)).to.equal(MAX_COINS)
		end)

		it("rejects NaN (security: NaN bypasses purchase gates)", function()
			local nan = 0 / 0
			expect(clampCoins(nan)).to.equal(0)
		end)

		it("rejects -NaN", function()
			local neg_nan = -(0 / 0)
			expect(clampCoins(neg_nan)).to.equal(0)
		end)

		it("clamps +Inf to MAX_COINS", function()
			local pos_inf = math.huge
			expect(clampCoins(pos_inf)).to.equal(MAX_COINS)
		end)

		it("clamps -Inf to 0", function()
			local neg_inf = -math.huge
			expect(clampCoins(neg_inf)).to.equal(0)
		end)

		it("is idempotent (clamping an already-clamped value)", function()
			local v = clampCoins(12345)
			expect(clampCoins(v)).to.equal(v)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract verification
	-- ──────────────────────────────────────────────────────────────────

	local profileSource = fs.readFile("src/shared/PlayerProfile.lua")

	describe("Source contract: constants and version", function()
		it("CURRENT_VERSION is 2", function()
			expect(profileSource:find("CURRENT_VERSION = 2", 1, true)).to.be.a("number")
		end)

		it("MAX_COINS is 999999999", function()
			expect(profileSource:find("MAX_COINS = 999999999", 1, true)).to.be.a("number")
		end)
	end)

	describe("Source contract: clampCoins security guards", function()
		it("rejects non-number type", function()
			expect(profileSource:find('type(value) ~= "number"', 1, true)).to.be.a("number")
		end)

		it("rejects NaN via self-inequality", function()
			expect(profileSource:find("value ~= value", 1, true)).to.be.a("number")
		end)

		it("uses math.floor for integer rounding", function()
			expect(profileSource:find("math.floor(math.max(0, math.min(PlayerProfile.MAX_COINS, value)))", 1, true)).to.be.a("number")
		end)
	end)

	describe("Source contract: default() profile schema", function()
		it("default function exists", function()
			expect(profileSource:find("function PlayerProfile.default()", 1, true)).to.be.a("number")
		end)

		it("Version field present", function()
			expect(profileSource:find("Version = PlayerProfile.CURRENT_VERSION", 1, true)).to.be.a("number")
		end)

		it("Coins initialized from StartingCash", function()
			expect(profileSource:find("Coins = GameConfig.StartingCash", 1, true)).to.be.a("number")
		end)

		it("Equipment section with rod/bait fields", function()
			expect(profileSource:find("EquippedRodLevel = 1", 1, true)).to.be.a("number")
			expect(profileSource:find("EquippedBaitLevel = 1", 1, true)).to.be.a("number")
			expect(profileSource:find("OwnedRodLevels", 1, true)).to.be.a("number")
		end)

		it("Aquarium section with capacity and defense fields", function()
			expect(profileSource:find("Capacity = GameConfig.Aquarium.baseCapacity", 1, true)).to.be.a("number")
			expect(profileSource:find("UpgradeLevel = 1", 1, true)).to.be.a("number")
			expect(profileSource:find("StoredFish = {}", 1, true)).to.be.a("number")
			expect(profileSource:find("UnclaimedIncome = 0", 1, true)).to.be.a("number")
			expect(profileSource:find("LockLevel = 0", 1, true)).to.be.a("number")
			expect(profileSource:find("AlarmLevel = 0", 1, true)).to.be.a("number")
		end)

		it("Aquarium raid fields present", function()
			expect(profileSource:find("RaidOptIn = false", 1, true)).to.be.a("number")
			expect(profileSource:find("RaidProtectionUntilTimestamp = 0", 1, true)).to.be.a("number")
		end)

		it("Dock section with upgrade level", function()
			expect(profileSource:find("Dock = {", 1, true)).to.be.a("number")
			expect(profileSource:find("UpgradeLevel = 1", 1, true)).to.be.a("number")
		end)

		it("Collection section with discovery + milestones", function()
			expect(profileSource:find("DiscoveredSpecies = {}", 1, true)).to.be.a("number")
			expect(profileSource:find("MilestonesClaimed = {}", 1, true)).to.be.a("number")
		end)

		it("PvP section with raid tracking", function()
			expect(profileSource:find("RaidAttemptsToday = 0", 1, true)).to.be.a("number")
			expect(profileSource:find("RecentTargetTimestamps = {}", 1, true)).to.be.a("number")
			expect(profileSource:find("RaidsWon = 0", 1, true)).to.be.a("number")
			expect(profileSource:find("RaidsLost = 0", 1, true)).to.be.a("number")
		end)

		it("Onboarding section with all flags", function()
			expect(profileSource:find("HasCompletedIntro = false", 1, true)).to.be.a("number")
			expect(profileSource:find("HasCaughtFirstFish = false", 1, true)).to.be.a("number")
			expect(profileSource:find("HasStoredFirstFish = false", 1, true)).to.be.a("number")
			expect(profileSource:find("HasClaimedIncome = false", 1, true)).to.be.a("number")
			expect(profileSource:find("HasSeenRaidExplanation = false", 1, true)).to.be.a("number")
			expect(profileSource:find("HasSeenSellStoreComparison = false", 1, true)).to.be.a("number")
		end)

		it("Defense section with free lock uses", function()
			expect(profileSource:find("LockFreeUsesRemaining", 1, true)).to.be.a("number")
			expect(profileSource:find("LockFreeUsesMax", 1, true)).to.be.a("number")
		end)

		it("Quest pool fields present", function()
			expect(profileSource:find("dailyQuests = {}", 1, true)).to.be.a("number")
			expect(profileSource:find("weeklyQuests = {}", 1, true)).to.be.a("number")
		end)
	end)
end
