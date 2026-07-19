--[[
	FishVisuals.lua — Reusable fish visual archetype factory (TASK 2.8).

	Builds the actual 3D models used to render fish in the world. Today the
	only consumer is DockManager.updateAquariumVisual (server, aquarium
	inhabitants). Collection book (7.3) will consume the silhouette variant
	for undiscovered entries.

	DESIGN (first principles):
	  1. ARCHETYPES, NOT PER-SPECIES. 15 species collapse into 5 archetypes
	     (Panfish / Streamer / DeepBody / Longsnout / Serpent). Each archetype
	     is a part-assembly descriptor (no MeshPart uploads needed); species
	     pick an archetype via FishVisuals.SPECIES_TO_ARCHETYPE.
	  2. RARITY VARIES BEYOND COLOR. Color alone is not readable for
	     colorblind players (PRD UX). Each rarity adds: size multiplier,
	     material choice, glow (PointLight) for Epic+, particles for
	     Legendary. Shape comes from the archetype; scale/glow/particles
	     come from rarity.
	  3. NO HIGH-POLY, NO PER-FISH ALLOC STORM. Max ~6 parts per fish.
	     Bounded by GameConfig.Aquarium.maxVisibleFish (10) × DockCount (8)
	     = 80 fish models worst-case. Direct Instance.new per build is
	     cheaper than maintaining a template cache + clone lifecycle.
	  4. SHARED MODULE. Lives in ReplicatedStorage.Shared so the client
	     collection book can build silhouettes without duplicating the
	     archetype table.

	Public API:
	  FishVisuals.build(speciesId, rarityName) -> Model
	  FishVisuals.buildSilhouette(speciesId) -> Model
	  FishVisuals.getArchetype(speciesId) -> string (archetype id)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local FishVisuals = {}

-- ════════════════════════════════════════════════════════════════════════════
-- Rarity presentation table — the non-color cues.
-- Size multiplier is applied on top of each archetype's base size.
-- Material replaces the part Material. Glow adds a PointLight on the body.
-- Particles adds a small sparkle emitter (Legendary only).
-- ════════════════════════════════════════════════════════════════════════════
local RARITY_VISUALS = {
	Common =    { sizeMult = 1.00, material = Enum.Material.SmoothPlastic, glow = false, particles = false },
	Uncommon =  { sizeMult = 1.10, material = Enum.Material.SmoothPlastic, glow = false, particles = false },
	Rare =      { sizeMult = 1.25, material = Enum.Material.Neon,          glow = false, particles = false },
	Epic =      { sizeMult = 1.40, material = Enum.Material.Neon,          glow = true,  particles = false },
	Legendary = { sizeMult = 1.60, material = Enum.Material.Neon,          glow = true,  particles = true  },
}

-- ════════════════════════════════════════════════════════════════════════════
-- Archetype descriptors. Each returns a table of part descriptors:
--   { name, shape, size, cframe (relative to root), color?, material? }
-- Sizes are BASE sizes (Common=1.0); rarity multiplier applied at build time.
-- Root is always the first part listed and becomes model.PrimaryPart.
-- ════════════════════════════════════════════════════════════════════════════

local function makeBodyPart(name, shape, size, offsetCFrame)
	return {
		name = name,
		shape = shape,
		size = size,
		cframe = offsetCFrame or CFrame.new(),
	}
end

local ARCHETYPES = {
	-- Small round body, small wedge tail. Starter-fish silhouette.
	Panfish = {
		parts = {
			makeBodyPart("Body", Enum.PartType.Ball, Vector3.new(0.55, 0.45, 1.1)),
			makeBodyPart("Tail", Enum.PartType.Wedge, Vector3.new(0.12, 0.4, 0.45),
				CFrame.new(0, 0, 0.72) * CFrame.Angles(math.rad(-90), 0, 0)),
		},
	},

	-- Elongated body, larger tail. Mid-tier predator profile.
	Streamer = {
		parts = {
			makeBodyPart("Body", Enum.PartType.Block, Vector3.new(0.4, 0.35, 1.5)),
			makeBodyPart("Tail", Enum.PartType.Wedge, Vector3.new(0.1, 0.45, 0.55),
				CFrame.new(0, 0, 0.95) * CFrame.Angles(math.rad(-90), 0, 0)),
		},
	},

	-- Tall body + dorsal fin wedge on top. Reef/pelagic profile.
	DeepBody = {
		parts = {
			makeBodyPart("Body", Enum.PartType.Block, Vector3.new(0.45, 0.7, 1.2)),
			makeBodyPart("DorsalFin", Enum.PartType.Wedge, Vector3.new(0.08, 0.35, 0.5),
				CFrame.new(0, 0.45, -0.1)),
			makeBodyPart("Tail", Enum.PartType.Wedge, Vector3.new(0.12, 0.55, 0.5),
				CFrame.new(0, 0, 0.78) * CFrame.Angles(math.rad(-90), 0, 0)),
		},
	},

	-- Long body + extended snout. Swordfish/Marlin/Sturgeon profile.
	Longsnout = {
		parts = {
			makeBodyPart("Body", Enum.PartType.Block, Vector3.new(0.4, 0.4, 1.4)),
			makeBodyPart("Snout", Enum.PartType.Block, Vector3.new(0.08, 0.08, 0.7),
				CFrame.new(0, 0, -1.0)),
			makeBodyPart("Tail", Enum.PartType.Wedge, Vector3.new(0.12, 0.5, 0.55),
				CFrame.new(0, 0, 0.95) * CFrame.Angles(math.rad(-90), 0, 0)),
		},
	},

	-- Multi-segment serpentine body. Legendary profile (koi, eel, king).
	Serpent = {
		parts = {
			makeBodyPart("Body", Enum.PartType.Ball, Vector3.new(0.5, 0.4, 0.7)),
			makeBodyPart("Segment2", Enum.PartType.Ball, Vector3.new(0.42, 0.35, 0.6),
				CFrame.new(0, 0, 0.55)),
			makeBodyPart("Segment3", Enum.PartType.Ball, Vector3.new(0.35, 0.3, 0.5),
				CFrame.new(0, 0, 1.0)),
			makeBodyPart("Tail", Enum.PartType.Wedge, Vector3.new(0.1, 0.4, 0.5),
				CFrame.new(0, 0, 1.45) * CFrame.Angles(math.rad(-90), 0, 0)),
		},
	},
}

-- ════════════════════════════════════════════════════════════════════════════
-- Species -> Archetype mapping. Fallback default ensures a missing entry
-- never nil-crashes the renderer.
-- ════════════════════════════════════════════════════════════════════════════
local SPECIES_TO_ARCHETYPE = {
	-- Panfish (Common)
	Bluegill = "Panfish",
	Perch = "Panfish",
	Sardine = "Panfish",
	-- Streamer (Uncommon)
	Mackerel = "Streamer",
	Trout = "Streamer",
	Bass = "Streamer",
	-- DeepBody (Rare)
	Snapper = "DeepBody",
	Grouper = "DeepBody",
	Tuna = "DeepBody",
	-- Longsnout (Epic)
	Swordfish = "Longsnout",
	Marlin = "Longsnout",
	Sturgeon = "Longsnout",
	-- Serpent (Legendary)
	GoldenKoi = "Serpent",
	AbyssalEel = "Serpent",
	HarborKing = "Serpent",
}
local DEFAULT_ARCHETYPE = "Panfish"

-- Exposed for testing / debugging
FishVisuals.ARCHETYPES = ARCHETYPES
FishVisuals.SPECIES_TO_ARCHETYPE = SPECIES_TO_ARCHETYPE
FishVisuals.RARITY_VISUALS = RARITY_VISUALS

-- Cache of unknown speciesIds already warned about, so a single bad record
-- doesn't spam the server log every aquarium refresh tick.
local _warnedUnknownSpecies = {}

function FishVisuals.getArchetype(speciesId)
	if speciesId == nil or SPECIES_TO_ARCHETYPE[speciesId] == nil then
		-- TASK 2.8 (fresh-eyes): nil speciesId would silently render as the
		-- default archetype; surface it so the malformed record is diagnosable
		-- in server logs instead of being invisible. Warn-once per speciesId
		-- so repeated renders of the same bad record don't flood the log.
		if not _warnedUnknownSpecies[speciesId] then
			_warnedUnknownSpecies[speciesId] = true
			warn("[FishVisuals] Unknown speciesId: " .. tostring(speciesId) .. " — using default archetype")
		end
		return DEFAULT_ARCHETYPE
	end
	return SPECIES_TO_ARCHETYPE[speciesId]
end

-- Internal: look up rarity color from GameConfig.Rarities by name.
local function rarityColor(rarityName)
	for _, r in ipairs(GameConfig.Rarities) do
		if r.name == rarityName then
			return r.color
		end
	end
	return Color3.fromRGB(255, 255, 255)
end

-- Internal: shared builder. `mode` is "full" or "silhouette".
local function buildInternal(speciesId, rarityName, mode)
	local archetypeId = FishVisuals.getArchetype(speciesId)
	local archetype = ARCHETYPES[archetypeId]
	local rarityVis = RARITY_VISUALS[rarityName] or RARITY_VISUALS.Common

	local model = Instance.new("Model")
	model.Name = "Fish_" .. tostring(speciesId)

	local baseColor
	if mode == "silhouette" then
		baseColor = Color3.fromRGB(20, 20, 25)
	else
		baseColor = rarityColor(rarityName)
	end

	local primaryPart = nil
	for i, partDef in ipairs(archetype.parts) do
		local p = Instance.new("Part")
		p.Name = partDef.name
		p.Shape = partDef.shape
		p.Size = partDef.size * rarityVis.sizeMult
		p.CFrame = partDef.cframe -- relative; repositioned by caller via model:SetPrimaryPartCFrame
		p.Color = baseColor
		if mode == "silhouette" then
			p.Material = Enum.Material.SmoothPlastic
			p.Transparency = 0.15
		else
			p.Material = rarityVis.material
			p.Transparency = 0
		end
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true

		-- Weld everything to the first part (root)
		if i == 1 then
			primaryPart = p
			p.Anchored = true -- root is anchored; others weld to it
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primaryPart
			weld.Part1 = p
			weld.Parent = primaryPart
		end

		p.Parent = model
	end

	model.PrimaryPart = primaryPart

	-- Epic + Legendary: glow on the root part
	if mode == "full" and rarityVis.glow and primaryPart then
		local light = Instance.new("PointLight")
		light.Color = baseColor
		light.Brightness = 1.5
		light.Range = (rarityName == "Legendary") and 8 or 5
		light.Parent = primaryPart
	end

	-- Legendary only: sparkle particles
	if mode == "full" and rarityVis.particles and primaryPart then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxassetid://241685484" -- sparkle
		emitter.Color = ColorSequence.new(baseColor)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(0.6, 1.2)
		emitter.Rate = 8
		emitter.Speed = NumberRange.new(0.3, 0.8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 0.6
		emitter.Parent = primaryPart
	end

	return model
end

--[[
	Build a full-color fish model for the given species + rarity.
	Caller is responsible for positioning via model:SetPrimaryPartCFrame(cf)
	and parenting the model into the world.
]]
function FishVisuals.build(speciesId, rarityName)
	return buildInternal(speciesId, rarityName, "full")
end

--[[
	Build a dark "undiscovered" silhouette of the given species.
	Used by the collection book (7.3) to render not-yet-caught entries.
	Shape is preserved (so players can recognize silhouette -> species),
	but all rarity cues (color, glow, particles) are suppressed.
]]
function FishVisuals.buildSilhouette(speciesId)
	-- Silhouette always uses Common sizing so the shape isn't rarity-tipped
	return buildInternal(speciesId, "Common", "silhouette")
end

return FishVisuals
