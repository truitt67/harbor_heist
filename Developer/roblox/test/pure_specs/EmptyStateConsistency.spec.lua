-- Empty-state consistency across panels (harborheist-3mo7.3.34).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: the bead's original premise was partially stale. By the time
-- this work started, renderEmptyState (the panel-level hero card, kqbq.14)
-- ALREADY existed and inventory/collection/quest panels already used it.
-- The true remaining gaps were:
--   1. The collection panel's MILESTONES subsection rendered a bare
--      "No milestones available." label.
--   2. The bead's "shop filter empty state" is MOOT — no filter mechanism
--      exists; shopRows is static config and always renders all kinds.
--
-- Decision pinned here: subsection empties use a COMPACT row variant
-- (renderEmptyRow) matching the row visual language, NOT the 200-220px
-- hero card which would dwarf the rows around it inside a subsection.
--
-- Pins the contract:
--   1. renderEmptyState (panel-level hero) and renderEmptyRow (subsection
--      compact row) both exist and use Theme tokens.
--   2. Panel-level empties (inventory, collection, quest daily + weekly)
--      route through renderEmptyState.
--   3. The milestones subsection routes through renderEmptyRow — the bare
--      "No milestones available." label is gone.
--   4. renderEmptyRow matches the row visual language (surface.secondary,
--      corners.roomy, stroke 0.9) with an accent icon tile + title +
--      subtitle, all Theme-token driven.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — empty-state consistency contract regressed (harborheist-3mo7.3.34)",
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

	describe("Empty-state consistency (harborheist-3mo7.3.34)", function()
		it("defines both empty-state factories", function()
			has("local function renderEmptyState(parent, cfg)", "panel-level hero factory")
			has("local function renderEmptyRow(parent, cfg)", "subsection compact-row factory")
		end)

		it("panel-level empties route through renderEmptyState", function()
			has("renderEmptyState(inventoryList, {", "inventory empty state")
			has("renderEmptyState(collectionList, {", "collection empty state")
			has("renderEmptyState(questList, {", "quest empty state")
			has('title = "No fish yet"', "inventory title")
			has('title = "No discoveries yet"', "collection title")
			has('title = "No daily quests"', "quest daily title")
			has('title = "No weekly quests"', "quest weekly title")
		end)

		it("milestones subsection uses the compact row, not a bare label", function()
			has("renderEmptyRow(collectionList, {", "milestones empty state")
			has('title = "No milestones yet"', "milestones title")
			has("subtitle = \"Keep catching and discovering", "milestones subtitle")
			-- The bare-label call must be gone (the string survives only in
			-- the explaining comment, so pin the original call shape).
			expect(string.find(src, 'Text = "No milestones available."', 1, true)).to.equal(nil)
		end)

		it("renderEmptyRow matches the row visual language", function()
			has("row.BackgroundColor3 = Theme.color.surface.secondary", "row surface token")
			has("corner(row, Theme.corners.roomy)", "row corner token")
			has("stroke(row, 0.9)", "row stroke matches makeMilestoneRow")
			has("tile.BackgroundColor3 = accent", "accent icon tile")
			has("TextXAlignment = Enum.TextXAlignment.Left", "left-aligned text")
		end)

		it("uses Theme tokens, never bare literals for fonts/sizes/colors", function()
			-- The compact row must read from Theme, not hardcode.
			has("Font = Theme.type.fonts.bold", "title font token")
			has("Font = Theme.type.fonts.body", "subtitle font token")
			has("TextSize = Theme.type.sizes.sm", "title size token")
			has("TextSize = Theme.type.sizes.xs", "subtitle size token")
			has("TextColor3 = Theme.color.text.primary", "title color token")
			has("TextColor3 = Theme.color.text.secondary", "subtitle color token")
		end)

		it("renderEmptyRow is defined AFTER its dependencies", function()
			-- Load-order trap: locals bind at definition site. renderEmptyRow
			-- calls corner/stroke/makeLabel/staggerFadeIn and reads Theme +
			-- IS_MOBILE — all must be defined first.
			local deps = {
				"local function corner(", "local function stroke(",
				"local function makeLabel(", "local function staggerFadeIn(",
				"local Theme = {", "local IS_MOBILE",
			}
			local rowDef = pos("local function renderEmptyRow(parent, cfg)")
			for _, dep in ipairs(deps) do
				expect(pos(dep) < rowDef).to.equal(true)
			end
		end)

		it("renderEmptyRow is defined BEFORE its call site", function()
			local def = pos("local function renderEmptyRow(parent, cfg)")
			local call = pos("renderEmptyRow(collectionList, {")
			expect(def < call).to.equal(true)
		end)
	end)
end
