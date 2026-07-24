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
	Text = "+$0.0/sec",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 12 or 13,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	-- TASK 24.1 (hvfh.4.1): RichText so the claimable "ready" segment can be
	-- tinted claim-green (and pulsed) without a second label or layout change.
	RichText = true,
})

-- TASK 24.1 (hvfh.4.1): the whole HUD card opens the aquarium panel. Labels
-- don't sink input, so this transparent button gets the click even under the
-- labels; ZIndex keeps it below the +$ gain floaters (ZIndex 5). The
-- Activated handler is wired near the bottom with the other panel openers
-- (showPanel/aquariumPanel are not defined yet at this point in the file).
local hudClick = Instance.new("TextButton")
hudClick.Name = "HUDClick"
hudClick.Size = UDim2.new(1, 0, 1, 0)
hudClick.BackgroundTransparency = 1
hudClick.Text = ""
hudClick.AutoButtonColor = false
hudClick.ZIndex = 4
hudClick.Parent = hud

-- TASK 24.1 (hvfh.4.1): dual-purpose income line — rate always shown, plus a
-- claim-green "$N ready" segment while unclaimed income exists. One line: no
-- HUD height change, no carryPill shift. #32A050 == Color3.fromRGB(50,160,80),
-- the claimButton green used in render().
local CLAIM_GREEN_HEX = "32A050"
local function updateIncomeLine(readyTransparency)
	local ready = state and state.unclaimedIncome or 0
	if ready > 0 then
		-- One notch smaller on the 178px mobile card so rate + ready fit on
		-- one line (the no-layout-shift path; 6+ digit ready values may still
		-- clip on mobile — accepted tradeoff, recorded in the bead).
		incomeLabel.TextSize = IS_MOBILE and 11 or 13
		incomeLabel.Text = string.format(
			'+$%.1f/sec  •  <font color="#%s" transparency="%.2f"><b>$%s ready</b></font>',
			state.incomePerSec, CLAIM_GREEN_HEX, readyTransparency or 0, formatCash(ready)
		)
	else
		incomeLabel.TextSize = IS_MOBILE and 12 or 13
		incomeLabel.Text = string.format("+$%.1f/sec", state and state.incomePerSec or 0)
	end
end

-- Slow pulse on the "ready" segment only (font transparency attribute), ~5Hz
-- updates on a 2.4s cycle; sleeps cheaply when there is nothing to claim.
-- render() owns the plain-rate line whenever ready == 0.
task.spawn(function()
	while true do
		if state and (state.unclaimedIncome or 0) > 0 then
			local phase = (os.clock() % 2.4) / 2.4
			local alpha = 0.05 + 0.5 * (1 - math.abs(phase * 2 - 1))
			updateIncomeLine(alpha)
			task.wait(0.2)
		else
			task.wait(0.5)
		end
	end
end)

-- Animated cash counting
local displayedCash = 0
local cashTweenConn = nil
local lastCash = nil
local hasRenderedCash = false
local function animateCashTo(target)
	target = type(target) == "number" and target or 0
	if not hasRenderedCash then
		hasRenderedCash = true
		displayedCash = target
		lastCash = target
		cashLabel.Text = "$" .. formatCash(target)
		return
	end
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
local function showNotification(message, color, category)
	color = color or UI.accentSoft
	-- TASK 24.3 (hvfh.4.3): category forwarded from server (catch/quest/raid/
	-- lock/economy/info). Defaults to "info" when nil so existing 2-arg
	-- FireClient call sites keep working. The value is accepted here to
	-- satisfy the arity contract; the toast icon/chip RENDERING that consumes
	-- it is the client-visual half of 24.3 (separate follow-up). Until that
	-- lands, the param is forward-only plumbing — harmless dead local.
	category = category or "info"
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
-- Mobile: position above the right-edge action bar stack (7 buttons × 70
-- = 490px tall, bottom at -90 → top at -580; +12px gap → -592).
-- Desktop: just above the bottom action bar (58px at -18 → top at -76;
-- +8px gap → -84).
onboardingPrompt.Position = UDim2.new(0.5, 0, 1, IS_MOBILE and -592 or -84)
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
	Size = UDim2.new(0, IS_MOBILE and 36 or 24, 0, IS_MOBILE and 36 or 24),
	Position = UDim2.new(1, IS_MOBILE and -42 or -30, 0.5, IS_MOBILE and -18 or -12),
	Text = "✕",
	TextSize = IS_MOBILE and 14 or 12,
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
-- Sell-vs-store comparison prompt (TASK 9.4 / 0jc.4)
-- Shown on the first catch to help the player decide whether
-- to sell the fish for instant cash or store it for passive income.
-- Dismissible and persists via MarkOnboardingFlag.
-- ============================================================
local sellStorePrompt = Instance.new("Frame")
sellStorePrompt.Name = "SellStorePrompt"
sellStorePrompt.AnchorPoint = Vector2.new(0.5, 0)
sellStorePrompt.Position = UDim2.new(0.5, 0, 0, SAFE_TOP + 140)
sellStorePrompt.Size = UDim2.new(IS_MOBILE and 1 or 0, IS_MOBILE and -24 or 360, 0, IS_MOBILE and 126 or 116)
sellStorePrompt.BackgroundColor3 = UI.surface
sellStorePrompt.BackgroundTransparency = 0.08
sellStorePrompt.Visible = false
sellStorePrompt.ZIndex = 16
sellStorePrompt.Parent = screenGui
corner(sellStorePrompt, 14)
stroke(sellStorePrompt, 0.7, UI.accent, 1.5)

makeLabel(sellStorePrompt, {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 10),
	Text = "You caught a fish!",
	Font = FONT_BOLD,
	TextSize = IS_MOBILE and 16 or 15,
	TextColor3 = UI.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 17,
})

makeLabel(sellStorePrompt, {
	Size = UDim2.new(1, -20, 0, 36),
	Position = UDim2.new(0, 10, 0, 34),
	Text = "Sell now for instant cash, or store it to earn income over time.",
	Font = FONT_BODY,
	TextSize = IS_MOBILE and 13 or 12,
	TextColor3 = UI.textDim,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 17,
})

local sellStoreClose = makeButton(sellStorePrompt, {
	Size = UDim2.new(0, IS_MOBILE and 36 or 26, 0, IS_MOBILE and 36 or 26),
	Position = UDim2.new(1, IS_MOBILE and -41 or -31, 0, IS_MOBILE and 4 or 8),
	Text = "✕",
	TextSize = 13,
	BackgroundColor3 = UI.surfaceHi,
	TextColor3 = UI.textDim,
	CornerRadius = 999,
	ZIndex = 17,
})

local sellStoreSellBtn = makeButton(sellStorePrompt, {
	Size = UDim2.new(0.48, -6, 0, IS_MOBILE and 44 or 36),
	Position = UDim2.new(0, 10, 1, IS_MOBILE and -56 or -48),
	Text = "SELL $0",
	BackgroundColor3 = UI.good,
	TextColor3 = UI.ink,
	CornerRadius = 10,
	ZIndex = 17,
})

local sellStoreStoreBtn = makeButton(sellStorePrompt, {
	Size = UDim2.new(0.48, -6, 0, IS_MOBILE and 44 or 36),
	Position = UDim2.new(0.52, 4, 1, IS_MOBILE and -56 or -48),
	Text = "STORE $0/min",
	BackgroundColor3 = UI.accent,
	TextColor3 = UI.ink,
	CornerRadius = 10,
	ZIndex = 17,
})

