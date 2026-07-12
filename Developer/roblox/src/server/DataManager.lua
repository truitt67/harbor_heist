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
		dailyQuestKey = nil,
		dailyQuests = {},
		weeklyQuestKey = nil,
		weeklyQuests = {},
	}
end

-- SECURITY: Quests are persisted so rewards can't be re-claimed by rejoining.
-- Validate structure since DataStore contents may be corrupt.
local function sanitizeQuestList(list)
	local clean = {}
	if type(list) ~= "table" then
		return clean
	end
	for _, q in ipairs(list) do
		if type(q) == "table"
			and type(q.type) == "string"
			and type(q.target) == "number" and q.target > 0
			and type(q.reward) == "number" and q.reward >= 0
		then
			table.insert(clean, {
				id = type(q.id) == "string" and q.id or "",
				type = q.type,
				target = q.target,
				rarity = type(q.rarity) == "number" and q.rarity or nil,
				progress = type(q.progress) == "number" and math.clamp(q.progress, 0, q.target) or 0,
				claimed = q.claimed == true,
				reward = q.reward,
				desc = type(q.desc) == "string" and q.desc or "",
			})
		end
	end
	return clean
end

local function sanitize(data)
	local clean = defaultData()
	if type(data) ~= "table" then
		return clean
	end
	-- Validate cash - never negative; clamp (not reset) at the storage ceiling
	if type(data.cash) == "number" and data.cash >= 0 then
		clean.cash = math.min(data.cash, 999999999)
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
	if type(data.dailyQuestKey) == "string" then
		clean.dailyQuestKey = data.dailyQuestKey
	end
	if type(data.weeklyQuestKey) == "string" then
		clean.weeklyQuestKey = data.weeklyQuestKey
	end
	clean.dailyQuests = sanitizeQuestList(data.dailyQuests)
	clean.weeklyQuests = sanitizeQuestList(data.weeklyQuests)
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
		dailyQuestKey = data.dailyQuestKey,
		dailyQuests = data.dailyQuests,
		weeklyQuestKey = data.weeklyQuestKey,
		weeklyQuests = data.weeklyQuests,
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

	-- RELIABILITY: If a save is already in flight (e.g. autosave), WAIT for it
	-- instead of skipping - skipping the final save on leave/shutdown loses data.
	local waited = 0
	while session.isSaving and waited < 15 do
		task.wait(0.1)
		waited += 0.1
	end
	if session.isSaving then
		warn("[HarborHeist] Timed out waiting for in-flight save for " .. player.Name)
		return
	end

	session.isSaving = true
	
	local ok, err = withRetries(function()
		return dataStore:UpdateAsync(keyFor(player), function()
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
				dailyQuestKey = session.dailyQuestKey,
				dailyQuests = session.dailyQuests,
				weeklyQuestKey = session.weeklyQuestKey,
				weeklyQuests = session.weeklyQuests,
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
			-- RELIABILITY: save() yields, and players joining mid-loop would add
			-- new keys to `sessions` during pairs() traversal (undefined behavior
			-- that can error and kill this loop). Snapshot the list first.
			local players = {}
			for player in pairs(sessions) do
				table.insert(players, player)
			end
			for _, player in ipairs(players) do
				if sessions[player] then
					task.spawn(function()
						DataManager.save(player)
					end)
				end
			end
		end
	end)
end

function DataManager.bindToClose()
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		-- RELIABILITY: Save all players in parallel - sequential saves (each with
		-- retries) could easily blow past the 30s BindToClose budget.
		local remaining = 0
		for player in pairs(sessions) do
			remaining += 1
			task.spawn(function()
				-- RELIABILITY: pcall so an unexpected error can never leave the
				-- `remaining` counter stuck and hang BindToClose for the full 30s.
				pcall(DataManager.save, player)
				remaining -= 1
			end)
		end
		while remaining > 0 do
			task.wait(0.1)
		end
	end)
end

return DataManager
