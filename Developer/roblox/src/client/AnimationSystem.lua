--[[
=============================================================================
EPIC 34: Animation & Motion Design — Micro-interactions, Transitions, Physics
=============================================================================

BACKGROUND:
The current animation system uses basic tweens with easing curves. This lacks
the polish of premium apps. We need spring physics for interactive elements,
micro-interactions for user feedback, and gesture-based animations for mobile.

IMPLEMENTATION PLAN:
1. Spring physics system — natural overshoot for "pop" feel
2. Micro-interactions — button press, toggle, success/error states
3. Gesture animations — swipe to dismiss, pull-to-refresh
4. Transition library — fade, slide, scale, rotate presets

DEPENDENCIES:
- Theme tokens (harborheist-uabg) for consistent timing/spacing
- UserInputService for gesture detection
- TweenService for all animations

SUCCESS CRITERIA:
- Spring physics system implemented and documented
- 10+ micro-interactions added
- Gesture-based animations work on mobile
- All transitions use consistent timing/easing
--]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- harborheist-kqbq: source success/error colors from the canonical palette
-- instead of hardcoded RGBs (were 52,199,123 and 255,92,92 — duplicates of
-- UIPalette.good/bad that would drift if the palette changed).
local UIPalette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIPalette"))

local AnimationSystem = {}
AnimationSystem.__index = AnimationSystem

--[[
=============================================================================
Spring Physics System
=============================================================================

Spring physics provides natural motion with overshoot and settling. Unlike
easing curves which are synthetic, springs feel organic and responsive.

Key parameters:
- stiffness: How quickly the spring wants to return to rest (higher = snappier)
- damping: Energy loss per cycle (lower = more oscillation)
- velocityScale: Multiplier for input-driven motion

Usage:
  local spring = AnimationSystem:spring(parent, {
    stiffness = 0.8,
    damping = 0.6,
  })
  spring:setProperty("Rotation", 45)  -- animate Rotation to 45

NOTE: Spring only animates NUMERIC properties (Rotation, Transparency, etc).
It cannot animate UDim2/Vector2/Color3 — use TweenService for those.

--]]

local Spring = {}
Spring.__index = Spring

-- Registry of all active springs, ticked by Heartbeat
local activeSprings = {}
local heartbeatConnected = false

local function ensureHeartbeat()
  if heartbeatConnected then return end
  heartbeatConnected = true
  local lastTime = os.clock()
  RunService.Heartbeat:Connect(function()
    local now = os.clock()
    local dt = math.min(now - lastTime, 0.1)  -- cap dt to avoid spiral of death
    lastTime = now
    -- Iterate backwards so removals during iteration are safe
    for i = #activeSprings, 1, -1 do
      local spring = activeSprings[i]
      if spring:update(dt) then
        -- Spring settled, remove from active list
        table.remove(activeSprings, i)
      end
    end
  end)
end

function Spring.new(parent, config)
  local self = setmetatable({}, Spring)

  self.parent = parent or nil
  self.property = nil  -- must be set via setProperty

  -- Default spring parameters (tuned for UI elements)
  self.stiffness = config and config.stiffness or 0.85
  self.damping = config and config.damping or 0.65

  -- Current state
  self.currentValue = nil
  self.targetValue = nil
  self.velocity = 0
  self.isAnimating = false

  return self
end

function Spring:setProperty(property)
  self.property = property
  -- Store the current value of this property on the parent (if it exists)
  -- Only works for numeric properties
  if self.parent then
    local ok, val = pcall(function() return self.parent[property] end)
    if ok and type(val) == "number" then
      self.currentValue = val
    end
  end
end

function Spring:apply(value, instant)
  if instant then
    -- Instant set (no animation)
    self.currentValue = value
    self.targetValue = value
    self.velocity = 0
    self.isAnimating = false

    if self.parent and self.property then
      pcall(function() self.parent[self.property] = value end)
    end
    return true
  end

  -- Start or redirect spring animation
  if self.currentValue == nil then
    -- Initialize from parent if we haven't yet
    if self.parent and self.property then
      local ok, val = pcall(function() return self.parent[self.property] end)
      if ok and type(val) == "number" then
        self.currentValue = val
      else
        self.currentValue = value  -- can't read, just snap
      end
    else
      self.currentValue = value
    end
  end

  self.targetValue = value
  self.isAnimating = true

  -- Register for heartbeat ticks if not already active
  local alreadyRegistered = false
  for _, s in ipairs(activeSprings) do
    if s == self then alreadyRegistered = true; break end
  end
  if not alreadyRegistered then
    table.insert(activeSprings, self)
    ensureHeartbeat()
  end

  return false
end

function Spring:update(dt)
  if not self.isAnimating then
    return true  -- settled (or never started)
  end

  if self.currentValue == nil or self.targetValue == nil then
    return true
  end

  -- Spring physics: F = kx - cv (Hooke's restoring law + damping). The
  -- restoring term must point TOWARD the target (displacement = target -
  -- current, so +k*displacement); the previous negated form was an
  -- anti-restoring force that diverged from the target and never settled
  -- (dead code today — no Spring consumers — but a landmine for any
  -- future caller, since unsettled springs accumulate in activeSprings
  -- and get ticked every Heartbeat forever).
  local displacement = self.targetValue - self.currentValue
  local force = (self.stiffness * displacement) - (self.damping * self.velocity)

  self.velocity = self.velocity + (force * dt)
  self.currentValue = self.currentValue + (self.velocity * dt)

  -- Check if settled
  if math.abs(displacement) < 0.01 and math.abs(self.velocity) < 0.01 then
    self.currentValue = self.targetValue
    self.isAnimating = false

    if self.parent and self.property then
      pcall(function() self.parent[self.property] = self.targetValue end)
    end

    return true  -- settled
  end

  -- Apply current value to parent
  if self.parent and self.property then
    pcall(function() self.parent[self.property] = self.currentValue end)
  end

  return false  -- still animating
end

function Spring:reset()
  self.velocity = 0
  self.isAnimating = false
  -- Remove from active list
  for i = #activeSprings, 1, -1 do
    if activeSprings[i] == self then
      table.remove(activeSprings, i)
      break
    end
  end
end

--[[
=============================================================================
Micro-interaction System
=============================================================================

Provides instant feedback for user actions. Each interaction type has a
specific visual and/or haptic response.

Types:
- press: Button click feedback (squash + sound)
- toggle: Switch/checkbox state change
- success: Positive action confirmation
- error: Negative action feedback
--]]

local MicroInteraction = {}
MicroInteraction.__index = MicroInteraction

function MicroInteraction.new(config)
  local self = setmetatable({}, MicroInteraction)

  self.config = config or {}
  self.interactions = {}

  return self
end

function MicroInteraction:addPress(button, soundId, volume)
  -- Button press feedback with squash animation
  if not button then
    return false
  end

  local interaction = {
    type = "press",
    button = button,
    soundId = soundId or nil,
    volume = volume or 0.3,
    scaleDown = 0.96,
    scaleUp = 1.0,
    tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    scaleInstance = nil,
  }

  self.interactions[button] = interaction

  -- Reuse existing UIScale if present, otherwise create one
  local function getOrCreateScale()
    local existing = button:FindFirstChildOfClass("UIScale")
    if existing then return existing end
    local s = Instance.new("UIScale")
    s.Parent = button
    return s
  end

  -- Connect events (tracked for Destroying cleanup — 6yp6.5)
  local pressDownConn = button.MouseButton1Down:Connect(function()
    if not button.Active then return end

    -- Play sound
    if interaction.soundId then
      pcall(function()
        local s = Instance.new("Sound")
        s.SoundId = interaction.soundId
        s.Volume = interaction.volume
        s.Parent = SoundService
        SoundService:PlayLocalSound(s)
        Debris:AddItem(s, 2)
      end)
    end

    -- Squash animation — reuse existing UIScale to avoid stacking
    local scale = getOrCreateScale()
    interaction.scaleInstance = scale
    TweenService:Create(scale, interaction.tweenInfo, { Scale = interaction.scaleDown }):Play()
  end)

  local pressUpConn = button.MouseButton1Up:Connect(function()
    local scale = interaction.scaleInstance
    if scale and scale.Parent then
      -- selene: allow(incorrect_standard_library_use) — Spring is a valid
      -- Enum.EasingStyle member (confirmed via Roblox creator docs); selene
      -- 0.31's roblox std is stale.
      TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Spring, Enum.EasingDirection.Out),
                         { Scale = interaction.scaleUp }):Play()
    end
    interaction.scaleInstance = nil
  end)

  local pressEndConn = button.InputEnded:Connect(function(inputObject)
    if inputObject.UserInputType == Enum.UserInputType.Touch or
       inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
      local scale = interaction.scaleInstance
      if scale and scale.Parent then
        TweenService:Create(scale, interaction.tweenInfo, { Scale = interaction.scaleUp }):Play()
      end
      interaction.scaleInstance = nil
    end
  end)

  -- harborheist-review-aug2026-6yp6.5: auto-disconnect on destroy. Buttons
  -- ARE recreated (shop/inventory/raid rows, toast action buttons) and each
  -- orphan kept the closures AND the self.interactions registry entry — a
  -- strong ref to the destroyed button. Destroying fires on Destroy(), so
  -- cleanup needs no call-site cooperation.
  interaction.connections = { pressDownConn, pressUpConn, pressEndConn }
  button.Destroying:Connect(function()
    for _, conn in ipairs(interaction.connections) do
      conn:Disconnect()
    end
    self.interactions[button] = nil
  end)

  return true
