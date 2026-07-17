--[[
	FishDefinitions.lua — Static fish species catalog for Harbor Heist.

	Each species has a SpeciesId, DisplayName, Rarity, ZoneIds, BaseSellValue,
	IncomePerMinute, CatchWeight, ModelId, and CollectionOrder.

	This is a MINIMAL stub (one species per rarity) created to unblock
	TASK 1.2 (FishInstance). TASK 2.1 will expand this to the full
	12-20 species catalog across starter and upgraded zones.
]]

local FishDefinitions = {}

FishDefinitions.Species = {
	Bluegill = {
		SpeciesId = "Bluegill",
		DisplayName = "Bluegill",
		Rarity = "Common",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 15,
		IncomePerMinute = 1,
		CatchWeight = 60,
		ModelId = "Fish_Bluegill",
		CollectionOrder = 1,
	},

	Mackerel = {
		SpeciesId = "Mackerel",
		DisplayName = "Mackerel",
		Rarity = "Uncommon",
		ZoneIds = { "StarterPier" },
		BaseSellValue = 30,
		IncomePerMinute = 3,
		CatchWeight = 25,
		ModelId = "Fish_Mackerel",
		CollectionOrder = 2,
	},

	Snapper = {
		SpeciesId = "Snapper",
		DisplayName = "Red Snapper",
		Rarity = "Rare",
		ZoneIds = { "StarterPier", "DeepWater" },
		BaseSellValue = 80,
		IncomePerMinute = 8,
		CatchWeight = 12,
		ModelId = "Fish_Snapper",
		CollectionOrder = 3,
	},

	Swordfish = {
		SpeciesId = "Swordfish",
		DisplayName = "Swordfish",
		Rarity = "Epic",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 200,
		IncomePerMinute = 20,
		CatchWeight = 6,
		ModelId = "Fish_Swordfish",
		CollectionOrder = 4,
	},

	GoldenKoi = {
		SpeciesId = "GoldenKoi",
		DisplayName = "Golden Koi",
		Rarity = "Legendary",
		ZoneIds = { "DeepWater" },
		BaseSellValue = 600,
		IncomePerMinute = 60,
		CatchWeight = 2,
		ModelId = "Fish_GoldenKoi",
		CollectionOrder = 5,
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

function FishDefinitions.getRandomInZone(zoneId, rng)
	local pool = FishDefinitions.ByZone[zoneId]
	if not pool or #pool == 0 then
		return nil
	end
	local total = 0
	for _, def in ipairs(pool) do
		total += def.CatchWeight
	end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local acc = 0
	for _, def in ipairs(pool) do
		acc += def.CatchWeight
		if roll <= acc then
			return def
		end
	end
	return pool[1]
end

return FishDefinitions
