-- STORE ALL preview source-contract tests (EPIC 45, harborheist-ux45-workflow-clarity-etj2.2.4).
--
-- Implements docs/STORE_ALL_PREVIEW.md (etj2.2.3). init.client.lua and
-- AquariumService.lua cannot be required under lune, so these pins assert:
-- the capacity-aware label matrix (STORE ALL / STORE %d OF %d / TANK FULL),
-- the progressive-disclosure helper strip, the debounced bulk invoke, the
-- server-side partial-reconciliation copy (single channel), the §15.9
-- converged full-tank string, and the no-optimistic-mutation guarantee.
-- Studio scenarios (empty bag, all fit, exact fit, one slot, full tank,
-- double-tap, raid race, desktop keyboard, mobile touch, panel escape)
-- are recorded under etj2.5.2.
--
-- etj2.2.4 contracts ACTIVATED 2026-08-03.

local fs = require("@lune/fs")

local clientSource = fs.readFile("src/client/init.client.lua")
local aquariumSource = fs.readFile("src/server/AquariumService.lua")
local designDoc = fs.readFile("docs/STORE_ALL_PREVIEW.md")

return function(describe, it, expect)
describe("etj2.2.4 STORE ALL preview + reconciliation contracts", function()
	it("spec harness loads and sources are readable", function()
		expect(#clientSource > 1000).to.equal(true)
		expect(#aquariumSource > 500).to.equal(true)
		expect(#designDoc > 500).to.equal(true)
	end)

	describe("D2 decision-point preview (client)", function()
		it("preview computes from snapshot storedFish + capacity", function()
			expect(clientSource:find("local tankFits = math.max(0, (state.capacity or 0) - #(state.storedFish or {}))", 1, true)).to.be.a("number")
			expect(clientSource:find("local movable = math.min(#carried, tankFits)", 1, true)).to.be.a("number")
		end)
		it("partial state previews the split on the button label", function()
			expect(clientSource:find('invStoreAllBtn.Text = string.format("STORE %d OF %d", movable, #carried)', 1, true)).to.be.a("number")
		end)
		it("zero-fit renders TANK FULL blocked state with the recovery helper", function()
			expect(clientSource:find('invStoreAllBtn.Text = "TANK FULL"', 1, true)).to.be.a("number")
			expect(clientSource:find('invStoreAllHelper.Text = "Sell stored fish to free space."', 1, true)).to.be.a("number")
		end)
		it("helper strip exists, starts hidden (progressive disclosure)", function()
			expect(clientSource:find("local invStoreAllHelper", 1, true)).to.be.a("number")
			expect(clientSource:find("invStoreAllHelper = makeLabel(inventoryContent, {", 1, true)).to.be.a("number")
			expect(clientSource:find("invStoreAllHelper.Visible = false", 1, true)).to.be.a("number")
		end)
		it("partial helper explains moved/remaining with singular grammar", function()
			expect(clientSource:find('"Only %d fit — 1 stays in your bag."', 1, true)).to.be.a("number")
			expect(clientSource:find('"Only %d fit — %d stay in your bag."', 1, true)).to.be.a("number")
		end)
		it("design doc and code share the label vocabulary", function()
			expect(designDoc:find("STORE 2 OF 5", 1, true)).to.be.a("number")
			expect(designDoc:find("TANK FULL", 1, true)).to.be.a("number")
		end)
	end)

	describe("D4 debounced bulk invoke (client)", function()
		it("bulk handler debounces via setButtonEnabled(false) + pcall'd invoke", function()
			expect(clientSource:find("setButtonEnabled(invStoreAllBtn, false)", 1, true)).to.be.a("number")
			expect(clientSource:find("Remotes.RequestStoreFish:InvokeServer()", 1, true)).to.be.a("number")
		end)
		it("fresh-eyes: re-renders from snapshot instead of blind setButtonEnabled(true) restore", function()
			-- A blind restore would fight renderInventory (which re-asserted
			-- capacity-aware state during the InvokeServer yield via the
			-- server's stateSync.push), causing a color/label flicker.
			expect(clientSource:find("setButtonEnabled(invStoreAllBtn, true)", 1, true) == nil).to.equal(true)
			expect(clientSource:find("renderInventory()\nend)", 1, true)).to.be.a("number")
		end)
		it("network-drop path shows the §15.7 recoverable-error shape", function()
			expect(clientSource:find("Couldn't store your fish — try again.", 1, true)).to.be.a("number")
		end)
	end)

	describe("D3 server reconciliation (single channel)", function()
		it("partial store names moved AND remaining with the next step", function()
			expect(aquariumSource:find("Stored %d fish — %d didn't fit. Sell stored fish to free space.", 1, true)).to.be.a("number")
		end)
		it("partial branch is keyed on carried remaining after the move loop", function()
			expect(aquariumSource:find("elseif #session.carried > 0 then", 1, true)).to.be.a("number")
		end)
		it("full-tank copy uses the §15.9 converged form", function()
			expect(aquariumSource:find("Your aquarium is full! Sell some fish first.", 1, true)).to.be.a("number")
			expect(aquariumSource:find('"Your aquarium is full! Sell some fish."', 1, true) == nil).to.equal(true)
		end)
		it("all-fit success copy is unchanged (D1: no churn on the sacred path)", function()
			expect(aquariumSource:find("Stored %d fish. They now earn you cash every second!", 1, true)).to.be.a("number")
		end)
	end)

	describe("trust invariants", function()
		it("client never removes from the snapshot carriedFish (no optimistic mutation)", function()
			expect(clientSource:find("table.remove(state.carriedFish", 1, true) == nil).to.equal(true)
		end)
		it("server still moves only what fits (authoritative capacity loop intact)", function()
			expect(aquariumSource:find("while #session.carried > 0 and #storedFish < capacity do", 1, true)).to.be.a("number")
		end)
	end)
end)
end
