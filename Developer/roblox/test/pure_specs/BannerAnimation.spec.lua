-- Banner entrance/exit animation contract (harborheist-3mo7.3.38).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: the raid banner and the DataStore-degraded banner were the
-- last two surfaces that hard-popped via raw .Visible toggles; every
-- other popup (toasts, prompts, panels) animates. This bead gives both
-- a slide-down/fade entrance (EASE_OUT) and slide-up/fade exit (EASE_IN)
-- via a shared animateBanner helper.
--
-- The contract this spec pins is less about the tween and more about the
-- CALL SITES, because both are hot paths:
--   * render() runs on EVERY state push and drives dataStoreBanner.
--   * updateRaidCountdown() runs every second from the countdown ticker
--     and drives raidBanner.
-- A naive gate on banner.Visible would replay the entrance every tick —
-- and, worse, during the exit tween .Visible stays true (it is deferred
-- to the tween's Completed callback so the wind-down renders), so a
-- .Visible gate would also replay the hide AND the "Saving restored"
-- toast every push. Both sites therefore gate on intended-state flags
-- (raidBannerShown / dataStoreBannerShown).
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — banner animation contract regressed (harborheist-3mo7.3.38)",
				label))
		end
		expect(true).to.equal(true)
	end

	describe("Banner animations (harborheist-3mo7.3.38)", function()
		it("shared animateBanner helper exists", function()
			has("local function animateBanner(banner, key, restFn, show)", "helper definition")
		end)

		it("entrance uses EASE_OUT and exit uses EASE_IN", function()
			has("TweenService:Create(banner, EASE_OUT, {", "entrance easing")
			has("local tween = TweenService:Create(banner, EASE_IN, {", "exit easing")
		end)

		it("exit defers Visible=false to the tween completion", function()
			has("if bannerAnimTokens[key] == token then", "supersede token gate")
			has("banner.Visible = false", "deferred hide")
		end)

		it("raid banner call site is flag-gated, not .Visible-gated", function()
			has("if not raidBannerShown then", "entrance flag")
			has('animateBanner(raidBanner, "raid", raidBannerRest, true)', "entrance call")
			has('animateBanner(raidBanner, "raid", raidBannerRest, false)', "exit call")
			-- No raw show-toggle may remain — the initial declaration
			-- (raidBanner.Visible = false) is the ONLY legitimate one.
			if string.find(src, "raidBanner.Visible = true", 1, true) then
				error("raidBanner.Visible = true regressed — bypasses the entrance animation (harborheist-3mo7.3.38)")
			end
			expect(true).to.equal(true)
		end)

		it("dataStore banner call site is flag-gated, not .Visible-gated", function()
			has("if not dataStoreBannerShown then", "entrance flag")
			has('animateBanner(dataStoreBanner, "dataStore", dataStoreBannerRest, true)', "entrance call")
			has('animateBanner(dataStoreBanner, "dataStore", dataStoreBannerRest, false)', "exit call")
			if string.find(src, "dataStoreBanner.Visible = true", 1, true) then
				error("dataStoreBanner.Visible = true regressed — bypasses the entrance animation (harborheist-3mo7.3.38)")
			end
			expect(true).to.equal(true)
		end)

		it("rest positions are shared between placement and animation", function()
			-- The SAFE_TOP resize consumers and the animation must use the
			-- same source, or a viewport resize mid-slide strands a banner
			-- at a stale offset.
			has("local function raidBannerRest()", "raid rest fn")
			has("local function dataStoreBannerRest()", "dataStore rest fn")
			has("raidBanner.Position = raidBannerRest()", "raid placement")
			has("dataStoreBanner.Position = dataStoreBannerRest()", "dataStore placement")
		end)
	end)
end
