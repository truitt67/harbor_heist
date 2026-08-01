local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
-- harborheist-5rcp.3: HapticService removed — the haptic system now uses
-- HapticEffect instances (modern API) instead of the deprecated HapticService.
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

-- harborheist-pytn.1: Animation system integration
-- Provides spring physics, transitions, gestures, and micro-interactions
local AnimationSystem = require(script:WaitForChild("AnimationSystem"))
local Anim = AnimationSystem  -- shorthand for use in UI code

-- harborheist-ncxu: Keyboard navigation system (EPIC 32: Accessibility)
-- Provides Tab/Shift+Tab navigation, Enter/Space activation, focus indicators
local KeyboardNav = require(script:WaitForChild("KeyboardNav"))

-- harborheist-i39g.3: Gradient library (EPIC 35: Visual Polish)
-- Provides named gradient presets for surfaces, accents, status, and rarity.
-- Use Gradients.apply(element, "surface.default") instead of vGradient() for new code.
local Gradients = require(script:WaitForChild("GradientLibrary"))

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
-- TASK 4.4 (0cw.4 / wqw.18): species DisplayName lookup for the inventory panel
local FishDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FishDefinitions"))
-- harborheist-nk22 (EPIC 36): canonical base color palette — single source of
-- truth shared with GradientLibrary. The local `UI` table below sources from
-- this so palette edits live in one place (src/shared/UIPalette.lua).
local UIPalette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIPalette"))
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local Remotes = {}
for _, child in ipairs(remotesFolder:GetChildren()) do
	Remotes[child.Name] = child
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
-- R4 polish #1 (desktop): pointing-hand cursor over interactive buttons.
local playerMouse = player:GetMouse()

-- ============================================================
-- Device profile: hyper-optimize layout per modality.
-- ============================================================
-- Layout mode detection (harborheist-0ci3): compact/standard/wide screens
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Viewport width thresholds for layout modes
local LAYOUT_THRESHOLDS = {
	compact = 1200,   -- < 1200px: single column, compact UI
	standard = 1600,  -- 1200-1600px: standard desktop layout
	wide = 1920,      -- > 1600px: wide screen with side panels
}

-- Detect current layout mode based on viewport width
local function getLayoutMode(viewportW)
	if not viewportW then return "standard" end
	
	viewportW = math.floor(viewportW)
	
	if viewportW < LAYOUT_THRESHOLDS.compact then
		return "compact"
	elseif viewportW < LAYOUT_THRESHOLDS.standard then
		return "standard"
	else
		return "wide"
	end
end

-- Current layout mode (updated on resize); seeded from the live viewport so
-- wide-screen players don't sit in "standard" until their first resize.
local currentLayoutMode = getLayoutMode(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X)

-- Viewport-resize wiring lives after updatePanelSizing's definition
-- (layoutDesktopBar / layoutMobileStack are feature-branch locals with their
-- own resize handlers; the layout-mode tracker only refreshes panel sizing).

-- R4 polish #2 (mobile): context-aware haptic feedback system for touch interactions.
--
-- ARCHITECTURE NOTE (harborheist-5rcp.3, ultrathink review):
-- The ORIGINAL implementation (5rcp) had TWO compounding bugs that together made
-- the ENTIRE haptic system a silent no-op since the feature was first written:
--
--   Bug A: HapticService:Play(effectType, intensity, duration) does NOT exist.
--          Per Roblox creator docs, HapticService only exposes GetMotor /
--          IsMotorSupported / IsVibrationSupported / SetMotor — and the service
--          itself is DEPRECATED. The method "Play" was hallucinated. The pcall
--          around the call silently swallowed the "attempt to call a nil value"
--          error, so every haptic in the game did nothing.
--
--   Bug B: HAPTIC_CATEGORIES used the string "Rumble" for every success/error/
--          rarity effect. "Rumble" is NOT a valid HapticEffectType member. The
--          valid members are: Custom, UIHover, UIClick, UINotification,
--          GameplayExplosion, GameplayCollision. The 5rcp.2 fix papered over the
--          crash by falling back to UIClick, but that destroyed all semantic
--          differentiation — a legendary catch felt identical to a button press.
--
-- FIX: Rewritten to use the modern HapticEffect INSTANCE API (the documented
-- successor to the deprecated HapticService:Play):
--   1. Create a HapticEffect instance, set .Type to a VALID HapticEffectType.
--   2. Parent to workspace (required for the effect to be emitted).
--   3. Call :Play(). Auto-clean via Debris after the plausible max tail.
-- Intensity/duration are no longer direct API params (HapticEffect:Play takes
-- none); instead the effect TYPE carries the semantic weight, and for Custom
-- effects the waveform keys define amplitude over time. For the preset types
-- used here (UIClick, UINotification, GameplayCollision, GameplayExplosion),
-- the engine selects the appropriate waveform per device.
--
-- Fully pcall-guarded — on devices without haptic hardware, HapticEffect:Play
-- is a silent no-op. Deliberately NOT wired to every UI moment — haptics
-- everywhere is haptics nowhere.

-- Map internal category names to VALID Enum.HapticEffectType members.
-- harborheist-5rcp.3: replaced the invalid "Rumble" string with real members.
-- Semantic mapping rationale (per Roblox docs descriptions):
--   UI clicks / presses           -> UIClick       (crisp, immediate)
--   Success / milestone / reveal  -> UINotification (draws attention)
--   Error                         -> GameplayCollision (sharp, dies quickly)
--   Major celebration             -> GameplayExplosion (high intensity, lingers)
local HAPTIC_TYPES = {
	PressStart     = Enum.HapticEffectType.UIClick,
	PressEnd       = Enum.HapticEffectType.UIClick,
	SuccessSmall   = Enum.HapticEffectType.UINotification,
	SuccessLarge   = Enum.HapticEffectType.GameplayExplosion,
	ErrorSmall     = Enum.HapticEffectType.GameplayCollision,
	ErrorLarge     = Enum.HapticEffectType.GameplayCollision,
	RarityReveal   = Enum.HapticEffectType.GameplayExplosion,
	QuestComplete  = Enum.HapticEffectType.UINotification,
	MilestoneClaim = Enum.HapticEffectType.GameplayExplosion,
}

-- Haptic feedback dispatcher (fallback to PressEnd if category not found).
-- harborheist-l0rb / consolidation: single source of truth — all wrappers below
-- delegate here so the IS_MOBILE guard + pcall + lookup live in exactly one place.
local function playHaptic(category)
	if not IS_MOBILE then return end

	local effectType = HAPTIC_TYPES[category] or HAPTIC_TYPES.PressEnd
	if effectType == nil then return end

	pcall(function()
		local effect = Instance.new("HapticEffect")
		effect.Type = effectType
		effect.Parent = workspace
		-- Schedule cleanup BEFORE :Play() — if Play() errors (pcall swallows
		-- it), the instance would otherwise leak into workspace permanently,
		-- accumulating one dead HapticEffect per failed call for the session.
		-- 3s covers the longest preset tail (GameplayExplosion lingers).
		Debris:AddItem(effect, 3)
		effect:Play()
	end)
end

-- Convenience wrappers for common actions
local function hapticPressStart()
	playHaptic("PressStart")
end

local function hapticPressEnd()
	playHaptic("PressEnd")
end

local function hapticSuccess()
	playHaptic("SuccessSmall")
end

local function hapticError()
	playHaptic("ErrorSmall")
end

-- Legacy compatibility - kept for existing code paths (celebration moments)
local function hapticTick()
	playHaptic("RarityReveal")
end

-- ============================================================
-- Design system
-- ============================================================
-- ============================================================
-- Design system (Theme token integration - harborheist-nk22)
-- Migrated from hardcoded Color3 values to Theme tokens
-- ============================================================

-- harborheist-nk22 (EPIC 36): base colors sourced from the shared UIPalette
-- module (single source of truth, shared with GradientLibrary). The `Theme`
-- token table below aliases these same values into semantic groups — new UI
-- code reads Theme.color.surface.secondary etc., not this flat table.
local UI = {
	bg = UIPalette.color("bg"),
	surface = UIPalette.color("surface"),
	surfaceHi = UIPalette.color("surfaceHi"),
	stroke = UIPalette.color("stroke"),
	accent = UIPalette.color("accent"),
	accentSoft = UIPalette.color("accentSoft"),
	good = UIPalette.color("good"),
	bad = UIPalette.color("bad"),
	warn = UIPalette.color("warn"),
	quest = UIPalette.color("quest"),
	boat = UIPalette.color("boat"),
	purple = UIPalette.color("purple"),
	text = UIPalette.color("text"),
	textDim = UIPalette.color("textDim"),
	textFaint = UIPalette.color("textFaint"),
	ink = UIPalette.color("ink"),
	-- Additional palette colors for semantic tokens
	money = UIPalette.color("money"),
	undiscovered = UIPalette.color("undiscovered"),
	claimReady = UIPalette.color("claimReady"),
	claimReadyHi = UIPalette.color("claimReadyHi"),
	disabled = UIPalette.color("disabled"),
	neutral = UIPalette.color("neutral"),
	alert = UIPalette.color("alert"),
	raidAlert = UIPalette.color("raidAlert"),
}

local FONT_HEAD = Enum.Font.GothamBlack
local FONT_BOLD = Enum.Font.GothamBold
local FONT_MED = Enum.Font.GothamMedium
local FONT_BODY = Enum.Font.Gotham

local EASE_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- harborheist-2wuo.1: Back -> Spring for the "pop" easing (scale-in
-- reveals, button bounce-back). Spring gives physics-based overshoot that
-- feels more natural than Back's synthetic curve. NOT applied to EASE_FAST
-- (Quad) or EASE_IN (Quad) — those control press compression, hover glows,
-- fades, and exit acceleration where Spring overshoot would cause flicker
-- or feel wrong.
-- selene: allow(incorrect_standard_library_use) — Spring is a valid
-- Enum.EasingStyle member (confirmed via Roblox creator docs); selene
-- 0.31's roblox std is stale.
local EASE_POP = TweenInfo.new(0.28, Enum.EasingStyle.Spring, Enum.EasingDirection.Out)
local EASE_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- R4 polish #7/#8: exits ACCELERATE, entries decelerate. Both panel close
-- paths (mobile slide, desktop shrink) used decelerating easings — the
-- slowest, most visible part of the exit was the tail.
local EASE_IN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ============================================================
-- Design tokens (harborheist-uabg.7): canonical foundation for
-- spacing, typography, color, radii, shadows and button variants.
--
-- DEFINITION-only pass. Existing call sites still read the flat
-- `UI` / `FONT_*` palette above and are NOT migrated here — that is
-- the separate harborheist-uabg.6 bead. `Theme` aliases those same
-- values (no duplication, no behavioral change) so new UI code opts
-- into the semantic system incrementally:
--   Theme.color.surface.secondary   instead of  UI.surface
--   Theme.color.text.primary        instead of  UI.text
--   Theme.corners.md                instead of  literal 12
--   makeButton(parent, { Variant = "danger", ... })
-- ============================================================
local Theme = {
	spacing = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 },
	type = {
		sizes = { xxs = 11, xs = 12, sm = 15, md = 19, lg = 24, xl = 30 }, -- 1.25 ratio
		fonts = { head = FONT_HEAD, bold = FONT_BOLD, med = FONT_MED, body = FONT_BODY },
	},
	color = {
		surface = { primary = UI.bg, secondary = UI.surface, elevated = UI.surfaceHi, undiscovered = UI.undiscovered },
		text = { primary = UI.text, secondary = UI.textDim, tertiary = UI.textFaint, ink = UI.ink },
		stroke = UI.stroke,
		accent = { base = UI.accent, soft = UI.accentSoft },
		status = { good = UI.good, bad = UI.bad, warn = UI.warn, info = UI.accentSoft, claimReady = UI.claimReady, claimReadyHi = UI.claimReadyHi, disabled = UI.disabled, neutral = UI.neutral, alert = UI.alert, raidAlert = UI.raidAlert },
		brand = { quest = UI.quest, boat = UI.boat, purple = UI.purple },
		money = UI.money,
	},
	corners = { hairline = 2, thin = 3, slim = 4, compact = 5, snug = 6, tight = 7, sm = 8, roomy = 10, md = 12, spacious = 14, lg = 16, xl = 20, pill = 999 },
	-- Roblox UI has no native shadow; elevation is faked with layered
	-- Frames. Consumed by EPIC 35 (harborheist-i39g.1); defined here so
	-- the token system is complete and that bead reads a single source.
	shadows = {
		low = { layers = 2, spread = 4, alpha = 0.15 },
		medium = { layers = 3, spread = 8, alpha = 0.2 },
		high = { layers = 4, spread = 16, alpha = 0.3 },
	},
	buttonVariants = {
		primary = { bg = UI.accent, text = UI.ink, strokeColor = nil, strokeTransparency = 1 },
		secondary = { bg = UI.surfaceHi, text = UI.text, strokeColor = UI.stroke, strokeTransparency = 0.7 },
		ghost = { bg = UI.surface, text = UI.textDim, strokeColor = UI.stroke, strokeTransparency = 0.85 },
		danger = { bg = UI.bad, text = UI.ink, strokeColor = nil, strokeTransparency = 1 },
	},
}

-- Variant radii are assigned AFTER the constructor: a table constructor
-- cannot self-reference its own `local Theme` (resolves to nil global and
-- crashes at load — regression introduced in 4199fc5, reverted here to the
-- uabg.7 pattern).
for _, variant in pairs(Theme.buttonVariants) do
	variant.radius = Theme.corners.md
end

local state = nil
local casting = false
local castHitZone = { perfectStart_ = 0.35, perfectEnd_ = 0.65, goodStart_ = 0.15, goodEnd_ = 0.85 }
local castDeadline = 0
-- TASK 23.1 (hvfh.3.1): duration of the currently-open cast overlay. The
-- old per-cast InputBegan closure captured this by upvalue; the single
-- overlay router (see CastState handler below) needs it as file scope.
local castOverlayDuration = 0
-- harborheist-njqm: idle-cast coach toast. True while an OPENED cast
-- overlay is still waiting for its first tap; a CastState(false) arriving
-- in that window means the cast timed out with zero input and the server
-- silently assigned luckBonus 0. Coached once per session.
local castAwaitingInput = false
local coachShownIdleCast = false
-- TASK 23.1 (hvfh.3.1): central minigame/overlay manager. ONE owner for
-- "which timed-input overlay is active", replacing four independent global
-- InputBegan listeners (cast overlay, raid minigame, bite minigame x2).
-- Model: initiation gating, NOT preemption (see bead; preemption eats
-- in-flight catches or races the server raid deadline). The single
-- UserInputService.InputBegan router connection is wired at the BOTTOM of
-- this file (after every overlayInputHandlers.<name> assignment), because
-- Lua locals are lexically scoped and the handlers don't exist yet here.
local activeOverlay = nil -- nil | "cast" | "bite" | "raid"
local overlayInputHandlers = {} -- name -> handler(input, gameProcessed)

local function requestOverlay(name)
	if activeOverlay ~= nil then
		return false
	end
	activeOverlay = name
	return true
end

local function releaseOverlay(name)
	if activeOverlay == name then
		activeOverlay = nil
	end
end

local function isOverlayActive(kind)
	return activeOverlay == kind
end

-- ============================================================
-- harborheist-i39g.4: Z-Index Ladder (canonical reference)
--
-- Roblox renders siblings by ZIndex (higher = on top) when the
-- ScreenGui uses ZIndexBehavior.Sibling (set below). This ladder
-- is the single source of truth for layering — new UI must slot
-- into an existing band or extend it, never invent a new value
-- in the middle of a band.
--
--   0-9    HUD elements (cash card, carry pill, HUD buttons)
--          4 = hudClick, 5 = income line / action bar
--
--   10     Action button badges (bag badge, boat state dot)
--          These are children of action buttons, layered above the button
--
--   15-19  Onboarding / coach marks / raid banner
--          15 = onboardingPrompt, 16 = accent bar / labels,
--          18 = raid banner background, 19 = raid banner icon / text
--
--   20-24  Panel backdrops (dimmed screen behind a modal panel)
--          20 = backdrop
--
--   25-29  Panel content (the modal itself + its children)
--          25 = panel frame, 26 = grabber / drag surface / content,
--          27 = inner controls (capacity bar, claim button),
--          28 = shop/quest panel fills
--
--   30-39  Prompts (sell/store confirmations)
--          30 = sellStorePrompt, 31 = prompt children
--
--   40-49  Minigame overlays (cast, bite, raid)
--          40 = OVERLAY_Z_BASE (frame), 41 = OVERLAY_Z_CONTENT,
--          42 = OVERLAY_Z_ZONE (good zone), 43 = OVERLAY_Z_MARKER,
--          49 = rarity flash (legendary catch celebration)
--
--   50-54  Reveal card (first-catch / epic-catch celebration)
--          50 = card, 51 = topBar / tag / icon, 52 = rarity stroke
--
--   55-59  Toasts (ALWAYS WIN — carry server truth like raid-victim)
--          55 = toastHost, 56 = toast, 57 = accentBar / action buttons,
--          58 = toast title, 59 = dismiss button, 60+i = stacked toasts
--
--   100    Empty-state overlays (panel-local, not a global layer)
--          Used by showCollectionSkeleton / empty-frame factories
--
-- RULES:
-- 1. Toasts (55-59) always render above everything — they carry
--    server-authoritative notifications (raid-victim, datastore errors).
-- 2. Minigame overlays (40-49) must be above panels (25-29) so the
--    timing bar is visible when a panel is open behind it.
-- 3. Never assign ZIndex between bands (e.g., 35) — that creates
--    ambiguous layering. Use the band assigned to your UI category.
-- 4. If you need a new band, extend the nearest one (e.g., 60-69 for
--    a new overlay type) and update this comment.
-- ============================================================
local OVERLAY_Z_BASE = 40
local OVERLAY_Z_CONTENT = 41
local OVERLAY_Z_ZONE = 42
local OVERLAY_Z_MARKER = 43

-- TASK 22.4 (hvfh.2.4): local first-catch counter. Incremented on each
-- ok=true SubmitCatchInput result; counter == 1 triggers the reveal card
-- regardless of rarity. Local + deterministic — no server-flag race.
local catchesThisSession = 0
local questData = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HarborHeistUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Safe area handling (harborheist-fxfx): proper inset detection for all devices
local inset = GuiService:GetGuiInset()

-- Calculate safe top offset based on device type and orientation
local function calculateSafeTop()
	-- Get current viewport dimensions to detect landscape (Camera is not a
	-- service — read the CurrentCamera; nil-safe before the first camera exists)
	local cam = workspace.CurrentCamera
	local viewportSize = cam and cam.ViewportSize or Vector2.new(1920, 1080)

	-- Detect if in landscape mode (width > height)
	local isLandscape = viewportSize.X > viewportSize.Y
	
	-- Base safe area values: accounts for notch, status bar, and system UI
	local baseSafeArea = {
		portrait = { mobile = 12, desktop = 8 },
		landscape = { mobile = 16, desktop = 10 }, -- Extra padding in landscape
	}
	
	-- Use the appropriate value based on device type and orientation
	local safeTop = baseSafeArea[isLandscape and "landscape" or "portrait"][IS_MOBILE and "mobile" or "desktop"]
	
	-- Add notch compensation if detected (iOS devices have larger inset.Y)
	if inset.Y and inset.Y > 20 then
		safeTop = math.max(safeTop, inset.Y + 4) -- Extra 4px for notch safety margin
	end
	
	return safeTop
end

-- Mutable: harborheist-vr21 — recalculated on viewport/orientation change by
-- refreshSafeTop() below (HUD consumers reposition via safeTopConsumers).
local SAFE_TOP = calculateSafeTop()

-- Registry of SAFE_TOP consumers: each entry re-reads SAFE_TOP and
-- repositions one UI element. Populated where each element is created
-- (closures keep the element references alive).
local safeTopConsumers = {}
local function refreshSafeTop()
	SAFE_TOP = calculateSafeTop()
	for _, fn in ipairs(safeTopConsumers) do
		task.spawn(fn)
	end
