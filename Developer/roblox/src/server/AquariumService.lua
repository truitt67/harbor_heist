local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local PlayerProfile = require(game:GetService("ReplicatedStorage").Shared.PlayerProfile)

local AquariumService = {}

function AquariumService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService
	local analytics = deps.analytics -- EPIC 11
	local antiExploit = deps.antiExploit -- EPIC 10
	local auditLog = deps.auditLog -- EPIC 10 / TASK 10.3
	local onboarding = deps.onboarding -- EPIC 9

	local function refreshVisual(session)
		local dock = dockManager.getDock(session.player)
		if dock then
			dockManager.updateAquariumVisual(dock, session, stateSync.getCapacity(session))
		end
	end
	AquariumService.refreshVisual = function(session)
		refreshVisual(session)
	end

	remotes.StoreFish.OnServerInvoke = function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "store")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local storedFish = session.profile.Aquarium.StoredFish
		local capacity = stateSync.getCapacity(session)
		local stored = 0
		while #session.carried > 0 and #storedFish < capacity do
			local fish = table.remove(session.carried)
			table.insert(storedFish, fish)
			stored += 1
		end
		if stored == 0 then
			if #session.carried == 0 then
				remotes.notify(player, "You have no fish to store. Go fish!", Color3.fromRGB(255, 170, 80))
			else
				remotes.notify(player, "Your aquarium is full! Sell some fish.", Color3.fromRGB(255, 170, 80))
			end
		else
			remotes.notify(
				player,
				string.format("Stored %d fish. They now earn you cash every second!", stored),
				Color3.fromRGB(120, 220, 255)
			)
		end
		if auditLog and stored > 0 then
			local totalVal = 0
			for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
				totalVal += fish.BaseSellValue or 0
			end
			auditLog.logStore(player, stored, totalVal)
		end
		refreshVisual(session)
		-- TASK 14.15 (wqw.15): fish were added to StoredFish, so invalidate
		-- the cached incomePerSec before the push repopulates it.
		if stored > 0 then
			stateSync.invalidateIncomeCache(session)
		end
		stateSync.push(session)
		-- TASK 12.2 (thj.2): persist when fish are stored (not just autosave).
		-- Spawned so the handler returns immediately; coalesced by
		-- DataManager.save's isSaving guard. Only save when something was
		-- actually stored (stored > 0) to avoid no-op writes.
		if stored > 0 then
			task.spawn(function()
				dataManager.save(player)
			end)
		end
		if stored > 0 and questService then
			questService.onFishStored(session, stored)
		end
		-- EPIC 9 (TASK 9.1): flip the first-store onboarding flag (bulk path).
		if stored > 0 and onboarding then
			onboarding.mark(session, "HasStoredFirstFish")
		end
		return { ok = stored > 0, stored = stored }
	end

	remotes.ClaimIncome.OnServerInvoke = function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "claim")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		local unclaimed = session.profile.Aquarium.UnclaimedIncome
		if unclaimed <= 0 then
			return { ok = false, reason = "nothing_to_claim" }
		end
		-- Transfer unclaimed income to coins
		-- N5: route every coin write through clampCoins so the MAX_COINS cap
		-- cannot be overflowed by claiming a large pool near the ceiling.
		session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + unclaimed)
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + unclaimed
		session.profile.Aquarium.UnclaimedIncome = 0
		if auditLog then
			auditLog.logClaim(player, unclaimed)
		end
		remotes.notify(player, string.format("Claimed $%d in aquarium income!", unclaimed), Color3.fromRGB(130, 255, 130))
		stateSync.push(session)
		-- EPIC 11 (TASK 11.2): income_claimed. Amount is the key field —
		-- dashboard uses it to track economy flow + claim frequency.
		if analytics then
			analytics.track(player, "income_claimed", { amount = unclaimed })
		end
		-- EPIC 9 (TASK 9.1): flip the first-claim onboarding flag. Idempotent.
		if onboarding then
			onboarding.mark(session, "HasClaimedIncome")
		end
		return { ok = true, amount = unclaimed }
	end

	remotes.SellAll.OnServerInvoke = function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "sell")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local storedFish = session.profile.Aquarium.StoredFish
		-- TASK 14.6 (wqw.6): a locked aquarium blocks removal of stored fish
		-- (PRD AQUA: locks block ALL theft and modification). Previously SellAll
		-- liquidated stored fish during an active lock, enabling lock-then-sell
		-- before a raid and making the lock mechanic theater. Carried fish are
		-- not in the aquarium, so they remain sellable while locked.
		local locked = (session.lockedUntil or 0) > os.clock()
		local payout = 0
		local storedCount = #storedFish
		local carriedCount = #session.carried
		if not locked then
			for _, fish in ipairs(storedFish) do
				payout += fish.BaseSellValue
			end
		end
		for _, fish in ipairs(session.carried) do
			payout += fish.BaseSellValue
		end
		if payout <= 0 then
			if locked and storedCount > 0 then
				remotes.notify(player, "Aquarium is locked — stored fish can't be sold until the lock expires.", Color3.fromRGB(255, 170, 80))
				return { ok = false, reason = "aquarium_locked" }
			end
			remotes.notify(player, "No fish to sell!", Color3.fromRGB(255, 170, 80))
			return { ok = false }
		end
		local soldCount = carriedCount
		if not locked then
			for i = #storedFish, 1, -1 do
				storedFish[i] = nil
			end
			soldCount += storedCount
		end
		for i = #session.carried, 1, -1 do
			session.carried[i] = nil
		end
		session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + payout)
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + payout
		if auditLog then
			auditLog.logSell(player, soldCount, payout)
		end
		if locked then
			remotes.notify(player, string.format("Sold %d carried fish for $%d! (Stored fish untouched — aquarium locked)", soldCount, payout), Color3.fromRGB(130, 255, 130))
		else
			remotes.notify(player, string.format("Sold all fish for $%d!", payout), Color3.fromRGB(130, 255, 130))
		end
		refreshVisual(session)
		-- TASK 14.15 (wqw.15): stored fish were removed only when not locked,
		-- so invalidate the cached incomePerSec in that case. Carried-only sells
		-- (locked) don't change income and don't need invalidation.
		if not locked and storedCount > 0 then
			stateSync.invalidateIncomeCache(session)
		end
		stateSync.push(session)
		-- TASK 12.2 (thj.2): persist on sell (not just autosave + leave).
		-- Spawned so the handler returns immediately; coalesced by
		-- DataManager.save's isSaving guard. payout > 0 is guaranteed by the
		-- early return above, so this is always a real transaction.
		task.spawn(function()
			dataManager.save(player)
		end)
		if questService then
			questService.onFishSold(session, payout)
		end
		return { ok = true, payout = payout }
	end

	-- TASK 8.4 (gdj.4): Lock system rework — limited free uses + cooldown.
	-- PRD PVP-03: "activate a temporary aquarium lock using an earned in-game
	-- resource, cooldown, or limited free uses." Design: 3 free uses per
	-- session (tracked in profile.Defense.LockFreeUsesRemaining), then cooldown
	-- gates further uses. Free uses regenerate on daily reset (future) or can
	-- be purchased (future). For V1: free uses + cooldown, no purchase.
	remotes.LockAquarium.OnServerInvoke = function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "lock")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local now = os.clock()
		if (session.lockedUntil or 0) > now then
			return { ok = false, reason = "already_locked" }
		end
		if (session.lockCooldownUntil or 0) > now then
			remotes.notify(
				player,
				string.format("Lock recharging... %ds left.", math.ceil(session.lockCooldownUntil - now)),
				Color3.fromRGB(255, 170, 80)
			)
			return { ok = false, reason = "cooldown" }
		end
		-- TASK 8.4: check free-use budget. If exhausted, still allow lock but
		-- with a longer cooldown (2x) to discourage spam. Free uses are the
		-- "earned resource" — they regenerate via daily reset (future bead).
		local defense = session.profile.Defense
		if not defense then
			defense = { LockFreeUsesRemaining = 3, LockFreeUsesMax = 3 }
			session.profile.Defense = defense
		end
		local freeUses = defense.LockFreeUsesRemaining or 0
		local hasFreeUse = freeUses > 0

		-- Upgrade-scaled lock duration. The base config is the fallback; each
		-- Lock tier in GameConfig.Upgrades.Lock overrides duration + cooldown.
		-- N7: previously this block was a stub (`if UpgradeLevel > 1 then` with
		-- an empty body), so buying Lock I/II/III changed nothing about the lock.
		local lockLevel = session.profile.Aquarium.LockLevel or 0
		local lockDuration = GameConfig.Aquarium.lockDuration
		local lockCooldown = GameConfig.Aquarium.lockCooldown
		if lockLevel > 0 and GameConfig.Upgrades.Lock[lockLevel] then
			local tier = GameConfig.Upgrades.Lock[lockLevel]
			lockDuration = tier.lockDuration
			lockCooldown = tier.lockCooldown
		end
		-- If no free uses left, double the cooldown (soft gate, not hard block).
		if not hasFreeUse then
			lockCooldown = lockCooldown * 2
		end
		session.lockedUntil = now + lockDuration
		session.lockCooldownUntil = session.lockedUntil + lockCooldown
		-- Consume a free use if available.
		if hasFreeUse then
			defense.LockFreeUsesRemaining = freeUses - 1
		end
		-- Generation token: a re-lock invalidates any pending "lock expired"
		-- notification from a previous lock's delayed closure.
		session.lockGeneration = (session.lockGeneration or 0) + 1
		local generation = session.lockGeneration
		-- Also persist as epoch timestamps (TASK 1.1: structured profile)
		session.profile.Aquarium.LockUntilTimestamp = os.time() + lockDuration
		session.profile.Aquarium.LockCooldownUntilTimestamp = os.time() + lockDuration + lockCooldown
		if hasFreeUse then
			remotes.notify(
				player,
				string.format("Aquarium locked for %ds! (%d free uses left)", lockDuration, defense.LockFreeUsesRemaining),
				Color3.fromRGB(130, 255, 130)
			)
		else
			remotes.notify(
				player,
				string.format("Aquarium locked for %ds. (No free uses — longer recharge)", lockDuration),
				Color3.fromRGB(130, 255, 130)
			)
		end
		refreshVisual(session)
		stateSync.push(session)
		if auditLog then
			auditLog.logLock(player, lockDuration, defense.LockFreeUsesRemaining)
		end
		-- EPIC 11 (TASK 11.2): aquarium_locked. Tracks defensive engagement.
		if analytics then
			analytics.track(player, "aquarium_locked", {
				lock_level = lockLevel,
				duration = lockDuration,
				used_free = hasFreeUse,
				free_remaining = defense.LockFreeUsesRemaining,
			})
		end
		task.delay(lockDuration, function()
			if session.player.Parent and session.lockGeneration == generation then
				refreshVisual(session)
				stateSync.push(session)
				remotes.notify(session.player, "Your aquarium lock expired. Watch out for thieves!", Color3.fromRGB(255, 170, 80))
			end
		end)
		return { ok = true, usedFree = hasFreeUse, freeRemaining = defense.LockFreeUsesRemaining }
	end

	-- TASK 8.2 (gdj.2): Raid opt-in toggle. PRD PVP-02: "A player can raid only
	-- during a clearly labeled raid window or after explicitly opting into a
	-- risk zone." The opt-in flag lives in profile.Aquarium.RaidOptIn (schema
	-- already exists, TASK 1.1). This remote lets the client toggle it.
	-- Server validates: new-player protection gate (8.3) must be passed before
	-- opt-in is allowed — a new player who hasn't met the progression threshold
	-- cannot opt in, preventing accidental exposure.
	remotes.RequestToggleRaidOptIn.OnServerInvoke = function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "raid_opt_in")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		-- TASK 8.3 (gdj.3): new-player protection gate. DEC-4 double gate:
		-- (1) progression: first aquarium upgrade OR 10 catches, (2) opt-in.
		-- Use max of Stats and PvP counters so a legacy save with only PvP
		-- populated still counts (elseif would drop PvP when Stats=0).
		local statsCatches = (session.profile.Stats and session.profile.Stats.TotalCatches) or 0
		local pvpCatches = (session.profile.PvP and session.profile.PvP.TotalCatches) or 0
		local totalCatches = math.max(statsCatches, pvpCatches)
		local hasUpgrade = (session.profile.Aquarium.UpgradeLevel or 1) > 1
		local hasEnoughCatches = totalCatches >= 10
		if not hasUpgrade and not hasEnoughCatches then
			remotes.notify(
				player,
				string.format("You need an aquarium upgrade or 10 catches to enable raids. (%d/10 catches)", totalCatches),
				Color3.fromRGB(255, 170, 80)
			)
			return { ok = false, reason = "new_player_protected", catches = totalCatches }
		end
		local newValue = not session.profile.Aquarium.RaidOptIn
		session.profile.Aquarium.RaidOptIn = newValue
		if newValue then
			remotes.notify(player, "Raid opt-in ENABLED. Your aquarium can be targeted during raid windows!", Color3.fromRGB(255, 170, 80))
		else
			remotes.notify(player, "Raid opt-in DISABLED. Your aquarium is safe from raids.", Color3.fromRGB(130, 255, 130))
		end
		stateSync.push(session)
		if analytics then
			analytics.track(player, "raid_opt_in_toggled", { enabled = newValue })
		end
		if onboarding then
			onboarding.mark(session, "HasSeenRaidExplanation")
		end
		return { ok = true, raidOptIn = newValue }
	end

	AquariumService.refreshVisual = refreshVisual
