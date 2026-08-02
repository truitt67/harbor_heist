--[[
=============================================================================
EPIC 36 (harborheist-nk22): Canonical UI Color Palette
=============================================================================

SINGLE SOURCE OF TRUTH for the game's base color palette.

History: the base UI colors were originally hardcoded inline in
init.client.lua's `UI` table (24 colors) and DUPLICATED in
GradientLibrary.lua's `UI` table (14-color subset). If one changed and
the other didn't, gradients would drift from the actual UI — a silent
visual-consistency bug. This module eliminates that duplication: both
consumers now require UIPalette and read `UIPalette.colors.<name>`.

DESIGN NOTES:
- These are the BASE (flat) palette values. Semantic token groupings
  (surface.primary, status.good, text.primary, ...) are built ON TOP of
  these in init.client.lua's `Theme` local — that alias layer is where
  new code should read from, NOT these flat values directly:
      Theme.color.surface.secondary   instead of  UIPalette.colors.surface
      Theme.color.text.primary        instead of  UIPalette.colors.text
- Gradient interpolations (e.g. lightened tokens via Color3:Lerp) are
  computed in GradientLibrary at require time from these base tokens —
  they are not stored here. The one formerly-tuned RGB value
  (surfaceMid = 26,38,57) was promoted INTO this palette in
  harborheist-kqbq.22.5 so it remains the single source of truth;
  GradientLibrary now derives every preset from palette tokens only.
- Colors are stored as RGB integer triples (not Color3) so this module
  has zero Roblox-instance dependencies and can be required by any
  context (pure-Luau specs included). Consumers call UIPalette.color(name)
  to get a Color3.

USAGE:
  local UIPalette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIPalette"))
  local bg = UIPalette.color("bg")            -- Color3
  local rgb = UIPalette.colors.bg              -- {r=13, g=20, b=31}
=============================================================================
--]]

local UIPalette = {}

-- Base palette: name -> {r, g, b} (0-255 integers)
-- Values MUST stay in sync with the visual design. Changing a value here
-- updates every consumer (init.client.lua UI table, GradientLibrary).
UIPalette.colors = {
	bg = { r = 13, g = 20, b = 31 },
	surface = { r = 20, g = 30, b = 46 },
	surfaceHi = { r = 30, g = 43, b = 63 },
	-- harborheist-kqbq.22.5: Tuned mid-surface highlight for the
	-- surface.default gradient preset (GradientLibrary). Between surface
	-- (20,30,46) and surfaceHi (30,43,63) — provides a subtle vertical lift
	-- on panels/overlays/cards. Promoted from a raw fromRGB in
	-- GradientLibrary so the palette stays the single source of truth.
	surfaceMid = { r = 26, g = 38, b = 57 },
	stroke = { r = 255, g = 255, b = 255 },
	accent = { r = 56, g = 152, b = 255 },
	accentSoft = { r = 120, g = 190, b = 255 },
	good = { r = 52, g = 199, b = 123 },
	bad = { r = 255, g = 92, b = 92 },
	warn = { r = 255, g = 184, b = 64 },
	quest = { r = 255, g = 205, b = 92 },
	boat = { r = 94, g = 200, b = 235 },
	purple = { r = 167, g = 139, b = 250 },
	text = { r = 238, g = 243, b = 250 },
	textDim = { r = 148, g = 163, b = 184 },
	textFaint = { r = 138, g = 154, b = 177 },
	ink = { r = 10, g = 16, b = 26 },
	-- Additional semantic palette colors
	-- harborheist-kqbq.18.5: shifted from mint (134,239,172) to warm gold-green
	-- (158,215,88) — treasure semantic, distinguishes money/currency from
	-- success-green (good=52,199,123). WCAG AA-large/UI 3:1 verified on all
	-- dark surfaces (bg, surface, surfaceHi, undiscovered). See kqbq.18.4.
	money = { r = 158, g = 215, b = 88 },
	undiscovered = { r = 16, g = 24, b = 36 },
	claimReady = { r = 50, g = 160, b = 80 },
	claimReadyHi = { r = 74, g = 198, b = 114 },
	disabled = { r = 100, g = 60, b = 60 },
	neutral = { r = 60, g = 70, b = 80 },
	alert = { r = 255, g = 170, b = 80 },
	raidAlert = { r = 255, g = 120, b = 120 },
	-- harborheist-a2ug.2: species-discovery celebration gold — distinct from
	-- quest (255,205,92) because discovery is a premium celebration moment.
	discovery = { r = 255, g = 215, b = 0 },
}

--- Look up a base color by name and return a Color3.
-- @param name string - Palette key (e.g. "bg", "surface", "accent")
-- @return Color3 - The color, or nil if the name is unknown
function UIPalette.color(name)
	local c = UIPalette.colors[name]
	if not c then
		return nil
	end
	return Color3.fromRGB(c.r, c.g, c.b)
end

return UIPalette
