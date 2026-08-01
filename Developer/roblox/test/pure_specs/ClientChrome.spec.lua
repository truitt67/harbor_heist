-- Client chrome source-contract tests (EPIC 44, harborheist-kqbq).
--
-- init.client.lua cannot be required under lune (Instance/game at top
-- level), so these specs assert the production source still contains the
-- motion/feedback invariants landed by EPIC 44 children. Pure source
-- contracts only — visual confirmation lives in the Studio passes
-- (harborheist-orpl / harborheist-rswb).
--
-- kqbq.1 contracts ACTIVATED 2026-08-01: all four close sites verified at 0.22s.
--   kqbq.2 button press feel (EASE_PRESS 0.10s, depth 0.94) — pending
--   kqbq.3 desktop hover pacing (EASE_HOVER 0.2s) — pending

local fs = require("@lune/fs")

local clientSource = fs.readFile("src/client/init.client.lua")

return function(describe, it, expect)
describe("EPIC 44 client chrome source contracts", function()
	it("spec harness loads and client source is readable", function()
		expect(#clientSource > 1000).to.equal(true)
	end)

	describe("kqbq.1 panel close/open duration harmony", function()
		it("hidePanels mobile slides down at 0.22s", function()
			expect(clientSource:find('Anim:slide(panel, "down", 0.22)', 1, true)).to.be.a("number")
		end)
		it("hidePanels desktop scales to 0.9 at 0.22s", function()
			expect(clientSource:find("Anim:scale(panel, fit * 0.9, 0.22)", 1, true)).to.be.a("number")
		end)
		it("showPanel switch mobile slides oldPanel down at 0.22s", function()
			expect(clientSource:find('Anim:slide(oldPanel, "down", 0.22)', 1, true)).to.be.a("number")
		end)
		it("showPanel switch desktop scales oldPanel to 0.9 at 0.22s", function()
			expect(clientSource:find("Anim:scale(oldPanel, fit * 0.9, 0.22)", 1, true)).to.be.a("number")
		end)
		it("no 0.16s close duration remains on slide-down paths", function()
			expect(clientSource:find('"down", 0.16', 1, true) == nil).to.equal(true)
		end)
		it("no 0.16s close duration remains on scale-to-0.9 paths", function()
			expect(clientSource:find("fit * 0.9, 0.16", 1, true) == nil).to.equal(true)
		end)
	end)
end)
end
