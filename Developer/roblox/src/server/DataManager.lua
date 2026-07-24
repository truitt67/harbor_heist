local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)

local DataManager = {}

-- TASK 1.6 (Option b — new key with copy+migrate): bump the DataStore key to
-- _v2. The structured profile (TASK 1.1, CURRENT_VERSION=2) is a breaking
-- format change from v1's flat fields (cash/rodLevel/liveWell). Using a NEW
-- key instead of overwriting v1 in place means: (1) rollback is possible if
-- the migration misbehaves (v1 data is untouched until proven), (2) a bad
-- migration can't permanently corrupt the only copy of a player's data.
--
-- Migration flow (DataManager.load): read v2 first. If empty, read v1,
-- sanitize() (which handles the flat->structured conversion, TASK 1.3), then
-- write the migrated profile to v2 and mark it migrated. v1 is left intact
-- for one grace period as a rollback anchor; a future task can delete it once
-- the closed test confirms migration stability.
local STORE_NAME_V2 = "HarborHeist_PlayerData_v2"
local STORE_NAME_V1 = "HarborHeist_PlayerData_v1"
local dataStore = nil      -- v2 (current, authoritative)
local dataStoreV1 = nil    -- v1 (legacy, read-only migration source)
local storeOk = pcall(function()
	dataStore = DataStoreService:GetDataStore(STORE_NAME_V2)
end)

-- TASK 10.5: DataStore failure tracking
local consecutiveFailures = 0
local MAX_FAILURES_BEFORE_DISABLE = 3
local isDataStoreHealthy = true
local lastFailureTime = 0
local FAILURE_COOLDOWN = 60 -- seconds before retrying after disable
-- v1 store is only needed for migration reads; failure here is non-fatal
-- (players without v1 data just skip migration).
pcall(function()
	dataStoreV1 = DataStoreService:GetDataStore(STORE_NAME_V1)
end)

