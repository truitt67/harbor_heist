-- RaidService pure-logic unit tests (TASK 41-01-C, harborheist-m3vj.2).
--
-- RaidService has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the raid
-- scheduling/eligibility/outcome mechanics are mirrored as pure Luau
-- functions and exercised against the authoritative config values.
-- Time is passed in as an argument (now/nowWall parameters) so the
-- mirrors stay pure — no mocks, fakes, or stubs. Source-contract
-- assertions verify that the production code still contains the
-- formulas and gate order tested here.
--
-- Covers: window state math, opt-in/eligibility composition, attacker
-- and per-victim cooldowns, the wall→session clock rejoin bridge
-- (hbyz), attacker gate order (validateAttacker), per-window loss cap,
-- cooldown commit bookkeeping (bounded RecentTargetUserIds), challenge
-- zone geometry, timing-forgery rejection (yxdh), server-side tier
-- derivation, success-chance rolls, weighted steal pick with Legendary
-- protection + Epic weight (PVP-08), fenced transfer on full aquarium,
-- and defender immunity/stats side effects.

local fs = require("@lune/fs")

-- ──────────────────────────────────────────────────────────────────────
-- Config mirrors (must match src/shared/GameConfig.lua)
-- ──────────────────────────────────────────────────────────────────────

local RAID = {
	windowIntervalMin = 20 * 60,
	windowIntervalMax = 30 * 60,
	windowDuration = 5 * 60,
	optInDefault = false,
	unlockTotalCatches = 10,
	legendaryProtection = {
		nonStealable = true,
		epicStealWeightMultiplier = 0.3,
	},
	maxFishPerRaid = 1,
	raiderCooldownSeconds = 6 * 60,
	defenderProtectionSeconds = 20 * 60,
	perVictimCooldownSeconds = 30 * 60,
	minigame = {
		durationSeconds = 8,
		markerSpeed = 0.8,
		perfectZoneSize = 0.12,
		goodZoneSize = 0.30,
		successChance = { perfect = 0.85, good = 0.55, ok = 0.10 },
	},
	maxLossesPerWindow = 2,
}

local NETWORK_GRACE = 0.5
local MAX_COINS = 999999999

-- ──────────────────────────────────────────────────────────────────────
-- Logic mirrors (verbatim from RaidService.lua production code)
-- ──────────────────────────────────────────────────────────────────────

-- PlayerProfile.clampCoins (same mirror as ShopServiceLogic spec).
local function clampCoins(value)
	if type(value) ~= "number" then
		return 0
	end
	if value ~= value then
		return 0
	end
	return math.floor(math.max(0, math.min(MAX_COINS, value)))
end

-- Window state (RaidService.lua lines 99-127). `state` mirrors the
-- module upvalues windowOpen/windowEndsAt/nextWindowAt; `now` is os.clock().
local function getWindowRemaining(state, now)
	if not state.windowOpen then
		return 0
	end
	return math.max(0, state.windowEndsAt - now)
end

local function getNextWindowIn(state, now)
	if state.windowOpen then
		return 0
	end
	return math.max(0, state.nextWindowAt - now)
end

local function getWindowState(state, now)
	return {
		open = state.windowOpen,
		remainingSeconds = getWindowRemaining(state, now),
		nextWindowInSeconds = getNextWindowIn(state, now),
	}
end

-- Full raid-eligibility composition (lines 163-168): window open AND
-- (dock-flag opt-in OR Raid Waters zone presence).
local function isRaidEligible(windowOpen, optedIn, inRaidWaters)
	if not windowOpen then
		return false
	end
	return optedIn or inRaidWaters
end

-- Attacker raid cooldown (lines 191-205). nil last → fresh attacker is
-- NEVER on cooldown (the old `or 0` bug read every fresh attacker as
-- on-cooldown for the first raiderCooldownSeconds of server uptime).
local function isAttackerOnCooldown(session, now)
	local last = session and session.raidAttackLastAt
	if not last then
		return false, 0
	end
	local cooldownEnd = last + RAID.raiderCooldownSeconds
	if cooldownEnd > now then
		return true, math.ceil(cooldownEnd - now)
	end
	return false, 0
end

-- Per-victim cooldown (lines 209-223).
local function isVictimOnCooldown(session, targetUserId, now)
	local cooldowns = session and session.raidTargetCooldowns
	if not cooldowns then
		return false, 0
	end
	local expiry = cooldowns[targetUserId]
	if not expiry then
		return false, 0
	end
	if expiry > now then
		return true, math.ceil(expiry - now)
	end
	return false, 0
end

-- hbyz rejoin bridge (lines 235-267): re-seed session os.clock() fields
-- from the persisted os.time() mirrors after a (re)join, closing the
-- PVP-06/07 rejoin bypass.
local function onSessionLoaded(session, nowWall, nowClock)
	if not session then
		return
	end
	local pvp = session.profile and session.profile.PvP
	if not pvp then
		return
	end
	local lastRaid = pvp.LastRaidTimestamp or 0
	if lastRaid > 0 then
		local elapsed = nowWall - lastRaid
		if elapsed >= 0 and elapsed < RAID.raiderCooldownSeconds then
			session.raidAttackLastAt = nowClock - elapsed
		end
	end
	if type(pvp.RecentTargetTimestamps) == "table" then
		for uid, ts in pairs(pvp.RecentTargetTimestamps) do
			if type(uid) == "number" and type(ts) == "number" then
				local remaining = RAID.perVictimCooldownSeconds - (nowWall - ts)
				if remaining > 0 then
					session.raidTargetCooldowns = session.raidTargetCooldowns or {}
					session.raidTargetCooldowns[uid] = nowClock + remaining
				end
			end
		end
	end
