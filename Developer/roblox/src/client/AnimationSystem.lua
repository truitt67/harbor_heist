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
    velocityScale = 1.0
  })
  
  -- Apply to property
  spring:setProperty("Position", targetValue)
  spring:update()

--]]

local Spring = {}
Spring.__index = Spring

function Spring.new(parent, config)
  local self = setmetatable({}, Spring)
  
  self.parent = parent or nil
  self.property = "Size" -- default property
  
  -- Default spring parameters (tuned for UI elements)
  self.stiffness = config and config.stiffness or 0.85
  self.damping = config and config.damping or 0.65
  self.velocityScale = config and config.velocityScale or 1.0
  
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
  if self.parent and type(self.parent[property]) == "number" then
    self.currentValue = self.parent[property]
  end
end

function Spring:apply(value, instant)
  -- Instant set (no animation)
  if instant or not self.isAnimating then
    self.currentValue = value
    self.targetValue = value
    self.velocity = 0
    
    -- Apply immediately if parent exists
    if self.parent and self.propertyName then
      self.parent[self.property] = value
    end
    
    return true
  end
  
  -- Start spring animation
  self.targetValue = value
  self.isAnimating = true
  
  -- If we have a parent, apply current value
  if self.parent and self.propertyName then
    self.parent[self.property] = self.currentValue or value
  end
  
  return false
end

function Spring:update(dt)
  if not self.isAnimating then
    return false
  end
  
  -- Spring physics: F = -kx - cv (Hooke's law + damping)
  local displacement = self.targetValue - self.currentValue
  local force = -(self.stiffness * displacement) - (self.damping * self.velocity)
  
  self.velocity = self.velocity + (force * dt)
  self.currentValue = self.currentValue + (self.velocity * dt)
  
  -- Check if settled
  if math.abs(displacement) < 0.01 then
    self.currentValue = self.targetValue
    self.isAnimating = false
    
    -- Apply final value
    if self.parent and self.propertyName then
      self.parent[self.property] = self.targetValue
    end
    
    return true
  end
  
  -- Apply current value to parent
  if self.parent and self.propertyName then
    self.parent[self.property] = self.currentValue
  end
  
  return false
end

function Spring:reset()
  self.velocity = 0
  self.isAnimating = false
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
- loading: Progress indicator
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
    tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
  }
  
  self.interactions[button] = interaction
  
  -- Connect events
  button.MouseButton1Down:Connect(function()
    if not button.Active then return end
    
    -- Play sound
    if interaction.soundId then
      local s = Instance.new("Sound")
      s.SoundId = interaction.soundId
      s.Volume = interaction.volume
      s.Parent = game:GetService("SoundService")
      SoundService:PlayLocalSound(s)
      Debris:AddItem(s, 2)
    end
    
    -- Squash animation
    local scale = Instance.new("UIScale")
    scale.Parent = button
    TweenService:Create(scale, interaction.tweenInfo, { Scale = interaction.scaleDown }):Play()
    
    self.interactions[button].scaleInstance = scale
  end)
  
  button.MouseButton1Up:Connect(function()
    local scale = self.interactions[button] and self.interactions[button].scaleInstance
    if scale then
      TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Spring, Enum.EasingDirection.Out), 
                         { Scale = interaction.scaleUp }):Play()
      self.interactions[button].scaleInstance = nil
    end
  end)
  
  button.InputEnded:Connect(function(inputObject)
    if inputObject.UserInputType == Enum.UserInputType.Touch or 
       inputObject.UserInputType == Enum.UserInputType.MouseButton1 then
      local scale = self.interactions[button] and self.interactions[button].scaleInstance
      if scale then
        TweenService:Create(scale, interaction.tweenInfo, { Scale = interaction.scaleUp }):Play()
        self.interactions[button].scaleInstance = nil
      end
    end
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
    offset = UDim2.new(0, -15, 0, 0),
    tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
  }
  
  self.interactions[switchFrame] = interaction
  
  -- Toggle state change animation
  switchFrame.Activated:Connect(function()
    local offset = interaction.offset
    
    -- Animate the toggle
    TweenService:Create(switchFrame, interaction.tweenInfo, { 
      Position = UDim2.new(0, 15, 0, 0) 
    }):Play()
    
    -- Optional label animation
    if interaction.label then
      local labelTween = TweenService:Create(interaction.label, 
                                             TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                                             { TextTransparency = 0 })
      labelTween:Play()
    end
  end)
  
  return true
end

