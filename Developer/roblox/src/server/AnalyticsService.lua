--!strict
-- AnalyticsService.lua (EPIC 11, TASK 11.1)
-- Server-authoritative wrapper around Roblox's built-in AnalyticsService.
-- Centralizes the V1 event catalog so gameplay code can't typo event names,
-- and so every event carries consistent metadata (userId, session start,
-- timestamp). Gracefully no-ops if the engine service is unavailable.
--
-- DESIGN (first principles):
--   1. ONE fire point. Gameplay code never calls AnalyticsService directly —
--      it calls Analytics.track(player, eventName, fields). This is the only
--      seam, so event-name validation + field shape live in one place.
--   2. Authoritative catalog. The 19 PRD events (PRD.md L491-509) plus 7
--      derived events round out the 26 the closed-test exit criteria demand.
--      (24 original + suspicious_action + raid_targets_requested, added in
--      harborheist-os9 — they were fired by gameplay code but unregistered.)
--      The catalog is a set: track() rejects unknown names (prevents typos
--      silently spawning ghost events in the dashboard).
--   3. Funnel timing. first_session_start is captured once per player and
--      attached to every event, so the dashboard can compute time-to-X for
--      the onboarding funnel without joining across events.
--   4. No throwing. Analytics must NEVER break gameplay. Every call is
--      pcall-wrapped; failures log to stdout and continue.
--
-- EVENTS (26):
--   Onboarding funnel: tutorial_started, starter_rod_received, first_cast,
--     first_catch, first_store, first_sale, first_upgrade
--   Core loop: fish_caught, fish_catch_failed, fish_stored, fish_sold,
--     income_claimed, cast_result_tier
--   Shop / collection: upgrade_shop_opened, upgrade_purchased,
--     collection_book_opened
--   PvP / raid: raid_info_viewed, raid_opt_in_enabled, aquarium_locked,
--     raid_attempted, raid_succeeded, raid_defended
--   Churn signals: player_left_before_first_catch,
--     player_left_before_first_upgrade
--   Security/ops: suspicious_action, raid_targets_requested

local Players = game:GetService("Players")
-- Memoized engine AnalyticsService reference. Resolved ONCE on first track()
-- call; subsequent calls return the cached reference (or nil if unavailable).
-- CORRECTED (fresh-eyes review): previously getEngineService ran a pcall +
-- game:GetService on EVERY event fire (~20+/min/player). Now resolved once.
local _engineService = nil
local _engineServiceResolved = false
local function getEngineService(): any
	if _engineServiceResolved then
		return _engineService
	end
	-- pcall in case AnalyticsService is disabled (some Studio configs) —
	-- analytics should degrade to no-op, never crash the server.
	local ok, svc = pcall(function()
		return game:GetService("AnalyticsService")
	end)
	_engineServiceResolved = true
	_engineService = (ok and svc) or nil
	return _engineService
end

-- Narrow a Player-instance-or-something-else argument to a Player (or nil).
-- typeof() is read through a LOCAL on purpose: luau-analyze refines direct
-- `typeof(x) == "Instance"` comparisons against a Roblox type environment
-- the CLI doesn't have, producing UnknownType 'Instance' noise in this
-- --!strict file. Semantics are identical (typeof is a pure builtin).
local function asPlayer(player: any): any
	local t = typeof(player)
	if t == "Instance" and player:IsA("Player") then
		return player
	end
	return nil
end

-- Narrow a Player-instance-or-UserId argument to a UserId (or nil).
local function userIdOf(player: any): number?
	local p = asPlayer(player)
	if p then
		return p.UserId
	end
	if type(player) == "number" then
		return player
	end
	return nil
end

local AnalyticsService = {}

-- Authoritative catalog of the 24 V1 events. track() validates against this.
-- Using a set (keys = true) gives O(1) lookup and reads as intent.
local EVENTS = {
	-- Onboarding funnel (PRD: tutorial_started, starter_rod_received, first_cast)
	tutorial_started = true,
	starter_rod_received = true,
	first_cast = true,
	first_catch = true,
	first_store = true,
	first_sale = true,
	first_upgrade = true,
	-- Core loop
	fish_caught = true,
	fish_catch_failed = true,
	fish_stored = true,
	fish_sold = true,
	income_claimed = true,
	cast_result_tier = true,
	-- Shop / collection
	upgrade_shop_opened = true,
	upgrade_purchased = true,
	collection_book_opened = true,
	-- PvP / raid
	raid_info_viewed = true,
	raid_opt_in_enabled = true,
	aquarium_locked = true,
	raid_attempted = true,
	raid_succeeded = true,
	raid_defended = true,
	-- Churn signals
	player_left_before_first_catch = true,
	player_left_before_first_upgrade = true,
	-- harborheist-os9: these two were already FIRED by gameplay code but
	-- missing from the catalog, so track() rejected every call (warn spam +
	-- lost data). suspicious_action is the EPIC 10 anti-exploit telemetry
	-- event; raid_targets_requested is the gdj.13 raid-UI open metric.
	suspicious_action = true,
	raid_targets_requested = true,
}

