local WorldBuilder = {}

local function makePart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		part[key] = value
	end
	return part
end

function WorldBuilder.setupEnvironment()
	local lighting = game:GetService("Lighting")
	lighting.ClockTime = 15.6
	lighting.Brightness = 2.4
	lighting.ExposureCompensation = 0.15
	lighting.EnvironmentDiffuseScale = 0.6
	lighting.EnvironmentSpecularScale = 0.8
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.35
	lighting.Ambient = Color3.fromRGB(96, 110, 128)
	lighting.OutdoorAmbient = Color3.fromRGB(128, 140, 156)

	local atmosphere = lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.6
	atmosphere.Color = Color3.fromRGB(199, 214, 230)
	atmosphere.Decay = Color3.fromRGB(106, 132, 165)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.6
	atmosphere.Parent = lighting

	local bloom = lighting:FindFirstChild("HarborBloom") or Instance.new("BloomEffect")
	bloom.Name = "HarborBloom"
	bloom.Intensity = 0.6
	bloom.Size = 32
	bloom.Threshold = 1.05
	bloom.Parent = lighting

	local color = lighting:FindFirstChild("HarborColor") or Instance.new("ColorCorrectionEffect")
	color.Name = "HarborColor"
	color.Brightness = 0.02
	color.Contrast = 0.08
	color.Saturation = 0.12
	color.TintColor = Color3.fromRGB(255, 250, 242)
	color.Parent = lighting

	local sunRays = lighting:FindFirstChild("HarborSunRays") or Instance.new("SunRaysEffect")
	sunRays.Name = "HarborSunRays"
	sunRays.Intensity = 0.08
	sunRays.Spread = 0.6
	sunRays.Parent = lighting

	if not workspace.Terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.42
		clouds.Density = 0.28
		clouds.Color = Color3.fromRGB(235, 240, 248)
		clouds.Parent = workspace.Terrain
	end

	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(28, 92, 128)
	terrain.WaterReflectance = 0.6
	terrain.WaterTransparency = 0.7
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 12
end

