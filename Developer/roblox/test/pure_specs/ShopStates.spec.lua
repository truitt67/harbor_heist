-- Shop unavailable-state source-contract tests (EPIC 45, harborheist-ux45-workflow-clarity-etj2.2.2).
--
-- Implements docs/UNAVAILABLE_STATE_PATTERN.md §2 (locked-by-prerequisite,
-- maxed) in the shop rows of init.client.lua, which cannot be required
-- under lune. These pins assert: LOCKED rows name the exact prerequisite
-- (recovery path first, description trailing), OWNED keeps the absolute
-- description, the MAXED summary row carries an unambiguous completed-state
-- subtitle, and the green MAXED badge is preserved. Visual confirmation
-- (every track at level 0/mid/max, desktop + mobile) lives in the Studio
-- matrix (etj2.5.2).
--
-- etj2.2.2 contracts ACTIVATED 2026-08-03.

local fs = require("@lune/fs")

local clientSource = fs.readFile("src/client/init.client.lua")
local patternDoc = fs.readFile("docs/UNAVAILABLE_STATE_PATTERN.md")

local function countOccurrences(haystack, needle)
	local n = 0
	local start = 1
	while true do
		local found = haystack:find(needle, start, true)
		if not found then
			break
		end
		n = n + 1
		start = found + 1
	end
	return n
end

return function(describe, it, expect)
describe("etj2.2.2 shop prerequisite + maxed-state contracts", function()
	it("spec harness loads and sources are readable", function()
		expect(#clientSource > 1000).to.equal(true)
		expect(#patternDoc > 500).to.equal(true)
	end)

	describe("locked-by-prerequisite rows (pattern §2)", function()
		it("prerequisiteSubText helper exists and names the exact prior tier", function()
			expect(clientSource:find("local function prerequisiteSubText(entry)", 1, true)).to.be.a("number")
			expect(clientSource:find('return "Requires " .. itemDisplayName(other) .. "  •  " .. itemSubText(entry)', 1, true)).to.be.a("number")
		end)
		it("helper matches the same kind at level - 1 (the exact prerequisite)", function()
			expect(clientSource:find("if other.kind == entry.kind and other.level == entry.level - 1 then", 1, true)).to.be.a("number")
		end)
		it("LOCKED branch renders prerequisite copy, not a bare description", function()
			expect(clientSource:find("entry.subTextLabel.Text = prerequisiteSubText(entry)", 1, true)).to.be.a("number")
		end)
		it("OWNED branch is the ONLY remaining absolute-description assignment", function()
			expect(countOccurrences(clientSource, "entry.subTextLabel.Text = itemSubText(entry)")).to.equal(1)
		end)
		it("pattern doc and code share the locked-by-prerequisite vocabulary", function()
			expect(patternDoc:find("Locked by prerequisite", 1, true)).to.be.a("number")
			expect(patternDoc:find("Requires Steel Rod", 1, true)).to.be.a("number")
		end)
	end)

	describe("maxed tracks (pattern §2)", function()
		it("summary row carries the unambiguous completed-state subtitle", function()
			expect(clientSource:find("Fully upgraded — nothing left to buy in this track.", 1, true)).to.be.a("number")
		end)
		it("MAXED badge stays status.good (achievement color, never disabled-tertiary)", function()
			expect(clientSource:find('Text = "MAXED",\n\t\tFont = Theme.type.fonts.bold,\n\t\tTextSize = Theme.type.sizes.sm,\n\t\tTextColor3 = Theme.color.status.good,', 1, true)).to.be.a("number")
		end)
		it("summary row still replaces the buy button (no inert control to misread)", function()
			expect(countOccurrences(clientSource, "MAXED badge instead of a buy button")).to.equal(1)
		end)
	end)

	describe("decision-point integrity (non-goals preserved)", function()
		it("unaffordable-next-tier stays tappable with the shortfall toast (cl05 exception)", function()
			expect(clientSource:find('Need $%s more for %s', 1, true)).to.be.a("number")
		end)
		it("delta subtext for the purchasable row is intact (a2ug.8)", function()
			expect(clientSource:find("entry.subTextLabel.Text = itemDeltaSubText(entry, currentLevel)", 1, true)).to.be.a("number")
		end)
	end)
end)
end
