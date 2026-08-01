-- Client chrome source-contract tests (EPIC 44, harborheist-kqbq).
--
-- init.client.lua cannot be required under lune (Instance/game at top
-- level), so these specs assert the production source still contains the
-- motion/feedback invariants landed by EPIC 44 children. Pure source
-- contracts only — visual confirmation lives in the Studio passes
-- (harborheist-orpl / harborheist-rswb).
--
-- PENDING CONTRACTS (activate as each child lands):
--   kqbq.1 panel close/open duration harmony:
--     expect 'Anim:slide(panel, "down", 0.22)'          (hidePanels mobile)
--     expect "Anim:scale(panel, fit * 0.9, 0.22)"       (hidePanels desktop)
--     expect 'Anim:slide(oldPanel, "down", 0.22)'       (showPanel switch mobile)
--     expect "Anim:scale(oldPanel, fit * 0.9, 0.22)"    (showPanel switch desktop)
--     expect NO '"down", 0.16' and NO "fit * 0.9, 0.16" remaining
--   NOTE 2026-08-01: the kqbq.1 code edits (4 close-duration hunks) were
--   overwritten in the working tree by a parallel same-identity session
--   writing init.client.lua from a stale buffer (a2ug.8 WIP). Contracts
--   stay commented until the code is re-applied post-coordination.

local fs = require("@lune/fs")

local clientSource = fs.readFile("src/client/init.client.lua")

return function(describe, it, expect)
describe("EPIC 44 client chrome source contracts", function()
	it("spec harness loads and client source is readable", function()
		expect(#clientSource > 1000).to.equal(true)
	end)
end)
end