end

-- Attacker gate order (lines 275-296): window → opt-in → safe harbor →
-- new-player protection → stun → attacker cooldown.
local function validateAttacker(state)
	if not state.windowOpen then
		return false, "window_closed"
	end
	if not (state.optedIn or state.inRaidWaters) then
		return false, "not_opted_in"
	end
	if state.inSafeHarbor then
		return false, "safe_harbor_protected"
	end
	if state.newPlayerProtected then
		return false, "new_player_protected"
	end
	if state.stunUntil and state.stunUntil > state.now then
		return false, "stunned"
	end
	local onCd, remaining = isAttackerOnCooldown({ raidAttackLastAt = state.raidAttackLastAt }, state.now)
	if onCd then
		return false, "attacker_cooldown", { cooldownRemaining = remaining }
	end
	return true, "ok"
end

-- Defender per-window loss bookkeeping (lines 459-472). Keyed on the
-- monotonically increasing window serial so a new window auto-resets.
local function getWindowLosses(session, windowSerial)
	local losses = session.raidWindowLosses
	if not losses or losses.serial ~= windowSerial then
		losses = { serial = windowSerial, count = 0, value = 0 }
		session.raidWindowLosses = losses
	end
	return losses.count, losses
end

local function isLossCapped(session, windowSerial)
	local count = getWindowLosses(session, windowSerial)
	return count >= (RAID.maxLossesPerWindow or 2)
end

-- Attacker cooldown commit (lines 477-508): burns BOTH cooldowns on
-- attempt commit (a failed minigame still burns them — PVP-06 is per
-- ATTEMPT), bumps persisted mirrors, prunes the per-victim timestamp map,
-- and keeps RecentTargetUserIds a bounded deduped array (cap 10, FIFO).
local function commitAttackerCooldowns(session, targetUserId, now, nowWall)
	session.raidAttackLastAt = now
	session.raidTargetCooldowns = session.raidTargetCooldowns or {}
	session.raidTargetCooldowns[targetUserId] = now + RAID.perVictimCooldownSeconds
	local pvp = session.profile.PvP
	pvp.LastRaidTimestamp = nowWall
	pvp.RaidAttemptsToday = (pvp.RaidAttemptsToday or 0) + 1
	pvp.RecentTargetTimestamps = pvp.RecentTargetTimestamps or {}
	pvp.RecentTargetTimestamps[targetUserId] = nowWall
	for uid, ts in pairs(pvp.RecentTargetTimestamps) do
		if (nowWall - ts) >= RAID.perVictimCooldownSeconds then
			pvp.RecentTargetTimestamps[uid] = nil
		end
	end
	pvp.RecentTargetUserIds = pvp.RecentTargetUserIds or {}
	for _, uid in ipairs(pvp.RecentTargetUserIds) do
		if uid == targetUserId then
			return
		end
	end
	table.insert(pvp.RecentTargetUserIds, targetUserId)
	if #pvp.RecentTargetUserIds > 10 then
		table.remove(pvp.RecentTargetUserIds, 1)
	end
end

-- Server-authoritative challenge geometry (lines 569-585). The center is
-- drawn in [goodHalf, 1-goodHalf] so the good zone always fits in [0,1].
-- `frac` is the rng:NextNumber() draw in [0,1).
local function buildChallenge(frac)
	local cfg = RAID.minigame
	local goodHalf = cfg.goodZoneSize / 2
	local center = goodHalf + frac * ((1 - goodHalf) - goodHalf)
	local perfectHalf = cfg.perfectZoneSize / 2
	return {
		center = center,
		goodStart = center - goodHalf,
		goodEnd = center + goodHalf,
		perfectStart = center - perfectHalf,
		perfectEnd = center + perfectHalf,
		markerSpeed = cfg.markerSpeed,
		durationSeconds = cfg.durationSeconds,
	}
end

-- Server-side tier derivation (lines 814, 839-846): the client reports
-- only a raw marker position; the server clamps it and re-derives the
-- tier from its OWN stored bounds (PVP-10).
local function clampPosition(markerPosition)
	return math.clamp(markerPosition, 0, 1)
end

local function deriveRaidTier(position, raid)
	if position >= raid.perfectStart and position <= raid.perfectEnd then
		return "perfect"
	elseif position >= raid.goodStart and position <= raid.goodEnd then
		return "good"
	else
		return "ok"
	end
end

-- Timing-forgery check (lines 829-838, yxdh): a submission that arrives
-- before the marker could physically reach the reported position (minus
-- a 0.5s network grace) is impossible for an honest client → too_fast.
local function isTooFast(position, durationSeconds, elapsed)
	if durationSeconds > 0 then
		local minNeeded = position * durationSeconds
		if elapsed < (minNeeded - NETWORK_GRACE) then
			return true
		end
	end
	return false
