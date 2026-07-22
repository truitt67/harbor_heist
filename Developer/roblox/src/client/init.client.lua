local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
-- TASK 4.4 (0cw.4 / wqw.18): species DisplayName lookup for the inventory panel
local FishDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FishDefinitions"))
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local Remotes = {}
for _, child in ipairs(remotesFolder:GetChildren()) do
	Remotes[child.Name] = child
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- Device profile: hyper-optimize layout per modality.
-- ============================================================
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ============================================================
-- Design system
-- ============================================================
local UI = {
	bg = Color3.fromRGB(13, 20, 31),
	surface = Color3.fromRGB(20, 30, 46),
	surfaceHi = Color3.fromRGB(30, 43, 63),
	stroke = Color3.fromRGB(255, 255, 255),
	accent = Color3.fromRGB(56, 152, 255),
	accentSoft = Color3.fromRGB(120, 190, 255),
	good = Color3.fromRGB(52, 199, 123),
	bad = Color3.fromRGB(255, 92, 92),
	warn = Color3.fromRGB(255, 184, 64),
	quest = Color3.fromRGB(255, 205, 92),
	boat = Color3.fromRGB(94, 200, 235),
	purple = Color3.fromRGB(167, 139, 250),
	text = Color3.fromRGB(238, 243, 250),
	textDim = Color3.fromRGB(148, 163, 184),
	textFaint = Color3.fromRGB(100, 116, 139),
	ink = Color3.fromRGB(10, 16, 26),
}

local FONT_HEAD = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold
local FONT_MED = Enum.Font.GothamMedium
local FONT_BODY = Enum.Font.Gotham

local EASE_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EASE_POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EASE_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local state = nil
local casting = false
local castHitZone = { perfectStart_ = 0.35, perfectEnd_ = 0.65, goodStart_ = 0.15, goodEnd_ = 0.85 }
local castDeadline = 0
local castInputConn = nil
local questData = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HarborHeistUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local inset = GuiService:GetGuiInset()
local SAFE_TOP = math.max(inset.Y, IS_MOBILE and 12 or 8)

-- ============================================================
-- Primitive helpers
-- ============================================================
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

