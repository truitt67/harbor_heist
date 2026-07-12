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

local COLORS = {
	panel = Color3.fromRGB(25, 40, 55),
	panelLight = Color3.fromRGB(40, 60, 80),
	accent = Color3.fromRGB(80, 180, 255),
	good = Color3.fromRGB(90, 220, 120),
	bad = Color3.fromRGB(255, 100, 100),
	warn = Color3.fromRGB(255, 190, 80),
	text = Color3.fromRGB(240, 245, 250),
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
actionBar.Size = UDim2.new(0, 460, 0, 64)
actionBar.Position = UDim2.new(0.5, -230, 1, -84)
actionBar.BackgroundTransparency = 1
actionBar.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.Parent = actionBar

local fishButton = makeButton(actionBar, {
	Size = UDim2.new(0, 150, 1, 0),
	Text = "FISH (F)",
	BackgroundColor3 = COLORS.good,
})

local storeButton = makeButton(actionBar, {
	Size = UDim2.new(0, 150, 1, 0),
	Text = "STORE (0)",
	BackgroundColor3 = COLORS.accent,
})

local aquariumButton = makeButton(actionBar, {
	Size = UDim2.new(0, 150, 1, 0),
	Text = "AQUARIUM",
	BackgroundColor3 = Color3.fromRGB(180, 140, 255),
})

-- ============ Notifications ============
local notifyFrame = Instance.new("Frame")
notifyFrame.Size = UDim2.new(0, 420, 0, 260)
notifyFrame.Position = UDim2.new(0.5, -210, 0, 20)
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
		local tween = TweenService:Create(note, TweenInfo.new(0.5), { BackgroundTransparency = 1, TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		note:Destroy()
	end)
end

-- ============ Aquarium panel ============
local aquariumPanel = Instance.new("Frame")
aquariumPanel.Size = UDim2.new(0, 340, 0, 330)
aquariumPanel.Position = UDim2.new(0.5, -170, 0.5, -165)
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
	Size = UDim2.new(1, -28, 0, 56),
	Position = UDim2.new(0, 14, 0, 48),
	Text = "",
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextScaled = false,
	TextSize = 18,
})

local rarityList = makeLabel(aquariumPanel, {
	Size = UDim2.new(1, -28, 0, 110),
	Position = UDim2.new(0, 14, 0, 106),
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
	Text = "LOCK (60s)",
	BackgroundColor3 = COLORS.warn,
})

-- ============ Shop panel ============
local shopPanel = Instance.new("Frame")
shopPanel.Size = UDim2.new(0, 380, 0, 420)
shopPanel.Position = UDim2.new(0.5, -190, 0.5, -210)
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

local function buildShopRow(kind, level, item, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 64)
	row.BackgroundColor3 = COLORS.panelLight
	row.LayoutOrder = order
	row.Parent = shopList
	corner(row, 10)

	makeLabel(row, {
		Size = UDim2.new(0.62, -10, 0.5, 0),
		Position = UDim2.new(0, 10, 0, 4),
		Text = item.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 18,
	})

	makeLabel(row, {
		Size = UDim2.new(0.62, -10, 0.4, 0),
		Position = UDim2.new(0, 10, 0.52, 0),
		Text = item.desc .. " (+" .. item.luck .. " luck)",
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = false,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(180, 200, 220),
	})

	local buyButton = makeButton(row, {
		Size = UDim2.new(0.32, 0, 0, 40),
		Position = UDim2.new(0.66, 0, 0.5, -20),
		Text = "$" .. item.cost,
	})

	buyButton.Activated:Connect(function()
		local result = Remotes.BuyItem:InvokeServer(kind, level)
		if result and result.ok then
			refreshShop()
		end
	end)

	shopRows[kind .. level] = { row = row, buyButton = buyButton, level = level, kind = kind, item = item }
end

function refreshShop()
	if not state then
		return
	end
	for _, entry in pairs(shopRows) do
		local currentLevel = entry.kind == "rod" and state.rodLevel or state.baitLevel
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

for level, rod in ipairs(GameConfig.Rods) do
	buildShopRow("rod", level, rod, level)
end
for level, bait in ipairs(GameConfig.Baits) do
	buildShopRow("bait", level, bait, 10 + level)
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

	local rodName = GameConfig.Rods[state.rodLevel].name
	local baitName = GameConfig.Baits[state.baitLevel].name
	aquariumStats.Text = string.format(
		"Fish stored: %d / %d\nIncome: $%.1f per second\nGear: %s + %s",
		state.liveWellCount, state.capacity, state.incomePerSec, rodName, baitName
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
		lockButton.Text = string.format("LOCK (%ds)", GameConfig.Aquarium.lockDuration)
		lockButton.BackgroundColor3 = COLORS.warn
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		doFish()
	end
end)

-- ============ Remote listeners ============
Remotes.StateChanged.OnClientEvent:Connect(function(snapshot)
	state = snapshot
	render()
	refreshShop()
end)

Remotes.Notify.OnClientEvent:Connect(showNotification)

Remotes.CastState.OnClientEvent:Connect(function(isCasting)
	casting = isCasting
	render()
end)

Remotes.OpenAquarium.OnClientEvent:Connect(function()
	aquariumPanel.Visible = true
	shopPanel.Visible = false
end)

Remotes.OpenShop.OnClientEvent:Connect(function()
	shopPanel.Visible = true
	aquariumPanel.Visible = false
end)

task.spawn(function()
	local snapshot = Remotes.GetState:InvokeServer()
	if snapshot and not state then
		state = snapshot
		render()
		refreshShop()
	end
end)
