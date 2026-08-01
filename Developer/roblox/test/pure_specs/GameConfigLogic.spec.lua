-- GameConfig pure-logic unit tests (harborheist-yw3u).
--
-- GameConfig.lua has Color3.fromRGB() at module level (in the Rarities
-- table) so it cannot be required directly in the lune pure runner. The
-- rollRarity weighted-probability logic is mirrored as pure Luau functions
-- and exercised against expected behaviour. Source-contract assertions
-- verify that the production code still contains the config values and
-- validation checks tested here.
--
-- Covers: rollRarity weight distribution, luck bonus scaling, boundary
-- rolls, deterministic mock-rng behaviour, and config structure contracts
-- (Rarities, RodDefinitions, BaitDefinitions, MiniGame, validate checks).

local fs = require("@lune/fs")

return function(describe, it, expect)
	-- ──────────────────────────────────────────────────────────────────
	-- Config mirrors (must match src/shared/GameConfig.lua)
	-- ──────────────────────────────────────────────────────────────────

	local Rarities = {
		{ name = "Common",    weight = 55, value = 10 },
		{ name = "Uncommon",  weight = 25, value = 25 },
		{ name = "Rare",      weight = 12, value = 70 },
		{ name = "Epic",      weight = 6,  value = 180 },
		{ name = "Legendary", weight = 2,  value = 500 },
	}

	local MiniGame = {
		hitZoneWidth = 0.3,
		goodZoneWidth = 0.5,
		biteZoneCeiling = 0.85,
		accuracyLuckBonus = { perfect = 25, good = 12, ok = 0 },
	}

	local RodDefinitions = {
		{ id = 1, name = "Basic Rod",  luck = 0,  castTime = 4, minigameZoneSize = 0.30 },
		{ id = 2, name = "Steel Rod",  luck = 8,  castTime = 3, minigameZoneSize = 0.35 },
		{ id = 3, name = "Golden Rod", luck = 20, castTime = 2, minigameZoneSize = 0.40 },
	}

	local BaitDefinitions = {
		{ id = 1, name = "Basic Bait",  luck = 0  },
		{ id = 2, name = "Shrimp Bait", luck = 6  },
		{ id = 3, name = "Magic Bait",  luck = 15 },
	}

	-- ──────────────────────────────────────────────────────────────────
	-- rollRarity logic mirror (verbatim from GameConfig.lua)
	-- ──────────────────────────────────────────────────────────────────

	-- Mirrors GameConfig.rollRarity(luck, rng) — weighted probability
	-- with luck bonus scaling higher rarities. Returns index 1..5.
	local function rollRarity(luck, rng)
		local total = 0
		local weights = {}
		for i, rarity in ipairs(Rarities) do
			local w = rarity.weight * (1 + (luck / 100) * (i - 1))
			weights[i] = w
			total += w
		end
		local roll = (rng and rng:NextNumber() or math.random()) * total
		local acc = 0
		for i, w in ipairs(weights) do
			acc += w
			if roll <= acc then
				return i
			end
		end
		return 1
	end

	-- Mock RNG that returns a fixed value (0..1)
	local function makeMockRng(value)
		return {
			NextNumber = function()
				return value
			end,
		}
	end

	-- ──────────────────────────────────────────────────────────────────
	-- rollRarity tests
	-- ──────────────────────────────────────────────────────────────────

	describe("rollRarity", function()
		it("returns a valid index (1-5)", function()
			for _, v in ipairs({ 0, 0.1, 0.3, 0.5, 0.7, 0.9, 0.99, 1.0 }) do
				local idx = rollRarity(0, makeMockRng(v))
				expect(idx).to.be.a("number")
				expect(idx >= 1 and idx <= 5).to.equal(true)
			end
		end)

		it("returns 1 (Common) when roll is 0", function()
			expect(rollRarity(0, makeMockRng(0))).to.equal(1)
		end)

		it("returns 1 (Common) when roll is very small", function()
			expect(rollRarity(0, makeMockRng(0.001))).to.equal(1)
		end)

		it("returns last index (Legendary) when roll approaches 1", function()
			-- Roll just under total lands in the last bucket
			expect(rollRarity(0, makeMockRng(0.999))).to.equal(5)
		end)

		it("is deterministic with the same rng value", function()
			local rng = makeMockRng(0.5)
			local a = rollRarity(10, rng)
			local b = rollRarity(10, rng)
			expect(a).to.equal(b)
		end)

		it("luck=0 produces weight-proportional distribution", function()
			-- With luck=0, weights equal base weights: 55,25,12,6,2 (total=100)
			-- roll <= acc: boundary is inclusive at the TOP of each bucket
			expect(rollRarity(0, makeMockRng(0.54))).to.equal(1) -- Common
			expect(rollRarity(0, makeMockRng(0.55))).to.equal(2) -- Uncommon (55/100)
			-- (55+25)/100 = 0.80 → at 0.80 it's Uncommon (inclusive)
			expect(rollRarity(0, makeMockRng(0.79))).to.equal(2) -- Uncommon
			expect(rollRarity(0, makeMockRng(0.80))).to.equal(2) -- Uncommon (boundary inclusive)
			expect(rollRarity(0, makeMockRng(0.81))).to.equal(3) -- Rare (just above)
		end)

		it("high luck increases probability of rarer fish", function()
			-- With luck=100, weights are: 55, 50, 36, 24, 10 (total=175)
			-- Common boundary: 55/175 ≈ 0.314 (vs 0.55 with luck=0)
			-- So roll=0.40 gives Common with luck=0 but Uncommon with luck=100
			expect(rollRarity(0, makeMockRng(0.40))).to.equal(1)   -- Common (luck=0)
			expect(rollRarity(100, makeMockRng(0.40))).to.equal(2)  -- Uncommon (luck=100)
		end)

		it("luck bonus scales linearly with rarity index", function()
			-- weight[i] = base[i] * (1 + (luck/100) * (i-1))
			-- For luck=100: factor[i] = 1 + (i-1) = i
			-- So weights = 55*1, 25*2, 12*3, 6*4, 2*5 = 55, 50, 36, 24, 10
			local luck = 100
			local expectedWeights = { 55, 50, 36, 24, 10 }
			local total = 0
			for _, w in ipairs(expectedWeights) do total += w end
			-- Verify boundaries (roll <= acc is inclusive at top of bucket)
			local acc = 0
			for i, w in ipairs(expectedWeights) do
				acc += w
				local boundary = acc / total
				if i < 5 then
					-- Just below boundary → index i
					expect(rollRarity(luck, makeMockRng(boundary - 0.001))).to.equal(i)
					-- At boundary → still index i (inclusive)
					expect(rollRarity(luck, makeMockRng(boundary))).to.equal(i)
					-- Just above boundary → index i+1
					expect(rollRarity(luck, makeMockRng(boundary + 0.001))).to.equal(i + 1)
				end
			end
		end)

		it("works without rng (falls back to math.random)", function()
			-- Just verify it doesn't crash and returns valid index
			local idx = rollRarity(0)
			expect(idx).to.be.a("number")
			expect(idx >= 1 and idx <= 5).to.equal(true)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Config structure validation
	-- ──────────────────────────────────────────────────────────────────

	describe("Config structure", function()
		it("Rarities has 5 entries in order", function()
			expect(#Rarities).to.equal(5)
			expect(Rarities[1].name).to.equal("Common")
			expect(Rarities[2].name).to.equal("Uncommon")
			expect(Rarities[3].name).to.equal("Rare")
			expect(Rarities[4].name).to.equal("Epic")
			expect(Rarities[5].name).to.equal("Legendary")
		end)

		it("Rarities weights are non-increasing", function()
			for i = 2, #Rarities do
				expect(Rarities[i].weight <= Rarities[i - 1].weight).to.equal(true)
			end
		end)

		it("Rarities values increase with rarity", function()
			for i = 2, #Rarities do
				expect(Rarities[i].value > Rarities[i - 1].value).to.equal(true)
			end
		end)

		it("RodDefinitions has 3 rods with required fields", function()
			expect(#RodDefinitions).to.equal(3)
			for _, rod in ipairs(RodDefinitions) do
				expect(rod.id).to.be.a("number")
				expect(rod.name).to.be.a("string")
				expect(rod.luck).to.be.a("number")
				expect(rod.castTime).to.be.a("number")
				expect(rod.minigameZoneSize).to.be.a("number")
			end
		end)

		it("each rod minigameZoneSize <= biteZoneCeiling", function()
			local ceiling = MiniGame.biteZoneCeiling
			for _, rod in ipairs(RodDefinitions) do
				expect(rod.minigameZoneSize <= ceiling).to.equal(true)
			end
		end)

		it("each rod minigameZoneSize <= goodZoneWidth", function()
			local goodWidth = MiniGame.goodZoneWidth
			for _, rod in ipairs(RodDefinitions) do
				expect(rod.minigameZoneSize <= goodWidth).to.equal(true)
			end
		end)

		it("goodZoneWidth < 1.0", function()
			expect(MiniGame.goodZoneWidth < 1.0).to.equal(true)
		end)

		it("BaitDefinitions has 3 baits with required fields", function()
			expect(#BaitDefinitions).to.equal(3)
			for _, bait in ipairs(BaitDefinitions) do
				expect(bait.id).to.be.a("number")
				expect(bait.name).to.be.a("string")
				expect(bait.luck).to.be.a("number")
			end
		end)

		it("luck values are non-negative", function()
			for _, rod in ipairs(RodDefinitions) do
				expect(rod.luck >= 0).to.equal(true)
			end
			for _, bait in ipairs(BaitDefinitions) do
				expect(bait.luck >= 0).to.equal(true)
			end
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract verification
	-- ──────────────────────────────────────────────────────────────────

	local configSource = fs.readFile("src/shared/GameConfig.lua")

	describe("Source contract: config tables", function()
		it("Rarities table has 5 entries with correct names", function()
			expect(configSource:find('name = "Common"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Uncommon"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Rare"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Epic"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Legendary"', 1, true)).to.be.a("number")
		end)

		it("Rarities weights are 55, 25, 12, 6, 2", function()
			expect(configSource:find("weight = 55", 1, true)).to.be.a("number")
			expect(configSource:find("weight = 25", 1, true)).to.be.a("number")
			expect(configSource:find("weight = 12", 1, true)).to.be.a("number")
			expect(configSource:find("weight = 6", 1, true)).to.be.a("number")
			expect(configSource:find("weight = 2", 1, true)).to.be.a("number")
		end)

		it("Rarities values are 10, 25, 70, 180, 500", function()
			expect(configSource:find("value = 10,", 1, true)).to.be.a("number")
			expect(configSource:find("value = 25,", 1, true)).to.be.a("number")
			expect(configSource:find("value = 70,", 1, true)).to.be.a("number")
			expect(configSource:find("value = 180", 1, true)).to.be.a("number")
			expect(configSource:find("value = 500", 1, true)).to.be.a("number")
		end)

		it("RodDefinitions has 3 rods", function()
			expect(configSource:find('name = "Basic Rod"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Steel Rod"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Golden Rod"', 1, true)).to.be.a("number")
		end)

		it("BaitDefinitions has 3 baits", function()
			expect(configSource:find('name = "Basic Bait"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Shrimp Bait"', 1, true)).to.be.a("number")
			expect(configSource:find('name = "Magic Bait"', 1, true)).to.be.a("number")
		end)

		it("MiniGame config has correct values", function()
			expect(configSource:find("hitZoneWidth = 0.3", 1, true)).to.be.a("number")
			expect(configSource:find("goodZoneWidth = 0.5", 1, true)).to.be.a("number")
			expect(configSource:find("biteZoneCeiling = 0.85", 1, true)).to.be.a("number")
		end)
	end)

	describe("Source contract: functions and validation", function()
		it("rollRarity function exists", function()
			expect(configSource:find("function GameConfig.rollRarity(", 1, true)).to.be.a("number")
		end)

		it("rollRarity uses luck-scaled weight formula", function()
			expect(configSource:find("rarity.weight * (1 + (luck / 100) * (i - 1))", 1, true)).to.be.a("number")
		end)

		it("validate function exists", function()
			expect(configSource:find("function GameConfig.validate()", 1, true)).to.be.a("number")
		end)

		it("validate checks for stale incomePerSec field", function()
			expect(configSource:find("rarity.incomePerSec ~= nil", 1, true)).to.be.a("number")
		end)

		it("validate checks rod minigameZoneSize vs biteZoneCeiling", function()
			expect(configSource:find("rod.minigameZoneSize > ceiling", 1, true)).to.be.a("number")
		end)

		it("validate checks goodZoneWidth < 1.0", function()
			expect(configSource:find("goodWidth >= 1.0", 1, true)).to.be.a("number")
		end)

		it("validate checks rod minigameZoneSize vs goodZoneWidth", function()
			expect(configSource:find("rod.minigameZoneSize > goodWidth", 1, true)).to.be.a("number")
		end)

		it("validate checks rarity weight monotonicity", function()
			expect(configSource:find("rarity.weight > prev.weight", 1, true)).to.be.a("number")
		end)
	end)
end
