-- Overlay-contention recovery source-contract tests (EPIC 45, etj2.3.4).
--
-- The overlay router is a single-slot initiation gate (NOT preemption). Every
-- requestOverlay rejection must (1) leave no state wedged and (2) give the
-- player one concise explanation so it doesn't read as a dead control. This
-- spec pins the rejection-path recovery contracts documented in the bead.

local fs = require("@lune/fs")
local clientSource = fs.readFile("src/client/init.client.lua")

return function(describe, it, expect)
	describe("etj2.3.4 overlay-contention recovery", function()
		describe("cast overlay loses slot to raid", function()
			it("requestOverlay('cast') has an else branch with an explanatory toast", function()
				-- The cast path must NOT silently swallow a failed overlay
				-- acquisition. The player cast, sees waiting dots, but no
				-- timing bar — that reads as a dead control without a message.
				expect(clientSource:find('if requestOverlay("cast") then', 1, true)).to.be.a("number")
				-- The else branch must exist between the cast requestOverlay
				-- and the CastState(false) else branch.
				local castStart = clientSource:find('if requestOverlay("cast") then', 1, true)
				expect(castStart).to.be.a("number")
				local elseBranch = clientSource:find("else", castStart + 1, true)
				expect(elseBranch).to.be.a("number")
				local toast = clientSource:find("Cast timing skipped", elseBranch + 1, true)
				expect(toast).to.be.a("number")
				-- The toast must come BEFORE the CastState(false) else branch.
				local castStateElse = clientSource:find("\telse\n\t\t-- harborheist-njqm", 1, true)
				expect(castStateElse).to.be.a("number")
				expect(toast < castStateElse).to.equal(true)
			end)
			it("reassures the player the cast still resolves (no state unwedge needed)", function()
				-- The message must explain the cast resolves server-side so the
				-- player doesn't think they need to re-cast.
				expect(clientSource:find("cast still resolves", 1, true)).to.be.a("number")
			end)
			it("uses the info severity (not warn/bad — this is an accepted race, not an error)", function()
				local castStart = clientSource:find('if requestOverlay("cast") then', 1, true)
				local elseBranch = clientSource:find("else", castStart + 1, true)
				local castStateElse = clientSource:find("	else\n		-- harborheist-njqm", 1, true)
				local segment = clientSource:sub(elseBranch, castStateElse)
				expect(segment:find("status.info", 1, true)).to.be.a("number")
				expect(segment:find("status.warn", 1, true) == nil).to.equal(true)
				expect(segment:find("status.bad", 1, true) == nil).to.equal(true)
			end)
			it("uses generic phrasing (not raid-specific — slot could be bite or raid)", function()
				-- Fresh-eyes fix: the original toast said "finish your raid first"
				-- but requestOverlay("cast") fails for ANY active overlay (raid OR
				-- bite). If a bite overlay is active, the toast misleads the player.
				-- Generic phrasing ("finish the minigame first") is correct for both.
				local castStart = clientSource:find('if requestOverlay("cast") then', 1, true)
				local elseBranch = clientSource:find("else", castStart + 1, true)
				local castStateElse = clientSource:find("	else\n		-- harborheist-njqm", 1, true)
				local segment = clientSource:sub(elseBranch, castStateElse)
				expect(segment:find("finish the minigame first", 1, true)).to.be.a("number")
				expect(segment:find("finish your raid first", 1, true) == nil).to.equal(true)
			end)
		end)

		describe("bite minigame loses slot", function()
			it("requestOverlay('bite') failure shows an explanatory toast (non-cast case)", function()
				-- The bite path must explain why no minigame appeared.
				local biteFail = clientSource:find('if not requestOverlay("bite") then', 1, true)
				expect(biteFail).to.be.a("number")
				local toast = clientSource:find("A fish bit", biteFail + 1, true)
				expect(toast).to.be.a("number")
			end)
			it("suppresses the bite toast when a cast overlay is active (cast has its own message)", function()
				-- When the cast overlay is active, the cast's own etj2.3.4
				-- message already fires — a second toast would be duplicative.
				local biteFail = clientSource:find('if not requestOverlay("bite") then', 1, true)
				local guard = clientSource:find('if not isOverlayActive("cast") then', biteFail + 1, true)
				expect(guard).to.be.a("number")
			end)
			it("bails before any state mutation (no wedged fishState/minigameActive)", function()
				-- The requestOverlay("bite") check must be BEFORE minigameActive
				-- assignment so a failed acquisition leaves clean state.
				local biteFail = clientSource:find('if not requestOverlay("bite") then', 1, true)
				local minigameActiveSet = clientSource:find("minigameActive = true", biteFail + 1, true)
				expect(minigameActiveSet).to.be.a("number")
				-- The return must be between the check and the assignment.
				local returnLine = clientSource:find("return", biteFail + 1, true)
				expect(returnLine).to.be.a("number")
				expect(returnLine < minigameActiveSet).to.equal(true)
			end)
		end)

		describe("raid loses slot (pre-existing, must remain intact)", function()
			it("requestOverlay('raid') failure resets raidInProgress + shows toast", function()
				-- This path already had recovery before etj2.3.4 — verify it
				-- wasn't broken by the new changes.
				local raidFail = clientSource:find('if not requestOverlay("raid") then', 1, true)
				expect(raidFail).to.be.a("number")
				local reset = clientSource:find("raidInProgress = false", raidFail + 1, true)
				expect(reset).to.be.a("number")
				local toast = clientSource:find("raid attempt was cancelled", raidFail + 1, true)
				expect(toast).to.be.a("number")
			end)
		end)

		describe("panel during overlay (pre-existing, must remain intact)", function()
			it("overlayBlocksPanels shows 'finish the minigame' toast", function()
				expect(clientSource:find("finish the minigame first", 1, true)).to.be.a("number")
			end)
		end)
	end)
end