function MicroInteraction:addSuccess(parent, message, duration)
  -- Success indicator animation (checkmark fade in/out)
  if not parent then
    return false
  end
  
  local interaction = {
    type = "success",
    parent = parent,
    message = message or "",
    duration = duration or 2.0,
    checkmark = nil
  }
  
  -- Create success indicator with fallback colors if Theme is not available
  local checkmark = Instance.new("Frame")
  checkmark.Size = UDim2.new(0, 48, 0, 48)
  checkmark.Position = UDim2.new(0.5, -24, 0.5, -24)
  
  -- Use fallback colors if Theme is not loaded yet
  local bgColor = parent.BackgroundColor3 or Color3.fromRGB(66, 153, 225) -- default blue
  checkmark.BackgroundColor3 = bgColor
  checkmark.BackgroundTransparency = 1 -- fade in
  checkmark.ZIndex = 900 + 1  -- fallback Z index
  
  checkmark.Parent = parent
  
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = checkmark
  
  -- Create success text with fallback label creation if makeLabel is not available
  local successText
  if type(makeLabel) == "function" then
    successText = makeLabel(checkmark, {
      Size = UDim2.new(1, -16, 1, -16),
      Position = UDim2.new(0, 8, 0, 8),
      Text = message or "Success!",
      Font = Theme and Theme.type.fonts.bold or Enum.Font.SourceSansBold,
      TextSize = IS_MOBILE and 14 or 15,
      TextColor3 = UI.ink or Color3.fromRGB(255, 255, 255),
      ZIndex = 900 + 2
    })
  else
    -- Fallback: create a simple text label manually
    successText = Instance.new("TextLabel")
    successText.Size = UDim2.new(1, -16, 1, -16)
    successText.Position = UDim2.new(0, 8, 0, 8)
    successText.Text = message or "Success!"
    successText.Font = Enum.Font.SourceSansBold
    successText.TextSize = IS_MOBILE and 14 or 15
    successText.TextColor3 = Color3.fromRGB(255, 255, 255)
    successText.ZIndex = 900 + 2
    successText.Parent = checkmark
  end
  
  interaction.checkmark = checkmark
  interaction.successText = successText
  
  -- Fade in animation
  TweenService:Create(checkmark, TweenInfo.new(0.25, Enum.EasingStyle.Quad), 
                     { BackgroundTransparency = 0 }):Play()
  
  -- Schedule fade out
  task.delay(duration, function()
    if interaction.checkmark and interaction.checkmark.Parent then
      TweenService:Create(interaction.checkmark, 
                          TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                          { BackgroundTransparency = 1 }):Play()
      
      -- Hide text as well
      if interaction.successText then
        TweenService:Create(interaction.successText,
                           TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                           { TextTransparency = 1 }):Play()
      end
      
      task.delay(0.25, function()
        if interaction.checkmark and interaction.checkmark.Parent then
          interaction.checkmark:Destroy()
          if interaction.successText and interaction.successText.Parent then
            interaction.successText:Destroy()
          end
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
  
  local interaction = {
    type = "error",
    parent = parent,
    message = message or "",
    duration = duration or 2.0,
    errorFrame = nil
  }
  
  -- Create error indicator with fallback colors if Theme is not available
  local errorFrame = Instance.new("Frame")
  errorFrame.Size = UDim2.new(0, 48, 0, 48)
  errorFrame.Position = UDim2.new(0.5, -24, 0.5, -24)
  
  -- Use fallback colors if Theme is not loaded yet
  local bgColor = parent.BackgroundColor3 or Color3.fromRGB(231, 76, 60) -- default red
  errorFrame.BackgroundColor3 = bgColor
  errorFrame.BackgroundTransparency = 1 -- fade in
  errorFrame.ZIndex = 900 + 1  -- fallback Z index
  
  errorFrame.Parent = parent
  
  local corner = Instance.new("UICorner")
  corner.CornerRadius = UDim.new(0, 8)
  corner.Parent = errorFrame
  
  -- Create error text with fallback label creation if makeLabel is not available
  local errorText
  if type(makeLabel) == "function" then
    errorText = makeLabel(errorFrame, {
      Size = UDim2.new(1, -16, 1, -16),
      Position = UDim2.new(0, 8, 0, 8),
      Text = message or "Error!",
      Font = Theme and Theme.type.fonts.bold or Enum.Font.SourceSansBold,
      TextSize = IS_MOBILE and 14 or 15,
      TextColor3 = UI.ink or Color3.fromRGB(255, 255, 255),
      ZIndex = 900 + 2
    })
  else
    -- Fallback: create a simple text label manually
    errorText = Instance.new("TextLabel")
    errorText.Size = UDim2.new(1, -16, 1, -16)
    errorText.Position = UDim2.new(0, 8, 0, 8)
    errorText.Text = message or "Error!"
    errorText.Font = Enum.Font.SourceSansBold
    errorText.TextSize = IS_MOBILE and 14 or 15
    errorText.TextColor3 = Color3.fromRGB(255, 255, 255)
    errorText.ZIndex = 900 + 2
    errorText.Parent = errorFrame
  end
  
  interaction.errorFrame = errorFrame
  interaction.errorText = errorText
  
  -- Fade in animation
  TweenService:Create(errorFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), 
                     { BackgroundTransparency = 0 }):Play()
  
  -- Schedule fade out
  task.delay(duration, function()
    if interaction.errorFrame and interaction.errorFrame.Parent then
      TweenService:Create(interaction.errorFrame, 
                          TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                          { BackgroundTransparency = 1 }):Play()
      
      -- Hide text as well
      if interaction.errorText then
        TweenService:Create(interaction.errorText,
                           TweenInfo.new(0.2, Enum.EasingStyle.Quad),
                           { TextTransparency = 1 }):Play()
      end
      
      task.delay(0.25, function()
        if interaction.errorFrame and interaction.errorFrame.Parent then
          interaction.errorFrame:Destroy()
          if interaction.errorText and interaction.errorText.Parent then
            interaction.errorText:Destroy()
          end
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
- dragMove: Drag and drop with smooth following
--]]

local GestureAnimation = {}
GestureAnimation.__index = GestureAnimation

function GestureAnimation.new(config)
  local self = setmetatable({}, GestureAnimation)
  
  self.config = config or {}
  self.swipeThreshold = config and config.swipeThreshold or 100 -- pixels to trigger dismiss
  self.pullDistance = config and config.pullDistance or 50 -- pixels for refresh
  
  return self
end

function GestureAnimation:enableSwipeDismiss(panel, onDismiss)
  if not panel then
    return false
  end
  
  local lastX, lastY = nil, nil
  local isDragging = false
  local minSwipeDistance = self.swipeThreshold or 100
  
  panel.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
      -- Get initial touch position
      local startPos = input.Position
      
      -- Track movement events to detect swipe direction
      input.Changed:Connect(function(change)
        if change == "Position" and not isDragging then
          local currentPos = input.Position
          
          -- Calculate delta movement
          local deltaX = currentPos.X - lastX or currentPos.X
          local deltaY = lastY - currentPos.Y  -- inverted for Y axis (up is negative)
          
          if math.abs(deltaX) > minSwipeDistance then
            -- Horizontal swipe detected
            if deltaX > 0 then
              -- Swipe right
              if onDismiss then
                onDismiss()
              else
                local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                TweenService:Create(panel, tweenInfo, { 
                  Position = UDim2.new(-1, -panel.Size.X.Offset, 0, 0),
                  Visible = false 
                }):Play()
              end
            elseif deltaX < 0 then
              -- Swipe left
              if onDismiss then
                onDismiss()
              else
                local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
                TweenService:Create(panel, tweenInfo, { 
                  Position = UDim2.new(1, panel.Size.X.Offset, 0, 0),
                  Visible = false 
                }):Play()
              end
            end
          elseif deltaY > minSwipeDistance then
            -- Swipe up detected (dismiss)
            if onDismiss then
              onDismiss()
            else
              local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
              TweenService:Create(panel, tweenInfo, { 
                Position = UDim2.new(0, 0, 0, -panel.Size.Y.Offset),
                Visible = false 
              }):Play()
            end
          elseif deltaY < -minSwipeDistance then
            -- Swipe down (do nothing by default)
          end
          
          lastX, lastY = currentPos.X, currentPos.Y
        end
      end)
    end
  end)
  
  return true
