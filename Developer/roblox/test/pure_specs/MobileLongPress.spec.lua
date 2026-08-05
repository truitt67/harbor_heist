-- Mobile long-press gesture + touch-native bottom sheet
-- (harborheist-3mo7.1.2 + harborheist-f0x8).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Pins TWO contracts:
--   1. The long-press gesture (3mo7.1.2): 500ms touch hold on inventory rows,
--      token-based cancellation, row.Parent staleness guard, haptic feedback.
--   2. The bottom sheet (f0x8): mobile must NOT reuse the desktop cursor
--      popup (180px wide, 32px rows — fails 44px touch targets, slide-up
--      anim, backdrop dim, drag-to-dismiss). Instead showMobileActionSheet
--      renders a full-width bottom sheet built from the SAME shared action
--      list as desktop. Also pins the forward-declare ordering that a prior
--      WIP got wrong (closures captured a later-declared `destroy` local as
--      a nil global — Agent Mail msg 1292).
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — mobile long-press/action-sheet contract regressed",
				label))
		end
		expect(true).to.equal(true)
	end

	local function hasNot(literal, label)
		if string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern FOUND in init.client.lua — superseded pattern came back (harborheist-f0x8)",
				label))
		end
	end

	local function pos(literal)
		local p = string.find(src, literal, 1, true)
		if not p then
			error(string.format("ordering check: pattern not found: %s", literal))
		end
		return p
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

		it("long-press opens the touch-native bottom sheet, not the desktop cursor popup", function()
			-- harborheist-f0x8: the mobile branch calls showMobileActionSheet.
			-- The old fallback positioned the desktop popup via viewport math
			-- (viewport.X / 2, viewport.Y - 100) — that path is gone and must
			-- stay gone (it dereffed CurrentCamera and failed touch targets).
			has("showMobileActionSheet(fish)", "sheet invocation in mobile branch")
			hasNot("local y = viewport.Y - 100", "desktop cursor-popup positioning")
			-- createInventoryContextMenu(fish, x, y) may appear ONLY as the
			-- desktop function definition now — a second occurrence means the
			-- mobile branch regressed to the cursor popup.
			local count = 0
			local p = 1
			while true do
				local s = string.find(src, "createInventoryContextMenu(fish, x, y)", p, true)
				if not s then break end
				count = count + 1
				p = s + 1
			end
			expect(count).to.equal(1)
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
			local p = 1
			while true do
				local s = string.find(src, "row.Active = true", p, true)
				if not s then break end
				count = count + 1
				p = s + 1
			end
			expect(count).to.equal(2) -- Once in mobile branch, once in desktop
		end)
	end)

	describe("Mobile action sheet presentation (harborheist-f0x8)", function()
		it("desktop popup and mobile sheet share ONE action list builder", function()
			has("local function buildInventoryContextMenuItems(fish)", "shared builder definition")
			-- Exactly two consumers: createInventoryContextMenu (desktop) and
			-- showMobileActionSheet (mobile). If a third appears, one of the
			-- presentations has forked its own item list — that's drift.
			local count = 0
			local p = 1
			while true do
				local s = string.find(src, "local items = buildInventoryContextMenuItems(fish)", p, true)
				if not s then break end
				count = count + 1
				p = s + 1
			end
			expect(count).to.equal(2)
		end)

		it("sheet rows meet the 44px touch-target minimum", function()
			has("local SHEET_ROW_HEIGHT = 44", "44px row height constant")
			has("rowBtn.Size = UDim2.new(1, 0, 0, SHEET_ROW_HEIGHT)", "rows sized from the constant")
		end)

		it("sheet slides up from below the fold with the easeOut token", function()
			-- Entrance: starts fully below the fold, tweens to the bottom edge.
			has("sheet.Position = UDim2.new(0.5, 0, 1, sheetH)", "start position below the fold")
			has("TweenService:Create(sheet, EASE_OUT, { Position = UDim2.new(0.5, 0, 1, 0) }):Play()", "slide-up entrance")
		end)

		it("backdrop dims the world to 0.45 transparency", function()
			has("sheetBackdrop.ZIndex = 30", "backdrop in the prompts band")
			has("TweenService:Create(sheetBackdrop, EASE_OUT, { BackgroundTransparency = 0.45 }):Play()", "backdrop dim tween")
		end)

		it("drag-to-dismiss commits past 90px and springs back otherwise", function()
			has("local SHEET_DISMISS_DRAG = 90", "dismiss threshold constant")
			has("if dragDy > SHEET_DISMISS_DRAG then", "threshold comparison")
			has("dragSurface.Size = UDim2.new(1, 0, 0, grabZoneH)", "44px drag surface, not just the pill")
		end)

		it("sits in the prompts band (30-32) so toasts and overlays still win", function()
			-- RULE 1: toasts (55+) carry server truth and must never be occluded.
			-- RULE 2: minigame overlays (40-49) render above panels/prompts.
			-- A full-width bottom sheet at ZIndex 150+ would break both — pin
			-- the deliberate band choice.
			has("sheet.ZIndex = 31", "sheet frame band")
			has("rowBtn.ZIndex = 32", "action rows band")
			hasNot("sheet.ZIndex = 151", "sheet must not hijack the toast band")
		end)

		it("declares destroyed/destroy BEFORE any closure that calls destroy()", function()
			-- The bug that forced the prior WIP revert (Agent Mail msg 1292):
			-- the drag/backdrop/row closures captured a `local destroy` declared
			-- AFTER them, i.e. a nil global. Pin the ordering INSIDE the sheet
			-- function: the forward declarations must precede both the first
			-- dismiss closure and the destroyImpl they resolve to. Anchors are
			-- scoped past the sheet definition so makePanel's same-named
			-- dragSurface can't shadow the match.
			local sheetPos = pos("local function showMobileActionSheet(fish)")
			local function posAfter(literal)
				local p = string.find(src, literal, sheetPos, true)
				if not p then
					error(string.format("ordering check: pattern not found after sheet def: %s", literal))
				end
				return p
			end
			local destroyedPos = posAfter("local destroyed = false")
			local destroyDeclPos = posAfter("local destroy\n")
			local firstClosurePos = posAfter("table.insert(dragConns, dragSurface.InputBegan:Connect")
			local implPos = posAfter("local function destroyImpl()")
			expect(destroyedPos < destroyDeclPos).to.equal(true)
			expect(destroyDeclPos < firstClosurePos).to.equal(true)
			expect(destroyDeclPos < implPos).to.equal(true)
		end)

		it("honors the hidePanels cleanup contract via activeContextMenu", function()
			-- hidePanels calls activeContextMenu:destroy() exactly once and does
			-- not know whether a desktop popup or a mobile sheet is open. The
			-- sheet must register the same shape ({ destroy = fn }) so panel
			-- close cleans it up.
			has("activeContextMenu = { destroy = destroyImpl }", "sheet registered under activeContextMenu")
			has("function self:destroy()", "desktop ContextMenu destroy method intact")
		end)

		it("disconnects UserInputService-level drag connections on destroy", function()
			-- TouchMoved/TouchEnded connect to UserInputService, NOT the sheet —
			-- they outlive sheet:Destroy() unless explicitly disconnected (the
			-- connection-leak class-1 pattern).
			has("table.insert(dragConns, UserInputService.TouchMoved:Connect", "TouchMoved tracked")
			has("table.insert(dragConns, UserInputService.TouchEnded:Connect", "TouchEnded tracked")
			has("conn:Disconnect()", "drag connections disconnected in destroyImpl")
		end)
	end)
end