function WorldBuilder.build()
	WorldBuilder.setupEnvironment()

	local worldFolder = Instance.new("Folder")
	worldFolder.Name = "HarborWorld"
	worldFolder.Parent = workspace

	workspace.Terrain:FillBlock(
		CFrame.new(0, -8, 0),
		Vector3.new(600, 16, 600),
		Enum.Material.Water
	)

	local seabed = makePart({
		Name = "Seabed",
		Size = Vector3.new(600, 4, 600),
		CFrame = CFrame.new(0, -18, 0),
		Color = Color3.fromRGB(120, 110, 90),
		Material = Enum.Material.Sand,
		Parent = worldFolder,
	})
	seabed.Locked = true

	local plaza = makePart({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 80, 80),
		CFrame = CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(160, 120, 80),
		Material = Enum.Material.WoodPlanks,
		Parent = worldFolder,
	})
	plaza.Locked = true

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "PlazaSpawn"
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.CFrame = CFrame.new(0, 3, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Color = Color3.fromRGB(140, 100, 65)
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.Duration = 0
	spawnLocation.Parent = worldFolder

	WorldBuilder.buildShop(worldFolder)
	WorldBuilder.buildDecorations(worldFolder)
	WorldBuilder.buildBoatDock(worldFolder)
	WorldBuilder.buildRaidWaters(worldFolder)
	WorldBuilder.buildSafeHarbor(worldFolder)

	return worldFolder
end

function WorldBuilder.buildBoatDock(parent)
	local boatDock = Instance.new("Model")
	boatDock.Name = "BoatDock"
	boatDock.Parent = parent

	local dockZ = 38
	local platform = makePart({
		Name = "Platform",
		Size = Vector3.new(10, 1, 14),
		CFrame = CFrame.new(0, 0.5, dockZ),
		Color = Color3.fromRGB(150, 105, 70),
		Material = Enum.Material.WoodPlanks,
		Parent = boatDock,
	})

	for _, xOffset in ipairs({ -5, 5 }) do
		makePart({
			Name = "Railing",
			Size = Vector3.new(0.5, 1.5, 14),
			CFrame = CFrame.new(xOffset, 1.5, dockZ),
			Color = Color3.fromRGB(100, 70, 45),
			Material = Enum.Material.Wood,
			Parent = boatDock,
		})
	end

	local spawnPoint = Instance.new("Part")
	spawnPoint.Name = "SpawnPoint"
	spawnPoint.Size = Vector3.new(6, 0.1, 6)
	spawnPoint.CFrame = CFrame.new(0, 0.6, dockZ + 4)
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.Anchored = true
	spawnPoint.Parent = boatDock

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BoatSign"
	billboard.Size = UDim2.new(0, 160, 0, 42)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 110
	billboard.Parent = platform

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "BOAT DOCK"
	label.TextColor3 = Color3.fromRGB(100, 200, 255)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoatPrompt"
	prompt.ActionText = "Spawn Boat"
	prompt.ObjectText = "Boat Dock"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = platform

	boatDock.PrimaryPart = platform
	return prompt
end

-- TASK 8.2 (gdj.2): the "Raid Waters" pier (PRD PVP-02). A clearly marked
-- risk zone: standing on it opts you into raids for as long as you stay
-- (RaidService watches Zone.Touched/TouchEnded). Built opposite the boat
-- dock so the harbor reads: safe plaza in the middle, risk on the fringes.
function WorldBuilder.buildRaidWaters(parent)
	local raidWaters = Instance.new("Model")
	raidWaters.Name = "RaidWaters"
	raidWaters.Parent = parent

	local dockZ = -38
	local platform = makePart({
		Name = "Platform",
		Size = Vector3.new(10, 1, 14),
		CFrame = CFrame.new(0, 0.5, dockZ),
		Color = Color3.fromRGB(90, 50, 55),
		Material = Enum.Material.WoodPlanks,
		Parent = raidWaters,
	})
	platform.Locked = true

	for _, xOffset in ipairs({ -5, 5 }) do
		makePart({
			Name = "Railing",
			Size = Vector3.new(0.5, 1.5, 14),
			CFrame = CFrame.new(xOffset, 1.5, dockZ),
			Color = Color3.fromRGB(70, 35, 40),
			Material = Enum.Material.Wood,
			Parent = raidWaters,
		})
	end

	-- Red warning buoys flanking the pier mouth — non-threatening but
	-- unmistakable "danger ahead" signaling per PRD raid-visual guidance.
	for _, xOffset in ipairs({ -4, 4 }) do
		makePart({
			Name = "WarningBuoy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(xOffset, 1.2, dockZ - 8),
			Color = Color3.fromRGB(255, 80, 80),
			Material = Enum.Material.Neon,
			Parent = raidWaters,
		})
	end

	-- The opt-in volume itself. Invisible, non-colliding; Touched events do
	-- the work. Slightly larger than the platform so stepping onto any part
	-- of the pier registers.
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Size = Vector3.new(11, 6, 15)
	zone.CFrame = CFrame.new(0, 2.5, dockZ)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.Anchored = true
	zone.Parent = raidWaters

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RaidSign"
	billboard.Size = UDim2.new(0, 200, 0, 56)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 110
	billboard.Parent = platform

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "RAID WATERS\nOpt in to PvP raids while here"
	label.TextColor3 = Color3.fromRGB(255, 110, 110)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	raidWaters.PrimaryPart = platform
	return raidWaters
end

-- TASK 8.11 (gdj.11): Safe harbor zone — central plaza area where PvP raids
-- are disabled (PRD PVP-11). A clearly marked, invisible, non-colliding zone
-- that RaidService watches with Touched/TouchEnded + polling. Players standing
-- inside cannot initiate or be targeted by raids. Visually marked with green
-- buoys and a billboard sign so players understand the protection.
function WorldBuilder.buildSafeHarbor(parent)
	local safeHarbor = Instance.new("Model")
	safeHarbor.Name = "SafeHarbor"
	safeHarbor.Parent = parent

	local marker = makePart({
		Name = "Marker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, 56, 56),
		CFrame = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 180, 100),
		Material = Enum.Material.Neon,
		Transparency = 0.9,
		CanCollide = false,
		Parent = safeHarbor,
	})
	marker.Locked = true

	for _, angleDeg in ipairs({ 0, 90, 180, 270 }) do
		local angle = math.rad(angleDeg)
		makePart({
			Name = "SafeBuoy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(math.cos(angle) * 28, 1.2, math.sin(angle) * 28),
			Color = Color3.fromRGB(60, 200, 120),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = safeHarbor,
		})
	end

	-- Zone extends to ±29 on X/Z. Sized at 58 (not 80, the full plaza
	-- diameter) to avoid overlapping the Raid Waters zone at z=-30.5
	-- (RaidWaters.Zone center z=-38, half-depth 7.5 → leading edge z=-30.5).
	-- A player at the Raid Waters pier should be opted in to PvP, NOT
	-- simultaneously protected by the safe harbor.
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Size = Vector3.new(58, 8, 58)
	zone.CFrame = CFrame.new(0, 2, 0)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.Anchored = true
	zone.Parent = safeHarbor

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SafeHarborSign"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 6.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 110
	billboard.Parent = marker

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "SAFE HARBOR\nPvP raids disabled here"
	label.TextColor3 = Color3.fromRGB(100, 230, 130)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	safeHarbor.PrimaryPart = zone
	return safeHarbor
end