-- The FishInstance currently being offered by the comparison prompt.
local sellStoreTargetFish = nil
-- Whether the prompt has already been shown or dismissed this session.
local sellStorePromptShown = false
-- Carried count on the previous render, used to detect a new catch.
local lastCarriedCount = 0

local function hideSellStorePrompt()
	sellStorePrompt.Visible = false
	sellStoreTargetFish = nil
end

local function markSellStoreComparisonSeen()
	if not state or not state.onboarding or state.onboarding.HasSeenSellStoreComparison then
		return
	end
	-- Fire-and-forget: if the server is unreachable, the session flag still
	-- prevents the prompt from reappearing this session; the flag will persist
	-- on the next successful save.
	pcall(function()
		Remotes.MarkOnboardingFlag:InvokeServer("HasSeenSellStoreComparison")
	end)
end

local function showSellStorePrompt(fish)
	if sellStorePromptShown then
		return
	end
	if not fish then
		return
	end
	sellStorePromptShown = true
	sellStoreTargetFish = fish
	sellStoreSellBtn.Text = string.format("SELL $%d", fish.BaseSellValue or 0)
	sellStoreStoreBtn.Text = string.format("STORE $%.1f/min", fish.IncomePerMinute or 0)
	sellStorePrompt.Visible = true
	local scale = sellStorePrompt:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = sellStorePrompt
	scale.Scale = 0.92
	TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
end

sellStoreClose.Activated:Connect(function()
	hideSellStorePrompt()
	markSellStoreComparisonSeen()
end)

sellStoreSellBtn.Activated:Connect(function()
	if sellStoreTargetFish then
		Remotes.SellFish:InvokeServer(sellStoreTargetFish.InstanceId)
	end
	hideSellStorePrompt()
	markSellStoreComparisonSeen()
end)

sellStoreStoreBtn.Activated:Connect(function()
	if sellStoreTargetFish then
		Remotes.StoreSingleFish:InvokeServer(sellStoreTargetFish.InstanceId)
	end
	hideSellStorePrompt()
	markSellStoreComparisonSeen()
end)


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
-- TASK 25.1 (hvfh.5.1): forward-declared so hidePanels + render can
-- reference them before the sellButton handler section assigns them.
-- Lua closures capture upvalues lexically at definition time — a local
-- declared AFTER render()/hidePanels would be invisible to them (they'd
-- see globals instead). All four are assigned at the handler section below.
local disarmSellButton: any = nil
local sellArmed = false
local sellArmPayout = 0
local computeSellPayout: any = nil

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
		-- TASK 25.1 (hvfh.5.1): disarm SELL ALL confirm on panel close.
		if disarmSellButton then
			disarmSellButton()
		end
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
	Size = UDim2.new(1, -16, 0, IS_MOBILE and 44 or 34),
	Position = UDim2.new(0, 8, 1, -122),
	Text = "CLAIM $0",
	BackgroundColor3 = Color3.fromRGB(60, 70, 80),
	-- thj.5: claimButton is a sibling of the content frame (ZIndex 26); ensure
	-- it renders/interacts on top so the larger mobile buttons above it don't
	-- steal input in the overlapping region.
	ZIndex = 27,
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
	Size = UDim2.new(1, 0, 0, IS_MOBILE and 44 or 32),
	-- thj.5: keep a 4px gap above the SELL/LOCK buttons on mobile; the taller
	-- button would otherwise overlap because buttonH is also larger on mobile.
	Position = UDim2.new(0, 0, 1, -buttonH - (IS_MOBILE and 52 or 40)),
	Text = "RAID OPT-IN: OFF",
	BackgroundColor3 = UI.surfaceHi,
	ZIndex = 26,
})

-- ============================================================
-- Inventory panel (TASK 4.4 / wqw.18): per-fish SELL + STORE management.
-- Lists every carried fish from the snapshot's carriedFish array; each row
-- shows species/rarity/value with per-fish SELL (SellFish) and STORE
-- (StoreSingleFish) buttons, plus a bulk STORE ALL shortcut.
-- NOTE: no SELL ALL here — the server's RequestSellFish liquidates the AQUARIUM
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
	if not fish then
		return "Fish"
	end
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
		if fish then
			table.insert(signatureParts, tostring(fish.InstanceId))
		end
	end
	local signature = table.concat(signatureParts, "|")
	if signature == lastInventorySignature then
		return
	end
	lastInventorySignature = signature
	clearInventoryList()
	local totalValue = 0
	for _, fish in ipairs(carried) do
		if fish then
			totalValue += fish.BaseSellValue or 0
		end
	end
	inventoryStats.Text = string.format("%d / %d fish  •  total value $%s", state.carried or 0, state.maxCarried or 0, formatCash(totalValue))

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
		if not fish then
			continue
		end
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
	Remotes.RequestStoreFish:InvokeServer()
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
-- Collection book panel (TASK 7.3 / it3.3)
--   - RequestCollection remote returns the COLL-04-safe book payload.
--   - Discovered species show name, rarity, value, income.
--   - Undiscovered species show a silhouette and '???' with only a rarity hint.
-- ============================================================
local collectionPanel, collectionContent, collectionClose = makePanel("COLLECTION", UI.warn, UDim2.new(0, 520, 0, 560))

