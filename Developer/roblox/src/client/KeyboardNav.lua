--[[
	KeyboardNav.lua - Keyboard navigation system for Harbor Heist
	EPIC 32: Accessibility & Mobile UX
	
	Provides Tab/Shift+Tab navigation through UI elements with visual focus
	indicators. Enter/Space activation is handled natively by the Roblox engine
	via GuiService.SelectedObject — when a registered button is focused, the
	engine fires its Activated signal on Enter/Space. Desktop-only (no-op on
	mobile).
	
	Usage:
		local KeyboardNav = require(script.Parent.KeyboardNav)
		KeyboardNav:Register(button, tabOrder)
		KeyboardNav:Enable()
--]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local KeyboardNav = {}
KeyboardNav.__index = KeyboardNav

-- Configuration
local FOCUS_INDICATOR_THICKNESS = 3
local FOCUS_INDICATOR_COLOR = Color3.fromRGB(56, 152, 255) -- accent blue
local FOCUS_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- State
local focusableElements = {} -- array of {element, tabOrder, stroke}
local currentFocusIndex = 0
local isEnabled = false
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- harborheist-6qps: store the InputBegan connection so Disable() can
-- disconnect it. Without this, each Enable/Disable cycle leaks a connection
-- on UserInputService (the old connection's guard `if not isEnabled then
-- return end` prevents functional issues, but the closure stays in memory).
local inputConnection = nil

--[[
	Register a UI element as focusable via keyboard navigation.
	
	@param element GuiButton - The button or interactive element
	@param tabOrder number - Tab order (lower = earlier in tab cycle)
	@return nil
]]
function KeyboardNav:Register(element, tabOrder, onActivate)
	if isMobile then return end
	if not element or not element:IsA("GuiButton") then
		warn("[KeyboardNav] Cannot register non-GuiButton element")
		return
	end

	-- Check if already registered
	for _, entry in ipairs(focusableElements) do
		if entry.element == element then
			return -- Already registered
		end
	end

	-- Create focus indicator (UIStroke)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 0
	stroke.Color = FOCUS_INDICATOR_COLOR
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = element

	-- Suppress the engine's default selection ring (harborheist-mdzl):
	-- GuiService.SelectedObject shows a blue rectangle around the focused
	-- button. Our UIStroke above already provides the visual indicator, so a
	-- transparent SelectionImageObject prevents a double-ring.
	if not element.SelectionImageObject then
		local blankSelection = Instance.new("ImageLabel")
		blankSelection.Name = "KeyboardNavBlankSelection"
		blankSelection.Image = ""
		blankSelection.BackgroundTransparency = 1
		blankSelection.Size = UDim2.fromScale(1, 1)
		element.SelectionImageObject = blankSelection
	end

	table.insert(focusableElements, {
		element = element,
		tabOrder = tabOrder or #focusableElements + 1,
		stroke = stroke,
		-- harborheist-mdzl: onActivate is retained for backward compat but
		-- is no longer the activation path — GuiService.SelectedObject (set
		-- in ApplyFocus) makes the engine fire Activated on Enter/Space.
		onActivate = type(onActivate) == "function" and onActivate or nil,
	})
	
	-- Sort by tab order
	table.sort(focusableElements, function(a, b)
		return a.tabOrder < b.tabOrder
	end)
	
	-- Clean up when element is destroyed
	element.Destroying:Connect(function()
		self:Unregister(element)
	end)
end

--[[
	Unregister a UI element from keyboard navigation.
	
	@param element GuiButton - The element to unregister
	@return nil
]]
function KeyboardNav:Unregister(element)
	for i, entry in ipairs(focusableElements) do
		if entry.element == element then
			table.remove(focusableElements, i)
			if entry.stroke then
				entry.stroke:Destroy()
			end
			-- Adjust focus index if needed
			if currentFocusIndex >= i then
				currentFocusIndex = math.max(0, currentFocusIndex - 1)
			end
			return
		end
	end
end

--[[
	Move focus to the next element in tab order.
	
	@return nil
]]
function KeyboardNav:FocusNext()
	if #focusableElements == 0 then return end
	
	-- Clear current focus
	self:ClearFocus()
	
	-- Move to next (wrap around)
	currentFocusIndex = (currentFocusIndex % #focusableElements) + 1
	
	-- Apply focus
	self:ApplyFocus()
end

--[[
	Move focus to the previous element in tab order.
	
	@return nil
]]
function KeyboardNav:FocusPrevious()
	if #focusableElements == 0 then return end
	
	-- Clear current focus
	self:ClearFocus()
	
	-- Move to previous (wrap around)
	currentFocusIndex = currentFocusIndex - 1
	if currentFocusIndex < 1 then
		currentFocusIndex = #focusableElements
	end
	
	-- Apply focus
	self:ApplyFocus()
end

--[[
	Activate the currently focused element (simulate click).
	
	@return nil
]]
function KeyboardNav:ActivateFocused()
	if currentFocusIndex < 1 or currentFocusIndex > #focusableElements then
		return
	end
	
	local entry = focusableElements[currentFocusIndex]
	if not (entry and entry.element and entry.element.Active) then
		return
	end

	if entry.onActivate then
		entry.onActivate()
	elseif not entry.warnedNoCallback then
		-- RBXScriptSignal has no script-accessible :Fire() and
		-- VirtualInputManager is RobloxScriptSecurity-locked, so a button
		-- without a registered onActivate callback cannot be activated.
		-- Warn once per element instead of erroring on every keypress.
		entry.warnedNoCallback = true
		warn("[KeyboardNav] No onActivate callback registered for", entry.element.Name)
	end
end

--[[
	Clear focus from all elements.
	
	@return nil
]]
function KeyboardNav:ClearFocus()
	-- harborheist-mdzl: clear engine selection if it points to one of our
	-- registered elements (avoids clobbering selection set by other systems).
	local selected = GuiService.SelectedObject
	for _, entry in ipairs(focusableElements) do
		if entry.stroke then
			TweenService:Create(entry.stroke, FOCUS_TWEEN_INFO, {
				Thickness = 0
			}):Play()
		end
		if entry.element == selected then
			GuiService.SelectedObject = nil
		end
	end
end

--[[
	Apply focus indicator to the currently focused element.
	
	@return nil
]]
function KeyboardNav:ApplyFocus()
	if currentFocusIndex < 1 or currentFocusIndex > #focusableElements then
		return
	end
	
	local entry = focusableElements[currentFocusIndex]
	if entry and entry.stroke then
		TweenService:Create(entry.stroke, FOCUS_TWEEN_INFO, {
			Thickness = FOCUS_INDICATOR_THICKNESS
		}):Play()

		-- harborheist-mdzl: set GuiService.SelectedObject so the engine
		-- natively handles Enter/Space activation (fires the button's
		-- Activated signal). This replaces the removed ActivateFocused
		-- callback approach that required manual wiring at every call site.
		GuiService.SelectedObject = entry.element

		-- Ensure the focused element is visible inside any ancestor
		-- ScrollingFrame (vertical lists).
		local scrollFrame = entry.element:FindFirstAncestorOfClass("ScrollingFrame")
		if scrollFrame then
			local canvasY = scrollFrame.CanvasPosition.Y
			local viewHeight = scrollFrame.AbsoluteWindowSize.Y
			local elementTop = entry.element.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y + canvasY
			local elementBottom = elementTop + entry.element.AbsoluteSize.Y
			if elementTop < canvasY then
				scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, elementTop)
			elseif elementBottom > canvasY + viewHeight then
				scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, elementBottom - viewHeight)
			end
		end
	end
end

--[[
	Enable keyboard navigation (start listening for Tab/Shift+Tab).
	Enter/Space activation is handled natively by the engine via
	GuiService.SelectedObject (see ApplyFocus).
	
	@return nil
]]
function KeyboardNav:Enable()
	if isMobile or isEnabled then return end

	isEnabled = true

	-- harborheist-6qps: disconnect any stale connection before creating a
	-- new one (defensive — Enable is currently called once, but this
	-- prevents a future leak if Enable/Disable cycling is added).
	if inputConnection then
		inputConnection:Disconnect()
	end
	-- Listen for Tab and Shift+Tab (Enter/Space handled natively by engine)
	inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not isEnabled then return end
		if gameProcessed then return end -- Let game handle it first
		
		if input.KeyCode == Enum.KeyCode.Tab then
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				self:FocusPrevious()
			else
				self:FocusNext()
			end
		end
		-- harborheist-mdzl: Enter/Space activation is now handled natively by
		-- the engine via GuiService.SelectedObject (set in ApplyFocus). When
		-- the focused button is SelectedObject, pressing Enter/Space fires
		-- its Activated signal directly — no manual callback wiring needed.
	end)
end

--[[
	Disable keyboard navigation.
	
	@return nil
]]
function KeyboardNav:Disable()
	isEnabled = false
	-- harborheist-6qps: disconnect the input connection on disable so
	-- repeated Enable/Disable cycles don't accumulate idle connections.
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	self:ClearFocus()
	currentFocusIndex = 0
end

--[[
	Get the currently focused element.
	
	@return GuiButton? - The focused element, or nil if none
]]
function KeyboardNav:GetFocusedElement()
	if currentFocusIndex < 1 or currentFocusIndex > #focusableElements then
		return nil
	end
	return focusableElements[currentFocusIndex].element
end

--[[
	Clear all registered elements and reset state.
	
	@return nil
]]
function KeyboardNav:ClearAll()
	local selected = GuiService.SelectedObject
	for _, entry in ipairs(focusableElements) do
		if entry.stroke then
			entry.stroke:Destroy()
		end
		if entry.element == selected then
			GuiService.SelectedObject = nil
		end
	end
	focusableElements = {}
	currentFocusIndex = 0
end

return KeyboardNav
