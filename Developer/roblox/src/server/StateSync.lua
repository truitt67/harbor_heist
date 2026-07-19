local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local StateSync = {}

StateSync.remotes = nil

function StateSync.getCapacity(session)
	-- Local track: capacity is derived from UpgradeLevel in sanitize (N6 fix)
	-- and stored in profile.Aquarium.Capacity. This is the authoritative value.
	return session.profile.Aquarium.Capacity
end

function StateSync.incomePerSec(session)
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
	return total
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
		maxCarried = GameConfig.MaxCarried,
		liveWellCount = #aquarium.StoredFish,
		liveWellCounts = liveWellCounts,
		capacity = StateSync.getCapacity(session),
		incomePerSec = StateSync.incomePerSec(session),
		-- Local track: income pool + lock/steal timers
		unclaimedIncome = math.floor(aquarium.UnclaimedIncome),
		lockedUntil = math.max(0, session.lockedUntil - now),
		lockCooldownUntil = math.max(0, session.lockCooldownUntil - now),
		stealCooldownUntil = math.max(0, session.stealCooldownUntil - now),
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
