local GameConfig = {}

GameConfig.Rarities = {
	{ name = "Common",    weight = 55, value = 10,  incomePerSec = 0.2, color = Color3.fromRGB(190, 190, 190) },
	{ name = "Uncommon",  weight = 25, value = 25,  incomePerSec = 0.6, color = Color3.fromRGB(85, 200, 120) },
	{ name = "Rare",      weight = 12, value = 70,  incomePerSec = 1.8, color = Color3.fromRGB(70, 140, 255) },
	{ name = "Epic",      weight = 6,  value = 180, incomePerSec = 5,   color = Color3.fromRGB(170, 85, 255) },
	{ name = "Legendary", weight = 2,  value = 500, incomePerSec = 15,  color = Color3.fromRGB(255, 170, 0) },
}

GameConfig.Rods = {
	{ name = "Basic Rod",  cost = 0,    luck = 0,  castTime = 4, desc = "A trusty starter rod." },
	{ name = "Steel Rod",  cost = 500,  luck = 8,  castTime = 3, desc = "+Luck, faster casts." },
	{ name = "Golden Rod", cost = 2500, luck = 20, castTime = 2, desc = "++Luck, fastest casts." },
}

GameConfig.Baits = {
	{ name = "Basic Bait",  cost = 0,    luck = 0,  desc = "Plain old worms." },
	{ name = "Shrimp Bait", cost = 300,  luck = 6,  desc = "Rarer fish love shrimp." },
	{ name = "Magic Bait",  cost = 1500, luck = 15, desc = "Glows with legendary promise." },
}

GameConfig.Aquarium = {
	baseCapacity = 20,
	lockDuration = 60,
	lockCooldown = 120,
	stealChance = 0.5,
	stealCooldown = 20,
	maxVisibleFish = 10,
}

GameConfig.MaxCarried = 5
GameConfig.IncomeTickSeconds = 1
GameConfig.StartingCash = 0
GameConfig.DockCount = 8

function GameConfig.rollRarity(luck, rng)
	local total = 0
	local weights = {}
	for i, rarity in ipairs(GameConfig.Rarities) do
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

return GameConfig
