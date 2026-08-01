-- ShopService pure-logic unit tests (TASK 41-01, harborheist-m3vj.1).
--
-- ShopService has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the purchase
-- decision chain is mirrored as pure Luau functions and exercised against
-- the authoritative config values. Source-contract assertions verify
-- that the production code still contains the formulas tested here.
--
-- Covers: kind dispatch (rod/bait/aquarium/lock/alarm/dock), argument
-- validation, math.floor level coercion, sequential tier enforcement,
-- cost enforcement, coin clamping (incl. NaN guard), per-kind upgrade
-- application, rod ownership tracking, and income-cache invalidation
-- semantics. No mocks, fakes, or stubs — only pure math mirrors +
-- source-file contract checks.

local fs = require("@lune/fs")

-- ──────────────────────────────────────────────────────────────────────
-- Config mirrors (must match src/shared/GameConfig.lua)
-- ──────────────────────────────────────────────────────────────────────

local MAX_COINS = 999999999

local RodDefinitions = {
	{ id = 1, name = "Basic Rod",  cost = 0,    luck = 0,  castTime = 4, minigameZoneSize = 0.30 },
	{ id = 2, name = "Steel Rod",  cost = 500,  luck = 8,  castTime = 3, minigameZoneSize = 0.35 },
	{ id = 3, name = "Golden Rod", cost = 2500, luck = 20, castTime = 2, minigameZoneSize = 0.40 },
}

local BaitDefinitions = {
	{ id = 1, name = "Basic Bait",  cost = 0,    luck = 0  },
	{ id = 2, name = "Shrimp Bait", cost = 300,  luck = 6  },
	{ id = 3, name = "Magic Bait",  cost = 1500, luck = 15 },
}

local AquariumUpgradeTiers = {
	{ level = 1, name = "Starter Tank",  capacity = 20, cost = 0,    incomeMultiplier = 1.0  },
	{ level = 2, name = "Expanded Tank", capacity = 35, cost = 800,  incomeMultiplier = 1.1  },
	{ level = 3, name = "Large Tank",    capacity = 50, cost = 3000, incomeMultiplier = 1.25 },
	{ level = 4, name = "Mega Tank",     capacity = 75, cost = 8000, incomeMultiplier = 1.5  },
}

local LockUpgrades = {
	{ name = "Lock I",   cost = 400,  lockDuration = 90,  lockCooldown = 90 },
	{ name = "Lock II",  cost = 1200, lockDuration = 120, lockCooldown = 60 },
	{ name = "Lock III", cost = 3000, lockDuration = 150, lockCooldown = 30 },
}

local AlarmUpgrades = {
	{ name = "Alarm I",   cost = 500,  stunDuration = 3, notifyChance = 1.0 },
	{ name = "Alarm II",  cost = 1500, stunDuration = 5, notifyChance = 1.0 },
	{ name = "Alarm III", cost = 4000, stunDuration = 8, notifyChance = 1.0 },
}

local DockUpgradeTiers = {
	{ level = 1, name = "Basic Dock",         cost = 0,     incomeMultiplier = 1.0  },
	{ level = 2, name = "Lamp-Lit Dock",      cost = 1200,  incomeMultiplier = 1.15 },
	{ level = 3, name = "Garden Dock",        cost = 4000,  incomeMultiplier = 1.35 },
	{ level = 4, name = "Golden Harbor Dock", cost = 10000, incomeMultiplier = 1.6  },
}

local FIRST_UPGRADE_TARGET = 500

-- ──────────────────────────────────────────────────────────────────────
-- Logic mirrors (verbatim from ShopService.lua / PlayerProfile.lua)
-- ──────────────────────────────────────────────────────────────────────

-- PlayerProfile.clampCoins (PlayerProfile.lua lines 124-137): clamps to
-- [0, MAX_COINS]; non-number → 0; NaN → 0 (R1.2: NaN < cost is always
-- false, so a NaN-coined player could otherwise buy everything free).
local function clampCoins(value)
	if type(value) ~= "number" then
		return 0
	end
	if value ~= value then
		return 0
	end
	return math.floor(math.max(0, math.min(MAX_COINS, value)))
end

