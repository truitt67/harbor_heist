-- List padding unified to Theme.spacing tokens (harborheist-3mo7.3.39).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: 7 content-list paddings used raw UDim.new pixel values
-- (6, 8, 14) while Theme.spacing tokens existed. The collection list's
-- 14px matched no token at all. Investigation found an 8th hardcoded
-- list padding the bead missed (the mobile action sheet's row container)
-- — tokenized too so the "no hardcoded list padding remains" criterion
-- actually holds.
--
-- Policy pinned here:
--   * TIGHT lists (sm = 8px): toast stack, help list, action sheet rows —
--     dense/compact content where the tighter gap reads right. Toast and
--     help move 6→8 (a deliberate 2px bump for token alignment; both are
--     low-stakes surfaces).
--   * STANDARD lists (md = 12px): inventory, collection, shop, quest,
--     raid-target — the main content panels. Move 8→12 (collection 14→12)
--     for a consistent, roomier rhythm across all five.
--   * Named layout constants (MOBILE_STACK_PADDING, BAR_GAP) are
--     OUT OF SCOPE — they are deliberate fixed metrics for the action
--     stack and bottom bars, not content-list paddings.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — list padding token contract regressed (harborheist-3mo7.3.39)",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("List padding tokens (harborheist-3mo7.3.39)", function()
		it("tight lists use Theme.spacing.sm", function()
			has("toastLayout.Padding = UDim.new(0, Theme.spacing.sm)", "toast stack")
			has("helpListLayout.Padding = UDim.new(0, Theme.spacing.sm)", "help list")
			has("listLayout.Padding = UDim.new(0, Theme.spacing.sm)", "action sheet rows")
		end)

		it("standard content lists use Theme.spacing.md", function()
			has("inventoryLayout.Padding = UDim.new(0, Theme.spacing.md)", "inventory")
			has("collectionListLayout.Padding = UDim.new(0, Theme.spacing.md)", "collection")
			has("shopLayout.Padding = UDim.new(0, Theme.spacing.md)", "shop")
			has("questLayout.Padding = UDim.new(0, Theme.spacing.md)", "quest")
			has("raidTargetLayout.Padding = UDim.new(0, Theme.spacing.md)", "raid target")
		end)

		it("no hardcoded pixel padding remains on any list layout", function()
			-- Scan for the old shape: <ident>Layout.Padding = UDim.new(0, <digit>).
			-- Catches a regression to raw pixels on ANY *Layout variable.
			local bad = {}
			for name in string.gmatch(src, "([%w_]+Layout)%.Padding = UDim%.new%(0, %d+%)") do
				table.insert(bad, name)
			end
			if #bad > 0 then
				error(string.format(
					"hardcoded list padding regressed on: %s (harborheist-3mo7.3.39)",
					table.concat(bad, ", ")))
			end
			expect(#bad).to.equal(0)
		end)

		it("collection skeleton comment tracks the token, not a stale literal", function()
			has("-- (Padding=Theme.spacing.md) and preserves it.", "skeleton comment")
		end)

		it("the empty-state stack uses a token too (consistency check)", function()
			has("stack.Padding = UDim.new(0, Theme.spacing.sm)", "renderEmptyState stack")
		end)
	end)
end