local collectionProgress = makeLabel(collectionContent, {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "",
	Font = FONT_MED,
	TextSize = IS_MOBILE and 14 or 13,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local collectionProgressBar = Instance.new("Frame")
collectionProgressBar.Name = "ProgressBar"
collectionProgressBar.Size = UDim2.new(1, 0, 0, 10)
collectionProgressBar.Position = UDim2.new(0, 0, 0, 24)
collectionProgressBar.BackgroundColor3 = UI.surfaceHi
collectionProgressBar.ZIndex = 26
collectionProgressBar.Parent = collectionContent
corner(collectionProgressBar, 5)
stroke(collectionProgressBar, 0.9)

local collectionProgressFill = Instance.new("Frame")
collectionProgressFill.Name = "ProgressFill"
collectionProgressFill.Size = UDim2.new(0, 0, 1, 0)
collectionProgressFill.BackgroundColor3 = UI.warn
collectionProgressFill.ZIndex = 27
collectionProgressFill.Parent = collectionProgressBar
corner(collectionProgressFill, 5)
vGradient(collectionProgressFill, Color3.fromRGB(255, 205, 92), UI.warn)

local collectionList = Instance.new("ScrollingFrame")
collectionList.Name = "CollectionList"
-- Fill the rest of the content below the progress bar (y=44) with a small
-- bottom margin. Unlike the inventory panel, there is no bottom button.
collectionList.Size = UDim2.new(1, 0, 1, -56)
collectionList.Position = UDim2.new(0, 0, 0, 44)
collectionList.BackgroundTransparency = 1
collectionList.ScrollBarThickness = 4
collectionList.ScrollBarImageColor3 = UI.textFaint
collectionList.CanvasSize = UDim2.new(0, 0, 0, 0)
collectionList.AutomaticCanvasSize = Enum.AutomaticSize.Y
collectionList.ZIndex = 26
collectionList.Parent = collectionContent

local collectionListLayout = Instance.new("UIListLayout")
collectionListLayout.Padding = UDim.new(0, 14)
collectionListLayout.SortOrder = Enum.SortOrder.LayoutOrder
collectionListLayout.Parent = collectionList

local collectionBookData = nil
local lastCollectionSignature = nil

local function clearCollectionList()
	for _, child in ipairs(collectionList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function makeCollectionCard(parent, order, data, discovered)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, IS_MOBILE and 138 or 146, 0, IS_MOBILE and 130 or 126)
	card.BackgroundColor3 = discovered and UI.surface or Color3.fromRGB(16, 24, 36)
	card.BackgroundTransparency = 0.1
	card.LayoutOrder = order
	card.ZIndex = 26
	card.Parent = parent
	corner(card, 12)
	stroke(card, 0.9)

	local rarityColor = RARITY_COLORS[data.rarity] or UI.textDim
	if discovered then
		local topBar = Instance.new("Frame")
		topBar.Size = UDim2.new(1, 0, 0, 6)
		topBar.BackgroundColor3 = rarityColor
		topBar.ZIndex = 27
		topBar.Parent = card
		corner(topBar, 6)

		local icon = Instance.new("Frame")
		icon.Size = UDim2.new(0, 48, 0, 48)
		icon.Position = UDim2.new(0.5, -24, 0, 18)
		icon.BackgroundColor3 = UI.surfaceHi
		icon.ZIndex = 27
		icon.Parent = card
		corner(icon, 999)
		makeLabel(icon, { Size = UDim2.new(1, 0, 1, 0), Text = "F", Font = FONT_HEAD, TextSize = 26, TextColor3 = rarityColor, ZIndex = 28 })

		makeLabel(card, { Size = UDim2.new(1, -12, 0, 20), Position = UDim2.new(0, 6, 0, 68), Text = data.displayName, Font = FONT_BOLD, TextSize = 14, TextColor3 = UI.text, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 27 })
		makeLabel(card, { Size = UDim2.new(1, -12, 0, 16), Position = UDim2.new(0, 6, 0, 106), Text = string.format("$%d  •  $%.1f/min", data.baseSellValue or 0, data.incomePerMinute or 0), Font = FONT_BODY, TextSize = 11, TextColor3 = UI.textDim, ZIndex = 27 })

		local tag = Instance.new("Frame")
		tag.Size = UDim2.new(0, 74, 0, 18)
		tag.Position = UDim2.new(0, 6, 0, 88)
		tag.BackgroundColor3 = rarityColor
		tag.BackgroundTransparency = 0.78
		tag.ZIndex = 27
		tag.Parent = card
		corner(tag, 5)
		makeLabel(tag, { Size = UDim2.new(1, 0, 1, 0), Text = string.upper(data.rarity or "?"), Font = FONT_BOLD, TextSize = 10, TextColor3 = rarityColor, ZIndex = 28 })
	else
		local icon = Instance.new("Frame")
		icon.Size = UDim2.new(0, 48, 0, 48)
		icon.Position = UDim2.new(0.5, -24, 0, 26)
		icon.BackgroundColor3 = UI.surfaceHi
		icon.BackgroundTransparency = 0.6
		icon.ZIndex = 27
		icon.Parent = card
		corner(icon, 999)
		makeLabel(icon, { Size = UDim2.new(1, 0, 1, 0), Text = "?", Font = FONT_HEAD, TextSize = 28, TextColor3 = UI.textFaint, ZIndex = 28 })

		makeLabel(card, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 78), Text = "???", Font = FONT_BOLD, TextSize = 16, TextColor3 = UI.textFaint, ZIndex = 27 })
		makeLabel(card, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 98), Text = string.upper(data.rarity or "Unknown") .. " FISH", Font = FONT_BODY, TextSize = 11, TextColor3 = rarityColor, ZIndex = 27 })
	end
	return card
end

local function makeMilestoneRow(parent, order, milestone)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = UI.surface
	row.BackgroundTransparency = 0.1
	row.LayoutOrder = order
	row.ZIndex = 26
	row.Parent = parent
	corner(row, 10)
	stroke(row, 0.9)

	makeLabel(row, {
		Size = UDim2.new(1, -100, 0, 20),
		Position = UDim2.new(0, 10, 0, 6),
		Text = milestone.label,
		Font = FONT_BOLD,
		TextSize = 14,
		TextColor3 = UI.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})

	makeLabel(row, {
		Size = UDim2.new(1, -100, 0, 16),
		Position = UDim2.new(0, 10, 0, 26),
		Text = string.format("%d / %d", milestone.have or 0, milestone.need or 0),
		Font = FONT_BODY,
		TextSize = 12,
		TextColor3 = UI.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 27,
	})

	if milestone.claimed then
		makeLabel(row, {
			Size = UDim2.new(0, 80, 0, 28),
			Position = UDim2.new(1, -90, 0.5, -14),
			Text = "CLAIMED",
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = UI.good,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
	elseif milestone.complete then
		local claimBtn = makeButton(row, {
			Size = UDim2.new(0, IS_MOBILE and 96 or 80, 0, IS_MOBILE and 44 or 32),
			Position = UDim2.new(1, IS_MOBILE and -106 or -90, 0.5, IS_MOBILE and -22 or -16),
			Text = "CLAIM",
			Font = FONT_BOLD,
			TextSize = 12,
			BackgroundColor3 = UI.warn,
			ZIndex = 27,
		})
		claimBtn.Activated:Connect(function()
			local result = Remotes.ClaimCollectionReward:InvokeServer(milestone.id)
			if result and result.ok then
				milestone.claimed = true
				-- The signature is based on discovered/total counts, which don't
				-- change when claiming, so invalidate it to force a re-render.
				-- Server fires its own notification via remotes.notify, so no
				-- duplicate client-side showNotification here.
				lastCollectionSignature = nil
				renderCollection()
			elseif result and result.reason then
				showNotification("Could not claim: " .. tostring(result.reason), UI.bad)
			end
		end)
	else
		makeLabel(row, {
			Size = UDim2.new(0, 80, 0, 28),
			Position = UDim2.new(1, -90, 0.5, -14),
			Text = "LOCKED",
			Font = FONT_BOLD,
			TextSize = 12,
			TextColor3 = UI.textFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
	end

	return row
end

local function renderCollection()
	if not collectionBookData then
		return
	end
	local book = collectionBookData
	local signature = (book.discoveredCount or 0) .. "/" .. (book.totalSpecies or 0)
	if signature == lastCollectionSignature then
		return
	end
	lastCollectionSignature = signature
	clearCollectionList()

	collectionProgress.Text = string.format("%d / %d species discovered", book.discoveredCount or 0, book.totalSpecies or 0)
	local progress = (book.totalSpecies or 0) > 0 and (book.discoveredCount or 0) / (book.totalSpecies or 0) or 0
	collectionProgressFill.Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)

	if not book.ordered or #book.ordered == 0 then
		makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 44), Text = "No species catalogued yet.", Font = FONT_BODY, TextSize = 14, TextColor3 = UI.textFaint, LayoutOrder = 1, ZIndex = 26 })
		return
	end

	local currentRarity = nil
	local rarityGrid = nil
	local order = 1

	for i, speciesId in ipairs(book.ordered) do
		local data = book.discovered[speciesId] or book.undiscovered[speciesId]
		if data then
			if data.rarity ~= currentRarity then
				currentRarity = data.rarity
				makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 20), Text = string.upper(currentRarity or "Unknown"), Font = FONT_BOLD, TextSize = 12, TextColor3 = RARITY_COLORS[currentRarity] or UI.textDim, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 26 })
				order += 1

				rarityGrid = Instance.new("Frame")
				rarityGrid.Name = currentRarity .. "Grid"
				rarityGrid.Size = UDim2.new(1, 0, 0, 0)
				rarityGrid.AutomaticSize = Enum.AutomaticSize.Y
				rarityGrid.BackgroundTransparency = 1
				rarityGrid.LayoutOrder = order
				rarityGrid.ZIndex = 26
				rarityGrid.Parent = collectionList
				order += 1

				local gridLayout = Instance.new("UIGridLayout")
				gridLayout.CellSize = UDim2.new(0, IS_MOBILE and 138 or 146, 0, IS_MOBILE and 130 or 126)
				gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
				gridLayout.FillDirection = Enum.FillDirection.Horizontal
				gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
				gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
				gridLayout.Parent = rarityGrid
			end
			makeCollectionCard(rarityGrid, i, data, book.discovered[speciesId] ~= nil)
		end
	end

	-- Milestones section
	order += 1
	makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 20), Text = "MILESTONES", Font = FONT_BOLD, TextSize = 12, TextColor3 = UI.warn, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 26 })
	order += 1

	if book.milestones and #book.milestones > 0 then
		for _, milestone in ipairs(book.milestones) do
			makeMilestoneRow(collectionList, order, milestone)
			order += 1
		end
	else
		makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 44), Text = "No milestones available.", Font = FONT_BODY, TextSize = 14, TextColor3 = UI.textFaint, LayoutOrder = order, ZIndex = 26 })
	end