end

function MicroInteraction:addToggle(switchFrame, label)
  -- Toggle switch animation with slide effect
  if not switchFrame then
    return false
  end

  local interaction = {
    type = "toggle",
    switchFrame = switchFrame,
    label = label or nil,
    isOn = false,
    tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
  }

  self.interactions[switchFrame] = interaction

  -- Toggle state change animation (tracked for Destroying cleanup — 6yp6.5)
  local toggleConn = switchFrame.Activated:Connect(function()
    interaction.isOn = not interaction.isOn
    local targetX = interaction.isOn and 15 or -15

    -- Animate the toggle knob
    TweenService:Create(switchFrame, interaction.tweenInfo, {
      Position = UDim2.new(0, targetX, 0, 0)
    }):Play()

    -- Optional label animation
    if interaction.label then
      TweenService:Create(interaction.label,
                         TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                         { TextTransparency = 0 }):Play()
    end
  end)

  -- harborheist-review-aug2026-6yp6.5: auto-disconnect + registry eviction.
  interaction.connections = { toggleConn }
  switchFrame.Destroying:Connect(function()
    for _, conn in ipairs(interaction.connections) do
      conn:Disconnect()
    end
    self.interactions[switchFrame] = nil
  end)

  return true
end

function MicroInteraction:addSuccess(parent, message, duration)
  -- Success indicator animation (checkmark fade in/out)
  if not parent then
    return false
  end

  local checkmark = Instance.new("Frame")
  checkmark.Size = UDim2.new(0, 48, 0, 48)
  checkmark.Position = UDim2.new(0.5, -24, 0.5, -24)
  checkmark.BackgroundColor3 = UIPalette.color("good")
  checkmark.BackgroundTransparency = 1 -- fade in
  checkmark.ZIndex = 900 + 1
  checkmark.Parent = parent

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = checkmark

  local successText = Instance.new("TextLabel")
  successText.Size = UDim2.new(1, -16, 1, -16)
  successText.Position = UDim2.new(0, 8, 0, 8)
  successText.Text = message or "Success!"
  successText.Font = Enum.Font.SourceSansBold
  successText.TextSize = 14
  successText.TextColor3 = Color3.fromRGB(255, 255, 255)
  successText.BackgroundTransparency = 1
  successText.ZIndex = 900 + 2
  successText.Parent = checkmark

  -- Fade in animation
  TweenService:Create(checkmark, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                     { BackgroundTransparency = 0 }):Play()

  -- Schedule fade out
  task.delay(duration or 2.0, function()
    if checkmark.Parent then
      TweenService:Create(checkmark,
                          TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                          { BackgroundTransparency = 1 }):Play()
      TweenService:Create(successText,
                         TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                         { TextTransparency = 1 }):Play()

      task.delay(0.3, function()
        if checkmark.Parent then
          checkmark:Destroy()
        end
      end)
    end
  end)

  return true
