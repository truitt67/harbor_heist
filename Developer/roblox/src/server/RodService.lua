local TweenService = game:GetService("TweenService")

local RodService = {}

local rods = {} -- [player] = { model, motor, baseC0, tipAttachment, level }
local activeCasts = {} -- [player] = { bobber, beam, folder }

local fxFolder = nil

local ROD_STYLES = {
	[1] = {
		pole = Color3.fromRGB(133, 92, 55),
		poleMaterial = Enum.Material.Wood,
		grip = Color3.fromRGB(70, 48, 30),
		reel = Color3.fromRGB(90, 90, 95),
		accent = Color3.fromRGB(170, 170, 175),
		glow = false,
	},
	[2] = {
		pole = Color3.fromRGB(105, 115, 130),
		poleMaterial = Enum.Material.Metal,
		grip = Color3.fromRGB(35, 40, 48),
		reel = Color3.fromRGB(60, 130, 180),
		accent = Color3.fromRGB(120, 200, 255),
		glow = false,
	},
	[3] = {
		pole = Color3.fromRGB(235, 190, 80),
		poleMaterial = Enum.Material.Metal,
		grip = Color3.fromRGB(60, 40, 20),
		reel = Color3.fromRGB(255, 215, 100),
		accent = Color3.fromRGB(255, 230, 140),
		glow = true,
	},
}

local function getFxFolder()
	if not fxFolder or not fxFolder.Parent then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "FishingFX"
		fxFolder.Parent = workspace
	end
	return fxFolder
end

local function decorate(part)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

