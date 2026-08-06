-- Sell/store prompt backdrop + click-outside dismiss (harborheist-3mo7.2.4).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Background: the sellStorePrompt (first-catch comparison prompt) appeared
-- without a backdrop or click-outside dismiss — users had to find the small ✕
-- button to dismiss it. This bead adds a full-screen TextButton backdrop at
-- ZIndex 29 (just below the prompt's 30, above panel content) that dims the
-- world and captures click/touch-outside to dismiss.
--
-- Policy pinned here:
--   * The backdrop is a TextButton (not Frame) so .Activated fires on both
--     MouseButton1 and Touch — no separate InputBegan handler needed (same
--     pattern as the panel backdrop at ~line 3809).
--   * ZIndex 29 sits between panels (25-29) and the prompt (30): the dim
--     covers the HUD/world and any open panel, but the prompt renders above it.
--   * The dim fades to 0.45 (not 0.0 like the panel backdrop) — the comparison
--     prompt is a lighter-weight modal that keeps the game visible.
--   * hide() fades the backdrop out and defers Visible=false via task.delay so
--     the exit fade is visible (Pattern 20/23).
--   * show() seeds BackgroundTransparency = 1 before fading to the dim, so a
--     rapid re-show after a partial hide starts from invisible (not stale-dim).
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — backdrop regressed (harborheist-3mo7.2.4)",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("Sell/store prompt backdrop (harborheist-3mo7.2.4)", function()
		it("backdrop is created as a TextButton named SellStoreBackdrop", function()
			has('local sellStoreBackdrop = Instance.new("TextButton")', "backdrop creation")
			has('sellStoreBackdrop.Name = "SellStoreBackdrop"', "backdrop name")
		end)

		it("backdrop ZIndex is 29 (below prompt 30, above panels)", function()
			-- ZIndex 29: below the prompt (30) so the prompt renders above it,
			-- above panel content (25-29) so the dim covers any open panel.
			has("sellStoreBackdrop.ZIndex = 29", "backdrop ZIndex")
		end)

		it("backdrop is full-screen and starts invisible", function()
			has("sellStoreBackdrop.Size = UDim2.new(1, 0, 1, 0)", "backdrop size")
			has("sellStoreBackdrop.BackgroundTransparency = 1", "backdrop initial transparency")
			has("sellStoreBackdrop.Visible = false", "backdrop initial visibility")
		end)

		it("backdrop AutoButtonColor is false (no flash on tap)", function()
			has("sellStoreBackdrop.AutoButtonColor = false", "autobuttoncolor off")
		end)

		it("click-outside dismiss is wired on backdrop.Activated", function()
			-- The backdrop is a TextButton, so .Activated fires on MouseButton1
			-- AND Touch. The handler gates on sellStorePrompt.Visible so it only
			-- dismisses while the prompt is actually open.
			has("sellStoreBackdrop.Activated:Connect(", "backdrop activated handler")
		end)

		it("hide shows the backdrop fade-out then defers Visible=false", function()
			-- hideSellStorePrompt must fade the backdrop toward transparency 1
			-- and defer sellStoreBackdrop.Visible = false via task.delay so the
			-- exit is animated, not an instant pop-off.
			local hideIdx = string.find(src, "local function hideSellStorePrompt", 1, true)
			expect(hideIdx ~= nil).to.equal(true)
			-- Window from hide function to the next local function (markSellStoreComparisonSeen)
			local nextFunc = string.find(src, "local function markSellStoreComparisonSeen", hideIdx, true)
			local window = string.sub(src, hideIdx, nextFunc)
			expect(string.find(window, "BackgroundTransparency = 1", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "task.delay", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "sellStoreBackdrop.Visible = false", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("show seeds backdrop transparency=1 before fading to dim", function()
			-- showSellStorePrompt must set Visible=true, seed transparency=1,
			-- then tween to the dim constant so a rapid re-show starts clean.
			local showIdx = string.find(src, "local function showSellStorePrompt", 1, true)
			expect(showIdx ~= nil).to.equal(true)
			-- Window from show function to the SERVER_NOTIFIED_REASONS table
			local windowEnd = string.find(src, "SERVER_NOTIFIED_REASONS", showIdx, true)
			local window = string.sub(src, showIdx, windowEnd)
			expect(string.find(window, "sellStoreBackdrop.Visible = true", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "sellStoreBackdrop.BackgroundTransparency = 1", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "SELL_STORE_BACKDROP_DIM", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("dim constant is defined and is 0.45", function()
			-- 0.45 — lighter than the panel backdrop (0.0) because the comparison
			-- prompt is a lighter-weight modal that keeps the game visible.
			has("local SELL_STORE_BACKDROP_DIM = 0.45", "dim constant")
		end)
	end)
end
