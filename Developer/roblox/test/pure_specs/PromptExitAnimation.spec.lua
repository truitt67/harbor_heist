-- Prompt exit-animation + corner-radius token contracts
-- (harborheist-3mo7.3.15 / harborheist-3mo7.3.16).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: the two inline prompts (onboarding banner + sell/store
-- comparison) were the LAST modals with asymmetric motion — both entered
-- with a UIScale 0.92→1 EASE_POP but hard-hid via raw Visible=false.
-- Every other popup (panels, banners, context menu, toasts) animated out.
-- The fix adds a shared prompt-exit machinery: scale 1→0.92 (EASE_IN —
-- exits accelerate) + subtree alpha fade, with Visible=false deferred to
-- the tween's Completed and a generation token guarding the deferred hide.
--
-- Design decisions pinned here:
--   * Rest-alpha capture/restore (context-menu precedent, 3mo7.3.40):
--     captureRestAlphas records BackgroundTransparency/TextTransparency/
--     UIStroke.Transparency for the whole subtree AFTER full construction
--     (buttons, stroke, applyElevation shadows); restoreAlphas snaps them
--     back on re-show/cancel or the second open renders as a ghost.
--   * Re-show-during-exit cancel: both show paths call exit.cancel() when
--     .hiding — otherwise the deferred Visible=false would strand the
--     prompt invisible and its entrance gate (Visible==false) would never
--     re-fire. cancel() also snaps UIScale back to 1 (a mid-exit cancel
--     leaves scale < 1).
--   * Evaluator re-show gate: the carried-count gate treats a prompt
--     mid-exit (.Visible still true, exit.hiding) as hidden, or a catch
--     landing in the 0.16s wind-down window would be skipped — the
--     comparison lost because lastCarriedCount already advanced.
--   * 3mo7.3.16: the two sell/store prompt buttons used raw
--     CornerRadius = 10 — the only raw-integer radii in the file.
--     Theme.corners.roomy IS 10; the token keeps the visual identical and
--     restores the token contract.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — prompt exit contract regressed (harborheist-3mo7.3.15/16)",
				label))
		end
		expect(true).to.equal(true)
	end

	local function windowOf(startLiteral, endLiteral)
		local s = string.find(src, startLiteral, 1, true)
		expect(s ~= nil).to.equal(true)
		local e = string.find(src, endLiteral, s, true)
		expect(e ~= nil).to.equal(true)
		return string.sub(src, s, e)
	end

	describe("Prompt exit machinery (harborheist-3mo7.3.15)", function()
		it("makePromptExit builds token/hiding state with deferred hide", function()
			has("local function makePromptExit(prompt)", "machinery definition")
			has("local PROMPT_EXIT_SCALE = 0.92 -- mirrors the entrance seed", "exit scale constant")
			has("local tween = TweenService:Create(scale, EASE_IN, { Scale = PROMPT_EXIT_SCALE })", "exit scale tween")
			has("if exitState.token == token and prompt.Parent ~= nil then", "deferred-hide guard")
			has("if exitState.hiding or not prompt.Visible then", "exit no-op gate")
		end)

		it("rest alphas are captured/restored for the whole subtree", function()
			has("local function captureRestAlphas(root)", "rest capture")
			has("local function restoreAlphas(rest)", "rest restore")
			has("local function fadeAlphasToTransparent(rest, easing)", "subtree fade")
			has("onboardingExit = makePromptExit(onboardingPrompt)", "onboarding wiring")
			has("sellStoreExit = makePromptExit(sellStorePrompt)", "sellStore wiring")
			has("onboardingExit.captureRest()", "onboarding rest capture call")
			has("sellStoreExit.captureRest()", "sellStore rest capture call")
		end)

		it("cancel restores alphas AND snaps scale back to 1", function()
			local window = windowOf("function exitState.cancel()", "function exitState.exit(")
			expect(string.find(window, "restoreAlphas(exitState.rest)", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "scale.Scale = 1", 1, true) ~= nil)
				.to.equal(true)
		end)
	end)

	describe("Hard hides replaced with animated exits (harborheist-3mo7.3.15)", function()
		it("dismissOnboardingPrompt exits via the machinery", function()
			local window = windowOf("local function dismissOnboardingPrompt(stage)", "Sell-vs-store comparison prompt")
			expect(string.find(window, "onboardingExit.exit()", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "onboardingPrompt.Visible = false", 1, true) == nil)
				.to.equal(true)
		end)

		it("hideSellStorePrompt exits via the machinery (backdrop fade kept)", function()
			local window = windowOf("local function hideSellStorePrompt()", "local function markSellStoreComparisonSeen")
			expect(string.find(window, "sellStoreExit.exit()", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "sellStorePrompt.Visible = false", 1, true) == nil)
				.to.equal(true)
			-- The 3mo7.2.4 backdrop fade contract (SellStoreBackdrop.spec)
			-- still holds inside this window.
			expect(string.find(window, "BackgroundTransparency = 1", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "task.delay", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "sellStoreBackdrop.Visible = false", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("the dismiss button uses the animated exit", function()
			local window = windowOf("onboardingDismiss.Activated:Connect(function()", "-- Show a contextual prompt")
			expect(string.find(window, "onboardingExit.exit()", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("the evaluator's three stage-else hides use the animated exit", function()
			-- firstCast conditional hide, zero-carried temporary hide, and
			-- the all-stages-done else all call onboardingExit.exit().
			local count = 0
			for _ in string.gmatch(src, "onboardingExit%.exit%(%)") do
				count = count + 1
			end
			-- dismiss button (1) + dismissOnboardingPrompt (1) + evaluator (3) = 5
			expect(count).to.equal(5)
		end)
	end)

	describe("Re-show-during-exit races (harborheist-3mo7.3.15)", function()
		it("showOnboardingPrompt cancels an in-flight exit", function()
			local window = windowOf("local function showOnboardingPrompt(stage, text, color)", "-- Hide the onboarding prompt")
			expect(string.find(window, "if onboardingExit.hiding then", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "onboardingExit.cancel()", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("showSellStorePrompt cancels an in-flight exit", function()
			local window = windowOf("local function showSellStorePrompt(fish)", "SERVER_NOTIFIED_REASONS")
			expect(string.find(window, "if sellStoreExit.hiding then", 1, true) ~= nil)
				.to.equal(true)
			expect(string.find(window, "sellStoreExit.cancel()", 1, true) ~= nil)
				.to.equal(true)
		end)

		it("the carried-count gate treats a mid-exit prompt as hidden", function()
			has("local sellStoreEffectivelyHidden = not sellStorePrompt.Visible or sellStoreExit.hiding", "effectively-hidden gate")
			has("and sellStoreEffectivelyHidden then", "gate consumption")
		end)
	end)

	describe("Corner-radius token contract (harborheist-3mo7.3.16)", function()
		it("sell/store prompt buttons use Theme.corners.roomy, not raw 10", function()
			local count = 0
			for _ in string.gmatch(src, "CornerRadius = Theme%.corners%.roomy, %-%- harborheist%-3mo7%.3%.16: was raw 10") do
				count = count + 1
			end
			expect(count).to.equal(2)
		end)

		it("no raw CornerRadius = 10 remains anywhere in the client", function()
			local bad = {}
			for line in string.gmatch(src, "[^\n]+") do
				if string.find(line, "CornerRadius = 10,", 1, true) then
					table.insert(bad, line)
				end
			end
			if #bad > 0 then
				error(string.format(
					"raw CornerRadius = 10 regressed (%d site(s)) — use Theme.corners.roomy (harborheist-3mo7.3.16)",
					#bad))
			end
			expect(true).to.equal(true)
		end)
	end)
end