local function buildRodModel(level)
	local style = ROD_STYLES[level] or ROD_STYLES[1]
	local model = Instance.new("Model")
	model.Name = "FishingRod"

	-- The rod is assembled along the handle's +X axis.
	local handle = decorate(Instance.new("Part"))
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Cylinder
	handle.Size = Vector3.new(1.2, 0.32, 0.32)
	handle.Color = style.grip
	handle.Material = Enum.Material.Fabric
	handle.Parent = model

	local pole = decorate(Instance.new("Part"))
	pole.Name = "Pole"
	pole.Shape = Enum.PartType.Cylinder
	pole.Size = Vector3.new(3.6, 0.14, 0.14)
	pole.Color = style.pole
	pole.Material = style.poleMaterial
	pole.CFrame = handle.CFrame * CFrame.new(2.35, 0, 0)
	pole.Parent = model

	local tip = decorate(Instance.new("Part"))
	tip.Name = "Tip"
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.new(0.14, 0.14, 0.14)
	tip.Color = style.accent
	tip.Material = style.glow and Enum.Material.Neon or Enum.Material.Metal
	tip.CFrame = handle.CFrame * CFrame.new(4.18, 0, 0)
	tip.Parent = model

	local reel = decorate(Instance.new("Part"))
	reel.Name = "Reel"
	reel.Shape = Enum.PartType.Cylinder
	reel.Size = Vector3.new(0.14, 0.42, 0.42)
	reel.Color = style.reel
	reel.Material = style.glow and Enum.Material.Neon or Enum.Material.Metal
	reel.CFrame = handle.CFrame * CFrame.new(0.75, -0.28, 0) * CFrame.Angles(0, 0, math.rad(90))
	reel.Parent = model

	if style.glow then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Rate = 2
		sparkle.Lifetime = NumberRange.new(0.6, 1)
		sparkle.Speed = NumberRange.new(0.2, 0.5)
		sparkle.Size = NumberSequence.new(0.08)
		sparkle.Color = ColorSequence.new(style.accent)
		sparkle.LightEmission = 1
		sparkle.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkle.Parent = tip
	end

	for _, part in ipairs({ pole, tip, reel }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end

	local tipAttachment = Instance.new("Attachment")
	tipAttachment.Name = "LineAttachment"
	tipAttachment.Parent = tip

	model.PrimaryPart = handle
	return model, tipAttachment
end

local function findRightHand(character)
	return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
end

function RodService.unequip(player)
	local record = rods[player]
	if record then
		if record.model then
			record.model:Destroy()
		end
		rods[player] = nil
	end
end

function RodService.equip(player, session)
	RodService.unequip(player)
	local character = player.Character
	if not character or not session then
		return
	end
	local hand = findRightHand(character)
	if not hand then
		return
	end

	-- N14: read the equipped rod level from the profile, not a nonexistent
	-- session.rodLevel field. Without this fix the rod visual was always level 1
	-- (Basic Rod) even after purchasing a Steel or Golden Rod.
	local level = (session.profile and session.profile.Equipment and session.profile.Equipment.EquippedRodLevel) or 1
	local model, tipAttachment = buildRodModel(level)

	-- Grip pose: rod points forward and tilted up out of the right hand.
	local isR15 = character:FindFirstChild("RightHand") ~= nil
	local baseC0
	if isR15 then
		baseC0 = CFrame.new(0, -0.15, -0.1) * CFrame.Angles(math.rad(35), math.rad(-90), 0)
	else
		baseC0 = CFrame.new(0, -0.9, -0.2) * CFrame.Angles(math.rad(35), math.rad(-90), 0)
	end

	local motor = Instance.new("Motor6D")
	motor.Name = "RodGrip"
	motor.Part0 = hand
	motor.Part1 = model.PrimaryPart
	motor.C0 = baseC0
	motor.C1 = CFrame.new(-0.35, 0, 0)
	motor.Parent = hand

	model.Parent = character

	rods[player] = {
		model = model,
		motor = motor,
		baseC0 = baseC0,
		tipAttachment = tipAttachment,
		level = level,
	}
end

local function tweenMotor(motor, targetC0, duration, easing)
	local tween = TweenService:Create(
		motor,
		TweenInfo.new(duration, easing or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = targetC0 }
	)
	tween:Play()
	return tween
end

local function playCastSwing(record)
	local motor = record.motor
	local base = record.baseC0
	if not motor or not motor.Parent then
		return
	end
	-- Wind up over the shoulder, flick forward, settle back to rest.
	local windup = base * CFrame.Angles(math.rad(55), 0, 0)
	local flick = base * CFrame.Angles(math.rad(-35), 0, 0)
	tweenMotor(motor, windup, 0.22, Enum.EasingStyle.Back)
	task.delay(0.24, function()
		if motor.Parent then
			tweenMotor(motor, flick, 0.13, Enum.EasingStyle.Quad)
		end
	end)
	task.delay(0.45, function()
		if motor.Parent then
			tweenMotor(motor, base, 0.35, Enum.EasingStyle.Quad)
		end
	end)
end

local function makeSplash(position, color, count)
	local splash = decorate(Instance.new("Part"))
	splash.Name = "Splash"
	splash.Transparency = 1
	splash.Anchored = true
	splash.Size = Vector3.new(0.2, 0.2, 0.2)
	splash.CFrame = CFrame.new(position)
	splash.Parent = getFxFolder()

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.7)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(55, 55)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(200, 230, 255))
	emitter.LightEmission = 0.4
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Acceleration = Vector3.new(0, -18, 0)
	emitter.Parent = splash
	emitter:Emit(count or 14)

	task.delay(1.2, function()
		splash:Destroy()
	end)
end

local function clearCastFX(player)
	local fx = activeCasts[player]
	if fx then
		activeCasts[player] = nil
		if fx.folder then
			fx.folder:Destroy()
		end
	end
end

