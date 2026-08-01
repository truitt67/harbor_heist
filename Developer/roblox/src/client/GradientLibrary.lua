-- harborheist-i39g.3: Gradient library for EPIC 35 (Visual Polish)
-- Provides reusable UIGradient presets for surfaces, accents, status, and rarity.
-- All colors derive from the shared UIPalette (harborheist-kqbq.22.5).
--
-- USAGE:
--   local Gradients = require(script.Parent:WaitForChild("GradientLibrary"))
--   Gradients.apply(myFrame, "surface.elevated")
--   Gradients.apply(myButton, "accent.primary")
--   Gradients.apply(progressBar, "status.success")
--   Gradients.apply(rarityLabel, "rarity.Legendary")
--
-- DESIGN:
--   Each preset is a {from, to} Color3 pair. apply() creates a UIGradient
--   with Rotation=90 (vertical) and attaches it to the target. Returns the gradient
--   instance so callers can adjust Rotation/Transparency if needed.
--
-- PERFORMANCE:
--   UIGradient is cheap (GPU-side), but avoid stacking 10+ on a single frame.
--   The presets are static tables — no per-frame allocation.
--
-- MAINTENANCE:
-- Base colors are sourced from the shared UIPalette module
-- (ReplicatedStorage.Shared.UIPalette). All gradient presets derive from
-- palette tokens — either directly or via Color3:Lerp. The single tuned
-- variant (surfaceMid) was promoted into UIPalette in harborheist-kqbq.22.5
-- so the palette remains the single source of truth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- harborheist-nk22 (EPIC 36): Source base colors from the shared UIPalette
-- module instead of duplicating them here. Eliminates the silent drift risk
-- where this file's copy fell out of sync with init.client.lua's palette.
local UIPalette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UIPalette"))

local Gradients = {}

-- ============================================================================
-- Color references (sourced from shared UIPalette — single source of truth)
-- ============================================================================
local UI = {
	bg = UIPalette.color("bg"),
	surface = UIPalette.color("surface"),
	surfaceHi = UIPalette.color("surfaceHi"),
	-- harborheist-kqbq.22.5: tuned mid-surface token promoted from raw
	-- fromRGB so the palette stays the single source of truth.
	surfaceMid = UIPalette.color("surfaceMid"),
	accent = UIPalette.color("accent"),
	accentSoft = UIPalette.color("accentSoft"),
	good = UIPalette.color("good"),
	bad = UIPalette.color("bad"),
	warn = UIPalette.color("warn"),
	quest = UIPalette.color("quest"),
	boat = UIPalette.color("boat"),
	purple = UIPalette.color("purple"),
	text = UIPalette.color("text"),
	textDim = UIPalette.color("textDim"),
	ink = UIPalette.color("ink"),
}

