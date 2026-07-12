local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local Remotes = {}
for _, child in ipairs(remotesFolder:GetChildren()) do
	Remotes[child.Name] = child
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local state = nil
local casting = false
local castHitZone = { start_ = 0.35, finish = 0.65 }
local castDeadline = 0
local castInputConn = nil
local castTimeoutConn = nil
local questData = nil

local COLORS = {
	panel = Color3.fromRGB(25, 40, 55),
	panelLight = Color3.fromRGB(40, 60, 80),
	accent = Color3.fromRGB(80, 180, 255),
	good = Color3.fromRGB(90, 220, 120),
	bad = Color3.fromRGB(255, 100, 100),
	warn = Color3.fromRGB(255, 190, 80),
	text = Color3.fromRGB(240, 245, 250),
	quest = Color3.fromRGB(255, 215, 100),
	boat = Color3.fromRGB(100, 180, 220),
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HarborHeistUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

local function makeLabel(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.text
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	for key, value in pairs(props) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

local function makeButton(parent, props)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = COLORS.accent
	button.TextColor3 = Color3.fromRGB(15, 25, 35)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.AutoButtonColor = true
	for key, value in pairs(props) do
		button[key] = value
	end
	button.Parent = parent
	corner(button, 10)
	return button
end

-- ============ HUD: cash display ============
local cashFrame = Instance.new("Frame")
cashFrame.Size = UDim2.new(0, 220, 0, 74)
cashFrame.Position = UDim2.new(0, 12, 0, 12)
cashFrame.BackgroundColor3 = COLORS.panel
cashFrame.BackgroundTransparency = 0.15
cashFrame.Parent = screenGui
corner(cashFrame)

local cashLabel = makeLabel(cashFrame, {
	Size = UDim2.new(1, -16, 0.55, 0),
	Position = UDim2.new(0, 8, 0, 4),
	Text = "$0",
	TextColor3 = Color3.fromRGB(140, 255, 150),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local incomeLabel = makeLabel(cashFrame, {
	Size = UDim2.new(1, -16, 0.32, 0),
	Position = UDim2.new(0, 8, 0.58, 0),
	Text = "+$0.0/sec",
	TextColor3 = Color3.fromRGB(150, 210, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.GothamBold,
})

-- ============ Bottom action bar ============
local actionBar = Instance.new("Frame")
actionBar.Size = UDim2.new(0, 640, 0, 64)
actionBar.Position = UDim2.new(0.5, -320, 1, -84)
actionBar.BackgroundTransparency = 1
actionBar.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.Parent = actionBar

local fishButton = makeButton(actionBar, {
	Size = UDim2.new(0, 120, 1, 0),
	Text = "FISH (F)",
	BackgroundColor3 = COLORS.good,
})

local storeButton = makeButton(actionBar, {
	Size = UDim2.new(0, 130, 1, 0),
	Text = "STORE (0)",
	BackgroundColor3 = COLORS.accent,
})

local aquariumButton = makeButton(actionBar, {
	Size = UDim2.new(0, 130, 1, 0),
	Text = "AQUARIUM",
	BackgroundColor3 = Color3.fromRGB(180, 140, 255),
})

local questButton = makeButton(actionBar, {
	Size = UDim2.new(0, 120, 1, 0),
	Text = "QUESTS (Q)",
	BackgroundColor3 = COLORS.quest,
})

local boatButton = makeButton(actionBar, {
	Size = UDim2.new(0, 110, 1, 0),
	Text = "BOAT (B)",
	BackgroundColor3 = COLORS.boat,
})

-- ============ Notifications ============
local notifyFrame = Instance.new("Frame")
notifyFrame.Size = UDim2.new(0, 420, 0, 260)
notifyFrame.Position = UDim2.new(0.5, -210, 0, 90)
notifyFrame.BackgroundTransparency = 1
notifyFrame.Parent = screenGui

local notifyLayout = Instance.new("UIListLayout")
notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
notifyLayout.Padding = UDim.new(0, 6)
notifyLayout.Parent = notifyFrame

local function showNotification(message, color)
	local note = Instance.new("TextLabel")
	note.Size = UDim2.new(1, 0, 0, 34)
	note.BackgroundColor3 = COLORS.panel
	note.BackgroundTransparency = 0.2
	note.Text = message
	note.TextColor3 = color or COLORS.text
	note.Font = Enum.Font.FredokaOne
	note.TextScaled = true
	note.TextWrapped = true
	note.Parent = notifyFrame
	corner(note, 8)
	task.delay(4, function()
		if not note.Parent then return end
		local tween = TweenService:Create(note, TweenInfo.new(0.5), { BackgroundTransparency = 1, TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		note:Destroy()
	end)
end

-- ============ Aquarium panel ============
local aquariumPanel = Instance.new("Frame")
aquariumPanel.Size = UDim2.new(0, 340, 0, 360)
aquariumPanel.Position = UDim2.new(0.5, -170, 0.5, -180)
aquariumPanel.BackgroundColor3 = COLORS.panel
aquariumPanel.Visible = false
aquariumPanel.Parent = screenGui
corner(aquariumPanel, 14)

makeLabel(aquariumPanel, {
	Size = UDim2.new(1, -60, 0, 36),
	Position = UDim2.new(0, 14, 0, 8),
	Text = "MY AQUARIUM",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLORS.accent,
})

local aquariumClose = makeButton(aquariumPanel, {
	Size = UDim2.new(0, 32, 0, 32),
	Position = UDim2.new(1, -42, 0, 10),
	Text = "X",
	BackgroundColor3 = COLORS.bad,
})

local aquariumStats = makeLabel(aquariumPanel, {
	Size = UDim2.new(1, -28, 0, 70),
	Position = UDim2.new(0, 14, 0, 48),
	Text = "",
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextScaled = false,
	TextSize = 18,
})

local rarityList = makeLabel(aquariumPanel, {
	Size = UDim2.new(1, -28, 0, 130),
	Position = UDim2.new(0, 14, 0, 120),
	Text = "",
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextScaled = false,
	TextSize = 16,
	RichText = true,
})

local sellButton = makeButton(aquariumPanel, {
	Size = UDim2.new(0.5, -20, 0, 46),
	Position = UDim2.new(0, 14, 1, -60),
	Text = "SELL ALL",
	BackgroundColor3 = COLORS.good,
})

local lockButton = makeButton(aquariumPanel, {
	Size = UDim2.new(0.5, -20, 0, 46),
	Position = UDim2.new(0.5, 6, 1, -60),
	Text = "LOCK",
	BackgroundColor3 = COLORS.warn,
})

-- ============ Shop panel ============
local shopPanel = Instance.new("Frame")
shopPanel.Size = UDim2.new(0, 380, 0, 480)
shopPanel.Position = UDim2.new(0.5, -190, 0.5, -240)
shopPanel.BackgroundColor3 = COLORS.panel
shopPanel.Visible = false
shopPanel.Parent = screenGui
corner(shopPanel, 14)

makeLabel(shopPanel, {
	Size = UDim2.new(1, -60, 0, 36),
	Position = UDim2.new(0, 14, 0, 8),
	Text = "BAIT & TACKLE SHOP",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLORS.warn,
})

local shopClose = makeButton(shopPanel, {
	Size = UDim2.new(0, 32, 0, 32),
	Position = UDim2.new(1, -42, 0, 10),
	Text = "X",
	BackgroundColor3 = COLORS.bad,
})

local shopList = Instance.new("ScrollingFrame")
shopList.Size = UDim2.new(1, -28, 1, -66)
shopList.Position = UDim2.new(0, 14, 0, 52)
shopList.BackgroundTransparency = 1
shopList.ScrollBarThickness = 6
shopList.CanvasSize = UDim2.new(0, 0, 0, 0)
shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopList.Parent = shopPanel

local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 8)
shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
shopLayout.Parent = shopList

local shopRows = {}

local SHOP_CATALOG = {}
local function addCatalog(kind, items, orderBase)
	for level, item in ipairs(items) do
		table.insert(SHOP_CATALOG, { kind = kind, level = level, item = item, order = orderBase + level })
	end
end
addCatalog("rod", GameConfig.Rods, 0)
addCatalog("bait", GameConfig.Baits, 10)
addCatalog("capacity", GameConfig.Upgrades.Capacity, 20)
addCatalog("lock", GameConfig.Upgrades.Lock, 30)
addCatalog("alarm", GameConfig.Upgrades.Alarm, 40)
table.sort(SHOP_CATALOG, function(a, b) return a.order < b.order end)

local function itemDisplayName(entry)
	return entry.item.name or entry.item.desc or entry.kind
end

local function itemSubText(entry)
	local it = entry.item
	if entry.kind == "rod" or entry.kind == "bait" then
		return (it.desc or "") .. "  (+" .. (it.luck or 0) .. " luck)"
	elseif entry.kind == "capacity" then
		return "Capacity: " .. (it.capacity or 0) .. " fish"
	elseif entry.kind == "lock" then
		return "Lock " .. (it.lockDuration or 0) .. "s, recharge " .. (it.lockCooldown or 0) .. "s"
	elseif entry.kind == "alarm" then
		return "Stun thief " .. (it.stunDuration or 0) .. "s on failed heist"
	end
	return it.desc or ""
end

local function buildShopRow(entry)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 64)
	row.BackgroundColor3 = COLORS.panelLight
	row.LayoutOrder = entry.order
	row.Parent = shopList
	corner(row, 10)

	makeLabel(row, {
		Size = UDim2.new(0.62, -10, 0.5, 0),
		Position = UDim2.new(0, 10, 0, 4),
		Text = itemDisplayName(entry),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 18,
	})

	makeLabel(row, {
		Size = UDim2.new(0.62, -10, 0.4, 0),
		Position = UDim2.new(0, 10, 0.52, 0),
		Text = itemSubText(entry),
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(180, 200, 220),
	})

	local buyButton = makeButton(row, {
		Size = UDim2.new(0.32, 0, 0, 40),
		Position = UDim2.new(0.66, 0, 0.5, -20),
		Text = "$" .. (entry.item.cost or 0),
	})

	buyButton.Activated:Connect(function()
		local result = Remotes.BuyItem:InvokeServer(entry.kind, entry.level)
		if result and result.ok then
			refreshShop()
		end
	end)

	shopRows[entry.kind .. entry.level] = { row = row, buyButton = buyButton, level = entry.level, kind = entry.kind, item = entry.item }
end

function refreshShop()
	if not state then
		return
	end
	for _, entry in pairs(shopRows) do
		local currentLevel
		if entry.kind == "rod" then currentLevel = state.rodLevel
		elseif entry.kind == "bait" then currentLevel = state.baitLevel
		elseif entry.kind == "capacity" then currentLevel = state.capacityLevel or 0
		elseif entry.kind == "lock" then currentLevel = state.lockLevel or 0
		elseif entry.kind == "alarm" then currentLevel = state.alarmLevel or 0
		end
		if entry.level <= currentLevel then
			entry.buyButton.Text = "OWNED"
			entry.buyButton.BackgroundColor3 = Color3.fromRGB(100, 110, 120)
			entry.buyButton.Active = false
		elseif entry.level == currentLevel + 1 then
			entry.buyButton.Text = "$" .. entry.item.cost
			entry.buyButton.BackgroundColor3 = COLORS.good
			entry.buyButton.Active = true
		else
			entry.buyButton.Text = "LOCKED"
			entry.buyButton.BackgroundColor3 = Color3.fromRGB(70, 80, 90)
			entry.buyButton.Active = false
		end
	end
end

for _, entry in ipairs(SHOP_CATALOG) do
	buildShopRow(entry)
end

-- ============ Quest panel ============
local questPanel = Instance.new("Frame")
questPanel.Size = UDim2.new(0, 380, 0, 460)
questPanel.Position = UDim2.new(0.5, -190, 0.5, -230)
questPanel.BackgroundColor3 = COLORS.panel
questPanel.Visible = false
questPanel.Parent = screenGui
corner(questPanel, 14)

makeLabel(questPanel, {
	Size = UDim2.new(1, -60, 0, 36),
	Position = UDim2.new(0, 14, 0, 8),
	Text = "QUESTS",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = COLORS.quest,
})

local questClose = makeButton(questPanel, {
	Size = UDim2.new(0, 32, 0, 32),
	Position = UDim2.new(1, -42, 0, 10),
	Text = "X",
	BackgroundColor3 = COLORS.bad,
})

local questList = Instance.new("ScrollingFrame")
questList.Size = UDim2.new(1, -28, 1, -66)
questList.Position = UDim2.new(0, 14, 0, 52)
questList.BackgroundTransparency = 1
questList.ScrollBarThickness = 6
questList.CanvasSize = UDim2.new(0, 0, 0, 0)
questList.AutomaticCanvasSize = Enum.AutomaticSize.Y
questList.Parent = questPanel

local questLayout = Instance.new("UIListLayout")
questLayout.Padding = UDim.new(0, 8)
questLayout.SortOrder = Enum.SortOrder.LayoutOrder
questLayout.Parent = questList

local function makeQuestRow(parent, quest, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 64)
	row.BackgroundColor3 = COLORS.panelLight
	row.LayoutOrder = order
	row.Parent = parent
	corner(row, 10)

	local titleColor = quest.claimed and Color3.fromRGB(140, 220, 140) or COLORS.text
	makeLabel(row, {
		Size = UDim2.new(1, -16, 0.5, 0),
		Position = UDim2.new(0, 8, 0, 4),
		Text = quest.desc or "Quest",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 16,
		TextColor3 = titleColor,
	})

	local progressVal = math.min(quest.progress or 0, quest.target or 1)
	local progressBar = Instance.new("Frame")
	progressBar.Size = UDim2.new(0.6, -16, 0, 10)
	progressBar.Position = UDim2.new(0, 8, 0.62, 0)
	progressBar.BackgroundColor3 = Color3.fromRGB(50, 60, 70)
	progressBar.Parent = row
	corner(progressBar, 5)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(progressVal / math.max(1, quest.target or 1), 0, 1, 0)
	fill.BackgroundColor3 = quest.claimed and COLORS.good or COLORS.quest
	fill.Parent = progressBar
	corner(fill, 5)

	local progressText = quest.claimed and "CLAIMED" or string.format("%d/%d  ($%d)", progressVal, quest.target, quest.reward)
	makeLabel(row, {
		Size = UDim2.new(0.4, -8, 0.4, 0),
		Position = UDim2.new(0.6, 4, 0.6, 0),
		Text = progressText,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextScaled = false,
		TextSize = 14,
		TextColor3 = Color3.fromRGB(180, 220, 255),
		Font = Enum.Font.GothamBold,
	})
end

local sectionOrder = 0
local function renderQuestPanel(data)
	questList:ClearAllChildren()
	questLayout.Parent = questList
	sectionOrder = 0

	makeLabel(questList, {
		Size = UDim2.new(1, 0, 0, 26),
		Text = "DAILY",
		TextColor3 = COLORS.warn,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for i, q in ipairs(data and data.dailyQuests or {}) do
		makeQuestRow(questList, q, 10 + i)
	end

	makeLabel(questList, {
		Size = UDim2.new(1, 0, 0, 26),
		Text = "WEEKLY",
		TextColor3 = COLORS.accent,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		LayoutOrder = 100,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	for i, q in ipairs(data and data.weeklyQuests or {}) do
		makeQuestRow(questList, q, 110 + i)
	end
end

-- ============ Fishing mini-game overlay ============
local castOverlay = Instance.new("Frame")
castOverlay.Size = UDim2.new(0, 340, 0, 80)
castOverlay.Position = UDim2.new(0.5, -170, 0.55, -40)
castOverlay.BackgroundColor3 = COLORS.panel
castOverlay.BackgroundTransparency = 0.1
castOverlay.Visible = false
castOverlay.Parent = screenGui
corner(castOverlay, 12)

makeLabel(castOverlay, {
	Size = UDim2.new(1, -16, 0, 22),
	Position = UDim2.new(0, 8, 0, 6),
	Text = "CLICK / TAP TO HOOK!",
	TextColor3 = COLORS.warn,
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
})

local timingBar = Instance.new("Frame")
timingBar.Size = UDim2.new(1, -20, 0, 28)
timingBar.Position = UDim2.new(0, 10, 0, 36)
timingBar.BackgroundColor3 = Color3.fromRGB(45, 55, 70)
timingBar.Parent = castOverlay
corner(timingBar, 8)

local hitZoneFrame = Instance.new("Frame")
hitZoneFrame.Name = "HitZone"
hitZoneFrame.Size = UDim2.new(0.3, 0, 1, 0)
hitZoneFrame.Position = UDim2.new(0.35, 0, 0, 0)
hitZoneFrame.BackgroundColor3 = Color3.fromRGB(90, 200, 130)
hitZoneFrame.BackgroundTransparency = 0.35
hitZoneFrame.Parent = timingBar
corner(hitZoneFrame, 6)

local marker = Instance.new("Frame")
marker.Size = UDim2.new(0, 6, 1, -4)
marker.Position = UDim2.new(0, 0, 0, 2)
marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marker.Parent = timingBar
corner(marker, 3)

local markTween = nil

local function stopCastOverlay()
	castOverlay.Visible = false
	if markTween then
		markTween:Cancel()
		markTween = nil
	end
	if castInputConn then
		castInputConn:Disconnect()
		castInputConn = nil
	end
	if castTimeoutConn then
		castTimeoutConn:Disconnect()
		castTimeoutConn = nil
	end
end

-- ============ State rendering ============
local function toHex(color)
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function render()
	if not state then
		return
	end
	cashLabel.Text = "$" .. state.cash
	incomeLabel.Text = string.format("+$%.1f/sec", state.incomePerSec)
	storeButton.Text = string.format("STORE (%d/%d)", state.carried, state.maxCarried)

	if casting then
		fishButton.Text = "CASTING..."
		fishButton.BackgroundColor3 = Color3.fromRGB(120, 130, 140)
	else
		fishButton.Text = "FISH (F)"
		fishButton.BackgroundColor3 = COLORS.good
	end

	boatButton.Text = state.hasBoat and "BOAT (active)" or "BOAT (B)"

	local rodName = GameConfig.Rods[state.rodLevel].name
	local baitName = GameConfig.Baits[state.baitLevel].name
	aquariumStats.Text = string.format(
		"Fish stored: %d / %d\nIncome: $%.1f / sec\nGear: %s + %s\nUpgrades: Cap %d / Lock %d / Alarm %d",
		state.liveWellCount, state.capacity, state.incomePerSec, rodName, baitName,
		state.capacityLevel or 0, state.lockLevel or 0, state.alarmLevel or 0
	)

	local lines = {}
	for i, rarity in ipairs(GameConfig.Rarities) do
		local count = state.liveWellCounts[i] or state.liveWellCounts[tostring(i)] or 0
		table.insert(lines, string.format(
			'<font color="%s">%s</font>: %d fish ($%d each, +$%.1f/s)',
			toHex(rarity.color), rarity.name, count, rarity.value, rarity.incomePerSec
		))
	end
	rarityList.Text = table.concat(lines, "\n")

	if state.lockRemaining > 0 then
		lockButton.Text = string.format("LOCKED %ds", math.ceil(state.lockRemaining))
		lockButton.BackgroundColor3 = COLORS.bad
	elseif state.lockCooldownRemaining > 0 then
		lockButton.Text = string.format("RECHARGE %ds", math.ceil(state.lockCooldownRemaining))
		lockButton.BackgroundColor3 = Color3.fromRGB(100, 110, 120)
	else
		local lockDur = GameConfig.Aquarium.lockDuration
		if state.lockLevel and state.lockLevel > 0 and GameConfig.Upgrades.Lock[state.lockLevel] then
			lockDur = GameConfig.Upgrades.Lock[state.lockLevel].lockDuration
		end
		lockButton.Text = string.format("LOCK (%ds)", lockDur)
		lockButton.BackgroundColor3 = COLORS.warn
	end

	-- Stun effect
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if state.stunRemaining and state.stunRemaining > 0 then
				humanoid.WalkSpeed = 8
			else
				humanoid.WalkSpeed = 16
			end
		end
	end
end

-- ============ Actions ============
local function doFish()
	if not casting then
		Remotes.Cast:FireServer()
	end
end

fishButton.Activated:Connect(doFish)
storeButton.Activated:Connect(function()
	Remotes.StoreFish:InvokeServer()
end)
aquariumButton.Activated:Connect(function()
	aquariumPanel.Visible = not aquariumPanel.Visible
	shopPanel.Visible = false
	questPanel.Visible = false
end)
aquariumClose.Activated:Connect(function()
	aquariumPanel.Visible = false
end)
shopClose.Activated:Connect(function()
	shopPanel.Visible = false
end)
sellButton.Activated:Connect(function()
	Remotes.SellAll:InvokeServer()
end)
lockButton.Activated:Connect(function()
	Remotes.LockAquarium:InvokeServer()
end)
questClose.Activated:Connect(function()
	questPanel.Visible = false
end)
questButton.Activated:Connect(function()
	questPanel.Visible = not questPanel.Visible
	aquariumPanel.Visible = false
	shopPanel.Visible = false
	if questPanel.Visible and not questData then
		Remotes.OpenQuests:FireServer()
	end
end)
boatButton.Activated:Connect(function()
	local result = Remotes.SpawnBoat:InvokeServer()
	if not result then return end
	if not result.ok then
		local reasons = {
			already_has_boat = "You already have a boat out!",
			no_dock = "Boat dock is missing.",
			no_spawn_point = "Boat spawn point unavailable.",
			no_character = "Spawn your character first.",
		}
		showNotification(reasons[result.reason] or "Could not spawn boat.", COLORS.bad)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		doFish()
	elseif input.KeyCode == Enum.KeyCode.Q then
		questPanel.Visible = not questPanel.Visible
		aquariumPanel.Visible = false
		shopPanel.Visible = false
		if questPanel.Visible and not questData then
			Remotes.OpenQuests:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.B then
		Remotes.SpawnBoat:InvokeServer()
	end
end)

-- ============ Remote listeners ============
Remotes.StateChanged.OnClientEvent:Connect(function(snapshot)
	state = snapshot
	render()
	refreshShop()
end)

Remotes.Notify.OnClientEvent:Connect(showNotification)

Remotes.CastState.OnClientEvent:Connect(function(isCasting, castTime, hitZone)
	casting = isCasting
	if isCasting then
		if hitZone then
			castHitZone.start_ = hitZone.hitZoneStart or 0.35
			castHitZone.finish = hitZone.hitZoneEnd or 0.65
		else
			castHitZone.start_ = 0.35
			castHitZone.finish = 0.65
		end
		local zoneWidth = castHitZone.finish - castHitZone.start_
		hitZoneFrame.Size = UDim2.new(zoneWidth, 0, 1, 0)
		hitZoneFrame.Position = UDim2.new(castHitZone.start_, 0, 0, 0)

		castOverlay.Visible = true
		marker.Position = UDim2.new(0, 0, 0, 2)

		local duration = castTime or 4
		castDeadline = tick() + duration

		markTween = TweenService:Create(marker, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = UDim2.new(1, -6, 0, 2) })
		markTween:Play()

		castInputConn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not casting then return end
				local elapsed = tick() - (castDeadline - duration)
				local accuracy = math.clamp(elapsed / duration, 0, 1)
				stopCastOverlay()
				Remotes.CastResult:FireServer(accuracy)
			end
		end)

		castTimeoutConn = nil
	else
		stopCastOverlay()
	end
	render()
end)

Remotes.OpenAquarium.OnClientEvent:Connect(function()
	aquariumPanel.Visible = true
	shopPanel.Visible = false
	questPanel.Visible = false
end)

Remotes.OpenShop.OnClientEvent:Connect(function()
	shopPanel.Visible = true
	aquariumPanel.Visible = false
	questPanel.Visible = false
end)

Remotes.QuestProgressChanged.OnClientEvent:Connect(function(data)
	questData = data
	if questPanel.Visible then
		renderQuestPanel(data)
	end
end)

task.spawn(function()
	local snapshot = Remotes.GetState:InvokeServer()
	if snapshot and not state then
		state = snapshot
		render()
		refreshShop()
	end
end)