end

-- Outcome roll (lines 901-905): success iff NOT (roll > chance).
local function raidSucceeds(tier, rollValue)
	local chance = RAID.minigame.successChance[tier] or 0
	return not (rollValue > chance)
end

-- Weighted steal pick (lines 623-647, resolveRaidSuccess selection
-- half): non-protected fish only; Epic gets epicStealWeightMultiplier,
-- everything else weighs 1. Legendary fish carry IsRaidProtected=true
-- (PVP-08) so they never enter the pool.
local function pickStealIndex(fishList, rollValue)
	local epicMult = RAID.legendaryProtection.epicStealWeightMultiplier or 1
	local totalWeight = 0
	for _, fish in ipairs(fishList) do
		if not fish.IsRaidProtected then
			totalWeight += (fish.Rarity == "Epic") and epicMult or 1
		end
	end
	if totalWeight <= 0 then
		return nil, "no_stealable_fish"
	end
	local roll = rollValue * totalWeight
	local targetFish = nil
	for _, fish in ipairs(fishList) do
		if not fish.IsRaidProtected then
			roll -= (fish.Rarity == "Epic") and epicMult or 1
			if roll <= 0 then
				targetFish = fish
				break
			end
		end
	end
	-- N15 TOCTOU: re-find the reference in the live list before removing.
	if targetFish and not targetFish.IsRaidProtected then
		for i, fish in ipairs(fishList) do
			if fish == targetFish and not fish.IsRaidProtected then
				return i, targetFish
			end
		end
	end
	return nil, "fish_gone"
end

-- Fenced transfer (lines 670-681): attacker aquarium full → the stolen
-- fish is fenced for its BaseSellValue instead of inserted.
local function resolveTransfer(attackerSession, stolenFish, capacity)
	local attackerFish = attackerSession.profile.Aquarium.StoredFish
	if #attackerFish < capacity then
		table.insert(attackerFish, stolenFish)
		return { fenced = false }
	else
		attackerSession.profile.Coins = clampCoins(attackerSession.profile.Coins + stolenFish.BaseSellValue)
		attackerSession.profile.TotalCoinsEarned += stolenFish.BaseSellValue
		return { fenced = true }
	end
end

-- ──────────────────────────────────────────────────────────────────────
-- Source contract helpers
-- ──────────────────────────────────────────────────────────────────────

local raidSource = fs.readFile("src/server/RaidService.lua")
local gameConfigSource = fs.readFile("src/shared/GameConfig.lua")

