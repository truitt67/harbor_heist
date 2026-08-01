-- Desktop action-bar layout source contracts (EPIC 44, harborheist-kqbq.13).
--
-- init.client.lua cannot be required under lune (Instance/game at top
-- level), so these specs assert the production source still contains the
-- ultra-wide rebalance invariants landed by kqbq.13. Pure source contracts
-- only — the "feels anchored" visual confirmation lives in the Studio pass
-- (harborheist-rswb).
--
-- kqbq.13 contracts: layoutDesktopBar caps button width + total bar width
-- above a 1920px threshold so the bottom-center bar stays anchored on
-- ultra-wide viewports instead of floating as a tiny cluster. Standard
-- widths (<= 1920px) are pixel-unchanged (the shrink branch below ~820px
-- and the default BAR_BTN_W between are untouched).

local fs = require("@lune/fs")

local clientSource = fs.readFile("src/client/init.client.lua")

return function(describe, it, expect)
describe("kqbq.13 desktop ultra-wide action-bar rebalance", function()
	it("spec harness loads and client source is readable", function()
		expect(#clientSource > 1000).to.equal(true)
	end)

	it("wide-threshold constant is 1920px", function()
		expect(clientSource:find("local BAR_WIDE_VIEWPORT = 1920", 1, true)).to.be.a("number")
	end)
	it("max button-width bump constant is 12 (100 -> 112)", function()
		expect(clientSource:find("local BAR_WIDE_BTN_BUMP = 12", 1, true)).to.be.a("number")
	end)
	it("bump-step constant is 64px of viewport per +1px button", function()
		expect(clientSource:find("local BAR_WIDE_BUMP_STEP = 64", 1, true)).to.be.a("number")
	end)
	it("bar-width cap fraction is 0.40 (~40% of viewport)", function()
		expect(clientSource:find("local BAR_WIDE_CAP = 0.40", 1, true)).to.be.a("number")
	end)

	it("wide branch triggers strictly above the threshold", function()
		expect(clientSource:find("elseif viewportW > BAR_WIDE_VIEWPORT then", 1, true)).to.be.a("number")
	end)
	it("bump is floored and capped at BAR_WIDE_BTN_BUMP", function()
		expect(clientSource:find("local bump = math.min(BAR_WIDE_BTN_BUMP, math.floor((viewportW - BAR_WIDE_VIEWPORT) / BAR_WIDE_BUMP_STEP))", 1, true)).to.be.a("number")
	end)
	it("button width grows from BAR_BTN_W by the bump", function()
		expect(clientSource:find("btnW = BAR_BTN_W + bump", 1, true)).to.be.a("number")
	end)
	it("cap derives max button width from ~40% of viewport minus gaps", function()
		expect(clientSource:find("local maxByCap = math.floor((BAR_WIDE_CAP * viewportW - (#ACTIONS - 1) * BAR_GAP) / #ACTIONS + 0.5)", 1, true)).to.be.a("number")
	end)
	it("capped button width is the min of bump and cap", function()
		expect(clientSource:find("btnW = math.min(btnW, maxByCap)", 1, true)).to.be.a("number")
	end)

	it("standard-width shrink branch is preserved (pixel-unchanged below ~820px)", function()
		expect(clientSource:find("btnW = math.max(BAR_BTN_W_MIN, math.min(BAR_BTN_W, btnW))", 1, true)).to.be.a("number")
	end)
	it("barWidthFor formula is unchanged (#ACTIONS buttons + gaps)", function()
		expect(clientSource:find("return #ACTIONS * btnW + (#ACTIONS - 1) * BAR_GAP", 1, true)).to.be.a("number")
	end)
end)
end
