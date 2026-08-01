local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
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

-- TASK 24.1 (hvfh.4.1): injected via init(deps) — used to show the live
-- income RATE on the dock InfoSign so it always matches the HUD snapshot.
local stateSync = nil

function DockManager.init(deps)
	stateSync = deps.stateSync
end

local PLAZA_RADIUS = 40
local DOCK_LENGTH = 26
local DOCK_WIDTH = 6

local docks = {}
local docksFolder = nil

-- TASK 12.3: global pool for aquarium fish models so we don't create/destroy
-- them on every store/sell update. Models are keyed by species+rarity and
-- capped at a server-wide total to avoid unbounded memory growth.
local fishModelPool = {} -- [key] = { model1, model2, ... }
local activeFishTweens = {} -- [model] = Tween
local MAX_POOL_SIZE = 80
local poolFolder = nil

local function getPoolFolder()
	if not poolFolder then
		poolFolder = Instance.new("Folder")
		poolFolder.Name = "FishModelPool"
		poolFolder.Parent = ServerStorage
	end
	return poolFolder
end

local function stopFishTween(model)
	local tween = activeFishTweens[model]
	if tween then
		tween:Cancel()
		activeFishTweens[model] = nil
	end
end

local function releaseModel(model)
	if not model or not model.Parent then
		return
	end
	stopFishTween(model)
	model.Parent = getPoolFolder()
	local key = model:GetAttribute("FishModelKey")
	if key then
		fishModelPool[key] = fishModelPool[key] or {}
		table.insert(fishModelPool[key], model)
	end
end

local function getPooledModel(key)
	local pool = fishModelPool[key]
	if pool then
		for i = #pool, 1, -1 do
			local model = pool[i]
			if model and model.Parent then
				table.remove(pool, i)
				return model
			end
		end
	end
	return nil
end

local function trimPool()
	local total = 0
	for _, pool in pairs(fishModelPool) do
		total += #pool
	end
	if total <= MAX_POOL_SIZE then
		return
	end
	local excess = total - MAX_POOL_SIZE
	for _, pool in pairs(fishModelPool) do
		while excess > 0 and #pool > 0 do
			local model = table.remove(pool, 1)
			if model then
				stopFishTween(model)
				model:Destroy()
			end
			excess -= 1
		end
		if excess <= 0 then
			break
		end
	end
end

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
	-- TASK 14.14: "Open / Steal" was stale once walk-up stealing was removed
	-- (TASK 8.0/gdj.15) -- the prompt now only opens the OWNER's aquarium
	-- (init.server.lua connectAquariumPrompt), so "Open" is the accurate,
	-- neutral verb. Per-player text would need a client override (EPIC 12).
	prompt.ActionText = "Open"
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
		originalWalkwayColor = walkway.Color,
		originalWalkwayMaterial = walkway.Material,
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
			-- harborheist-review-aug2026-6yp6.8: FindFirstChild + nil guards,
			-- matching release()'s defensive pattern (was direct indexing —
			-- crashes if a future change rebuilds the aquarium model).
			local aquariumBase = dock.aquarium.PrimaryPart
			if aquariumBase then
				local sign = aquariumBase:FindFirstChild("InfoSign")
				if sign then
					local ownerLabel = sign:FindFirstChild("OwnerLabel")
					if ownerLabel then
						ownerLabel.Text = player.DisplayName .. "'s Aquarium"
					end
				end
				local prompt = aquariumBase:FindFirstChild("AquariumPrompt")
				if prompt then
					prompt.Enabled = true
				end
			end
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
			-- TASK 12.3: release fish display models back to the global pool instead
			-- of destroying them, so the next aquarium update can reuse them.
			local fishDisplay = dock.aquarium:FindFirstChild("FishDisplay")
			if fishDisplay then
				for _, child in ipairs(fishDisplay:GetChildren()) do
					releaseModel(child)
				end
			end
			-- TASK 6.4: clear cosmetic dock décor so a re-claimed dock resets
			-- to the next owner's tier (rebuilt on their join/store refresh).
			local dockDecor = dock.model and dock.model:FindFirstChild("DockDecor")
			-- TASK 17.5: restore the base walkway color/material so a level-4
			-- dock does not leave a golden walkway for the next owner.
			if dock.walkway then
				dock.walkway.Color = dock.originalWalkwayColor
				dock.walkway.Material = dock.originalWalkwayMaterial
			end
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

-- TASK 6.4 / TASK 17.5 (EPIC 6 / 17): render cosmetic dock upgrades per
-- Dock.UpgradeLevel. Tier 1 = base dock. Tier 2 adds lamp posts at the
-- entrance. Tier 3 adds planters along the walkway. Tier 4 applies golden
-- trim to the walkway. Cosmetic-only — no gameplay effect.
local function buildLampPost(parent, cframe)
	local pole = makePart({
		Name = "LampPostPole",
		Size = Vector3.new(0.8, 5, 0.8),
		CFrame = cframe,
		Color = Color3.fromRGB(60, 60, 60),
		Material = Enum.Material.Metal,
		CanCollide = false, -- decorative: don't obstruct players
		Parent = parent,
	})
	local lamp = makePart({
		Name = "LampPostLight",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		CFrame = cframe * CFrame.new(0, 3, 0),
		Color = Color3.fromRGB(255, 235, 150),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 230, 160)
	light.Parent = lamp
	return pole
end

local function buildPlanter(parent, cframe)
	makePart({ -- harborheist-6u6e: box variable was never referenced
		Name = "PlanterBox",
		Size = Vector3.new(1.6, 1, 1.6),
		CFrame = cframe,
		Color = Color3.fromRGB(120, 80, 50),
		Material = Enum.Material.Wood,
		CanCollide = false,
		Parent = parent,
	})
	makePart({
		Name = "PlanterFoliage",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.0, 1.2),
		CFrame = cframe * CFrame.new(0, 0.6, 0),
		Color = Color3.fromRGB(60, 160, 80),
		Material = Enum.Material.Grass,
		CanCollide = false,
		Parent = parent,
	})
