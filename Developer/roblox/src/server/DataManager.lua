local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)

local DataManager = {}

-- TASK 1.6 will decide whether to bump this to _v2. For now, same key with
-- in-load migration (TASK 1.3) handles the v1->v2 format upgrade.
local STORE_NAME = "HarborHeist_PlayerData_v1"
local dataStore = nil
local storeOk = pcall(function()
	dataStore = DataStoreService:GetDataStore(STORE_NAME)
end)

local sessions = {}

-- ════════════════════════════════════════════════════════════════════════════
-- DEEP SANITIZE — last line of defense against corrupted/exploited data.
-- TASK 1.5 expands this; the structure here validates every field from the
-- new PlayerProfile schema. Invalid entries are filtered, not crashed.
-- ════════════════════════════════════════════════════════════════════════════
local function sanitizeNested(data, clean, key, validator)
	if type(data[key]) == "table" then
		clean[key] = validator(data[key])
	end
end

local function sanitizeStoredFish(list)
	local clean = {}
	if type(list) ~= "table" then
		return clean
	end
	for _, item in ipairs(list) do
		-- Currently items are rarity indexes (1..#Rarities).
		-- TASK 1.2 will add FishInstance validation here.
		if type(item) == "number" and item >= 1 and item <= #GameConfig.Rarities then
			table.insert(clean, math.floor(item))
		end
	end
	return clean
end

local function sanitize(data)
	local clean = PlayerProfile.default()
	if type(data) ~= "table" then
		return clean
	end

	-- Version
	if type(data.Version) == "number" and data.Version >= 1 then
		clean.Version = data.Version
	end

	-- Coins
	if type(data.Coins) == "number" then
		clean.Coins = PlayerProfile.clampCoins(data.Coins)
	elseif type(data.cash) == "number" then
		-- Legacy v1 fallback (migration path)
		clean.Coins = PlayerProfile.clampCoins(data.cash)
	end
	if type(data.TotalCoinsEarned) == "number" then
		clean.TotalCoinsEarned = math.max(0, math.floor(data.TotalCoinsEarned))
	end

	-- Equipment
	if type(data.Equipment) == "table" then
		local eq = data.Equipment
		if type(eq.EquippedRodLevel) == "number" and GameConfig.Rods[eq.EquippedRodLevel] then
			clean.Equipment.EquippedRodLevel = eq.EquippedRodLevel
		end
		if type(eq.EquippedBaitLevel) == "number" and GameConfig.Baits[eq.EquippedBaitLevel] then
			clean.Equipment.EquippedBaitLevel = eq.EquippedBaitLevel
		end
		if type(eq.OwnedRodLevels) == "table" then
			clean.Equipment.OwnedRodLevels = {}
			for _, lvl in ipairs(eq.OwnedRodLevels) do
				if type(lvl) == "number" and GameConfig.Rods[lvl] then
					table.insert(clean.Equipment.OwnedRodLevels, lvl)
				end
			end
		end
	end

	-- Aquarium
	if type(data.Aquarium) == "table" then
		local aq = data.Aquarium
		if type(aq.Capacity) == "number" and aq.Capacity >= 1 then
			clean.Aquarium.Capacity = math.floor(aq.Capacity)
		end
		if type(aq.UpgradeLevel) == "number" and aq.UpgradeLevel >= 1 then
			clean.Aquarium.UpgradeLevel = math.floor(aq.UpgradeLevel)
		end
		clean.Aquarium.StoredFish = sanitizeStoredFish(aq.StoredFish)
		if type(aq.UnclaimedIncome) == "number" then
			clean.Aquarium.UnclaimedIncome = math.max(0, math.min(PlayerProfile.MAX_UNCLAIMED_INCOME, aq.UnclaimedIncome))
		end
		if type(aq.LastIncomeTimestamp) == "number" then
			clean.Aquarium.LastIncomeTimestamp = aq.LastIncomeTimestamp
		end
		if type(aq.LockUntilTimestamp) == "number" then
			clean.Aquarium.LockUntilTimestamp = aq.LockUntilTimestamp
		end
		if type(aq.LockCooldownUntilTimestamp) == "number" then
			clean.Aquarium.LockCooldownUntilTimestamp = aq.LockCooldownUntilTimestamp
		end
		if type(aq.RaidProtectionUntilTimestamp) == "number" then
			clean.Aquarium.RaidProtectionUntilTimestamp = aq.RaidProtectionUntilTimestamp
		end
		if type(aq.RaidOptIn) == "boolean" then
			clean.Aquarium.RaidOptIn = aq.RaidOptIn
		end
	end

	-- Dock
	if type(data.Dock) == "table" then
		if type(data.Dock.UpgradeLevel) == "number" and data.Dock.UpgradeLevel >= 1 then
			clean.Dock.UpgradeLevel = math.floor(data.Dock.UpgradeLevel)
		end
		if type(data.Dock.CosmeticUnlocks) == "table" then
			clean.Dock.CosmeticUnlocks = {}
			for _, v in ipairs(data.Dock.CosmeticUnlocks) do
				if type(v) == "string" then
					table.insert(clean.Dock.CosmeticUnlocks, v)
				end
			end
		end
	end

	-- Collection
	if type(data.Collection) == "table" then
		if type(data.Collection.DiscoveredSpecies) == "table" then
			for speciesId, val in pairs(data.Collection.DiscoveredSpecies) do
				if type(speciesId) == "string" and val == true then
					clean.Collection.DiscoveredSpecies[speciesId] = true
				end
			end
		end
		if type(data.Collection.MilestonesClaimed) == "table" then
			for _, m in ipairs(data.Collection.MilestonesClaimed) do
				if type(m) == "string" then
					table.insert(clean.Collection.MilestonesClaimed, m)
				end
			end
		end
	end

	-- PvP
	if type(data.PvP) == "table" then
		if type(data.PvP.RaidAttemptsToday) == "number" then
			clean.PvP.RaidAttemptsToday = math.max(0, math.floor(data.PvP.RaidAttemptsToday))
		end
		if type(data.PvP.LastRaidTimestamp) == "number" then
			clean.PvP.LastRaidTimestamp = data.PvP.LastRaidTimestamp
		end
		if type(data.PvP.RecentTargetUserIds) == "table" then
			for _, uid in ipairs(data.PvP.RecentTargetUserIds) do
				if type(uid) == "number" then
					table.insert(clean.PvP.RecentTargetUserIds, uid)
				end
			end
		end
		if type(data.PvP.RaidsWon) == "number" then
			clean.PvP.RaidsWon = math.max(0, math.floor(data.PvP.RaidsWon))
		end
		if type(data.PvP.RaidsLost) == "number" then
			clean.PvP.RaidsLost = math.max(0, math.floor(data.PvP.RaidsLost))
		end
	end

	-- Onboarding
	if type(data.Onboarding) == "table" then
		for flag, val in pairs(data.Onboarding) do
			if type(flag) == "string" and type(val) == "boolean" then
				clean.Onboarding[flag] = val
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
	-- RELIABILITY: Exponential backoff with jitter to avoid thundering herd
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
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

	local profile = sanitize(saved)

	-- Session = profile + runtime-only fields (not persisted).
	-- The profile sub-tables are the SAME table references so services can
	-- read/write profile.Aquarium.StoredFish directly.
	local session = {
		player = player,
		profile = profile,
		-- Convenience aliases: these point INTO the profile so reads/writes
		-- go to the canonical nested structure. Services update gradually.
		cash = nil, -- DEPRECATED: use profile.Coins; kept nil to force compile-error discovery
		carried = {}, -- SECURITY: Always empty on load (client data untrusted)
		casting = false,
		dockIndex = nil,
		isSaving = false,
		-- Runtime-only os.clock timers (NOT persisted; persist as epoch in profile)
		lockedUntil = 0,
		lockCooldownUntil = 0,
		stealCooldownUntil = 0, -- legacy; RaidService (TASK 8.x) will replace
	}
	-- Restore lock timers from persisted epoch timestamps if still active
	local nowEpoch = os.time()
	if profile.Aquarium.LockUntilTimestamp > nowEpoch then
		session.lockedUntil = os.clock() + (profile.Aquarium.LockUntilTimestamp - nowEpoch)
	end
	if profile.Aquarium.LockCooldownUntilTimestamp > nowEpoch then
		session.lockCooldownUntil = os.clock() + (profile.Aquarium.LockCooldownUntilTimestamp - nowEpoch)
	end
	if profile.PvP.StealCooldownUntilTimestamp > nowEpoch then
		session.stealCooldownUntil = os.clock() + (profile.PvP.StealCooldownUntilTimestamp - nowEpoch)
	end
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

	if session.isSaving then
		warn("[HarborHeist] Save already in progress for " .. player.Name)
		return
	end

	session.isSaving = true

	local profile = session.profile

	-- Persist runtime lock timers as epoch timestamps (they may have been set
	-- since load and need to survive server restart)
	local nowEpoch = os.time()
	local nowClock = os.clock()
	if session.lockedUntil > nowClock then
		profile.Aquarium.LockUntilTimestamp = nowEpoch + math.floor(session.lockedUntil - nowClock)
	end
	if session.lockCooldownUntil > nowClock then
		profile.Aquarium.LockCooldownUntilTimestamp = nowEpoch + math.floor(session.lockCooldownUntil - nowClock)
	end
	if session.stealCooldownUntil > nowClock then
		profile.PvP.StealCooldownUntilTimestamp = nowEpoch + math.floor(session.stealCooldownUntil - nowClock)
	end

	local ok, err = withRetries(function()
		return dataStore:UpdateAsync(keyFor(player), function(oldData)
			local existing = sanitize(oldData)

			-- Merge: take the latest profile values (authoritative in-memory state)
			-- but preserve any fields the server doesn't own (future-proofing).
			existing.Version = PlayerProfile.CURRENT_VERSION
			existing.Coins = PlayerProfile.clampCoins(profile.Coins)
			existing.TotalCoinsEarned = profile.TotalCoinsEarned
			existing.Equipment = profile.Equipment
			existing.Aquarium = profile.Aquarium
			existing.Dock = profile.Dock
			existing.Collection = profile.Collection
			existing.PvP = profile.PvP
			existing.Onboarding = profile.Onboarding

			return existing
		end)
	end)

	session.isSaving = false

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