-- ============================================================================
-- Gradient presets
-- ============================================================================
-- Presets reference the UI table (sourced from UIPalette) for base colors.
-- harborheist-kqbq.22.5: all presets now derive from palette tokens —
-- either directly or via Color3:Lerp between existing tokens. No raw
-- Color3.fromRGB remains (contract-verified in ClientChrome.spec.lua).
local PRESETS = {
	-- Surface gradients: subtle background variations for panels/containers
	-- "default" is the workhorse — used by overlays, panels, HUD, reveal cards
	surface = {
		default = { from = UI.surfaceMid, to = UI.bg },
		elevated = { from = UI.surface, to = UI.surfaceHi },
		-- kqbq.22.5 SEAM FIX: was a raw Color3 literal brighter than the
		-- HUD card's base (bg=13,20,31), creating a muddy discontinuity at
		-- the top edge. Now uses UI.surface (20,30,46) — subtler,
		-- palette-consistent, closer to the card base.
		hud = { from = UI.surface, to = UI.bg },
	},

	-- Accent gradients: buttons, highlights, interactive elements
	accent = {
		primary = { from = UI.accent, to = UI.accentSoft },
		soft = { from = UI.accentSoft, to = UI.text },
		brand = { from = UI.purple, to = UI.accent },
		-- kqbq.22.5: from = lightened purple derived via Lerp toward text
		capacity = { from = UI.purple:Lerp(UI.text, 0.3), to = UI.purple },
	},

	-- Status gradients: progress bars, health indicators, feedback
	status = {
		-- kqbq.22.5: to = lightened good derived via Lerp toward text
		success = { from = UI.good, to = UI.good:Lerp(UI.text, 0.3) },
		-- kqbq.22.5: from was raw (255,205,92) which equals UI.quest
		warning = { from = UI.quest, to = UI.warn },
		collection = { from = UI.quest, to = UI.warn },
		-- kqbq.22.5: to = lightened bad derived via Lerp toward text
		error = { from = UI.bad, to = UI.bad:Lerp(UI.text, 0.3) },
		info = { from = UI.accentSoft, to = UI.boat },
	},

	-- Rarity gradients: fish rarity colors (Common through Legendary).
	-- kqbq.22.5: all presets derive from palette tokens via Lerp. The
	-- canonical rarity colors used in the UI live in GameConfig.Rarities;
	-- these gradient presets approximate them from palette tokens for
	-- visual consistency. Presets are currently unused (no Gradients.apply
	-- call uses the "rarity." path) but kept for future gradient effects.
	rarity = {
		Common = { from = UI.textDim, to = UI.textDim:Lerp(UI.ink, 0.5) },
		Uncommon = { from = UI.good, to = UI.good:Lerp(UI.ink, 0.5) },
		Rare = { from = UI.accent, to = UI.accent:Lerp(UI.ink, 0.5) },
		Epic = { from = UI.purple, to = UI.purple:Lerp(UI.ink, 0.5) },
		Legendary = { from = UI.quest, to = UI.quest:Lerp(UI.ink, 0.5) },
		Mythic = { from = UI.purple:Lerp(UI.bad, 0.5), to = UI.purple:Lerp(UI.ink, 0.3) },
	},
}

-- ============================================================================
-- Public API
-- ============================================================================

--- Apply a gradient preset to a GUI element.
-- @param element Instance - The Frame/TextLabel/TextButton to attach the gradient to
-- @param presetPath string - Dot-separated path: "category.name" (e.g., "surface.default")
-- @param rotation number? - Optional rotation in degrees (default 90 = vertical)
-- @return UIGradient - The created gradient instance (caller can adjust further)
function Gradients.apply(element, presetPath, rotation)
	if not element or not presetPath then
		warn("[GradientLibrary] apply() requires element and presetPath")
		return nil
	end

	-- Parse "category.name" into nested table lookup
	local category, name = presetPath:match("^([^.]+)%.(.+)$")
	if not category then
		warn("[GradientLibrary] Invalid preset path: ", presetPath, " (expected 'category.name')")
		return nil
	end

	local preset = PRESETS[category] and PRESETS[category][name]
	if not preset then
		warn("[GradientLibrary] Unknown preset: ", presetPath)
		return nil
	end

	-- Remove any existing UIGradient to avoid stacking
	for _, child in ipairs(element:GetChildren()) do
		if child:IsA("UIGradient") then
			child:Destroy()
		end
	end

	-- Create and configure the gradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(preset.from, preset.to)
	gradient.Rotation = rotation or 90
	gradient.Parent = element

	return gradient
end

--- Get a preset's color pair without applying it.
-- @param presetPath string - Dot-separated path: "category.name"
-- @return Color3, Color3 - The from and to colors, or nil if not found
function Gradients.getColors(presetPath)
	if not presetPath then
		return nil
	end
	local category, name = presetPath:match("^([^.]+)%.(.+)$")
	if not category then
		return nil
	end

	local preset = PRESETS[category] and PRESETS[category][name]
	if not preset then
		return nil
	end

	return preset.from, preset.to
end

--- List all available preset paths.
-- @return table - Array of preset path strings (e.g., {"surface.default", "accent.primary", ...})
function Gradients.listPresets()
	local paths = {}
	for category, presets in pairs(PRESETS) do
		for name, _ in pairs(presets) do
			table.insert(paths, category .. "." .. name)
		end
	end
	table.sort(paths)
	return paths
end

return Gradients
