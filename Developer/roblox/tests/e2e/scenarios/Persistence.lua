--[[
	Persistence.lua — E2E scenario: persistence round-trip + v1->v2
	migration against the real DataStore. TASK 19.6, migrated to the modular
	scenario architecture under EPIC 43 (z9mz).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, scenario place built from e2e_scenarios.project.json). NO stubs of
	game code — only the Player is a table-fake and, when Studio blocks
	DataStore access (unpublished place), an in-memory mock store injected
	via DataManager._setStores. Every step is logged through TestLogger
	(JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }.

	What this verifies:
	  Phase A — save -> reload round-trip with MUTATED state (defaults survive
	    anything, so mutated values are the only real proof a save works):
	    distinctive Coins/equipment/aquarium/fish values, synchronous
	    isShutdown save, session wipe, reload, every field verified —
	    including sanitize recomputing Capacity from UpgradeLevel.
	  Phase B — v1 -> v2 migration: clean the v2 key, seed the LEGACY v1
	    store with a flat-format payload, DataManager.load must read v1,
	    sanitize into the v2 schema, and persist the migrated profile to v2.
	    The deferred v2 write is proven by reading v2 DIRECTLY (a reload
	    alone can't distinguish "v2 write landed" from "v1 re-migrated").

	Mock-store rationale (preserved from runner 19.6): in an unpublished
	local build, GetDataStore itself throws "You must publish this place to
	the web" — DataManager's module-level pcall swallows this, leaving its
	store handles nil and turning every save() into a SILENT NO-OP. The mock
	deep-copies on every read/write, mirroring real DataStore serialization
	semantics, so reference-aliasing between "stored" data and live profiles
	can't hide bugs. Everything except the Roblox transport is real code.

	DEVIATION from the monolith (robustness, not semantics): the store-mode
	body runs inside a pcall and _setStores(nil) restoration runs in a
	finally-style path. In the modular architecture a crash here would
	otherwise leak mock stores into LATER scenarios sharing this DataModel.
	Any error is rethrown after restoration so the bootstrap still records
	the scenario crash.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Persistence = {}

-- Pull the already-wired services so assertions read the SAME module
-- instances the game wired (no re-require drift).
local function getServices()
	local harbor = ServerScriptService:WaitForChild("HarborHeist", 10)
	assert(harbor, "ServerScriptService.HarborHeist missing — game did not boot")
	return {
		DataManager = require(harbor:WaitForChild("DataManager")),
	}
end

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[deepCopy(k)] = deepCopy(v)
	end
	return c
end

local function makeMockDataStore()
	local data = {}
	return {
		GetAsync = function(_self, key)
			return deepCopy(data[key])
		end,
		SetAsync = function(_self, key, value)
			data[key] = deepCopy(value)
		end,
		RemoveAsync = function(_self, key)
			local old = data[key]
			data[key] = nil
			return deepCopy(old)
		end,
		UpdateAsync = function(_self, key, transform)
			local newValue = transform(deepCopy(data[key]))
			if newValue ~= nil then
				data[key] = deepCopy(newValue)
			end
			return deepCopy(newValue)
		end,
	}
end

function Persistence.run(harness)
	local logger = harness.logger

	logger:startScenario("persistence", "save/reload round-trip with mutated state + v1->v2 migration vs real DataStore")

	local svc = getServices()
	local DataManager = svc.DataManager
	local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
	local FishInstance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FishInstance"))

	-- ------------------------------------------------------------------
	-- STEP 1: store acquisition — REAL DataStore when published, else
	-- faithful in-memory mock injected via DataManager._setStores
	-- ------------------------------------------------------------------
	logger:step("store_mode", "probe real DataStore; fall back to injected mock")
	local v1Store, v2Store
	local realStoreAvailable = pcall(function()
		local probe = DataStoreService:GetDataStore("HarborHeist_PlayerData_v2")
		probe:GetAsync("__e2e_probe__") -- force a real call; GetDataStore alone may not throw
	end)
	if realStoreAvailable then
		logger:log("INFO", "store mode: REAL DataStore (published place)", {})
		v2Store = DataStoreService:GetDataStore("HarborHeist_PlayerData_v2")
		v1Store = DataStoreService:GetDataStore("HarborHeist_PlayerData_v1")
	else
		logger:log("INFO", "store mode: in-memory mock (Studio blocks DataStore for unpublished places)", {})
		v2Store = makeMockDataStore()
		v1Store = makeMockDataStore()
		DataManager._setStores(v2Store, v1Store)
	end

	-- Body wrapped so mock stores are ALWAYS restored (see header deviation).
	local bodyOk, bodyErr = pcall(function()
		-- ----------------------------------------------------------
		-- STEP 2: Phase A — save -> reload round-trip, mutated state
		-- ----------------------------------------------------------
		logger:step("roundtrip", "mutate, synchronous save, wipe, reload, verify")
		local persistPlayer = {
			UserId = 555666777,
			Name = "E2EPersist",
			DisplayName = "E2EPersist",
			Parent = Players,
			Character = nil,
		}
		local persistSession = DataManager.load(persistPlayer)
		logger:assertTrue("persist session created", persistSession ~= nil)

		if persistSession then
			local pp = persistSession.profile
			pp.Coins = 777
			pp.Equipment.EquippedRodLevel = 2
			pp.Equipment.OwnedRodLevels = { 1, 2 }
			pp.Aquarium.UpgradeLevel = 2
			pp.Aquarium.UnclaimedIncome = 123
			local persistFish = FishInstance.new("Tuna", "StarterPier")
			table.insert(pp.Aquarium.StoredFish, persistFish)

			local saveOk, saveErr = pcall(function()
				DataManager.save(persistPlayer, true) -- isShutdown: synchronous, waits for in-flight
			end)
			logger:assertTrue("round-trip save succeeds: " .. tostring(saveErr or ""), saveOk)

			DataManager.remove(persistPlayer)
			task.wait(0.5)
			local reloaded = DataManager.load(persistPlayer)
			logger:assertTrue("reload creates session", reloaded ~= nil)
			if reloaded then
				local rp = reloaded.profile
				logger:assertEq("round-trip Coins", 777, rp.Coins)
				logger:assertEq("round-trip EquippedRodLevel", 2, rp.Equipment.EquippedRodLevel)
				logger:assertEq("round-trip OwnedRodLevels count", 2, #rp.Equipment.OwnedRodLevels)
				logger:assertEq("round-trip Aquarium.UpgradeLevel", 2, rp.Aquarium.UpgradeLevel)
				-- sanitize recomputes Capacity from UpgradeLevel against the tier table
				logger:assertEq("round-trip Capacity recomputed", GameConfig.AquariumUpgradeTiers[2].capacity, rp.Aquarium.Capacity)
				logger:assertEq("round-trip UnclaimedIncome", 123, rp.Aquarium.UnclaimedIncome)
				logger:assertEq("round-trip StoredFish count", 1, #rp.Aquarium.StoredFish)
				if #rp.Aquarium.StoredFish > 0 then
					logger:assertEq("round-trip fish SpeciesId", "Tuna", rp.Aquarium.StoredFish[1].SpeciesId)
				end
				logger:log("INFO", "round-trip verified", {
					coins = rp.Coins,
					rod = rp.Equipment.EquippedRodLevel,
					storedFish = #rp.Aquarium.StoredFish,
				})
			end
			DataManager.remove(persistPlayer)
		end

		-- ----------------------------------------------------------
		-- STEP 3: Phase B — v1 -> v2 migration
		-- ----------------------------------------------------------
		logger:step("migration", "seed legacy v1 flat payload; load migrates to v2")
		local legacyPlayer = {
			UserId = 666777888,
			Name = "E2ELegacy",
			DisplayName = "E2ELegacy",
			Parent = Players,
			Character = nil,
		}
		local legacyKey = "player_" .. legacyPlayer.UserId

		-- Clean slate: no v2 data (v2 is checked first; leftover v2 from a
		-- previous run would bypass the migration path entirely).
		pcall(function()
			v2Store:RemoveAsync(legacyKey)
		end)
		local seedOk, seedErr = pcall(function()
			v1Store:SetAsync(legacyKey, {
				cash = 4242,
				rodLevel = 3,
				baitLevel = 2,
				capacityLevel = 1, -- 0-based in v1 -> UpgradeLevel 2 in v2
				liveWell = { 2, 3 }, -- legacy rarity indices -> FishInstance conversion
			})
		end)
		logger:assertTrue("v1 legacy payload seeded: " .. tostring(seedErr or ""), seedOk)

		local migSession = DataManager.load(legacyPlayer)
		logger:assertTrue("migration load creates session", migSession ~= nil)
		if migSession then
			local mp = migSession.profile
			logger:assertEq("migration cash -> Coins", 4242, mp.Coins)
			logger:assertEq("migration rodLevel", 3, mp.Equipment.EquippedRodLevel)
			logger:assertEq("migration baitLevel", 2, mp.Equipment.EquippedBaitLevel)
			logger:assertEq("migration capacityLevel+1 -> UpgradeLevel", 2, mp.Aquarium.UpgradeLevel)
			logger:assertEq("migration Capacity recomputed", GameConfig.AquariumUpgradeTiers[2].capacity, mp.Aquarium.Capacity)
			logger:assertEq("migration liveWell converted", 2, #mp.Aquarium.StoredFish)
			if #mp.Aquarium.StoredFish > 0 then
				logger:assertTrue("migrated fish have SpeciesId", mp.Aquarium.StoredFish[1].SpeciesId ~= nil)
				logger:assertTrue("migrated fish have Rarity", mp.Aquarium.StoredFish[1].Rarity ~= nil)
			end
			logger:log("INFO", "migration verified", {
				coins = mp.Coins,
				rod = mp.Equipment.EquippedRodLevel,
				bait = mp.Equipment.EquippedBaitLevel,
				fish = #mp.Aquarium.StoredFish,
			})

			-- The migration save to v2 is deferred (task.defer + async
			-- DataStore write). Wait for it, then prove it landed by reading
			-- v2 DIRECTLY — a reload alone can't distinguish "v2 write
			-- landed" from "v1 read and migrated a second time".
			logger:step("v2_direct_read", "prove deferred migration write landed in v2")
			task.wait(3)
			local v2Data
			local v2ReadOk, v2ReadErr = pcall(function()
				v2Data = v2Store:GetAsync(legacyKey)
			end)
			logger:assertTrue("v2 direct read succeeds: " .. tostring(v2ReadErr or ""), v2ReadOk)
			logger:assertTrue("migrated profile persisted to v2", v2Data ~= nil)
			if v2Data then
				logger:assertEq("v2 store has v2-schema Coins", 4242, v2Data.Coins)
				logger:assertTrue("v2 store has Equipment sub-table", type(v2Data.Equipment) == "table")
				if type(v2Data.Equipment) == "table" then
					logger:assertEq("v2 store rod level", 3, v2Data.Equipment.EquippedRodLevel)
				end
			end

			-- Final: reload from v2 (session wipe) yields identical values.
			logger:step("post_migration_reload", "reload from v2 matches migrated values")
			DataManager.remove(legacyPlayer)
			task.wait(0.5)
			local migReloaded = DataManager.load(legacyPlayer)
			logger:assertTrue("post-migration reload creates session", migReloaded ~= nil)
			if migReloaded then
				logger:assertEq("post-migration reload Coins", 4242, migReloaded.profile.Coins)
				logger:assertEq("post-migration reload rod", 3, migReloaded.profile.Equipment.EquippedRodLevel)
				logger:assertEq("post-migration reload fish count", 2, #migReloaded.profile.Aquarium.StoredFish)
			end
			DataManager.remove(legacyPlayer)

			-- Leave the DataStore clean for the next run (v1 re-seeded each
			-- run; v2 removed so the migration path is exercised again).
			pcall(function()
				v2Store:RemoveAsync(legacyKey)
			end)
		end
	end)

	-- ------------------------------------------------------------------
	-- STEP 4: restore the real store handles if mocks were injected
	-- (finally-style: runs even when the body errored)
	-- ------------------------------------------------------------------
	if not realStoreAvailable then
		DataManager._setStores(nil)
	end

	if not bodyOk then
		logger:log("ERROR", "persistence body crashed: " .. tostring(bodyErr), {})
		error(bodyErr, 0)
	end

	logger:finish()
end

return Persistence
