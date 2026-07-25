local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local Remotes = require(script.Remotes)
local DataManager = require(script.DataManager)
local WorldBuilder = require(script.WorldBuilder)
local DockManager = require(script.DockManager)
local StateSync = require(script.StateSync)
local FishingService = require(script.FishingService)
local AquariumService = require(script.AquariumService)
local ShopService = require(script.ShopService)
local FishInventoryService = require(script.FishInventoryService)
local QuestService = require(script.QuestService)
local BoatService = require(script.BoatService)
local RodService = require(script.RodService)
local AnalyticsService = require(script.AnalyticsService) -- EPIC 11 / TASK 11.1
local CollectionService = require(script.CollectionService) -- EPIC 7 / TASK 7.2
local OnboardingService = require(script.OnboardingService) -- EPIC 9 / TASK 9.1
local RaidService = require(script.RaidService) -- EPIC 8 / TASK 8.1
local AntiExploitService = require(script.AntiExploitService) -- EPIC 10 / TASK 10.1+10.2
local AuditLogService = require(script.AuditLogService) -- EPIC 10 / TASK 10.3

Players.CharacterAutoLoads = false

local worldFolder = WorldBuilder.build()
local docks = DockManager.buildAll(worldFolder)

StateSync.remotes = Remotes

local deps = {
	remotes = Remotes,
	dataManager = DataManager,
	dockManager = DockManager,
	stateSync = StateSync,
	worldFolder = worldFolder,
	questService = QuestService,
	rodService = RodService,
	analytics = AnalyticsService, -- EPIC 11
	onboarding = OnboardingService, -- EPIC 9
	raidService = RaidService, -- EPIC 8 (gdj.13 eligibility will gate on isWindowOpen)
	aquariumService = AquariumService, -- EPIC 8 (gdj.13 target selection reuses eligibility helpers)
	antiExploit = AntiExploitService, -- EPIC 10
	auditLog = AuditLogService, -- EPIC 10 / TASK 10.3
}

AntiExploitService.init(deps) -- EPIC 10: must init first so rate limiting is available
AuditLogService.init(deps) -- EPIC 10 / TASK 10.3
DockManager.init(deps) -- TASK 24.1 (hvfh.4.1): dock sign income-rate readout
local fishingInit = FishingService.init(deps)
local fishingCleanup = fishingInit.onPlayerRemoving
AquariumService.init(deps)
ShopService.init(deps)
FishInventoryService.init(deps)
QuestService.init(deps)
BoatService.init(deps)
CollectionService.init(deps) -- EPIC 7 / TASK 7.2 (collection book remote)
OnboardingService.init(deps) -- EPIC 9 / TASK 9.1 (onboarding flag writer)
RaidService.init(deps) -- EPIC 8 / TASK 8.1 (raid-window scheduler)
AquariumService.startIncomeLoop(deps)
DataManager.startAutosave()
DataManager.bindToClose()

-- E2E test bridge: expose internal service state for the E2E runner
-- (tests/e2e/runner.server.lua). The _G table is per-VM and never
-- replicates to clients. Guarded by the E2ERunner script existing (only
-- present in the E2E place, not in production builds).
local hasE2E = ServerScriptService:FindFirstChild("E2ERunner") ~= nil
print("[HarborHeist] init.server: E2ERunner present=" .. tostring(hasE2E))
if hasE2E then
	_G.HARBORHEIST_TEST = {
		activeBites = fishingInit._activeBites,
		setFishingRng = fishingInit._setRng,
		submitCatch = fishingInit._submitCatch,
		fishingCleanup = fishingCleanup,
	}
end

-- R2.3 (dt9.3): boot-time config assertion — prevents income definition
-- divergence from being reintroduced silently after R2.2 unification.
-- Hard-fails in Studio (fast feedback), warns in production (availability).
GameConfig.validate()

Remotes.GetState.OnServerInvoke = function(player)
	local ok, reason = AntiExploitService.checkRate(player, "get_state")
	if not ok then
		return nil
	end
	local session = DataManager.get(player)
	if session then
		local snap = StateSync.snapshot(session)
		-- TASK 10.5: include DataStore health in snapshot
		snap.dataStoreHealthy = DataManager.isHealthy()
		return snap
	end
	return nil
end

