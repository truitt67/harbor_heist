-- FishingService pure-logic unit tests (TASK 41-01-A, harborheist-m3vj.1.1).
--
-- FishingService has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the core catch
-- mechanics are mirrored as pure Luau functions and exercised against
-- the authoritative config values. Source-contract assertions verify
-- that the production code still contains the formulas tested here.
--
-- Covers: tier derivation, accuracy clamping, effective-zone interpolation,
-- luck stacking, bite-window timing, zone-bounds computation, and
-- re-roll anti-exploit semantics. No mocks, fakes, or stubs — only
-- pure math mirrors + source-file contract checks.

local fs = require("@lune/fs")

-- ──────────────────────────────────────────────────────────────────────
-- Config mirrors (must match src/shared/GameConfig.lua)
-- ──────────────────────────────────────────────────────────────────────

local MiniGame = {
	hitZoneWidth = 0.3,
	goodZoneWidth = 0.5,
	accuracyLuckBonus = { perfect = 25, good = 12, ok = 0 },
	biteZoneCeiling = 0.85,
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

local BITE_WINDOW_SECONDS = 3.5

-- ──────────────────────────────────────────────────────────────────────
-- Logic mirrors (verbatim from FishingService.lua production code)
-- ──────────────────────────────────────────────────────────────────────

-- Clamp client-reported marker position to [0,1]; non-numbers → 0.
local function clampAccuracy(accuracy)
	return type(accuracy) == "number" and math.clamp(accuracy, 0, 1) or 0
end

-- Derive accuracy tier from server-authoritative zone bounds.
-- Inner "perfect" band checked first (subset of outer "good" band).
local function deriveTier(accuracy, hitZoneStart, hitZoneEnd, goodStart, goodEnd)
	if accuracy >= hitZoneStart and accuracy <= hitZoneEnd then
		return "perfect"
	elseif accuracy >= goodStart and accuracy <= goodEnd then
		return "good"
	else
		return "ok"
	end
end

-- Map tier → luck bonus from config.
local function tierToLuckBonus(tier)
	return MiniGame.accuracyLuckBonus[tier] or 0
end

-- Interpolate base zone → ceiling by the cast-accuracy luck fraction.
-- Matches FishingService lines 386-396 (DECISION C / TASK 14.24).
local function computeEffectiveZone(baseZone, luckBonus, maxLuck, ceiling)
	local effectiveZone = baseZone
	if maxLuck and maxLuck > 0 and luckBonus > 0 then
		effectiveZone = baseZone + (luckBonus / maxLuck) * (ceiling - baseZone)
	end
	return math.clamp(effectiveZone, baseZone, ceiling)
end

-- Total luck for species roll: rod + bait + cast-accuracy bonus.
local function computeTotalLuck(rodLevel, baitLevel, castLuckBonus)
	local rod = RodDefinitions[rodLevel]
	local bait = BaitDefinitions[baitLevel]
	local rodLuck = rod and rod.luck or 0
	local baitLuck = bait and bait.luck or 0
	return rodLuck + baitLuck + (castLuckBonus or 0)
end

-- Compute zone bounds from a given center, matching FishingService lines 127-140.
local function computeZoneBounds(rodLevel, center)
	local rodDef = RodDefinitions[rodLevel]
	local perfectSize = (rodDef and rodDef.minigameZoneSize) or MiniGame.hitZoneWidth
	local goodSize = MiniGame.goodZoneWidth
	local halfGood = goodSize / 2
	local halfPerfect = perfectSize / 2
	return {
		goodStart = center - halfGood,
		goodEnd = center + halfGood,
		hitZoneStart = center - halfPerfect,
		hitZoneEnd = center + halfPerfect,
	}
end

-- Check if a bite submission is within the time window.
local function isWithinBiteWindow(elapsed)
	return elapsed <= BITE_WINDOW_SECONDS
end

-- ──────────────────────────────────────────────────────────────────────
-- Source contract helpers
-- ──────────────────────────────────────────────────────────────────────

local fishingSource = fs.readFile("src/server/FishingService.lua")
local gameConfigSource = fs.readFile("src/shared/GameConfig.lua")
local clientSource = fs.readFile("src/client/init.client.lua")

return function(describe, it, expect)
	-- ════════════════════════════════════════════════════════════════════
	-- Tier derivation
	-- ════════════════════════════════════════════════════════════════════
	describe("Tier derivation", function()
		it("classifies center of perfect zone as 'perfect'", function()
			local bounds = computeZoneBounds(1, 0.5)
			local tier = deriveTier(0.5, bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd)
			expect(tier).to.equal("perfect")
		end)

		it("classifies good-only zone (outside perfect) as 'good'", function()
			local bounds = computeZoneBounds(1, 0.5)
			-- 0.5 is perfect center; 0.30 is in good [0.25,0.75] but outside perfect [0.35,0.65]
			local tier = deriveTier(0.30, bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd)
			expect(tier).to.equal("good")
		end)

		it("classifies outside both zones as 'ok'", function()
			local bounds = computeZoneBounds(1, 0.5)
			local tier = deriveTier(0.05, bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd)
			expect(tier).to.equal("ok")
		end)

		it("inclusive boundary: exact hitZoneStart maps to 'perfect'", function()
			local bounds = computeZoneBounds(1, 0.5)
			local tier = deriveTier(bounds.hitZoneStart, bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd)
			expect(tier).to.equal("perfect")
		end)

		it("inclusive boundary: exact hitZoneEnd maps to 'perfect'", function()
			local bounds = computeZoneBounds(1, 0.5)
			local tier = deriveTier(bounds.hitZoneEnd, bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd)
			expect(tier).to.equal("perfect")
		end)

		it("inclusive boundary: exact goodStart maps to 'good'", function()
			local bounds = computeZoneBounds(1, 0.5)
			local tier = deriveTier(bounds.goodStart, bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd)
			expect(tier).to.equal("good")
		end)

		it("perfect zone is nested inside good zone for all rods", function()
			for _, rod in ipairs(RodDefinitions) do
				local center = 0.5
				local bounds = computeZoneBounds(rod.id, center)
				expect(bounds.hitZoneStart >= bounds.goodStart).to.equal(true)
				expect(bounds.hitZoneEnd <= bounds.goodEnd).to.equal(true)
			end
		end)

		it("perfect band is narrower than good band for all rods", function()
			for _, rod in ipairs(RodDefinitions) do
				local center = 0.5
				local bounds = computeZoneBounds(rod.id, center)
				local perfectWidth = bounds.hitZoneEnd - bounds.hitZoneStart
				local goodWidth = bounds.goodEnd - bounds.goodStart
				expect(perfectWidth < goodWidth).to.equal(true)
			end
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Accuracy clamping
	-- ════════════════════════════════════════════════════════════════════
	describe("Accuracy clamping", function()
		it("clamps values above 1 to 1", function()
			expect(clampAccuracy(1.5)).to.equal(1)
		end)

		it("clamps negative values to 0", function()
			expect(clampAccuracy(-0.5)).to.equal(0)
		end)

		it("preserves values in [0,1]", function()
			expect(clampAccuracy(0.0)).to.equal(0)
			expect(clampAccuracy(0.5)).to.equal(0.5)
			expect(clampAccuracy(1.0)).to.equal(1)
		end)

		it("replaces non-numbers with 0", function()
			expect(clampAccuracy(nil)).to.equal(0)
			expect(clampAccuracy("foo")).to.equal(0)
			expect(clampAccuracy(true)).to.equal(0)
		end)

		it("handles crafted extreme values (anti-exploit)", function()
			expect(clampAccuracy(99)).to.equal(1)
			expect(clampAccuracy(-99)).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Luck bonus mapping
	-- ════════════════════════════════════════════════════════════════════
	describe("Luck bonus mapping", function()
		it("perfect tier yields 25 luck bonus", function()
			expect(tierToLuckBonus("perfect")).to.equal(25)
		end)

		it("good tier yields 12 luck bonus", function()
			expect(tierToLuckBonus("good")).to.equal(12)
		end)

		it("ok tier yields 0 luck bonus", function()
			expect(tierToLuckBonus("ok")).to.equal(0)
		end)

		it("unknown tier defaults to 0", function()
			expect(tierToLuckBonus("amazing")).to.equal(0)
			expect(tierToLuckBonus(nil)).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Effective zone interpolation (DECISION C / TASK 14.24)
	-- ════════════════════════════════════════════════════════════════════
	describe("Effective zone interpolation", function()
		local ceiling = MiniGame.biteZoneCeiling
		local maxLuck = MiniGame.accuracyLuckBonus.perfect

		it("no luck bonus keeps base zone", function()
			local baseZone = 0.30
			expect(computeEffectiveZone(baseZone, 0, maxLuck, ceiling)).to.equal(baseZone)
		end)

		it("perfect luck inflates zone to ceiling", function()
			local baseZone = 0.30
			local luckBonus = MiniGame.accuracyLuckBonus.perfect
			local zone = computeEffectiveZone(baseZone, luckBonus, maxLuck, ceiling)
			expect(math.abs(zone - ceiling) <= 0.001).to.equal(true)
		end)

		it("good luck inflates zone partially", function()
			local baseZone = 0.30
			local luckBonus = MiniGame.accuracyLuckBonus.good
			local zone = computeEffectiveZone(baseZone, luckBonus, maxLuck, ceiling)
			-- good = 12, maxPerfect = 25, fraction = 12/25 = 0.48
			local expected = baseZone + 0.48 * (ceiling - baseZone)
			expect(math.abs(zone - expected) <= 0.001).to.equal(true)
			expect(zone < ceiling).to.equal(true)
			expect(zone > baseZone).to.equal(true)
		end)

		it("effective zone never exceeds ceiling", function()
			-- Even with inflated luck, clamp holds
			local zone = computeEffectiveZone(0.30, 999, maxLuck, ceiling)
			expect(zone).to.equal(ceiling)
		end)

		it("effective zone never drops below base zone", function()
			local zone = computeEffectiveZone(0.30, -5, maxLuck, ceiling)
			expect(zone).to.equal(0.30)
		end)

		it("base zone equals ceiling when maxLuck is 0 (degenerate)", function()
			local zone = computeEffectiveZone(0.85, 25, 0, ceiling)
			expect(zone).to.equal(0.85)
		end)

		it("perfect cast with Steel Rod (zone 0.35) reaches ceiling", function()
			local zone = computeEffectiveZone(0.35, MiniGame.accuracyLuckBonus.perfect, maxLuck, ceiling)
			expect(math.abs(zone - ceiling) <= 0.001).to.equal(true)
		end)

		it("perfect cast with Golden Rod (zone 0.40) reaches ceiling", function()
			local zone = computeEffectiveZone(0.40, MiniGame.accuracyLuckBonus.perfect, maxLuck, ceiling)
			expect(math.abs(zone - ceiling) <= 0.001).to.equal(true)
		end)

		it("ok cast keeps base for every rod", function()
			for _, rod in ipairs(RodDefinitions) do
				local zone = computeEffectiveZone(rod.minigameZoneSize, 0, maxLuck, ceiling)
				expect(zone).to.equal(rod.minigameZoneSize)
			end
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Luck stacking
	-- ════════════════════════════════════════════════════════════════════
	describe("Luck stacking", function()
		it("Basic Rod + Basic Bait + no cast bonus = 0 luck", function()
			expect(computeTotalLuck(1, 1, 0)).to.equal(0)
		end)

		it("Golden Rod + Magic Bait = 35 base luck", function()
			expect(computeTotalLuck(3, 3, 0)).to.equal(35)
		end)

		it("Basic Rod + perfect cast = 25 luck (cast bonus only)", function()
			expect(computeTotalLuck(1, 1, 25)).to.equal(25)
		end)

		it("Golden Rod + Magic Bait + perfect cast = 60 luck", function()
			expect(computeTotalLuck(3, 3, 25)).to.equal(60)
		end)

		it("Golden Rod + Magic Bait + good cast = 47 luck", function()
			expect(computeTotalLuck(3, 3, 12)).to.equal(47)
		end)

		it("nil cast bonus defaults to 0", function()
			expect(computeTotalLuck(1, 1, nil)).to.equal(0)
		end)

		it("invalid gear levels produce 0 gear luck", function()
			expect(computeTotalLuck(99, 99, 0)).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Bite window timing
	-- ════════════════════════════════════════════════════════════════════
	describe("Bite window timing", function()
		it("BITE_WINDOW_SECONDS is 3.5", function()
			expect(BITE_WINDOW_SECONDS).to.equal(3.5)
		end)

		it("elapsed within window is valid", function()
			expect(isWithinBiteWindow(0)).to.equal(true)
			expect(isWithinBiteWindow(3.0)).to.equal(true)
			expect(isWithinBiteWindow(3.5)).to.equal(true)
		end)

		it("elapsed beyond window is too slow", function()
			expect(isWithinBiteWindow(3.51)).to.equal(false)
			expect(isWithinBiteWindow(5.0)).to.equal(false)
			expect(isWithinBiteWindow(10.0)).to.equal(false)
		end)

		it("boundary is inclusive (exactly 3.5 is valid)", function()
			expect(isWithinBiteWindow(3.5)).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Zone bounds computation
	-- ════════════════════════════════════════════════════════════════════
	describe("Zone bounds computation", function()
		it("good zone width is 0.5 for all rods", function()
			for _, rod in ipairs(RodDefinitions) do
				local bounds = computeZoneBounds(rod.id, 0.5)
				local width = bounds.goodEnd - bounds.goodStart
				expect(math.abs(width - 0.5) <= 0.001).to.equal(true)
			end
		end)

		it("perfect zone width varies by rod (wider for better rods)", function()
			local w1 = computeZoneBounds(1, 0.5)
			local w3 = computeZoneBounds(3, 0.5)
			local perfectW1 = w1.hitZoneEnd - w1.hitZoneStart
			local perfectW3 = w3.hitZoneEnd - w3.hitZoneStart
			expect(perfectW3 > perfectW1).to.equal(true)
		end)

		it("zone center range keeps good zone inside [0,1]", function()
			-- The center is randomized in [halfGood, 1-halfGood]
			local halfGood = MiniGame.goodZoneWidth / 2
			local center = halfGood -- minimum valid center
			local bounds = computeZoneBounds(1, center)
			expect(bounds.goodStart >= 0).to.equal(true)
			expect(bounds.goodEnd <= 1).to.equal(true)
		end)

		it("Basic Rod perfect zone uses fallback hitZoneWidth", function()
			-- Basic Rod minigameZoneSize = 0.30, which equals hitZoneWidth
			local bounds = computeZoneBounds(1, 0.5)
			local perfectWidth = bounds.hitZoneEnd - bounds.hitZoneStart
			expect(math.abs(perfectWidth - 0.30) <= 0.001).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract verification
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract verification", function()
		it("FishingService uses tier derivation with inclusive bounds", function()
			expect(fishingSource:find("accuracy >= biteData.hitZoneStart and accuracy <= biteData.hitZoneEnd", 1, true)).to.be.a("number")
		end)

		it("FishingService maps tier to luckBonus from GameConfig", function()
			expect(fishingSource:find("GameConfig.MiniGame.accuracyLuckBonus[tier]", 1, true)).to.be.a("number")
		end)

		it("FishingService clamps accuracy to [0,1]", function()
			expect(fishingSource:find("math.clamp(accuracy, 0, 1)", 1, true)).to.be.a("number")
		end)

		it("FishingService computes effective zone with base-to-ceiling interpolation", function()
			expect(fishingSource:find("baseZone + (luckBonus / maxLuck) * (ceiling - baseZone)", 1, true)).to.be.a("number")
		end)

		it("FishingService clamps effective zone to [baseZone, ceiling]", function()
			expect(fishingSource:find("math.clamp(effectiveZone, baseZone, ceiling)", 1, true)).to.be.a("number")
		end)

		it("FishingService luck stacks rod + bait + cast bonus", function()
			expect(fishingSource:find("rod.luck + bait.luck", 1, true)).to.be.a("number")
		end)

		it("FishingService bite timing uses BITE_WINDOW_SECONDS", function()
			expect(fishingSource:find("BITE_WINDOW_SECONDS", 1, true)).to.be.a("number")
		end)

		it("FishingService uses Random.new (not math.random)", function()
			expect(fishingSource:find("Random.new()", 1, true)).to.be.a("number")
			expect(fishingSource:find("math.random", 1, true)).to.equal(nil)
		end)

		it("FishingService uses rng:NextNumber for re-roll", function()
			expect(fishingSource:find("rng:NextNumber()", 1, true)).to.be.a("number")
		end)

		it("GameConfig.MiniGame.hitZoneWidth is 0.3", function()
			expect(gameConfigSource:find("hitZoneWidth = 0.3", 1, true)).to.be.a("number")
		end)

		it("GameConfig.MiniGame.goodZoneWidth is 0.5", function()
			expect(gameConfigSource:find("goodZoneWidth = 0.5", 1, true)).to.be.a("number")
		end)

		it("GameConfig.MiniGame.biteZoneCeiling is 0.85", function()
			expect(gameConfigSource:find("biteZoneCeiling = 0.85", 1, true)).to.be.a("number")
		end)

		it("GameConfig.MiniGame.accuracyLuckBonus: perfect=25, good=12, ok=0", function()
			expect(gameConfigSource:find("perfect = 25", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("good = 12", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("ok = 0", 1, true)).to.be.a("number")
		end)

		it("FishingService exposes _setRng test seam", function()
			expect(fishingSource:find("_setRng", 1, true)).to.be.a("number")
		end)

		it("FishingService exposes _activeBites test seam", function()
			expect(fishingSource:find("_activeBites", 1, true)).to.be.a("number")
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract: a2ug.6 discovery toast suppression + NEW DISCOVERY ribbon
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract: a2ug.6 discovery suppression + ribbon", function()
		it("FishingService tracks session.catchesThisSession", function()
			expect(fishingSource:find("session.catchesThisSession = (session.catchesThisSession or 0) + 1", 1, true)).to.be.a("number")
		end)

		it("FishingService computes isNewDiscovery before setting collection", function()
			expect(fishingSource:find("local isNewDiscovery = not session.profile.Collection.DiscoveredSpecies", 1, true)).to.be.a("number")
		end)

		it("FishingService has cardEligible suppression check", function()
			expect(fishingSource:find("local cardEligible", 1, true)).to.be.a("number")
			expect(fishingSource:find("if not cardEligible then", 1, true)).to.be.a("number")
		end)

		it("FishingService cardEligible mirrors client condition (Rare+ OR first catch)", function()
			expect(fishingSource:find('fish.Rarity == "Rare" or fish.Rarity == "Epic" or fish.Rarity == "Legendary" or session.catchesThisSession == 1', 1, true)).to.be.a("number")
		end)

		it("FishingService return includes isNewDiscovery", function()
			expect(fishingSource:find("isNewDiscovery = isNewDiscovery or nil", 1, true)).to.be.a("number")
		end)

		it("FishingService discovery toast only fires inside not-cardEligible branch", function()
			expect(fishingSource:find("if not cardEligible then\n\t\t\t\tremotes.notify", 1, true)).to.be.a("number")
		end)

		it("client showRevealCard accepts isNew parameter", function()
			expect(clientSource:find("local function showRevealCard(speciesId, rarity, value, isNew)", 1, true)).to.be.a("number")
		end)

		it("client passes result.isNewDiscovery to showRevealCard", function()
			expect(clientSource:find("showRevealCard(result.speciesId, rarity, result.value, result.isNewDiscovery)", 1, true)).to.be.a("number")
		end)

		it("client renders NEW DISCOVERY ribbon text", function()
			expect(clientSource:find('"NEW DISCOVERY"', 1, true)).to.be.a("number")
		end)

		it("client uses UIPalette discovery gold for ribbon", function()
			expect(clientSource:find('UIPalette.color("discovery")', 1, true)).to.be.a("number")
		end)

		it("client has contentYOffset for layout shift", function()
			expect(clientSource:find("local contentYOffset = isNew and 10 or 0", 1, true)).to.be.a("number")
		end)
	end)
end
