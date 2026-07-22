--[[
	FishInstance.lua — Individual fish record factory and validator.

	Each caught fish becomes a FishInstance with a unique server-generated ID,
	species reference, sell value, income rate, catch timestamp, source zone,
	and raid protection flag. These records enable per-fish selling, raid theft,
	collection tracking, and aquarium display selection.

	Replaces the old system where fish were bare rarity indexes (integers).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FishDefinitions = require(ReplicatedStorage.Shared.FishDefinitions)

local FishInstance = {}

--[[
	Creates a new FishInstance from a species ID and source zone.

	@param speciesId string — key into FishDefinitions.Species
	@param sourceZoneId string — zone where caught (e.g. "StarterPier")
	@return FishInstance — validated record
]]
function FishInstance.new(speciesId, sourceZoneId)
	local def = FishDefinitions.get(speciesId) -- throws on invalid speciesId

	return {
		InstanceId = HttpService:GenerateGUID(false),
		SpeciesId = def.SpeciesId,
		Rarity = def.Rarity,
		BaseSellValue = def.BaseSellValue,
		IncomePerMinute = def.IncomePerMinute,
		CaughtAtTimestamp = os.time(),
		SourceZoneId = sourceZoneId or "Unknown",
		IsRaidProtected = (def.Rarity == "Legendary"),
	}
end

--[[
	Validates a FishInstance record's fields. Returns true if valid, false otherwise.
	Used by sanitize() to filter corrupted data.
]]
function FishInstance.validate(record)
	if type(record) ~= "table" then
		return false
	end
	if type(record.InstanceId) ~= "string" or #record.InstanceId == 0 then
		return false
	end
	if type(record.SpeciesId) ~= "string" then
		return false
	end
	-- Verify species exists in definitions
	local ok = pcall(FishDefinitions.get, record.SpeciesId)
	if not ok then
		return false
	end
	if type(record.Rarity) ~= "string" then
		return false
	end
	if type(record.BaseSellValue) ~= "number" or record.BaseSellValue < 0 then
		return false
	end
	if type(record.IncomePerMinute) ~= "number" or record.IncomePerMinute < 0 then
		return false
	end
	if type(record.CaughtAtTimestamp) ~= "number" then
		return false
	end
	if type(record.SourceZoneId) ~= "string" then
		return false
	end
	if type(record.IsRaidProtected) ~= "boolean" then
		return false
	end
	return true
end

--[[
	Creates a FishInstance from a legacy rarity index (for migration).
	Picks a random species matching that rarity tier (TASK 14.12: randomized so v1->v2 migration preserves species variety instead of collapsing to the first species in each bucket).
]]
function FishInstance.fromRarityIndex(rarityIndex)
	-- Deliberately hardcoded, NOT derived from GameConfig.Rarities: v1 records
	-- were stamped with the v1 ordinal semantics (1=Common..5=Legendary) and
	-- stay that way forever. Deriving this from live config would silently
	-- mis-map un-migrated v1 fish after any future rarity reorder/rename.
	local rarityNames = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
	local rarityName = rarityNames[rarityIndex]
	if not rarityName then
		rarityName = "Common"
	end
	local pool = FishDefinitions.ByRarity[rarityName]
	if not pool or #pool == 0 then
		pool = FishDefinitions.ByRarity["Common"]
	end
	local def = pool[math.random(1, #pool)]
	return FishInstance.new(def.SpeciesId, "Migration")
end

return FishInstance
