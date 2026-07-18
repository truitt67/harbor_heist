--[[
	FishDefinitions.lua — Static fish species catalog for Harbor Heist.

	Each species has a SpeciesId, DisplayName, Rarity, ZoneIds, BaseSellValue,
	IncomePerMinute, CatchWeight, ModelId, and CollectionOrder.

	15 species across 5 rarity tiers and 2 zones (StarterPier, DeepWater).
	Common species are weighted heavily; Legendary are rare. Income and sell
	values scale exponentially with rarity to make progression feel rewarding.
]]

local FishDefinitions = {}

FishDefinitions.Species = {
	-- ══════════════════════════════════════════════════════════════════════
	-- COMMON (weight ~55 total) — StarterPier only
	-- ══════════════════════════════════════════════════════════════════════
	Bluegill = {
		SpeciesId = "Bluegill",
		DisplayName = "Bluegill",
		Rarity = "Common",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 15,
		IncomePerMinute = 1,
		CatchWeight = 30,
		ModelId = "Fish_Bluegill",
		CollectionOrder = 1,
	},

	Perch = {
		SpeciesId = "Perch",
		DisplayName = "Yellow Perch",
		Rarity = "Common",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 12,
		IncomePerMinute = 1,
		CatchWeight = 25,
		ModelId = "Fish_Perch",
		CollectionOrder = 2,
	},

	Sardine = {
		SpeciesId = "Sardine",
		DisplayName = "Sardine",
		Rarity = "Common",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 8,
		IncomePerMinute = 0.5,
		CatchWeight = 20,
		ModelId = "Fish_Sardine",
		CollectionOrder = 3,
	},

	-- ══════════════════════════════════════════════════════════════════════
	-- UNCOMMON (weight ~25 total) — StarterPier
	-- ══════════════════════════════════════════════════════════════════════
	Mackerel = {
		SpeciesId = "Mackerel",
		DisplayName = "Mackerel",
		Rarity = "Uncommon",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 30,
		IncomePerMinute = 3,
		CatchWeight = 15,
		ModelId = "Fish_Mackerel",
		CollectionOrder = 4,
	},

	Trout = {
		SpeciesId = "Trout",
		DisplayName = "Rainbow Trout",
		Rarity = "Uncommon",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 35,
		IncomePerMinute = 3.5,
		CatchWeight = 12,
		ModelId = "Fish_Trout",
		CollectionOrder = 5,
	},

	Bass = {
		SpeciesId = "Bass",
		DisplayName = "Largemouth Bass",
		Rarity = "Uncommon",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 40,
		IncomePerMinute = 4,
		CatchWeight = 10,
		ModelId = "Fish_Bass",
		CollectionOrder = 6,
	},

	-- ══════════════════════════════════════════════════════════════════════
	-- RARE (weight ~12 total) — StarterPier + DeepWater
	-- ══════════════════════════════════════════════════════════════════════
	Snapper = {
		SpeciesId = "Snapper",
		DisplayName = "Red Snapper",
		Rarity = "Rare",
		ZoneIds = { "StarterPier", "DeepWater" },
		BaseSellValue = 80,
		IncomePerMinute = 8,
		CatchWeight = 8,
		ModelId = "Fish_Snapper",
		CollectionOrder = 7,
	},

	Grouper = {
		SpeciesId = "Grouper",
		DisplayName = "Goliath Grouper",
		Rarity = "Rare",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 95,
		IncomePerMinute = 9,
		CatchWeight = 6,
		ModelId = "Fish_Grouper",
		CollectionOrder = 8,
	},

	Tuna = {
		SpeciesId = "Tuna",
		DisplayName = "Bluefin Tuna",
		Rarity = "Rare",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 110,
		IncomePerMinute = 10,
		CatchWeight = 5,
		ModelId = "Fish_Tuna",
		CollectionOrder = 9,
	},

	-- ══════════════════════════════════════════════════════════════════════
	-- EPIC (weight ~6 total) — DeepWater only
	-- ══════════════════════════════════════════════════════════════════════
	Swordfish = {
		SpeciesId = "Swordfish",
		DisplayName = "Swordfish",
		Rarity = "Epic",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 200,
		IncomePerMinute = 20,
		CatchWeight = 4,
		ModelId = "Fish_Swordfish",
		CollectionOrder = 10,
	},

	Marlin = {
		SpeciesId = "Marlin",
		DisplayName = "Blue Marlin",
		Rarity = "Epic",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 250,
		IncomePerMinute = 25,
		CatchWeight = 3,
		ModelId = "Fish_Marlin",
		CollectionOrder = 11,
	},

	Sturgeon = {
		SpeciesId = "Sturgeon",
		DisplayName = "Ancient Sturgeon",
		Rarity = "Epic",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 300,
		IncomePerMinute = 30,
		CatchWeight = 2,
		ModelId = "Fish_Sturgeon",
		CollectionOrder = 12,
	},

	-- ══════════════════════════════════════════════════════════════════════
	-- LEGENDARY (weight ~2 total) — DeepWater only
	-- ══════════════════════════════════════════════════════════════════════
	GoldenKoi = {
		SpeciesId = "GoldenKoi",
		DisplayName = "Golden Koi",
		Rarity = "Legendary",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 600,
		IncomePerMinute = 60,
		CatchWeight = 1,
		ModelId = "Fish_GoldenKoi",
		CollectionOrder = 13,
	},

	AbyssalEel = {
		SpeciesId = "AbyssalEel",
		DisplayName = "Abyssal Eel",
		Rarity = "Legendary",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 750,
		IncomePerMinute = 75,
		CatchWeight = 1,
		ModelId = "Fish_AbyssalEel",
		CollectionOrder = 14,
	},

	HarborKing = {
		SpeciesId = "HarborKing",
		DisplayName = "The Harbor King",
		Rarity = "Legendary",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 1000,
		IncomePerMinute = 100,
		CatchWeight = 0.5,
		ModelId = "Fish_HarborKing",
		CollectionOrder = 15,
	},
}