end

local function toggleCollectionPanel()
	if activePanel == collectionPanel then
		hidePanels()
		return
	end
	showPanel(collectionPanel)
	local book = Remotes.RequestCollection:InvokeServer()
	if book and book.ok then
		collectionBookData = book
		renderCollection()
	elseif book and book.reason == "rate_limited" then
		if collectionBookData then
			renderCollection()
		else
			showNotification("Collection book loading too fast — try again.", UI.warn)
		end
	else
		showNotification("Collection book unavailable: " .. tostring(book and book.reason or "unknown"), UI.bad)
	end
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
-- "capacity", but the RequestPurchaseUpgrade handler rejects "capacity" (bad_kind) — so
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
		local result = Remotes.RequestPurchaseUpgrade:InvokeServer(entry.kind, entry.level)
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
			currentLevel = state.rodLevel or 1
		elseif entry.kind == "bait" then
			currentLevel = state.baitLevel or 1
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
-- Raid panel (TASK 8.12 / gdj.12)
-- Global window countdown, opt-in toggle, target selection, raid attempt.
-- ============================================================
local raidPanel, raidContent, raidClose = makePanel("RAID WATERS", UI.bad, UDim2.new(0, 440, 0, 520))

local raidStatusLabel = makeLabel(raidContent, {
	Size = UDim2.new(1, 0, 0, 48),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "Raid waters are calm",
	Font = FONT_HEAD,
	TextSize = IS_MOBILE and 18 or 20,
	TextColor3 = UI.text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	ZIndex = 26,
})

