--!strict
-- CollectionService.lua (EPIC 7, TASK 7.2)
-- Server-authoritative collection book. Serves the per-species book data to
-- the client: discovered species get FULL data (name, rarity, flavor, sell
-- value, income), undiscovered species get ONLY rarity + a silhouette flag
-- (PRD COLL-04: "undiscovered fish conceal precise catch data").
--
-- DESIGN (first principles):
--   1. Server is the only source of truth. The client never computes
--      discovered/undiscovered itself — it renders exactly what the server
--      returns. This is the anti-exploit boundary (COLL-04): the client can't
--      learn an undiscovered species' name/value because the server never
--      sends it.
--   2. Discovery state lives in profile.Collection.DiscoveredSpecies
--      (persisted, TASK 7.1). This module only READS it; FishingService owns
--      the writes (on catch).
--   3. Ordered output. Species are returned sorted by CollectionOrder so the
--      book layout is stable across sessions and matches the intended
--      progression (Common first, Legendary last).
--   4. Milestones are computed, not stored. getMilestones() derives progress
--      from DiscoveredSpecies + FishDefinitions; TASK 7.4 adds the claim
--      logic on top of this read model.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local FishDefinitions = require(Shared.FishDefinitions)
local PlayerProfile = require(Shared.PlayerProfile)

local CollectionService = {}

-- Module-level deps captured in init()
local remotes
local dataManager

-- Rarity ordinal for milestone reward scaling. Uses the SINGLE source of
-- truth exported by FishDefinitions (not a hardcoded duplicate that could
-- silently diverge if a rarity is ever reordered).
local RARITY_ORDER = FishDefinitions.RARITY_ORDER

--- Build the ordered species catalog (sorted by CollectionOrder).
-- Cached at module load — FishDefinitions is static.
local _orderedSpecies = nil
local function getOrderedSpecies()
	if _orderedSpecies then
		return _orderedSpecies
	end
	local list = {}
	for _, def in pairs(FishDefinitions.Species) do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return (a.CollectionOrder or 999) < (b.CollectionOrder or 999)
	end)
	_orderedSpecies = list
	return list
end

--- Build the collection book payload for a player.
-- Returns a table shaped for the client UI:
--   {
--     discovered = { [SpeciesId] = { full data } },   -- COLL-03
--     undiscovered = { [SpeciesId] = { rarity, silhouette } }, -- COLL-04
--     ordered = { SpeciesId, ... },                    -- stable layout order
--     totalSpecies = N,
--     discoveredCount = M,
--   }
-- The client renders `ordered` and looks each SpeciesId up in discovered or
-- undiscovered. Discovered species NEVER appear in the undiscovered map, so
-- the client can't accidentally render concealed data.
function CollectionService.buildBook(session)
	local profile = session and session.profile
	local discovered = (profile and profile.Collection and profile.Collection.DiscoveredSpecies) or {}

	local discoveredMap = {}
	local undiscoveredMap = {}
	local ordered = {}
	local discoveredCount = 0

	for _, def in ipairs(getOrderedSpecies()) do
		local id = def.SpeciesId
		table.insert(ordered, id)
		if discovered[id] then
			discoveredCount += 1
			-- COLL-03: discovered fish show name, rarity, value. (Flavor text
			-- is a COLL-03 "optional" field that doesn't exist in
			-- FishDefinitions yet — add it there when content is authored.)
			discoveredMap[id] = {
				speciesId = id,
				displayName = def.DisplayName,
				rarity = def.Rarity,
				zoneIds = def.ZoneIds,
				baseSellValue = def.BaseSellValue,
				incomePerMinute = def.IncomePerMinute,
				modelId = def.ModelId,
			}
		else
			-- COLL-04: undiscovered fish conceal precise catch data. Only
			-- rarity + a silhouette flag are sent. NO name, NO value, NO zone.
			undiscoveredMap[id] = {
				speciesId = id,
				rarity = def.Rarity,
				silhouette = true,
			}
		end
	end

	return {
		discovered = discoveredMap,
		undiscovered = undiscoveredMap,
		ordered = ordered,
		totalSpecies = #ordered,
		discoveredCount = discoveredCount,
	}
end