local function stroke(parent, transparency, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or UI.stroke
	s.Transparency = transparency or 0.88
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function padding(parent, all)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft = UDim.new(0, all)
	p.PaddingRight = UDim.new(0, all)
	p.Parent = parent
	return p
end

local function vGradient(parent, topColor, bottomColor)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(topColor, bottomColor)
	g.Parent = parent
	return g
end

local function makeLabel(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = UI.text
	label.Font = FONT_BODY
	label.TextScaled = false
	label.TextSize = 15
	for key, value in pairs(props) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

local function pressFeedback(button)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, EASE_FAST, { Scale = 0.96 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, EASE_FAST, { Scale = 1 }):Play()
	end)
	if not IS_MOBILE then
		button.MouseEnter:Connect(function()
			TweenService:Create(scale, EASE_FAST, { Scale = 1.025 }):Play()
		end)
	end
end

local function makeButton(parent, props)
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = UI.accent
	button.TextColor3 = UI.ink
	button.Font = FONT_BOLD
	button.TextSize = IS_MOBILE and 16 or 15
	button.AutoButtonColor = false
	local cornerRadius = props.CornerRadius
	props.CornerRadius = nil
	for key, value in pairs(props) do
		button[key] = value
	end
	button.Parent = parent
	corner(button, cornerRadius or 12)
	pressFeedback(button)
	return button
end

local function formatCash(n)
	local s = tostring(math.floor(n + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return formatted
end

-- ============================================================
-- HUD: cash card (top-left) — glass card with animated counter
-- ============================================================
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Size = IS_MOBILE and UDim2.new(0, 178, 0, 64) or UDim2.new(0, 224, 0, 78)
hud.Position = UDim2.new(0, 14, 0, SAFE_TOP + 6)
hud.BackgroundColor3 = UI.bg
hud.BackgroundTransparency = 0.18
hud.Parent = screenGui
corner(hud, 16)
stroke(hud, 0.85)
vGradient(hud, Color3.fromRGB(24, 36, 54), UI.bg)

makeLabel(hud, {
	Size = UDim2.new(0, 76, 0, 12),
	Position = UDim2.new(0, 14, 0, IS_MOBILE and 6 or 8),
	Text = "BALANCE",
	Font = FONT_BOLD,
	TextSize = 9,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local cashLabel = makeLabel(hud, {
	Size = UDim2.new(1, -24, 0, IS_MOBILE and 28 or 34),
	Position = UDim2.new(0, 14, 0, IS_MOBILE and 14 or 17),
	Text = "$0",
	Font = FONT_HEAD,
	TextSize = IS_MOBILE and 24 or 30,
	TextColor3 = Color3.fromRGB(134, 239, 172),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local incomeLabel = makeLabel(hud, {
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.new(0, 14, 1, IS_MOBILE and -22 or -26),
	Text = "+$0.0 / sec",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 12 or 13,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- Animated cash counting
local displayedCash = 0
local cashTweenConn = nil
local lastCash = nil
local function animateCashTo(target)
	if lastCash and target > lastCash then
		local gain = makeLabel(hud, {
			Size = UDim2.new(0, 100, 0, 20),
			Position = UDim2.new(1, -110, 0, 8),
			Text = "+$" .. formatCash(target - lastCash),
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = UI.good,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 5,
		})
		TweenService:Create(gain, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -110, 0, -10),
			TextTransparency = 1,
		}):Play()
		task.delay(0.85, function()
			gain:Destroy()
		end)
	end
	lastCash = target
	if cashTweenConn then
		cashTweenConn:Disconnect()
		cashTweenConn = nil
	end
	local from = displayedCash
	if from == target then
		cashLabel.Text = "$" .. formatCash(target)
		return
	end
	local t0 = os.clock()
	local dur = 0.45
	cashTweenConn = game:GetService("RunService").RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / dur, 0, 1)
		a = 1 - (1 - a) ^ 3
		displayedCash = from + (target - from) * a
		cashLabel.Text = "$" .. formatCash(displayedCash)
		if a >= 1 then
			displayedCash = target
			cashTweenConn:Disconnect()
			cashTweenConn = nil
		end
	end)
end

-- Carried-fish pill under the cash card
local carryPill = Instance.new("Frame")
carryPill.Size = IS_MOBILE and UDim2.new(0, 178, 0, 30) or UDim2.new(0, 224, 0, 34)
carryPill.Position = UDim2.new(0, 14, 0, SAFE_TOP + (IS_MOBILE and 76 or 90))
carryPill.BackgroundColor3 = UI.bg
carryPill.BackgroundTransparency = 0.25
carryPill.Parent = screenGui
corner(carryPill, 999)
stroke(carryPill, 0.88)

local carryLabel = makeLabel(carryPill, {
	Size = UDim2.new(1, -20, 1, 0),
	Position = UDim2.new(0, 12, 0, 0),
	Text = "On line: 0 / 3 fish",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 12 or 13,
	TextColor3 = UI.accentSoft,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- ============================================================
-- Toast notifications (top-center, slide + fade, accent bar)
-- ============================================================
local toastHost = Instance.new("Frame")
toastHost.Name = "Toasts"
toastHost.AnchorPoint = Vector2.new(0.5, 0)
toastHost.Size = UDim2.new(0, IS_MOBILE and 320 or 400, 0, 300)
toastHost.Position = UDim2.new(0.5, 0, 0, SAFE_TOP + 8)
toastHost.BackgroundTransparency = 1
toastHost.ZIndex = 50
toastHost.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHost

local toastOrder = 0
local function showNotification(message, color)
	color = color or UI.accentSoft
	toastOrder += 1

	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, IS_MOBILE and 40 or 42)
	toast.BackgroundColor3 = UI.bg
	toast.BackgroundTransparency = 1
	toast.LayoutOrder = toastOrder
	toast.ZIndex = 51
	toast.Parent = toastHost
	corner(toast, 12)
	local tStroke = stroke(toast, 1)

	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 4, 1, -14)
	accentBar.Position = UDim2.new(0, 8, 0, 7)
	accentBar.BackgroundColor3 = color
	accentBar.BackgroundTransparency = 1
	accentBar.ZIndex = 52
	accentBar.Parent = toast
	corner(accentBar, 2)

	local text = makeLabel(toast, {
		Size = UDim2.new(1, -32, 1, 0),
		Position = UDim2.new(0, 22, 0, 0),
		Text = message,
		Font = FONT_MED,
		TextSize = IS_MOBILE and 13 or 14,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
	})

	TweenService:Create(toast, EASE_OUT, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(tStroke, EASE_OUT, { Transparency = 0.82 }):Play()
	TweenService:Create(accentBar, EASE_OUT, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(text, EASE_OUT, { TextTransparency = 0 }):Play()

	task.delay(3.6, function()
		if not toast.Parent then
			return
		end
		local fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(toast, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(tStroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(accentBar, fade, { BackgroundTransparency = 1 }):Play()
		local t = TweenService:Create(text, fade, { TextTransparency = 1 })
		t:Play()
		t.Completed:Wait()
		toast:Destroy()
	end)
end

-- ============================================================
-- Onboarding contextual prompts (TASK 9.2 / 0jc.2)
-- Dismissible inline banners driven by OnboardingService flags.
-- Shows one prompt at a time based on the player's progression stage.
-- Non-blocking, non-modal — sits just above the action bar.
-- ============================================================
local onboardingPrompt = Instance.new("Frame")
onboardingPrompt.Name = "OnboardingPrompt"
onboardingPrompt.AnchorPoint = Vector2.new(0.5, 1)
-- Mobile: position above the right-edge action bar stack (5 buttons × 70
-- = 350px tall, bottom at -90 → top at -440; +12px gap → -452).
-- Desktop: just above the bottom action bar (58px at -18 → top at -76;
-- +8px gap → -84).
onboardingPrompt.Position = UDim2.new(0.5, 0, 1, IS_MOBILE and -452 or -84)
onboardingPrompt.Size = UDim2.new(IS_MOBILE and 1 or 0, IS_MOBILE and -24 or 360, 0, IS_MOBILE and 48 or 40)
onboardingPrompt.BackgroundColor3 = UI.surface
onboardingPrompt.BackgroundTransparency = 0.1
onboardingPrompt.Visible = false
onboardingPrompt.ZIndex = 15
onboardingPrompt.Parent = screenGui
corner(onboardingPrompt, 12)
stroke(onboardingPrompt, 0.7, UI.accent, 1.5)

local onboardingAccentBar = Instance.new("Frame")
onboardingAccentBar.Size = UDim2.new(0, 4, 1, -14)
onboardingAccentBar.Position = UDim2.new(0, 8, 0, 7)
onboardingAccentBar.BackgroundColor3 = UI.accent
onboardingAccentBar.ZIndex = 16
onboardingAccentBar.Parent = onboardingPrompt
corner(onboardingAccentBar, 2)

local onboardingLabel = makeLabel(onboardingPrompt, {
	Size = UDim2.new(1, -52, 1, 0),
	Position = UDim2.new(0, 20, 0, 0),
	Text = "",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 14 or 13,
	TextColor3 = UI.text,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 16,
})

local onboardingDismiss = makeButton(onboardingPrompt, {
	Size = UDim2.new(0, 24, 0, 24),
	Position = UDim2.new(1, -30, 0.5, -12),
	Text = "✕",
	TextSize = 12,
	BackgroundColor3 = UI.surfaceHi,
	TextColor3 = UI.textDim,
	CornerRadius = 999,
	ZIndex = 16,
})

-- Track dismissed prompts so they don't reappear in the same session.
-- Keyed by onboarding stage so each stage shows once, then hides until
-- the next stage's flag check triggers a new prompt.
local dismissedPrompts = {}
-- The stage currently shown in the prompt widget, or nil when hidden.
-- Set by showOnboardingPrompt, cleared by dismiss/hide. The dismiss
-- button uses this to mark the right stage as dismissed.
local currentPromptStage = nil

onboardingDismiss.Activated:Connect(function()
	if currentPromptStage then
		dismissedPrompts[currentPromptStage] = true
	end
	currentPromptStage = nil
	onboardingPrompt.Visible = false
end)

-- Show a contextual prompt for the given stage, unless already dismissed.
-- @param stage string — unique key for this prompt stage
-- @param text string — prompt text
-- @param color Color3 — accent bar color
local function showOnboardingPrompt(stage, text, color)
	if dismissedPrompts[stage] then
		return
	end
	currentPromptStage = stage
	onboardingLabel.Text = text
	onboardingAccentBar.BackgroundColor3 = color or UI.accent
	if not onboardingPrompt.Visible then
		onboardingPrompt.Visible = true
		local scale = onboardingPrompt:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = onboardingPrompt
		scale.Scale = 0.92
		TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
	end
end

-- Hide the onboarding prompt and mark the stage as dismissed.
local function dismissOnboardingPrompt(stage)
	dismissedPrompts[stage] = true
	currentPromptStage = nil
	onboardingPrompt.Visible = false
end

-- ============================================================
-- Modal framework: dim backdrop + animated panel (desktop card /
-- mobile bottom sheet)
-- ============================================================
local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 1
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.Visible = false
backdrop.ZIndex = 20
backdrop.Parent = screenGui

local activePanel = nil

local function makePanel(title, titleColor, desktopSize)
	local panel = Instance.new("Frame")
	panel.Name = title
	panel.BackgroundColor3 = UI.bg
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.ZIndex = 25
	if IS_MOBILE then
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.new(0.5, 0, 1, 0)
		panel.Size = UDim2.new(1, -12, 0.78, 0)
	else
		panel.AnchorPoint = Vector2.new(0.5, 0.5)
		panel.Position = UDim2.new(0.5, 0, 0.5, 0)
		panel.Size = desktopSize
	end
	panel.Parent = screenGui
	corner(panel, IS_MOBILE and 20 or 16)
	stroke(panel, 0.82)
	vGradient(panel, Color3.fromRGB(26, 38, 57), UI.bg)

	if IS_MOBILE then
		local grabber = Instance.new("Frame")
		grabber.Size = UDim2.new(0, 44, 0, 4)
		grabber.AnchorPoint = Vector2.new(0.5, 0)
		grabber.Position = UDim2.new(0.5, 0, 0, 8)
		grabber.BackgroundColor3 = UI.textFaint
		grabber.BackgroundTransparency = 0.4
		grabber.ZIndex = 26
		grabber.Parent = panel
		corner(grabber, 2)
	end

	local headerY = IS_MOBILE and 20 or 14
	makeLabel(panel, {
		Size = UDim2.new(1, -80, 0, 30),
		Position = UDim2.new(0, 18, 0, headerY),
		Text = title,
		Font = FONT_HEAD,
		TextSize = IS_MOBILE and 18 or 20,
		TextColor3 = titleColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})

	local close = makeButton(panel, {
		Size = UDim2.new(0, IS_MOBILE and 40 or 32, 0, IS_MOBILE and 40 or 32),
		Position = UDim2.new(1, IS_MOBILE and -52 or -44, 0, headerY - (IS_MOBILE and 6 or 2)),
		Text = "✕",
		TextSize = IS_MOBILE and 18 or 15,
		BackgroundColor3 = UI.surfaceHi,
		TextColor3 = UI.textDim,
		ZIndex = 26,
		CornerRadius = 999,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -32, 1, -(headerY + 44 + (IS_MOBILE and 12 or 4)))
	content.Position = UDim2.new(0, 16, 0, headerY + 40)
	content.ZIndex = 26
	content.Parent = panel

	return panel, content, close
end

local function hidePanels()
	if activePanel then
		local panel = activePanel
		activePanel = nil
		if IS_MOBILE then
			local slide = TweenService:Create(panel, EASE_OUT, { Position = UDim2.new(0.5, 0, 1.35, 0) })
			slide:Play()
			slide.Completed:Once(function()
				panel.Visible = false
			end)
		else
			panel.Visible = false
		end
	end
	TweenService:Create(backdrop, EASE_OUT, { BackgroundTransparency = 1 }):Play()
	task.delay(0.24, function()
		if not activePanel then
			backdrop.Visible = false
		end
	end)
end

local function showPanel(panel)
	if activePanel == panel then
		hidePanels()
		return
	end
	if activePanel then
		activePanel.Visible = false
	end
	activePanel = panel
	backdrop.Visible = true
	TweenService:Create(backdrop, EASE_OUT, { BackgroundTransparency = 0.45 }):Play()
	panel.Visible = true
	if IS_MOBILE then
		panel.Position = UDim2.new(0.5, 0, 1.35, 0)
		TweenService:Create(panel, EASE_POP, { Position = UDim2.new(0.5, 0, 1, 0) }):Play()
	else
		local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = panel
		scale.Scale = 0.92
		panel.BackgroundTransparency = 0.3
		TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
		TweenService:Create(panel, EASE_OUT, { BackgroundTransparency = 0.04 }):Play()
	end
end

backdrop.Activated:Connect(hidePanels)

-- ============================================================
-- Aquarium panel
-- ============================================================
local aquariumPanel, aquariumContent, aquariumClose = makePanel("MY AQUARIUM", UI.purple, UDim2.new(0, 360, 0, 464))

local aquariumStats = makeLabel(aquariumContent, {
	Size = UDim2.new(1, 0, 0, 66),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 15 or 14,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
	ZIndex = 26,
})

local capacityBar = Instance.new("Frame")
capacityBar.Size = UDim2.new(1, 0, 0, 10)
capacityBar.Position = UDim2.new(0, 0, 0, 68)
capacityBar.BackgroundColor3 = UI.surfaceHi
capacityBar.ZIndex = 26
capacityBar.Parent = aquariumContent
corner(capacityBar, 5)
stroke(capacityBar, 0.9)

local capacityFill = Instance.new("Frame")
capacityFill.Size = UDim2.new(0, 0, 1, 0)
capacityFill.BackgroundColor3 = UI.purple
capacityFill.ZIndex = 27
capacityFill.Parent = capacityBar
corner(capacityFill, 5)
vGradient(capacityFill, Color3.fromRGB(196, 181, 253), UI.purple)

-- TASK 5.1: claim accumulated aquarium income
local claimButton = makeButton(aquariumPanel, {
	Size = UDim2.new(1, -16, 0, 34),
	Position = UDim2.new(0, 8, 1, -122),
	Text = "CLAIM $0",
	BackgroundColor3 = Color3.fromRGB(60, 70, 80),
})

makeLabel(aquariumContent, {
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.new(0, 0, 0, 88),
	Text = "LIVE-WELL BREAKDOWN",
	Font = FONT_BOLD,
	TextSize = 10,
	TextColor3 = UI.textFaint,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local rarityList = makeLabel(aquariumContent, {
	Size = UDim2.new(1, 0, 1, -214),
	Position = UDim2.new(0, 0, 0, 110),
	Text = "",
	Font = FONT_BODY,
	TextSize = IS_MOBILE and 15 or 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
	ZIndex = 26,
})

local buttonH = IS_MOBILE and 52 or 46
local sellButton = makeButton(aquariumContent, {
	Size = UDim2.new(0.5, -6, 0, buttonH),
	Position = UDim2.new(0, 0, 1, -buttonH - 4),
	Text = "SELL ALL",
	BackgroundColor3 = UI.good,
	ZIndex = 26,
})

local lockButton = makeButton(aquariumContent, {
	Size = UDim2.new(0.5, -6, 0, buttonH),
	Position = UDim2.new(0.5, 6, 1, -buttonH - 4),
	Text = "LOCK",
	BackgroundColor3 = UI.warn,
	ZIndex = 26,
})

-- TASK 8.2/8.3: Raid opt-in toggle (server validates new-player gate)
local raidOptInButton = makeButton(aquariumContent, {
	Size = UDim2.new(1, 0, 0, 32),
	Position = UDim2.new(0, 0, 1, -buttonH - 40),
	Text = "RAID OPT-IN: OFF",
	BackgroundColor3 = UI.surfaceHi,
	ZIndex = 26,
})

-- ============================================================
-- Inventory panel (TASK 4.4 / wqw.18): per-fish SELL + STORE management.
-- Lists every carried fish from the snapshot's carriedFish array; each row
-- shows species/rarity/value with per-fish SELL (SellFish) and STORE
-- (StoreSingleFish) buttons, plus a bulk STORE ALL shortcut.
-- NOTE: no SELL ALL here — the server's SellAll liquidates the AQUARIUM
-- (stored fish) as well as carried fish, which would be dangerously
-- misleading in a panel scoped to the carried bag. Bulk sell lives in
-- the aquarium panel, where that behavior matches player expectations.
-- ============================================================
local inventoryPanel, inventoryContent, inventoryClose = makePanel("FISH BAG", UI.accent, UDim2.new(0, 420, 0, 500))

local inventoryStats = makeLabel(inventoryContent, {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 14 or 13,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Size = UDim2.new(1, 0, 1, -(IS_MOBILE and 82 or 76))
inventoryList.Position = UDim2.new(0, 0, 0, 24)
inventoryList.BackgroundTransparency = 1
inventoryList.ScrollBarThickness = 4
inventoryList.ScrollBarImageColor3 = UI.textFaint
inventoryList.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryList.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryList.ZIndex = 26
inventoryList.Parent = inventoryContent

local inventoryLayout = Instance.new("UIListLayout")
inventoryLayout.Padding = UDim.new(0, 8)
inventoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
inventoryLayout.Parent = inventoryList

local RARITY_COLORS = {}
for _, rarity in ipairs(GameConfig.Rarities) do
	RARITY_COLORS[rarity.name] = rarity.color
end

-- Failure reasons the server already notifies about (avoid duplicate toasts).
-- The server stays silent on rate_limited, no_session, bad_id,
-- fish_not_found, invalid_fish — those need a client-side toast.
local SERVER_NOTIFIED_REASONS = {
	aquarium_full = true,
	aquarium_locked = true,
	raid_protected = true,
}

local function fishDisplayName(fish)
	local ok, def = pcall(FishDefinitions.get, fish.SpeciesId)
	return (ok and def and def.DisplayName) or fish.SpeciesId or "Fish"
end

local function clearInventoryList()
	for _, child in ipairs(inventoryList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- Rebuild guard: state pushes arrive every second while income accrues.
-- Rebuilding the row instances on every push would destroy buttons mid-tap
-- (eaten clicks on mobile), so only rebuild when the carried contents or
-- carry limit actually change.
local lastInventorySignature = nil

local function renderInventory()
	if not state then
		return
	end
	local carried = state.carriedFish or {}
	local signatureParts = { tostring(state.maxCarried or 0) }
	for _, fish in ipairs(carried) do
		table.insert(signatureParts, tostring(fish.InstanceId))
	end
	local signature = table.concat(signatureParts, "|")
	if signature == lastInventorySignature then
		return
	end
	lastInventorySignature = signature
	clearInventoryList()
	local totalValue = 0
	for _, fish in ipairs(carried) do
		totalValue += fish.BaseSellValue or 0
	end
	inventoryStats.Text = string.format("%d / %d fish  •  total value $%s", #carried, state.maxCarried or 0, formatCash(totalValue))

	if #carried == 0 then
		makeLabel(inventoryList, {
			Size = UDim2.new(1, 0, 0, 44),
			Text = "No fish on the line — go catch some!",
			Font = FONT_BODY,
			TextSize = 14,
			TextColor3 = UI.textFaint,
			LayoutOrder = 1,
			ZIndex = 26,
		})
		return
	end

	local actionH = IS_MOBILE and 44 or 38
	local rowH = IS_MOBILE and 66 or 58
	for i, fish in ipairs(carried) do
		local rarityColor = RARITY_COLORS[fish.Rarity] or UI.textDim
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, rowH)
		row.BackgroundColor3 = UI.surface
		row.BackgroundTransparency = 0.15
		row.LayoutOrder = i
		row.ZIndex = 26
		row.Parent = inventoryList
		corner(row, 12)
		stroke(row, 0.9)

		local tag = Instance.new("Frame")
		tag.Size = UDim2.new(0, 74, 0, 18)
		tag.Position = UDim2.new(0, 10, 0, 7)
		tag.BackgroundColor3 = rarityColor
		tag.BackgroundTransparency = 0.78
		tag.ZIndex = 27
		tag.Parent = row
		corner(tag, 5)
		makeLabel(tag, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = string.upper(fish.Rarity or "?"),
			Font = FONT_BOLD,
			TextSize = 10,
			TextColor3 = rarityColor,
			ZIndex = 28,
		})

		makeLabel(row, {
			-- Width ends just before the SELL button (starts at 0.54) so long
			-- species names truncate cleanly instead of sliding under it.
			Size = UDim2.new(0.54, -100, 0, 20),
			Position = UDim2.new(0, 90, 0, 6),
			Text = fishDisplayName(fish),
			Font = FONT_BOLD,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 27,
		})

		makeLabel(row, {
			Size = UDim2.new(0.52, -20, 0, 18),
			Position = UDim2.new(0, 10, 0, rowH - 24),
			Text = string.format("$%d sell  •  $%.1f/min stored", fish.BaseSellValue or 0, fish.IncomePerMinute or 0),
			Font = FONT_BODY,
			TextSize = 12,
			TextColor3 = UI.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 27,
		})

		local sellBtn = makeButton(row, {
			Size = UDim2.new(0.22, -4, 0, actionH),
			Position = UDim2.new(0.54, 0, 0.5, -actionH / 2),
			Text = "SELL",
			TextSize = IS_MOBILE and 14 or 13,
			BackgroundColor3 = UI.good,
			ZIndex = 27,
		})
		local storeBtn = makeButton(row, {
			Size = UDim2.new(0.24, 0, 0, actionH),
			Position = UDim2.new(0.76, 0, 0.5, -actionH / 2),
			Text = "STORE",
			TextSize = IS_MOBILE and 14 or 13,
			BackgroundColor3 = UI.accent,
			ZIndex = 27,
		})

		sellBtn.Activated:Connect(function()
			local result = Remotes.SellFish:InvokeServer(fish.InstanceId)
			if result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
				showNotification("Could not sell: " .. tostring(result.reason), UI.bad)
			end
		end)
		storeBtn.Activated:Connect(function()
			local result = Remotes.StoreSingleFish:InvokeServer(fish.InstanceId)
			if result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
				showNotification("Could not store: " .. tostring(result.reason), UI.bad)
			end
		end)
	end
end

local invBulkH = IS_MOBILE and 46 or 40
local invStoreAllBtn = makeButton(inventoryContent, {
	Size = UDim2.new(1, 0, 0, invBulkH),
	Position = UDim2.new(0, 0, 1, -invBulkH),
	Text = "STORE ALL",
	BackgroundColor3 = UI.accent,
	ZIndex = 26,
})
invStoreAllBtn.Activated:Connect(function()
	Remotes.StoreFish:InvokeServer()
end)

local function toggleInventoryPanel()
	if activePanel == inventoryPanel then
		hidePanels()
		return
	end
	showPanel(inventoryPanel)
	renderInventory()
end

-- ============================================================
-- Shop panel
-- ============================================================
local shopPanel, shopContent, shopClose = makePanel("BAIT & TACKLE", UI.warn, UDim2.new(0, 420, 0, 520))

local shopList = Instance.new("ScrollingFrame")
shopList.Size = UDim2.new(1, 0, 1, 0)
shopList.BackgroundTransparency = 1
shopList.ScrollBarThickness = 4
shopList.ScrollBarImageColor3 = UI.textFaint
shopList.CanvasSize = UDim2.new(0, 0, 0, 0)
shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
shopList.ZIndex = 26
shopList.Parent = shopContent

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
-- N10: the capacity shop must use the SAME catalog the server sells from
-- (AquariumUpgradeTiers) and the SAME kind string the server dispatches on
-- ("aquarium"). Previously this used GameConfig.Upgrades.Capacity with kind
-- "capacity", but the BuyItem handler rejects "capacity" (bad_kind) — so
-- every capacity purchase silently failed, and the displayed prices/tiers
-- didn't match what the server would have charged.
addCatalog("aquarium", GameConfig.AquariumUpgradeTiers, 20)
addCatalog("lock", GameConfig.Upgrades.Lock, 30)
addCatalog("alarm", GameConfig.Upgrades.Alarm, 40)
-- N17 (TASK 17.4): the dock upgrade track. Uses GameConfig.DockUpgradeTiers
-- (the SAME table the server sells from in ShopService kind="dock") and the
-- kind string the server dispatches on. Order base 50 so dock rows sort last.
addCatalog("dock", GameConfig.DockUpgradeTiers, 50)
table.sort(SHOP_CATALOG, function(a, b)
	return a.order < b.order
end)

local KIND_META = {
	rod = { tag = "ROD", color = UI.accent },
	bait = { tag = "BAIT", color = UI.good },
	aquarium = { tag = "TANK", color = UI.purple },
	lock = { tag = "LOCK", color = UI.warn },
	alarm = { tag = "ALARM", color = UI.bad },
	dock = { tag = "DOCK", color = UI.boat },
}

local function itemDisplayName(entry)
	return entry.item.name or entry.item.desc or entry.kind
end

local function itemSubText(entry)
	local it = entry.item
	if entry.kind == "rod" or entry.kind == "bait" then
		return (it.desc or "") .. "  •  +" .. (it.luck or 0) .. " luck"
	elseif entry.kind == "aquarium" then
		-- AquariumUpgradeTiers use `capacity` + `incomeMultiplier`.
		return "Holds " .. (it.capacity or 0) .. " fish  •  +" .. math.floor(((it.incomeMultiplier or 1) - 1) * 100 + 0.5) .. "% income"
	elseif entry.kind == "lock" then
		return "Lock " .. (it.lockDuration or 0) .. "s • recharge " .. (it.lockCooldown or 0) .. "s"
	elseif entry.kind == "alarm" then
		return "Stuns thieves " .. (it.stunDuration or 0) .. "s"
	elseif entry.kind == "dock" then
		-- DockUpgradeTiers use `incomeMultiplier` + `cosmeticUnlocks`.
		local mult = "+" .. math.floor(((it.incomeMultiplier or 1) - 1) * 100 + 0.5) .. "% income"
		if it.cosmeticUnlocks and #it.cosmeticUnlocks > 0 then
			return mult .. "  •  " .. table.concat(it.cosmeticUnlocks, ", ")
		end
		return mult
	end
	return it.desc or ""
end

local refreshShop

local function buildShopRow(entry)
	local rowH = IS_MOBILE and 74 or 66
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, rowH)
	row.BackgroundColor3 = UI.surface
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = entry.order
	row.ZIndex = 26
	row.Parent = shopList
	corner(row, 12)
	stroke(row, 0.9)

	local meta = KIND_META[entry.kind]
	local tag = Instance.new("Frame")
	tag.Size = UDim2.new(0, 46, 0, 18)
	tag.Position = UDim2.new(0, 10, 0, 8)
	tag.BackgroundColor3 = meta.color
	tag.BackgroundTransparency = 0.75
	tag.ZIndex = 27
	tag.Parent = row
	corner(tag, 5)
	makeLabel(tag, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = meta.tag,
		Font = FONT_BOLD,
		TextSize = 10,
		TextColor3 = meta.color,
		ZIndex = 28,
	})

	makeLabel(row, {
		Size = UDim2.new(0.62, -70, 0, 20),
		Position = UDim2.new(0, 62, 0, 7),
		Text = itemDisplayName(entry),
		Font = FONT_BOLD,
		TextSize = IS_MOBILE and 15 or 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})

	makeLabel(row, {
		Size = UDim2.new(0.64, -20, 0, 30),
		Position = UDim2.new(0, 10, 0, 30),
		Text = itemSubText(entry),
		Font = FONT_BODY,
		TextSize = IS_MOBILE and 12 or 12,
		TextColor3 = UI.textDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 27,
	})

	local buyH = IS_MOBILE and 44 or 38
	local buyButton = makeButton(row, {
		Size = UDim2.new(0.3, 0, 0, buyH),
		Position = UDim2.new(0.68, 0, 0.5, -buyH / 2),
		Text = "$" .. formatCash(entry.item.cost or 0),
		TextSize = IS_MOBILE and 15 or 14,
		ZIndex = 27,
	})

	buyButton.Activated:Connect(function()
		if not buyButton.Active then
			return
		end
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
		if entry.kind == "rod" then
			currentLevel = state.rodLevel
		elseif entry.kind == "bait" then
			currentLevel = state.baitLevel
		elseif entry.kind == "aquarium" then
			-- N9: capacity tier maps to Aquarium.UpgradeLevel. The state field
			-- is upgradeLevel (1-4). The shop catalog is 1-indexed per tier,
			-- so level N in the catalog == upgradeLevel N.
			currentLevel = state.upgradeLevel or 1
		elseif entry.kind == "lock" then
			currentLevel = state.lockLevel or 0
		elseif entry.kind == "alarm" then
			currentLevel = state.alarmLevel or 0
		elseif entry.kind == "dock" then
			-- N17 (TASK 17.4): dock tier maps to Dock.UpgradeLevel via the
			-- snapshot's dockLevel field (1-4, 1-indexed like the catalog).
			currentLevel = state.dockLevel or 1
		end
		if entry.level <= currentLevel then
			entry.buyButton.Text = "OWNED"
			entry.buyButton.BackgroundColor3 = UI.surfaceHi
			entry.buyButton.TextColor3 = UI.textFaint
			entry.buyButton.Active = false
		elseif entry.level == currentLevel + 1 then
			local affordable = state.cash >= (entry.item.cost or 0)
			entry.buyButton.Text = "$" .. formatCash(entry.item.cost)
			entry.buyButton.BackgroundColor3 = affordable and UI.good or UI.surfaceHi
			entry.buyButton.TextColor3 = affordable and UI.ink or UI.textDim
			entry.buyButton.Active = true
		else
			entry.buyButton.Text = "LOCKED"
			entry.buyButton.BackgroundColor3 = UI.surface
			entry.buyButton.TextColor3 = UI.textFaint
			entry.buyButton.Active = false
		end
	end
end

for _, entry in ipairs(SHOP_CATALOG) do
	buildShopRow(entry)
end

-- ============================================================
-- Quest panel
-- ============================================================
local questPanel, questContent, questClose = makePanel("QUESTS", UI.quest, UDim2.new(0, 420, 0, 500))

local questList = Instance.new("ScrollingFrame")
questList.Size = UDim2.new(1, 0, 1, 0)
questList.BackgroundTransparency = 1
questList.ScrollBarThickness = 4
questList.ScrollBarImageColor3 = UI.textFaint
questList.CanvasSize = UDim2.new(0, 0, 0, 0)
questList.AutomaticCanvasSize = Enum.AutomaticSize.Y
questList.ZIndex = 26
questList.Parent = questContent

local questLayout = Instance.new("UIListLayout")
questLayout.Padding = UDim.new(0, 8)
questLayout.SortOrder = Enum.SortOrder.LayoutOrder
questLayout.Parent = questList

local function makeQuestRow(parent, quest, order)
	local rowH = IS_MOBILE and 72 or 64
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, rowH)
	row.BackgroundColor3 = UI.surface
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = order
	row.ZIndex = 26
	row.Parent = parent
	corner(row, 12)
	stroke(row, 0.9)

	makeLabel(row, {
		Size = UDim2.new(1, -110, 0, 20),
		Position = UDim2.new(0, 12, 0, 8),
		Text = quest.desc or "Quest",
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = quest.claimed and UI.good or UI.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})

	local target = math.max(1, quest.target or 1)
	local progressVal = math.min(quest.progress or 0, target)

	local progressBar = Instance.new("Frame")
	progressBar.Size = UDim2.new(1, -120, 0, 8)
	progressBar.Position = UDim2.new(0, 12, 1, -20)
	progressBar.BackgroundColor3 = UI.surfaceHi
	progressBar.ZIndex = 27
	progressBar.Parent = row
	corner(progressBar, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(progressVal / target, 0, 1, 0)
	fill.BackgroundColor3 = quest.claimed and UI.good or UI.quest
	fill.ZIndex = 28
	fill.Parent = progressBar
	corner(fill, 4)

	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0, 92, 0, 24)
	chip.Position = UDim2.new(1, -102, 0.5, -12)
	chip.BackgroundColor3 = quest.claimed and UI.good or UI.surfaceHi
	chip.BackgroundTransparency = quest.claimed and 0.75 or 0.3
	chip.ZIndex = 27
	chip.Parent = row
	corner(chip, 999)

	makeLabel(chip, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = quest.claimed and "CLAIMED" or string.format("%d/%d • $%d", progressVal, target, quest.reward or 0),
		Font = FONT_BOLD,
		TextSize = 11,
		TextColor3 = quest.claimed and UI.good or UI.accentSoft,
		ZIndex = 28,
	})
end

local function renderQuestPanel(data)
	for _, child in ipairs(questList:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	makeLabel(questList, {
		Size = UDim2.new(1, 0, 0, 24),
		Text = "DAILY",
		Font = FONT_BOLD,
		TextSize = 12,
		TextColor3 = UI.warn,
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})
	for i, q in ipairs(data and data.dailyQuests or {}) do
		makeQuestRow(questList, q, 10 + i)
	end

	makeLabel(questList, {
		Size = UDim2.new(1, 0, 0, 24),
		Text = "WEEKLY",
		Font = FONT_BOLD,
		TextSize = 12,
		TextColor3 = UI.accent,
		LayoutOrder = 100,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})
	for i, q in ipairs(data and data.weeklyQuests or {}) do
		makeQuestRow(questList, q, 110 + i)
	end
end

-- ============================================================
-- Action bar
--   Desktop: bottom-center pill bar with keyboard hint chips.
--   Mobile: right-edge thumb-zone stack of large round buttons.
-- ============================================================
local ACTIONS = {
	{ id = "fish", label = "FISH", short = "FISH", key = "F", color = UI.good },
	{ id = "store", label = "BAG", short = "BAG", key = "G", color = UI.accent },
	{ id = "aquarium", label = "TANK", short = "TANK", key = "T", color = UI.purple },
	{ id = "quests", label = "QUESTS", short = "QUEST", key = "Q", color = UI.quest },
	{ id = "boat", label = "BOAT", short = "BOAT", key = "B", color = UI.boat },
}

local actionButtons = {}

if IS_MOBILE then
	local stack = Instance.new("Frame")
	stack.AnchorPoint = Vector2.new(1, 1)
	stack.Position = UDim2.new(1, -12, 1, -90)
	stack.Size = UDim2.new(0, 64, 0, #ACTIONS * 70)
	stack.BackgroundTransparency = 1
	stack.Parent = screenGui

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	stackLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	stackLayout.Padding = UDim.new(0, 10)
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = stack

	for i, action in ipairs(ACTIONS) do
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(0, 60, 0, 60)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = i
		holder.Parent = stack

		local btn = makeButton(holder, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			BackgroundColor3 = UI.bg,
			TextColor3 = action.color,
			CornerRadius = 18,
		})
		btn.BackgroundTransparency = 0.16
		stroke(btn, 0.58, action.color, 1.5)
		makeLabel(btn, {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.new(0, 0, 0, 9),
			Text = action.key,
			Font = FONT_HEAD,
			TextSize = 20,
			TextColor3 = action.color,
		})
		local mobileLabel = makeLabel(btn, {
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 1, -20),
			Text = action.short,
			Font = FONT_BOLD,
			TextSize = 9,
			TextColor3 = UI.text,
		})
		actionButtons[action.id] = btn
		actionButtons[action.id .. "_label"] = mobileLabel
	end
else
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -18)
	bar.Size = UDim2.new(0, 620, 0, 58)
	bar.BackgroundColor3 = UI.bg
	bar.BackgroundTransparency = 0.2
	bar.Parent = screenGui
	corner(bar, 16)
	stroke(bar, 0.85)

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, 8)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bar

	for i, action in ipairs(ACTIONS) do
		local btn = makeButton(bar, {
			Size = UDim2.new(0, 112, 0, 42),
			Text = "",
			BackgroundColor3 = UI.surface,
			LayoutOrder = i,
		})
		btn.BackgroundTransparency = 0.25
		stroke(btn, 0.88)

		local textLabel = makeLabel(btn, {
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.new(0, 10, 0, 0),
			Text = action.label,
			Font = FONT_BOLD,
			TextSize = 14,
			TextColor3 = action.color,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local keyChip = Instance.new("Frame")
		keyChip.Size = UDim2.new(0, 20, 0, 20)
		keyChip.AnchorPoint = Vector2.new(1, 0.5)
		keyChip.Position = UDim2.new(1, -8, 0.5, 0)
		keyChip.BackgroundColor3 = UI.surfaceHi
		keyChip.Parent = btn
		corner(keyChip, 5)
		makeLabel(keyChip, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = action.key,
			Font = FONT_BOLD,
			TextSize = 11,
			TextColor3 = UI.textDim,
		})

		actionButtons[action.id] = btn
		actionButtons[action.id .. "_label"] = textLabel
	end
end

-- ============================================================
-- Fishing minigame overlay — glowing timing bar
-- ============================================================
local castOverlay = Instance.new("Frame")
castOverlay.AnchorPoint = Vector2.new(0.5, 0.5)
castOverlay.Size = IS_MOBILE and UDim2.new(1, -24, 0, 132) or UDim2.new(0, 400, 0, 112)
castOverlay.Position = UDim2.new(0.5, 0, IS_MOBILE and 0.42 or 0.58, 0)
castOverlay.BackgroundColor3 = UI.bg
castOverlay.BackgroundTransparency = 0.08
castOverlay.Visible = false
castOverlay.ZIndex = 40
castOverlay.Parent = screenGui
corner(castOverlay, 16)
stroke(castOverlay, 0.8)
vGradient(castOverlay, Color3.fromRGB(26, 38, 57), UI.bg)

local castTitle = makeLabel(castOverlay, {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 10),
	Text = IS_MOBILE and "TAP WHEN IN THE GREEN!" or "CLICK WHEN IN THE GREEN!",
	Font = FONT_HEAD,
	TextSize = IS_MOBILE and 15 or 16,
	TextColor3 = UI.warn,
	ZIndex = 41,
})

local timingBar = Instance.new("Frame")
timingBar.Size = UDim2.new(1, -24, 0, IS_MOBILE and 52 or 40)
timingBar.Position = UDim2.new(0, 12, 0, IS_MOBILE and 52 or 48)
timingBar.BackgroundColor3 = UI.surface
timingBar.ZIndex = 41
timingBar.Parent = castOverlay
corner(timingBar, 10)
stroke(timingBar, 0.85)

local hitZoneFrame = Instance.new("Frame")
hitZoneFrame.Name = "HitZone"
hitZoneFrame.Size = UDim2.new(0.3, 0, 1, 0)
hitZoneFrame.Position = UDim2.new(0.35, 0, 0, 0)
hitZoneFrame.BackgroundColor3 = UI.good
hitZoneFrame.BackgroundTransparency = 0.45
hitZoneFrame.ZIndex = 42
hitZoneFrame.Parent = timingBar
corner(hitZoneFrame, 8)
stroke(hitZoneFrame, 0.5, UI.good, 1.5)

local perfectZoneFrame = Instance.new("Frame")
perfectZoneFrame.Name = "PerfectZone"
perfectZoneFrame.AnchorPoint = Vector2.new(0.5, 0)
perfectZoneFrame.Size = UDim2.new(0.4, 0, 1, -8)
perfectZoneFrame.Position = UDim2.new(0.5, 0, 0, 4)
perfectZoneFrame.BackgroundColor3 = Color3.fromRGB(134, 239, 172)
perfectZoneFrame.BackgroundTransparency = 0.12
perfectZoneFrame.ZIndex = 43
perfectZoneFrame.Parent = hitZoneFrame
corner(perfectZoneFrame, 7)

makeLabel(castOverlay, {
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.new(0, 12, 1, -20),
	Text = "CENTER HIT  •  BONUS LUCK",
	Font = FONT_BOLD,
	TextSize = 9,
	TextColor3 = UI.textFaint,
	ZIndex = 41,
})

local marker = Instance.new("Frame")
marker.Size = UDim2.new(0, 5, 1, 6)
marker.Position = UDim2.new(0, 0, 0, -3)
marker.BackgroundColor3 = Color3.new(1, 1, 1)
marker.ZIndex = 43
marker.Parent = timingBar
corner(marker, 3)

local markerGlow = Instance.new("Frame")
markerGlow.Size = UDim2.new(0, 15, 1, 10)
markerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
markerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
markerGlow.BackgroundColor3 = UI.accentSoft
markerGlow.BackgroundTransparency = 0.75
markerGlow.ZIndex = 42
markerGlow.Parent = marker
corner(markerGlow, 8)

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
end

-- ============================================================
-- State rendering
-- ============================================================
local function toHex(color)
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local dataStoreWarningShown = false

-- TASK 9.2 (0jc.2): raid window state — forward-declared here so render()
-- can check HasSeenRaidExplanation against raidWindow.open for the onboarding
-- prompt. The actual OnClientEvent handler is wired at line ~1851 below.
local raidWindow = { open = false, remainingSeconds = 0, nextWindowInSeconds = 0 }

local function render()
	if not state then
		return
	end
	-- TASK 10.5: DataStore failure handling — show warning when unhealthy
	if state.dataStoreHealthy == false and not dataStoreWarningShown then
		dataStoreWarningShown = true
		showNotification("Saving unavailable -- try again. Your progress is safe but purchases may not persist.", Color3.fromRGB(255, 100, 100))
	elseif state.dataStoreHealthy ~= false and dataStoreWarningShown then
		dataStoreWarningShown = false
		showNotification("Saving restored!", Color3.fromRGB(100, 255, 100))
	end
	animateCashTo(state.cash)
	incomeLabel.Text = string.format("+$%.1f / sec", state.incomePerSec)
	carryLabel.Text = string.format("On line: %d / %d fish", state.carried, state.maxCarried)
	-- TASK 4.4 (0cw.4 / wqw.18): live-update the inventory panel on every
	-- state push (catch, per-fish sell/store, bulk actions) while it is open.
	if activePanel == inventoryPanel then
		renderInventory()
	end

	local fishBtn = actionButtons.fish
	local fishLbl = actionButtons.fish_label or fishBtn
	if casting then
		fishLbl.Text = IS_MOBILE and "..." or "CASTING"
		fishLbl.TextColor3 = UI.textFaint
	else
		fishLbl.Text = "FISH"
		fishLbl.TextColor3 = UI.good
	end

	local boatLbl = actionButtons.boat_label or actionButtons.boat
	boatLbl.Text = state.hasBoat and (IS_MOBILE and "SAIL" or "SAILING") or "BOAT"

	local rodName = GameConfig.Rods[state.rodLevel].name
	local baitName = GameConfig.Baits[state.baitLevel].name
	aquariumStats.Text = string.format(
		'<font color="#EEF3FA"><b>%d / %d fish</b></font>  •  <font color="#86EFAC"><b>$%.1f / sec</b></font>\n%s + %s\nTank %d  •  Lock %d  •  Alarm %d',
		state.liveWellCount, state.capacity, state.incomePerSec, rodName, baitName,
		state.upgradeLevel or 1, state.lockLevel or 0, state.alarmLevel or 0
	)
	local capacityRatio = math.clamp(state.liveWellCount / math.max(1, state.capacity), 0, 1)
	TweenService:Create(capacityFill, EASE_OUT, { Size = UDim2.new(capacityRatio, 0, 1, 0) }):Play()

	local lines = {}
	for i, rarity in ipairs(GameConfig.Rarities) do
		local count = state.liveWellCounts[rarity.name] or 0
		-- R2.2 (dt9.2): removed per-rarity incomePerSec display — it was
		-- reading the dead GameConfig.Rarities[].incomePerSec field which
		-- disagreed with the actual income (from FishDefinitions per-species
		-- IncomePerMinute) by 12-18x. Total income/sec from StateSync.snapshot
		-- (the authoritative, multiplier-aware value) is shown via the
		-- incomeLabel HUD element and the aquariumStats panel above.
		table.insert(lines, string.format(
			'<font color="%s">●</font>  <font color="%s"><b>%s</b></font>  ×%d   <font color="#94A3B8">$%d each</font>',
			toHex(rarity.color), toHex(rarity.color), rarity.name, count, rarity.value
		))
	end
	rarityList.Text = table.concat(lines, "\n")
	-- Lock button state (LOCAL field names per StateSync.lua)
	-- TASK 8.4: show free-use count in lock button text.
	if state.lockedUntil > 0 then
		lockButton.Text = string.format("LOCKED %ds", math.ceil(state.lockedUntil))
		lockButton.BackgroundColor3 = UI.bad
		lockButton.TextColor3 = UI.ink
	elseif state.lockCooldownUntil > 0 then
		lockButton.Text = string.format("RECHARGE %ds", math.ceil(state.lockCooldownUntil))
		lockButton.BackgroundColor3 = UI.surfaceHi
		lockButton.TextColor3 = UI.textDim
	else
		local lockDur = GameConfig.Aquarium.lockDuration
		if state.lockLevel and state.lockLevel > 0 and GameConfig.Upgrades.Lock[state.lockLevel] then
			lockDur = GameConfig.Upgrades.Lock[state.lockLevel].lockDuration
		end
		local freeUses = state.lockFreeUsesRemaining or 0
		local freeMax = state.lockFreeUsesMax or 3
		if freeUses > 0 then
			lockButton.Text = string.format("LOCK (%ds) [%d/%d free]", lockDur, freeUses, freeMax)
		else
			lockButton.Text = string.format("LOCK (%ds) [no free]", lockDur)
		end
		lockButton.BackgroundColor3 = UI.warn
		lockButton.TextColor3 = UI.ink
	end

	-- TASK 8.2/8.3: Raid opt-in toggle button state.
	if state.raidOptIn then
		raidOptInButton.Text = "RAID OPT-IN: ON (can be targeted)"
		raidOptInButton.BackgroundColor3 = UI.bad
		raidOptInButton.TextColor3 = UI.ink
	else
		local catches = state.totalCatches or 0
		local hasUpgrade = (state.upgradeLevel or 1) > 1
		if not hasUpgrade and catches < 10 then
			raidOptInButton.Text = string.format("RAID OPT-IN: LOCKED (%d/10 catches or upgrade needed)", catches)
			raidOptInButton.BackgroundColor3 = UI.surfaceHi
			raidOptInButton.TextColor3 = UI.textFaint
		else
			raidOptInButton.Text = "RAID OPT-IN: OFF (safe)"
			raidOptInButton.BackgroundColor3 = UI.surfaceHi
			raidOptInButton.TextColor3 = UI.text
		end
	end

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

	-- Claim income button (TASK 5.1)
	-- TASK 10.5: disable when DataStore is unhealthy
	local storeHealthy = state.dataStoreHealthy ~= false
	if not storeHealthy then
		claimButton.Text = "SAVING UNAVAILABLE"
		claimButton.BackgroundColor3 = Color3.fromRGB(100, 60, 60)
	elseif state.unclaimedIncome > 0 then
		claimButton.Text = string.format("CLAIM $%d", state.unclaimedIncome)
		claimButton.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
	else
		claimButton.Text = "CLAIM $0"
		claimButton.BackgroundColor3 = Color3.fromRGB(60, 70, 80)
	end

	-- TASK 9.2 (0jc.2): contextual onboarding prompts driven by flags.
	-- Only ONE prompt shows at a time, prioritized by the player's
	-- progression stage. Each is dismissible — once dismissed it stays
	-- hidden for the session. Prompts auto-clear when the flag flips
	-- (the server pushes a new state, and the now-true flag moves us
	-- to the next stage).
	local ob = state.onboarding or {}
	if not ob.HasCaughtFirstFish then
		-- Stage 1: player hasn't caught anything yet.
		if dismissedPrompts.firstCast then
			-- Already dismissed — hide prompt
		elseif casting then
			dismissOnboardingPrompt("firstCast")
		else
			showOnboardingPrompt("firstCast",
				IS_MOBILE and "Tap FISH while standing in the glowing zone!" or "Press F to cast into the glowing zone at your dock!",
				UI.good)
		end
	elseif not ob.HasStoredFirstFish then
		-- Stage 2: caught a fish but hasn't stored it yet.
		if state.carried > 0 then
			-- Button renamed STORE → BAG by TASK 4.4 (0cw.4): G now opens the
			-- per-fish bag panel, where STORE / STORE ALL live.
			showOnboardingPrompt("firstStore",
				IS_MOBILE and "Tap BAG to store your fish for passive income!" or "Press G to open your bag and store your fish — they'll earn cash over time!",
				UI.accent)
		else
			-- Player has 0 carried (sold the fish instead of storing it).
			-- Temporarily hide the prompt — DON'T permanently dismiss it,
			-- so it reappears when they catch another fish and still get
			-- the store guidance.
			currentPromptStage = nil
			onboardingPrompt.Visible = false
		end
	elseif not ob.HasClaimedIncome and (state.unclaimedIncome or 0) > 0 then
		-- Stage 3: has stored fish earning income but hasn't claimed yet.
		showOnboardingPrompt("firstClaim",
			IS_MOBILE and "Tap CLAIM to collect your earned income!" or "Open your tank and hit CLAIM to collect your income!",
			Color3.fromRGB(50, 160, 80))
	elseif not ob.HasSeenRaidExplanation and raidWindow.open then
		-- Stage 4: first raid window appeared and player hasn't seen the
		-- explanation. Dismissible — the player can ignore it and stay safe.
		showOnboardingPrompt("raidExplain",
			"Raids are optional! Open your tank panel to opt in and steal fish from other docks.",
			Color3.fromRGB(255, 120, 120))
	else
		-- All onboarding stages complete or dismissed — hide the prompt.
		currentPromptStage = nil
		onboardingPrompt.Visible = false
	end
end

-- ============================================================
-- Bite Timing Minigame (TASK 3.2)
-- ============================================================
local minigameFrame = Instance.new("Frame")
minigameFrame.Size = UDim2.new(0, 400, 0, 120)
minigameFrame.Position = UDim2.new(0.5, -200, 0.5, -60)
minigameFrame.BackgroundColor3 = UI.bg
minigameFrame.Visible = false
minigameFrame.Parent = screenGui
corner(minigameFrame, 14)

local minigameTitle = makeLabel(minigameFrame, {
	Size = UDim2.new(1, 0, 0, 28),
	Position = UDim2.new(0, 0, 0, 8),
	Text = "FISH ON! Tap when the marker is in the zone!",
	TextColor3 = UI.warn,
})

-- The bar track
local barTrack = Instance.new("Frame")
barTrack.Size = UDim2.new(1, -40, 0, 20)
barTrack.Position = UDim2.new(0, 20, 0, 50)
barTrack.BackgroundColor3 = UI.surfaceHi
barTrack.Parent = minigameFrame
corner(barTrack, 8)

-- The target zone (centered; width comes from the equipped rod's
-- minigameZoneSize — see runMinigame for the per-cast resize)
local targetZone = Instance.new("Frame")
targetZone.Size = UDim2.new(0.3, 0, 1, 0)
targetZone.Position = UDim2.new(0.35, 0, 0, 0)
targetZone.BackgroundColor3 = UI.good
targetZone.BackgroundTransparency = 0.5
targetZone.Parent = barTrack
corner(targetZone, 8)

-- The moving marker
local marker = Instance.new("Frame")
marker.Size = UDim2.new(0, 4, 1, 4)
marker.Position = UDim2.new(0, 0, 0, -2)
marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
marker.Parent = barTrack
corner(marker, 2)

-- Result text
local minigameResult = makeLabel(minigameFrame, {
	Size = UDim2.new(1, 0, 0, 24),
	Position = UDim2.new(0, 0, 0, 80),
	Text = "",
	TextColor3 = UI.text,
})

local minigameActive = false
local minigameStartTime = 0
local minigameWindow = 3.0
local minigameZoneId = nil
-- Half-width of the current target zone, refreshed per cast from the
-- equipped rod's minigameZoneSize (TASK 2.3). onMinigameTap validates
-- against this — NOT the hardcoded [0.35, 0.65] band — so a wider-zone
-- rod's advantage is actually visible to the player.
local minigameZoneHalfWidth = 0.15

-- Animate the marker sweeping back and forth
local function runMinigame(zoneId, windowSeconds)
	if minigameActive then return end
	minigameActive = true
	minigameZoneId = zoneId
	minigameWindow = windowSeconds
	minigameStartTime = os.clock()
	minigameFrame.Visible = true
	minigameResult.Text = ""

	-- ROUND-3 FIX (fellow-agent review): the minigame zone was hardcoded to
	-- 30% ([0.35, 0.65]) in BOTH the visual frame and the tap hit-test, but
	-- RodDefinitions gives better rods a wider minigameZoneSize (0.30/0.35/
	-- 0.40). The server's authoritative reroll (TASK 14.16) already uses the
	-- rod's zone size, so the client display was lying to honest players
	-- with upgraded rods — taps in the outer 5% of their "real" zone read
	-- as misses client-side. Size the zone from the equipped rod so what
	-- the player sees matches what the server accepts.
	local zoneSize = GameConfig.MiniGame.hitZoneWidth -- fallback 0.30
	if state and state.rodLevel then
		local rodDef = GameConfig.RodDefinitions[state.rodLevel]
		if rodDef and rodDef.minigameZoneSize then
			zoneSize = rodDef.minigameZoneSize
		end
	end
	minigameZoneHalfWidth = zoneSize / 2
	local zoneStart = 0.5 - minigameZoneHalfWidth
	targetZone.Size = UDim2.new(zoneSize, 0, 1, 0)
	targetZone.Position = UDim2.new(zoneStart, 0, 0, 0)

	task.spawn(function()
		local sweepDuration = 1.2 -- seconds for one full sweep
		while minigameActive do
			local elapsed = os.clock() - minigameStartTime
			if elapsed > minigameWindow then
				-- Time expired
				minigameActive = false
				minigameFrame.Visible = false
				Remotes.SubmitCatchInput:InvokeServer({ hit = false, elapsed = elapsed })
				break
			end

			-- Ping-pong sweep: 0 -> 1 -> 0
			local t = (elapsed % sweepDuration) / sweepDuration
			local pos
			if t < 0.5 then
				pos = t * 2 -- 0 -> 1
			else
				pos = 2 - t * 2 -- 1 -> 0
			end
			marker.Position = UDim2.new(pos, -2, 0, -2)
			task.wait()
		end
	end)
end

-- Player taps/ clicks to stop the marker
local function onMinigameTap()
	if not minigameActive then return end
	local elapsed = os.clock() - minigameStartTime
	local markerPos = marker.Position.X.Scale
	-- ROUND-3 FIX: validate against the per-rod zone (minigameZoneHalfWidth
	-- was set by runMinigame from RodDefinitions), not the legacy hardcoded
	-- [0.35, 0.65] band. The server is still authoritative (it re-rolls
	-- against the rod's zone size in SubmitCatchInput); this just aligns
	-- the client's pre-validation with the visual the player saw.
	local halfWidth = minigameZoneHalfWidth or 0.15
	local hit = markerPos >= (0.5 - halfWidth) and markerPos <= (0.5 + halfWidth)
	minigameActive = false
	minigameFrame.Visible = false
	local result = Remotes.SubmitCatchInput:InvokeServer({ hit = hit, elapsed = elapsed, markerPos = markerPos })
	-- TASK 14.16: the server re-rolls claimed hits against the rod's zone size,
	-- so an on-zone tap can still be rejected — surface that honestly.
	if hit and result and result.ok == false and result.reason == "missed" then
		showNotification("So close! The fish shook off the hook...", UI.warn)
	end
end

minigameFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		onMinigameTap()
	end
end)

-- Also allow tapping anywhere on screen during minigame
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not minigameActive then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		onMinigameTap()
	end
end)

-- ============================================================
-- Actions
-- ============================================================
local function doFish()
	if not casting then
		Remotes.Cast:FireServer()
	end
end

actionButtons.fish.Activated:Connect(doFish)
-- Panel close (✕) buttons were created by makePanel but never wired — dead
-- UI on every panel (backdrop click and Escape worked; the ✕ did nothing).
aquariumClose.Activated:Connect(hidePanels)
inventoryClose.Activated:Connect(hidePanels)
shopClose.Activated:Connect(hidePanels)
questClose.Activated:Connect(hidePanels)
-- TASK 4.4 (0cw.4 / wqw.18): BAG button opens the per-fish inventory panel
-- (bulk store-all remains available via the panel's STORE ALL button).
actionButtons.store.Activated:Connect(toggleInventoryPanel)
sellButton.Activated:Connect(function()
	Remotes.SellAll:InvokeServer()
end)
lockButton.Activated:Connect(function()
	Remotes.LockAquarium:InvokeServer()
end)
-- TASK 8.2/8.3: raid opt-in toggle (server validates new-player gate)
-- TASK 9.2 (0jc.2): dismiss the raid explanation onboarding prompt when the
-- player interacts with the opt-in button — they've now "seen" the explanation.
raidOptInButton.Activated:Connect(function()
	dismissOnboardingPrompt("raidExplain")
	Remotes.RequestToggleRaidOptIn:InvokeServer()
end)
-- TASK 5.1/14.1: claim accumulated aquarium income (was created but never wired)
claimButton.Activated:Connect(function()
	Remotes.ClaimIncome:InvokeServer()
end)

local function toggleQuestPanel()
	if activePanel == questPanel then
		hidePanels()
		return
	end
	showPanel(questPanel)
	if questData then
		renderQuestPanel(questData)
	else
		Remotes.OpenQuests:FireServer()
	end
end

actionButtons.quests.Activated:Connect(toggleQuestPanel)

local function trySpawnBoat()
	local result = Remotes.SpawnBoat:InvokeServer()
	if not result then
		return
	end
	if not result.ok then
		-- "stunned" is notified server-side (server sends a specific message);
		-- skip the client fallback to avoid a double toast.
		if result.reason == "stunned" then
			return
		end
		local reasons = {
			already_has_boat = "You already have a boat out!",
			no_dock = "Boat dock is missing.",
			no_spawn_point = "Boat spawn point unavailable.",
			no_character = "Spawn your character first.",
		}
		showNotification(reasons[result.reason] or "Could not spawn boat.", UI.bad)
	end
end

actionButtons.boat.Activated:Connect(trySpawnBoat)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		doFish()
	elseif input.KeyCode == Enum.KeyCode.G then
		toggleInventoryPanel()
	elseif input.KeyCode == Enum.KeyCode.T then
		showPanel(aquariumPanel)
	elseif input.KeyCode == Enum.KeyCode.Q then
		toggleQuestPanel()
	elseif input.KeyCode == Enum.KeyCode.B then
		trySpawnBoat()
	elseif input.KeyCode == Enum.KeyCode.Escape and activePanel then
		hidePanels()
	end
end)

-- ============================================================
-- Remote listeners
-- ============================================================
Remotes.StateChanged.OnClientEvent:Connect(function(snapshot)
	state = snapshot
	render()
	refreshShop()
end)

Remotes.Notify.OnClientEvent:Connect(showNotification)

-- EPIC 8 (TASK 8.1 / gdj.1): raid-window state. The server fires
-- RaidWindowChanged on window open/close edges and once to each late joiner.
-- Payload is DURATIONS ONLY (server never sends absolute os.clock() values,
-- which are machine-local): (isOpen, remainingSeconds, nextWindowInSeconds).
-- We track the latest state and toast on transitions; the full countdown /
-- "RAID WATERS OPEN" HUD banner is a later Epic 8 client bead — this keeps
-- the window visible to players in the meantime and gives that bead a
-- ready-made state source.
-- raidWindow is forward-declared above (before render()) so the onboarding
-- prompt logic can reference raidWindow.open for the HasSeenRaidExplanation
-- stage. The OnClientEvent handler here is the sole writer.
Remotes.RaidWindowChanged.OnClientEvent:Connect(function(isOpen, remainingSeconds, nextWindowInSeconds)
	local wasOpen = raidWindow.open
	raidWindow.open = isOpen == true
	raidWindow.remainingSeconds = remainingSeconds or 0
	raidWindow.nextWindowInSeconds = nextWindowInSeconds or 0
	if raidWindow.open and not wasOpen then
		showNotification(
			string.format("RAID WATERS OPEN for %d minutes! Steal fish from other docks while the window lasts.", math.floor(raidWindow.remainingSeconds / 60)),
			Color3.fromRGB(255, 120, 120)
		)
	elseif not raidWindow.open and wasOpen then
		showNotification("Raid waters closed. The harbor is safe... for now.", UI.accentSoft)
	end
end)

Remotes.CastState.OnClientEvent:Connect(function(isCasting, castTime, hitZone)
	casting = isCasting
	if isCasting then
		-- N16: read the server-authoritative hit-zone bounds (3rd arg).
		-- hitZoneStart/hitZoneEnd = outer "good" zone; goodStart/goodEnd =
		-- inner "perfect" zone. Falls back to hardcoded defaults if absent
		-- (e.g. older server), but the round-2 server always sends them.
		if hitZone then
			-- N16 (round-2 fix): server sends hitZoneStart/hitZoneEnd = INNER
			-- perfect bullseye (narrow), goodStart/goodEnd = OUTER good band
			-- (wide). The outer frame (hitZoneFrame) renders the GOOD band;
			-- the inner frame (perfectZoneFrame) renders the PERFECT bullseye.
			castHitZone.perfectStart_ = hitZone.hitZoneStart
			castHitZone.perfectEnd_ = hitZone.hitZoneEnd
			castHitZone.goodStart_ = hitZone.goodStart
			castHitZone.goodEnd_ = hitZone.goodEnd
		else
			-- Fallback (older server): good = wide outer, perfect = narrow inner
			castHitZone.perfectStart_ = 0.35
			castHitZone.perfectEnd_ = 0.65
			castHitZone.goodStart_ = 0.15
			castHitZone.goodEnd_ = 0.85
		end
		-- Outer "good" band frame (wider), rendered in the base green
		local goodStart = castHitZone.goodStart_ or 0.15
		local goodEnd = castHitZone.goodEnd_ or 0.85
		local goodWidth = goodEnd - goodStart
		hitZoneFrame.Size = UDim2.new(goodWidth, 0, 1, 0)
		hitZoneFrame.Position = UDim2.new(goodStart, 0, 0, 0)

		-- Inner "perfect" bullseye frame (narrower), a CHILD of the good frame.
		-- Its size/position are expressed as a FRACTION of the good frame, so
		-- convert the perfect band's track-space bounds into good-frame-space.
		if castHitZone.perfectStart_ and castHitZone.perfectEnd_ then
			local pWidth = castHitZone.perfectEnd_ - castHitZone.perfectStart_
			local pCenter = (castHitZone.perfectStart_ + castHitZone.perfectEnd_) / 2
			-- Width of perfect zone relative to the good band
			local relWidth = goodWidth > 0 and (pWidth / goodWidth) or 0.4
			-- Center of perfect zone as a fraction within the good band [0,1]
			local relCenter = goodWidth > 0
				and ((pCenter - goodStart) / goodWidth)
				or 0.5
			perfectZoneFrame.Size = UDim2.new(math.clamp(relWidth, 0, 1), 0, 1, -8)
			perfectZoneFrame.Position = UDim2.new(math.clamp(relCenter, 0, 1), 0, 0, 4)
			perfectZoneFrame.Visible = true
		else
			perfectZoneFrame.Visible = false
		end

		castOverlay.Visible = true
		marker.Position = UDim2.new(0, 0, 0, -3)

		local overlayScale = castOverlay:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		overlayScale.Parent = castOverlay
		overlayScale.Scale = 0.9
		TweenService:Create(overlayScale, EASE_POP, { Scale = 1 }):Play()

		local duration = castTime or 4
		castDeadline = os.clock() + duration

		markTween = TweenService:Create(
			marker,
			TweenInfo.new(duration, Enum.EasingStyle.Linear),
			{ Position = UDim2.new(1, -5, 0, -3) }
		)
		markTween:Play()

		castInputConn = UserInputService.InputBegan:Connect(function(input, gp)
			if gp then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not casting then
					return
				end
				local elapsed = os.clock() - (castDeadline - duration)
				local accuracy = math.clamp(elapsed / duration, 0, 1)
				stopCastOverlay()
				Remotes.CastResult:FireServer(accuracy)
			end
		end)
	else
		stopCastOverlay()
	end
	render()
end)

Remotes.BiteEvent.OnClientEvent:Connect(function(zoneId, windowSeconds)
	-- Start the timing minigame when the server says a fish is biting
	runMinigame(zoneId, windowSeconds)
end)

Remotes.OpenAquarium.OnClientEvent:Connect(function()
	showPanel(aquariumPanel)
end)

Remotes.OpenShop.OnClientEvent:Connect(function()
	showPanel(shopPanel)
	refreshShop()
end)

Remotes.QuestProgressChanged.OnClientEvent:Connect(function(data)
	questData = data
	if activePanel == questPanel then
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

-- TASK 9.2 (0jc.2): the old hardcoded onboarding toasts (task.delay(4/9))
-- have been replaced by the contextual prompt system above. The prompts
-- are driven by OnboardingService flags in render() — they show the right
-- hint at the right time and auto-advance as the player progresses.
-- A single delayed welcome toast remains for the very first session.
task.delay(5, function()
	if not state or not (state.onboarding or {}).HasCaughtFirstFish then
		showNotification(IS_MOBILE and "Welcome! Tap FISH in the glowing zone to catch your first fish." or "Welcome! Press F in the glowing zone to catch your first fish.", UI.good)
	end
end)