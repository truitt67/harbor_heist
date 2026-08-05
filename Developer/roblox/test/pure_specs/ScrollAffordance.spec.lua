-- Scroll affordance indicators on content lists (harborheist-3mo7.1.3).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Pins the affordance contract:
--   1. applyScrollAffordance exists and creates top/bottom gradient fades
--      that signal scrollable overflow while idle (auto-hidden scrollbars
--      only appear mid-scroll — kqbq.9).
--   2. Indicators are SIBLINGS of the ScrollingFrame (children scroll with
--      the canvas) and are applied AFTER the list's .Parent assignment
--      (the factory reads .Parent and .ZIndex).
--   3. All 6 scrollable content lists are wired.
--   4. Visibility rides the UIGradient.Transparency NumberSequence tween
--      (frames stay Visible=true; HIDDEN state is fully transparent), using
--      the project motion token — never a bare TweenInfo literal.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — scroll affordance contract regressed (harborheist-3mo7.1.3)",
				label))
		end
		expect(true).to.equal(true)
	end

	local function pos(literal)
		local p = string.find(src, literal, 1, true)
		if not p then
			error(string.format("ordering check: pattern not found: %s", literal))
		end
		return p
	end

	describe("Scroll affordance indicators (harborheist-3mo7.1.3)", function()
		it("defines the factory with the documented constants", function()
			has("local SCROLL_AFFORDANCE_HEIGHT = 24", "24px fade height")
			has("local function applyScrollAffordance(scrollingFrame)", "factory definition")
		end)

		it("creates top and bottom gradient indicators", function()
			has('makeIndicator("ScrollAffordanceTop", "top")', "top indicator")
			has('makeIndicator("ScrollAffordanceBottom", "bottom")', "bottom indicator")
			-- Opaque-at-edge fading into the list, one gradient per edge.
			has("gradient.Rotation = side == \"top\" and 90 or 270", "edge-anchored rotation")
		end)

		it("indicators are siblings of the list, positioned from its UDim", function()
			-- Children of a ScrollingFrame scroll with the canvas — the
			-- factory must parent to the list's Parent, never to the list.
			has("local parent = scrollingFrame.Parent", "reads the list's parent")
			has("indicator.Parent = parent", "parents to the sibling container")
		end)

		it("is applied AFTER each list's Parent assignment (reads .Parent/.ZIndex)", function()
			-- The factory reads scrollingFrame.Parent and .ZIndex at call
			-- time. If called before the list is configured, both are nil/0
			-- and the indicators land in nil-space with ZIndex 1.
			local lists = {
				"inventoryList", "collectionList", "shopList",
				"questList", "raidTargetList", "helpList",
			}
			for _, name in ipairs(lists) do
				local parentPos = pos(name .. ".Parent = ")
				local affordPos = pos("applyScrollAffordance(" .. name .. ")")
				expect(affordPos > parentPos).to.equal(true)
			end
		end)

		it("wires every scrollable content list", function()
			local lists = {
				"applyScrollAffordance(inventoryList)",
				"applyScrollAffordance(collectionList)",
				"applyScrollAffordance(shopList)",
				"applyScrollAffordance(questList)",
				"applyScrollAffordance(raidTargetList)",
				"applyScrollAffordance(helpList)",
			}
			for _, literal in ipairs(lists) do
				has(literal, literal)
			end
		end)

		it("fades via the frame BackgroundTransparency, not frame Visible toggles", function()
			-- The gradient keeps a STATIC transparency shape (opaque at the
			-- anchored edge, fading into the list); the frame's float
			-- BackgroundTransparency is what tweens — the proven TextFadeEdge
			-- pattern. Tweening a gradient's NumberSequence property has no
			-- precedent in this file and would throw inside a scroll handler
			-- if the tween target were rejected.
			has("NumberSequenceKeypoint.new(0, 0)", "visible state keypoint")
			has("NumberSequenceKeypoint.new(1, 1)", "visible state end keypoint")
			has("{ BackgroundTransparency = shown and 0 or 1 }", "frame transparency tween")
			has("indicator.BackgroundTransparency = 1 -- hidden until refresh() shows it", "starts hidden")
		end)

		it("uses the project motion token, not a bare TweenInfo", function()
			has("TweenService:Create(indicator, EASE_FAST,", "EASE_FAST token")
		end)

		it("tracks visibility from canvas overflow and scroll position", function()
			has("local canScroll = canvasH > viewH + 1", "overflow gate")
			has("local showTop = canScroll and scrollY > 1", "top visibility")
			has("local showBottom = canScroll and scrollY < canvasH - viewH - 1", "bottom visibility")
		end)

		it("returns its connections for caller-side disconnect", function()
			-- Same trackability contract as applyScrollbarAutoHide.
			local retPos = pos("return conns\nend\n\n-- TASK 23.2")
			expect(retPos).to.be.a("number")
		end)
	end)
end
