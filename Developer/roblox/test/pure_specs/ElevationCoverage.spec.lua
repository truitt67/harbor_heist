-- Elevation coverage for the three remaining floating surfaces
-- (harborheist-3mo7.3.41). Source-scan of src/client/init.client.lua —
-- no Roblox globals — so it runs under lune in the pure bucket.
--
-- Background: applyElevation (harborheist-i39g.1, init.client.lua:1566)
-- fakes depth with layered Shadow_N frames and was already applied to
-- the HUD, carry pill, toasts, panels, tooltip, and context menu. Three
-- prominent surfaces were still flat: the reveal card (hero moment), the
-- sell/store comparison prompt (modal), and the onboarding coaching
-- banner. This bead adds high/medium/low elevation respectively.
--
-- Policy pinned here:
--   * Tier choice follows the surface's narrative weight, not a fixed
--     rule: hero reveal = high (4 layers/16px), modal prompt = medium
--     (3/8px), coaching banner = low (2/4px). All values come from
--     Theme.shadows — the call sites pass ONLY a tier name.
--   * applyElevation's contract (init.client.lua:1558) forbids targets
--     carrying a UIListLayout (it would override the shadow frames'
--     explicit Position). None of the three surfaces has one; their
--     children are manually positioned, so shadows stay put.
--   * The reveal card's shadows are card children, so they inherit the
--     UIScale entrance animation and the dismiss fade loop (which tweens
--     every GuiObject descendant) for free.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — elevation coverage regressed (harborheist-3mo7.3.41)",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("Elevation coverage (harborheist-3mo7.3.41)", function()
		it("reveal card carries high elevation", function()
			has('applyElevation(card, "high")', "reveal card")
		end)

		it("sell/store comparison prompt carries medium elevation", function()
			has('applyElevation(sellStorePrompt, "medium")', "sell/store prompt")
		end)

		it("onboarding coaching banner carries low elevation", function()
			has('applyElevation(onboardingPrompt, "low")', "onboarding prompt")
		end)

		it("every applyElevation call uses a defined Theme.shadows tier", function()
			-- Theme.shadows defines exactly low/medium/high. A call with any
			-- other tier silently falls back to low — catch typos here.
			local valid = { low = true, medium = true, high = true }
			local bad = {}
			for level in string.gmatch(src, 'applyElevation%([^,]+,%s*"([%w_]+)"%)') do
				if not valid[level] then
					table.insert(bad, level)
				end
			end
			if #bad > 0 then
				error(string.format(
					"applyElevation called with undefined tier(s): %s (harborheist-3mo7.3.41)",
					table.concat(bad, ", ")))
			end
			expect(#bad).to.equal(0)
		end)

		it("no elevated surface gains a UIListLayout (shadow contract)", function()
			-- applyElevation's shadow frames use explicit Position; a
			-- UIListLayout parented to the SAME element would override
			-- them. Bounded-window scan: from each element's creation
			-- site, check every UIListLayout created within the next
			-- ~12000 chars (~240 lines, covers each element's full child
			-- block incl. the reveal card's ~187-line constructor) for a
			-- .Parent = <element> assignment within its own
			-- declaration block. A plain file-wide lazy match would span
			-- unrelated sections and false-positive.
			-- fresh-eyes fix: "local card = Instance.new(\"Frame\")" is NOT
			-- unique — renderEmptyState and makeCollectionCard use the same
			-- local name. Anchor on the reveal card's unique .Name instead.
			local checks = {
				{ name = "card", create = 'card.Name = "RevealCard"' },
				{ name = "sellStorePrompt", create = 'local sellStorePrompt = Instance.new("Frame")' },
				{ name = "onboardingPrompt", create = 'local onboardingPrompt = Instance.new("Frame")' },
			}
			for _, c in ipairs(checks) do
				local s = string.find(src, c.create, 1, true)
				if not s then
					error(string.format(
						"%s creation site not found — elevation target moved? (harborheist-3mo7.3.41)",
						c.name))
				end
				local window = string.sub(src, s, s + 12000)
				local pos = 1
				while true do
					local ls = string.find(window, 'Instance.new("UIListLayout")', pos, true)
					if not ls then
						break
					end
					-- A layout's .Parent is set within a few lines of
					-- creation; a 300-char segment is ample.
					local seg = string.sub(window, ls, ls + 300)
					-- %f[^%w_] word boundaries on BOTH sides so "card"
					-- never matches "cardScale", and an unrelated
					-- "<x>.Parent = card" line can't fake a layout parent.
					if string.find(seg, "%f[^%w_]Parent = " .. c.name .. "%f[^%w_]") then
						error(string.format(
							"%s gained a UIListLayout child — breaks applyElevation shadows (harborheist-3mo7.3.41)",
							c.name))
					end
					pos = ls + 1
				end
			end
			expect(true).to.equal(true)
		end)
	end)
end
