--[[
	KeyboardNav.lua - Keyboard navigation system for Harbor Heist
	EPIC 32: Accessibility & Mobile UX
	
	Provides Tab/Shift+Tab navigation through UI elements, Enter/Space activation,
	and visual focus indicators. Desktop-only (no-op on mobile).
	
	Usage:
		local KeyboardNav = require(script.Parent.KeyboardNav)
		KeyboardNav:Register(button, tabOrder)
		KeyboardNav:Enable()
--]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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

--[[
	Register a UI element as focusable via keyboard navigation.
	
	@param element GuiButton - The button or interactive element
	@param tabOrder number - Tab order (lower = earlier in tab cycle)
	@return nil
]]
function KeyboardNav:Register(element, tabOrder)
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
	
	table.insert(focusableElements, {
		element = element,
		tabOrder = tabOrder or #focusableElements + 1,
		stroke = stroke,
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
	if entry and entry.element and entry.element.Active then
		-- Fire the Activated event
		entry.element.Activated:Fire()
	end
end

--[[
	Clear focus from all elements.
	
	@return nil
]]
function KeyboardNav:ClearFocus()
	for _, entry in ipairs(focusableElements) do
		if entry.stroke then
			TweenService:Create(entry.stroke, FOCUS_TWEEN_INFO, {
				Thickness = 0
			}):Play()
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
		
		-- Ensure element is visible (scroll into view if needed)
		if entry.element.Parent and entry.element:IsA("ScrollingFrame") then
			-- TODO: Implement scroll-into-view for ScrollingFrame children
		end
	end
end

--[[
	Enable keyboard navigation (start listening for Tab/Enter/Space).
	
	@return nil
]]
function KeyboardNav:Enable()
	if isMobile or isEnabled then return end
	
	isEnabled = true
	
	-- Listen for Tab, Shift+Tab, Enter, Space
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not isEnabled then return end
		if gameProcessed then return end -- Let game handle it first
		
		if input.KeyCode == Enum.KeyCode.Tab then
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				self:FocusPrevious()
			else
				self:FocusNext()
			end
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
			self:ActivateFocused()
		end
	end)
end

--[[
	Disable keyboard navigation.
	
	@return nil
]]
function KeyboardNav:Disable()
	isEnabled = false
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
	for _, entry in ipairs(focusableElements) do
		if entry.stroke then
			entry.stroke:Destroy()
		end
	end
	focusableElements = {}
	currentFocusIndex = 0
end

return KeyboardNav