local shopPrompt = worldFolder.Shop.Counter.ShopPrompt
shopPrompt.Triggered:Connect(function(player)
	Remotes.OpenShop:FireClient(player)
	-- harborheist-os9: fire the catalog'd upgrade_shop_opened funnel event —
	-- it was registered in AnalyticsService but nobody fired it, so the
	-- shop-engagement dashboard metric was permanently empty.
	AnalyticsService.track(player, "upgrade_shop_opened", {})
end)

local boatPrompt = worldFolder.BoatDock.PrimaryPart.BoatPrompt
boatPrompt.Triggered:Connect(function(player)
	-- UNIFIED (fresh-eyes review): delegate to BoatService.handleSpawnRequest,
	-- the same entry point the SpawnBoat RemoteFunction uses. Previously this
	-- handler was a hand-duplicated copy of the spawn logic — and it was
	-- MISSING the stun check, so a stunned thief could bypass the slow debuff
	-- by walking to the dock and prompt-spawning an escape boat. One canonical
	-- path closes the exploit and prevents future drift.
	local result = BoatService.handleSpawnRequest(player)
	-- handleSpawnRequest already notifies on stun / success. Add the "already
	-- have a boat" notify here since the prompt is the only UI surface where
	-- that specific reason is surfaced (the RemoteFunction button just hides).
	if result and not result.ok and result.reason == "already_has_boat" then
		Remotes.notify(player, "You already have a boat!", Color3.fromRGB(255, 170, 80))
	end
end)

local function connectAquariumPrompt(dock)
	local prompt = dock.aquarium.PrimaryPart.AquariumPrompt
	prompt.Triggered:Connect(function(player)
		-- TASK 8.0 (gdj.15): legacy always-on steal REMOVED. The prompt now
		-- ONLY opens the owner's aquarium panel. PvP interaction moves to
		-- the scheduled RaidService (Epic 8) — no more walk-up griefing.
		if dock.owner == player then
			Remotes.OpenAquarium:FireClient(player)
		end
	end)
end

for _, dock in ipairs(docks) do
	connectAquariumPrompt(dock)
end

local function onPlayerAdded(player)
	local session = DataManager.load(player)
	-- RELIABILITY: The load can yield for several seconds; the player may have
	-- left in the meantime. Clean up so we don't leak a session for a gone player.
	if not player.Parent then
		DataManager.remove(player)
		return
	end
	-- hbyz (PVP-06/07): re-seed raid cooldowns from the persisted profile so
	-- a rejoin can't reset them. Must run AFTER DataManager.load (the profile
	-- mirrors come from the DataStore) and BEFORE any raid remote can fire.
	RaidService.onSessionLoaded(session)
	-- vaz2 (PVP-03): per-session lock free-use regen (reset to
	-- LockFreeUsesMax at join; the written 8.4 design is "3 per session").
	AquariumService.onSessionLoaded(session)
	StateSync.setupLeaderstats(player, session)

	-- EPIC 11 (TASK 11.2): tutorial_started fires once per player join.
	-- The actual onboarding flow (EPIC 9) isn't built yet, so this marks
	-- "player entered the world" as the funnel entry point.
	AnalyticsService.track(player, "tutorial_started")

	-- EPIC 9 (TASK 9.1): mark the intro complete on join. Idempotent — the
	-- OnboardingService early-returns if the flag is already set, so this is
	-- safe to call on every join (including rejoins).
	OnboardingService.mark(session, "HasCompletedIntro")

	QuestService.initializeQuests(session)
	QuestService.pushProgress(session)

	local dock = DockManager.claim(player)
	if dock then
		session.dockIndex = dock.index
		DockManager.updateAquariumVisual(dock, session, StateSync.getCapacity(session))
	else
		Remotes.notify(player, "All docks are taken! You'll spawn at the plaza.", Color3.fromRGB(255, 170, 80))
	end

	-- RELIABILITY: Store connection so we can disconnect it later to prevent memory leaks
	local characterConnection
	characterConnection = player.CharacterAdded:Connect(function(character)
		-- SECURITY: Verify player still exists before accessing dock
		if not player.Parent then
			characterConnection:Disconnect()
			return
		end
		task.wait(0.1)
		-- SECURITY: Verify character still exists and is parented
		if not character.Parent then
			return
		end
		local targetDock = DockManager.getDock(player)
		if targetDock then
			character:PivotTo(targetDock.spawnCFrame)
		end
		RodService.equip(player, DataManager.get(player))
		-- EPIC 11 (TASK 11.2): starter_rod_received fires ONCE per session
		-- (first character load only). CORRECTED (fresh-eyes): previously
		-- fired on every CharacterAdded (every respawn), inflating the event
		-- count. Gated by session.starterRodTracked so respawns don't re-fire.
		if not session.starterRodTracked then
			session.starterRodTracked = true
			AnalyticsService.track(player, "starter_rod_received")
		end
	end)
	session.characterConnection = characterConnection

	player:LoadCharacter()
	StateSync.push(session)
	Remotes.notify(
		player,
		"Welcome to Harbor Heist! Fish at your dock, store fish in your aquarium, and watch the cash roll in.",
		Color3.fromRGB(120, 220, 255)
	)
