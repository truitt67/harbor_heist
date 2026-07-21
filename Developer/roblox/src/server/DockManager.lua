local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local FishVisuals = require(ReplicatedStorage.Shared.FishVisuals) -- TASK 2.8
-- TASK 5.6 / DEC-6: rarity ordinal for curated highest-rarity display
-- selection. GameConfig.Rarities is ordered Common -> Legendary, so the
-- array index doubles as a rarity rank (higher == rarer).
local RARITY_ORD = {}
for _i, _r in ipairs(GameConfig.Rarities) do
	RARITY_ORD[_r.name] = _i
end

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

	-- Gentle bubble column rising through the tank.
	local bubbleAttachment = Instance.new("Attachment")
	bubbleAttachment.Position = Vector3.new(1.8, 0.5, 0)
	bubbleAttachment.Parent = base
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Rate = 3
	bubbles.Lifetime = NumberRange.new(1.2, 1.8)
	bubbles.Speed = NumberRange.new(1.2, 2)
	bubbles.SpreadAngle = Vector2.new(8, 8)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(1, 0.16),
	})
	bubbles.Color = ColorSequence.new(Color3.fromRGB(210, 240, 255))
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Parent = bubbleAttachment

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
	zoneLabel.Text = "Starter Pier"
	zoneLabel.TextColor3 = Color3.fromRGB(160, 230, 255)
	zoneLabel.TextStrokeTransparency = 0.4
	zoneLabel.TextScaled = true
	zoneLabel.Font = Enum.Font.FredokaOne
	zoneLabel.Parent = zoneSign

	-- Deep Water zone: further out, requires better rod (TASK 2.2)
	local deepEndPos = direction * (PLAZA_RADIUS + DOCK_LENGTH + 14)
	local deepWaterZone = makePart({
		Name = "DeepWaterZone",
		Size = Vector3.new(DOCK_WIDTH + 2, 6, 10),
		CFrame = CFrame.lookAt(deepEndPos, deepEndPos + direction) * CFrame.new(0, 4, 0),
		Transparency = 0.9,
		Color = Color3.fromRGB(30, 80, 180),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = dockModel,
	})

	local deepSign = Instance.new("BillboardGui")
	deepSign.Size = UDim2.new(0, 160, 0, 32)
	deepSign.StudsOffset = Vector3.new(0, 4, 0)
	deepSign.MaxDistance = 60
	deepSign.Parent = deepWaterZone
	local deepLabel = Instance.new("TextLabel")
	deepLabel.Size = UDim2.new(1, 0, 1, 0)
	deepLabel.BackgroundTransparency = 1
	deepLabel.Text = "Deep Water (Rod 2+)"
	deepLabel.TextColor3 = Color3.fromRGB(100, 150, 255)
	deepLabel.TextStrokeTransparency = 0.4
	deepLabel.TextScaled = true
	deepLabel.Font = Enum.Font.FredokaOne
	deepLabel.Parent = deepSign

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
		deepWaterZone = deepWaterZone,
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
	-- RELIABILITY: Clean up dock when player leaves to reset state.
	-- N7: clear ALL docks whose owner == player, not just the first — a
	-- double-claim (double-fired onPlayerAdded, rejoin race) can leave a
	-- second dock stuck enabled with a stale owner Player ref.
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
			-- TASK 6.4: clear cosmetic dock décor so a re-claimed dock resets
			-- to the next owner's tier (rebuilt on their join/store refresh).
			local dockDecor = dock.model and dock.model:FindFirstChild("DockDecor")
			if dockDecor then
				dockDecor:ClearAllChildren()
			end
			-- N7: no early return — keep scanning so any other dock this player
			-- may own from a double-claim race is also released.
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
		return false, nil
	end
	local zones = {
		{ zone = dock.fishingZone, zoneId = "StarterPier" },
		{ zone = dock.deepWaterZone, zoneId = "DeepWater" },
	}
	for _, entry in ipairs(zones) do
		local zone = entry.zone
		if zone then
			local relative = zone.CFrame:PointToObjectSpace(root.Position)
			local half = zone.Size / 2
			if math.abs(relative.X) <= half.X + 2
				and math.abs(relative.Y) <= half.Y + 3
				and math.abs(relative.Z) <= half.Z + 2 then
				return true, entry.zoneId
			end
		end
	end
	return false, nil
end

