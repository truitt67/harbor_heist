-- AnimationSystem success/error wiring contract (harborheist-3mo7.3.42).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: AnimationSystem shipped addSuccess/addError/addToggle
-- (EPIC 34) but init.client.lua never called success/error — dead code
-- with no visual feedback on sell/store beyond toasts. This bead wires
-- both micro-interactions (plus haptics) into the three economy actions:
--   * sellStore SELL (SellFish)   — success + error
--   * sellStore STORE (StoreSingleFish) — success + error
--   * aquarium SELL ALL (RequestSellFish) — success + error
--
-- Design decisions pinned here:
--   * showActionFeedback snapshots the anchor's geometry into a
--     screenGui-level host (or fills a panel parent). AnimationSystem
--     parents the indicator INTO the frame you pass — but
--     hideSellStorePrompt() runs in EVERY outcome right after the
--     invoke resolves, so an indicator parented to the prompt would die
--     with it. The host outlives the prompt and self-cleans.
--   * Toasts remain the textual channel (SERVER_NOTIFIED_REASONS dedup
--     preserved); the Anim indicator is the non-verbal one.
--   * addToggle stays UNWIRED: the UI has no toggle-switch surface —
--     raid opt-in is a server-state-driven button (renderRaidOptInButton
--     resets it every render). Forcing addToggle onto it would fight the
--     render loop. Wiring it is a design task, not this bead.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — action feedback wiring regressed (harborheist-3mo7.3.42)",
				label))
		end
		expect(true).to.equal(true)
	end

	local function count(pattern)
		local n = 0
		for _ in string.gmatch(src, pattern) do
			n = n + 1
		end
		return n
	end

	describe("Action feedback wiring (harborheist-3mo7.3.42)", function()
		it("showActionFeedback helper exists with host self-cleanup", function()
			has("local function showActionFeedback(anchor, kind, message, duration, parentOverride)", "helper definition")
			has('host.Name = "ActionFeedbackHost"', "feedback host")
			has("Anim:success(host, message, duration)", "success dispatch")
			has("Anim:error(host, message, duration)", "error dispatch")
		end)

		it("SELL action gives success and error feedback + haptics", function()
			has('showActionFeedback(sellStorePrompt, "success", "Sold!", 1.0)', "sell success")
			has('showActionFeedback(sellStorePrompt, "error", "Can\'t sell", 1.5)', "sell error")
		end)

		it("STORE action gives success and error feedback + haptics", function()
			has('showActionFeedback(sellStorePrompt, "success", "Stored!", 1.0)', "store success")
			has('showActionFeedback(sellStorePrompt, "error", "Can\'t store", 1.5)', "store error")
		end)

		it("SELL ALL gives panel-anchored feedback and captures the result", function()
			has('showActionFeedback(aquariumPanel, "success", "All fish sold!", 1.5, aquariumPanel)', "sell-all success")
			has('showActionFeedback(aquariumPanel, "error", "Can\'t sell", 1.5, aquariumPanel)', "sell-all error")
			-- The result was previously discarded — capture is the contract.
			has("local ok, result = pcall(function()\n\t\t\treturn Remotes.RequestSellFish:InvokeServer()", "sell-all result capture")
		end)

		it("haptics accompany the feedback", function()
			-- 5 error paths (sell x2 incl. pcall-fail, store x2, sell-all)
			-- and 3 success paths.
			expect(count("hapticError%(%)") >= 5).to.equal(true)
			expect(count("hapticSuccess%(%)") >= 3).to.equal(true)
		end)

		it("addToggle remains unwired (no toggle-switch surface exists)", function()
			-- Wiring addToggle onto the server-driven raid opt-in button
			-- would fight renderRaidOptInButton. Guard against a forced
			-- wiring that regresses the opt-in state machine.
			expect(string.find(src, "Anim:toggle(", 1, true) == nil).to.equal(true)
		end)
	end)
end
