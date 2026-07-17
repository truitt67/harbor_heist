local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local BoatService = {}

local boats = {}
local despawnTasks = {}
local seatConnections = {}

local dataManager = nil
local stateSync = nil

local function setSessionBoat(player, model)
	if not dataManager then
		return
	end
	local session = dataManager.get(player)
	if session then
		session.boatModel = model
		if stateSync and player.Parent then
			stateSync.push(session)
		end
	end
end

local function decoratePart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	return part
end

local function weldTo(hull, part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hull
	weld.Part1 = part
	weld.Parent = part
end

local WHITE = Color3.fromRGB(240, 242, 245)
local NAVY = Color3.fromRGB(28, 45, 72)
local TRIM_RED = Color3.fromRGB(190, 55, 50)
local DECK_WOOD = Color3.fromRGB(168, 125, 80)

local function makeBoatHull(player, spawnCFrame)
	local model = Instance.new("Model")
	model.Name = "Boat_" .. player.Name

	-- Main hull: white fiberglass, floats high thanks to low density.
	local hull = Instance.new("Part")
	hull.Name = "Hull"
	hull.Size = Vector3.new(4.8, 1.6, 11)
	hull.CFrame = spawnCFrame
	hull.Color = WHITE
	hull.Material = Enum.Material.SmoothPlastic
	hull.Anchored = false
	hull.CanCollide = true
	hull.CustomPhysicalProperties = PhysicalProperties.new(0.32, 0.4, 0.5)
	hull.Parent = model

	-- Pointed bow built from a wedge plus side tapers.
	local bow = Instance.new("WedgePart")
	bow.Name = "Bow"
	bow.Size = Vector3.new(4.8, 1.6, 3.2)
	bow.CFrame = spawnCFrame * CFrame.new(0, 0, -(11 / 2 + 3.2 / 2)) * CFrame.Angles(0, 0, math.rad(180))
	bow.Color = WHITE
	bow.Material = Enum.Material.SmoothPlastic
	bow.Anchored = false
	bow.CanCollide = true
	bow.Massless = true
	bow.Parent = model
	weldTo(hull, bow)

	-- Wood deck inset into the hull top.
	local deck = decoratePart(Instance.new("Part"))
	deck.Name = "Deck"
	deck.Size = Vector3.new(4.2, 0.15, 10.4)
	deck.CFrame = spawnCFrame * CFrame.new(0, 0.85, 0)
	deck.Color = DECK_WOOD
	deck.Material = Enum.Material.WoodPlanks
	deck.Parent = model
	weldTo(hull, deck)

	-- Gunwale rails and hull trim stripes.
	for _, side in ipairs({ -1, 1 }) do
		local rail = decoratePart(Instance.new("Part"))
		rail.Name = "Gunwale"
		rail.Size = Vector3.new(0.35, 0.45, 10.8)
		rail.CFrame = spawnCFrame * CFrame.new(side * 2.25, 1.05, 0)
		rail.Color = NAVY
		rail.Material = Enum.Material.SmoothPlastic
		rail.Parent = model
		weldTo(hull, rail)

		local stripe = decoratePart(Instance.new("Part"))
		stripe.Name = "TrimStripe"
		stripe.Size = Vector3.new(0.06, 0.32, 11)
		stripe.CFrame = spawnCFrame * CFrame.new(side * 2.42, 0.25, 0)
		stripe.Color = TRIM_RED
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Parent = model
		weldTo(hull, stripe)
	end

	-- Center console with slanted dash and steering wheel.
	local console = decoratePart(Instance.new("Part"))
	console.Name = "Console"
	console.Size = Vector3.new(1.8, 1.3, 0.9)
	console.CFrame = spawnCFrame * CFrame.new(0, 1.55, -1.4)
	console.Color = NAVY
	console.Material = Enum.Material.SmoothPlastic
	console.Parent = model
	weldTo(hull, console)

	local dash = Instance.new("WedgePart")
	decoratePart(dash)
	dash.Name = "Dash"
	dash.Size = Vector3.new(1.8, 0.5, 0.7)
	dash.CFrame = spawnCFrame * CFrame.new(0, 2.45, -1.5) * CFrame.Angles(0, math.rad(180), 0)
	dash.Color = NAVY
	dash.Material = Enum.Material.SmoothPlastic
	dash.Parent = model
	weldTo(hull, dash)

	local wheel = decoratePart(Instance.new("Part"))
	wheel.Name = "Wheel"
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(0.12, 0.85, 0.85)
	wheel.CFrame = spawnCFrame * CFrame.new(0, 2.35, -0.85) * CFrame.Angles(0, math.rad(90), math.rad(25))
	wheel.Color = Color3.fromRGB(50, 52, 58)
	wheel.Material = Enum.Material.SmoothPlastic
	wheel.Parent = model
	weldTo(hull, wheel)

	-- Windshield.
	local windshield = decoratePart(Instance.new("Part"))
	windshield.Name = "Windshield"
	windshield.Size = Vector3.new(2, 0.9, 0.1)
	windshield.CFrame = spawnCFrame * CFrame.new(0, 2.85, -1.85) * CFrame.Angles(math.rad(-18), 0, 0)
	windshield.Color = Color3.fromRGB(170, 215, 240)
	windshield.Material = Enum.Material.Glass
	windshield.Transparency = 0.55
	windshield.Parent = model
	weldTo(hull, windshield)

	-- Driver's seat: cushioned bench behind the console.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2.2, 0.5, 2)
	seat.CFrame = spawnCFrame * CFrame.new(0, 1.2, 0.6)
	seat.Color = NAVY
	seat.Material = Enum.Material.Fabric
	seat.Anchored = false
	seat.CanCollide = true
	seat.Massless = true
	seat.MaxSpeed = 32
	seat.Torque = 5
	seat.TurnSpeed = 8
	seat.HeadsUpDisplay = false
	seat.Parent = model
	weldTo(hull, seat)

	local backrest = decoratePart(Instance.new("Part"))
	backrest.Name = "Backrest"
	backrest.Size = Vector3.new(2.2, 1.1, 0.35)
	backrest.CFrame = spawnCFrame * CFrame.new(0, 1.85, 1.7)
	backrest.Color = NAVY
	backrest.Material = Enum.Material.Fabric
	backrest.Parent = model
	weldTo(hull, backrest)

	-- Outboard motor at the stern.
	local motorBody = decoratePart(Instance.new("Part"))
	motorBody.Name = "MotorBody"
	motorBody.Size = Vector3.new(0.9, 1.1, 0.7)
	motorBody.CFrame = spawnCFrame * CFrame.new(0, 1.35, 5.75)
	motorBody.Color = Color3.fromRGB(40, 42, 48)
	motorBody.Material = Enum.Material.SmoothPlastic
	motorBody.Parent = model
	weldTo(hull, motorBody)

	local motorCowl = decoratePart(Instance.new("Part"))
	motorCowl.Name = "MotorCowl"
	motorCowl.Shape = Enum.PartType.Ball
	motorCowl.Size = Vector3.new(0.9, 0.5, 0.7)
	motorCowl.CFrame = spawnCFrame * CFrame.new(0, 1.95, 5.75)
	motorCowl.Color = TRIM_RED
	motorCowl.Material = Enum.Material.SmoothPlastic
	motorCowl.Parent = model
	weldTo(hull, motorCowl)

	local shaft = decoratePart(Instance.new("Part"))
	shaft.Name = "MotorShaft"
	shaft.Size = Vector3.new(0.25, 1.4, 0.35)
	shaft.CFrame = spawnCFrame * CFrame.new(0, 0.2, 5.8)
	shaft.Color = Color3.fromRGB(40, 42, 48)
	shaft.Material = Enum.Material.SmoothPlastic
	shaft.Parent = model
	weldTo(hull, shaft)

	local prop = decoratePart(Instance.new("Part"))
	prop.Name = "Propeller"
	prop.Shape = Enum.PartType.Cylinder
	prop.Size = Vector3.new(0.1, 0.55, 0.55)
	prop.CFrame = spawnCFrame * CFrame.new(0, -0.45, 5.95) * CFrame.Angles(0, math.rad(90), 0)
	prop.Color = Color3.fromRGB(180, 185, 195)
	prop.Material = Enum.Material.Metal
	prop.Parent = model
	weldTo(hull, prop)

	-- Bow navigation light.
	local navLight = decoratePart(Instance.new("Part"))
	navLight.Name = "NavLight"
	navLight.Shape = Enum.PartType.Ball
	navLight.Size = Vector3.new(0.3, 0.3, 0.3)
	navLight.CFrame = spawnCFrame * CFrame.new(0, 1.1, -6.6)
	navLight.Color = Color3.fromRGB(120, 255, 170)
	navLight.Material = Enum.Material.Neon
	navLight.Parent = model
	weldTo(hull, navLight)
	local glow = Instance.new("PointLight")
	glow.Color = navLight.Color
	glow.Range = 8
	glow.Brightness = 0.8
	glow.Parent = navLight

	-- Invisible perimeter colliders: keep the boat from sliding under/through
	-- dock walkways (the visible deck parts are non-collidable decorations)
	-- while leaving the cockpit open so players can board.
	local function addCollider(size, offset)
		local collider = Instance.new("Part")
		collider.Name = "Collider"
		collider.Size = size
		collider.CFrame = spawnCFrame * offset
		collider.Transparency = 1
		collider.Anchored = false
		collider.CanCollide = true
		collider.CanQuery = false
		collider.CanTouch = false
		collider.Massless = true
		collider.Parent = model
		weldTo(hull, collider)
	end
	addCollider(Vector3.new(0.35, 1.6, 10.8), CFrame.new(-2.25, 1.6, 0))
	addCollider(Vector3.new(0.35, 1.6, 10.8), CFrame.new(2.25, 1.6, 0))
	addCollider(Vector3.new(4.6, 1.6, 0.35), CFrame.new(0, 1.6, -5.4))
	addCollider(Vector3.new(4.6, 1.6, 0.35), CFrame.new(0, 1.6, 5.4))

	-- Propulsion: a VehicleSeat alone has no wheels to drive, so translate its
	-- Throttle/Steer into velocity constraints on the hull.
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = hull

	local linear = Instance.new("LinearVelocity")
	linear.Name = "DriveVelocity"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.VectorVelocity = Vector3.zero
	linear.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	linear.MaxAxesForce = Vector3.new(60000, 0, 60000)
	linear.Parent = hull

	local angular = Instance.new("AngularVelocity")
	angular.Name = "DriveTurn"
	angular.Attachment0 = attachment
	angular.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	angular.AngularVelocity = Vector3.zero
	angular.MaxTorque = 60000
	angular.Parent = hull

	-- Wake trail + spray behind the stern while under power.
	local wakeA = Instance.new("Attachment")
	wakeA.Position = Vector3.new(-1.6, -0.7, 5.4)
	wakeA.Parent = hull
	local wakeB = Instance.new("Attachment")
	wakeB.Position = Vector3.new(1.6, -0.7, 5.4)
	wakeB.Parent = hull

	local wake = Instance.new("Trail")
	wake.Name = "Wake"
	wake.Attachment0 = wakeA
	wake.Attachment1 = wakeB
	wake.Lifetime = 1.6
	wake.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	wake.Color = ColorSequence.new(Color3.fromRGB(225, 245, 255))
	wake.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	wake.FaceCamera = false
	wake.Enabled = false
	wake.Parent = hull

	local sprayAttachment = Instance.new("Attachment")
	sprayAttachment.Position = Vector3.new(0, -0.5, 5.6)
	sprayAttachment.Parent = hull
	local spray = Instance.new("ParticleEmitter")
	spray.Name = "Spray"
	spray.Rate = 0
	spray.Lifetime = NumberRange.new(0.4, 0.8)
	spray.Speed = NumberRange.new(4, 8)
	spray.SpreadAngle = Vector2.new(30, 15)
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	spray.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Acceleration = Vector3.new(0, -14, 0)
	spray.EmissionDirection = Enum.NormalId.Back
	spray.Parent = sprayAttachment

	local function updateDrive()
		local throttle = seat.Throttle
		linear.VectorVelocity = Vector3.new(0, 0, -throttle * seat.MaxSpeed)
		angular.AngularVelocity = Vector3.new(0, -seat.Steer * 1.2, 0)
		local moving = throttle ~= 0
		wake.Enabled = moving
		spray.Rate = moving and 22 or 0
	end
	seat:GetPropertyChangedSignal("Throttle"):Connect(updateDrive)
	seat:GetPropertyChangedSignal("Steer"):Connect(updateDrive)

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
	setSessionBoat(player, model)

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
		setSessionBoat(player, nil)
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
	dataManager = deps.dataManager
	stateSync = deps.stateSync

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
		-- Spawn in open water past the platform edge, bow facing out to sea.
		local spawnCFrame = spawnPart.CFrame * CFrame.new(0, 1, 12) * CFrame.Angles(0, math.rad(180), 0)
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