end

function MicroInteraction:addError(parent, message, duration)
  -- Error indicator animation (X mark fade in/out with red color)
  if not parent then
    return false
  end

  local errorFrame = Instance.new("Frame")
  errorFrame.Size = UDim2.new(0, 48, 0, 48)
  errorFrame.Position = UDim2.new(0.5, -24, 0.5, -24)
  errorFrame.BackgroundColor3 = UIPalette.color("bad")
  errorFrame.BackgroundTransparency = 1 -- fade in
  errorFrame.ZIndex = 900 + 1
  errorFrame.Parent = parent

  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = errorFrame

  local errorText = Instance.new("TextLabel")
  errorText.Size = UDim2.new(1, -16, 1, -16)
  errorText.Position = UDim2.new(0, 8, 0, 8)
  errorText.Text = message or "Error!"
  errorText.Font = Enum.Font.SourceSansBold
  errorText.TextSize = 14
  errorText.TextColor3 = Color3.fromRGB(255, 255, 255)
  errorText.BackgroundTransparency = 1
  errorText.ZIndex = 900 + 2
  errorText.Parent = errorFrame

  -- Fade in animation
  TweenService:Create(errorFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                     { BackgroundTransparency = 0 }):Play()

  -- Schedule fade out
  task.delay(duration or 2.0, function()
    if errorFrame.Parent then
      TweenService:Create(errorFrame,
                          TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                          { BackgroundTransparency = 1 }):Play()
      TweenService:Create(errorText,
                         TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                         { TextTransparency = 1 }):Play()

      task.delay(0.3, function()
        if errorFrame.Parent then
          errorFrame:Destroy()
        end
      end)
    end
  end)

  return true