end

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
	local tierConfig = GameConfig.DockUpgradeTiers[tier] or {}
	local cosmeticUnlocks = tierConfig.cosmeticUnlocks or {}
	local unlockSet = {}
	for _, name in ipairs(cosmeticUnlocks) do
		unlockSet[name] = true
	end

	local anchor = dock.walkway and dock.walkway.CFrame

	-- Lamp posts at the dock entrance (tier 2+).
	if unlockSet["LampPost"] and anchor then
		local leftPost = anchor * CFrame.new(-(DOCK_WIDTH / 2 - 0.5), 2.5, -DOCK_LENGTH / 2 + 1.5)
		local rightPost = anchor * CFrame.new((DOCK_WIDTH / 2 - 0.5), 2.5, -DOCK_LENGTH / 2 + 1.5)
		buildLampPost(decor, leftPost)
		buildLampPost(decor, rightPost)
	end

	-- Planters along the walkway edges (tier 3+).
	if unlockSet["Planters"] and anchor then
		for _, zOffset in ipairs({ -3, 5 }) do
			for _, side in ipairs({ -1, 1 }) do
				local planterCFrame = anchor * CFrame.new(side * (DOCK_WIDTH / 2 - 0.3), 0.5, zOffset)
				buildPlanter(decor, planterCFrame)
			end
		end
	end

	-- Golden trim: gold-tinted walkway with metal material (tier 4+).
	if unlockSet["GoldenTrim"] then
		if dock.walkway then
			dock.walkway.Color = Color3.fromRGB(200, 170, 50)
			dock.walkway.Material = Enum.Material.Metal
		end
	else
		-- Restore the base dock appearance when cosmetics are absent or downgraded.
		if dock.walkway then
			dock.walkway.Color = dock.originalWalkwayColor
			dock.walkway.Material = dock.originalWalkwayMaterial
		end
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
	-- harborheist-review-aug2026-6yp6.8: FindFirstChild + nil guards (was
	-- direct indexing; a missing FishDisplay means nothing to render into).
	local display = dock.aquarium:FindFirstChild("FishDisplay")
	if not display then return end

	-- TASK 12.3: pool fish models instead of destroying/recreating them on
	-- every store/sell refresh. Move currently displayed models back to the
	-- global pool so they can be reused for the same (species, rarity) pair.
	for _, child in ipairs(display:GetChildren()) do
		releaseModel(child)
	end

	-- 6yp6.8: guarded Water lookup — the origin fallback is defensive-only;
	-- buildAll always creates Water, so this path means broken structure.
	local waterPart = dock.aquarium:FindFirstChild("Water")
	local waterCFrame = waterPart and waterPart.CFrame or CFrame.new(0, 0, 0)
	local shown = math.min(#validFish, GameConfig.Aquarium.maxVisibleFish)

	-- SECURITY: validFish entries are pre-validated above; render via the
	-- TASK 2.8 FishVisuals archetype factory (shape from SpeciesId, rarity
	-- adds size/glow/particles; falls back to a default archetype).
	for i = 1, shown do
		local fishData = validFish[i]
		local speciesId = fishData.SpeciesId
		local rarityName = fishData.Rarity
		local key = FishVisuals.getModelKey(speciesId, rarityName)

		-- Try to reuse a pooled model for this visual identity; build a new one
		-- only if the pool has no match.
		local fishModel = getPooledModel(key)
		if not fishModel then
			fishModel = FishVisuals.build(speciesId, rarityName)
			fishModel:SetAttribute("FishModelKey", key)
		end

		local body = fishModel.PrimaryPart
		if body then
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
			activeFishTweens[fishModel] = swimTween
		end
	end

	-- TASK 12.3: cap the global pool so memory does not grow without bound.
	trimPool()

	-- SECURITY: Verify sign elements exist before updating
	local sign = dock.aquarium.PrimaryPart and dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
	if not sign or not sign:FindFirstChild("StatusLabel") then
		return
	end
	
	local statusLabel = sign.StatusLabel
	-- TASK 24.1 (hvfh.4.1): append the income RATE (per-minute, matching the
	-- multiplier-aware StateSync snapshot value) so earning is advertised in
	-- the world. Rate only, NOT the live claimable number: this function runs
	-- on store/sell/lock/raid events rather than per-second, so a claimable
	-- figure would go stale — the rate changes only on those same events
	-- (+upgrades), so it is always fresh.
	local incomePerMin = (stateSync and stateSync.incomePerSec(session) or 0) * 60
	local locked = session.lockedUntil > os.clock()
	if locked then
		statusLabel.Text = string.format("%d/%d fish  •  $%d  •  $%.1f/min  |  LOCKED", #stored, capacity, totalValue, incomePerMin)
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		statusLabel.Text = string.format("%d/%d fish  •  $%d  •  $%.1f/min", #stored, capacity, totalValue, incomePerMin)
		statusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	end

	-- TASK 6.4: refresh dock cosmetic décor so the visual matches the
	-- purchased Dock.UpgradeLevel (covers join + store/sell refresh paths).
	DockManager.updateDockCosmetics(dock, session)
end

return DockManager
