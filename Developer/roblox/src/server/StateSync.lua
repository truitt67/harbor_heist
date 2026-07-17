local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local StateSync = {}

StateSync.remotes = nil

function StateSync.getCapacity(session)
	-- Read from profile.Aquarium.Capacity (TASK 1.1 structured profile)
	return session.profile.Aquarium.Capacity
end

function StateSync.incomePerSec(session)
	local total = 0
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		total += fish.IncomePerMinute / 60
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
		cash = math.floor(profile.Coins),
		rodLevel = profile.Equipment.EquippedRodLevel,
		baitLevel = profile.Equipment.EquippedBaitLevel,
		carried = #session.carried,
		maxCarried = GameConfig.MaxCarried,
		liveWellCount = #aquarium.StoredFish,
		liveWellCounts = liveWellCounts,
		capacity = StateSync.getCapacity(session),
		incomePerSec = StateSync.incomePerSec(session),
		-- os.clock() for runtime UI timers (these are session-relative, not persisted)
		lockRemaining = math.max(0, session.lockedUntil - now),
		lockCooldownRemaining = math.max(0, session.lockCooldownUntil - now),
	}
end

function StateSync.push(session)
	local player = session.player
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