end
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
	s.Color = color or Theme.color.stroke
	s.Transparency = transparency or 0.88
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function makeLabel(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.color.text.primary
	label.Font = Theme.type.fonts.body
	label.TextScaled = false
	label.TextSize = Theme.type.sizes.sm
	for key, value in pairs(props) do
		label[key] = value
	end
	label.Parent = parent
	return label
end

-- TASK 23.2 (hvfh.3.2): Unified overlay factory.
-- TASK 21.4 (harborheist-7w5a): definition MOVED below the primitive helpers
-- (screenGui/corner/stroke/vGradient/makeLabel). It was originally defined at
-- ~:106, BEFORE those locals — Luau binds names lexically at the definition
-- site, so the body read them as nil globals and the first corner() call
-- threw "attempt to call a nil value" at load time (both callers are
-- top-level: raid minigame + cast overlay), killing the client script before
-- the remote listeners and bootstrap could wire up. P0 boot-blocker.
local function makeOverlayFrame(name, titleText, subtitleText)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Unified size: mobile full-width minus padding, desktop fixed 400x112
	frame.Size = IS_MOBILE and UDim2.new(1, -24, 0, 132) or UDim2.new(0, 400, 0, 112)
	-- Unified position: center-stage at 0.42 mobile / 0.58 desktop
	frame.Position = UDim2.new(0.5, 0, IS_MOBILE and 0.42 or 0.58, 0)
	frame.BackgroundColor3 = Theme.color.surface.primary
	frame.BackgroundTransparency = 0.08
	frame.Visible = false
	frame.ZIndex = OVERLAY_Z_BASE
	frame.Parent = screenGui
	corner(frame, Theme.corners.lg)
	stroke(frame, 0.8)
	Gradients.apply(frame, "surface.default")

	-- Title (unified style)
	local title = makeLabel(frame, {
		Size = UDim2.new(1, -20, 0, 24),
		Position = UDim2.new(0, 10, 0, 10),
		Text = titleText,
		Font = Theme.type.fonts.head,
		TextSize = IS_MOBILE and Theme.type.sizes.sm or Theme.type.sizes.md,
		TextColor3 = Theme.color.status.warn,
		ZIndex = OVERLAY_Z_CONTENT,
	})

	-- Timing bar track (unified)
	local barTrack = Instance.new("Frame")
	barTrack.Size = UDim2.new(1, -24, 0, IS_MOBILE and 52 or 40)
	barTrack.Position = UDim2.new(0, 12, 0, IS_MOBILE and 52 or 48)
	barTrack.BackgroundColor3 = Theme.color.surface.secondary
	barTrack.ZIndex = OVERLAY_Z_CONTENT
	barTrack.Parent = frame
	corner(barTrack, Theme.corners.roomy)
	stroke(barTrack, 0.85)

	-- Good zone (unified)
	local goodZone = Instance.new("Frame")
	goodZone.Name = "GoodZone"
	goodZone.Size = UDim2.new(0.3, 0, 1, 0)
	goodZone.Position = UDim2.new(0.35, 0, 0, 0)
	goodZone.BackgroundColor3 = Theme.color.status.good
	goodZone.BackgroundTransparency = 0.45
	goodZone.ZIndex = OVERLAY_Z_ZONE
	goodZone.Parent = barTrack
	corner(goodZone, Theme.corners.sm)
	stroke(goodZone, 0.5, Theme.color.status.good, 1.5)

	-- Perfect zone (unified)
	local perfectZone = Instance.new("Frame")
	perfectZone.Name = "PerfectZone"
	perfectZone.AnchorPoint = Vector2.new(0.5, 0)
	perfectZone.Size = UDim2.new(0.4, 0, 1, -8)
	perfectZone.Position = UDim2.new(0.5, 0, 0, 4)
	perfectZone.BackgroundColor3 = Theme.color.money
	perfectZone.BackgroundTransparency = 0.12
	perfectZone.ZIndex = OVERLAY_Z_MARKER
	perfectZone.Parent = goodZone
	corner(perfectZone, Theme.corners.tight)

	-- Subtitle (unified) - TASK 26.3: improved readability
	local subtitle = makeLabel(frame, {
		Size = UDim2.new(1, -24, 0, 16),
		Position = UDim2.new(0, 12, 1, -20),
		Text = subtitleText,
		Font = Theme.type.fonts.bold,
		TextSize = IS_MOBILE and Theme.type.sizes.sm or Theme.type.sizes.xs,
		TextColor3 = Theme.color.text.tertiary,
		ZIndex = OVERLAY_Z_CONTENT,
	})

	-- Marker (unified)
	local marker = Instance.new("Frame")
	marker.Size = UDim2.new(0, 5, 1, 6)
	marker.Position = UDim2.new(0, 0, 0, -3)
	marker.BackgroundColor3 = Color3.new(1, 1, 1)
	marker.ZIndex = OVERLAY_Z_MARKER
	marker.Parent = barTrack
	corner(marker, Theme.corners.thin)

	local markerGlow = Instance.new("Frame")
	markerGlow.Size = UDim2.new(0, 15, 1, 10)
	markerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	markerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	markerGlow.BackgroundColor3 = Theme.color.accent.soft
	markerGlow.BackgroundTransparency = 0.75
	markerGlow.ZIndex = OVERLAY_Z_ZONE
	markerGlow.Parent = marker
	corner(markerGlow, Theme.corners.sm)

	return frame, title, barTrack, goodZone, perfectZone, subtitle, marker, markerGlow
end

-- ============================================================
-- harborheist-6qyq: Sound design — client-local SoundService one-shots.
-- The entire game was silent; sound is the cheapest premium-feel
-- multiplier for a cozy game. Every asset ID below is a Roblox-OWNED
-- classic/library upload, verified public via the economy v2 details API
-- (2026-07-26): a wrong/unauthorized ID fails SILENTLY (no error, no
-- sound), so never add an unverified ID to this table.
-- ============================================================
local SOUNDS = {
	buttonTick = "rbxassetid://12221967", -- button.wav (classic click)
	castLaunch = "rbxassetid://12222103", -- Rubber band sling shot.wav
	biteAlert = "rbxassetid://12221990", -- electronicpingshort.wav
	catchSplash = "rbxassetid://12222054", -- Kerplunk.wav
	catchRare = "rbxassetid://12221990", -- ping, brightened via PlaybackSpeed
	catchEpic = "rbxassetid://12221996", -- flashbulb.wav
	catchLegendary = "rbxassetid://12222030", -- HalloweenThunder.wav
	claimCoins = "rbxassetid://4612375233", -- gem_pickup (Roblox SFX library)
	raidOpen = "rbxassetid://12222095", -- Rocket whoosh 01.wav
	raidClose = "rbxassetid://12221944", -- bass.wav
	raidVictim = "rbxassetid://12222005", -- glassbreak.wav
}

-- Server-toast categories that carry a stinger (consumed in
-- showNotification, the single funnel for all server toasts).
local NOTIFY_SOUNDS = {
	-- ALARM-at-attempt, robbed, and defended toasts all share this
	-- category (RaidService.lua) — one shatter sting = 'your dock!'.
	["raid-victim"] = { id = SOUNDS.raidVictim, volume = 0.7 },
}

-- Fire-and-forget one-shot: no channel management or pooling (a few
-- plays/minute at most); Debris collects the instance after the longest
-- plausible tail. PlayLocalSound bypasses 3D so UI sounds never pan.
local function playSound(soundId, volume, speed)
	local s = Instance.new("Sound")
	s.Name = "HH_OneShot"
	s.SoundId = soundId
	s.Volume = volume or 0.5
	s.PlaybackSpeed = speed or 1
	s.Parent = SoundService
	SoundService:PlayLocalSound(s)
	Debris:AddItem(s, 6)
end
-- (harborheist-au38) pressFeedback removed: complete but unused function.

-- ============================================================
-- Context Menu System (harborheist-vasr)
-- Custom Frame-based right-click menus for desktop power users
-- ============================================================

local ContextMenu = {}
ContextMenu.__index = ContextMenu

-- Create a new context menu instance. items: { { id, text, action, disabled?, icon? } }
function ContextMenu.new(items, props)
	local self = setmetatable({}, ContextMenu)

	props = props or {}
	self.items = items or {}
	self.isOpen = false

	-- Visual settings from Theme (corners tokens are plain numbers)
	self.cornerRadius = props.CornerRadius or Theme.corners.md
	self.hoverColor = Theme.color.surface.elevated

	-- Menu root frame
	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "ContextMenu"
	menuFrame.BackgroundColor3 = Theme.color.surface.primary
	menuFrame.BackgroundTransparency = 0
	menuFrame.BorderSizePixel = 0
	menuFrame.ZIndex = 200 -- High Z to stay on top
	menuFrame.Visible = false
	corner(menuFrame, self.cornerRadius)
	stroke(menuFrame, 0.8)

	-- Store menu items data
	self.itemsData = {}
	for i, item in ipairs(self.items) do
		table.insert(self.itemsData, {
			id = item.id or tostring(i),
			text = item.text or "",
			icon = item.icon,
			action = item.action or function() end,
			disabled = item.disabled or false,
		})
	end

	-- Item buttons (built once; hover wired once — not per show())
	self.itemFrames = {}
	for i, item in ipairs(self.itemsData) do
		local itemBtn = Instance.new("TextButton")
		itemBtn.Name = "Item_" .. item.id
		itemBtn.Size = UDim2.new(1, -8, 0, 32)
		itemBtn.Position = UDim2.new(0, 4, 0, 4 + (i - 1) * 36)
		itemBtn.BackgroundColor3 = Theme.color.surface.primary
		itemBtn.BackgroundTransparency = 1
		itemBtn.ZIndex = 201
		itemBtn.AutoButtonColor = false
		itemBtn.Font = Theme.type.fonts.body
		itemBtn.TextSize = Theme.type.sizes.sm
		itemBtn.TextColor3 = Theme.color.text.primary
		itemBtn.TextXAlignment = Enum.TextXAlignment.Left
		itemBtn.TextTruncate = Enum.TextTruncate.AtEnd
		itemBtn.ClipsDescendants = true
		itemBtn.Text = "  " .. item.text
		itemBtn.Parent = menuFrame
		corner(itemBtn, Theme.corners.sm)

		if item.disabled then
			itemBtn.TextColor3 = Theme.color.text.tertiary
		end

		itemBtn.MouseEnter:Connect(function()
			if not item.disabled then
				itemBtn.BackgroundTransparency = 0
				itemBtn.BackgroundColor3 = self.hoverColor
			end
		end)
		itemBtn.MouseLeave:Connect(function()
			itemBtn.BackgroundTransparency = 1
		end)
		itemBtn.Activated:Connect(function()
			if not item.disabled then
				self:hide()
				item.action()
			end
		end)

		table.insert(self.itemFrames, itemBtn)
	end

	self.frame = menuFrame

	-- Parented lazily on first show (screenGui exists by then)
	function self:show(x, y)
		if not x or not y then return end
		if menuFrame.Parent == nil then
			menuFrame.Parent = screenGui
		end

		local cam = workspace.CurrentCamera
		local viewportW = cam and cam.ViewportSize.X or 1920
		local viewportH = cam and cam.ViewportSize.Y or 1080

		local menuWidth = 180
		local menuHeight = #self.itemsData * 36 + 8

		local posX = x + 8
		local posY = y
		if posX + menuWidth > viewportW then
			-- Flip left of the cursor, but never push the menu's RIGHT edge
			-- off-screen on viewports narrower than the menu itself.
			posX = math.max(0, math.min(viewportW - menuWidth, x - menuWidth - 8))
		end
		if posY + menuHeight > viewportH then
			posY = math.max(0, viewportH - menuHeight - 8)
		end

		menuFrame.Size = UDim2.new(0, menuWidth, 0, menuHeight)
		menuFrame.Position = UDim2.new(0, posX, 0, posY)
		menuFrame.Visible = true
		self.isOpen = true

		-- Click-outside-to-close: connected on show, disconnected on hide.
		-- Deferred so the same right-click that opened the menu can never be
		-- seen by this handler (the menu spawns 8px from the cursor, i.e. the
		-- opening click is technically "outside" the menu rect).
		if self._outsideConn then self._outsideConn:Disconnect() end
		task.defer(function()
			if not self.isOpen then return end
			if self._outsideConn then self._outsideConn:Disconnect() end
			self._outsideConn = UserInputService.InputBegan:Connect(function(input, processed)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.MouseButton2
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				local framePos = menuFrame.AbsolutePosition
				local frameSize = menuFrame.AbsoluteSize
				if pos.X < framePos.X or pos.X > framePos.X + frameSize.X
					or pos.Y < framePos.Y or pos.Y > framePos.Y + frameSize.Y then
					self:hide()
				end
			end)
		end)
	end

	function self:hide()
		menuFrame.Visible = false
		self.isOpen = false
		if self._outsideConn then
			self._outsideConn:Disconnect()
			self._outsideConn = nil
		end
	end

	function self:destroy()
		self:hide()
		menuFrame:Destroy()
	end

	return self
end

local function makeButton(parent, props)
	local button = Instance.new("TextButton")
	local cornerRadius = props.CornerRadius
	props.CornerRadius = nil
	-- harborheist-2wuo.2: Button micro-interactions - press/hover/success/error states
	-- Variant seeds bg/text/corner (+ stroke for secondary/ghost) from Theme.buttonVariants
	local variantName = props.Variant or "primary"
	props.Variant = nil
	local variant = Theme.buttonVariants[variantName] or Theme.buttonVariants.primary
	
	-- Set base colors with proper contrast
	button.BackgroundColor3 = (variant and variant.bg) or Theme.color.accent.base
	button.TextColor3 = (variant and variant.text) or Theme.color.text.ink
	button.Font = Theme.type.fonts.bold
	button.TextSize = IS_MOBILE and Theme.type.sizes.md or Theme.type.sizes.sm
	button.AutoButtonColor = false
	
	-- Apply custom properties if provided
	for key, value in pairs(props) do
		if key ~= "Variant" then
			button[key] = value
		end
	end
	
	button.Parent = parent
	
	local resolveRadius = cornerRadius or (variant and variant.radius) or Theme.corners.md
	corner(button, resolveRadius)
	
	-- Apply stroke if defined in variant
	if variant and variant.strokeColor then
		stroke(button, variant.strokeTransparency, variant.strokeColor, 1)
	end
	
	-- harborheist-2wuo.2: Micro-interaction system for button states
	local hoverGlow = nil
	local pressTween = nil
	
	if not IS_MOBILE then
		-- Desktop: white-wash hover glow effect
		hoverGlow = Instance.new("Frame")
		hoverGlow.Name = "HoverGlow"
		hoverGlow.Size = UDim2.new(1, 0, 1, 0)
		hoverGlow.BackgroundColor3 = Color3.new(1, 1, 1)
		hoverGlow.BackgroundTransparency = 1
		hoverGlow.ZIndex = button.ZIndex + 1
		hoverGlow.Parent = button
		corner(hoverGlow, resolveRadius)
	end
	
	-- harborheist-ks2m: Wire AnimationSystem press feedback if available.
	-- NOTE (harborheist-5rcp.4): AnimationSystem:addPress handles the VISUAL
	-- scale feedback + optional sound. It does NOT fire haptics. The haptic
	-- calls below must therefore run on EVERY button regardless of whether
	-- Anim:press succeeded — the previous code gated ALL of setupPressFeedback
	-- (including the haptic MouseButton1Down/Up handlers) behind
	-- `if hasAnimPress then return end`, which meant haptics only fired in the
	-- rare fallback path where AnimationSystem was unavailable. With
	-- AnimationSystem always loaded, the button-press haptic was a dead path.
	local hasAnimPress = false
	if Anim and type(Anim.press) == "function" then
		local ok = pcall(function()
			Anim:press(button)
		end)
		hasAnimPress = ok
	end
	
	-- Haptic + press feedback wiring. Haptics run unconditionally (mobile only);
	-- the visual scale/cancel/hover logic only runs when AnimationSystem did
	-- NOT take over (hasAnimPress gates the duplicate scale path only).
	-- harborheist-g9z2: Enhanced with hover effects, animation cancellation, and disabled button guards
	local function setupPressFeedback()
		-- harborheist-5rcp.4: Haptic wiring runs BEFORE the hasAnimPress gate
		-- so press/release/success/error haptics fire on EVERY button. The
		-- visual scale feedback below is the only thing gated by hasAnimPress.
		if IS_MOBILE then
			button.MouseButton1Down:Connect(function()
				if not button.Active then return end
				hapticPressStart()
			end)
			button.MouseButton1Up:Connect(function()
				if not button.Active then return end
				hapticPressEnd()
			end)
		end

		-- Success/error haptics wire on Click (fires once per successful tap,
		-- distinct from Down/Up which fire on raw press/release). These must
		-- also be unconditional — previously they lived below the hasAnimPress
		-- return and were dead code on every Anim-backed button.
		if props and props.onSuccess then
			button.MouseButton1Click:Connect(function()
				hapticSuccess()
				props.onSuccess()
			end)
		end
		if props and props.onError then
			button.MouseButton1Click:Connect(function()
				hapticError()
				props.onError(button)
			end)
		end

		-- harborheist-l0rb: Visual ripple effect on press (all platforms).
		-- A white circle spawns at the press point and expands outward while
		-- fading — complements the scale-darken and haptic systems. Fires
		-- on every button (before the hasAnimPress gate) so Anim-backed
		-- buttons also get the ripple. Self-cleans via task.delay.
		local function spawnRipple()
			if not button.Active then return end
			local mousePos = UserInputService:GetMouseLocation()
			local absPos = button.AbsolutePosition
			local absSize = button.AbsoluteSize
			local x = math.clamp(mousePos.X - absPos.X, 0, absSize.X)
			local y = math.clamp(mousePos.Y - absPos.Y, 0, absSize.Y)
			local maxSize = math.max(absSize.X, absSize.Y) * 1.5
			local ripple = Instance.new("Frame")
			ripple.Name = "Ripple"
			ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			ripple.BackgroundTransparency = 0.6
			ripple.AnchorPoint = Vector2.new(0.5, 0.5)
			ripple.Position = UDim2.new(0, x, 0, y)
			ripple.Size = UDim2.new(0, 0, 0, 0)
			local rippleCorner = Instance.new("UICorner")
			rippleCorner.CornerRadius = UDim.new(1, 0)
			rippleCorner.Parent = ripple
			ripple.ZIndex = button.ZIndex + 1
			ripple.Parent = button
			TweenService:Create(ripple, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, maxSize, 0, maxSize),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.4, function()
				if ripple.Parent then
					ripple:Destroy()
				end
			end)
		end
		button.MouseButton1Down:Connect(spawnRipple)

		if hasAnimPress then return end  -- AnimationSystem handles the visual scale
		if pressTween then return end
		
		pressTween = EASE_FAST
		
		-- harborheist-g9z2: Track active tweens for cancellation during rapid interactions
		local activeTweens = {}
		local function cancelTweens()
			for _, tween in pairs(activeTweens) do
				if tween and tween.PlaybackState ~= Enum.PlaybackState.Completed then
					pcall(function() tween:Cancel() end)
				end
			end
			activeTweens = {}
		end
		
		-- harborheist-g9z2: Store original color for hover lerp
		local originalColor = button.BackgroundColor3
		
		-- harborheist-g9z2: Pre-create shadow layers for hover elevation (desktop only)
		local hoverShadows = {}
		if not IS_MOBILE then
			local shadowConfig = Theme.shadows.low
			for i = 1, shadowConfig.layers do
				local shadow = Instance.new("Frame")
				shadow.Name = "HoverShadow_" .. i
				shadow.BackgroundColor3 = Color3.new(0, 0, 0)
				shadow.BackgroundTransparency = 1 -- start invisible
				shadow.Size = UDim2.new(1, shadowConfig.spread * i, 1, shadowConfig.spread * i)
				shadow.Position = UDim2.new(0, -shadowConfig.spread * i / 2, 0, -shadowConfig.spread * i / 2)
				shadow.ZIndex = button.ZIndex - 1
				shadow.Active = false
				shadow.Parent = button
				corner(shadow, resolveRadius)
				hoverShadows[i] = shadow
			end
		end
		
		button.MouseButton1Down:Connect(function()
			-- harborheist-g9z2: Guard against disabled buttons
			if not button.Active then
				return
			end
			
			-- harborheist-g9z2: Cancel any running animations before starting new ones
			cancelTweens()
			
			-- Press state - scale down slightly for tactile feedback
			activeTweens.scale = TweenService:Create(button, pressTween, { Scale = 0.96 })
			activeTweens.scale:Play()
		end)
		
		button.MouseButton1Up:Connect(function()
			-- harborheist-g9z2: Guard against disabled buttons
			if not button.Active then
				return
			end
			
			cancelTweens()
			
			-- Release state - bounce back with spring physics
			activeTweens.scale = TweenService:Create(button, EASE_POP, { Scale = 1 })
			activeTweens.scale:Play()
		end)
		
		-- harborheist-g9z2: Desktop hover effects
		if not IS_MOBILE then
			button.MouseEnter:Connect(function()
				-- harborheist-g9z2: Guard against disabled buttons
				if not button.Active then
					return
				end
				
				cancelTweens()
				
				-- harborheist-g9z2: Scale up slightly on hover
				activeTweens.scale = TweenService:Create(button, EASE_FAST, { Scale = 1.02 })
				activeTweens.scale:Play()
				
				-- harborheist-g9z2: Brighten background color (lerp toward white by 10%)
				local hoverColor = originalColor:Lerp(Color3.new(1, 1, 1), 0.1)
				activeTweens.color = TweenService:Create(button, EASE_FAST, { BackgroundColor3 = hoverColor })
				activeTweens.color:Play()
				
				-- harborheist-g9z2: Show hover glow overlay
				if hoverGlow then
					activeTweens.glow = TweenService:Create(hoverGlow, EASE_FAST, { BackgroundTransparency = 0.9 })
					activeTweens.glow:Play()
				end
				
				-- harborheist-g9z2: Fade in hover shadows for elevation lift
				-- harborheist-8qv8: track these in activeTweens so cancelTweens() covers them
				local shadowConfig = Theme.shadows.low
				for i, shadow in ipairs(hoverShadows) do
					local targetAlpha = 1 - (shadowConfig.alpha * (1 - (i - 1) / shadowConfig.layers))
					activeTweens["shadow_" .. i] = TweenService:Create(shadow, EASE_FAST, { BackgroundTransparency = targetAlpha })
					activeTweens["shadow_" .. i]:Play()
				end
				
				-- harborheist-g9z2: Change cursor to pointing hand
				playerMouse.Icon = "rbxasset://SystemCursors/PointingHand"
			end)
			
			button.MouseLeave:Connect(function()
				cancelTweens()
				
				-- harborheist-g9z2: Scale back to normal
				activeTweens.scale = TweenService:Create(button, EASE_FAST, { Scale = 1 })
				activeTweens.scale:Play()
				
				-- harborheist-g9z2: Restore original color
				activeTweens.color = TweenService:Create(button, EASE_FAST, { BackgroundColor3 = originalColor })
				activeTweens.color:Play()
				
				-- harborheist-g9z2: Hide hover glow
				if hoverGlow then
					activeTweens.glow = TweenService:Create(hoverGlow, EASE_FAST, { BackgroundTransparency = 1 })
					activeTweens.glow:Play()
				end
				
				-- harborheist-g9z2: Fade out hover shadows
				-- harborheist-8qv8: track these in activeTweens so cancelTweens() covers them
				for i, shadow in ipairs(hoverShadows) do
					activeTweens["shadow_" .. i] = TweenService:Create(shadow, EASE_FAST, { BackgroundTransparency = 1 })
					activeTweens["shadow_" .. i]:Play()
				end
				
				-- harborheist-g9z2: Reset cursor
				playerMouse.Icon = ""
			end)
			
			-- harborheist-g9z2: Clean up cursor and shadows on destroy
			button.Destroying:Connect(function()
				if playerMouse.Icon == "rbxasset://SystemCursors/PointingHand" then
					playerMouse.Icon = ""
				end
				for _, shadow in ipairs(hoverShadows) do
					if shadow.Parent then
						shadow:Destroy()
					end
				end
			end)
		end
	end
	
	setupPressFeedback()
	
	return button
end

