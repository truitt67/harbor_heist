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

function WorldBuilder.build()
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

	return worldFolder
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

	for i = 1, 5 do
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
end

return WorldBuilder
