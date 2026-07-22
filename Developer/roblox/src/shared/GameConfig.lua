local GameConfig = {}

GameConfig.Rarities = {
	-- R2.2 (dt9.2): incomePerSec field REMOVED — was dead config that
	-- disagreed with FishDefinitions.Species[].IncomePerMinute (the live
	-- income source) by 12-18x. The client aquarium rarity breakdown no
	-- longer displays per-rarity income/sec; the total incomePerSec from
	-- StateSync.snapshot (the authoritative, multiplier-aware value) is
	-- shown at the top of the panel instead.
	{ name = "Common",    weight = 55, value = 10,  color = Color3.fromRGB(190, 190, 190) },
	{ name = "Uncommon",  weight = 25, value = 25,  color = Color3.fromRGB(85, 200, 120) },
	{ name = "Rare",      weight = 12, value = 70,  color = Color3.fromRGB(70, 140, 255) },
	{ name = "Epic",      weight = 6,  value = 180, color = Color3.fromRGB(170, 85, 255) },
	{ name = "Legendary", weight = 2,  value = 500, color = Color3.fromRGB(255, 170, 0) },
}

-- TASK 14.10 (wqw.10): the legacy Rods/Baits tables were REMOVED. They
-- duplicated RodDefinitions/BaitDefinitions (below) minus the id and
-- minigameZoneSize fields — two sources of truth that could silently
-- diverge. RodDefinitions/BaitDefinitions are canonical; Rods/Baits are
-- aliases defined next to them so every existing GameConfig.Rods[level]
-- / GameConfig.Baits[level] access keeps working (same array layout).

GameConfig.Aquarium = {
	baseCapacity = 20,
	lockDuration = 60,
	lockCooldown = 120,
	-- TASK 8.0 (gdj.15): stealChance + stealCooldown REMOVED with the legacy
	-- always-on steal handler. Raid tuning moves into RaidService config
	-- (Epic 8).
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
	-- TASK 14.24 (DECISION C): ceiling for the bite catch zone after the
	-- server-authoritative cast-accuracy luckBonus inflates it. A PERFECT cast
	-- (luckBonus == accuracyLuckBonus.perfect) raises the effective bite zone
	-- from the rod's base minigameZoneSize up to this value, so a well-timed
	-- cast roughly triples catch odds vs the bare re-roll floor while an ok/no
	-- cast keeps the base floor. Exploiters are capped at the perfect-honest
	-- rate (never above it) and rarity stays server-rolled. Tunable: lower to
	-- keep always-hit exploiters on a tighter leash.
	biteZoneCeiling = 0.85,
}

GameConfig.Quests = {
	DailySlots = 3,
	WeeklySlots = 2,
}

GameConfig.Boat = {
	despawnDelay = 10,
}

