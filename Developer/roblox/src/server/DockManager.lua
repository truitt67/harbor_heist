local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local DockManager = {}

local PLAZA_RADIUS = 40
local DOCK_LENGTH = 26
local DOCK_WIDTH = 6

local docks = {}
local docksFolder = nil

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

local function buildAquarium(dockModel, cframe)
	local aquarium = Instance.new("Model")
	aquarium.Name = "Aquarium"
	aquarium.Parent = dockModel

	local base = makePart({
		Name = "Base",
		Size = Vector3.new(6, 1, 4),
		CFrame = cframe,
		Color = Color3.fromRGB(70, 70, 80),
		Material = Enum.Material.Metal,
		Parent = aquarium,
	})

	local _water = makePart({
		Name = "Water",
		Size = Vector3.new(5.4, 3, 3.4),
		CFrame = cframe * CFrame.new(0, 2, 0),
		Color = Color3.fromRGB(60, 150, 220),
		Material = Enum.Material.Glass,
		Transparency = 0.5,
		CanCollide = false,
		Parent = aquarium,
	})

	makePart({
		Name = "Glass",
		Size = Vector3.new(6, 4, 4),
		CFrame = cframe * CFrame.new(0, 2.5, 0),
		Color = Color3.fromRGB(200, 230, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.75,
		CanCollide = true,
		Parent = aquarium,
	})

	local fishFolder = Instance.new("Folder")
	fishFolder.Name = "FishDisplay"
	fishFolder.Parent = aquarium

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "InfoSign"
	billboard.Size = UDim2.new(0, 220, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 90
	billboard.Parent = base

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "OwnerLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Unclaimed Dock"
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Parent = billboard

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusLabel"
	statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	statusLabel.TextStrokeTransparency = 0.3
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = billboard

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AquariumPrompt"
	prompt.ActionText = "Open / Steal"
	prompt.ObjectText = "Aquarium"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = base

	aquarium.PrimaryPart = base
	return aquarium
end

local function buildDock(index)
	local angle = math.rad((index - 1) * (360 / GameConfig.DockCount))
	local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local midPos = direction * (PLAZA_RADIUS + DOCK_LENGTH / 2)
	local endPos = direction * (PLAZA_RADIUS + DOCK_LENGTH - 4)
	local lookCFrame = CFrame.lookAt(midPos + Vector3.new(0, 1.5, 0), midPos + direction * 10 + Vector3.new(0, 1.5, 0))

	local dockModel = Instance.new("Model")
	dockModel.Name = "Dock" .. index
	dockModel.Parent = docksFolder

	local walkway = makePart({
		Name = "Walkway",
		Size = Vector3.new(DOCK_WIDTH, 1, DOCK_LENGTH),
		CFrame = lookCFrame,
		Color = Color3.fromRGB(150, 105, 70),
		Material = Enum.Material.WoodPlanks,
		Parent = dockModel,
	})

	for offset = -DOCK_LENGTH / 2 + 2, DOCK_LENGTH / 2 - 1, 8 do
		for _, side in ipairs({ -1, 1 }) do
			makePart({
				Name = "Piling",
				Size = Vector3.new(1, 8, 1),
				CFrame = lookCFrame * CFrame.new(side * (DOCK_WIDTH / 2 - 0.5), -3, offset),
				Color = Color3.fromRGB(100, 70, 45),
				Material = Enum.Material.Wood,
				Parent = dockModel,
			})
		end
	end

	local fishingZone = makePart({
		Name = "FishingZone",
		Size = Vector3.new(DOCK_WIDTH, 6, 8),
		CFrame = CFrame.lookAt(endPos, endPos + direction) * CFrame.new(0, 4, 0),
		Transparency = 0.85,
		Color = Color3.fromRGB(80, 200, 255),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = dockModel,
	})

	local zoneSign = Instance.new("BillboardGui")
	zoneSign.Size = UDim2.new(0, 140, 0, 32)
	zoneSign.StudsOffset = Vector3.new(0, 4, 0)
	zoneSign.MaxDistance = 60
	zoneSign.Parent = fishingZone
	local zoneLabel = Instance.new("TextLabel")
	zoneLabel.Size = UDim2.new(1, 0, 1, 0)
	zoneLabel.BackgroundTransparency = 1
	zoneLabel.Text = "Fishing Zone"
	zoneLabel.TextColor3 = Color3.fromRGB(160, 230, 255)
	zoneLabel.TextStrokeTransparency = 0.4
	zoneLabel.TextScaled = true
	zoneLabel.Font = Enum.Font.FredokaOne
	zoneLabel.Parent = zoneSign

	local aquariumOffset = lookCFrame * CFrame.new(DOCK_WIDTH / 2 + 3.5, -0.5, -DOCK_LENGTH / 2 + 4)
	local aquarium = buildAquarium(dockModel, aquariumOffset)

	makePart({
		Name = "AquariumPlatform",
		Size = Vector3.new(8, 1, 8),
		CFrame = lookCFrame * CFrame.new(DOCK_WIDTH / 2 + 3.5, -0.05, -DOCK_LENGTH / 2 + 4),
		Color = Color3.fromRGB(150, 105, 70),
		Material = Enum.Material.WoodPlanks,
		Parent = dockModel,
	})

	local spawnCFrame = lookCFrame * CFrame.new(0, 3.5, -DOCK_LENGTH / 2 + 3)

	return {
		index = index,
		model = dockModel,
		walkway = walkway,
		fishingZone = fishingZone,
		aquarium = aquarium,
		spawnCFrame = spawnCFrame,
		owner = nil,
	}
end

function DockManager.buildAll(parent)
	docksFolder = Instance.new("Folder")
	docksFolder.Name = "Docks"
	docksFolder.Parent = parent
	for i = 1, GameConfig.DockCount do
		docks[i] = buildDock(i)
	end
	return docks
end

function DockManager.claim(player)
	for _, dock in ipairs(docks) do
		if dock.owner == nil then
			dock.owner = player
			local sign = dock.aquarium.PrimaryPart.InfoSign
			sign.OwnerLabel.Text = player.DisplayName .. "'s Aquarium"
			dock.aquarium.PrimaryPart.AquariumPrompt.Enabled = true
			return dock
		end
	end
	return nil
end

function DockManager.release(player)
	-- RELIABILITY: Clean up dock when player leaves to reset state
	for _, dock in ipairs(docks) do
		if dock.owner == player then
			dock.owner = nil
			-- SECURITY: Verify sign exists before accessing children
			local aquariumBase = dock.aquarium.PrimaryPart
			if aquariumBase then
				local sign = aquariumBase:FindFirstChild("InfoSign")
				if sign then
					local ownerLabel = sign:FindFirstChild("OwnerLabel")
					if ownerLabel then
						ownerLabel.Text = "Unclaimed Dock"
					end
					local statusLabel = sign:FindFirstChild("StatusLabel")
					if statusLabel then
						statusLabel.Text = ""
					end
				end
				local prompt = aquariumBase:FindFirstChild("AquariumPrompt")
				if prompt then
					prompt.Enabled = false
				end
			end
			-- SECURITY: Clear fish display instances
			local fishDisplay = dock.aquarium:FindFirstChild("FishDisplay")
			if fishDisplay then
				fishDisplay:ClearAllChildren()
			end
			return
		end
	end
end

function DockManager.getDock(player)
	for _, dock in ipairs(docks) do
		if dock.owner == player then
			return dock
		end
	end
	return nil
end

function DockManager.getDockByAquarium(promptParent)
	for _, dock in ipairs(docks) do
		if dock.aquarium.PrimaryPart == promptParent then
			return dock
		end
	end
	return nil
end

function DockManager.isInFishingZone(dock, character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local zone = dock.fishingZone
	local relative = zone.CFrame:PointToObjectSpace(root.Position)
	local half = zone.Size / 2
	return math.abs(relative.X) <= half.X + 2
		and math.abs(relative.Y) <= half.Y + 3
		and math.abs(relative.Z) <= half.Z + 2
end

function DockManager.updateAquariumVisual(dock, session, capacity)
	-- SECURITY: Verify dock and session exist
	if not dock or not session then
		return
	end
	
	local rng = Random.new(dock.index * 1000 + #session.liveWell)
	local display = dock.aquarium.FishDisplay
	display:ClearAllChildren()

	local GameConfigRarities = GameConfig.Rarities
	local waterCFrame = dock.aquarium.Water.CFrame
	local shown = math.min(#session.liveWell, GameConfig.Aquarium.maxVisibleFish)
	
	-- SECURITY: Validate each rarity index before creating visual representation
	for i = 1, shown do
		local rarityIndex = session.liveWell[i]
		-- Validate rarity index is within bounds
		if not (type(rarityIndex) == "number" and rarityIndex >= 1 and rarityIndex <= #GameConfigRarities) then
			warn("[HarborHeist] Invalid rarity index in visual update: " .. tostring(rarityIndex))
			continue
		end
		
		local rarity = GameConfigRarities[rarityIndex]
		if not rarity then
			continue
		end
		
		local fish = Instance.new("Part")
		fish.Name = "Fish"
		fish.Shape = Enum.PartType.Ball
		fish.Size = Vector3.new(0.7, 0.5, 1.1)
		fish.Color = rarity.color
		fish.Material = Enum.Material.Neon
		fish.Anchored = true
		fish.CanCollide = false
		fish.CFrame = waterCFrame
			* CFrame.new(rng:NextNumber(-2, 2), rng:NextNumber(-1, 1), rng:NextNumber(-1.2, 1.2))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		fish.Parent = display
	end

	-- SECURITY: Verify sign elements exist before updating
	local sign = dock.aquarium.PrimaryPart and dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
	if not sign or not sign:FindFirstChild("StatusLabel") then
		return
	end
	
	local statusLabel = sign.StatusLabel
	local locked = session.lockedUntil > os.clock()
	if locked then
		statusLabel.Text = string.format("%d/%d fish  |  LOCKED", #session.liveWell, capacity)
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		statusLabel.Text = string.format("%d/%d fish", #session.liveWell, capacity)
		statusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	end
end

return DockManager