function RodService.startCast(player, dock, castTime)
	clearCastFX(player)
	local record = rods[player]
	if not record then
		return
	end
	playCastSwing(record)

	local zone = dock and dock.fishingZone
	if not zone then
		return
	end
	local landing = (zone.CFrame * CFrame.new(0, 0, -4)).Position
	landing = Vector3.new(landing.X, 0.35, landing.Z)

	local folder = Instance.new("Folder")
	folder.Name = "Cast_" .. player.Name
	folder.Parent = getFxFolder()

	local bobber = decorate(Instance.new("Part"))
	bobber.Name = "Bobber"
	bobber.Shape = Enum.PartType.Ball
	bobber.Size = Vector3.new(0.45, 0.45, 0.45)
	bobber.Color = Color3.fromRGB(235, 65, 60)
	bobber.Material = Enum.Material.SmoothPlastic
	bobber.Anchored = true
	bobber.CFrame = CFrame.new(landing + Vector3.new(0, 6, 0))
	bobber.Parent = folder

	local ring = decorate(Instance.new("Part"))
	ring.Name = "BobberStripe"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, 0.5, 0.5)
	ring.Color = Color3.fromRGB(245, 245, 245)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Anchored = true
	ring.CFrame = bobber.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder

	local bobberAttachment = Instance.new("Attachment")
	bobberAttachment.Parent = bobber

	local beam = Instance.new("Beam")
	beam.Attachment0 = record.tipAttachment
	beam.Attachment1 = bobberAttachment
	beam.Width0 = 0.03
	beam.Width1 = 0.03
	beam.Color = ColorSequence.new(Color3.fromRGB(230, 230, 230))
	beam.Transparency = NumberSequence.new(0.25)
	beam.CurveSize0 = 1.5
	beam.CurveSize1 = -0.5
	beam.Segments = 12
	beam.Parent = bobber

	activeCasts[player] = { folder = folder, bobber = bobber, ring = ring, landing = landing }

	-- Drop the bobber onto the water after the swing, splash, then bob gently.
	task.delay(0.4, function()
		local fx = activeCasts[player]
		if not fx or fx.bobber ~= bobber or not bobber.Parent then
			return
		end
		local drop = TweenService:Create(
			bobber,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = CFrame.new(landing) }
		)
		drop:Play()
		drop.Completed:Once(function()
			if not bobber.Parent then
				return
			end
			ring.CFrame = bobber.CFrame * CFrame.Angles(0, 0, math.rad(90))
			makeSplash(landing, nil, 10)
			local bobTween = TweenService:Create(
				bobber,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ CFrame = CFrame.new(landing + Vector3.new(0, -0.18, 0)) }
			)
			bobTween:Play()
		end)
	end)
end

local function leapFish(player, rarity, fromPosition)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local fish = decorate(Instance.new("Part"))
	fish.Name = "CaughtFish"
	fish.Shape = Enum.PartType.Ball
	fish.Size = Vector3.new(1.4, 0.6, 0.45)
	fish.Color = rarity.color
	fish.Material = Enum.Material.Neon
	fish.Anchored = true
	fish.CFrame = CFrame.new(fromPosition)
	fish.Parent = getFxFolder()

	local shine = Instance.new("ParticleEmitter")
	shine.Rate = 0
	shine.Lifetime = NumberRange.new(0.4, 0.8)
	shine.Speed = NumberRange.new(2, 4)
	shine.SpreadAngle = Vector2.new(180, 180)
	shine.Size = NumberSequence.new(0.15)
	shine.Color = ColorSequence.new(rarity.color)
	shine.LightEmission = 1
	shine.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shine.Parent = fish

	makeSplash(fromPosition, rarity.color, 16)
	shine:Emit(12)

	-- Arc the fish from the water to the player's chest, then pop away.
	task.spawn(function()
		local target = root.Position + Vector3.new(0, 1, 0)
		local mid = (fromPosition + target) / 2 + Vector3.new(0, 6, 0)
		local duration = 0.55
		local elapsed = 0
		while elapsed < duration do
			local dt = task.wait()
			elapsed += dt
			if not fish.Parent or not root.Parent then
				break
			end
			local t = math.clamp(elapsed / duration, 0, 1)
			local a = fromPosition:Lerp(mid, t)
			local b = mid:Lerp(target, t)
			local pos = a:Lerp(b, t)
			local dir = b - pos
			if dir.Magnitude < 0.05 or math.abs(dir.Unit.Y) > 0.99 then
				fish.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(90), math.rad(t * 720))
			else
				fish.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.rad(90), math.rad(t * 720))
			end
		end
		if fish.Parent then
			shine:Emit(10)
			local shrink = TweenService:Create(
				fish,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 }
			)
			shrink:Play()
			shrink.Completed:Once(function()
				fish:Destroy()
			end)
		end
	end)
end

function RodService.endCast(player, success, rarity)
	local fx = activeCasts[player]
	local landing = fx and fx.landing
	clearCastFX(player)
	if success and rarity and landing then
		leapFish(player, rarity, landing)
	elseif landing then
		makeSplash(landing, Color3.fromRGB(160, 200, 230), 6)
	end
end

function RodService.onPlayerRemoving(player)
	clearCastFX(player)
	RodService.unequip(player)
end

function RodService.init(deps)
	-- Reserved for future dependency wiring; rod visuals are driven directly
	-- by FishingService and the character lifecycle in init.server.lua.
end

return RodService
