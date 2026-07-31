-- AquariumService pure-logic unit tests (TASK 41-01-B, harborheist-m3vj.1.2).
--
-- AquariumService has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the raid-eligibility
-- gates, lock mechanics, and fish-protection logic are mirrored as pure
-- Luau functions and exercised against the authoritative config values.
-- Source-contract assertions verify that the production code still
-- contains the logic tested here.
--
-- Covers: isNewPlayerProtected, isEligibleRaidTarget, isEligibleRaidAttacker,
-- hasStealableFish / getStealableFish / getProtectedFish, lock free-use
-- regen, lock duration/cooldown tiers, and income accrual math.
-- No mocks, fakes, or stubs — only pure logic mirrors + source-file
-- contract checks.

local fs = require("@lune/fs")

-- ──────────────────────────────────────────────────────────────────────
-- Config mirrors (must match src/shared/GameConfig.lua)
-- ──────────────────────────────────────────────────────────────────────

local RAID = {
	unlockTotalCatches = 10,
}

local DEFENSE = {
	LockFreeUsesMax = 3,
}

local AQUARIUMBASIC = {
	lockDuration = 60,
	lockCooldown = 120,
}

local LOCK_TIERS = {
	[1] = { lockDuration = 90,  lockCooldown = 90  },
	[2] = { lockDuration = 120, lockCooldown = 60  },
	[3] = { lockDuration = 150, lockCooldown = 30  },
}

local ECONOMY = {
	MaxUnclaimedIncome = 50000,
}

local INCOME_TICK_SECONDS = 1
local MAX_COINS = 999999999 -- PlayerProfile.MAX_COINS

-- ──────────────────────────────────────────────────────────────────────
-- Logic mirrors (verbatim from AquariumService.lua production code)
-- ──────────────────────────────────────────────────────────────────────

-- TASK 8.3: new-player protection gate (mirrors AquariumService.isNewPlayerProtected).
local function isNewPlayerProtected(session)
	if not session or not session.profile then
		return true
	end
	local statsCatches = (session.profile.Stats and session.profile.Stats.TotalCatches) or 0
	local pvpCatches = (session.profile.PvP and session.profile.PvP.TotalCatches) or 0
	local totalCatches = math.max(statsCatches, pvpCatches)
	local hasUpgrade = (session.profile.Aquarium.UpgradeLevel or 1) > 1
	local hasEnoughCatches = totalCatches >= RAID.unlockTotalCatches
	return not hasUpgrade and not hasEnoughCatches
end

-- TASK 8.3: eligible raid target (mirrors AquariumService.isEligibleRaidTarget).
local function isEligibleRaidTarget(session, now, epochNow)
	if not session or not session.profile then
		return false, "no_session"
	end
	if isNewPlayerProtected(session) then
		return false, "new_player_protected"
	end
	if not session.profile.Aquarium.RaidOptIn then
		return false, "not_opted_in"
	end
	if session.lockedUntil and session.lockedUntil > (now or 0) then
		return false, "locked"
	end
	local protectionUntil = session.profile.Aquarium.RaidProtectionUntilTimestamp or 0
	if protectionUntil > (epochNow or 0) then
		return false, "raid_protection"
	end
	-- Check stealable fish
	local hasStealable = false
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		if not fish.IsRaidProtected then
			hasStealable = true
			break
		end
	end
	if not hasStealable then
		return false, "no_stealable_fish"
	end
	return true, "ok"
end

-- TASK 8.3: eligible raid attacker (mirrors AquariumService.isEligibleRaidAttacker).
local function isEligibleRaidAttacker(session, now)
	if not session or not session.profile then
		return false, "no_session"
	end
	if isNewPlayerProtected(session) then
		return false, "new_player_protected"
	end
	if not session.profile.Aquarium.RaidOptIn then
		return false, "not_opted_in"
	end
	if session.stunUntil and session.stunUntil > (now or 0) then
		return false, "stunned"
	end
	return true, "ok"
end

