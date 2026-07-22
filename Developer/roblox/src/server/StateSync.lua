local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local StateSync = {}

StateSync.remotes = nil

function StateSync.getCapacity(session)
	-- Local track: capacity is derived from UpgradeLevel in sanitize (N6 fix)
	-- and stored in profile.Aquarium.Capacity. This is the authoritative value.
	return session.profile.Aquarium.Capacity
end

function StateSync.incomePerSec(session)
	-- TASK 14.15 (wqw.15): cache incomePerSec on the session to avoid the
	-- per-second O(fish) recompute in the income loop + on every snapshot
	-- push. Invalidated by StateSync.invalidateIncomeCache on StoredFish
	-- mutations + aquarium/dock upgrades. Nil-check (not truthiness) so a
	-- legit 0 (empty aquarium) stays cached instead of recomputing each tick.
	if session.cachedIncomePerSec ~= nil then
		return session.cachedIncomePerSec
	end
	local total = 0
	-- Local track: iterate rich FishInstance records with IncomePerMinute
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		total += fish.IncomePerMinute / 60
	end
	-- N13: apply the aquarium tier income multiplier. AquariumUpgradeTiers
	-- defines a per-level multiplier (1.0 at level 1, up to 1.5 at level 4)
	-- that was advertised in the shop but never actually applied to income,
	-- so buying a bigger tank gave more capacity but NOT the promised income
	-- bonus. This is the missing consumer.
	local upLevel = session.profile.Aquarium.UpgradeLevel or 1
	local tier = GameConfig.AquariumUpgradeTiers[upLevel]
	if tier and tier.incomeMultiplier then
		total *= tier.incomeMultiplier
	end
	-- N17 (TASK 17.3): apply the dock tier income multiplier. DockUpgradeTiers
	-- defines a larger per-level multiplier (1.0 at level 1, up to 1.6 at
	-- level 4) as a second parallel investment track. Stacks multiplicatively
	-- with the aquarium multiplier: maxed players get 1.5 * 1.6 = 2.4x base
	-- income per fish.
	local dockLevel = session.profile.Dock.UpgradeLevel or 1
	local dockTier = GameConfig.DockUpgradeTiers[dockLevel]
	if dockTier and dockTier.incomeMultiplier then
		total *= dockTier.incomeMultiplier
	end
	session.cachedIncomePerSec = total
	return total
end

-- TASK 14.15 (wqw.15): invalidate the cached incomePerSec. Call on every
-- StoredFish mutation (store/sell) and on aquarium/dock upgrade purchases.
-- The income loop only accrues UnclaimedIncome so it does NOT invalidate.
-- The future raid steal handler (gdj.14) MUST also call this on the victim,
-- or its cached income figure goes stale.
function StateSync.invalidateIncomeCache(session)
	if session ~= nil then
		session.cachedIncomePerSec = nil
	end
end

function StateSync.snapshot(session)
	local now = os.clock()
	local profile = session.profile
	local aquarium = profile.Aquarium
	local liveWellCounts = {}
	for _, fish in ipairs(aquarium.StoredFish) do
		local key = fish.Rarity
		liveWellCounts[key] = (liveWellCounts[key] or 0) + 1
	end
	return {
		-- Local track fields (profile-backed)
		cash = math.floor(profile.Coins),
		totalEarned = math.floor(profile.TotalCoinsEarned),
		rodLevel = profile.Equipment.EquippedRodLevel,
		baitLevel = profile.Equipment.EquippedBaitLevel,
		-- N8: expose defense upgrade levels so the client shop + aquarium
		-- panels reflect purchased tiers. Previously these were always nil
		-- on the client, so owned upgrades showed as level 0 / locked.
		upgradeLevel = profile.Aquarium.UpgradeLevel or 1,
		lockLevel = profile.Aquarium.LockLevel or 0,
		alarmLevel = profile.Aquarium.AlarmLevel or 0,
		-- N17 (TASK 17.4): expose dock tier so the client shop reflects
		-- owned/locked/affordable states for the dock upgrade track.
		dockLevel = profile.Dock.UpgradeLevel or 1,
		-- N9 (TASK 9.1): expose onboarding progression flags so the client can
		-- drive contextual prompts (9.2). The flags are tracked server-side
		-- (OnboardingService.mark) but were NOT in the snapshot — so the push
		-- that mark() fires on every flip sent a snapshot with NO onboarding
		-- data, and the client could never see them. The whole flag pipeline
		-- was a black hole until this field existed.
		onboarding = profile.Onboarding,
		-- RedBear additions: stun + boat state (session-scoped, nil-safe)
		stunRemaining = math.max(0, (session.stunUntil or 0) - now),
		hasBoat = (session.boatModel ~= nil),
		-- Shared fields (both tracks)
		carried = #session.carried,
		-- TASK 4.4 (0cw.4 / wqw.18): per-fish carried records so the client
		-- inventory panel can render a row per fish (species/rarity/value)
		-- with SELL + STORE buttons. FishInstance fields are plain data
		-- (strings/numbers), safe to replicate. Max GameConfig.MaxCarried
		-- entries, ~100 bytes each — negligible payload growth.
		carriedFish = session.carried,
		maxCarried = GameConfig.MaxCarried,
		liveWellCount = #aquarium.StoredFish,
		liveWellCounts = liveWellCounts,
		capacity = StateSync.getCapacity(session),
		incomePerSec = StateSync.incomePerSec(session),
		-- Local track: income pool + lock/steal timers
		unclaimedIncome = math.floor(aquarium.UnclaimedIncome),
		lockedUntil = math.max(0, (session.lockedUntil or 0) - now),
		lockCooldownUntil = math.max(0, (session.lockCooldownUntil or 0) - now),
		-- TASK 8.2/8.3 (gdj.2/gdj.3): raid dock-flag + eligibility for client HUD.
		-- totalCatches drives the "10 catches" half of DEC-4; raidOptIn is the opt-in flag.
		raidOptIn = aquarium.RaidOptIn == true,
		totalCatches = math.max((profile.Stats and profile.Stats.TotalCatches) or 0, (profile.PvP and profile.PvP.TotalCatches) or 0),
		-- TASK 8.4 (gdj.4): expose lock free-use counts for client UI.
		lockFreeUsesRemaining = (profile.Defense and profile.Defense.LockFreeUsesRemaining) or 0,
		lockFreeUsesMax = (profile.Defense and profile.Defense.LockFreeUsesMax) or GameConfig.Defense.LockFreeUsesMax,
		-- TASK 8.0 (gdj.15): stealCooldownUntil snapshot field REMOVED with the
		-- always-on steal handler. Client never consumed it; no replacement.
		-- TASK 10.5: DataStore health (overridden in GetState with live check)
		dataStoreHealthy = true,
		dockIndex = session.dockIndex,
	}
end

function StateSync.push(session)
	local player = session.player
	-- RELIABILITY: Callers include deferred task.delay callbacks; the player may
	-- have left by the time this runs.
	if not player or not player.Parent then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cashValue = leaderstats:FindFirstChild("Cash")
		if cashValue then
			cashValue.Value = math.floor(session.profile.Coins)
		end
	end
	StateSync.remotes.StateChanged:FireClient(player, StateSync.snapshot(session))
end

function StateSync.setupLeaderstats(player, session)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = math.floor(session.profile.Coins)
	cash.Parent = leaderstats
	leaderstats.Parent = player
end

return StateSync
