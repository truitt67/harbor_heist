local Players = game:GetService("Players")

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
}

local fishingCleanup = FishingService.init(deps).onPlayerRemoving
AquariumService.init(deps)
ShopService.init(deps)
FishInventoryService.init(deps)
QuestService.init(deps)
BoatService.init(deps)
CollectionService.init(deps) -- EPIC 7 / TASK 7.2 (collection book remote)
OnboardingService.init(deps) -- EPIC 9 / TASK 9.1 (onboarding flag writer)
AquariumService.startIncomeLoop(deps)
DataManager.startAutosave()
DataManager.bindToClose()

Remotes.GetState.OnServerInvoke = function(player)
	local session = DataManager.get(player)
	if session then
		return StateSync.snapshot(session)
	end
	return nil
end

local shopPrompt = worldFolder.Shop.Counter.ShopPrompt
shopPrompt.Triggered:Connect(function(player)
	Remotes.OpenShop:FireClient(player)
end)

local boatPrompt = worldFolder.BoatDock.PrimaryPart.BoatPrompt
boatPrompt.Triggered:Connect(function(player)
	local session = DataManager.get(player)
	if not session then
		return
	end
	if BoatService.getModel(player) then
		Remotes.notify(player, "You already have a boat!", Color3.fromRGB(255, 170, 80))
		return
	end
	local dockModel = worldFolder.BoatDock
	local spawnPart = dockModel:FindFirstChild("SpawnPoint")
	if spawnPart then
		-- Spawn in open water past the platform edge, bow facing out to sea
		-- (kept in sync with the SpawnBoat remote in BoatService).
		local spawnCFrame = spawnPart.CFrame * CFrame.new(0, 1, 12) * CFrame.Angles(0, math.rad(180), 0)
		local r = BoatService.spawnBoat(player, spawnCFrame)
		if r.ok and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = spawnCFrame * CFrame.new(0, 3, 0)
			end
			Remotes.notify(player, "Boat launched! Drive to other docks to steal.", Color3.fromRGB(120, 220, 255))
		end
	end
end)

local function connectAquariumPrompt(dock)
	local prompt = dock.aquarium.PrimaryPart.AquariumPrompt
	prompt.Triggered:Connect(function(player)
		if dock.owner == player then
			Remotes.OpenAquarium:FireClient(player)
		elseif dock.owner ~= nil then
			AquariumService.handleSteal(deps, player, dock)
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
	DataManager.save(player)

	-- EPIC 11 (TASK 11.2): churn signals. Fire BEFORE clearSession so the
	-- funnel state is still readable. A player who leaves without catching
	-- or upgrading is a retention red flag — these events power the
	-- "where did they drop off?" funnel analysis.
	local funnel = AnalyticsService.getFunnelState(player.UserId)
	if not funnel.firstCatchAt then
		AnalyticsService.track(player, "player_left_before_first_catch")
	end
	if not funnel.firstUpgradeAt then
		AnalyticsService.track(player, "player_left_before_first_upgrade")
	end

	DockManager.release(player)
	BoatService.onPlayerRemoving(player)
	RodService.onPlayerRemoving(player)
	-- EPIC 11 (TASK 11.1): clear analytics session to prevent unbounded
	-- growth of the sessions table across long server uptimes. Called AFTER
	-- other cleanup so any churn events fired by those services still have
	-- a valid session to read, and BEFORE DataManager.remove so UserId resolves.
	AnalyticsService.clearSession(player)
	DataManager.remove(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[HarborHeist] Server initialized.")