-- Stealable / protected fish helpers (mirror AquariumService lines 495-533).
local function hasStealableFish(session)
	if not session or not session.profile or not session.profile.Aquarium then
		return false
	end
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		if not fish.IsRaidProtected then
			return true
		end
	end
	return false
end

local function getStealableFish(session)
	if not session or not session.profile or not session.profile.Aquarium then
		return {}
	end
	local out = {}
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		if not fish.IsRaidProtected then
			table.insert(out, fish)
		end
	end
	return out
end

local function getProtectedFish(session)
	if not session or not session.profile or not session.profile.Aquarium then
		return {}
	end
	local out = {}
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		if fish.IsRaidProtected then
			table.insert(out, fish)
		end
	end
	return out
end

-- Lock regen (mirrors AquariumService.onSessionLoaded).
local function onSessionLoaded(session)
	if not session then
		return
	end
	local defense = session.profile and session.profile.Defense
	if not defense then
		return
	end
	defense.LockFreeUsesMax = defense.LockFreeUsesMax or DEFENSE.LockFreeUsesMax
	defense.LockFreeUsesRemaining = defense.LockFreeUsesMax
end

-- Lock duration/cooldown resolution (mirrors AquariumService handleActivateLock).
local function resolveLockParams(lockLevel, hasFreeUse)
	local lockDuration = AQUARIUMBASIC.lockDuration
	local lockCooldown = AQUARIUMBASIC.lockCooldown
	if lockLevel > 0 and LOCK_TIERS[lockLevel] then
		local tier = LOCK_TIERS[lockLevel]
		lockDuration = tier.lockDuration
		lockCooldown = tier.lockCooldown
	end
	if not hasFreeUse then
		lockCooldown = lockCooldown * 2
	end
	return lockDuration, lockCooldown
end

-- Income accrual per tick (mirrors AquariumService.startIncomeLoop logic).
local function computeIncomeAccrual(incomePerSec, unclaimed, tickSeconds)
	local income = incomePerSec * (tickSeconds or INCOME_TICK_SECONDS)
	if income <= 0 then
		return unclaimed, false -- no change
	end
	return math.min(unclaimed + income, ECONOMY.MaxUnclaimedIncome), true
end

-- Coin clamping (mirrors PlayerProfile.clampCoins — type guard, NaN guard, floor).
local function clampCoins(amount)
	if type(amount) ~= "number" then
		return 0
	end
	if amount ~= amount then -- NaN guard (NaN is the only number not equal to itself)
		return 0
	end
	return math.floor(math.max(0, math.min(MAX_COINS, amount)))
end

-- ──────────────────────────────────────────────────────────────────────
-- Source contract helpers
-- ──────────────────────────────────────────────────────────────────────

local aqSource = fs.readFile("src/server/AquariumService.lua")
local gameConfigSource = fs.readFile("src/shared/GameConfig.lua")
local profileSource = fs.readFile("src/shared/PlayerProfile.lua")

-- ──────────────────────────────────────────────────────────────────────
-- Session factory
-- ──────────────────────────────────────────────────────────────────────

local function makeSession(overrides)
	local base = {
		profile = {
			Aquarium = {
				UpgradeLevel = 1,
				RaidOptIn = false,
				StoredFish = {},
				UnclaimedIncome = 0,
				LockLevel = 0,
			},
			Stats = { TotalCatches = 0 },
			PvP = { TotalCatches = 0 },
			Defense = { LockFreeUsesRemaining = 3, LockFreeUsesMax = 3 },
			Coins = 0,
			TotalCoinsEarned = 0,
		},
		lockedUntil = 0,
		lockCooldownUntil = 0,
		stunUntil = 0,
	}
	if overrides then
		for k, v in pairs(overrides) do
			base[k] = v
		end
	end
	return base
end

local function makeFish(speciesId, rarity, isProtected)
	return {
		SpeciesId = speciesId,
		Rarity = rarity,
		IsRaidProtected = isProtected or false,
		BaseSellValue = 100,
	}
end