end

function GestureAnimation:enablePullToRefresh(refreshContainer, onRefresh)
  if not refreshContainer then
    return false
  end
  
  local startY = nil
  local isDragging = false
  local lastY = nil
  local minPullDistance = self.pullDistance or 50
  
  -- Track the container's position for visual feedback
  local pullOffset = 0
  
  refreshContainer.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
      -- Start tracking vertical drag
      startY = input.Position.Y
      
      input.Changed:Connect(function(change)
        if change == "Position" and not isDragging then
          local newPos = input.Position.Y
          
          -- Calculate pull distance (negative means pulled up)
          local deltaY = lastY - newPos
          pullOffset = math.max(0, deltaY)  -- only track upward pulls
          
          -- Apply visual feedback for pulling
          if pullOffset > minPullDistance then
            -- Pull far enough, trigger refresh
            if onRefresh then
              onRefresh()
            else
              -- Default: reload content - implement your refresh logic here
            end
            
            -- Reset after a short delay to allow multiple pulls
            task.delay(0.5, function()
              pullOffset = 0
            end)
          end
        elseif change == "Ancestry" then
          -- Container was destroyed, clean up
          isDragging = false
          startY = nil
          lastY = nil
        end
      end)
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

function Transition:fade(element, visible, duration)
  if not element then
    return false
  end
  
  local tweenInfo = TweenInfo.new(duration or self.defaultDuration, 
                                  self.defaultEasing, 
                                  Enum.EasingDirection.Out)
  
  if visible then
    -- Fade in
    TweenService:Create(element, tweenInfo, { 
      BackgroundTransparency = 0,
      TextTransparency = 0 
    }):Play()
    
    return true
  else
    -- Fade out
    TweenService:Create(element, tweenInfo, { 
      BackgroundTransparency = 1,
      TextTransparency = 1 
    }):Play()
    
    return false
  end