-- Per-player session record. The first*At stamps hold the event's age
-- (seconds since sessionStart), filled on first occurrence; nil = not yet.
-- The explicit type matters: without it --!strict infers the nil-literal
-- fields as type nil, hiding bad assignments from the analyzer.
type FunnelSession = {
	sessionStart: number,
	firstCastAt: number?,
	firstCatchAt: number?,
	firstStoreAt: number?,
	firstSaleAt: number?,
	firstUpgradeAt: number?,
}

-- Per-player session state: first-session start time + funnel progress flags.
-- Keyed by UserId (stable across rejoins, unlike Player instances).
local sessions: { [number]: FunnelSession } = {}

-- Internal: get or create the per-player session record.
local function getSession(userId: number): FunnelSession
	local s = sessions[userId]
	if not s then
		-- Funnel stamp fields start absent (nil = milestone not reached).
		-- They are documented on the FunnelSession type. The local
		-- annotation contextually types the literal (missing optional
		-- fields are fine); an unannotated literal would trip Luau's
		-- mutable-field invariance at the sessions[] write.
		local fresh: FunnelSession = {
			sessionStart = os.time(),
		}
		sessions[userId] = fresh
		return fresh
	end
	return s
end

--- Track an analytics event for a player.
-- @param player Player instance or UserId (number)
-- @param eventName string — must be in the EVENTS catalog
-- @param fields table? — structured custom fields merged into the event
-- @return boolean — true if fired (or would-fire in no-op mode), false on validation failure
function AnalyticsService.track(player, eventName, fields)
	-- Validate the catalog. Rejecting unknown names here is the single most
	-- valuable guard: it prevents a typo in gameplay code from silently
	-- spawning a ghost event in the Roblox dashboard that no one notices.
	if type(eventName) ~= "string" or not EVENTS[eventName] then
		warn(("[Analytics] rejected unknown event: %q")
			:format(tostring(eventName)))
		return false
	end

	-- Accept either a Player instance or a raw UserId so callers in
	-- PlayerRemoving handlers (where the Player may be parented-away) work.
	local userId = userIdOf(player)
	if not userId then
		warn(("[Analytics] %s: invalid player (got %s)")
			:format(eventName, typeof(player)))
		return false
	end

	-- Enrich with funnel metadata so the dashboard doesn't need joins.
	local s = getSession(userId)
	-- Session age computed ONCE and shared by the enriched payload and the
	-- first_* stamps below. CORRECTED (review): the stamps previously read
	-- `s.session_age_s` — a field that only ever existed on `enriched`, not
	-- on the session record — so every stamp assigned nil, isFirst() gating
	-- never engaged, first_* events fired on EVERY occurrence, and the
	-- time_to_first_* fields never reached the dashboard.
	local sessionAge = os.time() - s.sessionStart
	local enriched = {
		event = eventName,
		-- userId inside customFields so the dashboard can filter/group by
		-- player (FireEvent auto-attributes to the firing context, but
		-- server-side events need the explicit field for per-player queries).
		player_user_id = userId,
		-- ISO-ish epoch seconds; dashboard converts as needed.
		ts = os.time(),
		session_start = s.sessionStart,
		session_age_s = sessionAge,
	}
	-- Merge caller-provided fields (shallow). Caller fields win on collision
	-- so gameplay code can override the defaults if it ever needs to.
	if type(fields) == "table" then
		for k, v in pairs(fields) do
			enriched[k] = v
		end
	end

	-- Stamp funnel timestamps the first time we see each milestone event.
	-- These power the time-to-first-X success metrics (PRD L511+).
	-- CORRECTED (fresh-eyes review): stamps now trigger on the `first_*`
	-- events (which fire exactly once per player alongside the every-
	-- occurrence event), not on the every-occurrence events. Previously
	-- only the first `fish_caught` carried time_to_first_catch_s; now the
	-- dedicated `first_catch` event carries it, which matches its semantic.
	if eventName == "first_cast" and not s.firstCastAt then
		s.firstCastAt = sessionAge
		enriched.time_to_first_cast_s = sessionAge
	elseif eventName == "first_catch" and not s.firstCatchAt then
		s.firstCatchAt = sessionAge
		enriched.time_to_first_catch_s = sessionAge
	elseif eventName == "first_store" and not s.firstStoreAt then
		s.firstStoreAt = sessionAge
		enriched.time_to_first_store_s = sessionAge
	elseif eventName == "first_sale" and not s.firstSaleAt then
		s.firstSaleAt = sessionAge
		enriched.time_to_first_sale_s = sessionAge
	elseif eventName == "first_upgrade" and not s.firstUpgradeAt then
		s.firstUpgradeAt = sessionAge
		enriched.time_to_first_upgrade_s = sessionAge
	end

	-- Fire-and-forget. pcall so a transient analytics backend failure never
	-- propagates into gameplay code. CORRECTED (fresh-eyes review, twice):
	--   Attempt 1: called `FireClientEvent` — a non-existent method (confused
	--     with RemoteEvent:FireClient). Every event silently failed.
	--   Attempt 2: called `FireEvent(eventName, nil, enriched)` — but Roblox
	--     docs show FireEvent takes only (category, value); the 3rd arg is
	--     dropped, so custom fields never reached the dashboard.
	--   Correct: AnalyticsService:FireCustomEvent(player, eventCategory,
	--     customData) — takes a Player instance, the event category string,
	--     and the custom fields table. This is the legacy API but it's the
	--     one that actually works for custom event tracking. (All methods on
	--     AnalyticsService are marked Deprecated in favor of the newer
	--     AnalyticsService v2 / event-based APIs, but FireCustomEvent remains
	--     functional and is the standard for V1 custom events.)
	-- Requires the original Player instance (track() may have been passed a
	-- raw UserId for PlayerRemoving callers). Resolve back to the Player.
	local svc = getEngineService()
	if not svc then
		-- No-op mode (Studio without analytics). Still return true so callers
		-- don't think the event was rejected for a validation reason.
		return true
	end
	local playerInstance = asPlayer(player)
		or Players:GetPlayerByUserId(userId)
	if not playerInstance then
		-- Player left between the call and resolution (common in PlayerRemoving).
		-- We still have the userId in `enriched.player_user_id`, but FireCustomEvent
		-- needs the Player instance. Drop the event silently — churn signals
		-- fired in onPlayerRemoving are best-effort, not critical.
		return false
	end
	local ok, err = pcall(function()
		svc:FireCustomEvent(playerInstance, eventName, enriched)
	end)
	if not ok then
		warn(("[Analytics] %s fire failed: %s"):format(eventName, tostring(err)))
	end
	return ok
