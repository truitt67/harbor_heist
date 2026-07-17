--[[
	ZoneDefinitions.lua — Fishing zone definitions for Harbor Heist.

	Each zone has a ZoneId, DisplayName, required rod level to access,
	and a visual style. Zones gate progression: better rods unlock
	better fishing spots with rarer fish.

	The fish tables themselves live in FishDefinitions.ByZone.
]]

local ZoneDefinitions = {}

ZoneDefinitions.Zones = {
	StarterPier = {
		ZoneId = "StarterPier",
		DisplayName = "Starter Pier",
		RequiredRodLevel = 1,
		Description = "Calm waters near the dock. Common and Uncommon fish.",
		Color = Color3.fromRGB(80, 200, 255),
	},

	DeepWater = {
		ZoneId = "DeepWater",
		DisplayName = "Deep Water",
		RequiredRodLevel = 2,
		Description = "Deeper waters with stronger currents. Rare, Epic, and Legendary fish.",
		Color = Color3.fromRGB(30, 80, 180),
	},
}

function ZoneDefinitions.get(zoneId)
	local zone = ZoneDefinitions.Zones[zoneId]
	if not zone then
		error("[ZoneDefinitions] Unknown zone: " .. tostring(zoneId))
	end
	return zone
end

function ZoneDefinitions.canAccess(zoneId, rodLevel)
	local zone = ZoneDefinitions.get(zoneId)
	return rodLevel >= zone.RequiredRodLevel
end

function ZoneDefinitions.getZonesForRod(rodLevel)
	local accessible = {}
	for zoneId, zone in pairs(ZoneDefinitions.Zones) do
		if rodLevel >= zone.RequiredRodLevel then
			table.insert(accessible, zone)
		end
	end
	return accessible
end

return ZoneDefinitions
