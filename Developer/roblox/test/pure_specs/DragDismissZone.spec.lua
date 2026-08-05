-- Expanded drag-to-dismiss zone on bottom-sheet panels (harborheist-3mo7.1.4).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Pins the makePanel mobile drag-to-dismiss contract:
--   1. The draggable zone is a named 80px constant (was a magic 60px) —
--      comfortable thumb reach while staying clear of the content below.
--   2. Gesture-recognition feedback: the grab pill brightens while the
--      finger is down and restores on release.
--   3. Commit haptic: playHaptic("PressEnd") fires BEFORE hidePanels() on a
--      committed dismiss (never after teardown starts).
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — drag-to-dismiss zone contract regressed (harborheist-3mo7.1.4)",
				label))
		end
		expect(true).to.equal(true)
	end

	local function hasNot(literal, label)
		if string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern FOUND in init.client.lua — superseded pattern came back (harborheist-3mo7.1.4)",
				label))
		end
	end

	describe("Expanded drag-to-dismiss zone (harborheist-3mo7.1.4)", function()
		it("uses an 80px named drag zone, not the old magic 60px", function()
			has("local DRAG_DISMISS_ZONE = 80", "80px zone constant")
			has("dragSurface.Size = UDim2.new(1, 0, 0, DRAG_DISMISS_ZONE)", "drag surface sized from the constant")
			-- The old undersized strip must stay gone.
			hasNot("dragSurface.Size = UDim2.new(1, 0, 0, 60)", "60px magic number")
		end)

		it("drag gesture still commits past 90px and springs back otherwise", function()
			-- Threshold unchanged by this bead — the ZONE got bigger, not the
			-- commit distance (a taller grab area must not make dismissal
			-- easier to trigger by accident).
			has("if dragDy > 90 then", "90px commit threshold")
			has("TweenService:Create(panel, EASE_OUT, { Position = UDim2.new(0.5, 0, 1, 0) }):Play()", "spring-back tween")
		end)

		it("confirms gesture recognition via grab-pill opacity", function()
			-- Brightens while the finger is down...
			has("grabber.BackgroundTransparency = 0.25", "pill brightens on drag start")
			-- ...and restores on release (runs on BOTH the commit and
			-- spring-back paths — it precedes the branch).
			has("grabber.BackgroundTransparency = 0.5", "pill restored on release")
			local brighten = string.find(src, "grabber.BackgroundTransparency = 0.25", 1, true)
			local restore = string.find(src, "grabber.BackgroundTransparency = 0.5", brighten, true)
			expect(restore > brighten).to.equal(true)
		end)

		it("fires the commit haptic BEFORE hidePanels() on a committed dismiss", function()
			-- Ordering matters: hidePanels() starts teardown + exit animation;
			-- the haptic must not depend on what that teardown does.
			local threshold = string.find(src, "if dragDy > 90 then", 1, true)
			local haptic = string.find(src, 'playHaptic("PressEnd")', threshold, true)
			local hide = string.find(src, "hidePanels()", haptic, true)
			expect(haptic).to.be.a("number")
			expect(hide).to.be.a("number")
		end)

		it("drag start still requires the panel to be the active one", function()
			has("input.UserInputType == Enum.UserInputType.Touch and activePanel == panel", "active-panel gate")
		end)
	end)
end