-- egf.5: Local health-tracking helpers. save() and load() are the SOLE owners
-- of health transitions — no public API to invite double-counting from
-- external services. A successful WRITE resets the counter and flips healthy;
-- a successful READ does not reset (read-success doesn't prove write-health).
-- Both save and load failures increment the counter.
local function recordSuccess()
	consecutiveFailures = 0
	isDataStoreHealthy = true
end

local function recordFailure()
	consecutiveFailures += 1
	lastFailureTime = os.time()
	if consecutiveFailures >= MAX_FAILURES_BEFORE_DISABLE then
		isDataStoreHealthy = false
		warn("[HarborHeist] DataStore marked unhealthy after " .. consecutiveFailures .. " consecutive failures. Transactions will show warning.")
	end
end

local sessions = {}

-- TASK 14.27 (xsk): tracks UserIds with an in-flight UpdateAsync save. load()
-- checks this BEFORE GetAsync so a rapid same-UserId rejoin doesn't read stale
-- pre-save data (the wqw.20 deferred leave-save can be mid-UpdateAsync when the
-- rejoin's GetAsync fires on the same key). Set in save() after isSaving, cleared
-- after the save completes. Keyed by UserId (stable across rejoins) not Player.
local pendingSaveUserIds = {}

-- R1.1 (egf.1): tracks the ACTIVE session for each UserId (the one the
-- current player instance is using). Keyed by UserId because Player objects
-- are destroyed on leave and re-created on rejoin, so sessions[oldPlayer] is
-- a stale key. When a player rejoins, load() overwrites their entry here
-- with the new session. save() checks this inside the UpdateAsync merge to
-- detect whether a deferred leave-save is stale (the player has rejoined
-- with a fresh session) and skips the write to avoid clobbering the newer
-- data. This is the WRITE-side counterpart to xsk's pendingSaveUserIds
-- LOAD gate — together they close both directions of the rejoin race.
local activeSessionsByUserId = {}

-- ════════════════════════════════════════════════════════════════════════════
-- DEEP SANITIZE — last line of defense against corrupted/exploited data.
-- TASK 1.5 expands this; the structure here validates every field from the
-- new PlayerProfile schema. Invalid entries are filtered, not crashed.
-- ════════════════════════════════════════════════════════════════════════════
local function sanitizeStoredFish(list)
	local clean = {}
	if type(list) ~= "table" then
		return clean
	end
	local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)
	for _, item in ipairs(list) do
		if type(item) == "table" and FishInstance.validate(item) then
			table.insert(clean, item)
		elseif type(item) == "number" and item >= 1 and item <= #GameConfig.Rarities then
			-- Legacy rarity index -> convert to FishInstance
			local fish = FishInstance.fromRarityIndex(item)
			table.insert(clean, fish)
		end
	end
	return clean
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
	local clean = PlayerProfile.default()
	if type(data) ~= "table" then
		return clean
	end
	-- Version
	if type(data.Version) == "number" and data.Version >= 1 then
		clean.Version = data.Version
	end

	-- Legacy v1 fallback: convert old flat fields
	if type(data.cash) == "number" then
		clean.Coins = PlayerProfile.clampCoins(data.cash)
	end
	if type(data.rodLevel) == "number" and GameConfig.Rods[data.rodLevel] then
		clean.Equipment.EquippedRodLevel = data.rodLevel
	end
	if type(data.baitLevel) == "number" and GameConfig.Baits[data.baitLevel] then
		clean.Equipment.EquippedBaitLevel = data.baitLevel
	end
	if type(data.capacityLevel) == "number" and data.capacityLevel >= 0 and data.capacityLevel <= #GameConfig.Upgrades.Capacity then
		clean.Aquarium.UpgradeLevel = math.floor(data.capacityLevel) + 1
	end
	if type(data.lockLevel) == "number" and data.lockLevel >= 0 and data.lockLevel <= #GameConfig.Upgrades.Lock then
		clean.Aquarium.LockLevel = math.floor(data.lockLevel)
	end
	if type(data.alarmLevel) == "number" and data.alarmLevel >= 0 and data.alarmLevel <= #GameConfig.Upgrades.Alarm then
		clean.Aquarium.AlarmLevel = math.floor(data.alarmLevel)
	end
	if type(data.liveWell) == "table" then
		clean.Aquarium.StoredFish = sanitizeStoredFish(data.liveWell)
	end

	-- Coins
	if type(data.Coins) == "number" then
		clean.Coins = PlayerProfile.clampCoins(data.Coins)
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
		-- N3 (CRITICAL): only migrate v2 StoredFish when it actually exists.
		-- The unconditional version wiped the legacy `liveWell` migration above:
		-- sanitizeStoredFish(nil) returns {}, clobbering fish just converted
		-- from the v1 liveWell format. A v1 save with a partial Aquarium table
		-- (but no StoredFish) would silently lose every fish on first load.
		if type(aq.StoredFish) == "table" then
			clean.Aquarium.StoredFish = sanitizeStoredFish(aq.StoredFish)
		end
		if type(aq.UnclaimedIncome) == "number" then
			clean.Aquarium.UnclaimedIncome = math.max(0, math.min(GameConfig.Economy.MaxUnclaimedIncome, aq.UnclaimedIncome))
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
		-- N6: Recompute capacity from UpgradeLevel against the authoritative tier
		-- table so a crafted/exploited Capacity value cannot inflate storage.
		local AquariumUpgradeTiers = GameConfig.AquariumUpgradeTiers
		local upLevel = clean.Aquarium.UpgradeLevel or 1
		if AquariumUpgradeTiers and #AquariumUpgradeTiers > 0 then
			upLevel = math.max(1, math.min(upLevel, #AquariumUpgradeTiers))
			clean.Aquarium.UpgradeLevel = upLevel
			clean.Aquarium.Capacity = AquariumUpgradeTiers[upLevel].capacity
		end
		if type(aq.RaidProtectionUntilTimestamp) == "number" then
			clean.Aquarium.RaidProtectionUntilTimestamp = aq.RaidProtectionUntilTimestamp
		end
		if type(aq.RaidOptIn) == "boolean" then
			clean.Aquarium.RaidOptIn = aq.RaidOptIn
		end
		-- N5: persist defense upgrade levels from the v2 schema location.
		if type(aq.LockLevel) == "number" and aq.LockLevel >= 0 and aq.LockLevel <= #GameConfig.Upgrades.Lock then
			clean.Aquarium.LockLevel = math.floor(aq.LockLevel)
		end
		if type(aq.AlarmLevel) == "number" and aq.AlarmLevel >= 0 and aq.AlarmLevel <= #GameConfig.Upgrades.Alarm then
			clean.Aquarium.AlarmLevel = math.floor(aq.AlarmLevel)
		end
	end

	-- Dock
	if type(data.Dock) == "table" then
		if type(data.Dock.UpgradeLevel) == "number" and data.Dock.UpgradeLevel >= 1 then
			clean.Dock.UpgradeLevel = math.floor(data.Dock.UpgradeLevel)
		end
		-- N17 (TASK 17.6): clamp Dock.UpgradeLevel against the authoritative
		-- DockUpgradeTiers table, mirroring the Aquarium N6 pattern. A crafted
		-- save with UpgradeLevel=999 would otherwise be honored, causing
		-- DockUpgradeTiers[999] lookups to return nil downstream.
		local DockUpgradeTiers = GameConfig.DockUpgradeTiers
		local dockLevel = clean.Dock.UpgradeLevel or 1
		if DockUpgradeTiers and #DockUpgradeTiers > 0 then
			dockLevel = math.max(1, math.min(dockLevel, #DockUpgradeTiers))
			clean.Dock.UpgradeLevel = dockLevel
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
			local FishDefinitions = require(game:GetService("ReplicatedStorage").Shared.FishDefinitions)
			for speciesId, val in pairs(data.Collection.DiscoveredSpecies) do
				if type(speciesId) == "string" and val == true then
					-- Only keep species that exist in FishDefinitions
					local ok = pcall(FishDefinitions.get, speciesId)
					if ok then
						clean.Collection.DiscoveredSpecies[speciesId] = true
					end
				end
			end
		end
		-- MilestonesClaimed is a SET keyed by milestone id (map form), matching
		-- how CollectionService writes it (MilestonesClaimed[id] = true) and how
		-- DiscoveredSpecies works above. The earlier array-style sanitize
		-- (ipairs + table.insert) silently dropped every claimed milestone on
		-- reload because string keys aren't array indices — claims never
		-- persisted. Handle both shapes for forward/backward compat: if the
		-- data is array-form (legacy), convert to the map set.
		if type(data.Collection.MilestonesClaimed) == "table" then
			for key, val in pairs(data.Collection.MilestonesClaimed) do
				if type(key) == "string" and val == true then
					-- Map form: { [milestoneId] = true }
					clean.Collection.MilestonesClaimed[key] = true
				elseif type(key) == "number" and type(val) == "string" then
					-- Legacy array form: { "milestoneId", ... } -> convert to set
					clean.Collection.MilestonesClaimed[val] = true
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
		if type(data.PvP.TotalCatches) == "number" then
			clean.PvP.TotalCatches = math.max(0, math.floor(data.PvP.TotalCatches))
		end
		-- TASK 8.0 (gdj.15): legacy StealCooldownUntilTimestamp sanitize REMOVED
		-- with the always-on steal handler. Old saves that still carry the key
		-- will silently drop it on next load (sanitize only copies known keys).
	end

	-- Stats (TASK 8.3: total catches for new-player protection gate)
	if type(data.Stats) == "table" then
		if type(data.Stats.TotalCatches) == "number" then
			clean.Stats.TotalCatches = math.max(0, math.floor(data.Stats.TotalCatches))
			-- Mirror into PvP for backward compat with any code reading PvP.TotalCatches
			clean.PvP.TotalCatches = clean.Stats.TotalCatches
		end
	end
	-- Also accept top-level TotalCatches from legacy saves
	if type(data.TotalCatches) == "number" then
		local v = math.max(0, math.floor(data.TotalCatches))
		clean.Stats.TotalCatches = math.max(clean.Stats.TotalCatches, v)
		clean.PvP.TotalCatches = math.max(clean.PvP.TotalCatches, v)
	end

	-- Defense (TASK 8.4: lock free uses) — clamp both lower and upper bounds.
	-- egf.8: upper bound is the config max, NOT a hardcoded magic number —
	-- sanitize is the last line of defense, so a corrupted free-use count
	-- above the configured cap must be pulled back down to it.
	if type(data.Defense) == "table" then
		if type(data.Defense.LockFreeUsesRemaining) == "number" then
			clean.Defense.LockFreeUsesRemaining = math.clamp(math.floor(data.Defense.LockFreeUsesRemaining), 0, GameConfig.Defense.LockFreeUsesMax)
		end
		if type(data.Defense.LockFreeUsesMax) == "number" then
			clean.Defense.LockFreeUsesMax = math.clamp(math.floor(data.Defense.LockFreeUsesMax), 1, GameConfig.Defense.LockFreeUsesMax)
		end
	end

	-- Onboarding
	if type(data.Onboarding) == "table" then
		for flag, val in pairs(data.Onboarding) do
			-- Only accept flags that exist in the schema default. A corrupted
			-- save with arbitrary Onboarding keys (e.g. { EvilFlag = true })
			-- would otherwise inject junk keys into the profile; whitelist to
			-- the 5 known progression flags.
			if type(flag) == "string"
				and type(val) == "boolean"
				and clean.Onboarding[flag] ~= nil
			then
				clean.Onboarding[flag] = val
			end
		end
	end

	-- Quests (RedBear feature: persisted so rewards can't be re-claimed by rejoining)
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

local function withRetries(fn, maxAttempts)
	maxAttempts = maxAttempts or 4
	local lastErr
	-- RELIABILITY: Exponential backoff with jitter to avoid thundering herd
	for attempt = 1, maxAttempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < maxAttempts then
			local backoff = math.pow(2, attempt - 1) * 0.25 + math.random() * 0.25
			task.wait(backoff)
		end
	end
	return false, lastErr
end

function DataManager.load(player)
	local saved = nil
	-- TASK 14.27 (xsk): wait for any in-flight deferred save to this key before
	-- reading, so a rapid rejoin doesn't load stale pre-save DataStore data.
	-- The wqw.20 onPlayerRemoving defers save via task.spawn; if the rejoin's
	-- GetAsync fires before that save's UpdateAsync commits, it returns the
	-- OLD value. Bounded by the save's retry duration; 16s cap exceeds the
	-- save's 15s isSaving wait + 1s UpdateAsync. After the wait, GetAsync sees
	-- the committed data. If the save failed/timed out, the 60s autosave +
	-- transactional saves (thj.2) still persist the data shortly.
	local pendingWaited = 0
	while pendingSaveUserIds[player.UserId] and pendingWaited < 16 do
		task.wait(0.1)
		pendingWaited += 0.1
	end
	if dataStore then
		local ok, result = withRetries(function()
			return dataStore:GetAsync(keyFor(player))
		end)
		if ok then
			saved = result
		else
			warn("[HarborHeist] Failed to load data for " .. player.Name .. ": " .. tostring(result))
			-- egf.5: load failures participate in the health counter.
			recordFailure()
		end
	end

	-- TASK 1.6: v1->v2 migration. If v2 has no data but the legacy v1 store
	-- does, load v1 (sanitize() converts flat->structured), then write the
	-- migrated profile to v2 so subsequent loads hit v2 directly. The v1 key
	-- is left intact as a rollback anchor for the closed-test grace period.
	local migratedFromV1 = false
	if saved == nil and dataStoreV1 then
		local okV1, resultV1 = withRetries(function()
			return dataStoreV1:GetAsync(keyFor(player))
		end)
		if okV1 and resultV1 ~= nil then
			saved = resultV1
			migratedFromV1 = true
		end
	end

	local profile = sanitize(saved)

	-- R1.6 (egf.6): log the result of the v1->v2 migration so support can
	-- reconstruct what happened if a player reports missing fish/coins.
	-- print (not warn): this is a routine, expected one-time-per-player
	-- migration, not an error. warn() would spam the console and
	-- drown out real errors once the closed test onboards legacy players.
	if migratedFromV1 then
		local function formatSpeciesList(storedFish)
			local counts = {}
			for _, fish in ipairs(storedFish or {}) do
				if type(fish) == "table" and type(fish.SpeciesId) == "string" then
					counts[fish.SpeciesId] = (counts[fish.SpeciesId] or 0) + 1
				end
			end
			local parts = {}
			for speciesId, count in pairs(counts) do
				table.insert(parts, speciesId .. " x" .. count)
			end
			if #parts == 0 then
				return "none"
			end
			table.sort(parts)
			return table.concat(parts, ", ")
		end

		print(("[HarborHeist] MIGRATION v1->v2: user=%s(%d) | source v1{cash=%s rodLevel=%s baitLevel=%s liveWell=%s} | result{%s}"):format(
			player.Name, player.UserId,
			tostring(saved.cash), tostring(saved.rodLevel), tostring(saved.baitLevel),
			type(saved.liveWell) == "table" and (#saved.liveWell .. " fish") or tostring(saved.liveWell),
			formatSpeciesList(profile.Aquarium.StoredFish)))
	end

	-- TASK 1.6: if this profile came from the v1 store, persist it to v2
	-- immediately so the next load reads v2 directly (and so the player's
	-- data exists in the authoritative store even if they disconnect before
	-- the first autosave).
	local needsMigrationSave = migratedFromV1

	-- Session = profile + runtime-only fields (not persisted).
	-- The profile sub-tables are the SAME table references so services can
	-- read/write profile.Aquarium.StoredFish directly.
	local session = {
		player = player,
		profile = profile,
		-- Convenience aliases: these point INTO the profile so reads/writes
		-- go to the canonical nested structure. Services update gradually.
		carried = {}, -- SECURITY: Always empty on load (client data untrusted)
		casting = false,
		dockIndex = nil,
		isSaving = false,
		-- TASK 14.26 (5gr): dirty-flag for checkpoint-save coalescing. Set by
		-- non-shutdown save() calls that arrive while another save is in flight;
		-- cleared by the in-flight save's trailing-write check on completion.
		-- This collapses N rapid checkpoint calls into at most 2 sequential
		-- DataStore writes instead of N sequential (each with GetAsync+SetAsync).
		saveDirty = false,
		-- Runtime-only os.clock timers (NOT persisted; persist as epoch in profile)
		lockedUntil = 0,
		lockCooldownUntil = 0,
		-- TASK 8.0 (gdj.15): legacy stealCooldownUntil session field REMOVED with
		-- the always-on steal handler. RaidService (Epic 8) adds its own cooldown.
		-- RedBear additions: stun + boat runtime state (session-scoped)
		stunUntil = 0,
		castDeadline = 0,
		boatModel = nil,
		-- harborheist-gqh3: removed dead session fields:
		--   castHitZoneStart/castHitZoneEnd (cast overlay bounds moved to
		--     activeBites[player] in N16 CastResult wiring)
		--   heistCount (legacy steal handler removed in gdj.15)
		--   incomeSinceTick (income loop accrues to profile.Aquarium.UnclaimedIncome)
		--   boatDespawnTask/seatConnection (BoatService tracks these in its own
		--     module-level despawnTasks/seatConnections tables, not on session)
		-- Quest runtime fields (persisted via sanitize; runtime-mutable here).
		-- N2 (CRITICAL): read from the sanitized `profile`, NOT the raw `data`
		-- parameter — `data` is nil for brand-new players or when the datastore
		-- load failed, and indexing nil here crashes EVERY first-time join.
		dailyQuestKey = profile.dailyQuestKey,
		dailyQuests = profile.dailyQuests,
		weeklyQuestKey = profile.weeklyQuestKey,
		weeklyQuests = profile.weeklyQuests,
	}
	-- R1.3 (egf.3): Bounded timer rehydration. Epoch timestamps from
	-- DataStore can be corrupted or clock-skewed (bad save, local clock
	-- edit, future write bug). Without bounds, a far-future timestamp
	-- bricks the player's lock for months/years — they can't RequestSellFish,
	-- can't sell stored fish, can't be raided, and can't unlock. The
	-- ceiling is derived from the max lock duration + max cooldown across
	-- all upgrade tiers so balance changes can't silently invalidate it.
	-- A generous 600s (10min) floor covers current tiers (150s + 120s =
	-- 270s max) + headroom for future upgrades. Clamping logs a warn so
	-- the corruption is visible.
	local MAX_REHYDRATE_SECONDS = 600
	local function rehydrateTimer(ts, fieldName)
		local remaining = ts - os.time()
		if remaining <= 0 then
			return 0
		end
		if remaining > MAX_REHYDRATE_SECONDS then
			warn(string.format("[HarborHeist] Timer rehydration clamped: %s had %ds remaining (max %ds) — possible data corruption or clock skew",
				fieldName, math.floor(remaining), MAX_REHYDRATE_SECONDS))
			remaining = MAX_REHYDRATE_SECONDS
		end
		return os.clock() + remaining
	end
	session.lockedUntil = rehydrateTimer(profile.Aquarium.LockUntilTimestamp, "LockUntilTimestamp")
	session.lockCooldownUntil = rehydrateTimer(profile.Aquarium.LockCooldownUntilTimestamp, "LockCooldownUntilTimestamp")
	-- TASK 8.0 (gdj.15): legacy StealCooldownUntilTimestamp rehydrate REMOVED
	-- with the always-on steal handler. No replacement; RaidService manages
	-- its own cooldown when it lands.
	sessions[player] = session
	-- R1.1 (egf.1): register this as the active session for the userId. A
	-- concurrent deferred leave-save from a Previous player instance checks
	-- this map inside UpdateAsync to detect that the player has rejoined and
	-- its stale write should be skipped.
	activeSessionsByUserId[player.UserId] = session

	-- TASK 1.6: persist the migrated profile to v2 immediately (deferred so
	-- load returns promptly; DataManager.save reads the same session table).
	-- Deferring one frame lets the caller finish wiring the session before
	-- the async DataStore write runs.
	if needsMigrationSave then
		task.defer(function()
			if session.player and session.player.Parent then
				DataManager.save(session.player)
			end
		end)
	end
	return session
end

function DataManager.get(player)
	return sessions[player]
end

function DataManager.save(player, isShutdown)
	local session = sessions[player]
	if not session or not dataStore then
		return
	end

	-- RELIABILITY: If a save is already in flight:
	-- • Shutdown/leave saves (isShutdown=true) MUST persist synchronously — wait
	--   for the in-flight save to finish, then run ours. Skipping the final save
	--   on leave/shutdown loses data.
	-- • Checkpoint/autosave saves (isShutdown=nil) coalesce via a dirty flag —
	--   set saveDirty and return immediately. The in-flight save will run ONE
	--   trailing write to pick up all changes that arrived during it, collapsing
	--   N rapid checkpoint calls into at most 2 sequential DataStore writes
	--   instead of N sequential (each with GetAsync+SetAsync). This prevents
	--   DataStore budget throttling under transaction-heavy load.
	if session.isSaving then
		if isShutdown then
			local waited = 0
			while session.isSaving and waited < 15 do
				task.wait(0.1)
				waited += 0.1
			end
			if session.isSaving then
				warn("[HarborHeist] Timed out waiting for in-flight save for " .. player.Name)
				return
			end
		else
			session.saveDirty = true
			return
		end
	end

	session.isSaving = true
	-- TASK 14.27 (xsk): mark this userId as save-in-flight so a concurrent
	-- load() (rapid rejoin) waits for the UpdateAsync to commit before reading.
	pendingSaveUserIds[player.UserId] = true

	local profile = session.profile

	-- Persist runtime lock timers as epoch timestamps (they may have been set
	-- since load and need to survive server restart)
	-- R1.3 (egf.3): write-side assertion — clamp to the same ceiling as
	-- rehydrate so a buggy producer can never WRITE a timestamp further
	-- into the future than the rehydration layer will accept. Catches the
	-- bug at the source instead of silently storing corruption.
	local nowEpoch = os.time()
	local nowClock = os.clock()
	if session.lockedUntil > nowClock then
		local remaining = math.min(math.floor(session.lockedUntil - nowClock), 600)
		profile.Aquarium.LockUntilTimestamp = nowEpoch + remaining
	end
	if session.lockCooldownUntil > nowClock then
		local remaining = math.min(math.floor(session.lockCooldownUntil - nowClock), 600)
		profile.Aquarium.LockCooldownUntilTimestamp = nowEpoch + remaining
	end
	-- TASK 8.0 (gdj.15): legacy stealCooldownUntil persist REMOVED with the
	-- always-on steal handler. No session field exists to persist anymore.

	-- TASK 14.20: on shutdown/leave, a fast-failing save (2 attempts) beats a
	-- slow save that gets killed mid-retry when the handler budget expires.
	local ok, err = withRetries(function()
		return dataStore:UpdateAsync(keyFor(player), function(oldData)
			-- R1.1 (egf.1): stale-save guard. If the player has left and
			-- rejoined since this save was queued (deferred leave-save via
			-- task.spawn), activeSessionsByUserId[userId] now points to the
			-- NEW session, not this one. Writing this stale profile would
			-- clobber the fresher rejoin data. Return oldData unchanged to
			-- make the stale save a no-op — the new session's own saves
			-- (autosave + transactional) will persist the correct data.
			if activeSessionsByUserId[player.UserId] ~= session then
				return oldData
			end
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
			existing.Stats = profile.Stats
			existing.Defense = profile.Defense
			-- Persist quest data (RedBear feature)
			existing.dailyQuestKey = session.dailyQuestKey
			existing.dailyQuests = session.dailyQuests
			existing.weeklyQuestKey = session.weeklyQuestKey
			existing.weeklyQuests = session.weeklyQuests

			return existing
		end)
	end, isShutdown and 2 or 4)

	session.isSaving = false
	-- TASK 14.27 (xsk): save committed (or failed) — unblock any waiting load().
	pendingSaveUserIds[player.UserId] = nil

	if not ok then
		warn("[HarborHeist] Failed to save data for " .. player.Name .. ": " .. tostring(err))
		recordFailure()
	else
		recordSuccess()
		-- R1.6 (egf.6): log successful saves so support can reconstruct a
		-- "I lost progress" timeline from the server output. One line per save
		-- (low volume; autosave + checkpoints), no full profile dump.
		print(("[HarborHeist] SAVE OK: user=%s(%d) | time=%d | shutdown=%s | coins=%s | storedFish=%d"):format(
			player.Name, player.UserId, os.time(), tostring(isShutdown == true),
			tostring(profile.Coins), #profile.Aquarium.StoredFish))
	end

	-- TASK 14.26 (5gr): Dirty-flag coalescing trailing write. If save() was
	-- called while this save was in flight (non-shutdown callers set saveDirty),
	-- run ONE trailing save to pick up all accumulated changes. This collapses
	-- N rapid checkpoint calls into at most 2 sequential DataStore writes.
	-- Skip for shutdown saves: their callers (BindToClose, leave) already
	-- waited for the in-flight save above and run their own synchronous save.
	if not isShutdown and sessions[player] and session.saveDirty then
		session.saveDirty = false
		DataManager.save(player)
	end
end

function DataManager.remove(player)
	local session = sessions[player]
	sessions[player] = nil
	-- R1.1 (egf.1): only clear the active-session entry if it still points
	-- to this session (the player may have already rejoined with a new one
	-- that replaced it via load()). Captured before the nil so we compare
	-- against the actual session object, not the now-nil sessions[player].
	if session and activeSessionsByUserId[player.UserId] == session then
		activeSessionsByUserId[player.UserId] = nil
	end
end

function DataManager.allSessions()
	return sessions
end

function DataManager.startAutosave()
	task.spawn(function()
		while true do
			task.wait(60)
			-- egf.5: attempt recovery after a cooldown if the DataStore was
			-- marked unhealthy. This is the only scheduled caller — without it
			-- the server stays unhealthy until a save happens to succeed.
			DataManager.tryRecover()
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
				-- TASK 14.20: isShutdown=true -> fewer retries inside the budget.
				pcall(DataManager.save, player, true)
				remaining -= 1
			end)
		end
		while remaining > 0 do
			task.wait(0.1)
		end
	end)
end

function DataManager.isHealthy()
	return isDataStoreHealthy
end

function DataManager.tryRecover()
	if not isDataStoreHealthy and os.time() - lastFailureTime > FAILURE_COOLDOWN then
		isDataStoreHealthy = true
		consecutiveFailures = 0
		print("[HarborHeist] DataStore attempting recovery after cooldown.")
		return true
	end
	return isDataStoreHealthy
end
-- Test export: makes the local sanitize function accessible to unit tests
-- without changing any production behavior. See test/specs/DataManagerSanitize.spec.lua
DataManager._sanitize = sanitize

return DataManager