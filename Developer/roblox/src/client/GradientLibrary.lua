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
--   The UI table (lines 28-43) mirrors init.client.lua's palette. If that palette
--   changes, update both files. Presets use tuned RGB variants for visual polish;
--   these aren't in the base UI table but are documented in the preset comments.

local Gradients = {}

-- ============================================================================
-- Color references (must match init.client.lua UI table)
-- ============================================================================
-- These are duplicated here because modules can't access init.client.lua's
-- locals. If the UI palette changes, update both files.
local UI = {
	bg = Color3.fromRGB(13, 20, 31),
	surface = Color3.fromRGB(20, 30, 46),
	surfaceHi = Color3.fromRGB(30, 43, 63),
	accent = Color3.fromRGB(56, 152, 255),
	accentSoft = Color3.fromRGB(120, 190, 255),
	good = Color3.fromRGB(52, 199, 123),
	bad = Color3.fromRGB(255, 92, 92),
	warn = Color3.fromRGB(255, 184, 64),
	quest = Color3.fromRGB(255, 205, 92),
	boat = Color3.fromRGB(94, 200, 235),
	purple = Color3.fromRGB(167, 139, 250),
	text = Color3.fromRGB(238, 243, 250),
	textDim = Color3.fromRGB(148, 163, 184),
	ink = Color3.fromRGB(10, 16, 26),
}

-- ============================================================================
-- Gradient presets
-- ============================================================================
-- Presets reference the UI table for base colors, with some tuned variants
-- for visual polish (e.g., 26,38,57 is a surface highlight between UI.surface
-- and UI.surfaceHi). These tuned values are documented inline.
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