-- Fresh player profile shape (PlayerProfile.default lines 39-52 region).
local function makeProfile(coins)
	return {
		Coins = coins or 0,
		Equipment = {
			EquippedRodLevel = 1,
			EquippedBaitLevel = 1,
			OwnedRodLevels = { 1 },
		},
		Aquarium = {
			UpgradeLevel = 1,
			Capacity = 20,
			LockLevel = 0,
			AlarmLevel = 0,
		},
		Dock = { UpgradeLevel = 1 },
	}
end

-- Kind → catalog + current level dispatch (ShopService.lua lines 41-66).
-- N6: lock and alarm must be in this dispatch or they return bad_kind
-- even though the shop UI lists them for sale.
local function resolveCatalog(kind, profile)
	if kind == "rod" then
		return RodDefinitions, profile.Equipment.EquippedRodLevel
	elseif kind == "bait" then
		return BaitDefinitions, profile.Equipment.EquippedBaitLevel
	elseif kind == "aquarium" then
		return AquariumUpgradeTiers, profile.Aquarium.UpgradeLevel or 1
	elseif kind == "lock" then
		return LockUpgrades, profile.Aquarium.LockLevel or 0
	elseif kind == "alarm" then
		return AlarmUpgrades, profile.Aquarium.AlarmLevel or 0
	elseif kind == "dock" then
		return DockUpgradeTiers, profile.Dock.UpgradeLevel or 1
	else
		return nil, nil
	end
end

-- Purchase decision chain (ShopService.lua handlePurchaseUpgrade,
-- lines 19-164). Roblox-side effects (notify, audit, analytics,
-- stateSync.push, task.spawn save) are not mirrored — only the
-- server-authoritative decision + profile mutation.
local function purchaseUpgrade(profile, kind, level)
	if type(kind) ~= "string" or type(level) ~= "number" then
		return { ok = false, reason = "bad_args" }
	end
	level = math.floor(level)
	local catalog, currentLevel = resolveCatalog(kind, profile)
	if not catalog then
		return { ok = false, reason = "bad_kind" }
	end
	local item = catalog[level]
	if not item then
		return { ok = false, reason = "bad_level" }
	end
	if level ~= currentLevel + 1 then
		return { ok = false, reason = "wrong_tier" }
	end
	if math.floor(profile.Coins) < item.cost then
		return { ok = false, reason = "poor" }
	end

	profile.Coins = clampCoins(profile.Coins - item.cost)
	if kind == "rod" then
		profile.Equipment.EquippedRodLevel = level
		local owned = profile.Equipment.OwnedRodLevels
		local alreadyOwned = false
		for _, lvl in ipairs(owned) do
			if lvl == level then
				alreadyOwned = true
				break
			end
		end
		if not alreadyOwned then
			table.insert(owned, level)
		end
	elseif kind == "bait" then
		profile.Equipment.EquippedBaitLevel = level
	elseif kind == "aquarium" then
		profile.Aquarium.UpgradeLevel = level
		profile.Aquarium.Capacity = catalog[level].capacity or catalog[level].Capacity or profile.Aquarium.Capacity
	elseif kind == "lock" then
		profile.Aquarium.LockLevel = level
	elseif kind == "alarm" then
		profile.Aquarium.AlarmLevel = level
	elseif kind == "dock" then
		profile.Dock.UpgradeLevel = level
	end

	-- TASK 14.15: only aquarium/dock affect income multipliers.
	local invalidatesIncome = (kind == "aquarium" or kind == "dock")
	return { ok = true, invalidatesIncome = invalidatesIncome, cost = item.cost, name = item.name }
end

-- ──────────────────────────────────────────────────────────────────────
-- Source contract helpers
-- ──────────────────────────────────────────────────────────────────────

local shopSource = fs.readFile("src/server/ShopService.lua")
local gameConfigSource = fs.readFile("src/shared/GameConfig.lua")
local playerProfileSource = fs.readFile("src/shared/PlayerProfile.lua")