-- ============================================================
-- harborheist-7h69.1: Universal skeleton loader factory.
-- Creates N ghost-card bars in a parent with a cascading transparency
-- pulse — the proven animation from showCollectionSkeleton, generalized
-- for reuse across any panel. NOT a UIGradient shimmer: Roblox
-- ColorSequenceKeypoint has no alpha channel (the bead's proposed
-- Color3.new(1,1,1,0) is technically invalid), so the pulse pattern is
-- the correct approach and is already runtime-verified.
--
-- The animation self-terminates: the task.spawn loop exits when
-- bars[1].Parent becomes nil (happens when the caller clears/replaces
-- the parent's children — e.g. clearCollectionList or rendering real
-- content). No manual cleanup needed.
--
-- config:
--   rows       — number of bars (default 3)
--   rowHeight  — bar height in px (default IS_MOBILE 110 / desktop 120)
--   gap        — bar spacing; sets UIListLayout.Padding if the factory
--                creates one (default Theme.spacing.md). Ignored if the
--                parent already has a UIListLayout (_preserved_ as-is).
--   zIndex     — ZIndex for bars (default 26)
--   animated   — run the pulse loop (default true)
--   barColor   — bar background (default Theme.color.surface.elevated)
--   radius     — corner radius (default Theme.corners.md)
-- Returns: bars table (for caller reference; destroying any bar triggers
-- self-termination).
-- ============================================================
-- EPIC 31: Loading States & Empty States for async data panels (shop, raid, inventory)
-- Universal skeleton loader factory with loading spinner support
local function createSkeletonRows(parent, config)
	-- Clear existing skeletons if any (only destroy skeletons, not other content)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name:find("^SkeletonRow_") or child.Name == "LoadingSpinner" then
			child:Destroy()
		end
	end
	
	local rows = config.rows or 4
	local rowHeight = config.rowHeight or (IS_MOBILE and 72 or 64)
	local zIndex = config.zIndex or 26
	
	-- Create loading spinner for async data fetch
	if parent:FindFirstChild("LoadingSpinner") then
		parent.LoadingSpinner:Destroy()
	end
	
	local spinner = Instance.new("Frame")
	spinner.Name = "LoadingSpinner"
	spinner.Size = UDim2.new(0, 48, 0, 48)
	spinner.Position = UDim2.new(0.5, -24, 0.5, -24)
	spinner.BackgroundColor3 = Theme.color.surface.primary
	spinner.BackgroundTransparency = 1
	spinner.ZIndex = zIndex + 1
	spinner.Parent = parent
	
	local spinnerStroke = Instance.new("UIStroke")
	spinnerStroke.Color = Theme.color.accent.base
	spinnerStroke.Thickness = 2
	spinnerStroke.Transparency = 0.9
	spinnerStroke.Parent = spinner
	
	local spinnerInner = Instance.new("Frame")
	spinnerInner.Size = UDim2.new(0, 36, 0, 36)
	spinnerInner.Position = UDim2.new(0.5, -18, 0.5, -18)
	spinnerInner.BackgroundColor3 = Theme.color.surface.primary
	spinnerInner.BackgroundTransparency = 1
	spinnerInner.ZIndex = zIndex + 2
	spinnerInner.Parent = spinner
	
	local spinnerStrokeInner = Instance.new("UIStroke")
	spinnerStrokeInner.Color = Theme.color.accent.base
	spinnerStrokeInner.Thickness = 3
	spinnerStrokeInner.Transparency = 0.85
	spinnerStrokeInner.Parent = spinnerInner
	
	-- Animate the spinner (self-terminates when spinner is destroyed)
	task.spawn(function()
		while spinnerInner.Parent and spinnerInner.Parent.Parent do
			local t = os.clock()
			spinnerInner.Position = UDim2.new(0.5, -18 + math.sin(t * 10) * 4, 0.5, -18 + math.cos(t * 10) * 4)
			spinnerInner.Rotation = t * 360
			task.wait(0.03)
		end
	end)
	
	-- Create skeleton rows for empty state display
	for i = 1, rows do
		local row = Instance.new("Frame")
		row.Name = string.format("SkeletonRow_%d", i)
		row.Size = UDim2.new(1, -16, 0, rowHeight)
		row.LayoutOrder = i  -- UIListLayout respects this for ordering
		row.BackgroundColor3 = Theme.color.surface.secondary
		row.BackgroundTransparency = 0.95
		row.ZIndex = zIndex
		row.Parent = parent
		
		corner(row, Theme.corners.sm)
		
		local skeletonStroke = Instance.new("UIStroke")
		skeletonStroke.Color = Theme.color.text.tertiary
		skeletonStroke.Thickness = 1
		skeletonStroke.Transparency = 0.7
		skeletonStroke.Parent = row
		
		-- Create placeholder content for each skeleton row
		local numItems = IS_MOBILE and 3 or 5
		for j = 1, numItems do
			local item = Instance.new("Frame")
			item.Size = UDim2.new(0.8, -4, 0, rowHeight - 4)
			item.Position = UDim2.new((j - 1) / numItems, 0, 0, 2)
			item.BackgroundColor3 = Theme.color.surface.primary
			item.BackgroundTransparency = 0.98
			item.ZIndex = zIndex + i
			item.Parent = row
			
			local itemStroke = Instance.new("UIStroke")
			itemStroke.Color = Theme.color.text.tertiary
			itemStroke.Thickness = 1
			itemStroke.Transparency = 0.6
			itemStroke.Parent = item
		end
	end

	-- harborheist-t6gt: shimmer overlay on skeleton rows.
	-- A subtle white Frame whose BackgroundTransparency cycles between
	-- 0.95 and 0.98 over a 2-second sine-wave period at 20fps. A single
	-- task.spawn loop drives all overlays (one loop, not N) and
	-- self-terminates when the first overlay loses its parent (rows
	-- destroyed/replaced by real content — callers like showLoading
	-- clear the parent's children, which sets Parent to nil).
	if config.animated ~= false then
		local shimmerOverlays = {}
		for i = 1, rows do
			local row = parent:FindFirstChild(string.format("SkeletonRow_%d", i))
			if row then
				local shimmer = Instance.new("Frame")
				shimmer.Name = "ShimmerOverlay"
				shimmer.Size = UDim2.new(1, 0, 1, 0)
				shimmer.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				shimmer.BackgroundTransparency = 0.95
				shimmer.ZIndex = zIndex + i + 10
				shimmer.Parent = row
				corner(shimmer, Theme.corners.sm)
				table.insert(shimmerOverlays, shimmer)
			end
		end
		task.spawn(function()
			local startTime = os.clock()
			while #shimmerOverlays > 0 and shimmerOverlays[1].Parent do
				local t = os.clock() - startTime
				local wave = (math.sin(t * math.pi) + 1) / 2
				local trans = 0.95 + wave * 0.03
				for _, overlay in ipairs(shimmerOverlays) do
					if overlay.Parent then
						overlay.BackgroundTransparency = trans
					end
				end
				task.wait(0.05)
			end
		end)
	end

	parent.LoadingSpinner = spinner
end

-- (harborheist-au38) showLoading + showEmptyState removed: were only called
-- by the now-removed refreshPanelState. No other call sites in the codebase.

-- (harborheist-au38) refreshPanelState removed: complete but unused function.

-- ============================================================
-- harborheist-i39g.1: Fake elevation/shadow system.
-- Roblox UI has no native drop-shadows, so elevation is faked with
-- layered black Frames behind the element, each progressively larger
-- and more transparent — the further out, the fainter. Consumes the
-- Theme.shadows configs defined in the design-token system (uabg.7),
-- proving those tokens are usable (single source of truth).
--
-- Shadow layers are parented to the element itself (ZIndex = element's
-- ZIndex - 1) and auto-destroy when the element is destroyed. They
-- extend past the element bounds via Size > 1 and negative Position.
-- IMPORTANT: apply to elements WITHOUT a UIListLayout on them (panels,
-- toasts, prompts, cards) — a UIListLayout would override the shadow
-- frames' explicit Position. For layout containers, wrap in a plain
-- Frame and apply elevation to the wrapper.
--
-- Duplicate-safe: if the element already has Shadow_N children, they
-- are removed and recreated (supports re-elevation on state change).
-- ============================================================
local function applyElevation(element, level)
	local config = Theme.shadows[level] or Theme.shadows.low
	-- Remove existing shadow layers (re-elevation support).
	for _, child in ipairs(element:GetChildren()) do
		if child.Name:match("^Shadow_%d+$") then
			child:Destroy()
		end
	end
	for i = 1, config.layers do
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow_" .. i
		shadow.BackgroundColor3 = Color3.new(0, 0, 0)
		shadow.BackgroundTransparency = 1 - (config.alpha * (1 - (i - 1) / config.layers))
		shadow.Size = UDim2.new(1, config.spread * i, 1, config.spread * i)
		shadow.Position = UDim2.new(0, -config.spread * i / 2, 0, -config.spread * i / 2)
		shadow.ZIndex = element.ZIndex - 1
		shadow.Active = false
		shadow.Parent = element
		corner(shadow, Theme.corners.lg)
	end
end

-- Register on Theme so the function is exported as part of the design
-- system (silences FunctionUnused; downstream beads call
-- Theme.applyElevation(element, "low")).
Theme.applyElevation = applyElevation

-- ============================================================
-- harborheist-2wuo.4: Reusable transition library.
-- Named TweenInfo presets + helper functions for common animations.
-- Existing EASE_* constants remain in use (this is additive, not a
-- replacement); new code can use Transitions for semantic clarity.
--
-- Usage:
--   Transitions.tween(panel, { BackgroundTransparency = 0.1 }, "normal", "out")
--   Transitions.fadeIn(label, 0.2)   -- tweens BackgroundTransparency + TextTransparency
--   Transitions.fadeOut(label, 0.2)  -- tweens to transparent
--   Transitions.scale(card, 0.94, 1, "spring")
--   Transitions.slide(panel, fromPos, toPos, "normal", "out")
--
-- The helpers return the running TweenService tween object so callers
-- can :Wait() for completion or :Cancel() if superseded.
-- ============================================================
local Transitions = {}

-- Duration presets (seconds). Match the existing EASE_* values so the
-- library is consistent with the hand-tuned timings already in the file.
Transitions.durations = {
	fast = 0.12, -- matches EASE_FAST
	normal = 0.22, -- matches EASE_OUT
	slow = 0.5,
}

-- Easing presets: pre-built TweenInfo objects keyed by semantic name.
-- Callers pass the NAME (string), not the TweenInfo, to helpers — the
-- library resolves it. This avoids importing TweenInfo at every call site.
Transitions._easings = {
	out = EASE_OUT,
	["in"] = EASE_IN,
	spring = EASE_POP,
	fast = EASE_FAST,
	inOut = TweenInfo.new(Transitions.durations.normal, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
	sine = TweenInfo.new(Transitions.durations.slow, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

-- Resolve a duration name or raw number, plus an easing name or TweenInfo.
local function resolveTweenInfo(duration, easing)
	local dur = type(duration) == "number" and duration
		or Transitions.durations[duration] or Transitions.durations.normal
	local ti = type(easing) == "table" and easing
		or Transitions._easings[easing] or Transitions._easings.out
	-- Override the resolved TweenInfo's duration with the requested value
	-- (easing presets carry a default duration; an explicit duration wins).
	if ti.Time ~= dur then
		ti = TweenInfo.new(dur, ti.EasingStyle, ti.EasingDirection)
	end
	return ti
end

-- Generic: tween any set of properties on an element. Returns the tween.
function Transitions.tween(element, props, duration, easing)
	local ti = resolveTweenInfo(duration, easing)
	local t = TweenService:Create(element, ti, props)
	t:Play()
	return t
end

-- Fade in: tween BackgroundTransparency (and TextTransparency for text
-- elements) to 0 / a caller-specified target. Returns the tween.
function Transitions.fadeIn(element, duration, targetTransparency)
	local props = { BackgroundTransparency = targetTransparency or 0 }
	if element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
		props.TextTransparency = targetTransparency or 0
	end
	return Transitions.tween(element, props, duration, "out")
end

-- Fade out: tween transparencies to 1 (fully invisible). Returns the tween.
function Transitions.fadeOut(element, duration)
	local props = { BackgroundTransparency = 1 }
	if element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
		props.TextTransparency = 1
	end
	return Transitions.tween(element, props, duration, "in")
end

-- Scale: tween a UIScale's Scale property. Auto-creates a UIScale if the
-- element doesn't have one (common pattern in this file). Returns the tween.
function Transitions.scale(element, fromScale, toScale, duration, easing)
	local scale = element:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = element
	end
	scale.Scale = fromScale or 1
	return Transitions.tween(scale, { Scale = toScale }, duration, easing or "spring")
end

-- Slide: tween Position from one UDim2 to another. Returns the tween.
function Transitions.slide(element, fromPos, toPos, duration, easing)
	element.Position = fromPos or element.Position
	return Transitions.tween(element, { Position = toPos }, duration, easing or "out")
end

-- Rotate: tween Rotation property for spin effects. Returns the tween.
function Transitions.rotate(element, degrees, duration, easing)
	local currentRotation = element.Rotation or 0
	return Transitions.tween(element, { Rotation = (currentRotation + degrees) % 360 }, duration, easing or "spring")
end

-- Pulse: create a pulsing animation that oscillates between two values.
-- Returns the tween object for cancellation if needed.
-- harborheist-5rcp.3 (ultrathink): the original implementation was broken —
-- it tweened ONCE to the midpoint and the Completed handler called :Cancel()
-- (a no-op on an already-completed tween). No oscillation ever happened. The
-- proper pattern uses TweenInfo's repeatCount=-1 + reverses=true to bounce
-- the property back and forth indefinitely until cancelled.
function Transitions.pulse(element, property, minVal, maxVal, duration, easing)
	-- harborheist-2wuo.3: nil safety - validate parameters before use
	if not element or not property then
		warn("Transitions.pulse: missing element or property")
		return nil
	end

	-- Seed the start value so the first half-cycle begins from minVal.
	element[property] = minVal

	local ti = resolveTweenInfo(duration or 1, easing or "sine")
	-- Override to an infinite reversing bounce regardless of the preset's
	-- own repeatCount/reverses defaults.
	ti = TweenInfo.new(ti.Time, ti.EasingStyle, ti.EasingDirection, -1, true, 0)

	local tweenObj = TweenService:Create(element, ti, {
		[property] = maxVal,
	})

	tweenObj:Play()
	return tweenObj
end

-- Stagger: create a staggered animation for multiple elements.
-- Returns a table of tweens that can be cancelled together.
-- harborheist-5rcp.3 (ultrathink): THREE bugs in the original:
--   1. `delay` param was accepted but never used — all tweens started at once.
--   2. `easing` param was accepted but never used — hardcoded Quad/Out.
--   3. `props` was passed straight to TweenService:Create INCLUDING the
--      `duration` key, which is not a tweenable property (silently ignored
--      on most instances, but invalid). Now split: duration is extracted for
--      the TweenInfo, the rest are the target props.
--   4. Completed handler removed tweens[1] (always the first) instead of the
--      finished tween — wrong element removed if completion order differed.
function Transitions.stagger(elements, props, delay, easing)
	local duration = (type(props) == "table" and props.duration) or 0.22
	-- Build the clean target-properties table (strip the `duration` meta key).
	local targetProps = {}
	if type(props) == "table" then
		for k, v in pairs(props) do
			if k ~= "duration" then
				targetProps[k] = v
			end
		end
	end

	local ti = resolveTweenInfo(duration, easing or "out")
	local staggerDelay = delay or 0.05
	local tweens = {}

	for i, element in ipairs(elements) do
		-- Rebuild TweenInfo per element so each gets its own Delay offset.
		local elementTi = TweenInfo.new(ti.Time, ti.EasingStyle, ti.EasingDirection, 0, false, staggerDelay * (i - 1))
		local tween = TweenService:Create(element, elementTi, targetProps)
		-- Remove THIS tween (not tweens[1]) when it completes.
		tween.Completed:Connect(function()
			for idx, t in ipairs(tweens) do
				if t == tween then
					table.remove(tweens, idx)
					break
				end
			end
		end)
		tween:Play()
		table.insert(tweens, tween)
	end
	return tweens
end

-- Register on Theme (silences unused; downstream code calls
-- Theme.Transitions.fadeIn(...) etc.).
Theme.Transitions = Transitions

-- R4 polish: staggered list entrance. Rows in a rebuilt list fade + settle
-- in with a per-index delay (35ms, capped at 8) — the Stripe/Linear list
-- feel. Walks descendants, captures their CURRENT transparencies, zeroes
-- them, then tweens back after the stagger delay. Positions are untouched
-- (UIListLayout owns them — tweening Position would fight the layout).
-- Callers: inventory rows, raid target rows, collection cards.
local STAGGER_STEP = 0.035
local STAGGER_MAX_INDEX = 8
local function staggerFadeIn(root, index)
	local delay = math.min(math.max(index - 1, 0), STAGGER_MAX_INDEX) * STAGGER_STEP
	local targets = {}
	local function capture(obj)
		if obj:IsA("GuiObject") then
			local entry = { bg = obj.BackgroundTransparency }
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				entry.text = obj.TextTransparency
				obj.TextTransparency = 1
			end
			obj.BackgroundTransparency = 1
			targets[obj] = entry
		end
	end
	capture(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			capture(descendant)
		elseif descendant:IsA("UIStroke") then
			targets[descendant] = { stroke = descendant.Transparency }
			descendant.Transparency = 1
		end
	end
	task.delay(delay, function()
		for obj, entry in pairs(targets) do
			if obj.Parent then
				if entry.bg ~= nil then
					TweenService:Create(obj, EASE_OUT, { BackgroundTransparency = entry.bg }):Play()
				end
				if entry.text ~= nil then
					TweenService:Create(obj, EASE_OUT, { TextTransparency = entry.text }):Play()
				end
				if entry.stroke ~= nil then
					TweenService:Create(obj, EASE_OUT, { Transparency = entry.stroke }):Play()
				end
			end
		end
	end)
end

-- harborheist-53q2 (EPIC 38): Rich empty-state card. Replaces the bare
-- "No data" TextLabels with a centered icon + title + description + action
-- card, faded in via the stagger helper. Lives AFTER staggerFadeIn because
-- Luau binds locals lexically at the definition site (same trap as the
-- makeOverlayFrame P0 at :508). cfg = { icon, title, description, action,
-- order = <LayoutOrder>, accent = <Color3> }. Icon uses a Unicode glyph;
-- every color is a Theme token and all exceed 4.5:1 contrast on the panel
-- surface (text.primary ~16:1, text.secondary ~7:1, brand accents ~7-12:1).
local function renderEmptyState(parent, cfg)
	local cardH = IS_MOBILE and 220 or 200
	local card = Instance.new("Frame")
	card.Name = "EmptyState"
	card.Size = UDim2.new(1, 0, 0, cardH)
	card.BackgroundColor3 = Theme.color.surface.secondary
	card.BackgroundTransparency = 0.94
	card.LayoutOrder = cfg.order or 1
	card.ZIndex = 26
	card.Parent = parent
	corner(card, Theme.corners.lg)

	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.VerticalAlignment = Enum.VerticalAlignment.Center
	stack.Padding = UDim.new(0, Theme.spacing.sm)
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Parent = card

	local accent = cfg.accent or Theme.color.accent.base

	makeLabel(card, {
		Size = UDim2.new(0, 64, 0, 64),
		Text = cfg.icon or "○",
		Font = Theme.type.fonts.body,
		TextSize = 64,
		TextColor3 = accent,
		LayoutOrder = 1,
		ZIndex = 27,
	})
	makeLabel(card, {
		Size = UDim2.new(1, -Theme.spacing.xxl * 2, 0, 26),
		Text = cfg.title,
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.md,
		TextColor3 = Theme.color.text.primary,
		LayoutOrder = 2,
		ZIndex = 27,
	})
	makeLabel(card, {
		Size = UDim2.new(1, -Theme.spacing.xxl * 2, 0, IS_MOBILE and 40 or 34),
		Text = cfg.description,
		Font = Theme.type.fonts.body,
		TextSize = Theme.type.sizes.sm,
		TextColor3 = Theme.color.text.secondary,
		TextWrapped = true,
		LayoutOrder = 3,
		ZIndex = 27,
	})
	makeLabel(card, {
		Size = UDim2.new(1, -Theme.spacing.xxl * 2, 0, 20),
		Text = cfg.action,
		Font = Theme.type.fonts.med,
		TextSize = Theme.type.sizes.sm,
		TextColor3 = accent,
		LayoutOrder = 4,
		ZIndex = 27,
	})

	staggerFadeIn(card, 1)
	return card
end

local function formatCash(n)
	local s = tostring(math.floor(n + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return formatted
end

-- harborheist-akdb (P1 load-order fix): formatRaidTime must be declared
-- BEFORE its earliest caller (renderRaidTargets, ~:2351). It previously sat
-- ~1600 lines lower (~:4084); Luau binds locals lexically at the definition
-- site, so the renderRaidTargets call read a nil GLOBAL and every locked /
-- cooldown raid-target row crashed the render thread at runtime.
local function formatRaidTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

-- ============================================================
-- HUD: cash card (top-left) — glass card with animated counter
-- ============================================================
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Size = IS_MOBILE and UDim2.new(0, 178, 0, 64) or UDim2.new(0, 224, 0, 78)
hud.Position = UDim2.new(0, 14, 0, SAFE_TOP + 6)
table.insert(safeTopConsumers, function()
	hud.Position = UDim2.new(0, 14, 0, SAFE_TOP + 6)
end)
hud.BackgroundColor3 = Theme.color.surface.primary
hud.BackgroundTransparency = 0.18
hud.Parent = screenGui
corner(hud, Theme.corners.lg)
stroke(hud, 0.85)
Gradients.apply(hud, "surface.hud")
-- harborheist-n9x9: subtle HUD lift. hud has no UIListLayout / no clip, so
-- the low-elevation shadow layers (ZIndex 0 = hud default 1 - 1) render
-- behind the cash card against the screen background.
applyElevation(hud, "low")

makeLabel(hud, {
	Size = UDim2.new(0, 76, 0, 12),
	Position = UDim2.new(0, 14, 0, IS_MOBILE and 6 or 8),
	Text = "BALANCE",
	Font = Theme.type.fonts.bold,
	TextSize = Theme.type.sizes.xs,
	TextColor3 = Theme.color.text.secondary,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local cashLabel = makeLabel(hud, {
	Size = UDim2.new(1, -24, 0, IS_MOBILE and 28 or 34),
	Position = UDim2.new(0, 14, 0, IS_MOBILE and 14 or 17),
	Text = "$0",
	Font = Theme.type.fonts.head,
	TextSize = IS_MOBILE and Theme.type.sizes.lg or Theme.type.sizes.xl,
	TextColor3 = Theme.color.money,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local incomeLabel = makeLabel(hud, {
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.new(0, 14, 1, IS_MOBILE and -22 or -26),
	Text = "+$0.0/min",
	Font = Theme.type.fonts.med,
	TextSize = IS_MOBILE and Theme.type.sizes.xs or Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.secondary,
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

-- harborheist-kecr: desktop hover affordance — the whole card opens the
-- aquarium panel but nothing signaled clickability, so players discovered
-- it by accident. MouseEnter lifts the background and brightens the card
-- stroke (the pressFeedback language buttons already speak); touch has no
-- hover, so this is desktop-only.
if not IS_MOBILE then
	local hudStroke = hud:FindFirstChildOfClass("UIStroke")
	hudClick.MouseEnter:Connect(function()
		TweenService:Create(hud, EASE_FAST, { BackgroundTransparency = 0.08 }):Play()
		if hudStroke then
			TweenService:Create(hudStroke, EASE_FAST, { Transparency = 0.45 }):Play()
		end
	end)
	hudClick.MouseLeave:Connect(function()
		TweenService:Create(hud, EASE_FAST, { BackgroundTransparency = 0.18 }):Play()
		if hudStroke then
			TweenService:Create(hudStroke, EASE_FAST, { Transparency = 0.85 }):Play()
		end
	end)
end

-- TASK 24.1 (hvfh.4.1): dual-purpose income line — rate always shown, plus a
-- claim-green "$N ready" segment while unclaimed income exists. One line: no
-- HUD height change, no carryPill shift. #32A050 == Color3.fromRGB(50,160,80),
-- the claimButton green used in render().
local CLAIM_GREEN_HEX = "32A050"

-- TASK 22.3 (hvfh.2.3): adaptive income-rate formatting. Formats the SAME
-- authoritative snapshot value (state.incomePerSec) — NEVER re-derive income
-- client-side (R2.2/dt9.2, see note near render()). Sub-0.1/sec rates (a
-- starter tank of 1-2 Commons) render per-minute so early players see a
-- non-zero rate; 0.1-10/sec gets 2 decimals; >10/sec keeps the legacy
-- 1-decimal per-sec form. "/min" and "/sec" suffixes are equal width, so the
-- HUD card does not jump when the format flips threshold.
local function formatIncomeRate(ratePerSec)
	ratePerSec = ratePerSec or 0
	if ratePerSec < 0.1 then
		return string.format("+$%.1f/min", ratePerSec * 60)
	elseif ratePerSec <= 10 then
		return string.format("+$%.2f/sec", ratePerSec)
	else
		return string.format("+$%.1f/sec", ratePerSec)
	end
end

local function updateIncomeLine(readyTransparency)
	local ready = state and state.unclaimedIncome or 0
	if ready > 0 then
		-- One notch smaller on the 178px mobile card so rate + ready fit on
		-- one line (the no-layout-shift path; 6+ digit ready values may still
		-- clip on mobile — accepted tradeoff, recorded in the bead).
		incomeLabel.TextSize = IS_MOBILE and Theme.type.sizes.xs or Theme.type.sizes.sm
		incomeLabel.Text = string.format(
			'%s  •  <font color="#%s" transparency="%.2f"><b>$%s ready</b></font>',
			formatIncomeRate(state.incomePerSec), CLAIM_GREEN_HEX, readyTransparency or 0, formatCash(ready)
		)
	else
		incomeLabel.TextSize = IS_MOBILE and Theme.type.sizes.xs or Theme.type.sizes.sm
		incomeLabel.Text = formatIncomeRate(state and state.incomePerSec or 0)
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
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.status.good,
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
	-- R4 polish #4: duration scales with the delta — +$12 snaps, +$48,000
	-- savors. Fixed 0.45s made jackpots feel identical to minnows.
	local delta = math.abs(target - from)
	local dur = math.clamp(0.35 + math.log10(math.max(1, delta)) * 0.25, 0.4, 1.4)
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
table.insert(safeTopConsumers, function()
	carryPill.Position = UDim2.new(0, 14, 0, SAFE_TOP + (IS_MOBILE and 76 or 90))
end)
carryPill.BackgroundColor3 = Theme.color.surface.primary
carryPill.BackgroundTransparency = 0.25
carryPill.Parent = screenGui
corner(carryPill, Theme.corners.pill)
stroke(carryPill, 0.88)
-- harborheist-n9x9: carry pill low-elevation lift (card tier).
applyElevation(carryPill, "low")

local carryLabel = makeLabel(carryPill, {
	Size = UDim2.new(1, -20, 1, 0),
	Position = UDim2.new(0, Theme.spacing.md, 0, 0),
	Text = "On line: 0 / 3 fish",
	Font = Theme.type.fonts.med,
	TextSize = IS_MOBILE and Theme.type.sizes.xs or Theme.type.sizes.sm,
	TextColor3 = Theme.color.accent.soft,
	TextXAlignment = Enum.TextXAlignment.Left,
})

-- ============================================================
-- Toast notifications (top-center, slide + fade, accent bar)
-- TASK 24.3 (hvfh.4.3): auto-size height, cap 3 visible,
-- FIFO queue w/ severity jump, category chip (color + label).
-- ============================================================
local MAX_VISIBLE_TOASTS = 3
-- R3 audit #2: cap the backlog so a raid flurry can't queue 40 stale toasts
-- that surface one-by-one over the next 2 minutes.
local MAX_TOAST_QUEUE = 8
local MIN_TOAST_H = IS_MOBILE and 40 or 42
local TOAST_LIFETIME = 3.6
local TOAST_FADE = 0.4
local TOAST_CATEGORIES = {
	catch = "CATCH", quest = "QUEST", raid = "RAID",
	["raid-victim"] = "RAID!", ["raid-attacker"] = "RAID",
	["raid-info"] = "RAID", lock = "LOCK", economy = "ECON",
	discovery = "NEW!", cast = "CAST", missed = "MISS",
	datastore = "SAVE", info = "INFO", zone = "ZONE",
}
local SEVERE_CATEGORIES = { ["raid-victim"] = true, datastore = true }

-- harborheist-6388.1: Toast variant system — 5 variants with distinct
-- colors, durations, and persistence. Categories map to variants so
-- showToastDirect can resolve the right duration/behavior from the
-- category alone (works for both showNotification and drainToastQueue).
-- Caller-passed colors take precedence (variant.color is a default).
local TOAST_VARIANTS = {
	info = { color = Theme.color.accent.soft, duration = 3.6, persistent = false },
	success = { color = Theme.color.status.good, duration = 3.6, persistent = false },
	warning = { color = Theme.color.status.warn, duration = 4.5, persistent = false },
	error = { color = Theme.color.status.bad, duration = 6, persistent = false },
	critical = { color = Theme.color.status.bad, duration = 0, persistent = true },
}

local CATEGORY_TO_VARIANT = {
	catch = "success", quest = "info", raid = "warning",
	["raid-victim"] = "critical", ["raid-attacker"] = "warning",
	["raid-info"] = "info", lock = "info", economy = "info",
	discovery = "info", cast = "info", missed = "warning",
	datastore = "critical", info = "info", zone = "warning",
}

-- Host geometry is consumed by the onboarding prompt clamp (TASK 28.2,
-- updateOnboardingPromptOffset) — single-sourced here, never re-literal'd.
local TOAST_HOST_TOP_OFFSET = 8
local TOAST_HOST_HEIGHT = 300
local toastHost = Instance.new("Frame")
toastHost.Name = "Toasts"
toastHost.AnchorPoint = Vector2.new(0.5, 0)
toastHost.Size = UDim2.new(0, IS_MOBILE and 320 or 400, 0, TOAST_HOST_HEIGHT)
toastHost.Position = UDim2.new(0.5, 0, 0, SAFE_TOP + TOAST_HOST_TOP_OFFSET)
table.insert(safeTopConsumers, function()
	toastHost.Position = UDim2.new(0.5, 0, 0, SAFE_TOP + TOAST_HOST_TOP_OFFSET)
end)
toastHost.BackgroundTransparency = 1
toastHost.ZIndex = 55
toastHost.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHost

local toastOrder = 0
local activeToastCount = 0
local toastQueue = {}

-- Forward declaration: showToastDirect calls drainToastQueue (line 517)
-- before it's defined, causing a runtime error.
local drainToastQueue
-- (harborheist-au38) dismissToast forward declaration removed: the upvalue was
-- assigned but never read. Per-call local dismiss() is used by all consumers.

local function showToastDirect(message, color, category, actions)
	toastOrder += 1
	activeToastCount += 1
	-- harborheist-n9x9: wrap each toast in a plain (no-clip, no-layout) frame
	-- so applyElevation's shadow layers render OUTSIDE the toast —
	-- toast.ClipsDescendants (set below) would clip a directly-parented shadow
	-- to the toast bounds, hiding it. wrap has NO AutomaticSize: a relative-
	-- sized shadow layer (Size scale 1) under an AutomaticSize parent
	-- feedback-loops (wrap grows to fit the shadow, whose scale-1 height grows
	-- with wrap, ...), so wrap's height is tracked to the toast's AbsoluteSize
	-- instead. Floors at MIN_TOAST_H; worst case is a 1-frame shadow lag.
	local wrap = Instance.new("Frame")
	wrap.Name = "ToastWrap"
	wrap.Size = UDim2.new(1, 0, 0, MIN_TOAST_H)
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = toastOrder
	wrap.ZIndex = 55
	wrap.Parent = toastHost
	applyElevation(wrap, "medium")

	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, MIN_TOAST_H)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.BackgroundColor3 = Theme.color.surface.primary
	toast.BackgroundTransparency = 1
	toast.ZIndex = 56
	toast.Parent = wrap
	corner(toast, Theme.corners.md)
	toast:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		wrap.Size = UDim2.new(1, 0, 0, math.max(MIN_TOAST_H, toast.AbsoluteSize.Y))
	end)
	local tStroke = stroke(toast, 1)
	-- hvfh.4.3 review fixup: enforce the bead's min height — AutomaticSize
	-- alone would shrink a degenerate (empty/short) toast below 40/2px.
	local toastMinSize = Instance.new("UISizeConstraint")
	toastMinSize.MinSize = Vector2.new(0, MIN_TOAST_H)
	toastMinSize.Parent = toast
	-- R3 audit #3: long wrapped messages grew unbounded via AutomaticSize
	-- inside the fixed 300px host — 3 fat toasts overflowed onto panels and
	-- overlays beneath. Cap at ~3 text lines and clip the rest.
	local toastMaxSize = Instance.new("UISizeConstraint")
	toastMaxSize.MaxSize = Vector2.new(math.huge, MIN_TOAST_H + 54)
	toastMaxSize.Parent = toast
	toast.ClipsDescendants = true
	local accentBar = Instance.new("Frame")
	accentBar.Size = UDim2.new(0, 4, 1, -14)
	accentBar.Position = UDim2.new(0, 8, 0, 7)
	accentBar.BackgroundColor3 = color
	accentBar.BackgroundTransparency = 1
	accentBar.ZIndex = 57
	accentBar.Parent = toast
	corner(accentBar, Theme.corners.hairline)
	local chip = makeLabel(toast, {
		Size = UDim2.new(0, 80, 0, 16),
		Position = UDim2.new(0, 18, 0, 4),
		Text = TOAST_CATEGORIES[category] or "INFO",
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = color,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 58,
	})
	local text = makeLabel(toast, {
		Size = UDim2.new(1, -32, 0, 0),
		Position = UDim2.new(0, 22, 0, 20),
		Text = message,
		Font = Theme.type.fonts.med,
		TextSize = Theme.type.sizes.sm,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 57,
	})
	text.AutomaticSize = Enum.AutomaticSize.Y
	-- hvfh.4.3 review fixup: bottom breathing room via label-internal
	-- padding. (Padding on the LABEL, not the toast, so the accent bar's
	-- scale height keeps resolving against the full toast height.)
	local textBottomPad = Instance.new("UIPadding")
	textBottomPad.PaddingBottom = UDim.new(0, Theme.spacing.sm)
	textBottomPad.Parent = text
	TweenService:Create(toast, EASE_OUT, { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(tStroke, EASE_OUT, { Transparency = 0.82 }):Play()
	TweenService:Create(accentBar, EASE_OUT, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(chip, EASE_OUT, { TextTransparency = 0 }):Play()
	TweenService:Create(text, EASE_OUT, { TextTransparency = 0 }):Play()
	-- R4 polish: spring pop on entrance — the comment header promises
	-- "slide + fade" but only fades ran; a quick 0.94→1 pop reads as motion
	-- without fighting the UIListLayout (which owns Position).
	local toastScale = Instance.new("UIScale")
	toastScale.Scale = 0.94
	toastScale.Parent = toast
	TweenService:Create(toastScale, EASE_POP, { Scale = 1 }):Play()
	-- harborheist-6388.1: variant-aware duration from CATEGORY_TO_VARIANT.
	-- Unmapped categories and variant.duration=0 fall back to TOAST_LIFETIME.
	local vName = CATEGORY_TO_VARIANT[category]
	local vConf = vName and TOAST_VARIANTS[vName]
	local lifetime = (vConf and vConf.duration > 0) and vConf.duration or TOAST_LIFETIME
	local persistent = vConf and vConf.persistent
	-- Shared dismiss logic (fade out + destroy + counter + queue drain).
	-- harborheist-lkd3: defined BEFORE the action buttons as a per-call local
	-- so every consumer (timer, close button, action buttons) captures THIS
	-- toast's dismiss. Previously the action-button closure dereferenced the
	-- shared dismissToast upvalue at click time — and every later toast
	-- reassigns that upvalue, so clicking an older toast's action dismissed
	-- the NEWEST toast while the clicked one leaked on screen (and its
	-- activeToastCount decrement never ran, starving the queue).
	-- The dismissed guard prevents a double-dismiss race: if the auto-dismiss
	-- timer fires while an action-button click is mid-fade (yielding on
	-- t.Completed:Wait()), the second call would decrement activeToastCount
	-- again — driving it negative and letting more than MAX_VISIBLE_TOASTS
	-- appear on screen over time.
	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		if toast.Parent then
			local fade = TweenInfo.new(TOAST_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(toast, fade, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(tStroke, fade, { Transparency = 1 }):Play()
			TweenService:Create(accentBar, fade, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(chip, fade, { TextTransparency = 1 }):Play()
			local t = TweenService:Create(text, fade, { TextTransparency = 1 })
			t:Play()
			t.Completed:Wait()
			wrap:Destroy()
		end
		activeToastCount -= 1
		drainToastQueue()
	end
	-- (harborheist-au38) dismissToast = dismiss assignment removed: the upvalue
	-- was never read after assignment. All consumers use the per-call local.
	-- Render action buttons if provided (max 2 per toast, right-aligned)
	if actions then
		-- harborheist-rk2h: action buttons were 24px tall — below the 44px
		-- mobile touch-target minimum. On mobile they grow to 44px and the
		-- toast min height rises to 52px so ClipsDescendants can't shave them.
		if IS_MOBILE then
			toastMinSize.MinSize = Vector2.new(0, math.max(MIN_TOAST_H, 52))
		end
		for i, action in ipairs(actions) do
			if i > 2 then break end -- max 2 action buttons per toast
			local btn = makeButton(toast, {
				Size = UDim2.new(0, 64, 0, IS_MOBILE and 44 or 24),
				Position = UDim2.new(1, -75 - (i-1)*68, 0.5, IS_MOBILE and -22 or -12),
				Text = action.label or "",
				Font = Theme.type.fonts.med,
				TextSize = IS_MOBILE and Theme.type.sizes.xxs or Theme.type.sizes.xs,
				BackgroundColor3 = Theme.color.surface.elevated,
				TextColor3 = color,
				CornerRadius = Theme.corners.sm,
				ZIndex = 60 + i,
			})
			btn.Activated:Connect(function()
				if action.callback then
					action.callback()
				end
				dismiss()
			end)
		end
	end
	if not persistent then
		task.delay(lifetime, dismiss)
	else
		-- Persistent toasts require manual dismissal via a close button.
		-- harborheist-rk2h: the ✕ was 20x20 — far below the 44px mobile
		-- touch-target minimum. On mobile it grows to 44x44, the toast min
		-- height rises to 52px (no clipping), and the message narrows so
		-- its first lines don't run underneath the button.
		if IS_MOBILE then
			toastMinSize.MinSize = Vector2.new(0, math.max(MIN_TOAST_H, 52))
			text.Size = UDim2.new(1, -80, 0, 0)
		end
		local closeBtn = makeButton(toast, {
			Size = UDim2.new(0, IS_MOBILE and 44 or 20, 0, IS_MOBILE and 44 or 20),
			Position = UDim2.new(1, IS_MOBILE and -48 or -24, 0, 4),
			Text = "✕",
			TextSize = Theme.type.sizes.xs,
			BackgroundColor3 = Theme.color.surface.elevated,
			TextColor3 = Theme.color.text.secondary,
			CornerRadius = Theme.corners.pill,
			ZIndex = 59,
		})
		closeBtn.Activated:Connect(dismiss)
	end
end

-- Assign to the forward-declared local
drainToastQueue = function()
	while activeToastCount < MAX_VISIBLE_TOASTS and #toastQueue > 0 do
		local pending = table.remove(toastQueue, 1)
		showToastDirect(pending.message, pending.color, pending.category, pending.actions)
	end
end

-- harborheist-keza: removed forward declaration of addToHistory (function removed — dead code).

local function showNotification(message, color, category, actions)
	category = category or "info"
	-- harborheist-6388.1: resolve toast variant from category for the
	-- color default (caller-passed color still takes precedence).
	local variantName = CATEGORY_TO_VARIANT[category]
	local variant = variantName and TOAST_VARIANTS[variantName]
	color = color or (variant and variant.color) or Theme.color.accent.soft
	-- harborheist-6qyq: server-toast categories with a stinger attached.
	-- showNotification is the single funnel for every server toast, so
	-- category sounds live here (raid-victim: ALARM / robbed / defended).
	local stinger = NOTIFY_SOUNDS[category]
	if stinger then
		playSound(stinger.id, stinger.volume, stinger.speed)
	end
	if activeToastCount < MAX_VISIBLE_TOASTS then
		showToastDirect(message, color, category, actions)
	else
		local entry = { message = message, color = color, category = category, actions = actions }
		if SEVERE_CATEGORIES[category] then
			table.insert(toastQueue, 1, entry)
		else
			table.insert(toastQueue, entry)
		end
		-- R3 audit #2: unbounded queue → stale "You caught X" toasts surfacing
		-- minutes after a raid flurry. Evict the OLDEST non-severe entry
		-- beyond a cap (severe toasts keep their queue-jump priority).
		while #toastQueue > MAX_TOAST_QUEUE do
			local evicted = false
			for i, pending in ipairs(toastQueue) do
				if not SEVERE_CATEGORIES[pending.category] then
					table.remove(toastQueue, i)
					evicted = true
					break
				end
			end
			if not evicted then
				table.remove(toastQueue, #toastQueue)
			end
		end
	end
end

-- harborheist-egvu: one moment — finish the minigame first. Panels opening
-- during an active overlay render BENEATH it but their backdrop still eats
-- taps (gameProcessed=true), which makes the timing bar untappable and
-- guarantees a lost fish. Placed after showNotification (lexical scope).
local function overlayBlocksPanels()
	if activeOverlay then
		showNotification("One moment — finish the minigame first!", Theme.color.status.warn)
		return true
	end
	return false
end

-- ============================================================
-- Action bar / action-stack geometry constants (TASK 28.2 / hvfh.8.2)
-- Single source of truth for the onboarding-prompt offset AND the
-- mobile action stack / desktop action bar layout. Defined here (before
-- the first use at the onboarding prompt) so every site reads the same
-- values; adding/removing an ACTION keeps the prompt clear with zero
-- manual edits. (itt5: these definitions were lost in the hvfh.8.2
-- partial-staging and are restored here.)
-- ============================================================
local MOBILE_STACK_BOTTOM = 90
local MOBILE_STACK_PITCH = 70
-- harborheist-hqn1: EFFECTIVE pitch after viewport-fit scaling. layoutMobileStack
-- mutates this on short screens; updateOnboardingPromptOffset reads it so the
-- prompt tracks the actual (possibly shrunk) stack top, not the design default.
local mobileStackPitch = MOBILE_STACK_PITCH
local MOBILE_STACK_PADDING = 10
local PROMPT_STACK_GAP = 12
local DESKTOP_BAR_BOTTOM = 18
local DESKTOP_BAR_H = 58
local PROMPT_BAR_GAP = 8

-- ============================================================
-- Onboarding contextual prompts (TASK 9.2 / 0jc.2)
-- Dismissible inline banners driven by OnboardingService flags.
-- Shows one prompt at a time based on the player's progression stage.
-- Non-blocking, non-modal — sits just above the action bar.
-- ============================================================
local onboardingPrompt = Instance.new("Frame")
onboardingPrompt.Name = "OnboardingPrompt"
onboardingPrompt.AnchorPoint = Vector2.new(0.5, 1)
-- Mobile: above the right-edge action stack; desktop: above the bottom
-- action bar. The value below is only a startup placeholder (the prompt
-- is invisible until a stage fires) — the AUTHORITATIVE offset is derived
-- from the geometry constants above by updateOnboardingPromptOffset()
-- (defined where ACTIONS is declared) and re-applied on viewport resize.
onboardingPrompt.Position = UDim2.new(0.5, 0, 1, -(DESKTOP_BAR_BOTTOM + DESKTOP_BAR_H + PROMPT_BAR_GAP))
onboardingPrompt.Size = UDim2.new(IS_MOBILE and 1 or 0, IS_MOBILE and -24 or 360, 0, IS_MOBILE and 48 or 40)
onboardingPrompt.BackgroundColor3 = Theme.color.surface.secondary
onboardingPrompt.BackgroundTransparency = 0.1
onboardingPrompt.Visible = false
onboardingPrompt.ZIndex = 15
onboardingPrompt.Parent = screenGui
corner(onboardingPrompt, Theme.corners.md)
stroke(onboardingPrompt, 0.7, Theme.color.accent.base, 1.5)

local onboardingAccentBar = Instance.new("Frame")
onboardingAccentBar.Size = UDim2.new(0, 4, 1, -14)
onboardingAccentBar.Position = UDim2.new(0, 8, 0, 7)
onboardingAccentBar.BackgroundColor3 = Theme.color.accent.base
onboardingAccentBar.ZIndex = 16
onboardingAccentBar.Parent = onboardingPrompt
corner(onboardingAccentBar, Theme.corners.hairline)

local onboardingLabel = makeLabel(onboardingPrompt, {
	-- harborheist-bpem.1: widened right padding (-52 -> -60) to match the
	-- enlarged 44px close button, preserving the original 10px text/button
	-- overlap relationship (button bg covers the empty right label margin).
	Size = UDim2.new(1, -60, 1, 0),
	Position = UDim2.new(0, 20, 0, 0),
	Text = "",
	Font = Theme.type.fonts.med,
	TextSize = Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.primary,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 16,
})

local onboardingDismiss = makeButton(onboardingPrompt, {
	-- harborheist-bpem.1: 36px was below the 44pt mobile touch-target minimum.
	Size = UDim2.new(0, IS_MOBILE and 44 or 24, 0, IS_MOBILE and 44 or 24),
	Position = UDim2.new(1, IS_MOBILE and -50 or -30, 0.5, IS_MOBILE and -22 or -12),
	Text = "✕",
	TextSize = IS_MOBILE and 14 or Theme.type.sizes.xs,
	BackgroundColor3 = Theme.color.surface.elevated,
	TextColor3 = Theme.color.text.secondary,
	CornerRadius = Theme.corners.pill,
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
	onboardingAccentBar.BackgroundColor3 = color or Theme.color.accent.base
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
-- hvfh.4.3 (BronzeLynx plan-space note): anchor below the cap-3 toast
-- stack (3 toasts ~= 152px from SAFE_TOP+8) so first-catch toasts no
-- longer render on top of this prompt (toast ZIndex 51 > 16).
sellStorePrompt.Position = UDim2.new(0.5, 0, 0, SAFE_TOP + 170)
table.insert(safeTopConsumers, function()
	sellStorePrompt.Position = UDim2.new(0.5, 0, 0, SAFE_TOP + 170)
end)
sellStorePrompt.Size = UDim2.new(IS_MOBILE and 1 or 0, IS_MOBILE and -24 or 360, 0, IS_MOBILE and 126 or 116)
sellStorePrompt.BackgroundColor3 = Theme.color.surface.secondary
sellStorePrompt.BackgroundTransparency = 0.08
sellStorePrompt.Visible = false
-- R3 audit #22: above panels (25-27) — a first catch arriving while a panel
-- was open rendered this prompt BEHIND it, invisible until closed.
sellStorePrompt.ZIndex = 30
sellStorePrompt.Parent = screenGui
corner(sellStorePrompt, Theme.corners.spacious)
stroke(sellStorePrompt, 0.7, Theme.color.accent.base, 1.5)

makeLabel(sellStorePrompt, {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 10),
	Text = "You caught a fish!",
	Font = Theme.type.fonts.bold,
	TextSize = IS_MOBILE and 16 or Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.primary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 31,
})

makeLabel(sellStorePrompt, {
	Size = UDim2.new(1, -20, 0, 36),
	Position = UDim2.new(0, 10, 0, 34),
	Text = "Sell now for instant cash, or store it to earn income over time.",
	Font = Theme.type.fonts.body,
	TextSize = IS_MOBILE and 13 or Theme.type.sizes.xs,
	TextColor3 = Theme.color.text.secondary,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 31,
})

local sellStoreClose = makeButton(sellStorePrompt, {
	-- harborheist-bpem.1: 36px was below the 44pt mobile touch-target minimum.
	Size = UDim2.new(0, IS_MOBILE and 44 or 26, 0, IS_MOBILE and 44 or 26),
	Position = UDim2.new(1, IS_MOBILE and -49 or -31, 0, IS_MOBILE and 4 or 8),
	Text = "✕",
	TextSize = Theme.type.sizes.sm,
	BackgroundColor3 = Theme.color.surface.elevated,
	TextColor3 = Theme.color.text.secondary,
	CornerRadius = Theme.corners.pill,
	ZIndex = 31,
})

local sellStoreSellBtn = makeButton(sellStorePrompt, {
	Size = UDim2.new(0.48, -6, 0, IS_MOBILE and 44 or 36),
	Position = UDim2.new(0, 10, 1, IS_MOBILE and -56 or -48),
	Text = "SELL $0",
	BackgroundColor3 = Theme.color.status.good,
	TextColor3 = Theme.color.text.ink,
	CornerRadius = 10,
	ZIndex = 31,
})

local sellStoreStoreBtn = makeButton(sellStorePrompt, {
	Size = UDim2.new(0.48, -6, 0, IS_MOBILE and 44 or 36),
	Position = UDim2.new(0.52, 4, 1, IS_MOBILE and -56 or -48),
	Text = "STORE $0/min",
	BackgroundColor3 = Theme.color.accent.base,
	TextColor3 = Theme.color.text.ink,
	CornerRadius = 10,
	ZIndex = 31,
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
	sellStoreSellBtn.Text = string.format("SELL $%s", formatCash(fish.BaseSellValue or 0))
	sellStoreStoreBtn.Text = string.format("STORE $%.1f/min", fish.IncomePerMinute or 0)
	sellStorePrompt.Visible = true
	local scale = sellStorePrompt:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = sellStorePrompt
	scale.Scale = 0.92
	TweenService:Create(scale, EASE_POP, { Scale = 1 }):Play()
end

-- Failure reasons the server already notifies about (avoid duplicate toasts).
-- The server stays silent on rate_limited, no_session, bad_id,
-- fish_not_found, invalid_fish — those need a client-side toast.
-- (R3 audit #4: moved above the sellStore comparison prompt handlers —
-- Luau binds locals lexically at the definition site, so the SELL/STORE
-- button callbacks below would otherwise read these as nil globals.)
local SERVER_NOTIFIED_REASONS = {
	aquarium_full = true,
	aquarium_locked = true,
	raid_protected = true,
}

-- harborheist-cjya: never show raw snake_case server reason strings to
-- players ('Could not sell: fish_not_found' after a fast double-tap read
-- like a bug report, not a game). Known reasons get friendly copy; anything
-- unexpected falls back to a generic line.
local FRIENDLY_FAILURE_REASONS = {
	fish_not_found = "That fish is already gone.",
	invalid_fish = "That fish can't be moved right now.",
	rate_limited = "Slow down a moment...",
	no_session = "Still loading — try again in a second.",
	bad_id = "That didn't work — try again.",
}

local function friendlyFailureReason(verb, reason)
	local friendly = FRIENDLY_FAILURE_REASONS[reason]
	if friendly then
		return friendly
	end
	return "Could not " .. verb .. " — try again."
end

sellStoreClose.Activated:Connect(function()
	hideSellStorePrompt()
	markSellStoreComparisonSeen()
end)

sellStoreSellBtn.Activated:Connect(function()
	-- R3 audit #4: un-pcall'd invoke + no revalidation — a fish already
	-- sold/stored elsewhere failed silently with no toast at all.
	if sellStoreTargetFish then
		local ok, result = pcall(function()
			return Remotes.SellFish:InvokeServer(sellStoreTargetFish.InstanceId)
		end)
		if not ok or result == nil then
			showNotification("Couldn't sell that fish — try again.", Theme.color.status.bad)
		elseif result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
			showNotification(friendlyFailureReason("sell", result.reason), Theme.color.status.bad)
		end
	end
	hideSellStorePrompt()
	markSellStoreComparisonSeen()
end)

sellStoreStoreBtn.Activated:Connect(function()
	if sellStoreTargetFish then
		local ok, result = pcall(function()
			return Remotes.StoreSingleFish:InvokeServer(sellStoreTargetFish.InstanceId)
		end)
		if not ok or result == nil then
			showNotification("Couldn't store that fish — try again.", Theme.color.status.bad)
		elseif result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
			showNotification(friendlyFailureReason("store", result.reason), Theme.color.status.bad)
		end
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
-- harborheist-vasr: forward declaration — the context menu implementation
-- lives in the inventory section below, but hidePanels must be able to
-- destroy an open menu when its panel closes.
local activeContextMenu = nil
-- R4 polish: forward declaration — makePanel's mobile drag-to-dismiss
-- handlers (defined below, before hidePanels' body) need the upvalue.
-- Assigned where the original `local function hidePanels()` stood.
local hidePanels
-- TASK 25.1 (hvfh.5.1): forward-declared so hidePanels + render can
-- reference them before the sellButton handler section assigns them.
-- Lua closures capture upvalues lexically at definition time — a local
-- declared AFTER render()/hidePanels would be invisible to them (they'd
-- see globals instead). All four are assigned at the handler section below.
local disarmSellButton: any = nil
-- TASK 24.4 (hvfh.4.4): forward declaration for the action-bar active-panel
-- indicator. Same hook pattern as disarmSellButton — the implementation is
-- assigned AFTER the action bar is built (~:2937) because actionButtons is
-- declared there; referencing it from showPanel/hidePanels directly would
-- bind a nil global (Luau lexical binding at the definition site).
local updateActionBarIndicator: any = nil
local sellArmed = false
local sellArmPayout = 0
local computeSellPayout: any = nil

-- TASK 28.3 (hvfh.8.3): desktop panels are fixed pixel sizes (up to
-- 520x560) centered in a ScreenGui with IgnoreGuiInset=true — on small
-- windows they crop against the Roblox top bar and screen edges. Fit by
-- shrinking the panel's existing pop-animation UIScale (internal layout
-- proportions survive; no content reflow). The mobile bottom sheet
-- (0.78 height) already scales — untouched.
local PANEL_SCREEN_MARGIN = 24
local function desktopPanelFitScale(panel)
	if IS_MOBILE then
		return 1
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return 1
	end
	-- A centered panel has equal top/bottom gaps, and the top gap must
	-- clear the Roblox top bar (inset) plus the aesthetic margin.
	local availW = cam.ViewportSize.X - 2 * PANEL_SCREEN_MARGIN
	local availH = cam.ViewportSize.Y - 2 * (inset.Y + PANEL_SCREEN_MARGIN)
	-- Floor: on absurdly small windows (<~120px tall) availW/availH go
	-- negative — never hand UIScale a non-positive scale (blanks the panel).
	return math.max(0.1, math.min(1, availW / panel.Size.X.Offset, availH / panel.Size.Y.Offset))
end

-- Panel sizing for wide screens (harborheist-0ci3): panels are registered
-- with their base desktop size; on "wide" viewports they get a modest bump,
-- on "compact" a slight shrink. UIScale fit clamping (28.3) stays in charge
-- of small windows — this only adjusts the base size.
local LAYOUT_PANEL_SCALE = { compact = 0.95, standard = 1, wide = 1.08 }
local registeredPanels = {} -- { { panel = Frame, baseW = int, baseH = int }, ... }

local function registerLayoutPanel(panel, baseW, baseH)
	table.insert(registeredPanels, { panel = panel, baseW = baseW, baseH = baseH })
end

-- Apply the current layout mode's base size to one registered panel.
local function applyLayoutPanelSize(panel)
	for _, entry in ipairs(registeredPanels) do
		if entry.panel == panel then
			local factor = LAYOUT_PANEL_SCALE[currentLayoutMode] or 1
			entry.panel.Size = UDim2.new(0, math.floor(entry.baseW * factor + 0.5), 0, math.floor(entry.baseH * factor + 0.5))
			return
		end
	end
end

local function updatePanelSizing()
	for _, entry in ipairs(registeredPanels) do
		-- Skip the panel while it's on screen: resizing a visible panel
		-- mid pop-animation snaps the layout and conflicts with the 28.3
		-- UIScale fit tween. Hidden panels pick up the new base size; the
		-- open one is re-fit by the desktopPanelFitScale resize handler.
		if entry.panel and entry.panel.Parent and not entry.panel.Visible then
			applyLayoutPanelSize(entry.panel)
		end
	end
end

-- Layout-mode resize wiring: declared after updatePanelSizing exists
-- (layoutDesktopBar / layoutMobileStack are feature-branch locals that keep
-- their own resize handlers; only panel sizing is refreshed here).
local function bindViewportWidth(cam)
	if not cam then return end

	local viewportConn

	local function updateLayoutMode()
		-- harborheist-vr21: any viewport change can flip the orientation
		-- branch (or, on mobile, the top inset) — recompute SAFE_TOP and
		-- reposition its consumers even when the layout MODE is unchanged.
		task.spawn(refreshSafeTop)
		local newMode = getLayoutMode(cam.ViewportSize.X)
		if newMode ~= currentLayoutMode then
			currentLayoutMode = newMode
			task.spawn(updatePanelSizing)
		end
	end

	if viewportConn then viewportConn:Disconnect() end
	viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayoutMode)
end

bindViewportWidth(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindViewportWidth(workspace.CurrentCamera)
end)

local function makePanel(title, titleColor, desktopSize)
	local panel = Instance.new("Frame")
	panel.Name = title
	panel.BackgroundColor3 = Theme.color.surface.primary
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
	corner(panel, IS_MOBILE and Theme.corners.xl or Theme.corners.lg)
	stroke(panel, 0.82)
	Gradients.apply(panel, "surface.default")

	if IS_MOBILE then
		local grabber = Instance.new("Frame")
		grabber.Size = UDim2.new(0, 44, 0, 4)
		grabber.AnchorPoint = Vector2.new(0.5, 0)
		grabber.Position = UDim2.new(0.5, 0, 0, 8)
		grabber.BackgroundColor3 = Theme.color.text.tertiary
		grabber.BackgroundTransparency = 0.4
		grabber.ZIndex = 26
		grabber.Parent = panel
		corner(grabber, Theme.corners.hairline)

		-- R4 polish (mobile): drag-to-dismiss — THE bottom-sheet pattern.
		-- The grabber was decorative; now the header strip is a drag surface.
		-- Pull down >90px (or fling) to dismiss; release short of that and
		-- the sheet springs back. hidePanels is forward-declared above.
		local dragSurface = Instance.new("TextButton")
		dragSurface.Name = "DragDismiss"
		dragSurface.Size = UDim2.new(1, 0, 0, 60)
		dragSurface.Position = UDim2.new(0, 0, 0, 0)
		dragSurface.BackgroundTransparency = 1
		dragSurface.Text = ""
		dragSurface.AutoButtonColor = false
		dragSurface.ZIndex = 26
		dragSurface.Parent = panel

		local dragInput = nil
		local dragStartY = 0
		local dragDy = 0
		dragSurface.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch and activePanel == panel then
				dragInput = input
				dragStartY = input.Position.Y
				dragDy = 0
			end
		end)
		UserInputService.TouchMoved:Connect(function(input)
			if input == dragInput then
				dragDy = math.max(0, input.Position.Y - dragStartY)
				panel.Position = UDim2.new(0.5, 0, 1, dragDy)
				-- R4 polish #3b: the world lightens as the sheet descends —
				-- sells the dismiss before it commits.
				backdrop.BackgroundTransparency = math.clamp(0.45 + dragDy / 400, 0.45, 1)
			end
		end)
		UserInputService.TouchEnded:Connect(function(input)
			if input == dragInput then
				dragInput = nil
				if dragDy > 90 then
					hidePanels()
				else
					TweenService:Create(panel, EASE_OUT, { Position = UDim2.new(0.5, 0, 1, 0) }):Play()
					TweenService:Create(backdrop, EASE_OUT, { BackgroundTransparency = 0.45 }):Play()
				end
			end
		end)
	end

	local headerY = IS_MOBILE and 20 or 14
	makeLabel(panel, {
		Size = UDim2.new(1, -80, 0, 30),
		Position = UDim2.new(0, 18, 0, headerY),
		Text = title,
		Font = Theme.type.fonts.head,
		TextSize = IS_MOBILE and Theme.type.sizes.md or Theme.type.sizes.lg,
		TextColor3 = titleColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})

	local close = makeButton(panel, {
		-- R4 polish #11: 40px was under the 44pt mobile touch-target
		-- guideline for the primary sheet exit.
		Size = UDim2.new(0, IS_MOBILE and 44 or 32, 0, IS_MOBILE and 44 or 32),
		Position = UDim2.new(1, IS_MOBILE and -56 or -44, 0, headerY - (IS_MOBILE and 8 or 2)),
		Text = "✕",
		TextSize = IS_MOBILE and 18 or Theme.type.sizes.sm,
		BackgroundColor3 = Theme.color.surface.elevated,
		TextColor3 = Theme.color.text.secondary,
		ZIndex = 26,
		CornerRadius = Theme.corners.pill,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -32, 1, -(headerY + 44 + (IS_MOBILE and 12 or 4)))
	content.Position = UDim2.new(0, 16, 0, headerY + 40)
	content.ZIndex = 26
	content.Parent = panel

	-- harborheist-0ci3: register for layout-mode resizing (desktop only;
	-- mobile uses the bottom-sheet size set above).
	if not IS_MOBILE and desktopSize then
		registerLayoutPanel(panel, desktopSize.X.Offset, desktopSize.Y.Offset)
	end

	-- harborheist-n9x9: modal depth. The panel frame has no UIListLayout and
	-- no ClipsDescendants, so applyElevation's shadow layers (ZIndex 24 =
	-- panel 25 - 1) safely render behind the panel, above the backdrop (20),
	-- extending past the panel bounds. Duplicate-safe; shows/hides + animates
	-- with the panel (shadows are children).
	applyElevation(panel, "medium")

	return panel, content, close
end

-- Assigned to the forward-declared local (see above makePanel) so the
-- mobile drag-to-dismiss handlers can reference it.
hidePanels = function()
	if activePanel then
		-- TASK 25.1 (hvfh.5.1): disarm SELL ALL confirm on panel close.
		if disarmSellButton then
			disarmSellButton()
		end
		-- harborheist-vasr: an open row context menu is screenGui-level —
		-- destroy it when panels close so it can't float orphaned. (It is
		-- only ever spawned from the inventory panel; `inventoryPanel`
		-- itself is declared below hidePanels so it can't be compared here.)
		if activeContextMenu then
			activeContextMenu:destroy()
			activeContextMenu = nil
		end
		local panel = activePanel
		activePanel = nil
		if updateActionBarIndicator then
			updateActionBarIndicator()
		end
		if IS_MOBILE then
			-- harborheist-pytn: Use AnimationSystem slide transition for mobile hide
			Anim:slide(panel, "down", 0.16)
			task.delay(0.2, function()
				-- Fresh-eyes: same reopen race as showPanel's switch path —
				-- a close→reopen inside the slide would hide the live panel.
				if activePanel ~= panel then
					panel.Visible = false
				end
			end)
		else
			-- harborheist-pytn: Use AnimationSystem scale transition for desktop hide
			local scale = panel:FindFirstChildOfClass("UIScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Parent = panel
			end
			local fit = scale.Scale
			Anim:scale(panel, fit * 0.9, 0.16)
			task.delay(0.2, function()
				if activePanel ~= panel then
					panel.Visible = false
					scale.Scale = fit -- restore for the next open
				end
			end)
		end
	end
	-- harborheist-pytn: Use AnimationSystem fade for backdrop
	Anim:fade(backdrop, false, 0.22)
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
		-- R3 audit #5: switching panels on mobile hard-hid the old sheet
		-- (Visible=false) while the new one slid up — an abrupt pop in a UI
		-- that tweens everywhere else. Slide the old one down like hidePanels.
		local oldPanel = activePanel
		if IS_MOBILE then
			-- harborheist-pytn: Use AnimationSystem slide transition for mobile switch
			Anim:slide(oldPanel, "down", 0.16)
			task.delay(0.2, function()
				-- Guard against A→B→A fast switching: if the user reopened
				-- this panel before the slide-out finished, don't hide it.
				if activePanel ~= oldPanel then
					oldPanel.Visible = false
				end
			end)
		else
			-- Fresh-eyes fix (R4 #8 twin): the desktop SWITCH path still
			-- hard-hid the old panel — hidePanels got the animated close but
			-- this twin didn't. Same shrink, same reopen guard.
			local scale = oldPanel:FindFirstChildOfClass("UIScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Parent = oldPanel
			end
			local fit = scale.Scale
			-- harborheist-pytn: Use AnimationSystem scale transition for desktop switch
			Anim:scale(oldPanel, fit * 0.9, 0.16)
			task.delay(0.2, function()
				if activePanel ~= oldPanel then
					oldPanel.Visible = false
					scale.Scale = fit
				end
			end)
		end
	end
	activePanel = panel
	if updateActionBarIndicator then
		updateActionBarIndicator()
	end
	backdrop.Visible = true
	-- harborheist-pytn: Use AnimationSystem fade for backdrop
	Anim:fade(backdrop, true, 0.22)
	panel.Visible = true
	if IS_MOBILE then
		-- harborheist-pytn: Use AnimationSystem slide transition for mobile show
		panel.Position = UDim2.new(0.5, 0, 1.35, 0)
		Anim:slide(panel, "up", 0.28)
	else
		-- harborheist-pytn: Use AnimationSystem scale and fade transitions for desktop show
		-- harborheist-0ci3: re-apply the layout-mode base size first — the
		-- mode may have changed while this panel was open (then skipped by
		-- updatePanelSizing), and desktopPanelFitScale reads panel.Size.
		applyLayoutPanelSize(panel)
		local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = panel
		-- TASK 28.3: clamp oversized panels to the viewport — the pop
		-- animates toward the fit factor instead of 1.
		local fit = desktopPanelFitScale(panel)
		scale.Scale = 0.92 * fit
		panel.BackgroundTransparency = 0.3
		Anim:scale(panel, fit, 0.28)
		Anim:fade(panel, true, 0.22)
	end
end

backdrop.Activated:Connect(hidePanels)

-- TASK 28.3 (hvfh.8.3): re-clamp an OPEN desktop panel on window resize —
-- the fit computed in showPanel would otherwise go stale mid-session.
if not IS_MOBILE then
	local panelFitConn
	local function bindPanelFit(cam)
		if not cam then
			return
		end
		if panelFitConn then
			panelFitConn:Disconnect()
		end
		panelFitConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if activePanel then
				local scale = activePanel:FindFirstChildOfClass("UIScale")
				if scale then
					-- R3 audit #6: a direct assignment snapped the scale
					-- instantly mid-pop-animation — tween to the new fit.
					TweenService:Create(scale, EASE_FAST, { Scale = desktopPanelFitScale(activePanel) }):Play()
				end
			end
		end)
	end
	bindPanelFit(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindPanelFit(workspace.CurrentCamera)
	end)
end

-- ============================================================
-- Aquarium panel
-- ============================================================
local aquariumPanel, aquariumContent, aquariumClose = makePanel("MY AQUARIUM", Theme.color.brand.purple, UDim2.new(0, 360, 0, 464))

local aquariumStats = makeLabel(aquariumContent, {
	Size = UDim2.new(1, 0, 0, 66),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "",
	Font = Theme.type.fonts.med,
	TextSize = Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.secondary,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true,
	ZIndex = 26,
})

local capacityBar = Instance.new("Frame")
capacityBar.Size = UDim2.new(1, 0, 0, 10)
capacityBar.Position = UDim2.new(0, 0, 0, 68)
capacityBar.BackgroundColor3 = Theme.color.surface.elevated
capacityBar.ZIndex = 26
capacityBar.Parent = aquariumContent
corner(capacityBar, Theme.corners.compact)
stroke(capacityBar, 0.9)

local capacityFill = Instance.new("Frame")
capacityFill.Size = UDim2.new(0, 0, 1, 0)
capacityFill.BackgroundColor3 = Theme.color.brand.purple
capacityFill.ZIndex = 27
capacityFill.Parent = capacityBar
corner(capacityFill, Theme.corners.compact)
-- Captured for R4 #10: render() tweens the threshold color through BOTH
-- the fill and its gradient (a UIGradient multiplies the background — a
-- red fill under a purple gradient would read muddy).
local capacityGradient = Gradients.apply(capacityFill, "accent.capacity")

-- TASK 5.1: claim accumulated aquarium income
local claimButton = makeButton(aquariumPanel, {
	Size = UDim2.new(1, -16, 0, IS_MOBILE and 44 or 34),
	Position = UDim2.new(0, 8, 1, -122),
	Text = "CLAIM $0",
	BackgroundColor3 = Theme.color.status.neutral,
	-- thj.5: claimButton is a sibling of the content frame (ZIndex 26); ensure
	-- it renders/interacts on top so the larger mobile buttons above it don't
	-- steal input in the overlapping region.
	ZIndex = 27,
})

-- R4 polish: gentle CLAIM glow while income is ready and the panel is open.
-- The HUD income-line pulse (TASK 24.1) covers the closed-panel case; this
-- covers the in-panel "what do I press next" moment. Runs at 10Hz only
-- while ready > 0 and the aquarium panel is active; render()'s 1Hz color
-- set loses the fight visually (same pattern as the income line).
-- Defined here — NOT in the income-line loop — because claimButton and
-- aquariumPanel don't exist at that point in the file (lexical binding).
task.spawn(function()
	local GLOW_LO = Theme.color.status.claimReady
	local GLOW_HI = Theme.color.status.claimReadyHi
	while true do
		-- Fresh-eyes fix: the pulse must NOT mask the DataStore-unhealthy
		-- state — render() paints the button danger-red "SAVING UNAVAILABLE"
		-- then, and a green glow over it would lie about a dead feature.
		if state
			and (state.unclaimedIncome or 0) > 0
			and state.dataStoreHealthy ~= false
			and activePanel == aquariumPanel
		then
			local phase = (os.clock() % 2.0) / 2.0
			local alpha = 0.5 * (1 - math.abs(phase * 2 - 1))
			claimButton.BackgroundColor3 = GLOW_LO:Lerp(GLOW_HI, alpha)
			task.wait(0.1)
		else
			task.wait(0.5)
		end
	end
end)

makeLabel(aquariumContent, {
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.new(0, 0, 0, 88),
	Text = "LIVE-WELL BREAKDOWN",
	Font = Theme.type.fonts.bold,
	TextSize = Theme.type.sizes.xs,
	TextColor3 = Theme.color.text.tertiary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local rarityList = makeLabel(aquariumContent, {
	Size = UDim2.new(1, 0, 1, -214),
	Position = UDim2.new(0, 0, 0, 110),
	Text = "",
	Font = Theme.type.fonts.body,
	TextSize = Theme.type.sizes.sm,
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
	BackgroundColor3 = Theme.color.status.good,
	ZIndex = 26,
})

local lockButton = makeButton(aquariumContent, {
	Size = UDim2.new(0.5, -6, 0, buttonH),
	Position = UDim2.new(0.5, 6, 1, -buttonH - 4),
	Text = "LOCK",
	BackgroundColor3 = Theme.color.status.warn,
	ZIndex = 26,
})

-- TASK 8.2/8.3: Raid opt-in toggle (server validates new-player gate)
local raidOptInButton = makeButton(aquariumContent, {
	Size = UDim2.new(1, 0, 0, IS_MOBILE and 44 or 32),
	-- thj.5: keep a 4px gap above the SELL/LOCK buttons on mobile; the taller
	-- button would otherwise overlap because buttonH is also larger on mobile.
	Position = UDim2.new(0, 0, 1, -buttonH - (IS_MOBILE and 52 or 40)),
	Text = "RAID OPT-IN: OFF",
	BackgroundColor3 = Theme.color.surface.elevated,
	ZIndex = 26,
})

-- R3 audit #7: the aquarium content uses fixed pixel offsets (rarity list
-- reserves 214px below a 110px offset ≈ 324px of content). In short
-- landscape viewports the 0.78-scale sheet made the list NEGATIVE height
-- (blank) and the SELL/LOCK/opt-in stack overlapped the stats. Give the
-- sheet a pixel floor (capped at viewport-8 so it never overflows the top)
-- and re-fit on rotation.
local function fitAquariumPanelHeight()
	if not IS_MOBILE then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vy = cam.ViewportSize.Y
	local h = math.clamp(math.floor(vy * 0.78), math.min(400, vy - 8), vy - 8)
	aquariumPanel.Size = UDim2.new(1, -12, 0, h)
end
fitAquariumPanelHeight()
if IS_MOBILE then
	local function bindAquariumFit(cam)
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(fitAquariumPanelHeight)
		end
	end
	bindAquariumFit(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindAquariumFit)
end

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
local inventoryPanel, inventoryContent, inventoryClose = makePanel("FISH BAG", Theme.color.accent.base, UDim2.new(0, 420, 0, 500))

local inventoryStats = makeLabel(inventoryContent, {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "",
	Font = Theme.type.fonts.med,
	TextSize = Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.secondary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local inventoryList = Instance.new("ScrollingFrame")
inventoryList.Size = UDim2.new(1, 0, 1, -(IS_MOBILE and 82 or 76))
inventoryList.Position = UDim2.new(0, 0, 0, 24)
inventoryList.BackgroundTransparency = 1
inventoryList.ScrollBarThickness = 4
inventoryList.ScrollBarImageColor3 = Theme.color.text.tertiary
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

-- TASK 27.2 (hvfh.7.2): bag rows sorted by rarity (desc), then BaseSellValue
-- (desc), with original catch order as the stable tiebreak so rows don't
-- shuffle under the player. table.sort is NOT stable, so the original index
-- rides along explicitly as the final comparator key. Returns a COPY — the
-- bead constraint is explicit: do NOT sort session.carried server-side
-- (carry order may gain gameplay meaning later; the server contract is not
-- the problem). Sorting upstream in renderInventory keeps the rebuild-guard
-- signature consistent automatically.
-- R3 audit #9: forward-declared so renderInventory can gate STORE ALL on
-- bag-emptiness before the button instance is created below.
local invStoreAllBtn
local function sortCarriedForDisplay(carried)
	local wrapped = {}
	for i, fish in ipairs(carried) do
		wrapped[i] = { fish = fish, idx = i }
	end
	table.sort(wrapped, function(a, b)
		local ra = FishDefinitions.RARITY_ORDER[a.fish.Rarity] or 0
		local rb = FishDefinitions.RARITY_ORDER[b.fish.Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		local va = a.fish.BaseSellValue or 0
		local vb = b.fish.BaseSellValue or 0
		if va ~= vb then
			return va > vb
		end
		return a.idx < b.idx
	end)
	local sorted = {}
	for i, entry in ipairs(wrapped) do
		sorted[i] = entry.fish
	end
	return sorted
end

-- (SERVER_NOTIFIED_REASONS / FRIENDLY_FAILURE_REASONS / friendlyFailureReason
-- moved above the sellStore comparison prompt section — R3 audit #4.)

local function fishDisplayName(fish)
	if not fish then
		return "Fish"
	end
	local ok, def = pcall(FishDefinitions.get, fish.SpeciesId)
	return (ok and def and def.DisplayName) or fish.SpeciesId or "Fish"
end

-- harborheist-vasr: is this fish still in the carried bag right now?
-- Context-menu actions re-check before invoking the server so a stale row
-- (bag changed while the menu is open) doesn't fire a dead InstanceId.
local function fishStillCarried(instanceId)
	if not state or not state.carriedFish then
		return false
	end
	for _, fish in ipairs(state.carriedFish) do
		if fish and fish.InstanceId == instanceId then
			return true
		end
	end
	return false
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

-- harborheist-vasr: forward-declared — the implementation lives after
-- renderInventory (it closes over createInventoryContextMenu, defined below),
-- while renderInventory must call it during row construction.
local bindInventoryRowContextMenu

local function renderInventory()
	if not state then
		-- harborheist-9yli: skeleton loader on initial load before state snapshot arrives
		if not inventoryList:FindFirstChild("SkeletonRow_1") then
			createSkeletonRows(inventoryList, {
				rows = 4,
				rowHeight = IS_MOBILE and 66 or 58,
				zIndex = 26,
			})
		end
		return
	end
	local carried = sortCarriedForDisplay(state.carriedFish or {})
	local signatureParts = { tostring(state.maxCarried or 0) }
	for _, fish in ipairs(carried) do
		if fish then
			table.insert(signatureParts, tostring(fish.InstanceId))
		end
	end
	local signature = table.concat(signatureParts, "|")
	-- R3 audit #9: STORE ALL should be dead while the bag is empty, otherwise
	-- it fires a pointless round-trip and the server returns a confusing
	-- toast. Reflect carry state on the bulk button every render.
	local bagHasFish = #carried > 0
	invStoreAllBtn.Active = bagHasFish
	invStoreAllBtn.AutoButtonColor = bagHasFish
	invStoreAllBtn.TextColor3 = bagHasFish and Theme.color.text.ink or Theme.color.text.tertiary
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
		renderEmptyState(inventoryList, {
			icon = "🎣",
			title = "No fish yet",
			description = "Your hold is empty — catch fish to start earning coins.",
			action = "Cast your line to get started",
			order = 1,
			accent = Theme.color.brand.boat,
		})
		return
	end

	local actionH = IS_MOBILE and 44 or 38
	local rowH = IS_MOBILE and 66 or 58
	for i, fish in ipairs(carried) do
		if not fish then
			continue
		end
		local rarityColor = RARITY_COLORS[fish.Rarity] or Theme.color.text.secondary
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, rowH)
		row.BackgroundColor3 = Theme.color.surface.secondary
		row.BackgroundTransparency = 0.15
		row.LayoutOrder = i
		row.ZIndex = 26
		row.Parent = inventoryList
		corner(row, Theme.corners.roomy)
		stroke(row, 0.9)

		local tag = Instance.new("Frame")
		tag.Size = UDim2.new(0, 74, 0, 18)
		tag.Position = UDim2.new(0, 10, 0, 7)
		tag.BackgroundColor3 = rarityColor
		tag.BackgroundTransparency = 0.78
		tag.ZIndex = 27
		tag.Parent = row
		corner(tag, Theme.corners.compact)
		makeLabel(tag, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = string.upper(fish.Rarity or "?"),
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = rarityColor,
			ZIndex = 28,
		})

		makeLabel(row, {
			-- Width ends just before the SELL button (starts at 0.54) so long
			-- species names truncate cleanly instead of sliding under it.
			Size = UDim2.new(0.54, -100, 0, 20),
			Position = UDim2.new(0, 90, 0, 6),
			Text = fishDisplayName(fish),
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.sm,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 27,
		})

		makeLabel(row, {
			Size = UDim2.new(0.52, -20, 0, 18),
			Position = UDim2.new(0, 10, 0, rowH - 24),
			Text = string.format("$%s sell  •  $%.1f/min stored", formatCash(fish.BaseSellValue or 0), fish.IncomePerMinute or 0),
			Font = Theme.type.fonts.body,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.text.secondary,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 27,
		})

		local sellBtn = makeButton(row, {
			Size = UDim2.new(0.22, -4, 0, actionH),
			Position = UDim2.new(0.54, 0, 0.5, -actionH / 2),
			Text = "SELL",
			TextSize = Theme.type.sizes.sm,
			BackgroundColor3 = Theme.color.status.good,
			ZIndex = 27,
		})
		local storeBtn = makeButton(row, {
			Size = UDim2.new(0.24, 0, 0, actionH),
			Position = UDim2.new(0.76, 0, 0.5, -actionH / 2),
			Text = "STORE",
			TextSize = Theme.type.sizes.sm,
			BackgroundColor3 = Theme.color.accent.base,
			ZIndex = 27,
		})

		-- R3 audit #8: debounce the invoke so a double-tap during latency
		-- can't fire two InvokeServer calls (server rejects the loser, but
		-- the client showed a raw-reason toast for it). Disabling the button
		-- also gives clear "I registered your tap" feedback.
		-- Fresh-eyes fix: pcall the invoke — an error (network drop) would
		-- otherwise leave Active=false FOREVER (state didn't change → no
		-- re-render → dead button until the panel is reopened).
		local function debouncedAction(btn, verb, fn)
			btn.Activated:Connect(function()
				if not btn.Active then
					return
				end
				btn.Active = false
				local ok, result = pcall(fn)
				btn.Active = true
				if not ok or result == nil then
					showNotification(friendlyFailureReason(verb, "bad_id"), Theme.color.status.bad)
				end
			end)
		end

		debouncedAction(sellBtn, "sell", function()
			local result = Remotes.SellFish:InvokeServer(fish.InstanceId)
			if result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
				showNotification(friendlyFailureReason("sell", result.reason), Theme.color.status.bad)
			end
			return result
		end)
		debouncedAction(storeBtn, "store", function()
			local result = Remotes.StoreSingleFish:InvokeServer(fish.InstanceId)
			if result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
				showNotification(friendlyFailureReason("store", result.reason), Theme.color.status.bad)
			end
			return result
		end)
		-- R4 polish: staggered entrance on rebuild.
		staggerFadeIn(row, i)
		
		-- harborheist-vasr: right-click context menu on this row (desktop)
		bindInventoryRowContextMenu(row, fish)
	end
end

local invBulkH = IS_MOBILE and 46 or 40
invStoreAllBtn = makeButton(inventoryContent, {
	Size = UDim2.new(1, 0, 0, invBulkH),
	Position = UDim2.new(0, 0, 1, -invBulkH),
	Text = "STORE ALL",
	BackgroundColor3 = Theme.color.accent.base,
	ZIndex = 26,
})
invStoreAllBtn.Activated:Connect(function()
	if not invStoreAllBtn.Active then
		return
	end
	Remotes.RequestStoreFish:InvokeServer()
end)

-- ============================================================
-- ============================================================
-- Inventory Panel Context Menu (harborheist-vasr)
-- Right-click a bag row: sell / store / species details. Desktop-only
-- (touch users already have per-row SELL/STORE buttons).
-- ============================================================

-- activeContextMenu itself is forward-declared near hidePanels (top of file)
-- so hidePanels can destroy an open menu when panels close.

local function createInventoryContextMenu(fish, x, y)
	if activeContextMenu then
		activeContextMenu:destroy()
		activeContextMenu = nil
	end

	local items = {
		{
			id = "sell",
			text = "Sell for $" .. formatCash(fish.BaseSellValue or 0),
			action = function()
				-- Re-check the fish is still in the bag — a right-click on a
				-- stale row after STORE ALL would otherwise carry a dead
				-- InstanceId to the server (rejected, but a wasted round-trip).
				if not fishStillCarried(fish.InstanceId) then
					showNotification("Fish is no longer in your bag", Theme.color.status.warn)
					return
				end
				-- pcall-guarded: a network drop must not error the handler
				local ok, result = pcall(function()
					return Remotes.SellFish:InvokeServer(fish.InstanceId)
				end)
				if ok and result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
					showNotification(friendlyFailureReason("sell", result.reason), Theme.color.status.bad)
				end
			end,
		},
		{
			id = "store",
			text = "Store in aquarium",
			action = function()
				if not fishStillCarried(fish.InstanceId) then
					showNotification("Fish is no longer in your bag", Theme.color.status.warn)
					return
				end
				local ok, result = pcall(function()
					return Remotes.StoreSingleFish:InvokeServer(fish.InstanceId)
				end)
				if ok and result and not result.ok and result.reason and not SERVER_NOTIFIED_REASONS[result.reason] then
					showNotification(friendlyFailureReason("store", result.reason), Theme.color.status.bad)
				end
			end,
		},
		{
			id = "details",
			text = "Species details",
			action = function()
				local ok, def = pcall(FishDefinitions.get, fish.SpeciesId)
				if ok and def then
					showNotification(
						string.format("%s — %s\n$%s sell  •  $%.1f/min stored",
							def.DisplayName or fish.SpeciesId,
							fish.Rarity or "?",
							formatCash(fish.BaseSellValue or 0),
							fish.IncomePerMinute or 0),
						Theme.color.status.info)
				else
					showNotification("Unknown species", Theme.color.status.bad)
				end
			end,
		},
	}

	activeContextMenu = ContextMenu.new(items)
	activeContextMenu:show(x, y)
end

-- Bound per-row inside renderInventory (the fish reference rides the
-- closure — no fake Instance properties, no list-level hit-testing).
bindInventoryRowContextMenu = function(row, fish)
	if IS_MOBILE then
		return
	end
	-- Plain Frames only receive InputBegan when Active; this also sinks
	-- row clicks so they don't fall through to the 3D world behind the panel.
	row.Active = true
	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			createInventoryContextMenu(fish, input.Position.X, input.Position.Y)
		end
	end)
end

local function toggleInventoryPanel()
	if overlayBlocksPanels() then
		return
	end
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
local collectionPanel, collectionContent, collectionClose = makePanel("COLLECTION", Theme.color.status.warn, UDim2.new(0, 520, 0, 560))

local collectionProgress = makeLabel(collectionContent, {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "",
	Font = Theme.type.fonts.med,
	TextSize = Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.secondary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local collectionProgressBar = Instance.new("Frame")
collectionProgressBar.Name = "ProgressBar"
collectionProgressBar.Size = UDim2.new(1, 0, 0, 10)
collectionProgressBar.Position = UDim2.new(0, 0, 0, 24)
collectionProgressBar.BackgroundColor3 = Theme.color.surface.elevated
collectionProgressBar.ZIndex = 26
collectionProgressBar.Parent = collectionContent
corner(collectionProgressBar, Theme.corners.compact)
stroke(collectionProgressBar, 0.9)

local collectionProgressFill = Instance.new("Frame")
collectionProgressFill.Name = "ProgressFill"
collectionProgressFill.Size = UDim2.new(0, 0, 1, 0)
collectionProgressFill.BackgroundColor3 = Theme.color.status.warn
collectionProgressFill.ZIndex = 27
collectionProgressFill.Parent = collectionProgressBar
corner(collectionProgressFill, Theme.corners.compact)
Gradients.apply(collectionProgressFill, "status.warning")

local collectionList = Instance.new("ScrollingFrame")
collectionList.Name = "CollectionList"
-- Fill the rest of the content below the progress bar (y=44) with a small
-- bottom margin. Unlike the inventory panel, there is no bottom button.
collectionList.Size = UDim2.new(1, 0, 1, -56)
collectionList.Position = UDim2.new(0, 0, 0, 44)
collectionList.BackgroundTransparency = 1
collectionList.ScrollBarThickness = 4
collectionList.ScrollBarImageColor3 = Theme.color.text.tertiary
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

-- TASK 27.1 (hvfh.7.1): Procedural fish silhouette for collection cards.
-- Replaces placeholder "F" / "?" text with a recognizable fish shape
-- composed of UI primitives (ellipse body + rotated tail + eye).
-- Tinted by rarity for discovered species; greyed out for undiscovered.
local function buildFishSilhouette(parent, color)
	-- Body (Ellipse)
	local body = Instance.new("Frame")
	body.Name = "FishBody"
	body.Size = UDim2.new(0.6, 0, 0.4, 0)
	body.Position = UDim2.new(0.2, 0, 0.3, 0)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.Parent = parent
	local bodyCorner = Instance.new("UICorner")
	bodyCorner.CornerRadius = UDim.new(0.5, 0)
	bodyCorner.Parent = body

	-- Tail (Rotated Frame)
	local tail = Instance.new("Frame")
	tail.Name = "FishTail"
	tail.Size = UDim2.new(0.25, 0, 0.3, 0)
	tail.AnchorPoint = Vector2.new(0, 0.5)
	tail.Position = UDim2.new(0.7, 0, 0.5, 0)
	tail.Rotation = 45
	tail.BackgroundColor3 = color
	tail.BorderSizePixel = 0
	tail.Parent = parent
	local tailCorner = Instance.new("UICorner")
	tailCorner.CornerRadius = UDim.new(0, Theme.corners.hairline)
	tailCorner.Parent = tail

	-- Eye (White dot for life)
	local eye = Instance.new("Frame")
	eye.Name = "FishEye"
	eye.Size = UDim2.new(0, 4, 0, 4)
	eye.Position = UDim2.new(0.3, 0, 0.4, 0)
	eye.BackgroundColor3 = Color3.new(1, 1, 1)
	eye.BorderSizePixel = 0
	eye.Parent = parent
	local eyeCorner = Instance.new("UICorner")
	eyeCorner.CornerRadius = UDim.new(0.5, 0)
	eyeCorner.Parent = eye
end

local function makeCollectionCard(parent, order, data, discovered)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, IS_MOBILE and 138 or 146, 0, IS_MOBILE and 130 or 126)
	card.BackgroundColor3 = discovered and Theme.color.surface.secondary or Theme.color.surface.undiscovered
	card.BackgroundTransparency = 0.1
	card.LayoutOrder = order
	card.ZIndex = 26
	card.Parent = parent
	corner(card, Theme.corners.md)
	stroke(card, 0.9)

	local rarityColor = RARITY_COLORS[data.rarity] or Theme.color.text.secondary
	if discovered then
		local topBar = Instance.new("Frame")
		topBar.Size = UDim2.new(1, 0, 0, 6)
		topBar.BackgroundColor3 = rarityColor
		topBar.ZIndex = 27
		topBar.Parent = card
		corner(topBar, Theme.corners.snug)

		local icon = Instance.new("Frame")
		icon.Size = UDim2.new(0, 48, 0, 48)
		icon.Position = UDim2.new(0.5, -24, 0, 18)
		icon.BackgroundColor3 = Theme.color.surface.elevated
		icon.ZIndex = 27
		icon.Parent = card
		corner(icon, Theme.corners.pill)
		-- TASK 27.1: Replace "F" text with procedural fish silhouette
		buildFishSilhouette(icon, rarityColor)

		makeLabel(card, { Size = UDim2.new(1, -12, 0, 20), Position = UDim2.new(0, 6, 0, 68), Text = data.displayName, Font = Theme.type.fonts.bold, TextSize = Theme.type.sizes.sm, TextColor3 = Theme.color.text.primary, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 27 })
		makeLabel(card, { Size = UDim2.new(1, -12, 0, 16), Position = UDim2.new(0, 6, 0, 106), Text = string.format("$%d  •  $%.1f/min", data.baseSellValue or 0, data.incomePerMinute or 0), Font = Theme.type.fonts.body, TextSize = Theme.type.sizes.xs, TextColor3 = Theme.color.text.secondary, ZIndex = 27 })

		local tag = Instance.new("Frame")
		tag.Size = UDim2.new(0, 74, 0, 18)
		tag.Position = UDim2.new(0, 6, 0, 88)
		tag.BackgroundColor3 = rarityColor
		tag.BackgroundTransparency = 0.78
		tag.ZIndex = 27
		tag.Parent = card
		corner(tag, Theme.corners.compact)
		makeLabel(tag, { Size = UDim2.new(1, 0, 1, 0), Text = string.upper(data.rarity or "?"), Font = Theme.type.fonts.bold, TextSize = Theme.type.sizes.xs, TextColor3 = rarityColor, ZIndex = 28 })
	else
		local icon = Instance.new("Frame")
		icon.Size = UDim2.new(0, 48, 0, 48)
		icon.Position = UDim2.new(0.5, -24, 0, 26)
		icon.BackgroundColor3 = Theme.color.surface.elevated
		icon.BackgroundTransparency = 0.6
		icon.ZIndex = 27
		icon.Parent = card
		corner(icon, Theme.corners.pill)
		-- TASK 27.1: Replace "?" text with greyed fish silhouette (no species-identifying info)
		buildFishSilhouette(icon, Theme.color.text.tertiary)

		makeLabel(card, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 0, 78), Text = "???", Font = Theme.type.fonts.bold, TextSize = Theme.type.sizes.sm, TextColor3 = Theme.color.text.tertiary, ZIndex = 27 })
		makeLabel(card, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 0, 98), Text = string.upper(data.rarity or "Unknown") .. " FISH", Font = Theme.type.fonts.body, TextSize = Theme.type.sizes.xs, TextColor3 = rarityColor, ZIndex = 27 })
	end
	return card
end

-- harborheist-y3rz: forward declaration — the milestone claim handler below
-- calls renderCollection() (~20 lines before its definition). Without this,
-- the handler binds a nil GLOBAL and crashes after the reward is granted.
local renderCollection

local function makeMilestoneRow(parent, order, milestone)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = Theme.color.surface.secondary
	row.BackgroundTransparency = 0.1
	row.LayoutOrder = order
	row.ZIndex = 26
	row.Parent = parent
	corner(row, Theme.corners.roomy)
	stroke(row, 0.9)

	makeLabel(row, {
		Size = UDim2.new(1, -100, 0, 20),
		Position = UDim2.new(0, 10, 0, 6),
		Text = milestone.label,
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.sm,
		TextColor3 = Theme.color.text.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})

	makeLabel(row, {
		Size = UDim2.new(1, -100, 0, 16),
		Position = UDim2.new(0, 10, 0, 26),
		Text = string.format("%d / %d", milestone.have or 0, milestone.need or 0),
		Font = Theme.type.fonts.body,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.text.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 27,
	})

	if milestone.claimed then
		makeLabel(row, {
			Size = UDim2.new(0, 80, 0, 28),
			Position = UDim2.new(1, -90, 0.5, -14),
			Text = "CLAIMED",
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.status.good,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
	elseif milestone.complete then
		local claimBtn = makeButton(row, {
			Size = UDim2.new(0, IS_MOBILE and 96 or 80, 0, IS_MOBILE and 44 or 32),
			Position = UDim2.new(1, IS_MOBILE and -106 or -90, 0.5, IS_MOBILE and -22 or -16),
			Text = "CLAIM",
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			BackgroundColor3 = Theme.color.status.warn,
			ZIndex = 27,
		})
		claimBtn.Activated:Connect(function()
			local result = Remotes.ClaimCollectionReward:InvokeServer(milestone.id)
			if result and result.ok then
				milestone.claimed = true
				hapticTick() -- R4 polish #2: reward moment
				-- Invalidate the rebuild signature to force a re-render (the
				-- signature now also covers claimed state — R3 #15 — but nil-ing
				-- keeps this correct even if the shape changes again).
				-- Server fires its own notification via remotes.notify, so no
				-- duplicate client-side showNotification here.
				lastCollectionSignature = nil
				renderCollection()
			elseif result and result.reason then
				showNotification("Could not claim: " .. tostring(result.reason), Theme.color.status.bad)
			end
		end)
	else
		makeLabel(row, {
			Size = UDim2.new(0, 80, 0, 28),
			Position = UDim2.new(1, -90, 0.5, -14),
			Text = "LOCKED",
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.text.tertiary,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
	end

	return row
end

-- Assigned to the forward-declared local (harborheist-y3rz) — see above.
renderCollection = function()
	if not collectionBookData then
		return
	end
	local book = collectionBookData
	-- R3 audit #15: signature was discovered/total only — a milestone
	-- becoming claimable (have/need crossing) never re-rendered the panel
	-- until an unrelated species discovery changed the count. Fold milestone
	-- progress + complete/claimed state into the signature. (Fresh-eyes:
	-- field names verified against makeMilestoneRow — have/need/complete/
	-- claimed; an earlier draft read a nonexistent .current fallback.)
	local sigParts = { tostring(book.discoveredCount or 0), tostring(book.totalSpecies or 0) }
	if book.milestones then
		for _, milestone in ipairs(book.milestones) do
			table.insert(sigParts, tostring(milestone.id))
			table.insert(sigParts, tostring(milestone.have or 0))
			table.insert(sigParts, milestone.complete and "1" or "0")
			table.insert(sigParts, milestone.claimed and "1" or "0")
		end
	end
	local signature = table.concat(sigParts, "/")
	if signature == lastCollectionSignature then
		return
	end
	lastCollectionSignature = signature
	clearCollectionList()

	collectionProgress.Text = string.format("%d / %d species discovered", book.discoveredCount or 0, book.totalSpecies or 0)
	local progress = (book.totalSpecies or 0) > 0 and (book.discoveredCount or 0) / (book.totalSpecies or 0) or 0
	collectionProgressFill.Size = UDim2.new(math.clamp(progress, 0, 1), 0, 1, 0)

	if not book.ordered or #book.ordered == 0 then
		renderEmptyState(collectionList, {
			icon = "📖",
			title = "No discoveries yet",
			description = "You haven't catalogued any species. Each new catch adds to your collection.",
			action = "Catch a fish to begin your catalogue",
			order = 1,
			accent = Theme.color.brand.purple,
		})
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
				makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 20), Text = string.upper(currentRarity or "Unknown"), Font = Theme.type.fonts.bold, TextSize = Theme.type.sizes.xs, TextColor3 = RARITY_COLORS[currentRarity] or Theme.color.text.secondary, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 26 })
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
			local card = makeCollectionCard(rarityGrid, i, data, book.discovered[speciesId] ~= nil)
			-- R4 polish: staggered entrance (delay caps at index 8 so large
			-- collections still appear promptly).
			if card then
				staggerFadeIn(card, i)
			end
		end
	end

	-- Milestones section
	order += 1
	makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 20), Text = "MILESTONES", Font = Theme.type.fonts.bold, TextSize = Theme.type.sizes.xs, TextColor3 = Theme.color.status.warn, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 26 })
	order += 1

	if book.milestones and #book.milestones > 0 then
		for _, milestone in ipairs(book.milestones) do
			makeMilestoneRow(collectionList, order, milestone)
			order += 1
		end
	else
		makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 44), Text = "No milestones available.", Font = Theme.type.fonts.body, TextSize = Theme.type.sizes.sm, TextColor3 = Theme.color.text.tertiary, LayoutOrder = order, ZIndex = 26 })
	end
end

-- R4 polish / harborheist-7h69.1: skeleton rows for the collection cold-
-- load. Delegates to the universal createSkeletonRows factory — three
-- ghost cards with a cascading transparency wave read as "premium loading"
-- where a bare "Loading..." label reads as "broken". The animation loop
-- self-terminates when clearCollectionList destroys the bars (refresh or
-- error path). The factory detects collectionList's existing UIListLayout
-- (Padding=14) and preserves it.
local function showCollectionSkeleton()
	clearCollectionList()
	createSkeletonRows(collectionList, {
		rows = 3,
		rowHeight = IS_MOBILE and 110 or 120,
		zIndex = 26,
	})
end

local function toggleCollectionPanel()
	if overlayBlocksPanels() then
		return
	end
	if activePanel == collectionPanel then
		hidePanels()
		return
	end
	showPanel(collectionPanel)
	-- R3 audit #14: un-pcall'd invoke + no loading state — a network error
	-- killed the handler thread and left a permanently blank panel, and slow
	-- networks showed emptiness with no spinner.
	-- Fresh-eyes fix: show cached data IMMEDIATELY when we have it (nil the
	-- signature to force a rebuild) and only show the loading row on a cold
	-- open — otherwise a rate_limited refresh left the loading row up
	-- forever (renderCollection early-returns on the unchanged signature).
	if collectionBookData then
		lastCollectionSignature = nil
		renderCollection()
	else
		showCollectionSkeleton()
	end
	local ok, book = pcall(function()
		return Remotes.RequestCollection:InvokeServer()
	end)
	if not ok then
		if collectionBookData then
			-- Keep showing the cached book; just say the refresh failed.
			showNotification("Couldn't refresh the collection — showing saved data.", Theme.color.status.bad)
		else
			clearCollectionList()
			makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 44), Text = "Couldn't load the collection — tap again to retry.", Font = Theme.type.fonts.body, TextSize = Theme.type.sizes.sm, TextColor3 = Theme.color.status.bad, LayoutOrder = 1, ZIndex = 26 })
		end
		return
	end
	if book and book.ok then
		collectionBookData = book
		lastCollectionSignature = nil -- fresh fetch: force rebuild
		renderCollection()
	elseif book and book.reason == "rate_limited" then
		if collectionBookData then
			-- Cached book already rendered above — nothing to fix up.
			showNotification("Collection book loading too fast — try again.", Theme.color.status.warn)
		else
			clearCollectionList()
			makeLabel(collectionList, { Size = UDim2.new(1, 0, 0, 44), Text = "Still loading — tap again in a moment.", Font = Theme.type.fonts.body, TextSize = Theme.type.sizes.sm, TextColor3 = Theme.color.text.tertiary, LayoutOrder = 1, ZIndex = 26 })
			showNotification("Collection book loading too fast — try again.", Theme.color.status.warn)
		end
	else
		-- Unknown failure: keep the cached book if we rendered one above;
		-- only blank the panel when there is nothing to show.
		if not collectionBookData then
			clearCollectionList()
		end
		showNotification("Collection book unavailable: " .. tostring(book and book.reason or "unknown"), Theme.color.status.bad)
	end
end

-- ============================================================
-- Shop panel
-- ============================================================
local shopPanel, shopContent, shopClose = makePanel("BAIT & TACKLE", Theme.color.status.warn, UDim2.new(0, 420, 0, 520))

local shopList = Instance.new("ScrollingFrame")
shopList.Size = UDim2.new(1, 0, 1, 0)
shopList.BackgroundTransparency = 1
shopList.ScrollBarThickness = 4
shopList.ScrollBarImageColor3 = Theme.color.text.tertiary
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
		table.insert(SHOP_CATALOG, { kind = kind, level = level, item = item, order = orderBase * 10 + level })
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

local function buildSectionHeader(title, order)
	makeLabel(shopList, {
		Size = UDim2.new(1, -6, 0, 20),
		Text = title,
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.text.tertiary,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		ZIndex = 26,
	})
end

local KIND_META = {
	rod = { tag = "ROD", color = Theme.color.accent.base },
	bait = { tag = "BAIT", color = Theme.color.status.good },
	aquarium = { tag = "TANK", color = Theme.color.brand.purple },
	lock = { tag = "LOCK", color = Theme.color.status.warn },
	alarm = { tag = "ALARM", color = Theme.color.status.bad },
	dock = { tag = "DOCK", color = Theme.color.brand.boat },
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
	row.BackgroundColor3 = Theme.color.surface.secondary
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = entry.order
	row.ZIndex = 26
	row.Parent = shopList
	corner(row, Theme.corners.roomy)
	stroke(row, 0.9)

	local meta = KIND_META[entry.kind]
	local tag = Instance.new("Frame")
	tag.Size = UDim2.new(0, 46, 0, 18)
	tag.Position = UDim2.new(0, 10, 0, 8)
	tag.BackgroundColor3 = meta.color
	tag.BackgroundTransparency = 0.75
	tag.ZIndex = 27
	tag.Parent = row
	corner(tag, Theme.corners.compact)
	makeLabel(tag, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = meta.tag,
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = meta.color,
		ZIndex = 28,
	})

	makeLabel(row, {
		Size = UDim2.new(0.62, -70, 0, 20),
		Position = UDim2.new(0, 62, 0, 7),
		Text = itemDisplayName(entry),
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.sm,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})

	makeLabel(row, {
		Size = UDim2.new(0.64, -20, 0, 30),
		Position = UDim2.new(0, 10, 0, 30),
		Text = itemSubText(entry),
		Font = Theme.type.fonts.body,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.text.secondary,
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
		-- harborheist-cl05: unaffordable next tier — explain the shortfall
		-- locally instead of firing an invoke that earns the server's
		-- generic 'Not enough cash!' error toast.
		if entry.affordable == false then
			local shortfall = math.max(0, (entry.item.cost or 0) - ((state and state.cash) or 0))
			showNotification(
				string.format("Need $%s more for %s", formatCash(shortfall), entry.item.name or "that upgrade"),
				Theme.color.status.warn
			)
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
		-- harborheist-9yli: skeleton loader on initial load before state snapshot arrives
		if not shopList:FindFirstChild("SkeletonRow_1") then
			createSkeletonRows(shopList, {
				rows = 4,
				rowHeight = IS_MOBILE and 74 or 66,
				zIndex = 26,
			})
		end
		return
	end
	-- harborheist-9yli: clear skeletons when state arrives
	if shopList:FindFirstChild("SkeletonRow_1") then
		for _, child in ipairs(shopList:GetChildren()) do
			if child.Name:find("SkeletonRow") or child.Name == "LoadingSpinner" then
				child:Destroy()
			end
		end
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
			entry.buyButton.BackgroundColor3 = Theme.color.surface.elevated
			entry.buyButton.TextColor3 = Theme.color.text.tertiary
			entry.buyButton.Active = false
		elseif entry.level == currentLevel + 1 then
			local affordable = state.cash >= (entry.item.cost or 0)
			entry.affordable = affordable -- harborheist-cl05: read by the buy handler
			entry.buyButton.Text = "$" .. formatCash(entry.item.cost)
			-- harborheist-cl05: unaffordable-but-tappable must not read as
			-- DISABLED — surfaceHi+textDim was pixel-identical to OWNED, so
			-- players tapped a 'dead' button and earned a generic error.
			-- Distinct surface + amber price = 'not yet'; the tap explains
			-- the shortfall (see buyButton.Activated).
			entry.buyButton.BackgroundColor3 = affordable and Theme.color.status.good or Theme.color.surface.secondary
			entry.buyButton.TextColor3 = affordable and Theme.color.text.ink or Theme.color.status.warn
			entry.buyButton.Active = true
		else
			entry.buyButton.Text = "LOCKED"
			entry.buyButton.BackgroundColor3 = Theme.color.surface.secondary
			entry.buyButton.TextColor3 = Theme.color.text.tertiary
			entry.buyButton.Active = false
		end
	end
end

buildSectionHeader("RODS", -1)
buildSectionHeader("BAIT", 99)
buildSectionHeader("TANK", 199)
buildSectionHeader("DEFENSE", 299)
buildSectionHeader("DOCK", 499)
for _, entry in ipairs(SHOP_CATALOG) do
	buildShopRow(entry)
end

-- ============================================================
-- Quest panel
-- ============================================================
local questPanel, questContent, questClose = makePanel("QUESTS", Theme.color.brand.quest, UDim2.new(0, 420, 0, 500))

local questList = Instance.new("ScrollingFrame")
questList.Size = UDim2.new(1, 0, 1, 0)
questList.BackgroundTransparency = 1
questList.ScrollBarThickness = 4
questList.ScrollBarImageColor3 = Theme.color.text.tertiary
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
	row.BackgroundColor3 = Theme.color.surface.secondary
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = order
	row.ZIndex = 26
	row.Parent = parent
	corner(row, Theme.corners.roomy)
	stroke(row, 0.9)

	makeLabel(row, {
		Size = UDim2.new(1, -110, 0, 20),
		Position = UDim2.new(0, 12, 0, 8),
		Text = quest.desc or "Quest",
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.sm,
		TextColor3 = quest.claimed and Theme.color.status.good or Theme.color.text.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})

	local target = math.max(1, quest.target or 1)
	local progressVal = math.min(quest.progress or 0, target)

	local progressBar = Instance.new("Frame")
	progressBar.Size = UDim2.new(1, -120, 0, 8)
	progressBar.Position = UDim2.new(0, 12, 1, -20)
	progressBar.BackgroundColor3 = Theme.color.surface.elevated
	progressBar.ZIndex = 27
	progressBar.Parent = row
	corner(progressBar, Theme.corners.slim)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(progressVal / target, 0, 1, 0)
	fill.BackgroundColor3 = quest.claimed and Theme.color.status.good or Theme.color.brand.quest
	fill.ZIndex = 28
	fill.Parent = progressBar
	corner(fill, Theme.corners.slim)

	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0, 92, 0, 24)
	chip.Position = UDim2.new(1, -102, 0.5, -12)
	chip.BackgroundColor3 = quest.claimed and Theme.color.status.good or Theme.color.surface.elevated
	chip.BackgroundTransparency = quest.claimed and 0.75 or 0.3
	chip.ZIndex = 27
	chip.Parent = row
	corner(chip, Theme.corners.pill)

	makeLabel(chip, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = quest.claimed and "CLAIMED" or string.format("%d/%d • $%s", progressVal, target, formatCash(quest.reward or 0)),
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = quest.claimed and Theme.color.status.good or Theme.color.accent.soft,
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
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.status.warn,
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})
	for i, q in ipairs(data and data.dailyQuests or {}) do
		makeQuestRow(questList, q, 10 + i)
	end
	-- harborheist-7h69.6: empty-state message when no daily quests.
	if not data or not data.dailyQuests or #data.dailyQuests == 0 then
		renderEmptyState(questList, {
			icon = "📜",
			title = "No daily quests",
			description = "New daily quests refresh at midnight.",
			action = "Check back tomorrow for fresh challenges",
			order = 2,
			accent = Theme.color.brand.quest,
		})
	end

	makeLabel(questList, {
		Size = UDim2.new(1, 0, 0, 24),
		Text = "WEEKLY",
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.accent.base,
		LayoutOrder = 100,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 26,
	})
	for i, q in ipairs(data and data.weeklyQuests or {}) do
		makeQuestRow(questList, q, 110 + i)
	end
	-- harborheist-7h69.6: empty-state message when no weekly quests.
	if not data or not data.weeklyQuests or #data.weeklyQuests == 0 then
		renderEmptyState(questList, {
			icon = "📜",
			title = "No weekly quests",
			description = "Weekly challenges are on a rotation.",
			action = "Check back soon for new challenges",
			order = 101,
			accent = Theme.color.brand.quest,
		})
	end
end

-- ============================================================
-- Raid panel (TASK 8.12 / gdj.12)
-- Global window countdown, opt-in toggle, target selection, raid attempt.
-- ============================================================
local raidPanel, raidContent, raidClose = makePanel("RAID WATERS", Theme.color.status.bad, UDim2.new(0, 440, 0, 520))

local raidStatusLabel = makeLabel(raidContent, {
	Size = UDim2.new(1, 0, 0, 48),
	Position = UDim2.new(0, 0, 0, 0),
	Text = "Raid waters are calm",
	Font = Theme.type.fonts.head,
	TextSize = IS_MOBILE and Theme.type.sizes.md or Theme.type.sizes.lg,
	TextColor3 = Theme.color.text.primary,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	ZIndex = 26,
})

local raidCountdownLabel = makeLabel(raidContent, {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, 50),
	Text = "Next window: --",
	Font = Theme.type.fonts.med,
	TextSize = Theme.type.sizes.sm,
	TextColor3 = Theme.color.text.secondary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local raidOptInPanelButton = makeButton(raidContent, {
	Size = UDim2.new(1, 0, 0, IS_MOBILE and 44 or 36),
	-- thj.5: keep the bottom edge at 114 so the label at y=116 keeps its 2px gap.
	Position = UDim2.new(0, 0, 0, IS_MOBILE and 70 or 78),
	Text = "RAID OPT-IN: OFF",
	BackgroundColor3 = Theme.color.surface.elevated,
	ZIndex = 26,
})

makeLabel(raidContent, {
	Size = UDim2.new(1, -100, 0, 16),
	Position = UDim2.new(0, 0, 0, 116),
	Text = "TARGETS",
	Font = Theme.type.fonts.bold,
	TextSize = Theme.type.sizes.xs,
	TextColor3 = Theme.color.text.tertiary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local raidTargetList = Instance.new("ScrollingFrame")
raidTargetList.Size = UDim2.new(1, 0, 1, -146)
raidTargetList.Position = UDim2.new(0, 0, 0, 144)
raidTargetList.BackgroundTransparency = 1
raidTargetList.ScrollBarThickness = 4
raidTargetList.ScrollBarImageColor3 = Theme.color.text.tertiary
raidTargetList.CanvasSize = UDim2.new(0, 0, 0, 0)
raidTargetList.AutomaticCanvasSize = Enum.AutomaticSize.Y
raidTargetList.ZIndex = 26
raidTargetList.Parent = raidContent

local raidTargetLayout = Instance.new("UIListLayout")
raidTargetLayout.Padding = UDim.new(0, 8)
raidTargetLayout.SortOrder = Enum.SortOrder.LayoutOrder
raidTargetLayout.Parent = raidTargetList

local raidRefreshButton = makeButton(raidContent, {
	-- harborheist-bpem.1: 36px was below the 44pt mobile touch-target
	-- minimum. Grown upward (Y 104->96) so the bottom edge stays at 140,
	-- preserving the 4px gap to the target list (top 144). Trade-off: the
	-- Y-overlap with the full-width raidOptInPanelButton (bottom edge 114)
	-- increases from 10px to 18px; the optIn button text is vertically
	-- centered (Y~92), above the overlap region (Y>=96), so no text is
	-- hidden — the refresh button's opaque bg just covers more of the
	-- optIn button's empty bottom-right corner.
	Size = UDim2.new(0, IS_MOBILE and 100 or 90, 0, IS_MOBILE and 44 or 28),
	Position = UDim2.new(1, IS_MOBILE and -104 or -94, 0, IS_MOBILE and 96 or 112),
	Text = "REFRESH",
	BackgroundColor3 = Theme.color.surface.elevated,
	TextColor3 = Theme.color.text.primary,
	TextSize = Theme.type.sizes.xs,
	ZIndex = 26,
})

local raidTargets = {}
local raidTargetsLoaded = false
local raidInProgress = false


-- Table to track countdown labels for unavailable targets (hvfh.6.1.2)
local raidTargetCountdownLabels = {}

local function renderRaidTargets(data)
	for _, child in ipairs(raidTargetList:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	raidTargetCountdownLabels = {}
	
	if not data or not data.ok then
		makeLabel(raidTargetList, {
			Size = UDim2.new(1, 0, 0, 48),
			Text = data and data.reason or "Could not load targets.",
			Font = Theme.type.fonts.med,
			TextSize = Theme.type.sizes.sm,
			TextColor3 = Theme.color.text.secondary,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
		return
	end
	if not data.canRaid then
		-- P0 syntax fix (fresh-eyes review): Luau cannot index a bare table
		-- constructor — ({...})[key] parses, {...}[key] does not (verified
		-- against lune, luau-analyze, and selene). The unparsable script
		-- would kill the ENTIRE client UI on load.
		local reasonText = ({
			window_closed = "No raid window is open right now.",
			not_opted_in = "You must opt in to raids to see targets.",
			new_player_protected = "New players are protected from raids until 10 catches or an upgrade.",
			stunned = "You are stunned and cannot raid.",
			attacker_cooldown = "Raid cooldown active — try again soon.",
		})[data.reason] or ("Cannot raid: " .. tostring(data.reason))
		makeLabel(raidTargetList, {
			Size = UDim2.new(1, 0, 0, 48),
			Text = reasonText,
			Font = Theme.type.fonts.med,
			TextSize = Theme.type.sizes.sm,
			TextColor3 = Theme.color.text.secondary,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
		return
	end
	if not data.targets or #data.targets == 0 then
		makeLabel(raidTargetList, {
			Size = UDim2.new(1, 0, 0, 48),
			Text = "No opted-in targets available. Other players must opt in to raids to appear here.",
			Font = Theme.type.fonts.med,
			TextSize = Theme.type.sizes.sm,
			TextColor3 = Theme.color.text.secondary,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 27,
		})
		return
	end
	
	-- Sort targets: available first, then unavailable (hvfh.6.1.2)
	local sortedTargets = {}
	for _, target in ipairs(data.targets) do
		table.insert(sortedTargets, target)
	end
	table.sort(sortedTargets, function(a, b)
		if a.available == b.available then
			return (a.displayName or a.name or "") < (b.displayName or b.name or "")
		end
		return a.available == true
	end)
	
	for i, target in ipairs(sortedTargets) do
		local isAvailable = target.available ~= false
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, IS_MOBILE and 68 or 60)
		row.BackgroundColor3 = isAvailable and Theme.color.surface.secondary or Theme.color.surface.elevated
		row.BackgroundTransparency = isAvailable and 0.15 or 0.3
		row.LayoutOrder = i
		row.ZIndex = 26
		row.Parent = raidTargetList
		corner(row, Theme.corners.roomy)
		stroke(row, isAvailable and 0.9 or 0.95)

		makeLabel(row, {
			Size = UDim2.new(1, -110, 0, 20),
			Position = UDim2.new(0, 12, 0, 8),
			Text = target.displayName or target.name or "Unknown",
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.sm,
			TextColor3 = isAvailable and Theme.color.text.primary or Theme.color.text.tertiary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 27,
		})
		
		local subtitleText = ""
		-- R3 audit #12: the old duplicate-label guard string-matched the
		-- display copy ("LOCKED", "Protected", ...) — any unknown
		-- unavailableReason fell through and rendered a SECOND overlapping
		-- subtitle on top of the first. Track creation with a flag instead.
		local subtitleCreated = false
		if isAvailable then
			subtitleText = string.format("Dock %d  •  %d stealable fish", target.dockIndex or 0, target.stealableCount or 0)
		else
			-- Format reason with countdown if applicable (hvfh.6.1.2)
			local reason = target.unavailableReason or "unavailable"
			local reasonLabel = ({
				locked = "LOCKED",
				raid_protection = "Protected",
				loss_capped = "Loss cap reached",
				safe_harbor = "In Safe Harbor",
				victim_cooldown = "Recently raided",
				no_stealable_fish = "No fish to steal",
			})[reason] or reason

			if (reason == "locked" or reason == "raid_protection" or reason == "victim_cooldown") and target.unavailableSeconds and target.unavailableSeconds > 0 then
				subtitleText = string.format("%s  •  %s", reasonLabel, formatRaidTime(target.unavailableSeconds))
				-- Store reference for 1Hz update
				local countdownLabel = makeLabel(row, {
					Size = UDim2.new(1, -110, 0, 16),
					Position = UDim2.new(0, 12, 0, 28),
					Text = subtitleText,
					Font = Theme.type.fonts.body,
					TextSize = Theme.type.sizes.xs,
					TextColor3 = Theme.color.text.tertiary,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 27,
				})
				subtitleCreated = true
				raidTargetCountdownLabels[target.userId] = {
					label = countdownLabel,
					reason = reason,
					reasonLabel = reasonLabel,
					seconds = target.unavailableSeconds,
				}
			else
				subtitleText = reasonLabel
				makeLabel(row, {
					Size = UDim2.new(1, -110, 0, 16),
					Position = UDim2.new(0, 12, 0, 28),
					Text = subtitleText,
					Font = Theme.type.fonts.body,
					TextSize = Theme.type.sizes.xs,
					TextColor3 = Theme.color.text.tertiary,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 27,
				})
				subtitleCreated = true
			end
		end

		if not subtitleCreated then
			makeLabel(row, {
				Size = UDim2.new(1, -110, 0, 16),
				Position = UDim2.new(0, 12, 0, 28),
				Text = subtitleText,
				Font = Theme.type.fonts.body,
				TextSize = Theme.type.sizes.xs,
				TextColor3 = isAvailable and Theme.color.text.secondary or Theme.color.text.tertiary,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 27,
			})
		end
		
		local attempt = makeButton(row, {
			Size = UDim2.new(0, IS_MOBILE and 104 or 92, 0, IS_MOBILE and 44 or 32),
			Position = UDim2.new(1, IS_MOBILE and -114 or -102, 0.5, IS_MOBILE and -22 or -16),
			Text = isAvailable and "RAID" or "UNAVAILABLE",
			BackgroundColor3 = isAvailable and Theme.color.status.bad or Theme.color.surface.elevated,
			TextColor3 = isAvailable and Theme.color.text.primary or Theme.color.text.tertiary,
			TextSize = Theme.type.sizes.xs,
			ZIndex = 27,
			Active = isAvailable,
		})
		
		if isAvailable then
			attempt.Activated:Connect(function()
				if raidInProgress then
					return
				end
				-- TASK 23.1 (hvfh.3.1) gate 2: never start a raid while a
				-- cast/bite minigame holds the overlay slot. Refused BEFORE
				-- RequestRaidAttempt fires — no server deadline starts.
				if isOverlayActive("cast") or isOverlayActive("bite") then
					showNotification("Reeling in a fish — one moment!", Theme.color.status.warn)
					return
				end
				raidInProgress = true
				local result = Remotes.RequestRaidAttempt:InvokeServer(target.userId)
				if not result or not result.ok then
					raidInProgress = false
					-- P0 syntax fix: parenthesize constructor before indexing
					-- (same class as the reasonText fix ~40 lines above).
					local failReason = ({
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
					})[result and result.reason] or "Could not start raid."
					showNotification(failReason, Theme.color.status.bad)
					return
				end
				startRaidMinigame(result)
			end)
		end
		-- R4 polish: staggered entrance on rebuild (signature-gated, so it
		-- only replays on real target changes — not every poll tick).
		staggerFadeIn(row, i)
	end
end

-- TASK 9.2 (0jc.2): raid window state — declared before updateRaidPanelStatic
-- (its earliest reader) so render() can check HasSeenRaidExplanation against
-- raidWindow.open for the onboarding prompt. The OnClientEvent handler is
-- wired at the bottom of this file. TASK 21.4 (harborheist-7w5a): this local
-- was previously declared ~500 lines LOWER (after updateRaidPanelStatic), so
-- the :2409 read bound a nil global and crashed on "attempt to index nil".
local raidWindow = { open = false, remainingSeconds = 0, nextWindowInSeconds = 0 }

-- harborheist-bkn1: SINGLE renderer for both raid opt-in toggle buttons
-- (aquarium panel + raid panel). The two copies had already drifted in copy
-- ('or upgrade)' vs 'or upgrade needed)'); the next behavior change would
-- have landed in one and not the other. TASK 25.3 (hvfh.5.3): the DEC-4 gate
-- is single-sourced server-side (GameConfig.Raid.unlockTotalCatches via
-- StateSync raidEligible); the client renders snapshot fields only.
local function renderRaidOptInButton(btn)
	if not state then
		return
	end
	if state.raidOptIn then
		btn.Text = "RAID OPT-IN: ON (can be targeted)"
		btn.BackgroundColor3 = Theme.color.status.bad
		btn.TextColor3 = Theme.color.text.ink
	elseif not state.raidEligible then
		btn.Text = string.format("RAID OPT-IN: LOCKED (%d/%d catches or upgrade needed)", state.totalCatches or 0, state.raidUnlockCatches or GameConfig.Raid.unlockTotalCatches)
		btn.BackgroundColor3 = Theme.color.surface.elevated
		btn.TextColor3 = Theme.color.text.tertiary
	else
		btn.Text = "RAID OPT-IN: OFF (safe)"
		btn.BackgroundColor3 = Theme.color.surface.elevated
		btn.TextColor3 = Theme.color.text.primary
	end
end

local function updateRaidPanelStatic()
	if not state then
		return
	end
	-- Update status header from local cached window state.
	if raidWindow.open then
		raidStatusLabel.Text = "RAID WATERS OPEN"
		raidStatusLabel.TextColor3 = Theme.color.status.bad
	else
		raidStatusLabel.Text = "Raid waters are calm"
		raidStatusLabel.TextColor3 = Theme.color.text.primary
	end
	-- Update opt-in toggle mirror (harborheist-bkn1: shared helper).
	renderRaidOptInButton(raidOptInPanelButton)
end

local function refreshRaidPanel()
	updateRaidPanelStatic()
	-- harborheist-7h69.5: skeleton rows on cold open (before first server
	-- response) so the target list isn't blank during the InvokeServer
	-- round-trip. raidTargetsLoaded distinguishes "loading" from "server
	-- returned empty" — the initial {} alone can't tell them apart.
	-- Self-terminates when renderRaidTargets destroys the bars on arrival.
	-- Clear first: the manual REFRESH button (1.5s debounce) can call this
	-- before the first InvokeServer returns, stacking duplicate skeleton bars
	-- — matching showCollectionSkeleton's clearCollectionList guard pattern.
	if not raidTargetsLoaded and activePanel == raidPanel then
		for _, child in ipairs(raidTargetList:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		raidTargetCountdownLabels = {}
		createSkeletonRows(raidTargetList, {
			rows = 3,
			rowHeight = IS_MOBILE and 68 or 60,
			zIndex = 26,
		})
	end
	-- Fetch targets from server asynchronously (window open/close or manual refresh).
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.GetRaidTargets:InvokeServer()
		end)
		if ok then
			raidTargets = data or {}
			raidTargetsLoaded = true
			if activePanel == raidPanel then
				renderRaidTargets(raidTargets)
			end
		end
	end)
end

-- ============================================================
-- TASK 26.2 (hvfh.6.2): Auto-refresh raid targets while panel is open
-- Poll every 3s while raid panel is active (0.33/s — safe headroom vs
-- AntiExploitService RATE_LIMITS.get_raid_targets = 10/10s).
-- Signature-guarded: rebuild rows ONLY when payload signature changes
-- (userIds + availability + reasons). Countdown seconds are mutated
-- in place by the 1Hz loop (raidTargetCountdownLabels), NOT included
-- in the signature — otherwise every poll would rebuild rows and
-- destroy mid-tap interactions.
-- ============================================================
local lastRaidTargetsSignature = nil

local function computeRaidTargetsSignature(data)
	if not data or not data.targets then
		return "empty"
	end
	local parts = {}
	for _, target in ipairs(data.targets) do
		-- Include: userId, available flag, reason (if unavailable).
		-- Exclude: unavailableSeconds (countdown) — mutated in place.
		table.insert(parts, tostring(target.userId))
		table.insert(parts, tostring(target.available))
		if target.unavailableReason then
			table.insert(parts, target.unavailableReason)
		end
	end
	return table.concat(parts, "|")
end

-- R3 audit #13: generation guard against poll-chain accumulation. A quick
-- close→reopen (<3s) let the OLD chain's pending task.delay see
-- activePanel == raidPanel again and resume alongside the NEW chain — N
-- quick cycles meant N concurrent 3s invoke loops forever. Each start bumps
-- the generation; stale chains die at their next tick.
local raidPollGeneration = 0

local function pollRaidTargets(generation)
	if activePanel ~= raidPanel then
		-- Panel closed: stop polling.
		return
	end
	if generation ~= raidPollGeneration then
		-- Superseded by a newer chain.
		return
	end
	-- Fetch new targets.
	task.spawn(function()
		local ok, data = pcall(function()
			return Remotes.GetRaidTargets:InvokeServer()
		end)
		if ok and data then
			local newSig = computeRaidTargetsSignature(data)
			if newSig ~= lastRaidTargetsSignature then
				-- Signature changed: rebuild rows.
				raidTargets = data
				renderRaidTargets(raidTargets)
				lastRaidTargetsSignature = newSig
			end
			-- If signature unchanged, do nothing — countdown labels
			-- are already ticking via the 1Hz loop.
		end
	end)
	-- Schedule next poll if panel still open.
	task.delay(3, function()
		pollRaidTargets(generation)
	end)
end

local function startRaidPanelPolling()
	-- Initialize signature from current data.
	lastRaidTargetsSignature = computeRaidTargetsSignature(raidTargets)
	-- Start polling loop (new generation kills any surviving old chain).
	raidPollGeneration += 1
	-- Fresh-eyes fix: capture the generation NOW. Passing the upvalue
	-- (pollRaidTargets(raidPollGeneration)) reads it when the delay FIRES —
	-- a close→reopen inside 3s bumps the generation and the stale chain's
	-- first tick would adopt the NEW value, reviving alongside the new chain
	-- (the exact leak the guard exists to kill).
	local generation = raidPollGeneration
	task.delay(3, function()
		pollRaidTargets(generation)
	end)
end

-- TASK 21.4 (harborheist-7w5a): toggleRaidPanel moved BELOW
-- startRaidPanelPolling — it calls it, and Luau binds locals lexically at
-- the definition site, so the previous order crashed the RAID button
-- handler with "attempt to call a nil value".
local function toggleRaidPanel()
	if overlayBlocksPanels() then
		return
	end
	if activePanel == raidPanel then
		hidePanels()
		-- Polling stops automatically (activePanel check in pollRaidTargets).
		return
	end
	showPanel(raidPanel)
	refreshRaidPanel()
	-- TASK 26.2 (hvfh.6.2): start auto-refresh polling.
	startRaidPanelPolling()
end

-- ============================================================
-- Raid timing minigame overlay (TASK 8.5b / gdj.14)
-- ============================================================
-- TASK 23.2 (hvfh.3.2): Unified overlay factory
local raidMinigameFrame, raidTitle, raidBarTrack, raidGoodZone, raidPerfectZone, raidSubtitle, raidMarker, raidMarkerGlow =
	makeOverlayFrame("RaidMinigame",
		IS_MOBILE and "TAP IN THE GREEN ZONE!" or "CLICK IN THE GREEN ZONE!",
		"PERFECT = HIGH CHANCE  •  GOOD = FAIR  •  MISS = LOW")

local raidMinigameTween = nil
local raidMinigameDuration = 0
local raidMinigameGeneration = 0

local function stopRaidMinigame()
	raidMinigameFrame.Visible = false
	releaseOverlay("raid")
	if raidMinigameTween then
		raidMinigameTween:Cancel()
		raidMinigameTween = nil
	end
end

function startRaidMinigame(challenge)
	-- TASK 23.1 (hvfh.3.1): take the overlay slot. Gate 2 (the RAID
	-- button handler) already refuses when a cast/bite is active, so this
	-- is the defensive backstop; bailing here leaves the raid challenge
	-- unresolved server-side (the server deadline simply expires).
	if not requestOverlay("raid") then
		-- Fresh-eyes fix: a BiteEvent CAN land during the invoke round-trip
		-- (CastState(false) frees the slot before the server fires the bite,
		-- so gate 2 passed, then the bite took the slot). The attempt
		-- handler already set raidInProgress = true — reset it or the RAID
		-- button is silently dead for the rest of the session.
		raidInProgress = false
		showNotification("Reeling in a fish — the raid attempt was cancelled.", Theme.color.status.warn)
		return
	end
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
	-- harborheist-d6et: generation-guard the expiry. The closure reads
	-- raidMinigameFrame.Visible at FIRE time, so without the guard a stale
	-- timer from a PREVIOUS raid would see the NEW raid's visible frame and
	-- stopRaidMinigame() it mid-play (plus raidInProgress=false and a bogus
	-- "Too slow!" toast). Latent today — raiderCooldownSeconds (360s) is
	-- burned at attempt time so no re-raid can start inside the 8s window —
	-- but a config retune below durationSeconds would weaponize it.
	raidMinigameGeneration += 1
	local generation = raidMinigameGeneration
	task.delay(raidMinigameDuration, function()
		if generation ~= raidMinigameGeneration then
			return
		end
		if raidMinigameFrame.Visible then
			stopRaidMinigame()
			raidInProgress = false
			showNotification("Too slow! The raid window of opportunity passed...", Theme.color.status.warn)
		end
	end)

	-- TASK 23.1 (hvfh.3.1): single registration with the overlay router,
	-- replacing the per-raid UserInputService.InputBegan connection (which
	-- the old stopRaidMinigame had to disconnect). Identical semantics.
	overlayInputHandlers.raid = function(input, gp)
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
						showNotification(string.format("Heist %s! Stole a %s %s worth $%s.", result.tier or "", result.rarity or "", result.speciesId or "", formatCash(result.value or 0)), Theme.color.status.good)
					elseif result.ok and not result.success then
						showNotification("Heist failed — the fish slipped away.", Theme.color.status.warn)
					end
				end
				refreshRaidPanel()
			end)
		end
	end
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
table.insert(safeTopConsumers, function()
	raidBanner.Position = IS_MOBILE and UDim2.new(1, -12, 0, SAFE_TOP + 6) or UDim2.new(0.5, 0, 0, SAFE_TOP + 6)
end)
raidBanner.BackgroundColor3 = Theme.color.surface.primary
raidBanner.BackgroundTransparency = 0.12
raidBanner.Visible = false
raidBanner.ZIndex = 18
raidBanner.Parent = screenGui
corner(raidBanner, Theme.corners.pill)
stroke(raidBanner, 0.7, Theme.color.status.bad, 1.5)

local raidBannerIcon = Instance.new("Frame")
raidBannerIcon.Size = UDim2.new(0, 8, 0, 8)
raidBannerIcon.Position = UDim2.new(0, 14, 0.5, -4)
raidBannerIcon.BackgroundColor3 = Theme.color.status.bad
raidBannerIcon.ZIndex = 19
raidBannerIcon.Parent = raidBanner
corner(raidBannerIcon, Theme.corners.pill)

local raidBannerLabel = makeLabel(raidBanner, {
	Size = UDim2.new(1, -34, 1, 0),
	Position = UDim2.new(0, 28, 0, 0),
	Text = IS_MOBILE and "RAID OPEN 0:00" or "RAID WATERS OPEN 0:00",
	Font = Theme.type.fonts.bold,
	TextSize = Theme.type.sizes.sm,
	TextColor3 = Theme.color.status.bad,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 19,
})
-- ============================================================
-- Action bar
--   Desktop: bottom-center pill bar with keyboard hint chips.
--   Mobile: right-edge thumb-zone stack of large round buttons.
-- ============================================================
local ACTIONS = {
	{ id = "fish", label = "FISH", short = "FISH", key = "F", color = Theme.color.status.good },
	{ id = "store", label = "BAG", short = "BAG", key = "G", color = Theme.color.accent.base },
	{ id = "collection", label = "BOOK", short = "BOOK", key = "C", color = Theme.color.status.warn },
	{ id = "aquarium", label = "TANK", short = "TANK", key = "T", color = Theme.color.brand.purple },
	{ id = "quests", label = "QUESTS", short = "QUEST", key = "Q", color = Theme.color.brand.quest },
	{ id = "raid", label = "RAID", short = "RAID", key = "R", color = Theme.color.status.bad },
	{ id = "boat", label = "BOAT", short = "BOAT", key = "B", color = Theme.color.brand.boat },
}

-- TASK 28.2 (hvfh.8.2): the prompt offset is DERIVED from the same
-- constants that build the stack/bar, so adding/removing an ACTION keeps
-- the prompt clear with zero manual edits. Recomputed on ViewportSize
-- change (rotation / window resize) — the previous one-shot startup
-- compute re-introduced the collision on rotation.
local function updateOnboardingPromptOffset()
	if IS_MOBILE then
		-- Calculate actual stack content height: buttons + gaps between them
		-- mobileStackPitch = btnSize + MOBILE_STACK_PADDING, so total = #ACTIONS * btnSize + (#ACTIONS - 1) * MOBILE_STACK_PADDING
		local btnSize = mobileStackPitch - MOBILE_STACK_PADDING
		local stackContentH = #ACTIONS * btnSize + (#ACTIONS - 1) * MOBILE_STACK_PADDING
		local offset = MOBILE_STACK_BOTTOM + stackContentH + PROMPT_STACK_GAP
		-- Short landscape phones: the derived offset would push the prompt
		-- into the toast host / HUD. Clamp so the prompt's top edge stays
		-- at or below the toast host's lower edge (+8px margin) — the
		-- bead's "safe fraction" fallback, anchored to the actual HUD
		-- geometry instead of an arbitrary ratio. Toast-host and prompt
		-- dimensions are read from their single sources (no literals here).
		-- Trade-off accepted per bead: on ultra-short screens the prompt
		-- may overlap the stack, never the HUD/toasts.
		local cam = workspace.CurrentCamera
		if cam then
			local toastHostBottom = SAFE_TOP + TOAST_HOST_TOP_OFFSET + TOAST_HOST_HEIGHT + 8
			local maxOffset = cam.ViewportSize.Y - toastHostBottom - onboardingPrompt.Size.Y.Offset
			offset = math.min(offset, math.max(maxOffset, 0))
		end
		onboardingPrompt.Position = UDim2.new(0.5, 0, 1, -offset)
	else
		-- Desktop: bar top = DESKTOP_BAR_BOTTOM + DESKTOP_BAR_H from the
		-- bottom; the prompt clears it by PROMPT_BAR_GAP.
		onboardingPrompt.Position = UDim2.new(0.5, 0, 1, -(DESKTOP_BAR_BOTTOM + DESKTOP_BAR_H + PROMPT_BAR_GAP))
	end
end
updateOnboardingPromptOffset()

local promptViewportConn
local function bindPromptViewport(cam)
	if not cam then
		return
	end
	if promptViewportConn then
		promptViewportConn:Disconnect()
	end
	promptViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateOnboardingPromptOffset)
end
bindPromptViewport(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindPromptViewport(workspace.CurrentCamera)
end)

local actionButtons = {}

if IS_MOBILE then
	local stack = Instance.new("ScrollingFrame")
	stack.Name = "ActionStack"
	stack.AnchorPoint = Vector2.new(1, 1)
	stack.Position = UDim2.new(1, -12, 1, -MOBILE_STACK_BOTTOM)
	stack.Size = UDim2.new(0, 64, 0, #ACTIONS * MOBILE_STACK_PITCH)
	stack.BackgroundTransparency = 1
	stack.ScrollingEnabled = false
	stack.ScrollBarThickness = 0
	stack.Parent = screenGui

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	stackLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	stackLayout.Padding = UDim.new(0, MOBILE_STACK_PADDING)
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Parent = stack

	local mobileStackButtons = {}
	for i, action in ipairs(ACTIONS) do
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(0, 60, 0, 60)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = i
		holder.Parent = stack

		local btn = makeButton(holder, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			BackgroundColor3 = Theme.color.surface.primary,
			TextColor3 = action.color,
			CornerRadius = 18,
		})
		btn.BackgroundTransparency = 0.16
		stroke(btn, 0.58, action.color, 1.5)
		-- harborheist-m32r: on mobile there IS no keyboard — the hero glyph
		-- is the ACTION NAME, and the key letter demotes to the small
		-- footnote (kept for cross-platform players). Previously the 20px
		-- hero showed 'F'/'G'/... and the actual action name was 9px.
		local heroLabel = makeLabel(btn, {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.new(0, 0, 0, 9),
			Text = action.short,
			Font = Theme.type.fonts.head,
			TextSize = Theme.type.sizes.md,
			TextColor3 = action.color,
		})
		local footnoteLabel = makeLabel(btn, {
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 1, -20),
			Text = action.key,
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.text.tertiary,
		})
		actionButtons[action.id] = btn
		actionButtons[action.id .. "_label"] = heroLabel
		-- harborheist-a2ug.4: capture the key footnote so the bite-wait
		-- affordance can animate it ("WAIT", "WAIT.", ...) during fishState
		-- == "waiting" — the footnote's "F" is only a cross-platform hint
		-- (m32r), so demoting it while waiting is safe.
		actionButtons[action.id .. "_footnote"] = footnoteLabel
		mobileStackButtons[i] = { holder = holder, hero = heroLabel }
	end
	-- harborheist-hqn1 + harborheist-xrfp: fit the stack to the viewport height.
	-- The fixed 60px/70px layout needs MOBILE_STACK_BOTTOM + 7*70 = 580px vertically;
	-- short landscape phones (~375px) pushed the top buttons (QUEST/RAID/
	-- BOAT) off-screen and unreachable. Mirrors the desktop bar's
	-- responsive shrink (TASK 28.1). mobileStackPitch is shared with
	-- updateOnboardingPromptOffset so the prompt tracks the shrunk stack.
	--
	-- harborheist-xrfp fix: enforce 44px minimum touch target (Apple HIG / Material Design).
	-- If scaling would make buttons smaller than 44px, use a scrollable container instead.
	local MIN_TOUCH_TARGET = 44
	local MIN_SCALE = MIN_TOUCH_TARGET / 60  -- 0.733
	
	local function layoutMobileStack(viewportH)
		local cam = workspace.CurrentCamera
		viewportH = viewportH or (cam and cam.ViewportSize.Y) or 800
		-- Calculate original content height: buttons + gaps between them
		local fullH = #ACTIONS * 60 + (#ACTIONS - 1) * MOBILE_STACK_PADDING
		-- Available height: viewport minus bottom margin and HUD zone
		local availH = viewportH - MOBILE_STACK_BOTTOM - (SAFE_TOP + 60)
		local idealScale = availH / fullH
		
		-- If ideal scale would violate touch target, use minimum scale and enable scrolling
		if idealScale < MIN_SCALE then
			local btnSize = MIN_TOUCH_TARGET
			-- Pitch = button size + padding between buttons
			mobileStackPitch = btnSize + MOBILE_STACK_PADDING
			-- Calculate actual content height: buttons + gaps between them
			local contentH = #ACTIONS * btnSize + (#ACTIONS - 1) * MOBILE_STACK_PADDING
			-- Clamp stack height to available space, let ScrollingFrame handle overflow
			stack.Size = UDim2.new(0, btnSize + 4, 0, math.min(contentH, availH))
			for _, entry in ipairs(mobileStackButtons) do
				entry.holder.Size = UDim2.new(0, btnSize, 0, btnSize)
				entry.hero.TextSize = math.max(12, math.floor(18 * MIN_SCALE + 0.5))
			end
			-- Enable scrolling if stack overflows viewport
			if stack:IsA("ScrollingFrame") then
				stack.CanvasSize = UDim2.new(0, 0, 0, contentH)
				stack.ScrollingEnabled = true
				stack.ScrollingDirection = Enum.ScrollingDirection.Y
			end
		else
			-- Normal scaling (fits within viewport)
			local scale = math.clamp(idealScale, MIN_SCALE, 1)
			local btnSize = math.floor(60 * scale + 0.5)
			-- Pitch = button size + padding between buttons
			mobileStackPitch = btnSize + MOBILE_STACK_PADDING
			-- Calculate actual content height: buttons + gaps between them
			local contentH = #ACTIONS * btnSize + (#ACTIONS - 1) * MOBILE_STACK_PADDING
			stack.Size = UDim2.new(0, btnSize + 4, 0, contentH)
			for _, entry in ipairs(mobileStackButtons) do
				entry.holder.Size = UDim2.new(0, btnSize, 0, btnSize)
				entry.hero.TextSize = math.max(12, math.floor(18 * scale + 0.5))
			end
			-- Disable scrolling when it fits
			if stack:IsA("ScrollingFrame") then
				stack.CanvasSize = UDim2.new(0, 0, 0, 0)
				stack.ScrollingEnabled = false
			end
		end
	end
	layoutMobileStack()

	local stackViewportConn
	local function bindStackViewport(cam)
		if not cam then
			return
		end
		if stackViewportConn then
			stackViewportConn:Disconnect()
		end
		stackViewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			layoutMobileStack(cam.ViewportSize.Y)
			updateOnboardingPromptOffset()
		end)
	end
	bindStackViewport(workspace.CurrentCamera)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindStackViewport(workspace.CurrentCamera)
		layoutMobileStack()
		updateOnboardingPromptOffset()
	end)
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
	bar.Position = UDim2.new(0.5, 0, 1, -DESKTOP_BAR_BOTTOM)
	bar.Size = UDim2.new(0, barWidthFor(BAR_BTN_W), 0, DESKTOP_BAR_H)
	bar.BackgroundColor3 = Theme.color.surface.primary
	bar.BackgroundTransparency = 0.2
	bar.Parent = screenGui
	corner(bar, Theme.corners.lg)
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
			BackgroundColor3 = Theme.color.surface.secondary,
			LayoutOrder = i,
		})
		btn.BackgroundTransparency = 0.25
		stroke(btn, 0.88)

		local textLabel = makeLabel(btn, {
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.new(0, 10, 0, 0),
			Text = action.label,
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.sm,
			TextColor3 = action.color,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local keyChip = Instance.new("Frame")
		keyChip.Size = UDim2.new(0, 20, 0, 20)
		keyChip.AnchorPoint = Vector2.new(1, 0.5)
		keyChip.Position = UDim2.new(1, -8, 0.5, 0)
		keyChip.BackgroundColor3 = Theme.color.surface.elevated
		keyChip.Parent = btn
		corner(keyChip, Theme.corners.compact)
		makeLabel(keyChip, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = action.key,
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.text.secondary,
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
		bar.Size = UDim2.new(0, barWidthFor(btnW), 0, DESKTOP_BAR_H)
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

-- harborheist-ncxu: Register action buttons with keyboard navigation
-- Tab order: action buttons first (fish, store, collection, quests, raid, boat)
if not IS_MOBILE then
	local tabOrder = 1
	for _, action in ipairs(ACTIONS) do
		local btn = actionButtons[action.id]
		if btn then
			KeyboardNav:Register(btn, tabOrder)
			tabOrder = tabOrder + 1
		end
	end
	
	-- Register panel close buttons (continue tab order)
	if aquariumClose then
		KeyboardNav:Register(aquariumClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	if inventoryClose then
		KeyboardNav:Register(inventoryClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	if collectionClose then
		KeyboardNav:Register(collectionClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	if shopClose then
		KeyboardNav:Register(shopClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	if questClose then
		KeyboardNav:Register(questClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	if raidClose then
		KeyboardNav:Register(raidClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	
	-- Register onboarding and sell/store prompt buttons
	if onboardingDismiss then
		KeyboardNav:Register(onboardingDismiss, tabOrder)
		tabOrder = tabOrder + 1
	end
	if sellStoreClose then
		KeyboardNav:Register(sellStoreClose, tabOrder)
		tabOrder = tabOrder + 1
	end
	if sellStoreSellBtn then
		KeyboardNav:Register(sellStoreSellBtn, tabOrder)
		tabOrder = tabOrder + 1
	end
	if sellStoreStoreBtn then
		KeyboardNav:Register(sellStoreStoreBtn, tabOrder)
		tabOrder = tabOrder + 1
	end
	
	-- Register HUD click button
	if hudClick then
		KeyboardNav:Register(hudClick, tabOrder)
		tabOrder = tabOrder + 1
	end
	
	-- Register aquarium panel buttons
	if claimButton then
		KeyboardNav:Register(claimButton, tabOrder)
		tabOrder = tabOrder + 1
	end
	if sellButton then
		KeyboardNav:Register(sellButton, tabOrder)
		tabOrder = tabOrder + 1
	end
	if lockButton then
		KeyboardNav:Register(lockButton, tabOrder)
		tabOrder = tabOrder + 1
	end
	if raidOptInButton then
		KeyboardNav:Register(raidOptInButton, tabOrder)
		tabOrder = tabOrder + 1
	end
	if invStoreAllBtn then
		KeyboardNav:Register(invStoreAllBtn, tabOrder)
		tabOrder = tabOrder + 1
	end
	
	-- Enable keyboard navigation
	KeyboardNav:Enable()
end

-- TASK 24.4 (hvfh.4.4): action-bar active-panel indicator. showPanel and
-- hidePanels already track activePanel centrally — this renders that state
-- on the buttons (no parallel state). Selected treatment: brighter stroke
-- (~0.3 vs 0.88 desktop / 0.58 mobile), action-colored, slightly thicker.
-- FISH and BOAT are momentary actions with no panel — never highlighted.
-- Assigned here (not declared with showPanel) because actionButtons and the
-- panel locals are all defined above this point; see the forward decl.
updateActionBarIndicator = function()
	local panelToAction = {
		[inventoryPanel] = "store",
		[collectionPanel] = "collection",
		[aquariumPanel] = "aquarium",
		[questPanel] = "quests",
		[raidPanel] = "raid",
	}
	local activeId = activePanel and panelToAction[activePanel] or nil
	for _, action in ipairs(ACTIONS) do
		local btn = actionButtons[action.id]
		local s = btn and btn:FindFirstChildOfClass("UIStroke")
		if s then
			local selected = (action.id == activeId)
			if IS_MOBILE then
				s.Transparency = selected and 0.3 or 0.58
				s.Thickness = selected and 2.5 or 1.5
			else
				s.Transparency = selected and 0.3 or 0.88
				s.Color = selected and action.color or Theme.color.stroke
				s.Thickness = selected and 2 or 1
			end
		end
	end
end

-- ============================================================
-- Fishing minigame overlay — glowing timing bar
-- ============================================================
-- TASK 23.2 (hvfh.3.2): Unified overlay factory
-- [harborheist-a2ug.5] Show the concrete cast-timing prize instead of vague
-- "BONUS LUCK". Values are flat config (gear-independent) — set once at
-- construction. See FishingService TASK 14.24 (DECISION C): a perfect cast
-- inflates the effective bite zone from the rod's base to biteZoneCeiling via
-- (luckBonus/maxLuck)*(ceiling-base); rod/bait luck are owned stats, not at
-- stake in this moment, so we show ONLY the marginal timing prizes.
local castOverlay, castTitle, timingBar, hitZoneFrame, perfectZoneFrame, castSubtitle, marker, markerGlow =
	makeOverlayFrame("CastOverlay",
		IS_MOBILE and "TAP WHEN IN THE GREEN!" or "CLICK WHEN IN THE GREEN!",
		string.format("PERFECT +%d LUCK  •  GOOD +%d LUCK",
			GameConfig.MiniGame.accuracyLuckBonus.perfect,
			GameConfig.MiniGame.accuracyLuckBonus.good))

local markTween = nil

local function stopCastOverlay()
	castOverlay.Visible = false
	releaseOverlay("cast")
	if markTween then
		markTween:Cancel()
		markTween = nil
	end
end

-- TASK 23.1 (hvfh.3.1): single registration with the overlay router,
-- replacing the per-cast UserInputService.InputBegan connection (which
-- the old stopCastOverlay had to disconnect). Identical semantics: skip
-- game-processed input, require the local casting flag, resolve accuracy
-- from the same castDeadline/castOverlayDuration pair, fire CastResult.
overlayInputHandlers.cast = function(input, gp)
	if gp then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if not casting then
			return
		end
		local elapsed = os.clock() - (castDeadline - castOverlayDuration)
		local accuracy = math.clamp(elapsed / castOverlayDuration, 0, 1)
		castAwaitingInput = false -- harborheist-njqm: input received, no coach toast
		stopCastOverlay()
		Remotes.CastResult:FireServer(accuracy)
	end
end

-- ============================================================
-- State rendering
-- ============================================================
local function toHex(color)
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local dataStoreWarningShown = false

-- ============================================================
-- TASK 22.1 (hvfh.2.1): FISH button state machine.
-- Replaces the binary `casting`-flag label with three visually
-- distinct states driven by server events (never per-frame churn):
--   idle        "FISH"            green,  static
--   waiting     "WAITING"/"..."   muted,  slow stroke pulse
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
		labelColor = Theme.color.status.warn
		strokeColor = Theme.color.status.warn
		baseTrans = fishStrokeDefaultTrans or 0.5
		pulseMode = "fast"
	elseif fishState == "waiting" then
		labelText = IS_MOBILE and "..." or "WAITING"
		labelColor = Theme.color.text.tertiary
		strokeColor = Theme.color.text.tertiary
		baseTrans = fishStrokeDefaultTrans or 0.6
		pulseMode = "slow"
	else
		labelText = "FISH"
		labelColor = Theme.color.status.good
		strokeColor = fishStrokeDefaultColor or Theme.color.status.good
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

-- ============================================================
-- harborheist-a2ug.4: bite-wait engagement affordance.
-- The 2-6s server-picked bite delay (FishingService BITE_MIN/MAX_DELAY
-- 2.0/6.0) used to read as a dead button: static "WAITING" on desktop,
-- a bare "..." on mobile. While fishState == "waiting", animate the
-- ellipsis so the button visibly lives: desktop hero "WAITING" cycles
-- dots; mobile hero stays "..." and the key footnote (its "F" is only
-- a cross-platform hint, m32r) animates "WAIT", "WAIT.", "WAIT..",
-- "WAIT...". Deliberately NOT a progress bar / countdown — the client
-- must not know the server delay (anti-exploit), and an ETA affordance
-- would mislead.
local waitingDotsLoop = nil
-- Original footnote text captured before the dots animation demotes it,
-- so stopWaitingDots restores the actual key glyph instead of a literal.
local waitingDotsFootnoteText = nil

local function startWaitingDots()
	if waitingDotsLoop then
		return
	end
	local lbl = actionButtons.fish_label or actionButtons.fish
	local footnote = actionButtons.fish_footnote
	if footnote then
		waitingDotsFootnoteText = footnote.Text
	end
	waitingDotsLoop = task.spawn(function()
		local step = 0
		while fishState == "waiting" do
			local dots = string.rep(".", step % 4)
			if IS_MOBILE then
				-- Hero "..." already reads as waiting; animate the footnote.
				if footnote then
					footnote.Text = "WAIT" .. dots
				end
			elseif lbl then
				lbl.Text = "WAITING" .. dots
			end
			step += 1
			task.wait(0.4)
		end
	end)
end

local function stopWaitingDots()
	if waitingDotsLoop then
		task.cancel(waitingDotsLoop)
		waitingDotsLoop = nil
	end
	local footnote = actionButtons.fish_footnote
	if footnote and waitingDotsFootnoteText then
		footnote.Text = waitingDotsFootnoteText
		waitingDotsFootnoteText = nil
	end
	-- Desktop hero text is restored by renderFishButton (idempotent).
end

-- First-wait expectation setting: a first-timer has no idea how long a
-- bite takes. Show one contextual prompt on their first-ever cast;
-- dismissedPrompts is session-scoped, so it never nags twice in a
-- session, and HasCaughtFirstFish gates it out permanently after.
local firstWaitArmed = false

local function setFishState(newState)
	local previous = fishState
	fishState = newState
	renderFishButton()
	if newState == "waiting" then
		startWaitingDots()
		if previous ~= "waiting"
			and not firstWaitArmed
			and not (state and state.onboarding and state.onboarding.HasCaughtFirstFish)
		then
			firstWaitArmed = true
			showOnboardingPrompt("firstWait",
				"A fish usually bites within a few seconds — stay ready!",
				Theme.color.status.warn)
		end
	else
		stopWaitingDots()
		if previous == "waiting" and firstWaitArmed and currentPromptStage == "firstWait" then
			dismissOnboardingPrompt("firstWait")
		end
	end
end

-- ============================================================
-- TASK 29.1 (hvfh.8.4): Persistent cast-zone guidance cue.
-- A soft world-space BillboardGui (bobbing arrow + slow-pulsing
-- ring) over the player's FishingZone, visible ONLY while
-- snapshot onboarding.HasCaughtFirstFish == false. It disappears
-- because the player succeeded, not because they dismissed it.
-- Cozy styling per PRD (warm accent, no flashing red).
-- ============================================================
local zoneCueGui = nil       -- the BillboardGui instance (or nil)
local zoneCueLoop = nil      -- the Heartbeat connection
local zoneCueDockIndex = nil -- which dock the cue is attached to

local function destroyZoneCue()
	if zoneCueLoop then
		zoneCueLoop:Disconnect()
		zoneCueLoop = nil
	end
	if zoneCueGui then
		zoneCueGui:Destroy()
		zoneCueGui = nil
	end
	zoneCueDockIndex = nil
end

-- Build or refresh the cue for the player's dock. No-op if no dock
-- assigned (dockIndex nil = spawned at plaza — no personal zone).
local function updateZoneCue(dockIndex, hasCaught)
	if hasCaught or not dockIndex then
		destroyZoneCue()
		return
	end
	-- Already attached to the correct dock — nothing to do.
	if zoneCueGui and zoneCueDockIndex == dockIndex then
		return
	end
	-- Dock changed (rare: rejoin to a different dock) — rebuild.
	destroyZoneCue()
	local docksFolder = workspace:FindFirstChild("Docks")
	if not docksFolder then
		return
	end
	local dock = docksFolder:FindFirstChild("Dock" .. tostring(dockIndex))
	if not dock then
		return
	end
	local zone = dock:FindFirstChild("FishingZone")
	if not zone then
		return
	end
	zoneCueDockIndex = dockIndex
	-- BillboardGui floats above the zone pad, always faces the camera.
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZoneCue"
	gui.Adornee = zone
	gui.Size = UDim2.new(0, 120, 0, 80)
	gui.StudsOffset = Vector3.new(0, 5, 0) -- 5 studs above the zone center
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80 -- fades out when far away (cozy, not intrusive)
	gui.Parent = zone
	zoneCueGui = gui
	-- Downward-pointing arrow (triangle-ish via rotated frame) in warm green.
	local arrow = Instance.new("Frame")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.new(0, 20, 0, 20)
	arrow.Position = UDim2.new(0.5, 0, 0.35, 0)
	arrow.BackgroundColor3 = Theme.color.status.good
	arrow.BackgroundTransparency = 0.2
	arrow.Rotation = 45 -- diamond; the bottom half reads as a down-arrow tip
	local arrowCorner = Instance.new("UICorner")
	arrowCorner.CornerRadius = UDim.new(0, 4)
	arrowCorner.Parent = arrow
	arrow.Parent = gui
	-- Soft pulsing ring below the arrow (the "glow" that draws the eye).
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.new(0, 40, 0, 40)
	ring.Position = UDim2.new(0.5, 0, 0.7, 0)
	ring.BackgroundColor3 = Theme.color.status.good
	ring.BackgroundTransparency = 0.7
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0) -- circle
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Theme.color.status.good
	ringStroke.Thickness = 2
	ringStroke.Transparency = 0.3
	ringStroke.Parent = ring
	ring.Parent = gui
	-- Gentle pulse: arrow bobs up/down, ring scales/fades slowly.
	-- Matches the cozy PRD aesthetic — no flashing, no urgency colors.
	local RunService = game:GetService("RunService")
	zoneCueLoop = RunService.Heartbeat:Connect(function()
		-- Self-destruct if the zone part was destroyed (server dock
		-- teardown) — prevents a leaked connection after the gui is gone.
		if not zoneCueGui or not zoneCueGui.Parent then
			destroyZoneCue()
			return
		end
		local t = os.clock()
		-- Bob: arrow moves ±6px on a 1.5s cycle.
		arrow.Position = UDim2.new(0.5, 0, 0.35 + math.sin(t * 4) * 0.06, 0)
		-- Pulse: ring scales 1.0→1.25 + fades on a 2s cycle.
		local pulse = (math.sin(t * 3) + 1) / 2 -- 0→1
		ring.Size = UDim2.new(0, 40 + pulse * 10, 0, 40 + pulse * 10)
		ring.BackgroundTransparency = 0.7 - pulse * 0.25
		ringStroke.Transparency = 0.3 - pulse * 0.2
	end)
end

-- R4 polish #15: last-applied lock-button state class — render() tweens
-- colors only on class change (never on the 1Hz countdown text updates).
local lastLockClass = nil
-- harborheist-tzgk/03mo: lazily-created boat state dot, owned by render().
local boatStateDot = nil
-- harborheist-rxz0: last-applied capacity-bar state — tween only on change.
local lastCapacityRatio = nil
local lastCapacityClass = nil
-- harborheist-yi2q: lazily-created BAG count badge, owned by render().
local bagBadge, bagBadgeLabel = nil, nil

local function render()
	if not state then
		return
	end
	-- TASK 10.5: DataStore failure handling — show warning when unhealthy
	-- (R4 polish #12: token colors — raw literals were off-palette)
	if state.dataStoreHealthy == false and not dataStoreWarningShown then
		dataStoreWarningShown = true
		showNotification("Saving unavailable -- try again. Your progress is safe but purchases may not persist.", Theme.color.status.bad)
	elseif state.dataStoreHealthy ~= false and dataStoreWarningShown then
		dataStoreWarningShown = false
		showNotification("Saving restored!", Theme.color.status.good)
	end
	animateCashTo(state.cash)
	-- TASK 24.1 (hvfh.4.1): rate + pulsing claim-green "ready" segment (the
	-- pulse loop re-asserts it while ready > 0; this covers every state push).
	updateIncomeLine()
	carryLabel.Text = string.format("On line: %d / %d fish", state.carried or 0, state.maxCarried or 0)
	-- harborheist-yi2q: carried-count badge on the BAG action button — the
	-- carry pill showed the count but the button itself gave none, and a
	-- player at cap learned it only AFTER their cast was refused. The badge
	-- floats at the button's top-right corner (clear of the desktop key
	-- chip and the mobile hero label) and tints red at cap.
	if not bagBadge then
		bagBadge = Instance.new("Frame")
		bagBadge.Name = "BagCountBadge"
		bagBadge.AnchorPoint = Vector2.new(1, 0)
		bagBadge.Size = UDim2.new(0, 26, 0, 12)
		bagBadge.Position = UDim2.new(1, -4, 0, -4)
		bagBadge.BackgroundColor3 = Theme.color.surface.elevated
		bagBadge.BorderSizePixel = 0
		bagBadge.ZIndex = 10
		bagBadge.Parent = actionButtons.store
		corner(bagBadge, Theme.corners.pill)
		bagBadgeLabel = makeLabel(bagBadge, {
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			Font = Theme.type.fonts.bold,
			TextSize = Theme.type.sizes.xs,
			TextColor3 = Theme.color.text.secondary,
		})
	end
	local maxCarry = state.maxCarried or 0
	local bagFull = maxCarry > 0 and (state.carried or 0) >= maxCarry
	bagBadgeLabel.Text = string.format("%d/%d", state.carried or 0, maxCarry)
	bagBadge.BackgroundColor3 = bagFull and Theme.color.status.bad or Theme.color.surface.elevated
	bagBadgeLabel.TextColor3 = bagFull and Theme.color.text.ink or Theme.color.text.secondary
	-- TASK 4.4 (0cw.4 / wqw.18): live-update the inventory panel on every
	-- state push (catch, per-fish sell/store, bulk actions) while it is open.
	if activePanel == inventoryPanel then
		renderInventory()
	end

	renderFishButton()

	-- TASK 29.1 (hvfh.8.4): persistent cast-zone guidance. The cue
	-- lives only while the player hasn't caught their first fish and
	-- has an assigned dock. It self-destructs the instant the flag
	-- flips — progress-gated, never dismiss-gated.
	updateZoneCue(state.dockIndex, (state.onboarding or {}).HasCaughtFirstFish == true)

	-- harborheist-tzgk + harborheist-03mo: render() no longer writes the
	-- boat LABEL. layoutDesktopBar / the mobile stack builder own button
	-- text — the 1Hz 'SAILING'/'SAIL' stomp fought the short-label layout
	-- (tzgk), and a STATE string on a COMMAND button read as a command, so
	-- tapping it earned the 'already have a boat' error toast (03mo).
	-- render() owns a state dot instead: cyan dot top-right = boat is out.
	if not boatStateDot then
		boatStateDot = Instance.new("Frame")
		boatStateDot.Name = "BoatStateDot"
		boatStateDot.AnchorPoint = Vector2.new(1, 0)
		boatStateDot.Size = UDim2.new(0, 8, 0, 8)
		boatStateDot.Position = UDim2.new(1, -5, 0, 5)
		boatStateDot.BackgroundColor3 = Theme.color.brand.boat
		boatStateDot.BorderSizePixel = 0
		boatStateDot.ZIndex = 10
		boatStateDot.Parent = actionButtons.boat
		corner(boatStateDot, Theme.corners.slim)
	end
	boatStateDot.Visible = state.hasBoat == true

	-- R3 audit #20: the aquarium stats RichText rebuild, rarity list, capacity
	-- tween, and lock-button state were running on EVERY 1Hz state push even
	-- with the panel closed — wasted string churn + layout invalidation. Gate
	-- ONLY the panel-specific block on visibility; everything after (SELL ALL
	-- disarm, stun WalkSpeed, CLAIM button, onboarding prompts) must keep
	-- running unconditionally. (HUD income/cash/carry are updated above.)
	if activePanel == aquariumPanel then
		local rodLevel = state.rodLevel or 1
		local baitLevel = state.baitLevel or 1
		local rodName = (GameConfig.Rods[rodLevel] and GameConfig.Rods[rodLevel].name) or "Basic Rod"
		local baitName = (GameConfig.Baits[baitLevel] and GameConfig.Baits[baitLevel].name) or "Worms"
	-- harborheist-9ocy: reuse the HUD's adaptive formatIncomeRate here — the
	-- raw '$%.1f / sec' form read '$0.0 / sec' for starter tanks (the exact
	-- complaint hvfh.2.3 fixed on the HUD), in the panel where players go to
	-- understand income.
	aquariumStats.Text = string.format(
		'<font color="#EEF3FA"><b>%d / %d fish</b></font>  •  <font color="#86EFAC"><b>%s</b></font>\n%s + %s\nTank %d  •  Lock %d  •  Alarm %d',
		state.liveWellCount, state.capacity, formatIncomeRate(state.incomePerSec), rodName, baitName,
		state.upgradeLevel or 1, state.lockLevel or 0, state.alarmLevel or 0
	)
	local capacityRatio = math.clamp(state.liveWellCount / math.max(1, state.capacity), 0, 1)
	-- R4 polish: capacity bar doubles as ambient status — purple while
	-- comfortable, amber past 60%, red past 85% ("nearly full, sell or
	-- upgrade"). Color tweens with the size so transitions stay smooth.
	local capacityClass = "low"
	if capacityRatio >= 0.85 then
		capacityClass = "high"
	elseif capacityRatio >= 0.6 then
		capacityClass = "mid"
	end
	local capacityColor = capacityClass == "high" and Theme.color.status.bad or capacityClass == "mid" and Theme.color.status.warn or Theme.color.brand.purple
	-- harborheist-rxz0: tween only on CHANGE — every 1Hz push was spawning
	-- a fresh tween pair on the same properties, orphaning the previous
	-- ones and restarting the easing so the bar never settled (same
	-- class-gate pattern as the lock button below).
	if capacityClass ~= lastCapacityClass or not lastCapacityRatio or math.abs(capacityRatio - lastCapacityRatio) >= 0.01 then
		lastCapacityClass = capacityClass
		lastCapacityRatio = capacityRatio
		TweenService:Create(capacityFill, EASE_OUT, { Size = UDim2.new(capacityRatio, 0, 1, 0), BackgroundColor3 = capacityColor }):Play()
		-- The gradient multiplies the fill color — retint it to match or the
		-- threshold colors read muddy (light top ~45% toward white, matching
		-- the original 196,181,253-over-purple relationship).
		TweenService:Create(capacityGradient, EASE_OUT, {
			Color = ColorSequence.new(capacityColor:Lerp(Color3.new(1, 1, 1), 0.45), capacityColor),
		}):Play()
	end

	local lines = {}
	for i, rarity in ipairs(GameConfig.Rarities) do
		local count = (state.liveWellCounts and state.liveWellCounts[rarity.name]) or 0
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
	-- R4 polish #15: color transitions tween instead of snapping on the 1Hz
	-- push. Only re-assert when the state CLASS changes — the countdown text
	-- updates every second and would restart the tween constantly.
	local lockClass, lockBg, lockFg
	if (state.lockedUntil or 0) > 0 then
		lockButton.Text = string.format("LOCKED %ds", math.ceil(state.lockedUntil))
		lockClass, lockBg, lockFg = "locked", Theme.color.status.bad, Theme.color.text.ink
	elseif (state.lockCooldownUntil or 0) > 0 then
		lockButton.Text = string.format("RECHARGE %ds", math.ceil(state.lockCooldownUntil))
		lockClass, lockBg, lockFg = "recharge", Theme.color.surface.elevated, Theme.color.text.secondary
	else
		local lockDur = GameConfig.Aquarium.lockDuration
		if state.lockLevel and state.lockLevel > 0 and GameConfig.Upgrades.Lock[state.lockLevel] then
			lockDur = GameConfig.Upgrades.Lock[state.lockLevel].lockDuration
		end
		local freeUses = state.lockFreeUsesRemaining or 0
		if freeUses > 0 then
			lockButton.Text = string.format("LOCK %ds — %d quick locks left", lockDur, freeUses)
		else
			lockButton.Text = string.format("LOCK %ds — slower recharge", lockDur)
		end
		lockClass, lockBg, lockFg = "ready", Theme.color.status.warn, Theme.color.text.ink
	end
	if lockClass ~= lastLockClass then
		lastLockClass = lockClass
		TweenService:Create(lockButton, EASE_FAST, { BackgroundColor3 = lockBg, TextColor3 = lockFg }):Play()
	end
	end -- R3 audit #20: end aquarium-panel-visible gate

	-- TASK 25.1 (hvfh.5.1): disarm the SELL ALL confirm if the payout
	-- changed since arming (new catch/store/sell/lock toggle) so the
	-- confirmed number is never stale.
	if sellArmed and computeSellPayout() ~= sellArmPayout then
		disarmSellButton()
	end

	-- TASK 8.2/8.3: Raid opt-in toggle button state (harborheist-bkn1: shared
	-- helper — single source for both toggle buttons).
	renderRaidOptInButton(raidOptInButton)

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
		claimButton.BackgroundColor3 = Theme.color.status.disabled
	elseif state.unclaimedIncome > 0 then
		claimButton.Text = string.format("CLAIM $%s", formatCash(state.unclaimedIncome))
		claimButton.BackgroundColor3 = Theme.color.status.claimReady
	else
		claimButton.Text = "CLAIM $0"
		claimButton.BackgroundColor3 = Theme.color.status.neutral
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
		-- harborheist-a2ug.4: a2ug.4's firstWait prompt may be the visible
		-- stage right now; the rescue below must not clobber it with the
		-- firstCast text on the next 1Hz push.
		if dismissedPrompts.firstCast then
			-- Already dismissed — hide prompt
		elseif casting then
			-- Player started casting: the cast guidance has served its
			-- purpose. harborheist-a2ug.4 fix: mark firstCast dismissed
			-- WITHOUT hiding the widget when a2ug.4's firstWait prompt owns
			-- it — the old unconditional dismissOnboardingPrompt("firstCast")
			-- killed the firstWait prompt within 1s of it appearing.
			dismissedPrompts.firstCast = true
			if currentPromptStage == "firstCast" then
				currentPromptStage = nil
				onboardingPrompt.Visible = false
			end
		elseif currentPromptStage ~= "firstWait" then
			showOnboardingPrompt("firstCast",
				IS_MOBILE and "Tap FISH while standing in the glowing zone!" or "Press F to cast into the glowing zone at your dock!",
				Theme.color.status.good)
		end
	elseif not ob.HasStoredFirstFish then
		-- Stage 2: caught a fish but hasn't stored it yet.
		if state.carried > 0 then
			-- Button renamed STORE → BAG by TASK 4.4 (0cw.4): G now opens the
			-- per-fish bag panel, where STORE / STORE ALL live.
			showOnboardingPrompt("firstStore",
				IS_MOBILE and "Tap BAG to store your fish for passive income!" or "Press G to open your bag and store your fish — they'll earn cash over time!",
				Theme.color.accent.base)
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
			Theme.color.status.claimReady)
	elseif not ob.HasSeenRaidExplanation and raidWindow.open then
		-- Stage 4: first raid window appeared and player hasn't seen the
		-- explanation. Dismissible — the player can ignore it and stay safe.
		showOnboardingPrompt("raidExplain",
			"Raids are optional! Open your tank panel to opt in and steal fish from other docks.",
			Theme.color.status.raidAlert)
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
-- TASK 23.2 (hvfh.3.2): Unified frame treatment with cast/raid overlays
-- ============================================================
local minigameFrame = Instance.new("Frame")
minigameFrame.Name = "BiteMinigame"
minigameFrame.AnchorPoint = Vector2.new(0.5, 0.5)
minigameFrame.Size = IS_MOBILE and UDim2.new(1, -24, 0, 132) or UDim2.new(0, 400, 0, 112)
minigameFrame.Position = UDim2.new(0.5, 0, IS_MOBILE and 0.42 or 0.58, 0)
minigameFrame.BackgroundColor3 = Theme.color.surface.primary
minigameFrame.BackgroundTransparency = 0.08
minigameFrame.Visible = false
minigameFrame.ZIndex = OVERLAY_Z_BASE
minigameFrame.Parent = screenGui
corner(minigameFrame, Theme.corners.lg)
stroke(minigameFrame, 0.8)
Gradients.apply(minigameFrame, "surface.default")

local minigameTitle = makeLabel(minigameFrame, {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.new(0, 10, 0, 10),
	Text = IS_MOBILE and "FISH ON! Tap when the marker is in the zone!" or "FISH ON! Click when the marker is in the zone!",
	Font = Theme.type.fonts.head,
	TextSize = IS_MOBILE and Theme.type.sizes.sm or Theme.type.sizes.md,
	TextColor3 = Theme.color.status.warn,
	ZIndex = OVERLAY_Z_CONTENT,
})

-- The bar track (unified sizing with cast/raid)
local barTrack = Instance.new("Frame")
barTrack.Size = UDim2.new(1, -24, 0, IS_MOBILE and 52 or 40)
barTrack.Position = UDim2.new(0, 12, 0, IS_MOBILE and 52 or 48)
barTrack.BackgroundColor3 = Theme.color.surface.secondary
barTrack.ZIndex = OVERLAY_Z_CONTENT
barTrack.Parent = minigameFrame
corner(barTrack, Theme.corners.roomy)
stroke(barTrack, 0.85)

-- The target zone (centered; width comes from the equipped rod's
-- minigameZoneSize — see runMinigame for the per-cast resize)
local targetZone = Instance.new("Frame")
targetZone.Size = UDim2.new(0.3, 0, 1, 0)
targetZone.Position = UDim2.new(0.35, 0, 0, 0)
targetZone.BackgroundColor3 = Theme.color.status.good
targetZone.BackgroundTransparency = 0.45
targetZone.ZIndex = OVERLAY_Z_ZONE
targetZone.Parent = barTrack
corner(targetZone, Theme.corners.sm)
stroke(targetZone, 0.5, Theme.color.status.good, 1.5)

-- The moving marker (bite minigame)
-- Renamed from 'marker' to 'biteMarker' to avoid shadowing the cast overlay marker.
local biteMarker = Instance.new("Frame")
biteMarker.Size = UDim2.new(0, 5, 1, 6)
biteMarker.Position = UDim2.new(0, 0, 0, -3)
biteMarker.BackgroundColor3 = Color3.new(1, 1, 1)
biteMarker.ZIndex = OVERLAY_Z_MARKER
biteMarker.Parent = barTrack
corner(biteMarker, Theme.corners.thin)

local biteMarkerGlow = Instance.new("Frame")
biteMarkerGlow.Size = UDim2.new(0, 15, 1, 10)
biteMarkerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
biteMarkerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
biteMarkerGlow.BackgroundColor3 = Theme.color.accent.soft
biteMarkerGlow.BackgroundTransparency = 0.75
biteMarkerGlow.ZIndex = OVERLAY_Z_ZONE
biteMarkerGlow.Parent = biteMarker
corner(biteMarkerGlow, Theme.corners.sm)

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
		showNotification("Fishing sync hiccup — try casting again.", Theme.color.status.warn)
		return
	end
	-- TASK 23.1 (hvfh.3.1): take the overlay slot. The BiteEvent handler
	-- already gates on an active raid (rule 3); this is the defensive
	-- backstop for any other occupied-slot path. Bail BEFORE mutating any
	-- state so fishState/minigameActive can never wedge.
	if not requestOverlay("bite") then
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
				releaseOverlay("bite")
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
			biteMarker.Position = UDim2.new(pos, -2, 0, -2)
			task.wait()
		end
	end)
end

-- ============================================================
-- TASK 22.4 (hvfh.2.4): Catch reveal card
-- Centered card on catch success for Rare/Epic/Legendary (and every
-- first-session catch). Display-only — does NOT take the overlay slot.
-- If a minigame overlay is active, offsets to 0.30 vertical to avoid
-- overlap with the centered minigame. Built from the structured
-- SubmitCatchInput invoke result, not the server notify string.
-- Auto-dismiss ~2.5s; tap-to-dismiss; EASE_POP scale-in.
-- ============================================================
local revealCard = nil
local revealDismissToken = 0
-- R4 polish #9: the Epic/Legendary stroke-breath tween, cancelled on
-- dismiss/replacement so it never writes to a destroyed UIStroke.
local revealStrokePulse = nil

local function showRevealCard(speciesId, rarity, value)
	if revealCard then
		revealCard:Destroy()
		revealCard = nil
	end
	local token = revealDismissToken + 1
	revealDismissToken = token

	local rarityColor = RARITY_COLORS[rarity] or Theme.color.text.secondary

	-- Look up display name + income from FishDefinitions (structured data,
	-- not string parsing per the bead spec)
	local displayName = speciesId or "Fish"
	local incomePerMin = 0
	local ok, def = pcall(FishDefinitions.get, speciesId)
	if ok and def then
		displayName = def.DisplayName or displayName
		incomePerMin = def.IncomePerMinute or 0
	end

	-- Offset up if a minigame holds the overlay slot; center otherwise.
	local slotOccupied = isOverlayActive("cast") or isOverlayActive("bite") or isOverlayActive("raid")
	local yScale = slotOccupied and 0.30 or 0.5

	local card = Instance.new("Frame")
	card.Name = "RevealCard"
	if IS_MOBILE then
		card.Size = UDim2.new(1, -24, 0, 160)
		card.Position = UDim2.new(0, 12, yScale, -80)
	else
		card.Size = UDim2.new(0, 280, 0, 160)
		card.Position = UDim2.new(0.5, -140, yScale, -80)
	end
	card.BackgroundColor3 = Theme.color.surface.primary
	card.ZIndex = 50
	card.Active = true
	card.Parent = screenGui
	corner(card, Theme.corners.lg)
	local cardStroke = stroke(card, 0.4, rarityColor, 2)
	-- harborheist-s0yp: unified surface treatment — every other surface
	-- (HUD, panels, overlays) carries the vertical gradient; the reveal
	-- moment was the one flat card in the game.
	Gradients.apply(card, "surface.default")

	-- R4 polish #9: rarity-graded celebration — the peak moment of the game
	-- should feel different per tier. Rare: the standard pop. Epic: adds a
	-- breathing rarity-stroke pulse. Legendary: slower/bigger entrance plus
	-- a full-screen rarity flash behind the card.
	local isEpicPlus = rarity == "Epic" or rarity == "Legendary"
	local isLegendary = rarity == "Legendary"

	-- Scale-in (EASE_POP per bead spec; Legendary gets the grander 0.35 start)
	local cardScale = Instance.new("UIScale")
	cardScale.Scale = isLegendary and 0.35 or 0.5
	cardScale.Parent = card
	-- harborheist-2wuo.1: Legendary reveal also uses Spring (was Back) for
	-- physics-based overshoot — the most dramatic catch gets the bounciest pop.
	-- selene: allow(incorrect_standard_library_use) — Spring is valid (see EASE_POP note).
	TweenService:Create(cardScale, isLegendary and TweenInfo.new(0.5, Enum.EasingStyle.Spring, Enum.EasingDirection.Out) or EASE_POP, { Scale = 1 }):Play()

	-- Epic+: stroke breathes while the card is up. Stored so dismiss() and
	-- the next card can cancel it (a tween on a destroyed stroke errors).
	if revealStrokePulse then
		revealStrokePulse:Cancel()
		revealStrokePulse = nil
	end
	if isEpicPlus then
		hapticTick() -- R4 polish #2: the catch deserves a physical tick
		revealStrokePulse = TweenService:Create(
			cardStroke,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.05 }
		)
		revealStrokePulse:Play()
	end

	-- Legendary: full-screen rarity flash (fast in, slow out, then gone).
	if isLegendary then
		local flash = Instance.new("Frame")
		flash.Size = UDim2.new(1, 0, 1, 0)
		flash.BackgroundColor3 = rarityColor
		flash.BackgroundTransparency = 1
		flash.ZIndex = 49
		flash.Parent = screenGui
		TweenService:Create(flash, EASE_FAST, { BackgroundTransparency = 0.82 }):Play()
		task.delay(0.14, function()
			if flash.Parent then
				TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			end
		end)
		task.delay(0.65, function()
			if flash.Parent then
				flash:Destroy()
			end
		end)
	end

	-- Rarity top bar
	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 6)
	topBar.BackgroundColor3 = rarityColor
	topBar.ZIndex = 51
	topBar.Parent = card
	corner(topBar, Theme.corners.snug)

	-- Rarity tag
	local tag = Instance.new("Frame")
	tag.Size = UDim2.new(0, 100, 0, 22)
	tag.Position = UDim2.new(0.5, -50, 0, 20)
	tag.BackgroundColor3 = rarityColor
	tag.BackgroundTransparency = 0.78
	tag.ZIndex = 51
	tag.Parent = card
	corner(tag, Theme.corners.compact)
	makeLabel(tag, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = string.upper(rarity or "?"),
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = rarityColor,
		ZIndex = 52,
	})

	-- harborheist-s0yp: rarity-tinted fish silhouette beside the species
	-- name — the collection book's visual, earned at the reveal moment.
	local icon = Instance.new("Frame")
	icon.Size = UDim2.new(0, 48, 0, 48)
	icon.Position = UDim2.new(0, 18, 0, 52)
	icon.BackgroundColor3 = Theme.color.surface.elevated
	icon.ZIndex = 51
	icon.Parent = card
	corner(icon, Theme.corners.pill)
	buildFishSilhouette(icon, rarityColor)

	-- Species display name (big, right of the icon)
	makeLabel(card, {
		Size = UDim2.new(1, -92, 0, 30),
		Position = UDim2.new(0, 76, 0, 54),
		Text = displayName,
		Font = Theme.type.fonts.head,
		TextSize = Theme.type.sizes.lg,
		TextColor3 = Theme.color.text.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 51,
	})

	-- Sell value + income/min line (harborheist-gw38: formatCash separators)
	makeLabel(card, {
		Size = UDim2.new(1, -92, 0, 20),
		Position = UDim2.new(0, 76, 0, 92),
		Text = string.format("$%s  •  $%.1f/min", formatCash(value or 0), incomePerMin),
		Font = Theme.type.fonts.body,
		TextSize = Theme.type.sizes.sm,
		TextColor3 = Theme.color.text.secondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 51,
	})

	-- "tap to dismiss" hint (R4 #9c: platform-correct copy)
	makeLabel(card, {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 130),
		Text = IS_MOBILE and "tap to dismiss" or "click to dismiss",
		Font = Theme.type.fonts.body,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.text.tertiary,
		ZIndex = 51,
	})

	revealCard = card

	-- Token-guarded dismiss: prevents a stale auto-dismiss timer from
	-- clobbering a newer card (e.g. two Rare catches in quick succession).
	local function dismiss()
		if token ~= revealDismissToken then
			return
		end
		revealDismissToken = revealDismissToken + 1
		if revealCard == card then
			if revealStrokePulse then
				revealStrokePulse:Cancel()
				revealStrokePulse = nil
			end
			TweenService:Create(cardScale, EASE_FAST, { Scale = 0.5 }):Play()
			-- R4 polish #9b: fade alongside the shrink — the old shrink-only
			-- dismiss hard-popped at Destroy.
			TweenService:Create(card, EASE_FAST, { BackgroundTransparency = 1 }):Play()
			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("GuiObject") then
					TweenService:Create(d, EASE_FAST, { BackgroundTransparency = 1 }):Play()
					if d:IsA("TextLabel") or d:IsA("TextButton") then
						TweenService:Create(d, EASE_FAST, { TextTransparency = 1 }):Play()
					end
				elseif d:IsA("UIStroke") then
					TweenService:Create(d, EASE_FAST, { Transparency = 1 }):Play()
				end
			end
			task.delay(0.15, function()
				if revealCard == card then
					card:Destroy()
					revealCard = nil
				end
			end)
		end
	end

	-- Tap-to-dismiss: frame InputBegan fires for Mouse/Touch on the card.
	-- card.Active = true means taps ON the card set gameProcessed=true in
	-- UserInputService.InputBegan, so the overlay router skips them — a
	-- tap to dismiss the card never also triggers a minigame action.
	card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dismiss()
		end
	end)

	-- Auto-dismiss after ~2.5s
	task.delay(2.5, function()
		dismiss()
	end)
end

-- Player taps/ clicks to stop the marker
local function onMinigameTap()
	if not minigameActive then return end
	local elapsed = os.clock() - minigameStartTime
	local markerPos = biteMarker.Position.X.Scale
	-- ROUND-3 FIX: validate against the per-rod zone (minigameZoneHalfWidth
	-- was set by runMinigame from RodDefinitions), not the legacy hardcoded
	-- [0.35, 0.65] band. The server is still authoritative (it re-rolls
	-- against the rod's zone size in SubmitCatchInput); this just aligns
	-- the client's pre-validation with the visual the player saw.
	local halfWidth = minigameZoneHalfWidth or 0.15
	local hit = markerPos >= (0.5 - halfWidth) and markerPos <= (0.5 + halfWidth)
	minigameActive = false
	releaseOverlay("bite")
	minigameFrame.Visible = false
	setFishState("idle")
	local result = Remotes.SubmitCatchInput:InvokeServer({ hit = hit, elapsed = elapsed, markerPos = markerPos })
	-- TASK 14.16: the server re-rolls claimed hits against the rod's zone size,
	-- so an on-zone tap can still be rejected — surface that honestly.
	if hit and result and result.ok == false and result.reason == "missed" then
		showNotification("So close! The fish shook off the hook...", Theme.color.status.warn)
	end
	-- TASK 22.4 (hvfh.2.4): reveal card on catch success for Rare+ and
	-- first-session catches. Built from the structured invoke result, not
	-- the server notify string. Card is display-only (no overlay slot).
	if result and result.ok == true then
		catchesThisSession += 1
		local rarity = result.rarity or "Common"
		-- harborheist-6qyq: every catch splashes; rarity layers a sting on
		-- top (ping -> flashbulb -> thunder) so the tiers ASCEND audibly.
		playSound(SOUNDS.catchSplash, 0.55)
		if rarity == "Rare" then
			playSound(SOUNDS.catchRare, 0.6, 1.3)
		elseif rarity == "Epic" then
			playSound(SOUNDS.catchEpic, 0.65)
		elseif rarity == "Legendary" then
			playSound(SOUNDS.catchLegendary, 0.8)
		end
		if catchesThisSession == 1
			or rarity == "Rare" or rarity == "Epic" or rarity == "Legendary" then
			showRevealCard(result.speciesId, rarity, result.value)
		end
	end
end

-- TASK 23.1 (hvfh.3.1): both former bite-input listeners (the GuiObject
-- minigameFrame.InputBegan and the tap-anywhere UserInputService one) are
-- replaced by this single registration with the overlay router. Behavior
-- is preserved exactly: minigameFrame is not Active, so taps over it never
-- set gameProcessed and reach this handler just like the old
-- tap-anywhere listener; taps on real buttons still set gameProcessed and
-- are skipped (no accidental catch submits while opening a panel).
overlayInputHandlers.bite = function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not minigameActive then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		onMinigameTap()
	end
end

-- ============================================================
-- Actions
-- ============================================================
-- TASK 22.2 (hvfh.2.2): cast-while-casting feedback. During the 6-10s bite
-- wait a repeat F-press used to die silently on the `casting` guard and the
-- button read as broken; now it gets a short shake. Rotation, not Position —
-- the desktop bar's UIListLayout owns button Position and would fight the
-- tween; Rotation is layout-free on both mobile + desktop branches. Steps
-- are ~3 frames (0.05s) with decaying amplitude, always settling back to 0.
-- Token guard: spam-pressing restarts the shake instead of stacking tweens.
local fishShakeToken = 0
local function shakeFishButton()
	local btn = actionButtons.fish
	if not btn then
		return
	end
	fishShakeToken += 1
	local token = fishShakeToken
	task.spawn(function()
		local step = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		for _, angle in ipairs({ -3, 3, -2, 0 }) do
			if token ~= fishShakeToken then
				return
			end
			local tween = TweenService:Create(btn, step, { Rotation = angle })
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

local function doFish()
	-- TASK 23.1 (hvfh.3.1) gate 1: never start a cast while the raid
	-- minigame holds the overlay slot. Refused BEFORE RequestCast fires —
	-- nothing is committed server-side, zero server calls.
	if isOverlayActive("raid") then
		showNotification("Finish the raid first!", Theme.color.status.warn)
		return
	end
	-- harborheist-egvu: mid-bite F-presses must not fire a second RequestCast
	-- (server backstop rejects them; shake = 'you are busy, tap the bar!').
	if isOverlayActive("bite") then
		shakeFishButton()
		return
	end
	if casting then
		-- TASK 22.2 (hvfh.2.2): visible "still waiting" feedback, not a dead button.
		shakeFishButton()
	else
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

-- harborheist-2wuo.3: Wire gesture animations to panels and lists
-- Swipe-to-dismiss on all panels (horizontal swipe to close)
if Anim and type(Anim.swipeDismiss) == "function" then
	pcall(function()
		Anim:swipeDismiss(aquariumPanel, hidePanels)
		Anim:swipeDismiss(inventoryPanel, hidePanels)
		Anim:swipeDismiss(shopPanel, hidePanels)
		Anim:swipeDismiss(questPanel, hidePanels)
		Anim:swipeDismiss(raidPanel, hidePanels)
		Anim:swipeDismiss(collectionPanel, hidePanels)
	end)
end

-- Pull-to-refresh on scrollable lists
if Anim and type(Anim.pullToRefresh) == "function" then
	pcall(function()
		-- Inventory list: refresh by re-rendering
		Anim:pullToRefresh(inventoryList, function()
			renderInventory()
		end)
		
		-- Collection list: refresh by re-fetching data
		Anim:pullToRefresh(collectionList, function()
			renderCollection()
		end)
		
		-- Quest list: re-render with cached data; server pushes updates via QuestProgressChanged
		Anim:pullToRefresh(questList, function()
			if questData then
				renderQuestPanel(questData)
			end
		end)
	end)
end

-- TASK 4.4 (0cw.4 / wqw.18): BAG button opens the per-fish inventory panel
-- (bulk store-all remains available via the panel's STORE ALL button).
actionButtons.store.Activated:Connect(toggleInventoryPanel)
-- TASK 7.3 (it3.3): BOOK button opens the collection book panel.
actionButtons.collection.Activated:Connect(toggleCollectionPanel)
-- TASK 8.12 (gdj.12): RAID button opens the raid panel.
actionButtons.raid.Activated:Connect(toggleRaidPanel)
-- TASK 8.12 (gdj.12): refresh + opt-in inside the raid panel.
-- R3 audit #21: debounce refresh so rapid taps can't stack invokes (server
-- rate-limits the loser, which the user never sees — it just "eats" the tap).
local lastRaidRefreshAt = 0
raidRefreshButton.Activated:Connect(function()
	local now = os.clock()
	if now - lastRaidRefreshAt < 1.5 then
		return
	end
	lastRaidRefreshAt = now
	refreshRaidPanel()
end)
-- R3 audit #19: optimistic disable until the next 1Hz state push confirms the
-- new opt-in state — a double-tap inside that window sent two toggles and
-- landed the player in the OPPOSITE state from what the button showed.
raidOptInPanelButton.Activated:Connect(function()
	if not raidOptInPanelButton.Active then
		return
	end
	dismissOnboardingPrompt("raidExplain")
	raidOptInPanelButton.Active = false
	task.delay(1.5, function()
		raidOptInPanelButton.Active = true
	end)
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
	sellButton.BackgroundColor3 = Theme.color.status.good
	sellButton.TextColor3 = Theme.color.text.ink
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
				showNotification("Aquarium is locked — stored fish can't be sold until the lock expires.", Theme.color.status.alert)
				else
				showNotification("No fish to sell!", Theme.color.status.alert)
			end
			return
		end
		sellArmed = true
		sellArmPayout = payout
		local locked = (state.lockedUntil or 0) > 0
		if locked then
			sellButton.Text = string.format("SELL BAG $%s? TAP", formatCash(payout))
		else
			sellButton.Text = string.format("SELL ALL $%s? TAP", formatCash(payout))
		end
		sellButton.BackgroundColor3 = Theme.color.status.bad
		sellButton.TextColor3 = Theme.color.text.ink
		sellArmTask = task.delay(3, function()
			disarmSellButton()
		end)
	end
end)
local lockHintShown = false
lockButton.Activated:Connect(function()
	if not lockHintShown then
		lockHintShown = true
		showNotification("Locks always work; your first 3 each session recharge faster.", Theme.color.accent.soft, "lock")
	end
	Remotes.RequestActivateLock:InvokeServer()
end)
-- TASK 8.2/8.3: raid opt-in toggle (server validates new-player gate)
-- TASK 9.2 (0jc.2): dismiss the raid explanation onboarding prompt when the
-- player interacts with the opt-in button — they've now "seen" the explanation.
raidOptInButton.Activated:Connect(function()
	-- R3 audit #19 (fresh-eyes: the raid PANEL's toggle got this guard in the
	-- first pass but the aquarium twin was missed — same double-tap hazard).
	if not raidOptInButton.Active then
		return
	end
	dismissOnboardingPrompt("raidExplain")
	raidOptInButton.Active = false
	task.delay(1.5, function()
		raidOptInButton.Active = true
	end)
	Remotes.RequestToggleRaidOptIn:InvokeServer()
end)
-- TASK 5.1/14.1: claim accumulated aquarium income (was created but never wired)
claimButton.Activated:Connect(function()
	local result = Remotes.RequestClaimIncome:InvokeServer()
	-- harborheist-6qyq: cha-ching only when income actually landed.
	if result and result.ok and (result.amount or 0) > 0 then
		playSound(SOUNDS.claimCoins, 0.6)
	end
end)

local function toggleQuestPanel()
	if overlayBlocksPanels() then
		return
	end
	if activePanel == questPanel then
		hidePanels()
		return
	end
	showPanel(questPanel)
	-- harborheist-p8v7: ALWAYS ask the server for fresh quests on open
	-- (fire-and-forget; QuestProgressChanged re-renders the panel). Cached
	-- data renders immediately as a placeholder — previously a reopen after
	-- daily rotation showed yesterday's quests until the next server push.
	if questData then
		renderQuestPanel(questData)
	else
		-- harborheist-7h69.4: skeleton rows on cold open (questData nil)
		-- while waiting for the server's QuestProgressChanged push. Self-
		-- terminates when renderQuestPanel destroys the bars on data arrival.
		-- Clear first: a reopen before the server responds (questData still
		-- nil) would otherwise stack duplicate skeleton bars on top of the
		-- previous set — matching showCollectionSkeleton's clearCollectionList
		-- guard pattern.
		for _, child in ipairs(questList:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		createSkeletonRows(questList, {
			rows = 4,
			rowHeight = IS_MOBILE and 72 or 64,
			zIndex = 26,
		})
	end
	Remotes.OpenQuests:FireServer()
end

actionButtons.quests.Activated:Connect(toggleQuestPanel)

local lastBoatSpawnAt = 0
local function trySpawnBoat()
	-- R3 audit #16/#21: no overlay gate or debounce — spamming B / tapping the
	-- boat button fired an InvokeServer per tap and toasted each rejection.
	if activeOverlay then
		return
	end
	local now = os.clock()
	if now - lastBoatSpawnAt < 1 then
		return
	end
	lastBoatSpawnAt = now
	-- harborheist-03mo: boat already out (the state dot says so) — treat the
	-- tap as a query, not a command: friendly info toast, zero server calls.
	-- A stale snapshot self-corrects on the next 1Hz push; a stale-false
	-- read just falls through to the server's own already_has_boat rejection.
	if state and state.hasBoat then
		showNotification("Your boat is out — find it at your dock!", Theme.color.brand.boat)
		return
	end
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
		showNotification(reasons[result.reason] or "Could not spawn boat.", Theme.color.status.bad)
	end
end

actionButtons.boat.Activated:Connect(trySpawnBoat)

-- harborheist-i74e (EPIC 40): keyboard-shortcut help panel + completion
-- of the action shortcuts. The core F/G/C/T/Q/R/B/Escape handlers below
-- already existed; this adds S (shop), Space (cast), I (inventory alias),
-- H (toggle this help panel), and the discoverable help panel itself so
-- all shortcuts are documented in-game (acceptance: "Help panel shows all
-- shortcuts").
local helpPanel, helpContent, helpClose = makePanel("SHORTCUTS", Theme.color.accent.base, UDim2.new(0, 360, 0, 480))

makeLabel(helpContent, {
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.new(0, 0, 0, 0),
	Text = IS_MOBILE and "Tap an action button:" or "Press a key or click an action:",
	Font = Theme.type.fonts.med,
	TextSize = Theme.type.sizes.xs,
	TextColor3 = Theme.color.text.tertiary,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 26,
})

local helpList = Instance.new("ScrollingFrame")
helpList.Name = "ShortcutList"
helpList.Size = UDim2.new(1, 0, 1, -26)
helpList.Position = UDim2.new(0, 0, 0, 26)
helpList.BackgroundTransparency = 1
helpList.BorderSizePixel = 0
helpList.ScrollBarThickness = 4
helpList.ScrollBarImageColor3 = Theme.color.text.tertiary
helpList.CanvasSize = UDim2.new(0, 0, 0, 0)
helpList.AutomaticCanvasSize = Enum.AutomaticSize.Y
helpList.ZIndex = 26
helpList.Parent = helpContent

local helpListLayout = Instance.new("UIListLayout")
helpListLayout.FillDirection = Enum.FillDirection.Vertical
helpListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
helpListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
helpListLayout.Padding = UDim.new(0, 6)
helpListLayout.SortOrder = Enum.SortOrder.LayoutOrder
helpListLayout.Parent = helpList

local SHORTCUT_ROWS = {
	{ key = "F",     desc = "Cast / Start Fishing" },
	{ key = "Space", desc = "Cast (when no panel is open)" },
	{ key = "G",     desc = "Fish Bag (carried fish)" },
	{ key = "I",     desc = "Fish Bag (alias of G)" },
	{ key = "C",     desc = "Collection Book" },
	{ key = "T",     desc = "My Aquarium (Tank)" },
	{ key = "S",     desc = "Bait & Tackle (Shop)" },
	{ key = "Q",     desc = "Quests" },
	{ key = "R",     desc = "Raid Waters" },
	{ key = "B",     desc = "Spawn Boat" },
	{ key = "Tab",   desc = "Navigate buttons (Shift+Tab reverses)" },
	{ key = "Enter", desc = "Activate the focused button" },
	{ key = "Esc",   desc = "Close panel / dismiss prompt" },
	{ key = "H",     desc = "Toggle this shortcuts panel" },
}

for idx, row in ipairs(SHORTCUT_ROWS) do
	local rowFrame = Instance.new("Frame")
	rowFrame.Size = UDim2.new(1, 0, 0, 30)
	rowFrame.BackgroundTransparency = 1
	rowFrame.LayoutOrder = idx
	rowFrame.ZIndex = 26
	rowFrame.Parent = helpList

	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0, 46, 0, 24)
	chip.Position = UDim2.new(0, 0, 0.5, 0)
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.BackgroundColor3 = Theme.color.surface.elevated
	chip.ZIndex = 27
	chip.Parent = rowFrame
	corner(chip, Theme.corners.compact)
	stroke(chip, 0.85)

	makeLabel(chip, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = row.key,
		Font = Theme.type.fonts.bold,
		TextSize = Theme.type.sizes.xs,
		TextColor3 = Theme.color.text.secondary,
		ZIndex = 28,
	})

	makeLabel(rowFrame, {
		Size = UDim2.new(1, -56, 1, 0),
		Position = UDim2.new(0, 56, 0, 0),
		Text = row.desc,
		Font = Theme.type.fonts.med,
		TextSize = Theme.type.sizes.sm,
		TextColor3 = Theme.color.text.primary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 27,
	})
end

helpClose.Activated:Connect(hidePanels)
if not IS_MOBILE then
	KeyboardNav:Register(helpClose, 100)
end

local function toggleHelpPanel()
	if overlayBlocksPanels() then
		return
	end
	if activePanel == helpPanel then
		hidePanels()
		return
	end
	showPanel(helpPanel)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		doFish()
	elseif input.KeyCode == Enum.KeyCode.Space then
		-- harborheist-i74e: Space casts when no panel is open. When a panel
		-- is open, Space activates the focused button via KeyboardNav, so we
		-- defer to that to avoid a double-action.
		if not activePanel then
			doFish()
		end
	elseif input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.I then
		toggleInventoryPanel()
	elseif input.KeyCode == Enum.KeyCode.C then
		toggleCollectionPanel()
	elseif input.KeyCode == Enum.KeyCode.T then
		if not overlayBlocksPanels() then
			showPanel(aquariumPanel)
			render() -- R3 audit #20: aquarium block is push-gated; render on open
		end
	elseif input.KeyCode == Enum.KeyCode.S then
		-- harborheist-i74e: open the Bait & Tackle shop panel.
		if not overlayBlocksPanels() then
			showPanel(shopPanel)
			refreshShop()
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		toggleQuestPanel()
	elseif input.KeyCode == Enum.KeyCode.R then
		toggleRaidPanel()
	elseif input.KeyCode == Enum.KeyCode.B then
		trySpawnBoat()
	elseif input.KeyCode == Enum.KeyCode.H then
		-- harborheist-i74e: toggle the keyboard-shortcut help panel.
		toggleHelpPanel()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		-- R3 audit #17: Escape dismissed panels only — the onboarding prompt
		-- and sell/store comparison prompt had no keyboard path out.
		if activePanel then
			hidePanels()
		elseif sellStorePrompt.Visible then
			hideSellStorePrompt()
			markSellStoreComparisonSeen()
		elseif onboardingPrompt.Visible and currentPromptStage then
			dismissOnboardingPrompt(currentPromptStage)
		end
	end
end)

-- ============================================================
-- Remote listeners
-- ============================================================
Remotes.StateChanged.OnClientEvent:Connect(function(snapshot)
	if not snapshot or type(snapshot) ~= "table" then
		warn("[Client] Invalid state snapshot received")
		return
	end
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
-- NOTE (harborheist-akdb): formatRaidTime moved up next to formatCash — the
-- declaration must precede renderRaidTargets (its earliest caller).
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
		playSound(SOUNDS.raidOpen, 0.65) -- harborheist-6qyq: window-open stinger
		-- R3 audit #18: floor() printed '0 minutes' for sub-minute windows.
		showNotification(
			string.format("RAID WATERS OPEN for %s! Steal fish from other docks while the window lasts.", formatRaidTime(raidWindow.remainingSeconds)),
			Theme.color.status.raidAlert
		)
	elseif not raidWindow.open and wasOpen then
		playSound(SOUNDS.raidClose, 0.55) -- harborheist-6qyq: window-close settle
		showNotification("Raid waters closed. The harbor is safe... for now.", Theme.color.accent.soft)
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
		
		-- Update unavailable target countdowns (hvfh.6.1.2)
		for userId, data in pairs(raidTargetCountdownLabels) do
			if data.seconds > 0 then
				data.seconds = data.seconds - 1
				if data.seconds > 0 then
					data.label.Text = string.format("%s  •  %s", data.reasonLabel, formatRaidTime(data.seconds))
				else
					data.label.Text = data.reasonLabel
				end
			end
		end
	end
end)

Remotes.CastState.OnClientEvent:Connect(function(isCasting, castTime, hitZone)
	casting = isCasting
	if isCasting then
		-- harborheist-a2ug.4 fix: route through setFishState (was a raw
		-- assignment that silently bypassed the waiting-dots loop and the
		-- firstWait prompt hook — both only fire inside setFishState).
		setFishState("waiting")
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

		local duration = castTime or 4
		-- TASK 23.1 (hvfh.3.1): take the single overlay slot. If a raid
		-- minigame started in the sub-second between RequestCast and this
		-- CastState, the request fails and the cast overlay simply never
		-- opens; the cast resolves server-side with no CastResult input
		-- (same accepted-race philosophy as rule 3, see BiteEvent handler).
		if requestOverlay("cast") then
			castAwaitingInput = true -- harborheist-njqm: overlay open, watching for a tap
			playSound(SOUNDS.castLaunch, 0.5) -- harborheist-6qyq: sling-shot cast
			castOverlayDuration = duration
			castOverlay.Visible = true
			marker.Position = UDim2.new(0, 0, 0, -3)

			local overlayScale = castOverlay:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			overlayScale.Parent = castOverlay
			overlayScale.Scale = 0.9
			TweenService:Create(overlayScale, EASE_POP, { Scale = 1 }):Play()

			castDeadline = os.clock() + duration

			markTween = TweenService:Create(
				marker,
				TweenInfo.new(duration, Enum.EasingStyle.Linear),
				{ Position = UDim2.new(1, -5, 0, -3) }
			)
			markTween:Play()
		end
	else
		-- harborheist-njqm: a CastState(false) arriving while the overlay
		-- still awaited input means the cast timed out with ZERO taps — the
		-- server assigned luckBonus 0 with no player-facing explanation.
		-- Coach once per session so the miss teaches the mechanic.
		if castAwaitingInput then
			castAwaitingInput = false
			if not coachShownIdleCast then
				coachShownIdleCast = true
				showNotification("No timing bonus — tap the bar next cast!", Theme.color.status.warn)
			end
		end
		-- CastState(false) with no bite: the cast resolved/cancelled. Only
		-- clear the waiting state — never bite-ready (a BiteEvent may be
		-- arriving in this same deferred callback right after this; clearing
		-- bite-ready here would lose the bite). render() below re-renders.
		-- harborheist-a2ug.4 fix: setFishState, not a raw assignment — the
		-- raw write left the dots loop running and the firstWait prompt up.
		if fishState == "waiting" then
			setFishState("idle")
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
	-- TASK 23.1 (hvfh.3.1) rule 3: a BiteEvent landing mid-raid-minigame
	-- is the one unavoidable race (a cast was legally in flight when a
	-- LEGAL raid started — both initiations passed their gates). Do NOT
	-- open the bite overlay on top of the raid overlay; let the bite
	-- expire server-side. The server sends its own "Too slow! The fish
	-- got away..." timeout toast (FishingService.lua), which already
	-- explains the cost: the player chose to raid with a line in the
	-- water. (Implementer choice recorded in the bead: no toast
	-- suppression/replacement — the server message is the explanation.)
	if isOverlayActive("raid") then
		return
	end
	playSound(SOUNDS.biteAlert, 0.65) -- harborheist-6qyq: FISH ON! ping
	runMinigame(windowSeconds)
end)

Remotes.OpenAquarium.OnClientEvent:Connect(function()
	-- harborheist-egvu: server-pushed opens get the same overlay gate as
	-- every other panel opener — the dock prompt is tappable mid-minigame,
	-- and a panel opening under the overlay eats the timing bar's taps.
	if not overlayBlocksPanels() then
		showPanel(aquariumPanel)
		render() -- R3 audit #20: aquarium block is push-gated; render on open
	end
end)

-- TASK 24.1 (hvfh.4.1): clicking/tapping the HUD cash card opens the
-- aquarium panel (same toggle semantics as every other panel opener).
hudClick.Activated:Connect(function()
	if not overlayBlocksPanels() then
		showPanel(aquariumPanel)
		render() -- R3 audit #20: aquarium block is push-gated; render on open
	end
end)

Remotes.OpenShop.OnClientEvent:Connect(function()
	-- harborheist-egvu: same overlay gate as OpenAquarium — the shop
	-- counter prompt is tappable mid-minigame.
	if not overlayBlocksPanels() then
		showPanel(shopPanel)
		refreshShop()
	end
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
task.delay(5, function()
	if not state or not (state.onboarding or {}).HasCaughtFirstFish then
		showNotification(IS_MOBILE and "Welcome! Tap FISH in the glowing zone to catch your first fish." or "Welcome! Press F in the glowing zone to catch your first fish.", Theme.color.status.good)
	end
end)

-- ============================================================
-- TASK 23.1 (hvfh.3.1): the ONE UserInputService.InputBegan router.
-- Lives at the BOTTOM of the file, after every overlayInputHandlers.<name>
-- assignment (cast at stopCastOverlay, raid in startRaidMinigame, bite in
-- the bite-minigame section), because Lua locals are lexically scoped and
-- those handlers don't exist until their sections run. Every event checks
-- the CURRENT activeOverlay, so a later registration is picked up even if
-- an overlay opened before its handler section executed. Exactly one
-- connection serves all timed overlays; the four former per-overlay
-- listeners (cast, raid, bite GuiObject, bite tap-anywhere) are gone.
-- (harborheist-au38) withLoading removed: complete but unused function.

-- harborheist-keza: removed dead toast history code (addToHistory,
-- getHistory, clearHistory, toastHistory table, setmetatable). The write
-- path (addToHistory) was called from showNotification but getHistory and
-- clearHistory had zero call sites — the feature was half-shipped
-- (harborheist-6388.4 storage half; UI consumer never built). Bounded at
-- 50 entries so no leak, but dead code adds confusion and maintenance cost.


-- harborheist-3xlw: restore the TASK 23.1 (hvfh.3.1) overlay input router.
-- This connection is the ONLY dispatcher for the three timed minigame
-- overlays — without it overlayInputHandlers.cast/.bite/.raid are
-- registered but never invoked and the minigames cannot receive clicks.
-- It was silently overwritten at HEAD by 6f1a0c8's toast-history append.
-- Lives at the BOTTOM of the file, after every overlayInputHandlers.<name>
-- assignment (lexical scope: handlers don't exist until their sections run;
-- every event re-reads the CURRENT activeOverlay so late registration is
-- picked up even if an overlay opened before its handler section executed).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	local handler = activeOverlay and overlayInputHandlers[activeOverlay] or nil
	if handler then
		handler(input, gameProcessed)
	end
end)