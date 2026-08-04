-- KeyboardNav pure-logic unit tests (harborheist-px6v).
--
-- KeyboardNav.lua has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the core focus-
-- management logic is mirrored as pure Luau functions and exercised
-- against expected behaviour. Source-contract assertions verify that
-- the production code still contains the patterns tested here.
--
-- Covers: tab-order sorting, focus next/previous wrapping, register/
-- unregister index adjustment, ClearAll reset, and the harborheist-mdzl
-- GuiService.SelectedObject activation pattern (source contracts only).

local fs = require("@lune/fs")

return function(describe, it, expect)
	-- ──────────────────────────────────────────────────────────────────
	-- Focus-management logic mirror (must match src/client/KeyboardNav.lua)
	-- ──────────────────────────────────────────────────────────────────

	-- Mirrors the state and pure-logic portions of KeyboardNav.
	-- UI-dependent parts (UIStroke, TweenService, GuiService, UserInputService)
	-- are omitted — only data-structure and index logic is mirrored.
	local function makeNav()
		local focusableElements = {}
		local currentFocusIndex = 0

		local function register(element, tabOrder)
			table.insert(focusableElements, {
				element = element,
				tabOrder = tabOrder or #focusableElements + 1,
			})
			table.sort(focusableElements, function(a, b)
				return a.tabOrder < b.tabOrder
			end)
		end

		local function unregister(element)
			for i, entry in ipairs(focusableElements) do
				if entry.element == element then
					table.remove(focusableElements, i)
					if currentFocusIndex >= i then
						currentFocusIndex = math.max(0, currentFocusIndex - 1)
					end
					return
				end
			end
		end

		local function clearFocus()
			-- Mirror: clears visual indicators (omitted) + index stays
			-- In production ClearFocus does NOT reset currentFocusIndex;
			-- FocusNext/Previous call ClearFocus then set the new index.
		end

		local function focusNext()
			if #focusableElements == 0 then return end
			clearFocus()
			currentFocusIndex = (currentFocusIndex % #focusableElements) + 1
		end

		local function focusPrevious()
			if #focusableElements == 0 then return end
			clearFocus()
			currentFocusIndex = currentFocusIndex - 1
			if currentFocusIndex < 1 then
				currentFocusIndex = #focusableElements
			end
		end

		local function clearAll()
			focusableElements = {}
			currentFocusIndex = 0
		end

		return {
			register = register,
			unregister = unregister,
			focusNext = focusNext,
			focusPrevious = focusPrevious,
			clearAll = clearAll,
			_count = function() return #focusableElements end,
			_index = function() return currentFocusIndex end,
			_elementAt = function(i) return focusableElements[i] and focusableElements[i].element end,
			_tabOrderAt = function(i) return focusableElements[i] and focusableElements[i].tabOrder end,
		}
	end

	-- ──────────────────────────────────────────────────────────────────
	-- Registration and tab ordering
	-- ──────────────────────────────────────────────────────────────────

	describe("Registration and tab ordering", function()
		it("starts empty with zero focus index", function()
			local nav = makeNav()
			expect(nav._count()).to.equal(0)
			expect(nav._index()).to.equal(0)
		end)

		it("registers a single element", function()
			local nav = makeNav()
			nav.register("ButtonA", 1)
			expect(nav._count()).to.equal(1)
			expect(nav._elementAt(1)).to.equal("ButtonA")
		end)

		it("sorts elements by tabOrder on insert", function()
			local nav = makeNav()
			nav.register("ButtonC", 3)
			nav.register("ButtonA", 1)
			nav.register("ButtonB", 2)
			expect(nav._elementAt(1)).to.equal("ButtonA")
			expect(nav._elementAt(2)).to.equal("ButtonB")
			expect(nav._elementAt(3)).to.equal("ButtonC")
		end)

		it("assigns implicit tabOrder when not provided", function()
			local nav = makeNav()
			nav.register("First")
			nav.register("Second")
			nav.register("Third")
			expect(nav._tabOrderAt(1)).to.equal(1)
			expect(nav._tabOrderAt(2)).to.equal(2)
			expect(nav._tabOrderAt(3)).to.equal(3)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Focus next (Tab)
	-- ──────────────────────────────────────────────────────────────────

	describe("FocusNext (Tab)", function()
		it("does nothing when empty", function()
			local nav = makeNav()
			nav.focusNext()
			expect(nav._index()).to.equal(0)
		end)

		it("moves from 0 to 1 on first Tab", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.focusNext()
			expect(nav._index()).to.equal(1)
		end)

		it("wraps from last to first", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			nav.focusNext() -- 1
			nav.focusNext() -- 2
			nav.focusNext() -- 3
			nav.focusNext() -- wrap to 1
			expect(nav._index()).to.equal(1)
		end)

		it("cycles through all elements in tab order", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			local visited = {}
			for _ = 1, 3 do
				nav.focusNext()
				visited[#visited + 1] = nav._elementAt(nav._index())
			end
			expect(visited[1]).to.equal("A")
			expect(visited[2]).to.equal("B")
			expect(visited[3]).to.equal("C")
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Focus previous (Shift+Tab)
	-- ──────────────────────────────────────────────────────────────────

	describe("FocusPrevious (Shift+Tab)", function()
		it("does nothing when empty", function()
			local nav = makeNav()
			nav.focusPrevious()
			expect(nav._index()).to.equal(0)
		end)

		it("wraps from 0 to last on first Shift+Tab", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			nav.focusPrevious()
			expect(nav._index()).to.equal(3)
		end)

		it("wraps from first to last", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.focusNext() -- index = 1
			nav.focusPrevious() -- wrap to 2
			expect(nav._index()).to.equal(2)
		end)

		it("cycles backwards through all elements", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			local visited = {}
			for _ = 1, 3 do
				nav.focusPrevious()
				visited[#visited + 1] = nav._elementAt(nav._index())
			end
			expect(visited[1]).to.equal("C")
			expect(visited[2]).to.equal("B")
			expect(visited[3]).to.equal("A")
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Unregister and index adjustment
	-- ──────────────────────────────────────────────────────────────────

	describe("Unregister", function()
		it("removes the specified element", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			nav.unregister("B")
			expect(nav._count()).to.equal(2)
			expect(nav._elementAt(1)).to.equal("A")
			expect(nav._elementAt(2)).to.equal("C")
		end)

		it("decrements focus index when removing at or before current", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			nav.focusNext() -- index = 1 (A)
			nav.focusNext() -- index = 2 (B)
			nav.unregister("A") -- removes index 1, decrements currentFocusIndex
			expect(nav._index()).to.equal(1)
			expect(nav._elementAt(nav._index())).to.equal("B")
		end)

		it("does not change focus index when removing after current", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.register("C", 3)
			nav.focusNext() -- index = 1 (A)
			nav.unregister("C") -- removes index 3, after current
			expect(nav._index()).to.equal(1)
		end)

		it("is a no-op for unknown element", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.unregister("Nonexistent")
			expect(nav._count()).to.equal(1)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- ClearAll
	-- ──────────────────────────────────────────────────────────────────

	describe("ClearAll", function()
		it("removes all elements and resets index", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.register("B", 2)
			nav.focusNext() -- index = 1
			nav.clearAll()
			expect(nav._count()).to.equal(0)
			expect(nav._index()).to.equal(0)
		end)

		it("allows re-registration after clear", function()
			local nav = makeNav()
			nav.register("A", 1)
			nav.clearAll()
			nav.register("X", 10)
			expect(nav._count()).to.equal(1)
			expect(nav._elementAt(1)).to.equal("X")
			nav.focusNext()
			expect(nav._index()).to.equal(1)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract verification (harborheist-mdzl patterns)
	-- ──────────────────────────────────────────────────────────────────

	local navSource = fs.readFile("src/client/KeyboardNav.lua")

	describe("Source contract: module structure", function()
		it("imports GuiService", function()
			expect(navSource:find('local GuiService = game:GetService("GuiService")', 1, true)).to.be.a("number")
		end)

		it("imports UserInputService", function()
			expect(navSource:find('local UserInputService = game:GetService("UserInputService")', 1, true)).to.be.a("number")
		end)

		it("imports TweenService", function()
			expect(navSource:find('local TweenService = game:GetService("TweenService")', 1, true)).to.be.a("number")
		end)

		it("exposes Register method", function()
			expect(navSource:find("function KeyboardNav:Register(", 1, true)).to.be.a("number")
		end)

		it("exposes Unregister method", function()
			expect(navSource:find("function KeyboardNav:Unregister(", 1, true)).to.be.a("number")
		end)

		it("exposes FocusNext method", function()
			expect(navSource:find("function KeyboardNav:FocusNext()", 1, true)).to.be.a("number")
		end)

		it("exposes FocusPrevious method", function()
			expect(navSource:find("function KeyboardNav:FocusPrevious()", 1, true)).to.be.a("number")
		end)

		it("exposes ClearAll method", function()
			expect(navSource:find("function KeyboardNav:ClearAll()", 1, true)).to.be.a("number")
		end)
	end)

	describe("Source contract: harborheist-mdzl (native Enter/Space via GuiService.SelectedObject)", function()
		it("ApplyFocus sets GuiService.SelectedObject to the focused element", function()
			expect(navSource:find("GuiService.SelectedObject = entry.element", 1, true)).to.be.a("number")
		end)

		it("ClearFocus clears GuiService.SelectedObject when it matches a registered element", function()
			expect(navSource:find("GuiService.SelectedObject = nil", 1, true)).to.be.a("number")
		end)

		it("Register sets a blank SelectionImageObject to suppress engine ring", function()
			expect(navSource:find("KeyboardNavBlankSelection", 1, true)).to.be.a("number")
		end)

		it("Enable does NOT manually handle Return/Space keys", function()
			-- The old code had: elseif input.KeyCode == Enum.KeyCode.Return or ...
			-- This should no longer exist inside the Enable function's InputBegan handler.
			local enableStart = navSource:find("function KeyboardNav:Enable()", 1, true)
			expect(enableStart).to.be.a("number")
			local disableStart = navSource:find("function KeyboardNav:Disable()", 1, true)
			expect(disableStart).to.be.a("number")
			local enableBlock = navSource:sub(enableStart, disableStart)
			local hasReturnHandler = enableBlock:find("Enum.KeyCode.Return", 1, true)
			expect(hasReturnHandler).to.equal(nil)
		end)

		it("ActivateFocused is retained for backward compatibility", function()
			expect(navSource:find("function KeyboardNav:ActivateFocused()", 1, true)).to.be.a("number")
		end)

		it("Disable disconnects the input connection (6qps)", function()
			expect(navSource:find("inputConnection:Disconnect()", 1, true)).to.be.a("number")
		end)

		it("Enable stores the input connection before Connect (6qps)", function()
			expect(navSource:find("inputConnection = UserInputService.InputBegan:Connect", 1, true)).to.be.a("number")
		end)
	end)

	-- harborheist-3mo7.2.1: source contract for shop/inventory button registration
	local clientSource = fs.readFile("src/client/init.client.lua")

	describe("Source contract: harborheist-3mo7.2.1 (shop/inventory keyboard nav)", function()
		it("registers shop BUY buttons with KeyboardNav", function()
			-- Shop buy buttons are created in buildShopRow, stored in shopRows[key].buyButton
			-- Registration happens after the SHOP_CATALOG loop
			expect(clientSource:find("KeyboardNav:Register(row.buyButton", 1, true)).to.be.a("number")
		end)

		it("registers inventory SELL buttons with KeyboardNav", function()
			-- Per-fish sellBtn created in renderInventory loop
			expect(clientSource:find("KeyboardNav:Register(sellBtn", 1, true)).to.be.a("number")
		end)

		it("registers inventory STORE buttons with KeyboardNav", function()
			-- Per-fish storeBtn created in renderInventory loop
			expect(clientSource:find("KeyboardNav:Register(storeBtn", 1, true)).to.be.a("number")
		end)

		it("uses tab order 1000+ for inventory row buttons", function()
			-- Inventory buttons use 1000+i*2 pattern to place after static HUD buttons
			expect(clientSource:find("1000 + i * 2", 1, true)).to.be.a("number")
		end)

		it("uses tab order 2000+ for shop buy buttons", function()
			-- Shop buttons use 2000+ to place after inventory row buttons
			expect(clientSource:find("local shopTabOrder = 2000", 1, true)).to.be.a("number")
		end)
	end)

	-- harborheist-3mo7.2.2: source contract for panel focus management
	describe("Source contract: harborheist-3mo7.2.2 (panel focus management)", function()
		it("declares previousFocusElement variable", function()
			-- Track focus before panel opens so we can restore it on close
			expect(clientSource:find("local previousFocusElement = nil", 1, true)).to.be.a("number")
		end)

		it("defines findFirstFocusableElement helper", function()
			-- Helper to find the first focusable GuiButton in a panel
			expect(clientSource:find("local function findFirstFocusableElement(container)", 1, true)).to.be.a("number")
		end)

		it("saves focus before opening panel", function()
			-- Save current focus when opening a panel
			expect(clientSource:find("previousFocusElement = GuiService.SelectedObject", 1, true)).to.be.a("number")
		end)

		it("focuses first element in panel on open", function()
			-- Move focus to first focusable element when panel opens
			expect(clientSource:find("local firstFocusable = findFirstFocusableElement(panel)", 1, true)).to.be.a("number")
			expect(clientSource:find("GuiService.SelectedObject = firstFocusable", 1, true)).to.be.a("number")
		end)

		it("restores focus when panel closes", function()
			-- Restore previous focus when panel closes
			expect(clientSource:find("if previousFocusElement and previousFocusElement.Parent then", 1, true)).to.be.a("number")
		end)

		it("clears previousFocusElement after restore", function()
			-- Reset the saved focus after restoring
			expect(clientSource:find("previousFocusElement = nil", 1, true)).to.be.a("number")
		end)
	end)

	-- harborheist-3mo7.1.1: source contract for iOS safe-area handling
	describe("Source contract: harborheist-3mo7.1.1 (iOS safe-area handling)", function()
		it("defines calculateSafeBottom function", function()
			-- Calculate bottom safe area for iOS home indicator
			expect(clientSource:find("local function calculateSafeBottom()", 1, true)).to.be.a("number")
		end)

		it("declares SAFE_BOTTOM variable", function()
			-- Mutable bottom safe area, recalculated on orientation change
			expect(clientSource:find("local SAFE_BOTTOM = calculateSafeBottom()", 1, true)).to.be.a("number")
		end)

		it("defines getMobileStackBottom function", function()
			-- Dynamic bottom offset replacing hardcoded MOBILE_STACK_BOTTOM
			expect(clientSource:find("local function getMobileStackBottom()", 1, true)).to.be.a("number")
		end)

		it("registers mobile stack with safeTopConsumers", function()
			-- Mobile stack repositions on orientation change
			expect(clientSource:find("table.insert(safeTopConsumers, function()", 1, true)).to.be.a("number")
			expect(clientSource:find("stack.Position = UDim2.new(1, -12, 1, -getMobileStackBottom())", 1, true)).to.be.a("number")
		end)

		it("replaces MOBILE_STACK_BOTTOM with getMobileStackBottom()", function()
			-- All references use dynamic function instead of hardcoded constant
			expect(clientSource:find("getMobileStackBottom()", 1, true)).to.be.a("number")
			-- Verify no remaining references to old constant (except in comments)
			local moibleStackBottomCount = 0
			for _ in clientSource:gmatch("MOBILE_STACK_BOTTOM") do
				moibleStackBottomCount = moibleStackBottomCount + 1
			end
			-- Should only appear in comments (2 occurrences)
			expect(moibleStackBottomCount).to.equal(2)
		end)

		it("uses iOS home indicator heuristic", function()
			-- Heuristic: if inset.Y > 20, assume 34px home indicator
			expect(clientSource:find("if IS_MOBILE and inset.Y and inset.Y > 20 then", 1, true)).to.be.a("number")
			expect(clientSource:find("baseBottom = math.max(baseBottom, 34)", 1, true)).to.be.a("number")
		end)
	end)

	-- harborheist-3mo7.2.3: source contract for focus trapping
	describe("Source contract: harborheist-3mo7.2.3 (focus trapping)", function()
		it("declares focusTrapActive state variable", function()
			expect(navSource:find("local focusTrapActive = false", 1, true)).to.be.a("number")
		end)

		it("declares trappedElements state variable", function()
			expect(navSource:find("local trappedElements = {}", 1, true)).to.be.a("number")
		end)

		it("exposes EnableFocusTrap method", function()
			expect(navSource:find("function KeyboardNav:EnableFocusTrap(", 1, true)).to.be.a("number")
		end)

		it("exposes DisableFocusTrap method", function()
			expect(navSource:find("function KeyboardNav:DisableFocusTrap()", 1, true)).to.be.a("number")
		end)

		it("FocusNext respects focus trap", function()
			expect(navSource:find("if focusTrapActive then", 1, true)).to.be.a("number")
		end)

		it("FocusPrevious respects focus trap", function()
			-- Both FocusNext and FocusPrevious should check focusTrapActive
			local count = 0
			for _ in navSource:gmatch("if focusTrapActive then") do
				count = count + 1
			end
			expect(count >= 2).to.equal(true)
		end)

		it("showPanel enables focus trap", function()
			expect(clientSource:find("KeyboardNav:EnableFocusTrap(", 1, true)).to.be.a("number")
		end)

		it("hidePanels disables focus trap", function()
			expect(clientSource:find("KeyboardNav:DisableFocusTrap()", 1, true)).to.be.a("number")
		end)
	end)
end
