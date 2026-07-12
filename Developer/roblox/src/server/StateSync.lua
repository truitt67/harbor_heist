local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local StateSync = {}

StateSync.remotes = nil

function StateSync.getCapacity(session)
	local baseCapacity = GameConfig.Aquarium.baseCapacity
	if session and session.capacityLevel and session.capacityLevel > 0 then
		local upgrade = GameConfig.Upgrades.Capacity[session.capacityLevel]
		if upgrade then
			return upgrade.capacity
		end
	end
	return baseCapacity
end

function StateSync.incomePerSec(session)
	local total = 0
	for _, rarityIndex in ipairs(session.liveWell) do
		local rarity = GameConfig.Rarities[rarityIndex]
		if rarity and rarity.incomePerSec then
			total += rarity.incomePerSec
		end
	end
	return total
end

function StateSync.snapshot(session)
	local now = os.clock()
	local liveWellCounts = {}
	for _, rarityIndex in ipairs(session.liveWell) do
		local key = tostring(rarityIndex)
		liveWellCounts[key] = (liveWellCounts[key] or 0) + 1
	end
	return {
		cash = math.floor(session.cash),
		rodLevel = session.rodLevel,
		baitLevel = session.baitLevel,
		capacityLevel = session.capacityLevel or 0,
		lockLevel = session.lockLevel or 0,
		alarmLevel = session.alarmLevel or 0,
		carried = #session.carried,
		maxCarried = GameConfig.MaxCarried,
		liveWellCount = #session.liveWell,
		liveWellCounts = liveWellCounts,
		capacity = StateSync.getCapacity(session),
		incomePerSec = StateSync.incomePerSec(session),
		lockRemaining = math.max(0, session.lockedUntil - now),
		lockCooldownRemaining = math.max(0, session.lockCooldownUntil - now),
		stunRemaining = math.max(0, (session.stunUntil or 0) - now),
		hasBoat = (session.boatModel ~= nil),
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
			cashValue.Value = math.floor(session.cash)
		end
	end
	StateSync.remotes.StateChanged:FireClient(player, StateSync.snapshot(session))
end

function StateSync.setupLeaderstats(player, session)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = math.floor(session.cash)
	cash.Parent = leaderstats
	leaderstats.Parent = player
end

return StateSync