local raidCountdownLabel = makeLabel(raidContent, {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, 50),
	Text = "Next window: --",
	Font = FONT_MED,
	TextSize = 14,
	TextColor3 = UI.textDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local raidOptInPanelButton = makeButton(raidContent, {
	Size = UDim2.new(1, 0, 0, IS_MOBILE and 44 or 36),
	-- thj.5: keep the bottom edge at 114 so the label at y=116 keeps its 2px gap.
	Position = UDim2.new(0, 0, 0, IS_MOBILE and 70 or 78),
	Text = "RAID OPT-IN: OFF",
	BackgroundColor3 = UI.surfaceHi,
	ZIndex = 26,
})

makeLabel(raidContent, {
	Size = UDim2.new(1, -100, 0, 16),
	Position = UDim2.new(0, 0, 0, 116),
	Text = "TARGETS",
	Font = FONT_BOLD,
	TextSize = 10,
	TextColor3 = UI.textFaint,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local raidTargetList = Instance.new("ScrollingFrame")
raidTargetList.Size = UDim2.new(1, 0, 1, -146)
raidTargetList.Position = UDim2.new(0, 0, 0, 144)
raidTargetList.BackgroundTransparency = 1
raidTargetList.ScrollBarThickness = 4
raidTargetList.ScrollBarImageColor3 = UI.textFaint
raidTargetList.CanvasSize = UDim2.new(0, 0, 0, 0)
raidTargetList.AutomaticCanvasSize = Enum.AutomaticSize.Y
raidTargetList.ZIndex = 26
raidTargetList.Parent = raidContent

local raidTargetLayout = Instance.new("UIListLayout")
raidTargetLayout.Padding = UDim.new(0, 8)
raidTargetLayout.SortOrder = Enum.SortOrder.LayoutOrder
raidTargetLayout.Parent = raidTargetList

local raidRefreshButton = makeButton(raidContent, {
	Size = UDim2.new(0, IS_MOBILE and 100 or 90, 0, IS_MOBILE and 36 or 28),
	Position = UDim2.new(1, IS_MOBILE and -104 or -94, 0, IS_MOBILE and 104 or 112),
	Text = "REFRESH",
	BackgroundColor3 = UI.surfaceHi,
	TextColor3 = UI.text,
	TextSize = 11,
	ZIndex = 26,
})

local raidTargets = {}
local raidInProgress = false


local function renderRaidTargets(data)
	for _, child in ipairs(raidTargetList:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	if not data or not data.ok then
		makeLabel(raidTargetList, {
			Size = UDim2.new(1, 0, 0, 48),
			Text = data and data.reason or "Could not load targets.",
			Font = FONT_MED,
			TextSize = 14,
			TextColor3 = UI.textDim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
		return
	end
	if not data.canRaid then
		local reasonText = {
			window_closed = "No raid window is open right now.",
			not_opted_in = "You must opt in to raids to see targets.",
			new_player_protected = "New players are protected from raids until 10 catches or an upgrade.",
			stunned = "You are stunned and cannot raid.",
			attacker_cooldown = "Raid cooldown active — try again soon.",
		}[data.reason] or ("Cannot raid: " .. tostring(data.reason))
		makeLabel(raidTargetList, {
			Size = UDim2.new(1, 0, 0, 48),
			Text = reasonText,
			Font = FONT_MED,
			TextSize = 14,
			TextColor3 = UI.textDim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
		return
	end
	if not data.targets or #data.targets == 0 then
		makeLabel(raidTargetList, {
			Size = UDim2.new(1, 0, 0, 48),
			Text = "No opted-in targets available.",
			Font = FONT_MED,
			TextSize = 14,
			TextColor3 = UI.textDim,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
		return
	end
	for i, target in ipairs(data.targets) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, IS_MOBILE and 68 or 60)
		row.BackgroundColor3 = UI.surface
		row.BackgroundTransparency = 0.15
		row.LayoutOrder = i
		row.ZIndex = 26
		row.Parent = raidTargetList
		corner(row, 12)
		stroke(row, 0.9)

		makeLabel(row, {
			Size = UDim2.new(1, -110, 0, 20),
			Position = UDim2.new(0, 12, 0, 8),
			Text = target.displayName or target.name or "Unknown",
			Font = FONT_BOLD,
			TextSize = 14,
			TextColor3 = UI.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 27,
		})
		makeLabel(row, {
			Size = UDim2.new(1, -110, 0, 16),
			Position = UDim2.new(0, 12, 0, 28),
			Text = string.format("Dock %d  •  %d stealable fish", target.dockIndex or 0, target.stealableCount or 0),
			Font = FONT_BODY,
			TextSize = 12,
			TextColor3 = UI.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 27,
		})
		local attempt = makeButton(row, {
			Size = UDim2.new(0, IS_MOBILE and 104 or 92, 0, IS_MOBILE and 44 or 32),
			Position = UDim2.new(1, IS_MOBILE and -114 or -102, 0.5, IS_MOBILE and -22 or -16),
			Text = "RAID",
			BackgroundColor3 = UI.bad,
			TextSize = 12,
			ZIndex = 27,
		})
		attempt.Activated:Connect(function()
			if raidInProgress then
				return
			end
			raidInProgress = true
			local result = Remotes.RequestRaidAttempt:InvokeServer(target.userId)
			if not result or not result.ok then
				raidInProgress = false
				local failReason = {
					window_closed = "The raid window closed.",
					not_opted_in = "You are not opted in.",
					new_player_protected = "New players cannot raid.",
					stunned = "You are stunned.",
					attacker_cooldown = "Raid cooldown active.",
					victim_cooldown = "You recently raided this dock.",
					loss_capped = "This dock has lost too much this window.",
					target_unavailable = "Target left the harbor.",
					target_no_longer_eligible = "Target is no longer eligible.",
					no_stealable_fish = "No fish left to steal.",
					safe_harbor = "Target is in the Safe Harbor zone.",
					raid_in_progress = "You already have a raid in progress.",
				}[result and result.reason] or "Could not start raid."
				showNotification(failReason, UI.bad)
				return
			end
			startRaidMinigame(result)
		end)
	end
end

local function updateRaidPanelStatic()
	if not state then
		return
	end
	-- Update status header from local cached window state.
	if raidWindow.open then
		raidStatusLabel.Text = "RAID WATERS OPEN"
		raidStatusLabel.TextColor3 = UI.bad
	else
		raidStatusLabel.Text = "Raid waters are calm"
		raidStatusLabel.TextColor3 = UI.text
	end
	-- Update opt-in toggle mirror.
	if state.raidOptIn then
		raidOptInPanelButton.Text = "RAID OPT-IN: ON (can be targeted)"
		raidOptInPanelButton.BackgroundColor3 = UI.bad
		raidOptInPanelButton.TextColor3 = UI.ink
	else
		local catches = state.totalCatches or 0
		local hasUpgrade = (state.upgradeLevel or 1) > 1
		if not hasUpgrade and catches < 10 then
			raidOptInPanelButton.Text = string.format("RAID OPT-IN: LOCKED (%d/10 catches or upgrade)", catches)
			raidOptInPanelButton.BackgroundColor3 = UI.surfaceHi
			raidOptInPanelButton.TextColor3 = UI.textFaint
		else
			raidOptInPanelButton.Text = "RAID OPT-IN: OFF (safe)"
			raidOptInPanelButton.BackgroundColor3 = UI.surfaceHi
			raidOptInPanelButton.TextColor3 = UI.text
		end
	end
end

local function refreshRaidPanel()
	updateRaidPanelStatic()
	-- Fetch targets from server asynchronously (window open/close or manual refresh).
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.GetRaidTargets:InvokeServer()
		end)
		if ok then
			raidTargets = data or {}
			if activePanel == raidPanel then
				renderRaidTargets(raidTargets)
			end
		end
	end)
end

local function toggleRaidPanel()
	if activePanel == raidPanel then
		hidePanels()
		return
	end
	showPanel(raidPanel)
	refreshRaidPanel()
end

-- ============================================================
-- Raid timing minigame overlay (TASK 8.5b / gdj.14)
-- ============================================================
local raidMinigameFrame = Instance.new("Frame")
raidMinigameFrame.Name = "RaidMinigame"
raidMinigameFrame.Size = IS_MOBILE and UDim2.new(1, -24, 0, 132) or UDim2.new(0, 400, 0, 112)
raidMinigameFrame.Position = UDim2.new(0.5, 0, IS_MOBILE and 0.42 or 0.58, 0)
raidMinigameFrame.BackgroundColor3 = UI.bg
raidMinigameFrame.BackgroundTransparency = 0.08
raidMinigameFrame.Visible = false
raidMinigameFrame.ZIndex = 40
raidMinigameFrame.Parent = screenGui
corner(raidMinigameFrame, 16)
stroke(raidMinigameFrame, 0.8)
vGradient(raidMinigameFrame, Color3.fromRGB(26, 38, 57), UI.bg)

makeLabel(raidMinigameFrame, {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 10),
	Text = IS_MOBILE and "TAP IN THE GREEN ZONE!" or "CLICK IN THE GREEN ZONE!",
	Font = FONT_HEAD,
	TextSize = IS_MOBILE and 15 or 16,
	TextColor3 = UI.warn,
	ZIndex = 41,
})

local raidBarTrack = Instance.new("Frame")
raidBarTrack.Size = UDim2.new(1, -24, 0, IS_MOBILE and 52 or 40)
raidBarTrack.Position = UDim2.new(0, 12, 0, IS_MOBILE and 52 or 48)
raidBarTrack.BackgroundColor3 = UI.surface
raidBarTrack.ZIndex = 41
raidBarTrack.Parent = raidMinigameFrame
corner(raidBarTrack, 10)
stroke(raidBarTrack, 0.85)

local raidGoodZone = Instance.new("Frame")
raidGoodZone.Size = UDim2.new(0.3, 0, 1, 0)
raidGoodZone.Position = UDim2.new(0.35, 0, 0, 0)
raidGoodZone.BackgroundColor3 = UI.good
raidGoodZone.BackgroundTransparency = 0.45
raidGoodZone.ZIndex = 42
raidGoodZone.Parent = raidBarTrack
corner(raidGoodZone, 8)
stroke(raidGoodZone, 0.5, UI.good, 1.5)

local raidPerfectZone = Instance.new("Frame")
raidPerfectZone.Size = UDim2.new(0.4, 0, 1, -8)
raidPerfectZone.Position = UDim2.new(0.5, 0, 0, 4)
raidPerfectZone.BackgroundColor3 = Color3.fromRGB(134, 239, 172)
raidPerfectZone.BackgroundTransparency = 0.12
raidPerfectZone.ZIndex = 43
raidPerfectZone.Parent = raidGoodZone
corner(raidPerfectZone, 7)

makeLabel(raidMinigameFrame, {
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.new(0, 12, 1, -20),
	Text = "PERFECT = HIGH CHANCE  •  GOOD = FAIR  •  MISS = LOW",
	Font = FONT_BOLD,
	TextSize = 9,
	TextColor3 = UI.textFaint,
	ZIndex = 41,
})

local raidMarker = Instance.new("Frame")
raidMarker.Size = UDim2.new(0, 5, 1, 6)
raidMarker.Position = UDim2.new(0, 0, 0, -3)
raidMarker.BackgroundColor3 = Color3.new(1, 1, 1)
raidMarker.ZIndex = 43
raidMarker.Parent = raidBarTrack
corner(raidMarker, 3)

local raidMarkerGlow = Instance.new("Frame")
raidMarkerGlow.Size = UDim2.new(0, 15, 1, 10)
raidMarkerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
raidMarkerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
raidMarkerGlow.BackgroundColor3 = UI.accentSoft
raidMarkerGlow.BackgroundTransparency = 0.75
raidMarkerGlow.ZIndex = 42
raidMarkerGlow.Parent = raidMarker
corner(raidMarkerGlow, 8)

local raidMinigameTween = nil
local raidMinigameInputConn = nil
local raidMinigameDuration = 0

local function stopRaidMinigame()
	raidMinigameFrame.Visible = false
	if raidMinigameTween then
		raidMinigameTween:Cancel()
		raidMinigameTween = nil
	end
	if raidMinigameInputConn then
		raidMinigameInputConn:Disconnect()
		raidMinigameInputConn = nil
	end
end

local function startRaidMinigame(challenge)
	raidInProgress = true
	local goodStart = challenge.goodStart or 0.35
	local goodEnd = challenge.goodEnd or 0.65
	local goodWidth = goodEnd - goodStart
	raidGoodZone.Size = UDim2.new(goodWidth, 0, 1, 0)
	raidGoodZone.Position = UDim2.new(goodStart, 0, 0, 0)
	local perfectStart = challenge.perfectStart or 0.44
	local perfectEnd = challenge.perfectEnd or 0.56
	local pWidth = perfectEnd - perfectStart
	local pCenter = (perfectStart + perfectEnd) / 2
	local relWidth = goodWidth > 0 and (pWidth / goodWidth) or 0.4
	local relCenter = goodWidth > 0 and ((pCenter - goodStart) / goodWidth) or 0.5
	raidPerfectZone.Size = UDim2.new(math.clamp(relWidth, 0, 1), 0, 1, -8)
	raidPerfectZone.Position = UDim2.new(math.clamp(relCenter, 0, 1), 0, 0, 4)

	raidMinigameFrame.Visible = true
	raidMarker.Position = UDim2.new(0, 0, 0, -3)
	raidMinigameDuration = challenge.durationSeconds or 8
	raidMinigameTween = TweenService:Create(
		raidMarker,
		TweenInfo.new(raidMinigameDuration, Enum.EasingStyle.Linear),
		{ Position = UDim2.new(1, -5, 0, -3) }
	)
	raidMinigameTween:Play()

	-- Expire the overlay if the player never clicks (matching the server deadline).
	task.delay(raidMinigameDuration, function()
		if raidMinigameFrame.Visible then
			stopRaidMinigame()
			raidInProgress = false
			showNotification("Too slow! The raid window of opportunity passed...", UI.warn)
		end
	end)

	raidMinigameInputConn = UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if not raidMinigameFrame.Visible then
				return
			end
			local markerPos = raidMarker.Position.X.Scale
			stopRaidMinigame()
			task.spawn(function()
				local ok, result = pcall(function()
					return Remotes.SubmitRaidResult:InvokeServer(markerPos)
				end)
				raidInProgress = false
				if ok and result then
					if result.success then
						showNotification(string.format("Heist %s! Stole a %s %s worth $%d.", result.tier or "", result.rarity or "", result.speciesId or "", result.value or 0), UI.good)
					elseif result.ok and not result.success then
						showNotification("Heist failed — the fish slipped away.", UI.warn)
					end
				end
				refreshRaidPanel()
			end)
		end
	end)
end

-- ============================================================
-- Global raid window countdown HUD banner
-- ============================================================
local raidBanner = Instance.new("Frame")
raidBanner.Name = "RaidBanner"
-- Desktop: top-center banner. Mobile: top-right to avoid overlapping the HUD.
raidBanner.AnchorPoint = IS_MOBILE and Vector2.new(1, 0) or Vector2.new(0.5, 0)
raidBanner.Size = UDim2.new(0, IS_MOBILE and 180 or 340, 0, 36)
raidBanner.Position = IS_MOBILE and UDim2.new(1, -12, 0, SAFE_TOP + 6) or UDim2.new(0.5, 0, 0, SAFE_TOP + 6)
raidBanner.BackgroundColor3 = UI.bg
raidBanner.BackgroundTransparency = 0.12
raidBanner.Visible = false
raidBanner.ZIndex = 18
raidBanner.Parent = screenGui
corner(raidBanner, 999)
stroke(raidBanner, 0.7, UI.bad, 1.5)

local raidBannerIcon = Instance.new("Frame")
raidBannerIcon.Size = UDim2.new(0, 8, 0, 8)
raidBannerIcon.Position = UDim2.new(0, 14, 0.5, -4)
raidBannerIcon.BackgroundColor3 = UI.bad
raidBannerIcon.ZIndex = 19
raidBannerIcon.Parent = raidBanner
corner(raidBannerIcon, 999)

local raidBannerLabel = makeLabel(raidBanner, {
	Size = UDim2.new(1, -34, 1, 0),
	Position = UDim2.new(0, 28, 0, 0),
	Text = IS_MOBILE and "RAID OPEN 0:00" or "RAID WATERS OPEN 0:00",
	Font = FONT_BOLD,
	TextSize = 13,
	TextColor3 = UI.bad,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 19,
})
-- ============================================================
-- Action bar
--   Desktop: bottom-center pill bar with keyboard hint chips.
--   Mobile: right-edge thumb-zone stack of large round buttons.
-- ============================================================
local ACTIONS = {
	{ id = "fish", label = "FISH", short = "FISH", key = "F", color = UI.good },
	{ id = "store", label = "BAG", short = "BAG", key = "G", color = UI.accent },
	{ id = "collection", label = "BOOK", short = "BOOK", key = "C", color = UI.warn },
	{ id = "aquarium", label = "TANK", short = "TANK", key = "T", color = UI.purple },
	{ id = "quests", label = "QUESTS", short = "QUEST", key = "Q", color = UI.quest },
	{ id = "raid", label = "RAID", short = "RAID", key = "R", color = UI.bad },
	{ id = "boat", label = "BOAT", short = "BOAT", key = "B", color = UI.boat },
}

-- The onboarding prompt sits above the mobile action stack; keep it in sync
-- as the button count changes so it never overlaps the top button.
onboardingPrompt.Position = UDim2.new(0.5, 0, 1, IS_MOBILE and -(#ACTIONS * 70 + 102) or -84)

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
	-- TASK 28.1 (hvfh.8.1): bar width is derived from the content so an
	-- extra action can never silently overflow; on narrow windows the buttons
	-- + font shrink and the short labels kick in below ~700px (no clipping).
	local BAR_BTN_W = 100
	local BAR_BTN_H = 42
	local BAR_BTN_W_MIN = 76
	local BAR_GAP = 8
	local BAR_SIDE_MARGIN = 36
	local BAR_SHORT_VIEWPORT = 700

	local function barWidthFor(btnW)
		return #ACTIONS * btnW + (#ACTIONS - 1) * BAR_GAP
	end

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -18)
	bar.Size = UDim2.new(0, barWidthFor(BAR_BTN_W), 0, 58)
	bar.BackgroundColor3 = UI.bg
	bar.BackgroundTransparency = 0.2
	bar.Parent = screenGui
	corner(bar, 16)
	stroke(bar, 0.85)

	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, BAR_GAP)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bar

	local desktopBtns = {}
	for i, action in ipairs(ACTIONS) do
		local btn = makeButton(bar, {
			Size = UDim2.new(0, BAR_BTN_W, 0, BAR_BTN_H),
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
		desktopBtns[i] = { btn = btn, label = textLabel, action = action }
	end

	-- Fit the bar to the current viewport: below full+2*margin (~820px) shrink
	-- button width (floor 76) and font; below 700px use the short labels.
	local function layoutDesktopBar(viewportW)
		local cam = workspace.CurrentCamera
		viewportW = viewportW or (cam and cam.ViewportSize.X) or 1920
		local btnW = BAR_BTN_W
		local fullW = barWidthFor(BAR_BTN_W)
		if viewportW < fullW + 2 * BAR_SIDE_MARGIN then
			btnW = math.floor((viewportW - 2 * BAR_SIDE_MARGIN - (#ACTIONS - 1) * BAR_GAP) / #ACTIONS + 0.5)
			btnW = math.max(BAR_BTN_W_MIN, math.min(BAR_BTN_W, btnW))
		end
		local useShort = viewportW < BAR_SHORT_VIEWPORT
		local fontScale = (btnW - BAR_BTN_W_MIN) / (BAR_BTN_W - BAR_BTN_W_MIN)
		local textSize = 12 + math.floor(2 * fontScale + 0.5)
		bar.Size = UDim2.new(0, barWidthFor(btnW), 0, 58)
		for _, entry in ipairs(desktopBtns) do
			entry.btn.Size = UDim2.new(0, btnW, 0, BAR_BTN_H)
			entry.label.Text = useShort and entry.action.short or entry.action.label
			entry.label.TextSize = textSize
		end
	end

	layoutDesktopBar()

	local viewportConn
	local function bindViewport(cam)
		if not cam then return end
		if viewportConn then viewportConn:Disconnect() end
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			layoutDesktopBar(cam.ViewportSize.X)
		end)
	end
	bindViewport(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewport(workspace.CurrentCamera)
		layoutDesktopBar()
	end)
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

-- ============================================================
-- TASK 22.1 (hvfh.2.1): FISH button state machine.
-- Replaces the binary `casting`-flag label with three visually
-- distinct states driven by server events (never per-frame churn):
--   idle        "FISH"            green,  static
--   waiting     "WAITING..."/"..." muted,  slow stroke pulse
--   bite-ready  "FISH ON!"/"FISH!" warn,   fast stroke pulse
-- Transition edges (verified against server event order):
--   idle      -> waiting     on CastState(true)
--   waiting   -> idle        on CastState(false) with no bite
--   *         -> bite-ready  on BiteEvent, REGARDLESS of flag state
--   (CastState(false) fires at FishingService:187 BEFORE BiteEvent at
--    :213, so the transient idle is immediately overridden — bite-ready
--    survives that ordering rather than being lost to the early false.)
--   bite-ready -> idle       when the LOCAL minigame closes (tap or
--   timeout via onMinigameTap / runMinigame expiry) — NOT on any
--   CastState event; none is coming.
-- `casting` stays for the doFish + cast-input guards; it no longer
-- drives the label. The pulse tween is mode-tracked so re-rendering on
-- state pushes never restarts it (renderFishButton is idempotent).
-- ============================================================
local fishState = "idle" -- "idle" | "waiting" | "bite-ready"
local fishPulseTween = nil
local fishPulseMode = "none" -- "none" | "slow" | "fast"
local fishStrokeDefaultColor = nil
local fishStrokeDefaultTrans = nil

local function fishStroke()
	local btn = actionButtons.fish
	return btn and btn:FindFirstChildOfClass("UIStroke")
end

local function stopFishPulse()
	if fishPulseTween then
		fishPulseTween:Cancel()
		fishPulseTween = nil
	end
	fishPulseMode = "none"
end

local function ensureFishPulse(mode, baseTrans, amp)
	if fishPulseMode == mode and fishPulseTween then
		return
	end
	stopFishPulse()
	if mode == "none" then
		return
	end
	local s = fishStroke()
	if not s then
		return
	end
	local dur = mode == "fast" and 0.32 or 0.85
	fishPulseTween = TweenService:Create(
		s,
		TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = math.max(0, baseTrans - amp) }
	)
	fishPulseTween:Play()
	fishPulseMode = mode
end

local function renderFishButton()
	local btn = actionButtons.fish
	if not btn then
		return
	end
	local lbl = actionButtons.fish_label or btn
	local s = fishStroke()
	if s and not fishStrokeDefaultColor then
		fishStrokeDefaultColor = s.Color
		fishStrokeDefaultTrans = s.Transparency
	end
	local labelText, labelColor, strokeColor, baseTrans, pulseMode
	if fishState == "bite-ready" then
		labelText = IS_MOBILE and "FISH!" or "FISH ON!"
		labelColor = UI.warn
		strokeColor = UI.warn
		baseTrans = fishStrokeDefaultTrans or 0.5
		pulseMode = "fast"
	elseif fishState == "waiting" then
		labelText = IS_MOBILE and "..." or "WAITING..."
		labelColor = UI.textFaint
		strokeColor = UI.textFaint
		baseTrans = fishStrokeDefaultTrans or 0.6
		pulseMode = "slow"
	else
		labelText = "FISH"
		labelColor = UI.good
		strokeColor = fishStrokeDefaultColor or UI.good
		baseTrans = fishStrokeDefaultTrans or 0.6
		pulseMode = "none"
	end
	lbl.Text = labelText
	lbl.TextColor3 = labelColor
	if s then
		s.Color = strokeColor
		s.Transparency = baseTrans
	end
	ensureFishPulse(pulseMode, baseTrans, pulseMode == "fast" and 0.4 or 0.3)
end

local function setFishState(newState)
	fishState = newState
	renderFishButton()
end

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
	-- TASK 24.1 (hvfh.4.1): rate + pulsing claim-green "ready" segment (the
	-- pulse loop re-asserts it while ready > 0; this covers every state push).
	updateIncomeLine()
	carryLabel.Text = string.format("On line: %d / %d fish", state.carried, state.maxCarried)
	-- TASK 4.4 (0cw.4 / wqw.18): live-update the inventory panel on every
	-- state push (catch, per-fish sell/store, bulk actions) while it is open.
	if activePanel == inventoryPanel then
		renderInventory()
	end

	renderFishButton()

	local boatLbl = actionButtons.boat_label or actionButtons.boat
	boatLbl.Text = state.hasBoat and (IS_MOBILE and "SAIL" or "SAILING") or "BOAT"

	local rodLevel = state.rodLevel or 1
	local baitLevel = state.baitLevel or 1
	local rodName = (GameConfig.Rods[rodLevel] and GameConfig.Rods[rodLevel].name) or "Basic Rod"
	local baitName = (GameConfig.Baits[baitLevel] and GameConfig.Baits[baitLevel].name) or "Worms"
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

	-- TASK 25.1 (hvfh.5.1): disarm the SELL ALL confirm if the payout
	-- changed since arming (new catch/store/sell/lock toggle) so the
	-- confirmed number is never stale.
	if sellArmed and computeSellPayout() ~= sellArmPayout then
		disarmSellButton()
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

	-- TASK 9.4 (0jc.4): sell-vs-store comparison prompt on first catch.
	-- Detect a carried-count increase (new fish caught) and show the
	-- comparison once, unless the player has already seen/dismissed it.
	local carriedCount = state.carried or 0
	local carriedFish = state.carriedFish or {}

	-- If the prompt is open but its target fish is no longer in the carried
	-- inventory (player sold/stored it through another path), hide it and allow
	-- it to reappear on the next catch so the comparison is still presented.
	if sellStorePrompt.Visible and sellStoreTargetFish then
		local targetStillPresent = false
		for _, fish in ipairs(carriedFish) do
			if fish and fish.InstanceId == sellStoreTargetFish.InstanceId then
				targetStillPresent = true
				break
			end
		end
		if not targetStillPresent then
			hideSellStorePrompt()
			sellStorePromptShown = false
		end
	end

	if carriedCount > lastCarriedCount
		and not sellStorePromptShown
		and not (state.onboarding or {}).HasSeenSellStoreComparison
		and not sellStorePrompt.Visible then
		local firstFish = carriedFish[1]
		if firstFish then
			showSellStorePrompt(firstFish)
		end
	end
	lastCarriedCount = carriedCount
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

local minigameActive = false
local minigameStartTime = 0
local minigameWindow = 3.0
-- Half-width of the current target zone, refreshed per cast from the
-- equipped rod's minigameZoneSize (TASK 2.3). onMinigameTap validates
-- against this — NOT the hardcoded [0.35, 0.65] band — so a wider-zone
-- rod's advantage is actually visible to the player.
local minigameZoneHalfWidth = 0.15

-- Animate the marker sweeping back and forth
local function runMinigame(windowSeconds)
	if minigameActive then return end
	if type(windowSeconds) ~= "number" or windowSeconds <= 0 then
		showNotification("Fishing sync hiccup — try casting again.", UI.warn)
		return
	end
	minigameActive = true
	minigameWindow = windowSeconds
	minigameStartTime = os.clock()
	minigameFrame.Visible = true
	-- BiteEvent -> runMinigame reached here, so a bite is really happening:
	-- enter bite-ready now (after the windowSeconds guard, so a bad payload
	-- never sticks the button in bite-ready with no minigame to close it).
	setFishState("bite-ready")

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
				setFishState("idle")
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
	setFishState("idle")
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
		Remotes.RequestCast:FireServer()
	end
end

actionButtons.fish.Activated:Connect(doFish)
aquariumClose.Activated:Connect(hidePanels)
inventoryClose.Activated:Connect(hidePanels)
shopClose.Activated:Connect(hidePanels)
questClose.Activated:Connect(hidePanels)
raidClose.Activated:Connect(hidePanels)
collectionClose.Activated:Connect(hidePanels)
-- TASK 4.4 (0cw.4 / wqw.18): BAG button opens the per-fish inventory panel
-- (bulk store-all remains available via the panel's STORE ALL button).
actionButtons.store.Activated:Connect(toggleInventoryPanel)
-- TASK 7.3 (it3.3): BOOK button opens the collection book panel.
actionButtons.collection.Activated:Connect(toggleCollectionPanel)
-- TASK 8.12 (gdj.12): RAID button opens the raid panel.
actionButtons.raid.Activated:Connect(toggleRaidPanel)
-- TASK 8.12 (gdj.12): refresh + opt-in inside the raid panel.
raidRefreshButton.Activated:Connect(refreshRaidPanel)
raidOptInPanelButton.Activated:Connect(function()
	dismissOnboardingPrompt("raidExplain")
	Remotes.RequestToggleRaidOptIn:InvokeServer()
end)
-- TASK 25.1 (hvfh.5.1): SELL ALL two-step confirmation guard.
-- First tap arms the button with the exact payout + lock-scope; a 3s
-- window gives the player a chance to back out. Second tap fires. Any
-- state push that changes the payout disarms so the number is never stale.
-- sellArmed/sellArmPayout/computeSellPayout are forward-declared above
-- (before render/hidePanels) so those closures see the SAME variables.
sellArmed = false
sellArmPayout = 0
local sellArmTask: any = nil

computeSellPayout = function(): number
	if not state then
		return 0
	end
	local locked = (state.lockedUntil or 0) > 0
	local payout = 0
	for _, fish in ipairs(state.carriedFish or {}) do
		payout += fish.BaseSellValue or 0
	end
	if not locked then
		for _, fish in ipairs(state.storedFish or {}) do
			payout += fish.BaseSellValue or 0
		end
	end
	return payout
end

disarmSellButton = function()
	sellArmed = false
	sellArmPayout = 0
	if sellArmTask then
		local t = sellArmTask
		sellArmTask = nil
		pcall(task.cancel, t)
	end
	sellButton.Text = "SELL ALL"
	sellButton.BackgroundColor3 = UI.good
	sellButton.TextColor3 = UI.ink
end

sellButton.Activated:Connect(function()
	if not state then
		return
	end
	if sellArmed then
		disarmSellButton()
		Remotes.RequestSellFish:InvokeServer()
	else
		local payout = computeSellPayout()
		if payout <= 0 then
			local locked = (state.lockedUntil or 0) > 0
			if locked and (state.liveWellCount or 0) > 0 then
				showNotification("Aquarium is locked — stored fish can't be sold until the lock expires.", Color3.fromRGB(255, 170, 80))
			else
				showNotification("No fish to sell!", Color3.fromRGB(255, 170, 80))
			end
			return
		end
		sellArmed = true
		sellArmPayout = payout
		local locked = (state.lockedUntil or 0) > 0
		if locked then
			sellButton.Text = string.format("SELL BAG $%d? TAP", payout)
		else
			sellButton.Text = string.format("SELL ALL $%d? TAP", payout)
		end
		sellButton.BackgroundColor3 = UI.bad
		sellButton.TextColor3 = UI.ink
		sellArmTask = task.delay(3, function()
			disarmSellButton()
		end)
	end
end)
lockButton.Activated:Connect(function()
	Remotes.RequestActivateLock:InvokeServer()
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
	Remotes.RequestClaimIncome:InvokeServer()
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
	elseif input.KeyCode == Enum.KeyCode.C then
		toggleCollectionPanel()
	elseif input.KeyCode == Enum.KeyCode.T then
		showPanel(aquariumPanel)
	elseif input.KeyCode == Enum.KeyCode.Q then
		toggleQuestPanel()
	elseif input.KeyCode == Enum.KeyCode.R then
		toggleRaidPanel()
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
	if activePanel == raidPanel then
		updateRaidPanelStatic()
	end
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
local function formatRaidTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function updateRaidCountdown()
	if raidWindow.open then
		raidBanner.Visible = true
		local bannerPrefix = IS_MOBILE and "RAID OPEN " or "RAID WATERS OPEN "
		raidBannerLabel.Text = bannerPrefix .. formatRaidTime(raidWindow.remainingSeconds)
		raidCountdownLabel.Text = "Closes in " .. formatRaidTime(raidWindow.remainingSeconds)
	else
		raidBanner.Visible = false
		raidCountdownLabel.Text = "Next window in " .. formatRaidTime(raidWindow.nextWindowInSeconds)
	end
end

Remotes.RaidWindowChanged.OnClientEvent:Connect(function(isOpen, remainingSeconds, nextWindowInSeconds)
	local wasOpen = raidWindow.open
	raidWindow.open = isOpen == true
	raidWindow.remainingSeconds = remainingSeconds or 0
	raidWindow.nextWindowInSeconds = nextWindowInSeconds or 0
	updateRaidCountdown()
	if activePanel == raidPanel then
		refreshRaidPanel()
	end
	if raidWindow.open and not wasOpen then
		showNotification(
			string.format("RAID WATERS OPEN for %d minutes! Steal fish from other docks while the window lasts.", math.floor(raidWindow.remainingSeconds / 60)),
			Color3.fromRGB(255, 120, 120)
		)
	elseif not raidWindow.open and wasOpen then
		showNotification("Raid waters closed. The harbor is safe... for now.", UI.accentSoft)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if raidWindow.open then
			raidWindow.remainingSeconds = math.max(0, raidWindow.remainingSeconds - 1)
		else
			raidWindow.nextWindowInSeconds = math.max(0, raidWindow.nextWindowInSeconds - 1)
		end
		updateRaidCountdown()
	end
end)

Remotes.CastState.OnClientEvent:Connect(function(isCasting, castTime, hitZone)
	casting = isCasting
	if isCasting then
		fishState = "waiting"
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
		-- CastState(false) with no bite: the cast resolved/cancelled. Only
		-- clear the waiting state — never bite-ready (a BiteEvent may be
		-- arriving in this same deferred callback right after this; clearing
		-- bite-ready here would lose the bite). render() below re-renders.
		if fishState == "waiting" then
			fishState = "idle"
		end
		stopCastOverlay()
	end
	render()
end)

Remotes.BiteEvent.OnClientEvent:Connect(function(zoneId, windowSeconds)
	-- Start the timing minigame when the server says a fish is biting.
	-- The server fires FireClient(player, zoneId, BITE_WINDOW_SECONDS)
	-- (FishingService.lua), so the handler MUST take two params: zoneId
	-- (the triggering fishing zone) and windowSeconds (the authoritative
	runMinigame(windowSeconds)
end)

Remotes.OpenAquarium.OnClientEvent:Connect(function()
	showPanel(aquariumPanel)
end)

-- TASK 24.1 (hvfh.4.1): clicking/tapping the HUD cash card opens the
-- aquarium panel (same toggle semantics as every other panel opener).
hudClick.Activated:Connect(function()
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