end

local function onPlayerRemoving(player)
	-- RELIABILITY: Save data before cleanup to prevent loss
	-- SECURITY: Ensure player is fully cleaned up to prevent reference leaks
	local session = DataManager.get(player)
	if session and session.characterConnection then
		session.characterConnection:Disconnect()
	end
	fishingCleanup(player) -- clear activeBites + casting BEFORE remove() (TASK 14.3)

	-- EPIC 11 (TASK 11.2): churn signals. Fire BEFORE clearSession so the
	-- funnel state is still readable. A player who leaves without catching
	-- or upgrading is a retention red flag — these events power the
	-- "where did they drop off?" funnel analysis.
	-- TASK 14.20: fired synchronously here (before the spawned save/cleanup)
	-- so they always run even if the PlayerRemoving handler budget expires.
	local funnel = AnalyticsService.getFunnelState(player.UserId)
	if not funnel.firstCatchAt then
		AnalyticsService.track(player, "player_left_before_first_catch")
	end
	if not funnel.firstUpgradeAt then
		AnalyticsService.track(player, "player_left_before_first_upgrade")
	end

	-- TASK 14.20: the ONLY blocking step is the save (UpdateAsync w/ up to 4
	-- retries + backoff), which can be killed mid-write when the leave handler
	-- budget expires. So defer JUST the save (and the remove() that must follow
	-- it, since save reads sessions[player]); run the lightweight cleanup
	-- SYNCHRONOUSLY here instead of inside the spawn, for two reasons:
	--  1. None of release/despawn/unequip/clearSession yield, so they don't
	--     block the handler -- only the save did.
	--  2. RACE FIX (fresh-eyes): AnalyticsService.clearSession is keyed by
	--     UserId (stable across rejoins), while DataManager/dock/boat cleanup
	--     are keyed by the Player OBJECT. A deferred clearSession(player) could
	--     wipe a REJOINED player's analytics session (same UserId, new Player
	--     object) if the reconnect landed within the save's yield window.
	--     Running it synchronously here -- before any rejoin can register --
	--     closes that window. The deferred save+remove are object-keyed, so a
	--     rejoin touches a different sessions[] key and is unaffected.
	-- Order preserved: funnel events (above) -> release/boat/rod (their churn
	-- events still have an analytics session) -> clearSession -> [spawn] save
	-- -> remove. BindToClose is the authoritative shutdown save (isShutdown).
	DockManager.release(player)
	BoatService.onPlayerRemoving(player)
	RodService.onPlayerRemoving(player)
	-- EPIC 11 (TASK 11.1): clear analytics session to prevent unbounded growth
	-- of the sessions table across long server uptimes. AFTER boat/rod cleanup
	-- (so their churn events can still read it), BEFORE DataManager.remove.
	AnalyticsService.clearSession(player)
	-- Spawn the (blocking) save + the remove that must follow it. pcall so
	-- remove ALWAYS runs even if save throws (matches BindToClose's pcall
	-- pattern); remove is object-keyed (sessions[player]=nil) and safe after
	-- the Player object is destroyed. If shutdown kills this spawn before the
	-- save completes, BindToClose still saves sessions[player] (remove hasn't
	-- cleared it yet) -- no data loss.
	-- TASK 14.26 (5gr): isShutdown=true so the leave save WAITS for any in-flight
	-- save instead of coalescing (setting dirty+returning, then remove() would
	-- clear the session before the trailing save can run → data loss).
	task.spawn(function()
		pcall(DataManager.save, player, true)
		DataManager.remove(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[HarborHeist] Server initialized.")