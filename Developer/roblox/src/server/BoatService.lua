local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local BoatService = {}

local boats = {}
local despawnTasks = {}
local seatConnections = {}

local function makeBoatHull(player, spawnCFrame)
	local model = Instance.new("Model")
	model.Name = "Boat_" .. player.Name

	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(4, 1.5, 10)
	hull.CFrame = spawnCFrame
	hull.Color = Color3.fromRGB(120, 80, 50)
	hull.Material = Enum.Material.WoodPlanks
	hull.Anchored = false
	hull.CanCollide = true
	hull.BuoyancyAttachment = nil
	hull.Parent = model

	local bow = Instance.new("Part")
	bow.Name = "Bow"
	bow.Shape = Enum.PartType.Wedge
	bow.Size = Vector3.new(4, 1.5, 3)
	bow.CFrame = spawnCFrame * CFrame.new(0, 0, -(10 / 2 + 3 / 2))
	bow.Color = Color3.fromRGB(140, 95, 60)
	bow.Material = Enum.Material.WoodPlanks
	bow.Anchored = false
	bow.CanCollide = true
	bow.Parent = model

	local bowWeld = Instance.new("WeldConstraint")
	bowWeld.Part0 = hull
	bowWeld.Part1 = bow
	bowWeld.Parent = bow

	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2.5, 1, 2.5)
	seat.CFrame = spawnCFrame * CFrame.new(0, 1.5, 0)
	seat.Color = Color3.fromRGB(90, 60, 40)
	seat.Material = Enum.Material.Leather
	seat.Anchored = false
	seat.CanCollide = true
	seat.MaxSpeed = 32
	seat.Torque = 5
	seat.TurnSpeed = 8
	seat.Parent = model

	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = hull
	seatWeld.Part1 = seat
	seatWeld.Parent = seat

	model.PrimaryPart = hull
	return model, seat
end

function BoatService.spawnBoat(player, spawnCFrame)
	if boats[player] then
		return { ok = false, reason = "already_has_boat" }
	end
	if not player.Character then
		return { ok = false, reason = "no_character" }
	end

	local model, seat = makeBoatHull(player, spawnCFrame)
	model.Parent = workspace

	boats[player] = model

	local conn
	conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			if despawnTasks[player] then
				task.cancel(despawnTasks[player])
				despawnTasks[player] = nil
			end
		else
			if despawnTasks[player] then
				task.cancel(despawnTasks[player])
			end
			despawnTasks[player] = task.delay(GameConfig.Boat.despawnDelay, function()
				BoatService.despawnBoat(player)
			end)
		end
	end)
	seatConnections[player] = conn

	return { ok = true }
end

function BoatService.despawnBoat(player)
	local model = boats[player]
	if model then
		model:Destroy()
		boats[player] = nil
	end
	if despawnTasks[player] then
		task.cancel(despawnTasks[player])
		despawnTasks[player] = nil
	end
	if seatConnections[player] then
		seatConnections[player]:Disconnect()
		seatConnections[player] = nil
	end
end

function BoatService.setModel(player, model)
	boats[player] = model
end

function BoatService.getModel(player)
	return boats[player]
end

function BoatService.onPlayerRemoving(player)
	BoatService.despawnBoat(player)
end

function BoatService.init(deps)
	local remotes = deps.remotes
	local worldFolder = deps.worldFolder

	remotes.SpawnBoat.OnServerInvoke = function(player)
		if boats[player] then
			return { ok = false, reason = "already_has_boat" }
		end
		local boatDock = worldFolder and worldFolder:FindFirstChild("BoatDock")
		if not boatDock then
			return { ok = false, reason = "no_dock" }
		end
		local spawnPart = boatDock:FindFirstChild("SpawnPoint")
		if not spawnPart then
			return { ok = false, reason = "no_spawn_point" }
		end
		local spawnCFrame = spawnPart.CFrame * CFrame.new(0, 1, 4)
		local result = BoatService.spawnBoat(player, spawnCFrame)
		if result.ok and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = spawnCFrame * CFrame.new(0, 3, 0)
			end
		end
		if result.ok then
			remotes.notify(player, "Boat launched! Drive to other docks and pull up to their aquarium.", Color3.fromRGB(120, 220, 255))
		end
		return result
	end
end

return BoatService
