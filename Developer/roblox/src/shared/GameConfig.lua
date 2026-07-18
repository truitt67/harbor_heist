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

GameConfig.Upgrades = {
	Capacity = {
		{ name = "Capacity I", cost = 300,  capacity = 30, desc = "Expand aquarium to 30 fish" },
		{ name = "Capacity II", cost = 800,  capacity = 45, desc = "Expand aquarium to 45 fish" },
		{ name = "Capacity III", cost = 2000, capacity = 60, desc = "Expand aquarium to 60 fish" },
	},
	Lock = {
		{ name = "Lock I",   cost = 400,  lockDuration = 90,  lockCooldown = 90, desc = "Lock 90s, recharge 90s" },
		{ name = "Lock II",  cost = 1200, lockDuration = 120, lockCooldown = 60, desc = "Lock 120s, recharge 60s" },
		{ name = "Lock III", cost = 3000, lockDuration = 150, lockCooldown = 30, desc = "Lock 150s, recharge 30s" },
	},
	Alarm = {
		{ name = "Alarm I",   cost = 500,  stunDuration = 3, notifyChance = 1.0, desc = "Notify on theft, stun thief 3s" },
		{ name = "Alarm II",  cost = 1500, stunDuration = 5, notifyChance = 1.0, desc = "Notify on theft, stun thief 5s" },
		{ name = "Alarm III", cost = 4000, stunDuration = 8, notifyChance = 1.0, desc = "Notify on theft, stun thief 8s" },
	},
}

GameConfig.MiniGame = {
	hitZoneWidth = 0.3,
	goodZoneWidth = 0.5,
	accuracyLuckBonus = {
		perfect = 25,
		good = 12,
		ok = 0,
	},
}

GameConfig.Quests = {
	DailySlots = 3,
	WeeklySlots = 2,
}

GameConfig.Boat = {
	despawnDelay = 10,
}

GameConfig.MaxCarried = 5
GameConfig.IncomeTickSeconds = 1
GameConfig.StartingCash = 0
GameConfig.DockCount = 8

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 2.3: Expanded Rod Definitions
-- ════════════════════════════════════════════════════════════════════════════
GameConfig.RodDefinitions = {
	{ id = 1, name = "Basic Rod",  cost = 0,    luck = 0,  castTime = 4, minigameZoneSize = 0.30, desc = "A trusty starter rod." },
	{ id = 2, name = "Steel Rod",  cost = 500,  luck = 8,  castTime = 3, minigameZoneSize = 0.35, desc = "+Luck, faster casts, wider target." },
	{ id = 3, name = "Golden Rod", cost = 2500, luck = 20, castTime = 2, minigameZoneSize = 0.40, desc = "++Luck, fastest casts, widest target." },
}

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 2.4: Bait Definitions (reusable tiers per DEC-5)
-- ════════════════════════════════════════════════════════════════════════════
GameConfig.BaitDefinitions = {
	{ id = 1, name = "Basic Bait",  cost = 0,    luck = 0,  desc = "Plain old worms." },
	{ id = 2, name = "Shrimp Bait", cost = 300,  luck = 6,  desc = "Rarer fish love shrimp." },
	{ id = 3, name = "Magic Bait",  cost = 1500, luck = 15, desc = "Glows with legendary promise." },
}

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 2.5: Aquarium Capacity Upgrade Tiers
-- ════════════════════════════════════════════════════════════════════════════
GameConfig.AquariumUpgradeTiers = {
	{ level = 1, name = "Starter Tank",  capacity = 20,  cost = 0,    incomeMultiplier = 1.0,  desc = "Base aquarium" },
	{ level = 2, name = "Expanded Tank", capacity = 35,  cost = 800,  incomeMultiplier = 1.1,  desc = "+75% capacity, +10% income" },
	{ level = 3, name = "Large Tank",    capacity = 50,  cost = 3000, incomeMultiplier = 1.25, desc = "+150% capacity, +25% income" },
	{ level = 4, name = "Mega Tank",     capacity = 75,  cost = 8000, incomeMultiplier = 1.5,  desc = "+275% capacity, +50% income" },
}

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 2.6: Dock Upgrade Tiers
-- ════════════════════════════════════════════════════════════════════════════
GameConfig.DockUpgradeTiers = {
	{ level = 1, name = "Basic Dock",         cost = 0,     incomeMultiplier = 1.0,  cosmeticUnlocks = {},                                        desc = "Your starting dock" },
	{ level = 2, name = "Lamp-Lit Dock",      cost = 1200,  incomeMultiplier = 1.15, cosmeticUnlocks = { "LampPost" },                            desc = "+15% income, adds lamp posts" },
	{ level = 3, name = "Garden Dock",        cost = 4000,  incomeMultiplier = 1.35, cosmeticUnlocks = { "LampPost", "Planters" },                desc = "+35% income, adds planters" },
	{ level = 4, name = "Golden Harbor Dock", cost = 10000, incomeMultiplier = 1.6,  cosmeticUnlocks = { "LampPost", "Planters", "GoldenTrim" },  desc = "+60% income, golden trim" },
}

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 2.7: Economy Config — cost curves and balance
-- ════════════════════════════════════════════════════════════════════════════
GameConfig.Economy = {
	-- First meaningful purchase should be achievable in first session
	-- Basic Rod is free, Steel Rod at 500 is the first target
	-- A player catching Common fish (15) + storing for income should
	-- reach 500 in ~5-10 minutes of active play
	FirstUpgradeTarget = 500,
	-- Income tuning: stored fish generate this fraction of their sell value per minute
	IncomeToValueRatio = 0.05,
	-- Maximum unclaimed income before auto-claim kicks in (prevents extreme accumulation)
	MaxUnclaimedIncome = 50000,
}

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
