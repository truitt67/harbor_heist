-- Mobile touch-target regression guard for toast buttons (harborheist-rk2h).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- Pins the WCAG 2.1 (44px) minimum touch-target contract established in
-- rk2h: toast action buttons and the persistent-toast close button must
-- keep their IS_MOBILE 44px size branches, and the toast min-height bump
-- must stay so ClipsDescendants can't shave the enlarged buttons. If
-- someone shrinks these below 44px on mobile, this spec fails and flags it.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — the 44px mobile touch-target contract regressed",
				label))
		end
		expect(true).to.equal(true)
	end

	local function count(literal)
		local n, pos = 0, 1
		while true do
			local s = string.find(src, literal, pos, true)
			if not s then
				break
			end
			n += 1
			pos = s + 1
		end
		return n
	end

	describe("Mobile touch targets >= 44px (harborheist-rk2h)", function()
		it("toast action buttons keep a 44px mobile height branch", function()
			has("Size = UDim2.new(0, 64, 0, IS_MOBILE and 44 or 24)", "toast action button size")
		end)
		it("persistent toast close button keeps 44px mobile size branches", function()
			has("Size = UDim2.new(0, IS_MOBILE and 44 or 20, 0, IS_MOBILE and 44 or 20)",
				"toast close button size")
		end)
		it("toast min-height bump stays so enlarged buttons aren't clipped", function()
			local n = count("toastMinSize.MinSize = Vector2.new(0, math.max(MIN_TOAST_H, 52))")
			if n < 2 then
				error(string.format(
					"toast min-height bump: expected 2 call sites (action buttons + close button), found %d",
					n))
			end
			expect(true).to.equal(true)
		end)
	end)

	-- harborheist-3aug: comprehensive touch-target audit beyond toasts. Pins
	-- the 44px (WCAG 2.1 / Apple HIG) mobile minimum for the other major
	-- interactive buttons: panel close / square icon buttons, action bar,
	-- full-width primary buttons, and shop buy / raid buttons. Mirrors the
	-- rk2h pin style; if a button's mobile branch is shrunk below 44px the
	-- matching assertion fails and names the offender.
	describe("Interactive button touch targets >= 44px mobile (harborheist-3aug)", function()
		it("panel close / square icon buttons keep a 44px mobile size", function()
			has("Size = UDim2.new(0, IS_MOBILE and 44 or 24, 0, IS_MOBILE and 44 or 24)", "square icon button 44px")
			has("Size = UDim2.new(0, IS_MOBILE and 44 or 32, 0, IS_MOBILE and 44 or 32)", "square close button 44px")
		end)

		it("action bar buttons keep a 44px mobile height", function()
			has("Size = UDim2.new(0.48, -6, 0, IS_MOBILE and 44 or 36)", "action bar button height")
			has("local actionH = IS_MOBILE and 44 or 38", "actionH height var")
		end)

		it("full-width primary buttons keep a 44px mobile height", function()
			has("Size = UDim2.new(1, -16, 0, IS_MOBILE and 44 or 34)", "full-width primary button")
			has("Size = UDim2.new(1, 0, 0, IS_MOBILE and 44 or 32)", "full-width button (32 desktop)")
			has("Size = UDim2.new(1, 0, 0, IS_MOBILE and 44 or 36)", "full-width button (36 desktop)")
		end)

		it("shop buy / raid wide buttons keep a 44px mobile height", function()
			has("Size = UDim2.new(0, IS_MOBILE and 100 or 90, 0, IS_MOBILE and 44 or 28)", "shop/raid wide button height")
			has("Size = UDim2.new(0, IS_MOBILE and 96 or 80, 0, IS_MOBILE and 44 or 32)", "wide button height 44px")
			has("local buyH = IS_MOBILE and 44 or 38", "buyH height var")
		end)
	end)
end
