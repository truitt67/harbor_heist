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
}

local fishingCleanup = FishingService.init(deps).onPlayerRemoving
AquariumService.init(deps)
ShopService.init(deps)
FishInventoryService.init(deps)
QuestService.init(deps)
BoatService.init(deps)
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
	DockManager.release(player)
	BoatService.onPlayerRemoving(player)
	RodService.onPlayerRemoving(player)
	DataManager.remove(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[HarborHeist] Server initialized.")