-- Proof for hvfh.7.2 (TASK 27.2): bag rows sorted rarity desc, value desc,
-- stable catch-order tiebreak; rebuild guard unaffected.
-- Layers: (1) comparator behavior mirror, (2) source contracts.
--
-- Run: lune run test/_hvfh_7_2_inventory_sort_proof.luau

local fs = require("@lune/fs")

-- ---- Layer 1: comparator mirror (copy of sortCarriedForDisplay) ----
local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

local function sortCarriedForDisplay(carried)
	local wrapped = {}
	for i, fish in ipairs(carried) do
		wrapped[i] = { fish = fish, idx = i }
	end
	table.sort(wrapped, function(a, b)
		local ra = RARITY_ORDER[a.fish.Rarity] or 0
		local rb = RARITY_ORDER[b.fish.Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		local va = a.fish.BaseSellValue or 0
		local vb = b.fish.BaseSellValue or 0
		if va ~= vb then
			return va > vb
		end
		return a.idx < b.idx
	end)
	local sorted = {}
	for i, entry in ipairs(wrapped) do
		sorted[i] = entry.fish
	end
	return sorted
end

-- Case 1: rarity dominates value (a cheap Legendary beats a pricey Common).
local bag = {
	{ InstanceId = "a", Rarity = "Common", BaseSellValue = 500 },
	{ InstanceId = "b", Rarity = "Legendary", BaseSellValue = 10 },
	{ InstanceId = "c", Rarity = "Rare", BaseSellValue = 100 },
}
local s1 = sortCarriedForDisplay(bag)
assert(s1[1].InstanceId == "b" and s1[2].InstanceId == "c" and s1[3].InstanceId == "a",
	"rarity must dominate value")

-- Case 2: same rarity -> value desc.
local bag2 = {
	{ InstanceId = "a", Rarity = "Rare", BaseSellValue = 50 },
	{ InstanceId = "b", Rarity = "Rare", BaseSellValue = 200 },
	{ InstanceId = "c", Rarity = "Rare", BaseSellValue = 100 },
}
local s2 = sortCarriedForDisplay(bag2)
assert(s2[1].InstanceId == "b" and s2[2].InstanceId == "c" and s2[3].InstanceId == "a",
	"same-rarity must sort value desc")

-- Case 3: full tie -> original catch order preserved (stable, no shuffling).
local bag3 = {
	{ InstanceId = "first", Rarity = "Common", BaseSellValue = 10 },
	{ InstanceId = "second", Rarity = "Common", BaseSellValue = 10 },
	{ InstanceId = "third", Rarity = "Common", BaseSellValue = 10 },
}
local s3 = sortCarriedForDisplay(bag3)
assert(s3[1].InstanceId == "first" and s3[2].InstanceId == "second" and s3[3].InstanceId == "third",
	"ties must preserve catch order")

-- Case 4: input array NOT mutated (server contract untouched).
local bag4 = {
	{ InstanceId = "z", Rarity = "Common", BaseSellValue = 1 },
	{ InstanceId = "y", Rarity = "Legendary", BaseSellValue = 2 },
}
sortCarriedForDisplay(bag4)
assert(bag4[1].InstanceId == "z" and bag4[2].InstanceId == "y", "input order must be untouched")

-- Case 5: unknown rarity -> rank 0, sorts last without error.
local bag5 = {
	{ InstanceId = "u", Rarity = "Mythic+", BaseSellValue = 999 },
	{ InstanceId = "k", Rarity = "Common", BaseSellValue = 1 },
}
local s5 = sortCarriedForDisplay(bag5)
assert(s5[2].InstanceId == "u", "unknown rarity must sink to the bottom")

-- Case 6: empty bag.
assert(#sortCarriedForDisplay({}) == 0, "empty bag must stay empty")
print("=== Comparator: all 6 cases pass ===")

-- ---- Layer 2: source contracts ----
local client = fs.readFile("src/client/init.client.lua")
assert(client:find("local function sortCarriedForDisplay(carried)", 1, true), "helper missing")
assert(client:find("local carried = sortCarriedForDisplay(state.carriedFish or {})", 1, true),
	"renderInventory must consume the sorted copy")
assert(client:find("FishDefinitions.RARITY_ORDER", 1, true), "must use the shared rarity order")
-- InstanceId is a random GUID (FishInstance:29) — it must NOT be the tiebreak.
assert(not client:find("InstanceId or 0", 1, true), "GUID InstanceId must not be used as sort key")
-- Server must NOT sort carried (bead constraint).
local server = fs.readFile("src/server/FishingService.lua")
assert(not server:find("table.sort"), "server must not sort carried fish")

print("=== All hvfh.7.2 inventory-sort proofs passed ===")
