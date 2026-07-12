local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local DataManager = {}

local STORE_NAME = "HarborHeist_PlayerData_v1"
local dataStore = nil
local storeOk = pcall(function()
	dataStore = DataStoreService:GetDataStore(STORE_NAME)
end)

local sessions = {}

local function defaultData()
	return {
		cash = GameConfig.StartingCash,
		rodLevel = 1,
		baitLevel = 1,
		liveWell = {},
		capacityLevel = 0,
		lockLevel = 0,
		alarmLevel = 0,
	}
end

local function sanitize(data)
	local clean = defaultData()
	if type(data) ~= "table" then
		return clean
	end
	-- Validate cash - ensure it's never negative (exploit prevention)
	if type(data.cash) == "number" and data.cash >= 0 and data.cash < 999999999 then
		clean.cash = data.cash
	end
	if type(data.rodLevel) == "number" and GameConfig.Rods[data.rodLevel] then
		clean.rodLevel = data.rodLevel
	end
	if type(data.baitLevel) == "number" and GameConfig.Baits[data.baitLevel] then
		clean.baitLevel = data.baitLevel
	end
	if type(data.capacityLevel) == "number" and data.capacityLevel >= 0 and data.capacityLevel <= #GameConfig.Upgrades.Capacity then
		clean.capacityLevel = math.floor(data.capacityLevel)
	end
	if type(data.lockLevel) == "number" and data.lockLevel >= 0 and data.lockLevel <= #GameConfig.Upgrades.Lock then
		clean.lockLevel = math.floor(data.lockLevel)
	end
	if type(data.alarmLevel) == "number" and data.alarmLevel >= 0 and data.alarmLevel <= #GameConfig.Upgrades.Alarm then
		clean.alarmLevel = math.floor(data.alarmLevel)
	end
	if type(data.liveWell) == "table" then
		-- Validate each item in liveWell - ensure it's a valid rarity index
		for _, rarityIndex in ipairs(data.liveWell) do
			if type(rarityIndex) == "number" and rarityIndex >= 1 and rarityIndex <= #GameConfig.Rarities then
				table.insert(clean.liveWell, math.floor(rarityIndex))
			end
		end
	end
	return clean
end

local function keyFor(player)
	return "player_" .. player.UserId
end

local function withRetries(fn)
	local lastErr
	-- RELIABILITY: Use exponential backoff with jitter to avoid thundering herd
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		-- Exponential backoff: 0.5s, 1s, 2s, 4s with random jitter
		if attempt < 4 then
			local backoff = math.pow(2, attempt - 1) * 0.25 + math.random() * 0.25
			task.wait(backoff)
		end
	end
	return false, lastErr
end

function DataManager.load(player)
	local saved = nil
	if dataStore then
		local ok, result = withRetries(function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			saved = result
		else
			warn("[HarborHeist] Failed to load data for " .. player.Name .. ": " .. tostring(result))
		end
	end

	local data = sanitize(saved)
	local session = {
		player = player,
		cash = data.cash,
		rodLevel = data.rodLevel,
		baitLevel = data.baitLevel,
		liveWell = data.liveWell,
		capacityLevel = data.capacityLevel,
		lockLevel = data.lockLevel,
		alarmLevel = data.alarmLevel,
		carried = {}, -- SECURITY: Always initialize as empty table - client data is untrusted
		casting = false,
		castDeadline = 0,
		castHitZoneStart = 0,
		castHitZoneEnd = 0,
		lockedUntil = 0,
		lockCooldownUntil = 0,
		stealCooldownUntil = 0,
		stunUntil = 0,
		dockIndex = nil,
		isSaving = false, -- SECURITY: Lock flag to prevent concurrent saves
		dailyQuestKey = nil,
		dailyQuests = {},
		weeklyQuestKey = nil,
		weeklyQuests = {},
		boatModel = nil,
		boatDespawnTask = nil,
		seatConnection = nil,
		heistCount = 0, -- today's steal counter for quest hook
		incomeSinceTick = 0,
	}
	sessions[player] = session
	return session
end

function DataManager.get(player)
	return sessions[player]
end

function DataManager.save(player)
	local session = sessions[player]
	if not session or not dataStore then
		return
	end
	
	-- SECURITY: Prevent concurrent saves (race condition protection)
	if session.isSaving then
		warn("[HarborHeist] Save already in progress for " .. player.Name)
		return
	end
	
	session.isSaving = true
	
	local ok, err = withRetries(function()
		-- SECURITY: Use UpdateAsync instead of SetAsync to avoid overwriting concurrent writes
		-- This is critical for multi-server environments
		return dataStore:UpdateAsync(keyFor(player), function(oldData)
			-- Validate and sanitize old data in case of corruption
			local existing = sanitize(oldData)
			
			-- Calculate cash including carried items
			local cash = session.cash
			for _, rarityIndex in ipairs(session.carried) do
				if type(rarityIndex) == "number" and GameConfig.Rarities[rarityIndex] then
					cash += GameConfig.Rarities[rarityIndex].value
				end
			end
			
			-- Build new payload
			local payload = {
				cash = math.floor(math.max(0, cash)), -- Prevent negative cash
				rodLevel = session.rodLevel,
				baitLevel = session.baitLevel,
				liveWell = session.liveWell,
				capacityLevel = session.capacityLevel,
				lockLevel = session.lockLevel,
				alarmLevel = session.alarmLevel,
			}

			return payload
		end)
	end)
	
	session.isSaving = false
	
	if not ok then
		warn("[HarborHeist] Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
end

function DataManager.remove(player)
	-- RELIABILITY: Clean up all references to prevent memory leaks
	sessions[player] = nil
end

function DataManager.allSessions()
	return sessions
end

function DataManager.startAutosave()
	task.spawn(function()
		while true do
			task.wait(60)
			for player in pairs(sessions) do
				DataManager.save(player)
			end
		end
	end)
end

function DataManager.bindToClose()
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		for player in pairs(sessions) do
			DataManager.save(player)
		end
	end)
end

return DataManager
