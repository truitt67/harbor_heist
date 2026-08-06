-- Context menu keyboard navigation (harborheist-3mo7.2.5).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Background: the ContextMenu class (init.client.lua ~line 896) had no
-- keyboard support. Users couldn't press Esc to close it, use arrow keys to
-- navigate items, or press Enter to activate the focused item. This bead adds
-- all three.
--
-- Policy pinned here:
--   * Self-contained handler — the context menu does NOT register with the
--     global KeyboardNav system (which is designed for persistent panels).
--     Instead, a dedicated _kbConn is connected on show (deferred, same window
--     as the outside-click handler) and disconnected on hide.
--   * Focus highlight uses the SAME visual as mouse hover (BackgroundTransparency
--     = 0 + self.hoverColor) so keyboard and mouse navigation look identical.
--   * Up/Down skip disabled items and wrap at boundaries (standard behavior).
--   * Enter activates the focused item (and hides the menu first, matching the
--     mouse-click activation path at itemBtn.Activated).
--   * Escape closes the menu.
--   * Focus seeds on the first non-disabled item when the menu opens, so the
--     user can immediately press Enter without first navigating.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — keyboard nav regressed (harborheist-3mo7.2.5)",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("Context menu keyboard navigation (harborheist-3mo7.2.5)", function()
		it("Escape key closes the menu", function()
			has("Enum.KeyCode.Escape", "escape key")
		end)

		it("Up arrow key navigates upward", function()
			has("Enum.KeyCode.Up", "up arrow")
		end)

		it("Down arrow key navigates downward", function()
			has("Enum.KeyCode.Down", "down arrow")
		end)

		it("Enter key activates focused item", function()
			has("Enum.KeyCode.Return", "enter key")
		end)

		it("keyboard connection is wired via _kbConn on show", function()
			has("self._kbConn", "kb connection variable")
			has("self._kbConn = UserInputService.InputBegan:Connect", "kb connection wiring")
		end)

		it("keyboard connection is disconnected on hide", function()
			-- hide() must disconnect _kbConn to prevent input leaks after close.
			-- Find the hide() function body and verify it cleans up _kbConn.
			local hideIdx = string.find(src, "function self:hide", 1, true)
			expect(hideIdx ~= nil).to.equal(true)
			local destroyIdx = string.find(src, "function self:destroy", hideIdx, true)
			local window = string.sub(src, hideIdx, destroyIdx)
			expect(string.find(window, "self._kbConn:Disconnect", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "self._kbConn = nil", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("focus highlight uses hoverColor (same visual as mouse hover)", function()
			has("self.hoverColor", "hover color for kb focus")
		end)

		it("focus seeds on first non-disabled item", function()
			-- The deferred block must find the first non-disabled item to seed.
			has("if not item.disabled then", "disabled-skip check")
		end)

		it("navigation wraps at boundaries", function()
			-- Wrapping: idx > count resets to 1, idx < 1 resets to count.
			has("if idx > #self.itemsData then idx = 1 end", "wrap-to-first")
			has("if idx < 1 then idx = #self.itemsData end", "wrap-to-last")
		end)

		it("Enter activation hides menu before calling action (mouse path parity)", function()
			-- The Enter handler must call self:hide() BEFORE item.action(),
			-- matching the mouse-click path (itemBtn.Activated: hide then action).
			local enterBlock = string.find(src, "Enum.KeyCode.Return", 1, true)
			expect(enterBlock ~= nil).to.equal(true)
			-- Window of ~300 chars after the Return check covers the handler body
			local window = string.sub(src, enterBlock, enterBlock + 300)
			local hidePos = string.find(window, "self:hide", 1, true)
			local actionPos = string.find(window, "item.action", 1, true)
			expect(hidePos ~= nil).to.equal(true)
			expect(actionPos ~= nil).to.equal(true)
			expect(hidePos < actionPos).to.equal(true)
		end)

		it("keyboard handler is gated on gameProcessed (no capture of engine input)", function()
			-- The InputBegan handler must check gameProcessed so it doesn't
			-- interfere with engine-level key processing.
			has("if gameProcessed or not self.isOpen then return end", "gameProcessed gate")
		end)
	end)
end
