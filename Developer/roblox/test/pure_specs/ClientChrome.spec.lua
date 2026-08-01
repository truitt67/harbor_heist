-- Client chrome source-contract tests (EPIC 44, harborheist-kqbq).
--
-- init.client.lua cannot be required under lune (Instance/game at top
-- level), so these specs assert the production source still contains the
-- motion/feedback invariants landed by EPIC 44 children. Pure source
-- contracts only — visual confirmation lives in the Studio passes
-- (harborheist-orpl / harborheist-rswb).
--
-- kqbq.1 contracts ACTIVATED 2026-08-01: all four close sites verified at 0.22s.
-- kqbq.2 contracts ACTIVATED 2026-08-01: EASE_PRESS 0.10s, depth 0.94.
-- kqbq.3 contracts ACTIVATED 2026-08-01: EASE_HOVER 0.2s for all hover tweens.

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

	describe("kqbq.2 button press feel", function()
		it("EASE_PRESS preset defined at 0.10s Quad Out", function()
			expect(clientSource:find("EASE_PRESS = TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)", 1, true)).to.be.a("number")
		end)
		it("pressTween uses EASE_PRESS", function()
			expect(clientSource:find("pressTween = EASE_PRESS", 1, true)).to.be.a("number")
		end)
		it("press compression depth is 0.94", function()
			expect(clientSource:find("pressTween, { Scale = 0.94 }", 1, true)).to.be.a("number")
		end)
		it("release still uses EASE_POP (Spring)", function()
			expect(clientSource:find("EASE_POP, { Scale = 1 }", 1, true)).to.be.a("number")
		end)
		it("EASE_PRESS defined exactly once", function()
			local count = 0
			for _ in clientSource:gmatch("EASE_PRESS") do count = count + 1 end
			expect(count).to.equal(2) -- definition + usage at pressTween
		end)
	end)

	describe("kqbq.3 desktop hover pacing", function()
		it("EASE_HOVER preset defined at 0.2s Quad Out", function()
			expect(clientSource:find("EASE_HOVER = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)", 1, true)).to.be.a("number")
		end)
		it("hover scale-up uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { Scale = 1.02 }", 1, true)).to.be.a("number")
		end)
		it("hover color tween uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { BackgroundColor3 = hoverColor }", 1, true)).to.be.a("number")
		end)
		it("hover glow uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { BackgroundTransparency = 0.9 }", 1, true)).to.be.a("number")
		end)
		it("hover shadow fade-in uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { BackgroundTransparency = targetAlpha }", 1, true)).to.be.a("number")
		end)
		it("leave scale-back uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { Scale = 1 }", 1, true)).to.be.a("number")
		end)
		it("leave color restore uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { BackgroundColor3 = originalColor }", 1, true)).to.be.a("number")
		end)
		it("leave glow hide uses EASE_HOVER", function()
			expect(clientSource:find("EASE_HOVER, { BackgroundTransparency = 1 }", 1, true)).to.be.a("number")
		end)
		it("press path does NOT use EASE_HOVER", function()
			expect(clientSource:find("pressTween = EASE_HOVER", 1, true) == nil).to.equal(true)
		end)
	end)
end)
end