end

--[[
=============================================================================
Gesture Animation System
=============================================================================

Provides touch-based animations for mobile devices.

Types:
- swipeDismiss: Swipe to dismiss panels/toasts
- pullToRefresh: Pull down to refresh content
--]]

local GestureAnimation = {}
GestureAnimation.__index = GestureAnimation

function GestureAnimation.new(config)
  local self = setmetatable({}, GestureAnimation)

  self.config = config or {}
  self.swipeThreshold = config and config.swipeThreshold or 100
  self.pullDistance = config and config.pullDistance or 50

  return self
end

function GestureAnimation:enableSwipeDismiss(panel, onDismiss)
  if not panel then
    return false
  end

  local minSwipeDistance = self.swipeThreshold or 100
  local tracking = false
  local startX, startY = 0, 0
  local startedInScrollable = false

  -- Helper: check if a point is inside a ScrollingFrame
  local function isPointInScrollingFrame(x, y)
    for _, child in ipairs(panel:GetDescendants()) do
      if child:IsA("ScrollingFrame") and child.Visible then
        local absPos = child.AbsolutePosition
        local absSize = child.AbsoluteSize
        if x >= absPos.X and x <= absPos.X + absSize.X and
           y >= absPos.Y and y <= absPos.Y + absSize.Y then
          return true
        end
      end
    end
    return false
  end

  local swipeBeganConn = panel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
      tracking = true
      startX = input.Position.X
      startY = input.Position.Y
      -- Check if touch started inside a scrollable area
      startedInScrollable = isPointInScrollingFrame(startX, startY)
    end
  end)

  local swipeEndedConn = panel.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch and tracking then
      tracking = false
      local endX = input.Position.X
      local endY = input.Position.Y
      local deltaX = endX - startX
      local deltaY = endY - startY

      if startedInScrollable then
        -- Inside scrollable: only allow horizontal swipes to dismiss
        -- Vertical swipes are reserved for scrolling/pull-to-refresh
        if math.abs(deltaX) > minSwipeDistance and math.abs(deltaX) > math.abs(deltaY) then
          if onDismiss then
            onDismiss()
          end
        end
      else
        -- Outside scrollable: allow both horizontal and vertical swipes
        if math.abs(deltaX) > minSwipeDistance and math.abs(deltaX) > math.abs(deltaY) then
          -- Horizontal swipe
          if onDismiss then
            onDismiss()
          end
        elseif deltaY > minSwipeDistance then
          -- Swipe down (natural dismiss for bottom sheets)
          if onDismiss then
            onDismiss()
          end
        end
      end
    end
  end)

  -- harborheist-review-aug2026-6yp6.5: auto-disconnect on panel destroy.
  local swipeConnections = { swipeBeganConn, swipeEndedConn }
  panel.Destroying:Connect(function()
    for _, conn in ipairs(swipeConnections) do
      conn:Disconnect()
    end
  end)

  return true