function WorldBuilder.buildShop(parent)
	local shop = Instance.new("Model")
	shop.Name = "Shop"
	shop.Parent = parent

	local base = makePart({
		Name = "Counter",
		Size = Vector3.new(8, 4, 3),
		CFrame = CFrame.new(0, 4, -14),
		Color = Color3.fromRGB(110, 75, 50),
		Material = Enum.Material.Wood,
		Parent = shop,
	})

	makePart({
		Name = "Roof",
		Size = Vector3.new(10, 1, 5),
		CFrame = CFrame.new(0, 9, -14),
		Color = Color3.fromRGB(200, 60, 60),
		Material = Enum.Material.Fabric,
		Parent = shop,
	})

	for _, xOffset in ipairs({ -4.5, 4.5 }) do
		makePart({
			Name = "Pole",
			Size = Vector3.new(0.6, 7, 0.6),
			CFrame = CFrame.new(xOffset, 5.5, -14),
			Color = Color3.fromRGB(90, 60, 40),
			Material = Enum.Material.Wood,
			Parent = shop,
		})
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ShopSign"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 120
	billboard.Parent = base

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "BAIT & TACKLE SHOP"
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Bait & Tackle"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = base

	shop.PrimaryPart = base
	return prompt
end

function WorldBuilder.buildDecorations(parent)
	local rng = Random.new(42)
	for i = 1, 6 do
		local angle = math.rad(i * 60 + 30)
		local radius = 30
		local post = makePart({
			Name = "LampPost",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = CFrame.new(math.cos(angle) * radius, 5.5, math.sin(angle) * radius),
			Color = Color3.fromRGB(60, 60, 60),
			Material = Enum.Material.Metal,
			Parent = parent,
		})
		local lamp = makePart({
			Name = "Lamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = post.CFrame * CFrame.new(0, 5, 0),
			Color = Color3.fromRGB(255, 235, 150),
			Material = Enum.Material.Neon,
			Parent = parent,
		})
		local light = Instance.new("PointLight")
		light.Range = 18
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 230, 160)
		light.Parent = lamp
	end

	for _ = 1, 5 do
		makePart({
			Name = "Crate",
			Size = Vector3.new(3, 3, 3),
			CFrame = CFrame.new(rng:NextNumber(-24, 24), 2.5, rng:NextNumber(8, 24))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			Color = Color3.fromRGB(150, 110, 70),
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end

	-- TASK 13.4 (mxl.4): Cozy harbor aesthetic — nautical props per PRD
	-- visual direction: "lanterns, simple nautical props." Plaza props sit
	-- between lamp posts at radius 22-28, clear of dock walkways (docks
	-- start at PLAZA_RADIUS=40 and extend outward). Harbor rocks sit at
	-- the waterline (radius 42-48) for a natural coastline.
	-- All Y values are relative to the plaza top surface (Y=2.5: the
	-- plaza cylinder is Size 4 centered at Y=0.5 + 90deg Z rotation, so
	-- its top face is at Y=2.5). Props sit ON the surface, not embedded.

	-- Barrels — weathered fishing-line barrels near the plaza edge
	for i = 1, 4 do
		local angle = math.rad(i * 90 + 15)
		local r = 22
		makePart({
			Name = "Barrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 2.2, 2.2),
			CFrame = CFrame.new(math.cos(angle) * r, 4.0, math.sin(angle) * r)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(110, 80, 50),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Rope coils — coiled fishing rope on the plaza near barrels
	for i = 1, 3 do
		local angle = math.rad(i * 120 + 45)
		local r = 25
		makePart({
			Name = "RopeCoil",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 2, 2),
			CFrame = CFrame.new(math.cos(angle) * r, 2.9, math.sin(angle) * r)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(180, 155, 110),
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Potted plants — greenery for a cozy harbor feel ("plants, rocks")
	-- Pot sits on the plaza surface; bush sits on top of the pot.
	for i = 1, 5 do
		local angle = math.rad(i * 72 + 10)
		local r = 28
		makePart({
			Name = "PlantPot",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, 1.5, 1.5),
			CFrame = CFrame.new(math.cos(angle) * r, 3.5, math.sin(angle) * r)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 90, 60),
			Material = Enum.Material.Wood,
			CanCollide = false,
			Parent = parent,
		})
		-- Ball parts in Roblox are always perfect spheres (diameter = smallest
		-- Size axis). Use uniform size so the intended diameter renders.
		makePart({
			Name = "PlantBush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = CFrame.new(math.cos(angle) * r, 5.6, math.sin(angle) * r),
			Color = Color3.fromRGB(60, 130, 65),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = parent,
		})
	end

	-- Harbor rocks — partially submerged boulders at the harbor edge
	-- for visual interest and a natural coastline feel. Placed outside
	-- the plaza disc (radius > 40) in the water terrain; CanCollide = false
	-- so they don't block boats or swimming players.
	for i = 1, 8 do
		local angle = math.rad(i * 45 + 22.5)
		local r = rng:NextNumber(42, 48)
		local size = rng:NextNumber(3, 6)
		makePart({
			Name = "HarborRock",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.new(math.cos(angle) * r, rng:NextNumber(-1, 1.5), math.sin(angle) * r),
			Color = Color3.fromRGB(90, 88, 85),
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = parent,
		})
	end
end

return WorldBuilder
