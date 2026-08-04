-- Mobile long-press gesture for per-fish actions (harborheist-3mo7.1.2).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Pins the mobile long-press gesture contract: inventory rows must detect
-- 500ms touch holds and open the context menu. Desktop right-click must
-- remain functional. The gesture must set row.Active=true, wire both
-- InputBegan (Touch) and InputEnded (Touch) handlers, and check row.Parent
-- to avoid stale fish data after renderInventory rebuild.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — the mobile long-press gesture contract regressed",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("Mobile long-press gesture for per-fish actions (harborheist-3mo7.1.2)", function()
		it("bindInventoryRowContextMenu handles mobile touch with long-press detection", function()
			-- Mobile path: IS_MOBILE branch with touch input detection
			has("if IS_MOBILE then", "mobile branch")
			has("input.UserInputType == Enum.UserInputType.Touch", "touch input type")
			has("isPressed = true", "press flag set")
			has("task.delay(LONG_PRESS_DURATION, function()", "delayed callback")
			has("isPressed = false", "press flag reset")
		end)

		it("long-press duration is 500ms", function()
			has("local LONG_PRESS_DURATION = 0.5", "500ms duration")
		end)

		it("haptic feedback fires on long-press trigger", function()
			has('playHaptic("PressStart")', "haptic feedback")
		end)

		it("context menu opens at bottom of screen on mobile", function()
			has("local viewport = workspace.CurrentCamera.ViewportSize", "viewport calculation")
			has("local x = viewport.X / 2", "center x position")
			has("local y = viewport.Y - 100", "bottom y position")
			has("createInventoryContextMenu(fish, x, y)", "menu creation")
		end)

		it("long-press callback checks row.Parent to avoid stale fish data after renderInventory rebuild", function()
			-- renderInventory rebuilds all rows on every state push (income ticks).
			-- If a state push lands during the 500ms long-press window, the old row
			-- is destroyed and a new one created. The callback must check row.Parent
			-- to bail if the row was destroyed, avoiding a context menu with stale
			-- fish data from the old closure.
			has("if isPressed and myToken == pressToken and row.Parent then", "row.Parent guard in callback")
		end)

		it("uses token-based cancellation to prevent stale callbacks", function()
			-- A quick tap-then-hold sequence could let the first touch's stale
			-- callback fire during the second touch's hold window. The pressToken
			-- generation counter prevents this: each touch increments the token,
			-- and the callback only fires if its captured token still matches.
			has("local pressToken = 0", "token initialization")
			has("pressToken += 1", "token increment")
			has("local myToken = pressToken", "token capture")
			has("myToken == pressToken", "token check in callback")
		end)

		it("InputEnded cancels long-press by resetting flag", function()
			has("row.InputEnded:Connect(function(input)", "input ended handler")
			has("isPressed = false", "cancel flag reset")
		end)

		it("desktop right-click context menu remains functional", function()
			has("input.UserInputType == Enum.UserInputType.MouseButton2", "right-click detection")
			has("createInventoryContextMenu(fish, input.Position.X, input.Position.Y)", "desktop menu creation")
		end)

		it("row.Active is set for both mobile and desktop", function()
			-- row.Active must be true for InputBegan to fire on Frames
			local count = 0
			local pos = 1
			while true do
				local s = string.find(src, "row.Active = true", pos, true)
				if not s then break end
				count = count + 1
				pos = s + 1
			end
			expect(count).to.equal(2) -- Once in mobile branch, once in desktop
		end)
	end)
end