end

function GestureAnimation:enablePullToRefresh(refreshContainer, onRefresh)
  if not refreshContainer then
    return false
  end

  local minPullDistance = self.pullDistance or 50
  local tracking = false
  local startY = 0
  local refreshing = false

  local refreshBeganConn = refreshContainer.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
      -- Only track if scrolled to top (standard pull-to-refresh UX)
      -- Use epsilon for floating point comparison
      local isScrollingFrame = refreshContainer:IsA("ScrollingFrame")
      local atTop = not isScrollingFrame or refreshContainer.CanvasPosition.Y < 1
      
      if atTop then
        tracking = true
        startY = input.Position.Y
      end
    end
  end)

  local refreshEndedConn = refreshContainer.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch and tracking then
      tracking = false
      local endY = input.Position.Y
      local deltaY = endY - startY  -- positive = pulled DOWN

      -- Pull DOWN to refresh (natural gesture)
      if deltaY > minPullDistance and not refreshing then
        refreshing = true
        if onRefresh then
          local ok, err = pcall(onRefresh)
          if not ok then
            warn("[AnimationSystem] pullToRefresh callback error: " .. tostring(err))
          end
        end
        -- Debounce: prevent re-trigger for 1 second
        task.delay(1.0, function()
          refreshing = false
        end)
      end
    end
  end)

  -- harborheist-review-aug2026-6yp6.5: auto-disconnect on container destroy.
  local refreshConnections = { refreshBeganConn, refreshEndedConn }
  refreshContainer.Destroying:Connect(function()
    for _, conn in ipairs(refreshConnections) do
      conn:Disconnect()
    end
  end)

  return true
end

--[[
=============================================================================
Transition Library
=============================================================================

Reusable transition presets for common UI animations.

Transitions:
- fade: Fade in/out with smooth alpha
- slide: Slide from edges (enter/exit)
- scale: Scale up/down for emphasis
- rotate: Rotate for attention-grabbing effects
- fadeSlide: Combined fade + slide for panel transitions
--]]

local Transition = {}
Transition.__index = Transition

function Transition.new(config)
  local self = setmetatable({}, Transition)

  self.config = config or {}
  self.defaultDuration = config and config.duration or 0.3
  self.defaultEasing = config and config.easing or Enum.EasingStyle.Quad

  return self
end