-- EPIC 8 (TASK 8.1 / gdj.1): raid-window scheduler tuning, per PRD
-- "Recommended V1 raid rule": windows occur every 20-30 minutes and last
-- 5 minutes. All values in seconds. The scheduler (RaidService) draws each
-- gap independently from [min, max] so window timing isn't perfectly
-- predictable.
GameConfig.Raid = {
	windowIntervalMin = 20 * 60,
	windowIntervalMax = 30 * 60,
	windowDuration = 5 * 60,
	-- TASK 8.2 (gdj.2): raid opt-in. Per PRD PVP-02, raids may only target
	-- players who opted in (dock flag toggle or Raid Waters pier zone).
	-- optInDefault must stay false: a player should never lose fish because
	-- they joined for the first time (PRD "opt-in or time-bounded").
	optInDefault = false,
	-- TASK 8.8 (gdj.8): Legendary fish raid protection (PVP-08).
	-- PRD: "Legendary fish either non-stealable or much lower raid probability."
	-- V1: Legendary fish are non-stealable (IsRaidProtected=true on FishInstance).
	-- Epic fish have reduced steal weight (configurable for future tuning).
	legendaryProtection = {
		nonStealable = true,
		epicStealWeightMultiplier = 0.3,
	},
	-- Raid outcome tuning
	maxFishPerRaid = 1,
	raiderCooldownSeconds = 5 * 60,
	defenderProtectionSeconds = 15 * 60,
	perVictimCooldownSeconds = 30 * 60,
	-- TASK 8.5b (gdj.14): raid timing minigame (DEC-2 hybrid). The server picks
	-- the zone bounds + marker speed per attempt; the client plays a
	-- moving-marker timing bar and reports only the raw marker position. The
	-- server re-derives the tier from its own bounds and rolls success against
	-- the tier's chance — a forged "always perfect" client is capped at the
	-- perfect rate, never 100% (same authority model as the N16/DECISION-C
	-- fishing floor). Marker speed is in [0,1] units/sec; 0.8 is a
	-- mobile-friendly sweep (full bar in 1.25s), not reflex-only.
	minigame = {
		durationSeconds = 8,
		markerSpeed = 0.8,
		perfectZoneSize = 0.12,
		goodZoneSize = 0.30,
		successChance = { perfect = 0.85, good = 0.55, ok = 0.20 },
	},
	-- TASK 8.9 (gdj.9): per-window loss cap (PVP-12). A defender can lose at
	-- most this many fish per raid window, across ALL attackers, so one window
	-- can never empty an aquarium (PVP-05). Tracked on the defender session
	-- (session.raidWindowLosses in RaidService) with the stolen value recorded
	-- alongside for the future value-fraction cap.
	maxLossesPerWindow = 2,
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

-- TASK 14.10 (wqw.10): canonical rod table is RodDefinitions (superset:
-- adds id + minigameZoneSize). Rods is kept as an alias for the many
-- existing GameConfig.Rods[level] readers (ShopService, FishingService,
-- DataManager sanitize, client HUD/shop).
GameConfig.Rods = GameConfig.RodDefinitions

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 2.4: Bait Definitions (reusable tiers per DEC-5)
-- ════════════════════════════════════════════════════════════════════════════
GameConfig.BaitDefinitions = {
	{ id = 1, name = "Basic Bait",  cost = 0,    luck = 0,  desc = "Plain old worms." },
	{ id = 2, name = "Shrimp Bait", cost = 300,  luck = 6,  desc = "Rarer fish love shrimp." },
	{ id = 3, name = "Magic Bait",  cost = 1500, luck = 15, desc = "Glows with legendary promise." },
}

-- TASK 14.10 (wqw.10): canonical bait table is BaitDefinitions (adds id).
-- Baits is an alias for existing GameConfig.Baits[level] readers
-- (ShopService, FishingService, DataManager sanitize, client HUD/shop).
GameConfig.Baits = GameConfig.BaitDefinitions

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
	-- R2.2 (dt9.2): IncomeToValueRatio REMOVED — was dead config with zero
	-- consumers. FishDefinitions.Species[].IncomePerMinute (copied into each
	-- FishInstance at creation) is the single source of truth for per-fish
	-- income. If a ratio-based derivation is desired in the future, add it
	-- as a separate balance task after playtesting the current hand-maintained values.
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

-- ════════════════════════════════════════════════════════════════════════════
-- R2.3 (dt9.3): Boot-time config assertion — prevents income definition
-- divergence from being reintroduced silently after R2.2 unification.
-- Pattern: hard-fail (error) in Studio for fast feedback, non-fatal warn
-- in production (availability over strictness). O(#species) cost — negligible.
-- Extensible: R2.4 config-validation harness can add more named checks here.
-- Call from init.server.lua after services load.
-- ════════════════════════════════════════════════════════════════════════════
function GameConfig.validate()
	local RunService = game:GetService("RunService")
	local FishDefinitions = require(game:GetService("ReplicatedStorage").Shared.FishDefinitions)
	local violations = {}

	-- Check 1: every FishDefinitions species has a valid IncomePerMinute
	-- (the single source of truth for per-fish income after R2.2).
	for id, def in pairs(FishDefinitions.Species) do
		if type(def.IncomePerMinute) ~= "number" or def.IncomePerMinute <= 0 then
			table.insert(violations, string.format(
				"FishDefinitions.Species.%s: IncomePerMinute is %s (expected positive number)",
				tostring(id), tostring(def.IncomePerMinute)
			))
		end
	end

	-- Check 2: GameConfig.Rarities entries must NOT have incomePerSec
	-- (deleted in R2.2 — was dead config disagreeing 12-18x with live source).
	for i, rarity in ipairs(GameConfig.Rarities) do
		if rarity.incomePerSec ~= nil then
			table.insert(violations, string.format(
				"GameConfig.Rarities[%d] (%s): incomePerSec field present — should be removed (R2.2 deleted it as dead config)",
				i, tostring(rarity.name)
			))
		end
	end

	-- Check 3: GameConfig.Economy must NOT have IncomeToValueRatio
	-- (deleted in R2.2 — was dead config with zero consumers).
	if GameConfig.Economy.IncomeToValueRatio ~= nil then
		table.insert(violations, "GameConfig.Economy.IncomeToValueRatio present — should be removed (R2.2 deleted it as dead config)")
	end

	if #violations > 0 then
		local msg = "[GameConfig.validate] Income invariant violations:\n" .. table.concat(violations, "\n")
		if RunService:IsStudio() then
			error(msg, 0)
		else
			warn(msg)
		end
	end
end

return GameConfig