return function(describe, it, expect)
	-- ════════════════════════════════════════════════════════════════════
	-- New-player protection gate
	-- ════════════════════════════════════════════════════════════════════
	describe("New-player protection gate", function()
		it("fresh player (no catches, no upgrade) is protected", function()
			expect(isNewPlayerProtected(makeSession())).to.equal(true)
		end)

		it("nil session is protected", function()
			expect(isNewPlayerProtected(nil)).to.equal(true)
		end)

		it("nil profile is protected", function()
			expect(isNewPlayerProtected({})).to.equal(true)
		end)

		it("10 catches unlocks (not protected)", function()
			local s = makeSession({ profile = { Stats = { TotalCatches = 10 }, PvP = { TotalCatches = 0 }, Aquarium = { UpgradeLevel = 1, RaidOptIn = false, StoredFish = {} } } })
			expect(isNewPlayerProtected(s)).to.equal(false)
		end)

		it("9 catches stays protected", function()
			local s = makeSession({ profile = { Stats = { TotalCatches = 9 }, PvP = { TotalCatches = 0 }, Aquarium = { UpgradeLevel = 1, RaidOptIn = false, StoredFish = {} } } })
			expect(isNewPlayerProtected(s)).to.equal(true)
		end)

		it("aquarium upgrade unlocks (not protected)", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 0
			s.profile.Aquarium.UpgradeLevel = 2
			expect(isNewPlayerProtected(s)).to.equal(false)
		end)

		it("takes max of Stats and PvP catches (legacy compat)", function()
			local s = makeSession({ profile = { Stats = { TotalCatches = 0 }, PvP = { TotalCatches = 10 }, Aquarium = { UpgradeLevel = 1, RaidOptIn = false, StoredFish = {} } } })
			expect(isNewPlayerProtected(s)).to.equal(false)
		end)

		it("missing Stats falls back to PvP catches", function()
			local s = makeSession({ profile = { PvP = { TotalCatches = 10 }, Aquarium = { UpgradeLevel = 1, RaidOptIn = false, StoredFish = {} } } })
			expect(isNewPlayerProtected(s)).to.equal(false)
		end)

		it("missing PvP falls back to Stats catches", function()
			local s = makeSession({ profile = { Stats = { TotalCatches = 10 }, Aquarium = { UpgradeLevel = 1, RaidOptIn = false, StoredFish = {} } } })
			expect(isNewPlayerProtected(s)).to.equal(false)
		end)

		it("both catches missing stays protected", function()
			local s = makeSession({ profile = { Aquarium = { UpgradeLevel = 1, RaidOptIn = false, StoredFish = {} } } })
			expect(isNewPlayerProtected(s)).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Raid target eligibility
	-- ════════════════════════════════════════════════════════════════════
	describe("Raid target eligibility", function()
		it("nil session returns false, 'no_session'", function()
			local ok, reason = isEligibleRaidTarget(nil, 100, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("no_session")
		end)

		it("new player protected returns false, 'new_player_protected'", function()
			local s = makeSession()
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("new_player_protected")
		end)

		it("unlocked but not opted-in returns false, 'not_opted_in'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = false
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("not_opted_in")
		end)

		it("opted-in but locked returns false, 'locked'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			s.lockedUntil = 200
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("locked")
		end)

		it("under raid protection immunity returns false, 'raid_protection'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			s.profile.Aquarium.RaidProtectionUntilTimestamp = 200
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("raid_protection")
		end)

		it("no stealable fish returns false, 'no_stealable_fish'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			-- Only legendary (protected) fish
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Leviathan", "Legendary", true))
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("no_stealable_fish")
		end)

		it("all conditions met returns true, 'ok'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Cod", "Common", false))
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(true)
			expect(reason).to.equal("ok")
		end)

		it("lock expired (lockedUntil < now) does not block", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			s.lockedUntil = 50 -- expired: now=100 > 50
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Cod", "Common", false))
			local ok, reason = isEligibleRaidTarget(s, 100, 100)
			expect(ok).to.equal(true)
			expect(reason).to.equal("ok")
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Raid attacker eligibility
	-- ════════════════════════════════════════════════════════════════════
	describe("Raid attacker eligibility", function()
		it("nil session returns false, 'no_session'", function()
			local ok, reason = isEligibleRaidAttacker(nil, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("no_session")
		end)

		it("new player protected returns false", function()
			local ok, reason = isEligibleRaidAttacker(makeSession(), 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("new_player_protected")
		end)

		it("unlocked but not opted-in returns false", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = false
			local ok, reason = isEligibleRaidAttacker(s, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("not_opted_in")
		end)

		it("stunned attacker returns false, 'stunned'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			s.stunUntil = 200
			local ok, reason = isEligibleRaidAttacker(s, 100)
			expect(ok).to.equal(false)
			expect(reason).to.equal("stunned")
		end)

		it("unstunned attacker (stunUntil expired) is eligible", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			s.stunUntil = 50 -- expired: now=100 > 50
			local ok, reason = isEligibleRaidAttacker(s, 100)
			expect(ok).to.equal(true)
			expect(reason).to.equal("ok")
		end)

		it("fully eligible attacker returns true, 'ok'", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 10
			s.profile.Aquarium.RaidOptIn = true
			local ok, reason = isEligibleRaidAttacker(s, 100)
			expect(ok).to.equal(true)
			expect(reason).to.equal("ok")
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Stealable / protected fish helpers
	-- ════════════════════════════════════════════════════════════════════
	describe("Stealable and protected fish", function()
		it("hasStealableFish — false with no fish", function()
			expect(hasStealableFish(makeSession())).to.equal(false)
		end)

		it("hasStealableFish — false with nil session", function()
			expect(hasStealableFish(nil)).to.equal(false)
		end)

		it("hasStealableFish — true with non-protected fish", function()
			local s = makeSession()
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Cod", "Common", false))
			expect(hasStealableFish(s)).to.equal(true)
		end)

		it("hasStealableFish — false with only Legendary (protected)", function()
			local s = makeSession()
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Leviathan", "Legendary", true))
			expect(hasStealableFish(s)).to.equal(false)
		end)

		it("getStealableFish returns only non-protected fish", function()
			local s = makeSession()
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Cod", "Common", false))
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Leviathan", "Legendary", true))
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Tuna", "Rare", false))
			local stealable = getStealableFish(s)
			expect(#stealable).to.equal(2)
			expect(stealable[1].SpeciesId).to.equal("Cod")
			expect(stealable[2].SpeciesId).to.equal("Tuna")
		end)

		it("getProtectedFish returns only Legendary (protected) fish", function()
			local s = makeSession()
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Cod", "Common", false))
			table.insert(s.profile.Aquarium.StoredFish, makeFish("Leviathan", "Legendary", true))
			local protected = getProtectedFish(s)
			expect(#protected).to.equal(1)
			expect(protected[1].SpeciesId).to.equal("Leviathan")
		end)

		it("mixed aquarium: stealable + protected counts are correct", function()
			local s = makeSession()
			table.insert(s.profile.Aquarium.StoredFish, makeFish("A", "Common", false))
			table.insert(s.profile.Aquarium.StoredFish, makeFish("B", "Rare", false))
			table.insert(s.profile.Aquarium.StoredFish, makeFish("C", "Epic", false))
			table.insert(s.profile.Aquarium.StoredFish, makeFish("D", "Legendary", true))
			expect(#getStealableFish(s)).to.equal(3)
			expect(#getProtectedFish(s)).to.equal(1)
		end)

		it("getStealableFish returns empty table for nil session", function()
			expect(#getStealableFish(nil)).to.equal(0)
		end)

		it("getProtectedFish returns empty table for nil session", function()
			expect(#getProtectedFish(nil)).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Lock free-use regen (vaz2)
	-- ════════════════════════════════════════════════════════════════════
	describe("Lock free-use regen", function()
		it("nil session is a no-op (no crash)", function()
			onSessionLoaded(nil)
		end)

		it("missing Defense is a no-op (no crash)", function()
			onSessionLoaded({ profile = {} })
		end)

		it("depleted budget refills to max on rejoin", function()
			local s = { profile = { Defense = { LockFreeUsesRemaining = 0, LockFreeUsesMax = 3 } } }
			onSessionLoaded(s)
			expect(s.profile.Defense.LockFreeUsesRemaining).to.equal(3)
		end)

		it("partially used budget refills to max", function()
			local s = { profile = { Defense = { LockFreeUsesRemaining = 1, LockFreeUsesMax = 3 } } }
			onSessionLoaded(s)
			expect(s.profile.Defense.LockFreeUsesRemaining).to.equal(3)
		end)

		it("missing LockFreeUsesMax falls back to GameConfig default", function()
			local s = { profile = { Defense = { LockFreeUsesRemaining = 2 } } }
			onSessionLoaded(s)
			expect(s.profile.Defense.LockFreeUsesRemaining).to.equal(DEFENSE.LockFreeUsesMax)
			expect(s.profile.Defense.LockFreeUsesMax).to.equal(DEFENSE.LockFreeUsesMax)
		end)

		it("full budget stays at max", function()
			local s = { profile = { Defense = { LockFreeUsesRemaining = 3, LockFreeUsesMax = 3 } } }
			onSessionLoaded(s)
			expect(s.profile.Defense.LockFreeUsesRemaining).to.equal(3)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Lock duration/cooldown resolution
	-- ════════════════════════════════════════════════════════════════════
	describe("Lock duration/cooldown resolution", function()
		it("base config (lockLevel 0) uses 60s duration, 120s cooldown", function()
			local dur, cd = resolveLockParams(0, true)
			expect(dur).to.equal(60)
			expect(cd).to.equal(120)
		end)

		it("Lock I: 90s duration, 90s cooldown with free use", function()
			local dur, cd = resolveLockParams(1, true)
			expect(dur).to.equal(90)
			expect(cd).to.equal(90)
		end)

		it("Lock II: 120s duration, 60s cooldown with free use", function()
			local dur, cd = resolveLockParams(2, true)
			expect(dur).to.equal(120)
			expect(cd).to.equal(60)
		end)

		it("Lock III: 150s duration, 30s cooldown with free use", function()
			local dur, cd = resolveLockParams(3, true)
			expect(dur).to.equal(150)
			expect(cd).to.equal(30)
		end)

		it("no free use doubles the cooldown (base)", function()
			local _, cd = resolveLockParams(0, false)
			expect(cd).to.equal(240) -- 120 * 2
		end)

		it("no free use doubles the cooldown (Lock I)", function()
			local _, cd = resolveLockParams(1, false)
			expect(cd).to.equal(180) -- 90 * 2
		end)

		it("no free use doubles the cooldown (Lock III)", function()
			local _, cd = resolveLockParams(3, false)
			expect(cd).to.equal(60) -- 30 * 2
		end)

		it("higher lock tiers have shorter cooldowns (incentive to upgrade)", function()
			local _, cd1 = resolveLockParams(1, true)
			local _, cd2 = resolveLockParams(2, true)
			local _, cd3 = resolveLockParams(3, true)
			expect(cd2 < cd1).to.equal(true)
			expect(cd3 < cd2).to.equal(true)
		end)

		it("higher lock tiers have longer durations (more protection)", function()
			local dur1 = resolveLockParams(1, true)
			local dur2 = resolveLockParams(2, true)
			local dur3 = resolveLockParams(3, true)
			expect(dur2 > dur1).to.equal(true)
			expect(dur3 > dur2).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Income accrual
	-- ════════════════════════════════════════════════════════════════════
	describe("Income accrual", function()
		it("IncomeTickSeconds is 1", function()
			expect(INCOME_TICK_SECONDS).to.equal(1)
		end)

		it("normal accrual below cap adds exactly", function()
			local new, changed = computeIncomeAccrual(10, 100, 1)
			expect(new).to.equal(110)
			expect(changed).to.equal(true)
		end)

		it("zero incomePerSec produces no change", function()
			local new, changed = computeIncomeAccrual(0, 100, 1)
			expect(new).to.equal(100)
			expect(changed).to.equal(false)
		end)

		it("UnclaimedIncome is capped at MaxUnclaimedIncome", function()
			local new, changed = computeIncomeAccrual(1000, 49999, 1)
			expect(new).to.equal(50000)
			expect(changed).to.equal(true)
		end)

		it("at cap, accrual still caps (no overflow)", function()
			local new, changed = computeIncomeAccrual(100, 50000, 1)
			expect(new).to.equal(50000)
			expect(changed).to.equal(true)
		end)

		it("MaxUnclaimedIncome is 50000", function()
			expect(ECONOMY.MaxUnclaimedIncome).to.equal(50000)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Coin clamping
	-- ════════════════════════════════════════════════════════════════════
	describe("Coin clamping", function()
		it("normal amount is preserved", function()
			expect(clampCoins(500)).to.equal(500)
		end)

		it("negative amount clamped to 0", function()
			expect(clampCoins(-100)).to.equal(0)
		end)

		it("large amount capped at MAX_COINS", function()
			expect(clampCoins(MAX_COINS + 50)).to.equal(MAX_COINS)
		end)

		it("claim near ceiling does not overflow", function()
			local coins = MAX_COINS - 25
			local unclaimed = 100
			expect(clampCoins(coins + unclaimed)).to.equal(MAX_COINS)
		end)

		it("non-number input returns 0", function()
			expect(clampCoins(nil)).to.equal(0)
			expect(clampCoins("foo")).to.equal(0)
			expect(clampCoins(true)).to.equal(0)
		end)

		it("NaN input returns 0 (anti-exploit)", function()
			local nan = 0/0
			expect(clampCoins(nan)).to.equal(0)
		end)

		it("negative input clamped to 0", function()
			expect(clampCoins(-50)).to.equal(0)
		end)

		it("fractional input is floored", function()
			expect(clampCoins(500.7)).to.equal(500)
			expect(clampCoins(0.9)).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract verification
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract verification", function()
		it("AquariumService defines isNewPlayerProtected", function()
			expect(aqSource:find("function AquariumService.isNewPlayerProtected", 1, true)).to.be.a("number")
		end)

		it("isNewPlayerProtected uses max of Stats and PvP catches", function()
			expect(aqSource:find("math.max(statsCatches, pvpCatches)", 1, true)).to.be.a("number")
		end)

		it("isNewPlayerProtected checks upgrade OR catches", function()
			expect(aqSource:find("not hasUpgrade and not hasEnoughCatches", 1, true)).to.be.a("number")
		end)

		it("AquariumService defines isEligibleRaidTarget", function()
			expect(aqSource:find("function AquariumService.isEligibleRaidTarget", 1, true)).to.be.a("number")
		end)

		it("isEligibleRaidTarget checks opt-in", function()
			expect(aqSource:find('not session.profile.Aquarium.RaidOptIn', 1, true)).to.be.a("number")
		end)

		it("isEligibleRaidTarget checks lock state", function()
			expect(aqSource:find("session.lockedUntil > os.clock()", 1, true)).to.be.a("number")
		end)

		it("isEligibleRaidTarget checks raid protection immunity", function()
			expect(aqSource:find("RaidProtectionUntilTimestamp", 1, true)).to.be.a("number")
		end)

		it("isEligibleRaidTarget checks stealable fish", function()
			expect(aqSource:find("hasStealableFish", 1, true)).to.be.a("number")
		end)

		it("AquariumService defines isEligibleRaidAttacker", function()
			expect(aqSource:find("function AquariumService.isEligibleRaidAttacker", 1, true)).to.be.a("number")
		end)

		it("isEligibleRaidAttacker checks stun state", function()
			expect(aqSource:find("session.stunUntil > os.clock()", 1, true)).to.be.a("number")
		end)

		it("AquariumService defines hasStealableFish", function()
			expect(aqSource:find("function AquariumService.hasStealableFish", 1, true)).to.be.a("number")
		end)

		it("hasStealableFish checks IsRaidProtected flag", function()
			expect(aqSource:find("not fish.IsRaidProtected", 1, true)).to.be.a("number")
		end)

		it("AquariumService defines getStealableFish", function()
			expect(aqSource:find("function AquariumService.getStealableFish", 1, true)).to.be.a("number")
		end)

		it("AquariumService defines getProtectedFish", function()
			expect(aqSource:find("function AquariumService.getProtectedFish", 1, true)).to.be.a("number")
		end)

		it("AquariumService defines onSessionLoaded (lock regen)", function()
			expect(aqSource:find("function AquariumService.onSessionLoaded", 1, true)).to.be.a("number")
		end)

		it("onSessionLoaded resets LockFreeUsesRemaining to max", function()
			expect(aqSource:find("defense.LockFreeUsesRemaining = defense.LockFreeUsesMax", 1, true)).to.be.a("number")
		end)

		it("locked aquarium blocks StoredFish sell (TASK 14.6)", function()
			expect(aqSource:find("aquarium_locked", 1, true)).to.be.a("number")
		end)

		it("no free use doubles cooldown", function()
			expect(aqSource:find("lockCooldown = lockCooldown * 2", 1, true)).to.be.a("number")
		end)

		it("income loop accrues to UnclaimedIncome pool", function()
			expect(aqSource:find("session.profile.Aquarium.UnclaimedIncome", 1, true)).to.be.a("number")
		end)

		it("income is capped at MaxUnclaimedIncome", function()
			expect(aqSource:find("math.min(unclaimed + income, maxUnclaimed)", 1, true)).to.be.a("number")
		end)

		it("uses PlayerProfile.clampCoins for coin writes", function()
			expect(aqSource:find("PlayerProfile.clampCoins", 1, true)).to.be.a("number")
		end)

		it("PlayerProfile.MAX_COINS is 999999999", function()
			expect(profileSource:find("MAX_COINS = 999999999", 1, true)).to.be.a("number")
		end)

		it("PlayerProfile.clampCoins has type guard", function()
			expect(profileSource:find('type(value) ~= "number"', 1, true)).to.be.a("number")
		end)

		it("PlayerProfile.clampCoins has NaN guard", function()
			expect(profileSource:find("value ~= value", 1, true)).to.be.a("number")
		end)

		it("PlayerProfile.clampCoins floors the result", function()
			expect(profileSource:find("math.floor", 1, true)).to.be.a("number")
		end)

		it("GameConfig.Raid.unlockTotalCatches is 10", function()
			expect(gameConfigSource:find("unlockTotalCatches = 10", 1, true)).to.be.a("number")
		end)

		it("GameConfig.Defense.LockFreeUsesMax is 3", function()
			expect(gameConfigSource:find("LockFreeUsesMax = 3", 1, true)).to.be.a("number")
		end)

		it("GameConfig base lockDuration is 60", function()
			expect(gameConfigSource:find("lockDuration = 60", 1, true)).to.be.a("number")
		end)

		it("GameConfig base lockCooldown is 120", function()
			expect(gameConfigSource:find("lockCooldown = 120", 1, true)).to.be.a("number")
		end)

		it("Lock III upgrade: 150s duration, 30s cooldown", function()
			expect(gameConfigSource:find("lockDuration = 150, lockCooldown = 30", 1, true)).to.be.a("number")
		end)

		it("MaxUnclaimedIncome is 50000 in GameConfig", function()
			expect(gameConfigSource:find("MaxUnclaimedIncome = 50000", 1, true)).to.be.a("number")
		end)

		it("IncomeTickSeconds is 1 in GameConfig", function()
			expect(gameConfigSource:find("IncomeTickSeconds = 1", 1, true)).to.be.a("number")
		end)
	end)
end
