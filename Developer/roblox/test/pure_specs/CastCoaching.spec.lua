-- Cast coaching source-contract tests (EPIC 45, harborheist-ux45-workflow-clarity-etj2.1.2).
--
-- Implements docs/CAST_COACHING_POLICY.md (etj2.1.1). init.client.lua and
-- FishingService.lua cannot be required under lune (Instance/game and
-- service wiring at top level), so these specs pin the production source
-- invariants: the four approved copy strings (with doc<->code parity),
-- the cadence/suppression structure, the Esc-cancel guard, and the
-- no-persistence decision. Behavioral confirmation lives in the Studio
-- matrix (policy §9; recorded under harborheist-orpl / etj2.5.2).
--
-- etj2.1.2 contracts ACTIVATED 2026-08-03: policy cadence A1/A2 + B1/B2,
-- T5 demonstrated-success suppression, S1/S2 drop rules, session-only state.

local fs = require("@lune/fs")

local clientSource = fs.readFile("src/client/init.client.lua")
local fishingSource = fs.readFile("src/server/FishingService.lua")
local policyDoc = fs.readFile("docs/CAST_COACHING_POLICY.md")
local profileSource = fs.readFile("src/shared/PlayerProfile.lua")
local dataManagerSource = fs.readFile("src/server/DataManager.lua")

local A1 = "The cast bar filled up — tap it before it fills to keep your luck bonus."
local A2 = "Still no luck bonus — one tap on the cast bar before it fills is all it takes."
local B1 = "That tap missed the GOOD band — tap inside it to keep the luck bonus."
local B2 = "The luck bonus needs the GOOD band — watch the marker and tap inside it."

return function(describe, it, expect)
describe("etj2.1.2 cast coaching contracts (docs/CAST_COACHING_POLICY.md)", function()
	it("spec harness loads and sources are readable", function()
		expect(#clientSource > 1000).to.equal(true)
		expect(#fishingSource > 500).to.equal(true)
		expect(#policyDoc > 500).to.equal(true)
	end)

	describe("copy: approved variants present, with doc<->code parity", function()
		it("A1 idle-coach copy in client AND policy doc", function()
			expect(clientSource:find(A1, 1, true)).to.be.a("number")
			expect(policyDoc:find(A1, 1, true)).to.be.a("number")
		end)
		it("A2 reminder copy in client AND policy doc", function()
			expect(clientSource:find(A2, 1, true)).to.be.a("number")
			expect(policyDoc:find(A2, 1, true)).to.be.a("number")
		end)
		it("B1 off-target copy in server AND policy doc", function()
			expect(fishingSource:find(B1, 1, true)).to.be.a("number")
			expect(policyDoc:find(B1, 1, true)).to.be.a("number")
		end)
		it("B2 escalated off-target copy in server AND policy doc", function()
			expect(fishingSource:find(B2, 1, true)).to.be.a("number")
			expect(policyDoc:find(B2, 1, true)).to.be.a("number")
		end)
		it("legacy one-shot string retired everywhere", function()
			expect(clientSource:find("No timing bonus — tap the bar next cast!", 1, true) == nil).to.equal(true)
			expect(fishingSource:find("No timing bonus — tap the bar next cast!", 1, true) == nil).to.equal(true)
		end)
	end)

	describe("Class A (idle cast) client cadence", function()
		it("explicit coaching state record replaces the one-shot boolean", function()
			expect(clientSource:find("local castCoach = {", 1, true)).to.be.a("number")
			expect(clientSource:find("idleCount = 0,", 1, true)).to.be.a("number")
			expect(clientSource:find("timingDemonstrated = false,", 1, true)).to.be.a("number")
			expect(clientSource:find("coachShownIdleCast", 1, true) == nil).to.equal(true)
		end)
		it("A1 fires on the 1st idle cast, A2 on the 4th (bounded repeat)", function()
			expect(clientSource:find("castCoach.idleCount == 1", 1, true)).to.be.a("number")
			expect(clientSource:find("castCoach.idleCount == 4", 1, true)).to.be.a("number")
		end)
		it("coach is dropped without counting when prompt owns attention (S1) or queue is full (S2)", function()
			expect(clientSource:find("if not castCoach.timingDemonstrated\n\t\t\t\tand not onboardingPrompt.Visible\n\t\t\t\tand activeToastCount < maxVisibleToasts()", 1, true)).to.be.a("number")
		end)
	end)

	describe("T5 demonstrated-success suppression", function()
		it("client sets timingDemonstrated on an in-band tap (server-sent bounds)", function()
			expect(clientSource:find("if accuracy >= castHitZone.goodStart_ and accuracy <= castHitZone.goodEnd_ then\n\t\t\tcastCoach.timingDemonstrated = true", 1, true)).to.be.a("number")
		end)
		it("server suppresses off-target coaching after a perfect/good cast", function()
			expect(fishingSource:find('if tier == "perfect" or tier == "good" then\n\t\t\toffTargetCoachCount[player] = CAST_COACH_SUPPRESSED', 1, true)).to.be.a("number")
		end)
	end)

	describe("Class B (off-target) server cadence", function()
		it("session-scoped player-keyed counter with sentinel exists", function()
			expect(fishingSource:find("local CAST_COACH_SUPPRESSED = 99", 1, true)).to.be.a("number")
			expect(fishingSource:find("local offTargetCoachCount = {}", 1, true)).to.be.a("number")
		end)
		it("coaching lives in the tier == ok branch, occurrences 1 and 2 only", function()
			expect(fishingSource:find('elseif tier == "ok" then', 1, true)).to.be.a("number")
			expect(fishingSource:find("local n = (offTargetCoachCount[player] or 0) + 1", 1, true)).to.be.a("number")
			expect(fishingSource:find("if n == 1 then", 1, true)).to.be.a("number")
			expect(fishingSource:find("elseif n == 2 then", 1, true)).to.be.a("number")
		end)
		it("counter is cleared on PlayerRemoving (no Player-instance leak, session reset)", function()
			expect(fishingSource:find("offTargetCoachCount[player] = nil", 1, true)).to.be.a("number")
		end)
	end)

	describe("guards and non-goals", function()
		it("Esc-cancel still clears castAwaitingInput before CancelCast (intentional bail never coaches)", function()
			expect(clientSource:find("castAwaitingInput = false\n\t\t\tstopCastOverlay()\n\t\t\tRemotes.CancelCast:FireServer()", 1, true)).to.be.a("number")
		end)
		it("no coaching state leaks into the persisted profile or DataManager (policy §5)", function()
			expect(profileSource:find("castCoach", 1, true) == nil).to.equal(true)
			expect(profileSource:find("offTargetCoach", 1, true) == nil).to.equal(true)
			expect(dataManagerSource:find("castCoach", 1, true) == nil).to.equal(true)
			expect(dataManagerSource:find("offTargetCoach", 1, true) == nil).to.equal(true)
		end)
		it("bite-minigame coaching copy untouched (classes must not share copy)", function()
			expect(clientSource:find("tap the bar next cast", 1, true) == nil).to.equal(true)
		end)
	end)
end)
end
