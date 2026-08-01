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

-- Services
local TweenService = game:GetService("TweenService")

-- Default configuration
-- harborheist-pj19: Use consistent easings from init.client.lua (EASE_OUT for open, EASE_IN for close)
local DEFAULT_CONFIG = {
  duration = 0.25,
  scaleStart = 0.8,
  easingStyle = Enum.EasingStyle.Quint,  -- EASE_OUT equivalent for smooth deceleration on open
  easingDirection = Enum.EasingDirection.Out,
}

-- Close animation defaults (EASE_IN for acceleration effect)
local DEFAULT_CLOSE_CONFIG = {
  duration = 0.25,
  easingStyle = Enum.EasingStyle.Quad,   -- EASE_IN equivalent for smooth acceleration on close
  easingDirection = Enum.EasingDirection.In,
}

-- Track active animations for cleanup (weak keys prevent memory leaks
-- when panels are destroyed externally without going through close())
local activeTweens = {}
setmetatable(activeTweens, { __mode = "k" })

-- Track animation context for proper close animations
local animationContext = {}
setmetatable(animationContext, { __mode = "k" })

-- Helper to get or create a UIScale for animation
-- Returns the UIScale to animate, or nil if the panel has a user-managed UIScale
-- Uses the PanelAnimationOwned attribute to distinguish our UIScales from user ones
local function ensureUIScale(guiObject)
  local success, uiScale = pcall(function()
    return guiObject:FindFirstChildWhichIsA("UIScale")
  end)
  
  if not success then
    return nil
  end
  
  if uiScale then
    -- If it has our ownership attribute, it's ours — safe to reuse
    local success, hasAttr = pcall(function()
      return uiScale:GetAttribute("PanelAnimationOwned")
    end)
    if success and hasAttr then
      return uiScale
    end
    -- Otherwise it's user-managed — don't interfere
    return nil
  end
  
  -- No UIScale exists — create one and mark it as ours
  local createSuccess, newScale = pcall(function()
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale:SetAttribute("PanelAnimationOwned", true)
    scale.Parent = guiObject
    return scale
  end)
  
  if not createSuccess then
    return nil
  end
  
  return newScale
end

