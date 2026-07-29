--[[
=============================================================================
EPIC 34: Animation & Motion Design — Panel Animations Module
=============================================================================

Provides smooth fade + scale animations for panels, modals, and dialogs.

USAGE:
  local PanelAnimation = require(ReplicatedStorage.Modules.PanelAnimation)
  
  -- Open a panel with animation
  local panel = Instance.new("Frame")
  panel.Size = UDim2.new(0, 400, 0, 300)
  panel.BackgroundTransparency = 1
  
  PanelAnimation:open(panel, {
    duration = 0.3,
    scaleStart = 0.8,
    onComplete = function() print("Panel opened") end,
  })
  
  -- Close a panel with animation
  PanelAnimation:close(panel)

CONFIGURATION:
- duration: Animation duration in seconds (default: 0.25)
- scaleStart: Starting scale for open animation (default: 0.8)
- easingStyle: Easing style to use (default: Enum.EasingStyle.Back)
--]]

local PanelAnimation = {}
PanelAnimation.__index = PanelAnimation

-- Services
local TweenService = game:GetService("TweenService")

-- Default configuration
local DEFAULT_CONFIG = {
  duration = 0.25,
  scaleStart = 0.8,
  easingStyle = Enum.EasingStyle.Back,
  easingDirection = Enum.EasingDirection.Out,
}

-- Track active animations for cleanup
local activeTweens = {}

-- Helper to create UIScale if needed
local function ensureUIScale(guiObject)
  local uiScale = guiObject:FindFirstChildWhichIsA("UIScale")
  if not uiScale then
    uiScale = Instance.new("UIScale")
    uiScale.Parent = guiObject
  end
  return uiScale
end

-- Open a panel with animation
function PanelAnimation:open(panel, options)
  if not panel or not panel:IsA("GuiObject") then
    warn("[PanelAnimation] Invalid panel provided to open()")
    return false
  end
  
  local config = {
    duration = (options and options.duration) or DEFAULT_CONFIG.duration,
    scaleStart = (options and options.scaleStart) or DEFAULT_CONFIG.scaleStart,
    easingStyle = (options and options.easingStyle) or DEFAULT_CONFIG.easingStyle,
    easingDirection = (options and options.easingDirection) or DEFAULT_CONFIG.easingDirection,
    onComplete = options and options.onComplete,
  }
  
  -- Cancel any existing animation on this panel
  if activeTweens[panel] then
    for _, tween in ipairs(activeTweens[panel]) do
      tween:Cancel()
    end
    activeTweens[panel] = nil
  end
  
  -- Ensure panel has UIScale for scaling animation
  local uiScale = ensureUIScale(panel)
  
  -- Set initial state
  panel.BackgroundTransparency = 1
  uiScale.Scale = config.scaleStart
  
  -- Create fade-in tween
  local fadeTween = TweenService:Create(panel, TweenInfo.new(
    config.duration,
    config.easingStyle,
    config.easingDirection
  ), {
    BackgroundTransparency = 0,
  })
  
  -- Create scale-up tween
  local scaleTween = TweenService:Create(uiScale, TweenInfo.new(
    config.duration,
    config.easingStyle,
    config.easingDirection
  ), {
    Scale = 1,
  })
  
  -- Track tweens
  activeTweens[panel] = {fadeTween, scaleTween}
  
  -- Set up completion callback
  fadeTween.Completed:Connect(function()
    activeTweens[panel] = nil
    if config.onComplete then
      config.onComplete()
    end
  end)
  
  -- Play both tweens
  fadeTween:Play()
  scaleTween:Play()
  
  return true
end

-- Close a panel with animation
function PanelAnimation:close(panel, options)
  if not panel or not panel:IsA("GuiObject") then
    warn("[PanelAnimation] Invalid panel provided to close()")
    return false
  end
  
  local config = {
    duration = (options and options.duration) or DEFAULT_CONFIG.duration,
    scaleEnd = (options and options.scaleEnd) or DEFAULT_CONFIG.scaleStart,
    easingStyle = (options and options.easingStyle) or Enum.EasingStyle.Quad,
    easingDirection = (options and options.easingDirection) or Enum.EasingDirection.In,
    onComplete = options and options.onComplete,
    destroyOnComplete = options and options.destroyOnComplete,
  }
  
  -- Cancel any existing animation
  if activeTweens[panel] then
    for _, tween in ipairs(activeTweens[panel]) do
      tween:Cancel()
    end
    activeTweens[panel] = nil
  end
  
  local uiScale = ensureUIScale(panel)
  
  -- Create fade-out tween
  local fadeTween = TweenService:Create(panel, TweenInfo.new(
    config.duration,
    config.easingStyle,
    config.easingDirection
  ), {
    BackgroundTransparency = 1,
  })
  
  -- Create scale-down tween
  local scaleTween = TweenService:Create(uiScale, TweenInfo.new(
    config.duration,
    config.easingStyle,
    config.easingDirection
  ), {
    Scale = config.scaleEnd,
  })
  
  -- Track tweens
  activeTweens[panel] = {fadeTween, scaleTween}
  
  -- Set up completion callback
  fadeTween.Completed:Connect(function()
    activeTweens[panel] = nil
    if config.destroyOnComplete and panel.Parent then
      panel:Destroy()
    end
    if config.onComplete then
      config.onComplete()
    end
  end)
  
  -- Play both tweens
  fadeTween:Play()
  scaleTween:Play()
  
  return true
end

-- Cancel animation immediately
function PanelAnimation:cancel(panel)
  if not panel then
    warn("[PanelAnimation] No panel provided to cancel()")
    return false
  end
  
  if activeTweens[panel] then
    for _, tween in ipairs(activeTweens[panel]) do
      tween:Cancel()
    end
    activeTweens[panel] = nil
  end
  
  return true
end

-- Check if panel is animating
function PanelAnimation:isAnimating(panel)
  return activeTweens[panel] ~= nil
end

-- Cleanup all animations
function PanelAnimation:cleanup()
  for panel, tweens in pairs(activeTweens) do
    for _, tween in ipairs(tweens) do
      tween:Cancel()
    end
  end
  activeTweens = {}
end

-- Cleanup on game shutdown
game:BindToClose(function()
  PanelAnimation:cleanup()
end)

return PanelAnimation
