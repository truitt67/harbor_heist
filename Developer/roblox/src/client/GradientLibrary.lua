-- harborheist-i39g.3: Gradient library for EPIC 35 (Visual Polish)
-- Provides reusable UIGradient presets for surfaces, accents, status, and rarity.
-- Base colors reference the UI palette; some presets use tuned variants.
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
-- (ReplicatedStorage.Shared.UIPalette). Gradient presets use tuned RGB
-- variants for visual polish; these aren't base palette colors but are
-- documented in each preset's comment.

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
-- Presets reference the UI table (sourced from UIPalette) for base colors,
-- with some tuned variants for visual polish (e.g. 26,38,57 is a surface
-- highlight between UI.surface and UI.surfaceHi). These tuned values are
-- documented inline.
local PRESETS = {
	-- Surface gradients: subtle background variations for panels/containers
	-- "default" is the workhorse — used by overlays, panels, HUD, reveal cards
	surface = {
		default = { from = Color3.fromRGB(26, 38, 57), to = UI.bg },
		elevated = { from = UI.surface, to = UI.surfaceHi },
		hud = { from = Color3.fromRGB(24, 36, 54), to = UI.bg },
	},

	-- Accent gradients: buttons, highlights, interactive elements
	accent = {
		primary = { from = UI.accent, to = UI.accentSoft },
		soft = { from = UI.accentSoft, to = UI.text },
		brand = { from = UI.purple, to = UI.accent },
		capacity = { from = Color3.fromRGB(196, 181, 253), to = UI.purple },
	},

	-- Status gradients: progress bars, health indicators, feedback
	status = {
		success = { from = UI.good, to = Color3.fromRGB(100, 220, 160) },
		warning = { from = Color3.fromRGB(255, 205, 92), to = UI.warn },
		collection = { from = UI.quest, to = UI.warn },
		error = { from = UI.bad, to = Color3.fromRGB(255, 140, 140) },
		info = { from = UI.accentSoft, to = UI.boat },
	},

	-- Rarity gradients: fish rarity colors (Common through Legendary)
	-- Matches GameConfig.Rarities array order. Colors are illustrative —
	-- adjust to match the actual rarity color palette used in the UI.
	rarity = {
		Common = { from = Color3.fromRGB(200, 200, 200), to = Color3.fromRGB(150, 150, 150) },
		Uncommon = { from = Color3.fromRGB(100, 200, 100), to = Color3.fromRGB(50, 150, 50) },
		Rare = { from = Color3.fromRGB(100, 150, 255), to = Color3.fromRGB(50, 100, 200) },
		Epic = { from = UI.purple, to = Color3.fromRGB(120, 80, 200) },
		Legendary = { from = UI.quest, to = Color3.fromRGB(255, 160, 50) },
		Mythic = { from = Color3.fromRGB(255, 100, 200), to = Color3.fromRGB(200, 50, 150) },
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