end

-- TASK 8.3 (gdj.3): New-player protection gate — server-side eligibility check.
-- DEC-4: Double gate — (1) progression: first aquarium upgrade OR 10 catches,
-- (2) raid window opt-in. Both required to participate in raids (attack or be
-- targeted). This function is the single source of truth for "is this player
-- eligible for raid participation?" Used by 8.2 opt-in toggle and 8.5a target
-- selection.
function AquariumService.isNewPlayerProtected(session)
	if not session or not session.profile then
		return true
	end
	local statsCatches = (session.profile.Stats and session.profile.Stats.TotalCatches) or 0
	local pvpCatches = (session.profile.PvP and session.profile.PvP.TotalCatches) or 0
	local totalCatches = math.max(statsCatches, pvpCatches)
	local hasUpgrade = (session.profile.Aquarium.UpgradeLevel or 1) > 1
	local hasEnoughCatches = totalCatches >= 10
	return not hasUpgrade and not hasEnoughCatches
end

-- TASK 8.3: Check if a session is eligible to be a raid target.
-- A player is a valid target only if: not new-player-protected, opted in,
-- not currently locked, not under raid protection immunity, and has at least
-- one stealable (non-protected) fish.
function AquariumService.isEligibleRaidTarget(session)
	if not session or not session.profile then
		return false, "no_session"
	end
	if AquariumService.isNewPlayerProtected(session) then
		return false, "new_player_protected"
	end
	if not session.profile.Aquarium.RaidOptIn then
		return false, "not_opted_in"
	end
	if session.lockedUntil and session.lockedUntil > os.clock() then
		return false, "locked"
	end
	-- Raid protection immunity (defender was recently raided)
	local protectionUntil = session.profile.Aquarium.RaidProtectionUntilTimestamp or 0
	if protectionUntil > os.time() then
		return false, "raid_protection"
	end
	-- TASK 8.8 (gdj.8): must have at least one non-protected fish to be worth targeting
	if not AquariumService.hasStealableFish(session) then
		return false, "no_stealable_fish"
	end
	return true, "ok"
