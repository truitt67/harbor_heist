-- WCAG AA contrast regression guard for the Harbor Heist client palette
-- (harborheist-bpem.3). Pure math only — no Roblox globals — so it runs
-- under lune in the pure bucket.
--
-- It pins the a11y contract: every text color must meet WCAG AA for
-- NORMAL text (>=4.5:1) on each dark surface, and the
-- text > textDim > textFaint luminance hierarchy must hold. If someone
-- darkens a palette color below AA, this spec fails and flags it.
--
-- Palette colors are read directly from UIPalette via rgbTriple (below),
-- the single source of truth — no hardcoded RGB mirror to drift from
-- the `UI` table in src/client/init.client.lua / Theme.color.* tokens.
local UIPalette = require("../../src/shared/UIPalette")

-- harborheist-3aug: comprehensive WCAG audit reads the canonical palette
-- directly. UIPalette.colors are pure RGB triples (Color3 is only used inside
-- the lazy UIPalette.color() fn, never at module top level), so this require
-- is lune-safe with no Roblox shim and cannot drift from the source of truth.
local function rgbTriple(name)
	local c = UIPalette.colors[name]
	return { c.r, c.g, c.b }
end

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

	-- Palette colors read directly from UIPalette via rgbTriple (single source
	-- of truth, harborheist-dfpz). Previously these were hardcoded RGB triplets
	-- duplicated from UIPalette — a drift hazard where a palette change would
	-- silently bypass these checks while the comprehensive audit block below
	-- caught it. rgbTriple returns {r,g,b} with integer keys 1/2/3, the same
	-- shape the contrast() and luminance() helpers expect.
	local bg = rgbTriple("bg")
	local surface = rgbTriple("surface")
	local surfaceHi = rgbTriple("surfaceHi")
	local text = rgbTriple("text")
	local textDim = rgbTriple("textDim")
	local textFaint = rgbTriple("textFaint")

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

	-- harborheist-3aug: comprehensive WCAG audit across the FULL canonical
	-- palette (reads UIPalette.colors directly so it cannot drift from the
	-- source of truth). Body-text colors must meet AA-normal (4.5:1); the
	-- status/accent colors used for large labels, icons, and UI components
	-- must meet the AA large-text / non-text-contrast floor (3:1, WCAG 1.4.11).
	-- Findings recorded on harborheist-3aug: every pair passes; the only
	-- borderline is claimReady on surfaceHi (~4.26:1 — passes 3:1 for large
	-- text/UI, below 4.5:1 for normal body text; avoid it for small body text).
	describe("Comprehensive palette audit (harborheist-3aug)", function()
		local surfaces = { "bg", "surface", "surfaceHi", "undiscovered" }
		local textColors = { "text", "textDim", "textFaint" }
		local statusColors = { "accent", "accentSoft", "good", "bad", "warn", "quest", "boat", "purple", "money", "claimReady", "claimReadyHi", "alert", "raidAlert", "discovery" }

		it("every text color meets AA-normal (4.5:1) on every dark surface", function()
			for _, fg in ipairs(textColors) do
				for _, s in ipairs(surfaces) do
					ge(contrast(rgbTriple(fg), rgbTriple(s)), 4.5, fg .. " on " .. s)
				end
			end
			expect(true).to.equal(true)
		end)

		it("every status/accent color meets AA large/UI (3:1) on every dark surface", function()
			for _, fg in ipairs(statusColors) do
				for _, s in ipairs(surfaces) do
					ge(contrast(rgbTriple(fg), rgbTriple(s)), 3.0, fg .. " on " .. s)
				end
			end
			expect(true).to.equal(true)
		end)

		it("UIPalette canonical palette resolves the audited colors", function()
			expect(UIPalette.colors.bg).to.be.a("table")
			expect(UIPalette.colors.text).to.be.a("table")
			expect(UIPalette.colors.surfaceHi).to.be.a("table")
		end)
	end)
end