-- Quick lookup: rarity name -> list of species in that rarity
FishDefinitions.ByRarity = {}
for id, def in pairs(FishDefinitions.Species) do
	local r = def.Rarity
	if not FishDefinitions.ByRarity[r] then
		FishDefinitions.ByRarity[r] = {}
	end
	table.insert(FishDefinitions.ByRarity[r], def)
end

-- Quick lookup: zone id -> list of species in that zone
FishDefinitions.ByZone = {}
for id, def in pairs(FishDefinitions.Species) do
	for _, zoneId in ipairs(def.ZoneIds) do
		if not FishDefinitions.ByZone[zoneId] then
			FishDefinitions.ByZone[zoneId] = {}
		end
		table.insert(FishDefinitions.ByZone[zoneId], def)
	end
end

function FishDefinitions.get(speciesId)
	local def = FishDefinitions.Species[speciesId]
	if not def then
		error("[FishDefinitions] Unknown species: " .. tostring(speciesId))
	end
	return def
end

-- Rarity ordinal for luck weighting (higher = rarer)
local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
-- Export so consumers (CollectionService, etc.) share ONE source of truth
-- instead of hardcoding a duplicate copy that could silently diverge.
FishDefinitions.RARITY_ORDER = RARITY_ORDER

--[[
	Weighted random species pick within a zone.
	luck (optional, rod+bait) multiplies each species' CatchWeight by
	(1 + luck/100 * (rarityOrder - 1)) — luck 0 leaves weights untouched,
	higher luck progressively favors rarer species (same curve as
	GameConfig.rollRarity but applied to the species table).
]]
function FishDefinitions.getRandomInZone(zoneId, rng, luck)
	local pool = FishDefinitions.ByZone[zoneId]
	if not pool or #pool == 0 then
		return nil
	end
	luck = luck or 0
	local total = 0
	local weights = {}
	for i, def in ipairs(pool) do
		local w = def.CatchWeight * (1 + (luck / 100) * ((RARITY_ORDER[def.Rarity] or 1) - 1))
		weights[i] = w
		total += w
	end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local acc = 0
	for i, def in ipairs(pool) do
		acc += weights[i]
		if roll <= acc then
			return def
		end
	end
	return pool[1]
end

return FishDefinitions
