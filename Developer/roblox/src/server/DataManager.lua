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
	}
end

local function sanitize(data)
	local clean = defaultData()
	if type(data) ~= "table" then
		return clean
	end
	if type(data.cash) == "number" and data.cash >= 0 then
		clean.cash = data.cash
	end
	if type(data.rodLevel) == "number" and GameConfig.Rods[data.rodLevel] then
		clean.rodLevel = data.rodLevel
	end
	if type(data.baitLevel) == "number" and GameConfig.Baits[data.baitLevel] then
		clean.baitLevel = data.baitLevel
	end
	if type(data.liveWell) == "table" then
		for _, rarityIndex in ipairs(data.liveWell) do
			if type(rarityIndex) == "number" and GameConfig.Rarities[rarityIndex] then
				table.insert(clean.liveWell, rarityIndex)
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
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(attempt)
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
		carried = {},
		casting = false,
		lockedUntil = 0,
		lockCooldownUntil = 0,
		stealCooldownUntil = 0,
		dockIndex = nil,
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
	local cash = session.cash
	for _, rarityIndex in ipairs(session.carried) do
		cash += GameConfig.Rarities[rarityIndex].value
	end
	local payload = {
		cash = math.floor(cash),
		rodLevel = session.rodLevel,
		baitLevel = session.baitLevel,
		liveWell = session.liveWell,
	}
	local ok, err = withRetries(function()
		dataStore:SetAsync(keyFor(player), payload)
	end)
	if not ok then
		warn("[HarborHeist] Failed to save data for " .. player.Name .. ": " .. tostring(err))
	end
end

function DataManager.remove(player)
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