return function(describe, it, expect)
	-- ════════════════════════════════════════════════════════════════════
	-- Argument validation
	-- ════════════════════════════════════════════════════════════════════
	describe("Argument validation", function()
		it("rejects non-string kind", function()
			local r = purchaseUpgrade(makeProfile(10000), 2, 2)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_args")
		end)

		it("rejects non-number level", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", "2")
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_args")
		end)

		it("rejects nil level", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", nil)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_args")
		end)

		it("coerces fractional level via math.floor before tier check", function()
			-- 2.9 floors to 2 → valid next tier for a level-1 rod owner
			local profile = makeProfile(10000)
			local r = purchaseUpgrade(profile, "rod", 2.9)
			expect(r.ok).to.equal(true)
			expect(profile.Equipment.EquippedRodLevel).to.equal(2)
		end)

		it("fractional level 1.2 floors to 1 and fails tier order", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", 1.2)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("wrong_tier")
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Kind dispatch
	-- ════════════════════════════════════════════════════════════════════
	describe("Kind dispatch", function()
		it("unknown kind returns bad_kind", function()
			local r = purchaseUpgrade(makeProfile(10000), "engine", 1)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_kind")
		end)

		it("all six shop kinds resolve a catalog", function()
			local profile = makeProfile(0)
			for _, kind in ipairs({ "rod", "bait", "aquarium", "lock", "alarm", "dock" }) do
				local catalog = resolveCatalog(kind, profile)
				expect(catalog).never.to.equal(nil)
			end
		end)

		it("lock/alarm current level defaults to 0 (not owned)", function()
			local profile = makeProfile(0)
			profile.Aquarium.LockLevel = nil
			profile.Aquarium.AlarmLevel = nil
			local _, lockLevel = resolveCatalog("lock", profile)
			local _, alarmLevel = resolveCatalog("alarm", profile)
			expect(lockLevel).to.equal(0)
			expect(alarmLevel).to.equal(0)
		end)

		it("aquarium/dock current level defaults to 1 (starter tier owned)", function()
			local profile = makeProfile(0)
			profile.Aquarium.UpgradeLevel = nil
			profile.Dock.UpgradeLevel = nil
			local _, aqLevel = resolveCatalog("aquarium", profile)
			local _, dockLevel = resolveCatalog("dock", profile)
			expect(aqLevel).to.equal(1)
			expect(dockLevel).to.equal(1)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Level validation
	-- ════════════════════════════════════════════════════════════════════
	describe("Level validation", function()
		it("level 0 is not in any catalog", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", 0)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_level")
		end)

		it("level beyond catalog is bad_level (rod has 3 tiers)", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", 4)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_level")
		end)

		it("level beyond catalog is bad_level (aquarium has 4 tiers)", function()
			local r = purchaseUpgrade(makeProfile(10000), "aquarium", 5)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_level")
		end)

		it("negative level is bad_level", function()
			local r = purchaseUpgrade(makeProfile(10000), "lock", -1)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("bad_level")
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Sequential tier enforcement
	-- ════════════════════════════════════════════════════════════════════
	describe("Sequential tier enforcement", function()
		it("cannot skip a tier (1 → 3)", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", 3)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("wrong_tier")
		end)

		it("cannot re-buy current tier", function()
			local r = purchaseUpgrade(makeProfile(10000), "rod", 1)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("wrong_tier")
		end)

		it("must buy exactly currentLevel + 1", function()
			local profile = makeProfile(10000)
			expect(purchaseUpgrade(profile, "bait", 2).ok).to.equal(true)
			-- now at 2: buying 2 again and buying 4 both fail, buying 3 works
			expect(purchaseUpgrade(profile, "bait", 2).reason).to.equal("wrong_tier")
			expect(purchaseUpgrade(profile, "bait", 4).reason).to.equal("bad_level")
			expect(purchaseUpgrade(profile, "bait", 3).ok).to.equal(true)
		end)

		it("lock tiers enforce order from 0", function()
			local profile = makeProfile(10000)
			expect(purchaseUpgrade(profile, "lock", 2).reason).to.equal("wrong_tier")
			expect(purchaseUpgrade(profile, "lock", 1).ok).to.equal(true)
			expect(profile.Aquarium.LockLevel).to.equal(1)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Cost enforcement
	-- ════════════════════════════════════════════════════════════════════
	describe("Cost enforcement", function()
		it("rejects when coins are 1 short", function()
			local r = purchaseUpgrade(makeProfile(499), "rod", 2)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("poor")
		end)

		it("accepts exact-cost purchase", function()
			local profile = makeProfile(500)
			local r = purchaseUpgrade(profile, "rod", 2)
			expect(r.ok).to.equal(true)
			expect(profile.Coins).to.equal(0)
		end)

		it("fractional coins are floored for the affordability check", function()
			-- 500.7 floors to 500 → affordable; remainder is clamped/floored away
			local profile = makeProfile(500.7)
			local r = purchaseUpgrade(profile, "rod", 2)
			expect(r.ok).to.equal(true)
			expect(profile.Coins).to.equal(0)
		end)

		it("fractional coins just under cost are rejected", function()
			local r = purchaseUpgrade(makeProfile(499.99), "rod", 2)
			expect(r.ok).to.equal(false)
			expect(r.reason).to.equal("poor")
		end)

		it("first rod upgrade matches Economy.FirstUpgradeTarget", function()
			expect(RodDefinitions[2].cost).to.equal(FIRST_UPGRADE_TARGET)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Coin clamping (PlayerProfile.clampCoins mirror)
	-- ════════════════════════════════════════════════════════════════════
	describe("Coin clamping", function()
		it("negative values clamp to 0", function()
			expect(clampCoins(-5)).to.equal(0)
		end)

		it("values above MAX_COINS clamp to MAX_COINS", function()
			expect(clampCoins(MAX_COINS + 1000)).to.equal(MAX_COINS)
		end)

		it("fractional values floor", function()
			expect(clampCoins(10.9)).to.equal(10)
		end)

		it("NaN clamps to 0 (R1.2 free-purchase exploit guard)", function()
			expect(clampCoins(0 / 0)).to.equal(0)
		end)

		it("non-number clamps to 0", function()
			expect(clampCoins("500")).to.equal(0)
			expect(clampCoins(nil)).to.equal(0)
		end)

		it("+Inf clamps to MAX_COINS", function()
			expect(clampCoins(math.huge)).to.equal(MAX_COINS)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Per-kind upgrade application
	-- ════════════════════════════════════════════════════════════════════
	describe("Per-kind upgrade application", function()
		it("rod purchase equips and tracks ownership", function()
			local profile = makeProfile(10000)
			purchaseUpgrade(profile, "rod", 2)
			expect(profile.Equipment.EquippedRodLevel).to.equal(2)
			local found = false
			for _, lvl in ipairs(profile.Equipment.OwnedRodLevels) do
				if lvl == 2 then
					found = true
					break
				end
			end
			expect(found).to.equal(true)
		end)

		it("rod ownership never double-inserts a level", function()
			local profile = makeProfile(10000)
			purchaseUpgrade(profile, "rod", 2)
			local count = 0
			for _, lvl in ipairs(profile.Equipment.OwnedRodLevels) do
				if lvl == 2 then count += 1 end
			end
			expect(count).to.equal(1)
		end)

		it("bait purchase equips new bait level", function()
			local profile = makeProfile(10000)
			purchaseUpgrade(profile, "bait", 2)
			expect(profile.Equipment.EquippedBaitLevel).to.equal(2)
		end)

		it("aquarium purchase applies tier capacity", function()
			local profile = makeProfile(20000)
			purchaseUpgrade(profile, "aquarium", 2)
			expect(profile.Aquarium.UpgradeLevel).to.equal(2)
			expect(profile.Aquarium.Capacity).to.equal(35)
			purchaseUpgrade(profile, "aquarium", 3)
			expect(profile.Aquarium.Capacity).to.equal(50)
			purchaseUpgrade(profile, "aquarium", 4)
			expect(profile.Aquarium.Capacity).to.equal(75)
		end)

		it("alarm purchase sets alarm level", function()
			local profile = makeProfile(10000)
			purchaseUpgrade(profile, "alarm", 1)
			expect(profile.Aquarium.AlarmLevel).to.equal(1)
		end)

		it("dock purchase sets dock upgrade level", function()
			local profile = makeProfile(10000)
			purchaseUpgrade(profile, "dock", 2)
			expect(profile.Dock.UpgradeLevel).to.equal(2)
		end)

		it("deducts the exact catalog cost", function()
			local profile = makeProfile(10000)
			purchaseUpgrade(profile, "rod", 2)
			expect(profile.Coins).to.equal(9500)
			purchaseUpgrade(profile, "rod", 3)
			expect(profile.Coins).to.equal(7000)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Income-cache invalidation semantics (TASK 14.15)
	-- ════════════════════════════════════════════════════════════════════
	describe("Income-cache invalidation semantics", function()
		it("aquarium and dock purchases invalidate income cache", function()
			local profile = makeProfile(100000)
			expect(purchaseUpgrade(profile, "aquarium", 2).invalidatesIncome).to.equal(true)
			expect(purchaseUpgrade(profile, "dock", 2).invalidatesIncome).to.equal(true)
		end)

		it("rod/bait/lock/alarm purchases do not invalidate income cache", function()
			local profile = makeProfile(100000)
			expect(purchaseUpgrade(profile, "rod", 2).invalidatesIncome).to.equal(false)
			expect(purchaseUpgrade(profile, "bait", 2).invalidatesIncome).to.equal(false)
			expect(purchaseUpgrade(profile, "lock", 1).invalidatesIncome).to.equal(false)
			expect(purchaseUpgrade(profile, "alarm", 1).invalidatesIncome).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Economy shape invariants
	-- ════════════════════════════════════════════════════════════════════
	describe("Economy shape invariants", function()
		it("starter tiers are free (rod 1, bait 1, aquarium 1, dock 1)", function()
			expect(RodDefinitions[1].cost).to.equal(0)
			expect(BaitDefinitions[1].cost).to.equal(0)
			expect(AquariumUpgradeTiers[1].cost).to.equal(0)
			expect(DockUpgradeTiers[1].cost).to.equal(0)
		end)

		it("costs strictly increase across tiers", function()
			local tracks = { RodDefinitions, BaitDefinitions, AquariumUpgradeTiers, LockUpgrades, AlarmUpgrades, DockUpgradeTiers }
			for _, track in ipairs(tracks) do
				for i = 2, #track do
					expect(track[i].cost > track[i - 1].cost).to.equal(true)
				end
			end
		end)

		it("aquarium capacities strictly increase", function()
			for i = 2, #AquariumUpgradeTiers do
				expect(AquariumUpgradeTiers[i].capacity > AquariumUpgradeTiers[i - 1].capacity).to.equal(true)
			end
		end)

		it("lock duration increases and cooldown decreases across tiers", function()
			for i = 2, #LockUpgrades do
				expect(LockUpgrades[i].lockDuration > LockUpgrades[i - 1].lockDuration).to.equal(true)
				expect(LockUpgrades[i].lockCooldown < LockUpgrades[i - 1].lockCooldown).to.equal(true)
			end
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract verification
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract verification", function()
		it("ShopService dispatches all six kinds", function()
			expect(shopSource:find('kind == "rod"', 1, true)).to.be.a("number")
			expect(shopSource:find('kind == "bait"', 1, true)).to.be.a("number")
			expect(shopSource:find('kind == "aquarium"', 1, true)).to.be.a("number")
			expect(shopSource:find('kind == "lock"', 1, true)).to.be.a("number")
			expect(shopSource:find('kind == "alarm"', 1, true)).to.be.a("number")
			expect(shopSource:find('kind == "dock"', 1, true)).to.be.a("number")
		end)

		it("ShopService floors the level argument", function()
			expect(shopSource:find("level = math.floor(level)", 1, true)).to.be.a("number")
		end)

		it("ShopService enforces sequential tiers", function()
			expect(shopSource:find("level ~= currentLevel + 1", 1, true)).to.be.a("number")
		end)

		it("ShopService floors coins for the affordability check", function()
			expect(shopSource:find("math.floor(session.profile.Coins) < item.cost", 1, true)).to.be.a("number")
		end)

		it("ShopService clamps coins after deduction (N5 defense in depth)", function()
			expect(shopSource:find("PlayerProfile.clampCoins(session.profile.Coins - item.cost)", 1, true)).to.be.a("number")
		end)

		it("ShopService invalidates income cache only for aquarium/dock", function()
			expect(shopSource:find('kind == "aquarium" or kind == "dock"', 1, true)).to.be.a("number")
			expect(shopSource:find("stateSync.invalidateIncomeCache(session)", 1, true)).to.be.a("number")
		end)

		it("ShopService tracks rod ownership without duplicates", function()
			expect(shopSource:find("OwnedRodLevels", 1, true)).to.be.a("number")
			expect(shopSource:find("alreadyOwned", 1, true)).to.be.a("number")
		end)

		it("ShopService reports authoritative charged price to analytics", function()
			expect(shopSource:find("price = item.cost", 1, true)).to.be.a("number")
		end)

		it("ShopService exposes _requestPurchaseUpgrade test seam", function()
			expect(shopSource:find("ShopService._requestPurchaseUpgrade", 1, true)).to.be.a("number")
		end)

		it("GameConfig.Rods aliases RodDefinitions (single source of truth)", function()
			expect(gameConfigSource:find("GameConfig.Rods = GameConfig.RodDefinitions", 1, true)).to.be.a("number")
		end)

		it("GameConfig.Baits aliases BaitDefinitions (single source of truth)", function()
			expect(gameConfigSource:find("GameConfig.Baits = GameConfig.BaitDefinitions", 1, true)).to.be.a("number")
		end)

		it("GameConfig rod costs: Steel 500, Golden 2500", function()
			expect(gameConfigSource:find('name = "Steel Rod",  cost = 500', 1, true)).to.be.a("number")
			expect(gameConfigSource:find('name = "Golden Rod", cost = 2500', 1, true)).to.be.a("number")
		end)

		it("GameConfig bait costs: Shrimp 300, Magic 1500", function()
			expect(gameConfigSource:find('name = "Shrimp Bait", cost = 300', 1, true)).to.be.a("number")
			expect(gameConfigSource:find('name = "Magic Bait",  cost = 1500', 1, true)).to.be.a("number")
		end)

		it("GameConfig aquarium tiers: capacities 20/35/50/75", function()
			expect(gameConfigSource:find("capacity = 20", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("capacity = 35", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("capacity = 50", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("capacity = 75", 1, true)).to.be.a("number")
		end)

		it("GameConfig Economy.FirstUpgradeTarget is 500", function()
			expect(gameConfigSource:find("FirstUpgradeTarget = 500", 1, true)).to.be.a("number")
		end)

		it("PlayerProfile.MAX_COINS is 999999999", function()
			expect(playerProfileSource:find("PlayerProfile.MAX_COINS = 999999999", 1, true)).to.be.a("number")
		end)

		it("PlayerProfile.clampCoins rejects NaN before clamping (R1.2)", function()
			expect(playerProfileSource:find("if value ~= value then", 1, true)).to.be.a("number")
		end)

		it("PlayerProfile default owns rod level 1", function()
			expect(playerProfileSource:find("OwnedRodLevels = { 1 }", 1, true)).to.be.a("number")
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract: purchase-success flash (a2ug.10)
	-- ──────────────────────────────────────────────────────────────────
	local clientSource = fs.readFile("src/client/init.client.lua")

	describe("Source contract: purchase-success flash (a2ug.10)", function()
		it("shopFlashTokens guard table exists", function()
			expect(clientSource:find("shopFlashTokens", 1, true)).to.be.a("number")
			expect(clientSource:find("token ~= shopFlashTokens[rowKey]", 1, true)).to.be.a("number")
		end)

		it("flash calls hapticSuccess on successful purchase", function()
			-- hapticSuccess should appear in the result.ok branch
			local okIdx = clientSource:find("if result and result.ok then", 1, true)
			expect(okIdx).to.be.a("number")
			local hapticIdx = clientSource:find("hapticSuccess", okIdx, true)
			expect(hapticIdx).to.be.a("number")
		end)

		it("flash uses chained EASE_FAST then EASE_OUT tweens on row Frame", function()
			local okIdx = clientSource:find("if result and result.ok then", 1, true)
			local tween1Idx = clientSource:find("EASE_FAST", okIdx, true)
			local tween2Idx = clientSource:find("EASE_OUT", tween1Idx, true)
			expect(tween1Idx).to.be.a("number")
			expect(tween2Idx).to.be.a("number")
			-- Flash targets row.BackgroundColor3 (not buyButton)
			local rowBgIdx = clientSource:find("BackgroundColor3 = Theme.color.status.good", okIdx, true)
			expect(rowBgIdx).to.be.a("number")
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract: a2ug.8 delta subtext on the purchasable row
	-- ──────────────────────────────────────────────────────────────────
	describe("Source contract: a2ug.8 delta subtext", function()
		it("itemDeltaSubText function exists", function()
			expect(clientSource:find("local function itemDeltaSubText(entry, currentLevel)", 1, true)).to.be.a("number")
		end)

		it("delta function handles rod kind", function()
			expect(clientSource:find('"rod"', 1, true)).to.be.a("number")
			local deltaIdx = clientSource:find("local function itemDeltaSubText", 1, true)
			local rodIdx = clientSource:find('entry.kind == "rod"', deltaIdx, true)
			expect(rodIdx).to.be.a("number")
		end)

		it("delta function handles all six kinds", function()
			local deltaIdx = clientSource:find("local function itemDeltaSubText", 1, true)
			for _, kind in ipairs({ "rod", "bait", "aquarium", "lock", "alarm", "dock" }) do
				local idx = clientSource:find('entry.kind == "' .. kind .. '"', deltaIdx, true)
				expect(idx).to.be.a("number")
			end
		end)

		it("delta uses arrow separator ( -> )", function()
			expect(clientSource:find(" luck -> +", 1, true)).to.be.a("number")
			expect(clientSource:find(" -> ", 1, true)).to.be.a("number")
		end)

		it("buildShopRow stores subTextLabel in shopRows entry", function()
			expect(clientSource:find("subTextLabel = subTextLabel", 1, true)).to.be.a("number")
		end)

		it("refreshShop sets delta text on purchasable row", function()
			expect(clientSource:find("itemDeltaSubText(entry, currentLevel)", 1, true)).to.be.a("number")
		end)

		it("refreshShop restores absolute text on OWNED row", function()
			local ownedIdx = clientSource:find('entry.buyButton.Text = "OWNED"', 1, true)
			local subTextIdx = clientSource:find("itemSubText(entry)", ownedIdx, true)
			expect(subTextIdx).to.be.a("number")
		end)

		it("refreshShop restores absolute text on LOCKED row", function()
			local lockedIdx = clientSource:find('entry.buyButton.Text = "LOCKED"', 1, true)
			local subTextIdx = clientSource:find("itemSubText(entry)", lockedIdx, true)
			expect(subTextIdx).to.be.a("number")
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract: shop MAXED summary rows (a2ug.9)
	-- ──────────────────────────────────────────────────────────────────
	describe("Source contract: shop MAXED summary rows (a2ug.9)", function()
		it("shopMaxLevels table computed from SHOP_CATALOG", function()
			expect(clientSource:find("shopMaxLevels", 1, true)).to.be.a("number")
			expect(clientSource:find("shopMaxLevels[entry.kind] = entry.level", 1, true)).to.be.a("number")
		end)

		it("getOrCreateSummaryRow function builds MAXED summary rows", function()
			expect(clientSource:find("getOrCreateSummaryRow", 1, true)).to.be.a("number")
			expect(clientSource:find("MAXED", 1, true)).to.be.a("number")
			expect(clientSource:find("Summary_", 1, true)).to.be.a("number")
		end)

		it("refreshShop toggles per-tier row visibility for maxed tracks", function()
			expect(clientSource:find("entry.row.Visible = not isMaxed", 1, true)).to.be.a("number")
			expect(clientSource:find("summary.row.Visible = isMaxed", 1, true)).to.be.a("number")
		end)

		it("section headers hide when all tracks in section are maxed", function()
			expect(clientSource:find("shopSectionHeaders", 1, true)).to.be.a("number")
			expect(clientSource:find("header.label.Visible = not allMaxed", 1, true)).to.be.a("number")
		end)

		it("buildSectionHeader stores kinds array for visibility tracking", function()
			expect(clientSource:find('buildSectionHeader("RODS", -1, { "rod" })', 1, true)).to.be.a("number")
			expect(clientSource:find('buildSectionHeader("DEFENSE", 299, { "lock", "alarm" })', 1, true)).to.be.a("number")
		end)
	end)
end