--- Compute collection milestone progress (read model for TASK 7.4).
-- Returns an array of milestone descriptors with progress + claimed state.
-- Milestones: discover N species; discover all of a rarity; discover all in
-- a zone. Claiming logic lives in TASK 7.4 — this only computes progress.
function CollectionService.getMilestones(session)
	local profile = session and session.profile
	local discovered = (profile and profile.Collection and profile.Collection.DiscoveredSpecies) or {}
	local claimed = (profile and profile.Collection and profile.Collection.MilestonesClaimed) or {}

	-- Tally progress
	local totalDiscovered = 0
	local byRarity = {} -- [rarity] = { have = n, total = n }
	local byZone = {}   -- [zoneId] = { have = n, total = n }

	for _, def in ipairs(getOrderedSpecies()) do
		local has = discovered[def.SpeciesId] == true
		if has then
			totalDiscovered += 1
		end
		-- rarity tally
		byRarity[def.Rarity] = byRarity[def.Rarity] or { have = 0, total = 0 }
		byRarity[def.Rarity].total += 1
		if has then
			byRarity[def.Rarity].have += 1
		end
		-- zone tally
		for _, zid in ipairs(def.ZoneIds or {}) do
			byZone[zid] = byZone[zid] or { have = 0, total = 0 }
			byZone[zid].total += 1
			if has then
				byZone[zid].have += 1
			end
		end
	end

	-- Build milestone list. `id` is stable; `claimed` reads MilestonesClaimed.
	local milestones = {}
	local function add(id, kind, label, have, need, reward)
		table.insert(milestones, {
			id = id,
			kind = kind,
			label = label,
			have = have,
			need = need,
			complete = have >= need,
			claimed = claimed[id] == true,
			reward = reward,
		})
	end

	-- Discover N species
	for _, n in ipairs({ 5, 10, 15 }) do
		add("count_" .. n, "count", ("Discover %d species"):format(n), totalDiscovered, n, { coins = n * 100 })
	end
	-- All of a rarity
	for rarity, tally in pairs(byRarity) do
		add("rarity_" .. rarity, "rarity", ("Discover all %s fish"):format(rarity), tally.have, tally.total, { coins = 200 * (RARITY_ORDER[rarity] or 1) })
	end
	-- All in a zone
	for zid, tally in pairs(byZone) do
		add("zone_" .. zid, "zone", ("Discover all %s fish"):format(zid), tally.have, tally.total, { coins = 250 })
	end

	-- Deterministic order: pairs() iterates byRarity/byZone in arbitrary
	-- order, which would reshuffle the milestone list between calls and make
	-- the client UI flicker. Sort by id so the layout is stable.
	table.sort(milestones, function(a, b)
		return a.id < b.id
	end)

	return milestones
end

function CollectionService.init(deps)
	remotes = deps.remotes
	dataManager = deps.dataManager

	-- RequestCollection (RemoteFunction): client asks for its book. Returns
	-- the COLL-04-safe payload. Read-only — no state mutation here.
	remotes.RequestCollection.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		local book = CollectionService.buildBook(session)
		book.ok = true
		return book
	end

	-- ClaimCollectionReward (RemoteFunction, TASK 7.4): claim a milestone
	-- reward. Validates three things server-side (never trust the client):
	--   1. The milestone id is real and complete (progress >= target).
	--   2. It hasn't been claimed already (MilestonesClaimed[id]).
	--   3. The reward is credited through clampCoins (no MAX_COINS overflow).
	remotes.ClaimCollectionReward.OnServerInvoke = function(player, milestoneId)
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		if type(milestoneId) ~= "string" or #milestoneId == 0 then
			return { ok = false, reason = "bad_id" }
		end

		-- Recompute milestones server-side (authoritative — the client only
		-- ever SENDS an id, never progress). Find the matching milestone.
		local target = nil
		for _, m in ipairs(CollectionService.getMilestones(session)) do
			if m.id == milestoneId then
				target = m
				break
			end
		end
		if not target then
			return { ok = false, reason = "unknown_milestone" }
		end
		if target.claimed then
			return { ok = false, reason = "already_claimed" }
		end
		if not target.complete then
			return { ok = false, reason = "incomplete" }
		end

		-- Credit the reward. Coins route through clampCoins; track lifetime.
		local profile = session.profile
		local coinsGranted = (target.reward and target.reward.coins) or 0
		if coinsGranted > 0 then
			profile.Coins = PlayerProfile.clampCoins(profile.Coins + coinsGranted)
			profile.TotalCoinsEarned = profile.TotalCoinsEarned + coinsGranted
		end
		-- Mark claimed BEFORE pushing state so the snapshot reflects it.
		profile.Collection.MilestonesClaimed[milestoneId] = true

		-- Notify + refresh client.
		if session.player and session.player.Parent then
			remotes.notify(
				session.player,
				("Collection milestone: %s (+%d coins)"):format(target.label, coinsGranted),
				Color3.fromRGB(255, 215, 0)
			)
		end
		local stateSync = deps.stateSync
		if stateSync then
			stateSync.push(session)
		end

		return { ok = true, milestoneId = milestoneId, coinsGranted = coinsGranted }
	end
end

return CollectionService