end

-- TASK 8.3: Check if a session is eligible to INITIATE a raid.
-- Attacker must: not be new-player-protected, be opted in, not be stunned.
function AquariumService.isEligibleRaidAttacker(session)
	if not session or not session.profile then
		return false, "no_session"
	end
	if AquariumService.isNewPlayerProtected(session) then
		return false, "new_player_protected"
	end
	if not session.profile.Aquarium.RaidOptIn then
		return false, "not_opted_in"
	end
	if session.stunUntil and session.stunUntil > os.clock() then
		return false, "stunned"
	end
	return true, "ok"
end

-- TASK 8.8 (gdj.8): Legendary fish raid protection (PVP-08).
-- PRD: "Legendary fish either non-stealable or much lower raid probability."
-- V1: Legendary fish are non-stealable (IsRaidProtected=true on FishInstance).
-- These helpers filter the aquarium's fish list for raid eligibility.

--- Returns true if the session has at least one fish that can be stolen.
function AquariumService.hasStealableFish(session)
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

--- Returns a list of stealable fish (non-protected) from the session's aquarium.
function AquariumService.getStealableFish(session)
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

--- Returns a list of protected fish (Legendary) from the session's aquarium.
function AquariumService.getProtectedFish(session)
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

-- TASK 8.0 (gdj.15): the legacy always-on steal handler was REMOVED. The old
-- prototype allowed any player to walk up to any aquarium and steal fish via
-- proximity prompt (50% RNG, 20s cooldown, no windows, no opt-in, no
-- protection) — directly violating the PRD's "opt-in, no griefing" promise.
-- PvP moves to the scheduled RaidService (Epic 8) with opt-in raid windows,
-- new-player protection, and a proper outcome resolution flow. Until then,
-- aquarium proximity prompts only open the owner's panel.

function AquariumService.startIncomeLoop(deps)
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync
	local questService = deps.questService
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
		-- Snapshot sessions to avoid mutation-during-iteration if a player
			-- leaves mid-tick (RedBear's safety pattern).
			local sessionsSnapshot = {}
			for k, session in pairs(dataManager.allSessions()) do
				sessionsSnapshot[k] = session
			end
			for _, session in pairs(sessionsSnapshot) do
				-- TASK 5.1: Accrue income to UnclaimedIncome pool (not auto-cash)
				local income = stateSync.incomePerSec(session) * GameConfig.IncomeTickSeconds
				if income > 0 then
					local unclaimed = session.profile.Aquarium.UnclaimedIncome
					local maxUnclaimed = GameConfig.Economy.MaxUnclaimedIncome
					session.profile.Aquarium.UnclaimedIncome = math.min(unclaimed + income, maxUnclaimed)
					if questService then
						questService.onIncomeEarned(session, income)
					end
				end
				if session.player and session.player.Parent then
					stateSync.push(session)
				end
			end
		end
	end)
end

return AquariumService