end

function Transition:slide(element, direction, duration)
  if not element then
    return false
  end
  
  local offset
  if direction == "left" or direction == "right" then
    offset = UDim2.new(direction == "left", -1, 0, 0) 
          :new(direction == "right", 1, 0, 0)
  else
    offset = UDim2.new(0, 0, direction == "up", -1, 0) 
          :new(direction == "down", 1, 0, 0)
  end
  
  local tweenInfo = TweenInfo.new(duration or self.defaultDuration, 
                                  Enum.EasingStyle.Back, 
                                  Enum.EasingDirection.Out)
  
  TweenService:Create(element, tweenInfo, { Position = offset }):Play()
  
  return true
end

function Transition:scale(element, scaleValue, duration)
  if not element then
    return false
  end
  
  local corner = Instance.new("UIScale")
  corner.Parent = element
  
  local tweenInfo = TweenInfo.new(duration or self.defaultDuration, 
                                  Enum.EasingStyle.Back, 
                                  Enum.EasingDirection.Out)
  
  TweenService:Create(corner, tweenInfo, { Scale = scaleValue }):Play()
  
  return true
end

function Transition:rotate(element, degrees, duration)
  if not element then
    return false
  end
  
  local rotation = Instance.new("UIRotation")
  rotation.Rotation = degrees
  rotation.Parent = element
  
  local tweenInfo = TweenInfo.new(duration or self.defaultDuration, 
                                  Enum.EasingStyle.Quad, 
                                  Enum.EasingDirection.Out)
  
  TweenService:Create(rotation, tweenInfo, { Rotation = degrees }):Play()
  
  return true
end

--[[
=============================================================================
Animation System Factory
=============================================================================

Creates and manages animation instances.
--]]

function AnimationSystem:spring(parent, config)
  local spring = Spring.new(parent, config)
  
  -- Auto-apply to parent if provided
  if parent then
    spring:setProperty(tostring(parent.Size))
  end
  
  return spring
end

function AnimationSystem:press(button, soundId, volume)
  return MicroInteraction:addPress(button, soundId, volume)
end

function AnimationSystem:toggle(switchFrame, label)
  return MicroInteraction:addToggle(switchFrame, label)
end

function AnimationSystem:success(parent, message, duration)
  return MicroInteraction:addSuccess(parent, message, duration)
end

function AnimationSystem:error(parent, message, duration)
  return MicroInteraction:addError(parent, message, duration)
end

function AnimationSystem:swipeDismiss(panel, onDismiss)
  return GestureAnimation:enableSwipeDismiss(panel, onDismiss)
end

function AnimationSystem:pullToRefresh(refreshContainer, onRefresh)
  return GestureAnimation:enablePullToRefresh(refreshContainer, onRefresh)
end

function AnimationSystem:fade(element, visible, duration)
  return Transition:fade(element, visible, duration)
end

function AnimationSystem:slide(element, direction, duration)
  return Transition:slide(element, direction, duration)
end

function AnimationSystem:scale(element, scaleValue, duration)
  return Transition:scale(element, scaleValue, duration)
end

function AnimationSystem:rotate(element, degrees, duration)
  return Transition:rotate(element, degrees, duration)
end

return AnimationSystem