-- TASK 6.4 (EPIC 6 / 17): unlock cosmetic dock décor per Dock.UpgradeLevel.
-- Tier 1 = base dock (no décor). Tier 2+ adds a warm lantern on a piling;
-- tier 3+ adds a banner on the opposite piling; tier 4 gilds the lantern.
-- Bounded: at most ~3 static anchored parts per dock, rebuilt from
-- profile.Dock.UpgradeLevel so the visual matches the purchased tier and
-- resets on dock release. Cosmetic-only — no gameplay effect.
function DockManager.updateDockCosmetics(dock, session)
	if not dock or not session then
		return
	end
	local dockModel = dock.model
	if not dockModel then
		return
	end
	local decor = dockModel:FindFirstChild("DockDecor")
	if not decor then
		decor = Instance.new("Folder")
		decor.Name = "DockDecor"
		decor.Parent = dockModel
	end
	decor:ClearAllChildren()

	local tier = (session.profile.Dock and session.profile.Dock.UpgradeLevel) or 1
	if tier < 2 then
		return -- base dock: no décor
	end

	local anchor = dock.walkway and dock.walkway.CFrame
	if not anchor then
		return
	end

	-- Lantern on the near-left piling (tier 2+); gilded at tier 4.
	local lanternColor = (tier >= 4) and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(255, 200, 120)
	local lantern = makePart({
		Name = "Lantern",
		Size = Vector3.new(0.7, 1.1, 0.7),
		CFrame = anchor * CFrame.new(-(DOCK_WIDTH / 2 - 0.5), 2.0, -DOCK_LENGTH / 2 + 4),
		Color = lanternColor,
		Material = Enum.Material.Neon,
		CanCollide = false, -- decorative: don't obstruct players near the dock edge
		Parent = decor,
	})
	local light = Instance.new("PointLight")
	light.Color = lanternColor
	light.Range = 16
	light.Brightness = (tier >= 4) and 2.2 or 1.4
	light.Parent = lantern

	-- Banner on the near-right piling (tier 3+); golden at tier 4.
	if tier >= 3 then
		local bannerColor = (tier >= 4) and Color3.fromRGB(255, 180, 60) or Color3.fromRGB(120, 200, 255)
		makePart({
			Name = "Banner",
			Size = Vector3.new(0.3, 2.2, 1.4),
			CFrame = anchor * CFrame.new((DOCK_WIDTH / 2 - 0.5), 3.0, -DOCK_LENGTH / 2 + 4),
			Color = bannerColor,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false, -- decorative: don't obstruct players near the dock edge
			Parent = decor,
		})
	end
end

function DockManager.updateAquariumVisual(dock, session, capacity)
	-- SECURITY: Verify dock and session exist
	if not dock or not session then
		return
	end
	
	local stored = session.profile.Aquarium.StoredFish

	-- TASK 5.6 / DEC-6: curate the displayed subset by HIGHEST rarity
	-- (not storage order) and tally total stored value for the AQUA-08 sign.
	local validFish = {}
	local totalValue = 0
	for i = 1, #stored do
		local fishData = stored[i]
		if type(fishData) ~= "table"
			or type(fishData.Rarity) ~= "string"
			or type(fishData.SpeciesId) ~= "string" then
			warn("[HarborHeist] Invalid fish record in visual update at index " .. i)
		else
			if type(fishData.BaseSellValue) == "number" then
				totalValue = totalValue + fishData.BaseSellValue
			end
			table.insert(validFish, fishData)
		end
	end

	-- Highest rarity first, then sell value, then SpeciesId for a stable
	-- deterministic layout (Luau's table.sort is not guaranteed stable).
	table.sort(validFish, function(a, b)
		local oa = RARITY_ORD[a.Rarity] or 0
		local ob = RARITY_ORD[b.Rarity] or 0
		if oa ~= ob then
			return oa > ob
		end
		local va = a.BaseSellValue or 0
		local vb = b.BaseSellValue or 0
		if va ~= vb then
			return va > vb
		end
		return a.SpeciesId < b.SpeciesId
	end)

	local rng = Random.new(dock.index * 1000 + #stored)
	local display = dock.aquarium.FishDisplay
	display:ClearAllChildren()

	local waterCFrame = dock.aquarium.Water.CFrame
	local shown = math.min(#validFish, GameConfig.Aquarium.maxVisibleFish)

	-- SECURITY: validFish entries are pre-validated above; render via the
	-- TASK 2.8 FishVisuals archetype factory (shape from SpeciesId, rarity
	-- adds size/glow/particles; falls back to a default archetype).
	for i = 1, shown do
		local fishData = validFish[i]
		local speciesId = fishData.SpeciesId
		local fishModel = FishVisuals.build(speciesId, fishData.Rarity)
		local body = fishModel.PrimaryPart

		local startYaw = rng:NextNumber(0, math.pi * 2)
		local startCFrame = waterCFrame
			* CFrame.new(rng:NextNumber(-1.8, 1.8), rng:NextNumber(-0.9, 0.9), rng:NextNumber(-1.1, 1.1))
			* CFrame.Angles(0, startYaw, 0)
		fishModel:SetPrimaryPartCFrame(startCFrame)
		fishModel.Parent = display

		-- Gentle looping swim: drift sideways/vertically with a slow turn, reversing forever.
		local driftCFrame = startCFrame
			* CFrame.new(rng:NextNumber(0.5, 1.1), rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.5, 0.5))
			* CFrame.Angles(0, rng:NextNumber(-0.9, 0.9), rng:NextNumber(-0.08, 0.08))
		local swimTween = TweenService:Create(
			body,
			TweenInfo.new(
				rng:NextNumber(2.2, 3.6),
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true,
				rng:NextNumber(0, 1.5)
			),
			{ CFrame = driftCFrame }
		)
		swimTween:Play()
	end

	-- SECURITY: Verify sign elements exist before updating
	local sign = dock.aquarium.PrimaryPart and dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
	if not sign or not sign:FindFirstChild("StatusLabel") then
		return
	end
	
	local statusLabel = sign.StatusLabel
	local locked = session.lockedUntil > os.clock()
	if locked then
		statusLabel.Text = string.format("%d/%d fish  •  $%d  |  LOCKED", #stored, capacity, totalValue)
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		statusLabel.Text = string.format("%d/%d fish  •  $%d", #stored, capacity, totalValue)
		statusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	end

	-- TASK 6.4: refresh dock cosmetic décor so the visual matches the
	-- purchased Dock.UpgradeLevel (covers join + store/sell refresh paths).
	DockManager.updateDockCosmetics(dock, session)
end

return DockManager
