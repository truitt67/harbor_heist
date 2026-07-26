-- WCAG AA contrast regression guard for the Harbor Heist client palette
-- (harborheist-bpem.3). Pure math only — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- It pins the a11y contract: every text color must meet WCAG AA for
-- NORMAL text (>=4.5:1) on each dark surface, and the
-- text > textDim > textFaint luminance hierarchy must hold. If someone
-- darkens a palette color below AA, this spec fails and flags it.
--
-- The RGB triplets below MUST be kept in sync with the `UI` table in
-- src/client/init.client.lua (and the Theme.color.* tokens that alias it).
return function(describe, it, expect)
	local function lin(c)
		local s = c / 255
		if s <= 0.03928 then
			return s / 12.92
		end
		return ((s + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(rgb)
		return 0.2126 * lin(rgb[1]) + 0.7152 * lin(rgb[2]) + 0.0722 * lin(rgb[3])
	end
	local function contrast(fg, bg)
		local lf, lb = luminance(fg), luminance(bg)
		local hi, lo = math.max(lf, lb), math.min(lf, lb)
		return (hi + 0.05) / (lo + 0.05)
	end
	local function ge(ratio, threshold, label)
		if ratio < threshold then
			error(string.format("%s: %.2f:1 is below the %.1f:1 AA requirement", label, ratio, threshold))
		end
	end

	-- Palette RGB triplets (mirror src/client/init.client.lua UI table).
	local bg = { 13, 20, 31 }
	local surface = { 20, 30, 46 }
	local surfaceHi = { 30, 43, 63 }
	local text = { 238, 243, 250 }
	local textDim = { 148, 163, 184 }
	local textFaint = { 130, 146, 169 }

	describe("WCAG AA text contrast (harborheist-bpem.3)", function()
		it("primary text meets AA-normal (4.5:1) on every dark surface", function()
			ge(contrast(text, bg), 4.5, "text on bg")
			ge(contrast(text, surface), 4.5, "text on surface")
			ge(contrast(text, surfaceHi), 4.5, "text on surfaceHi")
		end)
		it("secondary text (textDim) meets AA-normal on every dark surface", function()
			ge(contrast(textDim, bg), 4.5, "textDim on bg")
			ge(contrast(textDim, surface), 4.5, "textDim on surface")
			ge(contrast(textDim, surfaceHi), 4.5, "textDim on surfaceHi")
		end)
		it("tertiary text (textFaint) meets AA-normal on every dark surface", function()
			ge(contrast(textFaint, bg), 4.5, "textFaint on bg")
			ge(contrast(textFaint, surface), 4.5, "textFaint on surface")
			ge(contrast(textFaint, surfaceHi), 4.5, "textFaint on surfaceHi")
		end)
		it("preserves the text > textDim > textFaint luminance hierarchy", function()
			local lt, ld, lf = luminance(text), luminance(textDim), luminance(textFaint)
			if not (lt > ld and ld > lf) then
				error(string.format(
					"hierarchy broken: text=%.3f textDim=%.3f textFaint=%.3f", lt, ld, lf))
			end
			expect(true).to.equal(true)
		end)
	end)
end
