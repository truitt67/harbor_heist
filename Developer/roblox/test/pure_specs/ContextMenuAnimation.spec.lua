-- Context menu entrance/exit animation contract (harborheist-3mo7.3.40).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: the desktop right-click context menu was the only popup
-- with no animation — it hard-popped via raw .Visible toggles while
-- every other popup (toasts, prompts, panels, banners) animates.
--
-- Design decisions pinned here:
--   * Entrance is a UIScale 0.92→1 (EASE_POP) + fade-in, NOT a Size
--     tween — menu items use absolute Y offsets, so a shrunken frame
--     would leave the bottom items poking past it. UIScale scales items,
--     shadows, and stroke together from the top-left anchor (the click).
--   * Exit is EASE_FAST (0.12s) — dismissals leave faster than they
--     arrive (reveal-card precedent) — fading EVERYTHING out. show()
--     therefore restores every rest value (stroke transparency + per-
--     layer shadow alphas) captured at construction, or the second open
--     renders with ghost transparency.
--   * hide() flips isOpen FIRST and defers Visible=false to the tween's
--     Completed (token + Parent checks) — the outside-click handler and
--     item activation gate on isOpen, and during the wind-down .Visible
--     is still true.
--
-- The bead also shipped a RUNTIME BUGFIX that the investigation found:
-- the constructor called bare applyElevation() ~600 lines ABOVE the
-- local's definition site — the Luau load-order trap (locals bind at
-- definition) — so every desktop context-menu open crashed with
-- "attempt to call a nil value". The fix routes through the design-
-- system export Theme.applyElevation, registered at module load.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — context menu animation contract regressed (harborheist-3mo7.3.40)",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("Context menu animation (harborheist-3mo7.3.40)", function()
		it("entrance scales 0.92→1 with EASE_POP and fades in", function()
			has("self.scale.Scale = 0.92", "entrance seed")
			has("self._entranceScaleTween = TweenService:Create(self.scale, EASE_POP, { Scale = 1 })", "entrance scale tween")
		end)

		it("exit scales back to 0.92 with EASE_FAST and defers the hide", function()
			has("local tween = TweenService:Create(self.scale, EASE_FAST, { Scale = 0.92 })", "exit scale tween")
			has("if self._animToken == token and menuFrame.Parent ~= nil then", "deferred-hide guard")
			has("menuFrame.Visible = false", "deferred hide")
		end)

		it("rest-state alphas are captured at construction and restored on show", function()
			has("self._restStroke = menuStroke.Transparency", "stroke rest capture")
			has("self._restShadowAlpha = {}", "shadow rest capture")
			has("TweenService:Create(menuStroke, EASE_FAST, { Transparency = self._restStroke }):Play()", "stroke rest restore")
		end)

		it("constructor uses the module-load-safe Theme.applyElevation export", function()
			has('Theme.applyElevation(menuFrame, "high")', "design-system export call")
			-- The load-order bug: a bare applyElevation( call ABOVE the
			-- local's definition binds a nil global. Guard the exact shape
			-- (word boundary excludes Theme.applyElevation).
			if string.find(src, "[^.%w_]applyElevation%(menuFrame") then
				error("bare applyElevation(menuFrame...) regressed — Luau load-order trap: the constructor runs before the local is defined (harborheist-3mo7.3.40)")
			end
			expect(true).to.equal(true)
		end)

		it("hide flips isOpen before the animation starts", function()
			-- The outside-click handler gates on isOpen; during the exit
			-- tween .Visible is still true.
			local hidePos = string.find(src, "function self:hide()", 1, true)
			expect(hidePos).to.be.a("number")
			local isOpenFlip = string.find(src, "self.isOpen = false", hidePos, true)
			local tweenStart = string.find(src, "self._hiding = true", hidePos, true)
			expect(isOpenFlip).to.be.a("number")
			expect(tweenStart).to.be.a("number")
			expect(isOpenFlip < tweenStart).to.equal(true)
		end)
	end)
end