-- Open a panel with animation
function PanelAnimation:open(panel, options)
  -- Validate panel exists and is a GuiObject
  if not panel then
    warn("[PanelAnimation] No panel provided to open()")
    return false
  end
  
  local success, isGui = pcall(function() return panel:IsA("GuiObject") end)
  if not success or not isGui then
    warn("[PanelAnimation] Invalid panel provided to open() - must be a GuiObject")
    return false
  end
  
  -- Merge config with proper nil handling (not truthy/falsy)
  local config = {
    duration = options and options.duration ~= nil and options.duration or DEFAULT_CONFIG.duration,
    scaleStart = options and options.scaleStart ~= nil and options.scaleStart or DEFAULT_CONFIG.scaleStart,
    easingStyle = options and options.easingStyle ~= nil and options.easingStyle or DEFAULT_CONFIG.easingStyle,
    easingDirection = options and options.easingDirection ~= nil and options.easingDirection or DEFAULT_CONFIG.easingDirection,
    onComplete = options and options.onComplete,
  }
  
  -- Validate duration is positive
  if config.duration <= 0 then
    warn("[PanelAnimation] Duration must be positive, got: " .. tostring(config.duration))
    return false
  end
  
  -- Cancel any existing animation on this panel
  if activeTweens[panel] then
    for _, tween in ipairs(activeTweens[panel]) do
      pcall(function() tween:Cancel() end)
    end
    activeTweens[panel] = nil
  end
  
  -- Ensure panel has UIScale for scaling animation
  local uiScale = ensureUIScale(panel)
  if not uiScale then
    warn("[PanelAnimation] Panel has user-managed UIScale, skipping scale animation")
    -- Only animate transparency
    local fadeTweenSuccess, fadeTween = pcall(function()
      return TweenService:Create(panel, TweenInfo.new(
        config.duration,
        config.easingStyle,
        config.easingDirection
      ), {
        BackgroundTransparency = 0,
      })
    end)
    
    if not fadeTweenSuccess then
      warn("[PanelAnimation] Failed to create fade tween: " .. tostring(fadeTween))
      return false
    end
    
    -- Set initial state AFTER successful tween creation
    panel.BackgroundTransparency = 1
    
    activeTweens[panel] = {fadeTween}
    -- harborheist-review-aug2026-6yp6.6: :Once (not :Connect) — Completed
    -- fires exactly once per tween with its terminal state, so :Once gives
    -- correct one-shot semantics and auto-disconnects after the fire.
    fadeTween.Completed:Once(function(playbackState)
      if playbackState ~= Enum.PlaybackState.Completed then
        return
      end
      activeTweens[panel] = nil
      animationContext[panel] = nil
      if config.onComplete then
        config.onComplete()
      end
    end)
    fadeTween:Play()
    return true
  end
  
  -- Create tweens BEFORE setting initial state to avoid partial initialization
  local fadeTweenSuccess, fadeTween = pcall(function()
    return TweenService:Create(panel, TweenInfo.new(
      config.duration,
      config.easingStyle,
      config.easingDirection
    ), {
      BackgroundTransparency = 0,
    })
  end)
  
  if not fadeTweenSuccess then
    warn("[PanelAnimation] Failed to create fade tween: " .. tostring(fadeTween))
    return false
  end
  
  local scaleTweenSuccess, scaleTween = pcall(function()
    return TweenService:Create(uiScale, TweenInfo.new(
      config.duration,
      config.easingStyle,
      config.easingDirection
    ), {
      Scale = 1,
    })
  end)
  
  if not scaleTweenSuccess then
    warn("[PanelAnimation] Failed to create scale tween: " .. tostring(scaleTween))
    -- Clean up the fade tween we already created
    pcall(function() fadeTween:Cancel() end)
    return false
  end
  
  -- Store animation context for proper close animations
  animationContext[panel] = {
    scaleStart = config.scaleStart,
  }
  
  -- Set initial state AFTER all tweens are successfully created
  panel.BackgroundTransparency = 1
  uiScale.Scale = config.scaleStart
  
  -- Track tweens
  activeTweens[panel] = {fadeTween, scaleTween}
  
  -- Set up completion callback (only fires on natural completion, not cancellation)
  fadeTween.Completed:Once(function(playbackState)
    if playbackState ~= Enum.PlaybackState.Completed then
      return
    end
    activeTweens[panel] = nil
    animationContext[panel] = nil
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
  -- Validate panel exists and is a GuiObject
  if not panel then
    warn("[PanelAnimation] No panel provided to close()")
    return false
  end
  
  local success, isGui = pcall(function() return panel:IsA("GuiObject") end)
  if not success or not isGui then
    warn("[PanelAnimation] Invalid panel provided to close() - must be a GuiObject")
    return false
  end
  
  -- Merge config with proper nil handling
  local config = {
    duration = options and options.duration ~= nil and options.duration or DEFAULT_CONFIG.duration,
    scaleEnd = options and options.scaleEnd ~= nil and options.scaleEnd or DEFAULT_CONFIG.scaleStart,
    easingStyle = options and options.easingStyle ~= nil and options.easingStyle or Enum.EasingStyle.Quad,
    easingDirection = options and options.easingDirection ~= nil and options.easingDirection or Enum.EasingDirection.In,
    onComplete = options and options.onComplete,
    destroyOnComplete = options and options.destroyOnComplete,
  }
  
  -- Validate duration is positive
  if config.duration <= 0 then
    warn("[PanelAnimation] Duration must be positive, got: " .. tostring(config.duration))
    return false
  end
  
  -- Cancel any existing animation
  if activeTweens[panel] then
    for _, tween in ipairs(activeTweens[panel]) do
      pcall(function() tween:Cancel() end)
    end
    activeTweens[panel] = nil
  end
  
  -- Get or create UIScale
  local uiScale = ensureUIScale(panel)
  if not uiScale then
    warn("[PanelAnimation] Panel has user-managed UIScale, skipping scale animation")
    -- Only animate transparency
    local fadeTweenSuccess, fadeTween = pcall(function()
      return TweenService:Create(panel, TweenInfo.new(
        config.duration,
        config.easingStyle,
        config.easingDirection
      ), {
        BackgroundTransparency = 1,
      })
    end)
    
    if not fadeTweenSuccess then
      warn("[PanelAnimation] Failed to create fade tween: " .. tostring(fadeTween))
      return false
    end
    
    activeTweens[panel] = {fadeTween}
    fadeTween.Completed:Once(function(playbackState)
      if playbackState ~= Enum.PlaybackState.Completed then
        return
      end
      activeTweens[panel] = nil
      animationContext[panel] = nil
      if config.destroyOnComplete and panel.Parent then
        panel:Destroy()
      end
      if config.onComplete then
        config.onComplete()
      end
    end)
    fadeTween:Play()
    return true
  end
  
  -- Use stored context if available, otherwise use provided scaleEnd or default
  local context = animationContext[panel]
  local targetScaleEnd = config.scaleEnd
  if context and context.scaleStart then
    -- Use the original scaleStart as the default scaleEnd if not explicitly provided
    if not (options and options.scaleEnd ~= nil) then
      targetScaleEnd = context.scaleStart
    end
  end
  
  -- Create fade-out tween with error handling
  local fadeTweenSuccess, fadeTween = pcall(function()
    return TweenService:Create(panel, TweenInfo.new(
      config.duration,
      config.easingStyle,
      config.easingDirection
    ), {
      BackgroundTransparency = 1,
    })
  end)
  
  if not fadeTweenSuccess then
    warn("[PanelAnimation] Failed to create fade tween: " .. tostring(fadeTween))
    return false
  end
  
  -- Create scale-down tween with error handling
  local scaleTweenSuccess, scaleTween = pcall(function()
    return TweenService:Create(uiScale, TweenInfo.new(
      config.duration,
      config.easingStyle,
      config.easingDirection
    ), {
      Scale = targetScaleEnd,
    })
  end)
  
  if not scaleTweenSuccess then
    warn("[PanelAnimation] Failed to create scale tween: " .. tostring(scaleTween))
    -- Clean up the fade tween we already created
    pcall(function() fadeTween:Cancel() end)
    return false
  end
  
  -- Track tweens
  activeTweens[panel] = {fadeTween, scaleTween}
  
  -- Set up completion callback (only fires on natural completion, not cancellation)
  fadeTween.Completed:Once(function(playbackState)
    if playbackState ~= Enum.PlaybackState.Completed then
      return
    end
    activeTweens[panel] = nil
    animationContext[panel] = nil
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
  -- Validate panel exists and is a GuiObject
  if not panel then
    warn("[PanelAnimation] No panel provided to cancel()")
    return false
  end
  
  local success, isGui = pcall(function() return panel:IsA("GuiObject") end)
  if not success or not isGui then
    warn("[PanelAnimation] Invalid panel provided to cancel() - must be a GuiObject")
    return false
  end
  
  if activeTweens[panel] then
    for _, tween in ipairs(activeTweens[panel]) do
      pcall(function() tween:Cancel() end)
    end
    activeTweens[panel] = nil
  end
  
  -- Reset panel to fully visible state
  pcall(function()
    panel.BackgroundTransparency = 0
  end)
  
  -- Reset UIScale to 1 if it exists
  local uiScale = panel:FindFirstChildWhichIsA("UIScale")
  if uiScale then
    pcall(function()
      uiScale.Scale = 1
    end)
  end
  
  -- Clear animation context to prevent memory leak
  animationContext[panel] = nil
  
  return true
end

-- Check if panel is animating
function PanelAnimation:isAnimating(panel)
  return activeTweens[panel] ~= nil
end

-- Cleanup all animations
function PanelAnimation:cleanup()
  -- Collect all panels first to avoid modifying table while iterating
  local panelsToClean = {}
  for panel in pairs(activeTweens) do
    table.insert(panelsToClean, panel)
  end
  
  -- Cancel all tweens and clear context
  for _, panel in ipairs(panelsToClean) do
    local tweens = activeTweens[panel]
    if tweens then
      for _, tween in ipairs(tweens) do
        pcall(function() tween:Cancel() end)
      end
    end
    activeTweens[panel] = nil
    animationContext[panel] = nil
  end
end

-- Cleanup on game shutdown
game:BindToClose(function()
  PanelAnimation:cleanup()
end)

return PanelAnimation
