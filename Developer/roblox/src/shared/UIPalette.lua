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
- Tuned gradient variants (e.g. the mid-surface #1A2639 used by
  GradientLibrary's "surface.default" preset) live in GradientLibrary,
  not here — they are visual-polish interpolations between base colors,
  documented inline at each preset.
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
	money = { r = 134, g = 239, b = 172 },
	undiscovered = { r = 16, g = 24, b = 36 },
	claimReady = { r = 50, g = 160, b = 80 },
	claimReadyHi = { r = 74, g = 198, b = 114 },
	disabled = { r = 100, g = 60, b = 60 },
	neutral = { r = 60, g = 70, b = 80 },
	alert = { r = 255, g = 170, b = 80 },
	raidAlert = { r = 255, g = 120, b = 120 },
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
