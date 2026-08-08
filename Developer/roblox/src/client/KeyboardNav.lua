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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- harborheist-kqbq: source the focus color from the canonical palette instead
-- of a hardcoded RGB (was 56,152,255 — a duplicate of UIPalette.accent that
-- would drift if the palette changed).
local UIPalette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIPalette"))

local KeyboardNav = {}
KeyboardNav.__index = KeyboardNav

-- Configuration
local FOCUS_INDICATOR_THICKNESS = 3
local FOCUS_INDICATOR_COLOR = UIPalette.color("accent")
local FOCUS_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- State
local focusableElements = {} -- array of {element, tabOrder, stroke}
local currentFocusIndex = 0
local isEnabled = false
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- harborheist-3mo7.2.3: Focus trap state for modal panels
local focusTrapActive = false
local trappedElements = {}
-- harborheist-6qps: store the InputBegan connection so Disable() can
-- disconnect it. Without this, each Enable/Disable cycle leaks a connection
-- on UserInputService (the old connection's guard `if not isEnabled then
-- return end` prevents functional issues, but the closure stays in memory).
local inputConnection = nil
-- harborheist-gx6h: same leak-safe pattern for the engine-selection sync
-- connection (visual ring follows GuiService.SelectedObject from ANY path,
-- not just Tab). Stored so Disable() disconnects and re-Enable doesn't stack.
local selectionSyncConnection = nil

-- harborheist-gx6h: single authority for the visual focus ring. Every entry
-- remembers the thickness its stroke was last commanded toward (ringTarget)
-- so repeated calls for the same state are no-ops — this keeps the Tab path,
-- panel auto-focus/restore, and engine gamepad selection from spawning
-- duplicate or conflicting tweens on the same stroke.
local function setRingThickness(entry, thickness)
	if entry.ringTarget == thickness then
		return
	end
	entry.ringTarget = thickness
	if entry.stroke then
		TweenService:Create(entry.stroke, FOCUS_TWEEN_INFO, {
			Thickness = thickness,
		}):Play()
	end
end

-- harborheist-gx6h: extracted from ApplyFocus so non-Tab focus paths (panel
-- auto-focus/restore, gamepad D-pad) also keep the focused element visible
-- inside an ancestor ScrollingFrame's canvas.
local function scrollIntoView(element)
	local scrollFrame = element:FindFirstAncestorOfClass("ScrollingFrame")
	if not scrollFrame then return end
	local canvasY = scrollFrame.CanvasPosition.Y
	local viewHeight = scrollFrame.AbsoluteWindowSize.Y
	local elementTop = element.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y + canvasY
	local elementBottom = elementTop + element.AbsoluteSize.Y
	if elementTop < canvasY then
		scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, elementTop)
	elseif elementBottom > canvasY + viewHeight then
		scrollFrame.CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, elementBottom - viewHeight)
	end
end

-- harborheist-gx6h: render the focus ring from the engine's current
-- selection, whatever set it. Register() suppresses the engine's default
-- ring (KeyboardNavBlankSelection), so without this sync, gamepad D-pad
-- navigation and programmatic focus (panel auto-focus on open, focus restore
-- on close) would leave the user with NO visible focus indicator — a WCAG
-- 2.4.7 violation. Called on every SelectedObject change while enabled.
local function renderSelectionRing()
	local selected = GuiService.SelectedObject
	for _, entry in ipairs(focusableElements) do
		if entry.element == selected then
			setRingThickness(entry, FOCUS_INDICATOR_THICKNESS)
			scrollIntoView(entry.element)
		else
			setRingThickness(entry, 0)
		end
	end
end

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
		-- harborheist-gx6h: last commanded ring thickness (0 = hidden).
		-- setRingThickness no-ops when the target is unchanged, so Tab,
		-- panel auto-focus/restore, and gamepad paths never spawn
		-- duplicate tweens on the same stroke.
		ringTarget = 0,
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
	When focus trap is active, cycles only through trapped elements.
	
	@return nil
]]
function KeyboardNav:FocusNext()
	if focusTrapActive then
		-- Focus trap mode: cycle through trapped elements only
		if #trappedElements == 0 then return end
		
		-- Find current trapped element index
		local currentTrappedIndex = 0
		local selected = GuiService.SelectedObject
		for i, elem in ipairs(trappedElements) do
			if elem == selected then
				currentTrappedIndex = i
				break
			end
		end
		
		-- Move to next (wrap around)
		local nextIndex = (currentTrappedIndex % #trappedElements) + 1
		local nextElement = trappedElements[nextIndex]
		
		-- Clear visual focus from all elements, then apply to next
		self:ClearFocus()
		GuiService.SelectedObject = nextElement
		
		-- Find the next element in focusableElements and apply visual focus
		for i, entry in ipairs(focusableElements) do
			if entry.element == nextElement then
				currentFocusIndex = i
				self:ApplyFocus()
				break
			end
		end
	else
		-- Normal mode: cycle through all focusable elements
		if #focusableElements == 0 then return end
		
		-- Clear current focus
		self:ClearFocus()
		
		-- Move to next (wrap around)
		currentFocusIndex = (currentFocusIndex % #focusableElements) + 1
		
		-- Apply focus
		self:ApplyFocus()
	end
end

--[[
	Move focus to the previous element in tab order.
	When focus trap is active, cycles only through trapped elements.
	
	@return nil
]]
function KeyboardNav:FocusPrevious()
	if focusTrapActive then
		-- Focus trap mode: cycle through trapped elements only
		if #trappedElements == 0 then return end
		
		-- Find current trapped element index
		local currentTrappedIndex = 0
		local selected = GuiService.SelectedObject
		for i, elem in ipairs(trappedElements) do
			if elem == selected then
				currentTrappedIndex = i
				break
			end
		end
		
		-- Move to previous (wrap around)
		local prevIndex = currentTrappedIndex - 1
		if prevIndex < 1 then
			prevIndex = #trappedElements
		end
		local prevElement = trappedElements[prevIndex]
		
		-- Clear visual focus from all elements, then apply to previous
		self:ClearFocus()
		GuiService.SelectedObject = prevElement
		
		-- Find the previous element in focusableElements and apply visual focus
		for i, entry in ipairs(focusableElements) do
			if entry.element == prevElement then
				currentFocusIndex = i
				self:ApplyFocus()
				break
			end
		end
	else
		-- Normal mode: cycle through all focusable elements
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
		-- harborheist-gx6h: route through the ring authority so ringTarget
		-- stays in sync (a direct tween here would leave it stale and break
		-- the duplicate-tween dedupe).
		setRingThickness(entry, 0)
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
		-- harborheist-gx6h: route through the ring authority (dedupe-safe)
		-- instead of creating a tween directly.
		setRingThickness(entry, FOCUS_INDICATOR_THICKNESS)

		-- harborheist-mdzl: set GuiService.SelectedObject so the engine
		-- natively handles Enter/Space activation (fires the button's
		-- Activated signal). This replaces the removed ActivateFocused
		-- callback approach that required manual wiring at every call site.
		GuiService.SelectedObject = entry.element

		-- Ensure the focused element is visible inside any ancestor
		-- ScrollingFrame (vertical lists).
		scrollIntoView(entry.element)
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

	-- harborheist-gx6h: keep the visual ring in sync with the engine's
	-- selection no matter WHO sets it. Tab (ApplyFocus), panel auto-focus on
	-- open and focus restore on close (init.client.lua), and gamepad D-pad
	-- all converge on GuiService.SelectedObject; GetPropertyChangedSignal
	-- fires for every one of them. Without this, Register's blank
	-- SelectionImageObject would leave gamepad/programmatic focus with no
	-- visible indicator at all (WCAG 2.4.7).
	if selectionSyncConnection then
		selectionSyncConnection:Disconnect()
	end
	selectionSyncConnection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(renderSelectionRing)
	-- Defensive: if a selection already exists at enable time, render now —
	-- the property-change signal only fires on FUTURE changes.
	renderSelectionRing()
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
	-- harborheist-gx6h: same for the selection-sync connection.
	if selectionSyncConnection then
		selectionSyncConnection:Disconnect()
		selectionSyncConnection = nil
	end
	self:ClearFocus()
	currentFocusIndex = 0
end

--[[
	Get the currently focused element.

	Prefers the engine's selection (ground truth — it is what receives
	Enter/Space) when it is a registered element, and falls back to the
	Tab-managed index otherwise. This matters for consumers polling on
	Heartbeat (e.g. the keyboard-parity tooltip loop in init.client.lua):
	without engine-first lookup, focus set by panel auto-focus, focus
	restore, or gamepad D-pad would read as stale or "no focus".

	@return GuiButton? - The focused element, or nil if none
]]
function KeyboardNav:GetFocusedElement()
	-- harborheist-gx6h: engine selection wins when it is one of ours —
	-- Tab, panel auto-focus/restore, and gamepad all converge on it.
	local selected = GuiService.SelectedObject
	if selected then
		for _, entry in ipairs(focusableElements) do
			if entry.element == selected then
				return selected
			end
		end
	end
	if currentFocusIndex >= 1 and currentFocusIndex <= #focusableElements then
		return focusableElements[currentFocusIndex].element
	end
	return nil
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

--[[
	Enable focus trap for modal panels.
	When active, Tab/Shift+Tab cycles only through trapped elements.
	
	@param elements table - Array of GuiButton elements to trap focus within
	@return nil
]]
function KeyboardNav:EnableFocusTrap(elements)
	if isMobile then return end
	focusTrapActive = true
	-- Filter elements to only include those that are registered with KeyboardNav
	trappedElements = {}
	for _, elem in ipairs(elements or {}) do
		for _, entry in ipairs(focusableElements) do
			if entry.element == elem then
				table.insert(trappedElements, elem)
				break
			end
		end
	end
	-- Focus the first trapped element and apply visual focus
	if #trappedElements > 0 then
		for i, entry in ipairs(focusableElements) do
			if entry.element == trappedElements[1] then
				self:ClearFocus()
				currentFocusIndex = i
				self:ApplyFocus()
				break
			end
		end
	end
end

--[[
	Disable focus trap, restoring normal Tab navigation.
	
	@return nil
]]
function KeyboardNav:DisableFocusTrap()
	focusTrapActive = false
	trappedElements = {}
end

--[[
	Check if focus trap is currently active.
	
	@return boolean - True if focus trap is active
]]
function KeyboardNav:IsFocusTrapActive()
	return focusTrapActive
end

return KeyboardNav