return function(describe, it, expect)
	-- ════════════════════════════════════════════════════════════════════
	-- Window state math
	-- ════════════════════════════════════════════════════════════════════
	describe("Window state math", function()
		it("closed window reports 0 remaining and counts down next open", function()
			local state = { windowOpen = false, windowEndsAt = 0, nextWindowAt = 100 }
			expect(getWindowRemaining(state, 40)).to.equal(0)
			expect(getNextWindowIn(state, 40)).to.equal(60)
		end)

		it("open window counts down remaining and reports 0 next-open", function()
			local state = { windowOpen = true, windowEndsAt = 300, nextWindowAt = 0 }
			expect(getWindowRemaining(state, 120)).to.equal(180)
			expect(getNextWindowIn(state, 120)).to.equal(0)
		end)

		it("durations clamp at 0 (never negative)", function()
			local state = { windowOpen = true, windowEndsAt = 10, nextWindowAt = 5 }
			expect(getWindowRemaining(state, 99)).to.equal(0)
			state.windowOpen = false
			expect(getNextWindowIn(state, 99)).to.equal(0)
		end)

		it("getWindowState sends durations only (no absolute clocks)", function()
			local state = { windowOpen = true, windowEndsAt = 300, nextWindowAt = 0 }
			local payload = getWindowState(state, 250)
			expect(payload.open).to.equal(true)
			expect(payload.remainingSeconds).to.equal(50)
			expect(payload.nextWindowInSeconds).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Raid-window scheduler config (PRD V1 rule)
	-- ════════════════════════════════════════════════════════════════════
	describe("Scheduler config (PRD V1 raid rule)", function()
		it("window gap is 20-30 minutes", function()
			expect(RAID.windowIntervalMin).to.equal(1200)
			expect(RAID.windowIntervalMax).to.equal(1800)
		end)

		it("window duration is 5 minutes", function()
			expect(RAID.windowDuration).to.equal(300)
		end)

		it("gap interval is a valid non-empty range", function()
			expect(RAID.windowIntervalMin < RAID.windowIntervalMax).to.equal(true)
		end)

		it("opt-in defaults to false (PVP-02)", function()
			expect(RAID.optInDefault).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Eligibility composition
	-- ════════════════════════════════════════════════════════════════════
	describe("Eligibility composition", function()
		it("closed window makes everyone ineligible", function()
			expect(isRaidEligible(false, true, true)).to.equal(false)
			expect(isRaidEligible(false, true, false)).to.equal(false)
			expect(isRaidEligible(false, false, true)).to.equal(false)
		end)

		it("open window requires dock flag OR raid waters presence", function()
			expect(isRaidEligible(true, true, false)).to.equal(true)
			expect(isRaidEligible(true, false, true)).to.equal(true)
			expect(isRaidEligible(true, true, true)).to.equal(true)
			expect(isRaidEligible(true, false, false)).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Attacker cooldown
	-- ════════════════════════════════════════════════════════════════════
	describe("Attacker cooldown (PVP-06)", function()
		it("fresh attacker (nil last) is never on cooldown", function()
			local onCd, remaining = isAttackerOnCooldown({}, 100)
			expect(onCd).to.equal(false)
			expect(remaining).to.equal(0)
		end)

		it("inside the window reports ceil'd remaining seconds", function()
			local session = { raidAttackLastAt = 100 }
			local onCd, remaining = isAttackerOnCooldown(session, 100 + 359.2)
			expect(onCd).to.equal(true)
			expect(remaining).to.equal(1)
		end)

		it("exactly at expiry is off cooldown", function()
			local session = { raidAttackLastAt = 100 }
			local onCd = isAttackerOnCooldown(session, 100 + RAID.raiderCooldownSeconds)
			expect(onCd).to.equal(false)
		end)

		it("past expiry is off cooldown", function()
			local session = { raidAttackLastAt = 100 }
			expect(isAttackerOnCooldown(session, 10000)).to.equal(false)
		end)

		it("nil session is off cooldown", function()
			expect(isAttackerOnCooldown(nil, 100)).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Per-victim cooldown
	-- ════════════════════════════════════════════════════════════════════
	describe("Per-victim cooldown (PVP-07)", function()
		it("no cooldown table → off cooldown", function()
			expect(isVictimOnCooldown({}, 42, 100)).to.equal(false)
		end)

		it("unlisted victim → off cooldown", function()
			local s = { raidTargetCooldowns = { [7] = 50 } }
			expect(isVictimOnCooldown(s, 42, 100)).to.equal(false)
		end)

		it("active victim cooldown reports ceil'd remaining", function()
			local s = { raidTargetCooldowns = { [42] = 200.3 } }
			local onCd, remaining = isVictimOnCooldown(s, 42, 100)
			expect(onCd).to.equal(true)
			expect(remaining).to.equal(101)
		end)

		it("expired victim cooldown is off", function()
			local s = { raidTargetCooldowns = { [42] = 200 } }
			expect(isVictimOnCooldown(s, 42, 200)).to.equal(false)
			expect(isVictimOnCooldown(s, 42, 201)).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Rejoin bridge (hbyz)
	-- ════════════════════════════════════════════════════════════════════
	describe("Rejoin bridge (hbyz wall→session clock)", function()
		it("seeds attacker cooldown when last raid is still inside the window", function()
			local session = { profile = { PvP = { LastRaidTimestamp = 1000 } } }
			onSessionLoaded(session, 1000 + 100, 5000) -- 100s ago in wall time
			-- raidAttackLastAt = 5000 - 100 = 4900; cooldown ends 4900+360=5260
			local onCd, remaining = isAttackerOnCooldown(session, 5000)
			expect(onCd).to.equal(true)
			expect(remaining).to.equal(RAID.raiderCooldownSeconds - 100)
		end)

		it("expired mirror leaves the attacker off cooldown", function()
			local session = { profile = { PvP = { LastRaidTimestamp = 1000 } } }
			onSessionLoaded(session, 1000 + RAID.raiderCooldownSeconds + 1, 5000)
			expect(session.raidAttackLastAt).to.equal(nil)
		end)

		it("zero mirror leaves the attacker off cooldown", function()
			local session = { profile = { PvP = { LastRaidTimestamp = 0 } } }
			onSessionLoaded(session, 5000, 5000)
			expect(session.raidAttackLastAt).to.equal(nil)
		end)

		it("seeds per-victim cooldowns with remaining time", function()
			local session = { profile = { PvP = { RecentTargetTimestamps = { [42] = 1000 } } } }
			onSessionLoaded(session, 1000 + 600, 9000) -- 600s of the 1800s victim window used
			expect(session.raidTargetCooldowns).never.to.equal(nil)
			local onCd, remaining = isVictimOnCooldown(session, 42, 9000)
			expect(onCd).to.equal(true)
			expect(remaining).to.equal(RAID.perVictimCooldownSeconds - 600)
		end)

		it("prunes expired per-victim entries on seed", function()
			local session = { profile = { PvP = { RecentTargetTimestamps = { [42] = 1000, [43] = 1000 } } } }
			onSessionLoaded(session, 1000 + RAID.perVictimCooldownSeconds + 5, 9000)
			expect(session.raidTargetCooldowns).to.equal(nil)
		end)

		it("missing PvP mirror is a no-op", function()
			local session = { profile = {} }
			onSessionLoaded(session, 5000, 5000)
			expect(session.raidAttackLastAt).to.equal(nil)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Attacker gate order (validateAttacker)
	-- ════════════════════════════════════════════════════════════════════
	describe("Attacker gate order (validateAttacker)", function()
		local function baseState()
			return {
				windowOpen = true,
				optedIn = true,
				inRaidWaters = false,
				inSafeHarbor = false,
				newPlayerProtected = false,
				stunUntil = nil,
				raidAttackLastAt = nil,
				now = 1000,
			}
		end

		it("fully eligible attacker passes", function()
			local ok, reason = validateAttacker(baseState())
			expect(ok).to.equal(true)
			expect(reason).to.equal("ok")
		end)

		it("closed window wins over every other gate", function()
			local s = baseState()
			s.windowOpen = false
			s.optedIn = false
			s.inSafeHarbor = true
			local ok, reason = validateAttacker(s)
			expect(ok).to.equal(false)
			expect(reason).to.equal("window_closed")
		end)

		it("opt-in gate beats safe harbor gate", function()
			local s = baseState()
			s.optedIn = false
			s.inSafeHarbor = true
			local _, reason = validateAttacker(s)
			expect(reason).to.equal("not_opted_in")
		end)

		it("safe harbor beats new-player protection", function()
			local s = baseState()
			s.inSafeHarbor = true
			s.newPlayerProtected = true
			local _, reason = validateAttacker(s)
			expect(reason).to.equal("safe_harbor_protected")
		end)

		it("new-player protection beats stun", function()
			local s = baseState()
			s.newPlayerProtected = true
			s.stunUntil = 9999
			local _, reason = validateAttacker(s)
			expect(reason).to.equal("new_player_protected")
		end)

		it("stun beats attacker cooldown", function()
			local s = baseState()
			s.stunUntil = 1200
			s.raidAttackLastAt = 900 -- inside 360s cooldown at now=1000
			local _, reason = validateAttacker(s)
			expect(reason).to.equal("stunned")
		end)

		it("attacker cooldown surfaces with remaining seconds", function()
			local s = baseState()
			s.raidAttackLastAt = 900
			local ok, reason, extra = validateAttacker(s)
			expect(ok).to.equal(false)
			expect(reason).to.equal("attacker_cooldown")
			expect(extra.cooldownRemaining).to.equal(360 - 100)
		end)

		it("expired stun does not block", function()
			local s = baseState()
			s.stunUntil = 500 -- before now=1000
			local ok = validateAttacker(s)
			expect(ok).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Per-window loss cap (PVP-12)
	-- ════════════════════════════════════════════════════════════════════
	describe("Per-window loss cap (PVP-12)", function()
		it("fresh session starts at zero losses", function()
			local count = getWindowLosses({}, 1)
			expect(count).to.equal(0)
		end)

		it("cap is 2 losses per window", function()
			expect(RAID.maxLossesPerWindow).to.equal(2)
			local session = {}
			expect(isLossCapped(session, 1)).to.equal(false)
			local _, losses = getWindowLosses(session, 1)
			losses.count = 2
			expect(isLossCapped(session, 1)).to.equal(true)
		end)

		it("new window serial auto-resets the count", function()
			local session = {}
			local _, losses = getWindowLosses(session, 1)
			losses.count = 2
			expect(isLossCapped(session, 1)).to.equal(true)
			expect(isLossCapped(session, 2)).to.equal(false)
			expect(session.raidWindowLosses.serial).to.equal(2)
			expect(session.raidWindowLosses.count).to.equal(0)
		end)

		it("one fish per raid (DEC-3 theft cap)", function()
			expect(RAID.maxFishPerRaid).to.equal(1)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Cooldown commit bookkeeping
	-- ════════════════════════════════════════════════════════════════════
	describe("Cooldown commit bookkeeping", function()
		local function makeSession()
			return { profile = { PvP = {} } }
		end

		it("burns attacker + victim cooldowns on commit", function()
			local s = makeSession()
			commitAttackerCooldowns(s, 42, 1000, 5000)
			expect(s.raidAttackLastAt).to.equal(1000)
			expect(s.raidTargetCooldowns[42]).to.equal(1000 + RAID.perVictimCooldownSeconds)
		end)

		it("writes the persisted PvP mirrors", function()
			local s = makeSession()
			commitAttackerCooldowns(s, 42, 1000, 5000)
			expect(s.profile.PvP.LastRaidTimestamp).to.equal(5000)
			expect(s.profile.PvP.RaidAttemptsToday).to.equal(1)
			expect(s.profile.PvP.RecentTargetTimestamps[42]).to.equal(5000)
		end)

		it("repeat target does not duplicate RecentTargetUserIds", function()
			local s = makeSession()
			commitAttackerCooldowns(s, 42, 1000, 5000)
			commitAttackerCooldowns(s, 42, 1001, 5001)
			expect(#s.profile.PvP.RecentTargetUserIds).to.equal(1)
			expect(s.profile.PvP.RaidAttemptsToday).to.equal(2)
		end)

		it("RecentTargetUserIds is capped at 10 with FIFO eviction", function()
			local s = makeSession()
			for uid = 1, 11 do
				commitAttackerCooldowns(s, uid, 1000 + uid, 5000 + uid)
			end
			local ids = s.profile.PvP.RecentTargetUserIds
			expect(#ids).to.equal(10)
			expect(ids[1]).to.equal(2) -- uid 1 evicted
			expect(ids[10]).to.equal(11)
		end)

		it("prunes expired per-victim timestamps on write", function()
			local s = makeSession()
			s.profile.PvP.RecentTargetTimestamps = { [7] = 5000 - RAID.perVictimCooldownSeconds - 1 }
			commitAttackerCooldowns(s, 42, 1000, 5000)
			expect(s.profile.PvP.RecentTargetTimestamps[7]).to.equal(nil)
			expect(s.profile.PvP.RecentTargetTimestamps[42]).to.equal(5000)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Challenge geometry
	-- ════════════════════════════════════════════════════════════════════
	describe("Challenge geometry", function()
		it("good zone always fits inside [0,1] for any draw", function()
			local fracs = { 0, 0.25, 0.5, 0.75, 0.999 }
			for _, f in ipairs(fracs) do
				local c = buildChallenge(f)
				expect(c.goodStart >= 0).to.equal(true)
				expect(c.goodEnd <= 1).to.equal(true)
			end
		end)

		it("perfect zone is nested inside the good zone", function()
			for _, f in ipairs({ 0, 0.5, 0.999 }) do
				local c = buildChallenge(f)
				expect(c.perfectStart >= c.goodStart).to.equal(true)
				expect(c.perfectEnd <= c.goodEnd).to.equal(true)
			end
		end)

		it("zone widths match config", function()
			local c = buildChallenge(0.5)
			expect(math.abs((c.goodEnd - c.goodStart) - RAID.minigame.goodZoneSize) <= 0.001).to.equal(true)
			expect(math.abs((c.perfectEnd - c.perfectStart) - RAID.minigame.perfectZoneSize) <= 0.001).to.equal(true)
		end)

		it("perfect zone is smaller than good zone (minigame is meaningful)", function()
			expect(RAID.minigame.perfectZoneSize < RAID.minigame.goodZoneSize).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Server-side tier derivation (PVP-10)
	-- ════════════════════════════════════════════════════════════════════
	describe("Server-side tier derivation (PVP-10)", function()
		local raid = {
			perfectStart = 0.44, perfectEnd = 0.56,
			goodStart = 0.35, goodEnd = 0.65,
		}

		it("inside perfect bounds → perfect", function()
			expect(deriveRaidTier(0.5, raid)).to.equal("perfect")
			expect(deriveRaidTier(0.44, raid)).to.equal("perfect")
			expect(deriveRaidTier(0.56, raid)).to.equal("perfect")
		end)

		it("inside good but outside perfect → good", function()
			expect(deriveRaidTier(0.4, raid)).to.equal("good")
			expect(deriveRaidTier(0.6, raid)).to.equal("good")
		end)

		it("outside good → ok", function()
			expect(deriveRaidTier(0.1, raid)).to.equal("ok")
			expect(deriveRaidTier(0.9, raid)).to.equal("ok")
		end)

		it("client-reported position is clamped to [0,1]", function()
			expect(clampPosition(1.5)).to.equal(1)
			expect(clampPosition(-0.5)).to.equal(0)
			expect(clampPosition(0.5)).to.equal(0.5)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Timing-forgery rejection (yxdh)
	-- ════════════════════════════════════════════════════════════════════
	describe("Timing-forgery rejection (yxdh)", function()
		it("instant forged perfect (position 0.5, elapsed 0) is too fast", function()
			expect(isTooFast(0.5, 8, 0)).to.equal(true)
		end)

		it("honest fast tap on early position is allowed by the grace", function()
			-- position 0.1 needs 0.8s; 0.4s elapsed is inside grace (0.8-0.5=0.3)
			expect(isTooFast(0.1, 8, 0.4)).to.equal(false)
		end)

		it("submission exactly at physical minimum minus grace is allowed", function()
			expect(isTooFast(0.5, 8, 4 - NETWORK_GRACE)).to.equal(false)
		end)

		it("position 0 needs no time", function()
			expect(isTooFast(0, 8, 0)).to.equal(false)
		end)

		it("zero duration disables the check", function()
			expect(isTooFast(0.9, 0, 0)).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Outcome roll
	-- ════════════════════════════════════════════════════════════════════
	describe("Outcome roll", function()
		it("success chances: perfect 0.85 > good 0.55 > ok 0.10", function()
			expect(RAID.minigame.successChance.perfect > RAID.minigame.successChance.good).to.equal(true)
			expect(RAID.minigame.successChance.good > RAID.minigame.successChance.ok).to.equal(true)
		end)

		it("sloppy attempts rarely succeed (ok tier 10%)", function()
			expect(raidSucceeds("ok", 0.09)).to.equal(true)
			expect(raidSucceeds("ok", 0.11)).to.equal(false)
		end)

		it("boundary roll equal to chance succeeds (roll > chance is the failure)", function()
			expect(raidSucceeds("perfect", 0.85)).to.equal(true)
			expect(raidSucceeds("good", 0.55)).to.equal(true)
		end)

		it("a forged always-perfect client is capped at 85%, never 100%", function()
			expect(raidSucceeds("perfect", 0.86)).to.equal(false)
			expect(raidSucceeds("perfect", 0.99)).to.equal(false)
		end)

		it("unknown tier has zero chance", function()
			expect(raidSucceeds("legendary_tier", 0.5)).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Weighted steal pick (PVP-08)
	-- ════════════════════════════════════════════════════════════════════
	describe("Weighted steal pick (PVP-08)", function()
		local function fish(rarity, protected, value)
			return { Rarity = rarity, IsRaidProtected = protected or false, BaseSellValue = value or 10 }
		end

		it("legendary (raid-protected) fish are never in the pool", function()
			local list = { fish("Legendary", true, 500) }
			local idx, err = pickStealIndex(list, 0.5)
			expect(idx).to.equal(nil)
			expect(err).to.equal("no_stealable_fish")
		end)

		it("empty aquarium has nothing to steal", function()
			local idx, err = pickStealIndex({}, 0.5)
			expect(idx).to.equal(nil)
			expect(err).to.equal("no_stealable_fish")
		end)

		it("low roll picks the first eligible fish", function()
			local list = { fish("Common"), fish("Rare"), fish("Epic") }
			local idx = pickStealIndex(list, 0)
			expect(idx).to.equal(1)
		end)

		it("high roll picks the last eligible fish", function()
			local list = { fish("Common"), fish("Rare"), fish("Epic") }
			local idx = pickStealIndex(list, 0.999)
			expect(idx).to.equal(3)
		end)

		it("protected fish are skipped mid-list", function()
			local list = { fish("Common"), fish("Legendary", true), fish("Rare") }
			-- pool = Common(1) + Rare(1) = 2; roll 0.75*2=1.5 → Rare at idx 3
			local idx = pickStealIndex(list, 0.75)
			expect(idx).to.equal(3)
			expect(list[2].IsRaidProtected).to.equal(true)
		end)

		it("epic fish weigh 0.3 vs 1 for others", function()
			-- pool = Common(1) + Epic(0.3) = 1.3
			local list = { fish("Common"), fish("Epic") }
			-- roll 0.5*1.3=0.65 → after Common -0.35 → Common picked
			expect(pickStealIndex(list, 0.5)).to.equal(1)
			-- roll 0.9*1.3=1.17 → after Common 0.17 → after Epic -0.13 → Epic
			expect(pickStealIndex(list, 0.9)).to.equal(2)
		end)

		it("epic multiplier comes from config", function()
			expect(RAID.legendaryProtection.epicStealWeightMultiplier).to.equal(0.3)
			expect(RAID.legendaryProtection.nonStealable).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Fenced transfer (attacker aquarium full)
	-- ════════════════════════════════════════════════════════════════════
	describe("Fenced transfer (attacker aquarium full)", function()
		local function attackerSession(capacity)
			local stored = {}
			for _ = 1, capacity do
				table.insert(stored, { Rarity = "Common", BaseSellValue = 10 })
			end
			return {
				profile = {
					Coins = 100,
					TotalCoinsEarned = 0,
					Aquarium = { StoredFish = stored },
				},
			}
		end

		it("fish lands in the aquarium when capacity allows", function()
			local s = attackerSession(0)
			local stolen = { Rarity = "Rare", BaseSellValue = 70 }
			local r = resolveTransfer(s, stolen, 5)
			expect(r.fenced).to.equal(false)
			expect(#s.profile.Aquarium.StoredFish).to.equal(1)
			expect(s.profile.Coins).to.equal(100)
		end)

		it("full aquarium fences the fish for its sell value", function()
			local s = attackerSession(3)
			local stolen = { Rarity = "Rare", BaseSellValue = 70 }
			local r = resolveTransfer(s, stolen, 3)
			expect(r.fenced).to.equal(true)
			expect(#s.profile.Aquarium.StoredFish).to.equal(3)
			expect(s.profile.Coins).to.equal(170)
			expect(s.profile.TotalCoinsEarned).to.equal(70)
		end)

		it("fence payout clamps at MAX_COINS", function()
			local s = attackerSession(1)
			s.profile.Coins = MAX_COINS - 10
			local stolen = { Rarity = "Legendary", BaseSellValue = 500 }
			resolveTransfer(s, stolen, 1)
			expect(s.profile.Coins).to.equal(MAX_COINS)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract verification
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract verification", function()
		it("RaidService cooldowns read session-scoped os.clock() fields", function()
			expect(raidSource:find("session.raidAttackLastAt", 1, true)).to.be.a("number")
			expect(raidSource:find("session.raidTargetCooldowns", 1, true)).to.be.a("number")
		end)

		it("RaidService computes attacker cooldown end from config", function()
			expect(raidSource:find("cooldownEnd = last + GameConfig.Raid.raiderCooldownSeconds", 1, true)).to.be.a("number")
		end)

		it("validateAttacker rejects in gate order", function()
			local w = raidSource:find('return false, "window_closed"', 1, true)
			local n = raidSource:find('return false, "not_opted_in"', 1, true)
			local s = raidSource:find('return false, "safe_harbor_protected"', 1, true)
			local p = raidSource:find('return false, "new_player_protected"', 1, true)
			local st = raidSource:find('return false, "stunned"', 1, true)
			local c = raidSource:find('return false, "attacker_cooldown"', 1, true)
			expect(w).to.be.a("number")
			expect(w < n and n < s and s < p and p < st and st < c).to.equal(true)
		end)

		it("loss cap compares against GameConfig.Raid.maxLossesPerWindow", function()
			expect(raidSource:find("count >= (GameConfig.Raid.maxLossesPerWindow or 2)", 1, true)).to.be.a("number")
		end)

		it("challenge is built BEFORE cooldowns burn (xqd.4)", function()
			local challenge = raidSource:find("local center = rng:NextNumber(goodHalf, 1 - goodHalf)", 1, true)
			local burn = raidSource:find("commitAttackerCooldowns(session, targetUserId)", 1, true)
			expect(challenge).to.be.a("number")
			expect(burn).to.be.a("number")
			expect(challenge < burn).to.equal(true)
		end)

		it("single-resolution: activeRaids cleared before validation", function()
			expect(raidSource:find("activeRaids[player] = nil -- single-resolution", 1, true)).to.be.a("number")
		end)

		it("server clamps and re-derives tier from its own bounds", function()
			expect(raidSource:find("math.clamp(markerPosition, 0, 1)", 1, true)).to.be.a("number")
			expect(raidSource:find("position >= raid.perfectStart and position <= raid.perfectEnd", 1, true)).to.be.a("number")
		end)

		it("timing-forgery check uses position * duration minus grace", function()
			expect(raidSource:find("local minNeeded = position * duration", 1, true)).to.be.a("number")
			expect(raidSource:find("elapsed < (minNeeded - NETWORK_GRACE)", 1, true)).to.be.a("number")
		end)

		it("success roll caps forged clients at the tier chance", function()
			expect(raidSource:find("local chance = GameConfig.Raid.minigame.successChance[tier] or 0", 1, true)).to.be.a("number")
		end)

		it("steal pick weights Epic fish by the config multiplier", function()
			expect(raidSource:find('roll -= (fish.Rarity == "Epic") and epicMult or 1', 1, true)).to.be.a("number")
		end)

		it("transfer removes the fish at the TOCTOU-verified live index", function()
			expect(raidSource:find("stolenFish = table.remove(victimFish, liveIndex)", 1, true)).to.be.a("number")
		end)

		it("full-attacker fence path clamps coin payout", function()
			expect(raidSource:find("clampCoins(attackerSession.profile.Coins + stolenFish.BaseSellValue)", 1, true)).to.be.a("number")
		end)

		it("defender immunity is written as a wall-clock timestamp", function()
			expect(raidSource:find("RaidProtectionUntilTimestamp = os.time() + GameConfig.Raid.defenderProtectionSeconds", 1, true)).to.be.a("number")
		end)

		it("scheduler draws each gap independently from [min, max]", function()
			expect(raidSource:find("rng:NextNumber(cfg.windowIntervalMin, cfg.windowIntervalMax)", 1, true)).to.be.a("number")
		end)

		it("window serial bumps on every open", function()
			expect(raidSource:find("windowSerial += 1", 1, true)).to.be.a("number")
		end)

		it("test seams exist: _setRng, _setPlayersProvider, _setWindowOpen, _activeRaids", function()
			expect(raidSource:find("RaidService._setRng", 1, true)).to.be.a("number")
			expect(raidSource:find("RaidService._setPlayersProvider", 1, true)).to.be.a("number")
			expect(raidSource:find("RaidService._setWindowOpen", 1, true)).to.be.a("number")
			expect(raidSource:find("RaidService._activeRaids", 1, true)).to.be.a("number")
		end)

		it("GameConfig raid window: 20-30 min gap, 5 min duration", function()
			expect(gameConfigSource:find("windowIntervalMin = 20 * 60", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("windowIntervalMax = 30 * 60", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("windowDuration = 5 * 60", 1, true)).to.be.a("number")
		end)

		it("GameConfig raid cooldowns: 6min raider, 20min defender, 30min per-victim", function()
			expect(gameConfigSource:find("raiderCooldownSeconds = 6 * 60", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("defenderProtectionSeconds = 20 * 60", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("perVictimCooldownSeconds = 30 * 60", 1, true)).to.be.a("number")
		end)

		it("GameConfig raid caps: 1 fish per raid, 2 losses per window", function()
			expect(gameConfigSource:find("maxFishPerRaid = 1", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("maxLossesPerWindow = 2", 1, true)).to.be.a("number")
		end)

		it("GameConfig minigame: zones 0.12/0.30, chances 0.85/0.55/0.10", function()
			expect(gameConfigSource:find("perfectZoneSize = 0.12", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("goodZoneSize = 0.30", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("successChance = { perfect = 0.85, good = 0.55, ok = 0.10 }", 1, true)).to.be.a("number")
		end)

		it("GameConfig legendary protection: nonStealable + epic weight 0.3", function()
			expect(gameConfigSource:find("nonStealable = true", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("epicStealWeightMultiplier = 0.3", 1, true)).to.be.a("number")
		end)

		it("GameConfig raid unlock gate: 10 total catches", function()
			expect(gameConfigSource:find("unlockTotalCatches = 10", 1, true)).to.be.a("number")
		end)
	end)
end