-- TextTransparency exists only on text-bearing classes. Including it in a
-- tween goal for a plain Frame/ImageLabel makes TweenService:Create raise
-- "TextTransparency is not a valid member of <Class>" and abort the caller
-- (init.client.lua's desktop showPanel passed a Frame here).
local function supportsTextTransparency(element)
  return element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox")
end

-- harborheist-kqbq.17.2: resolve a duration argument that may be either a
-- bare number (legacy callers) or a pre-built TweenInfo from Theme.motion.
-- When a TweenInfo is passed it is used verbatim so the centralized easing
-- tokens flow through; a number falls back to the default easing so every
-- existing caller keeps working unchanged.
local function resolveTransitionInfo(duration, ctx, defaultStyle, defaultDirection)
  if typeof(duration) == "TweenInfo" then
    return duration
  end
  local dur = duration or ctx.defaultDuration or 0.3
  return TweenInfo.new(dur, defaultStyle, defaultDirection)
end

function Transition:fade(element, visible, duration)
  if not element then
    return false
  end

  local tweenInfo
  if typeof(duration) == "TweenInfo" then
    tweenInfo = duration
  else
    local dur = duration or self.defaultDuration or 0.3
    local easing = self.defaultEasing or Enum.EasingStyle.Quad
    tweenInfo = TweenInfo.new(dur, easing, Enum.EasingDirection.Out)
  end

  local target = visible and 0 or 1
  local props = { BackgroundTransparency = target }
  if supportsTextTransparency(element) then
    props.TextTransparency = target
  end

  TweenService:Create(element, tweenInfo, props):Play()
  return visible and true or false
end

function Transition:slide(element, direction, duration)
  if not element then
    return false
  end

  local offset
  if direction == "left" then
    offset = UDim2.new(-1, 0, 0, 0)
  elseif direction == "right" then
    offset = UDim2.new(1, 0, 0, 0)
  elseif direction == "up" then
    -- Slide up to center (for mobile panel show)
    offset = UDim2.new(0.5, 0, 0.5, 0)
  elseif direction == "down" then
    -- Slide down off screen (for mobile panel hide)
    offset = UDim2.new(0.5, 0, 1.78, 0)
  else
    return false
  end

  local tweenInfo = resolveTransitionInfo(duration, self, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

  TweenService:Create(element, tweenInfo, { Position = offset }):Play()

  return true
end

function Transition:scale(element, scaleValue, duration)
  if not element then
    return false
  end

  -- Reuse existing UIScale if present
  local uiScale = element:FindFirstChildOfClass("UIScale")
  if not uiScale then
    uiScale = Instance.new("UIScale")
    uiScale.Parent = element
  end

  local tweenInfo = resolveTransitionInfo(duration, self, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

  TweenService:Create(uiScale, tweenInfo, { Scale = scaleValue }):Play()

  return true
end

function Transition:rotate(element, degrees, duration)
  if not element then
    return false
  end

  -- Roblox GuiObjects have a Rotation property directly (no UIRotation class)
  local tweenInfo = resolveTransitionInfo(duration, self, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

  TweenService:Create(element, tweenInfo, { Rotation = degrees }):Play()

  return true
end

-- Combined preset: fade + slide for panel transitions
function Transition:fadeSlide(element, visible, direction, duration)
  if not element then
    return false
  end

  local offset
  if direction == "left" then
    offset = UDim2.new(-1, 0, 0, 0)
  elseif direction == "right" then
    offset = UDim2.new(1, 0, 0, 0)
  elseif direction == "up" then
    offset = UDim2.new(0, 0, -1, 0)
  elseif direction == "down" then
    offset = UDim2.new(0, 0, 1, 0)
  else
    offset = UDim2.new(0, 0, 1, 0)  -- default: slide down
  end

  local tweenInfo = resolveTransitionInfo(duration, self, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

  local target = visible and 0 or 1
  local props = {
    BackgroundTransparency = target,
    Position = visible and UDim2.new(0.5, 0, 0.5, 0) or offset,  -- center when showing
  }
  if supportsTextTransparency(element) then
    props.TextTransparency = target
  end

  TweenService:Create(element, tweenInfo, props):Play()
  return visible and true or false
end

--[[
=============================================================================
Animation System Factory
=============================================================================

Creates singleton instances of each subsystem and exposes them through
a single interface. All methods are safe to call — they pcall internally
where needed.

--]]

-- Create singleton instances (fixes the "methods called on class table" bug)
local microInteraction = MicroInteraction.new()
local gestureAnimation = GestureAnimation.new()
local transition = Transition.new()

function AnimationSystem:spring(parent, config)
  local spring = Spring.new(parent, config)
  if parent then
    -- Default to Rotation (a numeric property) — Size is UDim2 and won't work
    spring:setProperty("Rotation")
  end
  return spring
end

function AnimationSystem:press(button, soundId, volume)
  return microInteraction:addPress(button, soundId, volume)
end

function AnimationSystem:toggle(switchFrame, label)
  return microInteraction:addToggle(switchFrame, label)
end

function AnimationSystem:success(parent, message, duration)
  return microInteraction:addSuccess(parent, message, duration)
end

function AnimationSystem:error(parent, message, duration)
  return microInteraction:addError(parent, message, duration)
end

function AnimationSystem:swipeDismiss(panel, onDismiss)
  return gestureAnimation:enableSwipeDismiss(panel, onDismiss)
end

function AnimationSystem:pullToRefresh(refreshContainer, onRefresh)
  return gestureAnimation:enablePullToRefresh(refreshContainer, onRefresh)
end

function AnimationSystem:fade(element, visible, duration)
  return transition:fade(element, visible, duration)
end

function AnimationSystem:slide(element, direction, duration)
  return transition:slide(element, direction, duration)
end

function AnimationSystem:scale(element, scaleValue, duration)
  return transition:scale(element, scaleValue, duration)
end

function AnimationSystem:rotate(element, degrees, duration)
  return transition:rotate(element, degrees, duration)
end

function AnimationSystem:fadeSlide(element, visible, direction, duration)
  return transition:fadeSlide(element, visible, direction, duration)
end

return AnimationSystem