end

-- Convenience: track with a Player instance (most common call shape).
-- Identical to track(player, ...) but reads better at call sites.
function AnalyticsService.trackPlayer(player, eventName, fields)
	return AnalyticsService.track(player, eventName, fields)
end

--- Check whether a milestone has already been recorded for this player.
-- Lets call sites gate `first_*` events so they fire EXACTLY once per
-- player, not on every occurrence. CORRECTED (fresh-eyes review):
-- previously the `first_*` events fired every time alongside their
-- every-occurrence counterparts, polluting the funnel metrics.
-- @param userId number
-- @param milestone string — one of: first_cast, first_catch, first_store,
--        first_sale, first_upgrade
-- @return boolean — true if this milestone has NOT been recorded yet
function AnalyticsService.isFirst(userId: number, milestone: string)
	local s = sessions[userId]
	if not s then
		-- No session yet means nothing recorded — it's the first.
		return true
	end
	if milestone == "first_cast" then return not s.firstCastAt
	elseif milestone == "first_catch" then return not s.firstCatchAt
	elseif milestone == "first_store" then return not s.firstStoreAt
	elseif milestone == "first_sale" then return not s.firstSaleAt
	elseif milestone == "first_upgrade" then return not s.firstUpgradeAt
	end
	return false
end

--- Get the per-player funnel state (which milestones the player has hit).
-- Used by onPlayerRemoving to decide whether to fire churn signals.
-- @return table with firstCastAt/firstCatchAt/firstStoreAt/firstSaleAt/firstUpgradeAt
--         (nil for milestones not yet reached)
function AnalyticsService.getFunnelState(userId: number)
	local s = sessions[userId]
	if not s then
		return {}
	end
	return {
		firstCastAt = s.firstCastAt,
		firstCatchAt = s.firstCatchAt,
		firstStoreAt = s.firstStoreAt,
		firstSaleAt = s.firstSaleAt,
		firstUpgradeAt = s.firstUpgradeAt,
	}
end

--- Clear session state when a player leaves. Prevents unbounded growth of
-- the `sessions` table across long server uptimes. Called from
-- Players.PlayerRemoving by init.server.lua (wired in TASK 11.2).
function AnalyticsService.clearSession(player)
	local userId = userIdOf(player)
	if userId and sessions[userId] then
		sessions[userId] = nil
	end
end

--- Test helper: returns the authoritative event catalog as an array.
-- Used by 11.2's wiring verification + any future test harness to confirm
-- the catalog matches the PRD list exactly.
function AnalyticsService.listEvents()
	local list = {}
	for name in pairs(EVENTS) do
		table.insert(list, name)
	end
	table.sort(list)
	return list
end

return AnalyticsService
