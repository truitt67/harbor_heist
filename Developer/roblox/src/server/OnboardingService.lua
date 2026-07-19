--!strict
-- OnboardingService.lua (EPIC 9, TASK 9.1)
-- Tracks the five Onboarding progression flags that gate PvP (8.3) and drive
-- contextual prompts (9.2). The flags live in profile.Onboarding (schema +
-- sanitize already exist, TASK 1.1) — this service is the single writer that
-- flips them on the relevant gameplay events.
--
-- DESIGN (first principles):
--   1. ONE writer. Gameplay services never touch profile.Onboarding directly
--      — they call OnboardingService.mark(session, flag). This keeps the flag
--      names in one place (a typo'd flag string would silently no-op against
--      sanitize's boolean filter, so we centralize and validate).
--   2. Idempotent + cheap. mark() early-returns if the flag is already true,
--      so callers can fire it on every event without bookkeeping.
--   3. Flags only ever go false -> true. Onboarding is one-directional; there
--      is no "un-complete." mark() refuses to clear a set flag.
--   4. Push on change. When a flag flips, stateSync.push so the client HUD /
--      prompts react immediately (9.2 consumes these).
--
-- FLAG -> EVENT MAP:
--   HasCompletedIntro        set on first join (init.server onPlayerAdded)
--   HasCaughtFirstFish       first fish_caught (FishingService)
--   HasStoredFirstFish       first fish stored (FishInventory/Aquarium)
--   HasClaimedIncome         first income claim (AquariumService)
--   HasSeenRaidExplanation   first raid window viewed (8.x; setter ready)

local OnboardingService = {}

-- Module-level deps captured in init()
local stateSync

-- The authoritative flag list. mark() validates against this so a typo'd
-- flag string warns instead of silently writing a bogus key that sanitize
-- would then persist.
local FLAGS = {
	HasCompletedIntro = true,
	HasCaughtFirstFish = true,
	HasStoredFirstFish = true,
	HasClaimedIncome = true,
	HasSeenRaidExplanation = true,
}

--- Mark an onboarding flag complete for a session.
-- Idempotent: no-ops if already set. Pushes state on the false->true edge.
-- @param session table — the DataManager session (must have .profile)
-- @param flag string — one of FLAGS
-- @return boolean — true if this call flipped the flag, false otherwise
function OnboardingService.mark(session, flag)
	if not session or not session.profile or not session.profile.Onboarding then
		return false
	end
	if not FLAGS[flag] then
		warn(("[Onboarding] rejected unknown flag: %s"):format(tostring(flag)))
		return false
	end
	local ob = session.profile.Onboarding
	if ob[flag] then
		-- Already complete — one-directional, no re-fire.
		return false
	end
	ob[flag] = true
	-- Push so client prompts/HUD react on the edge. Nil-safe (Studio tests
	-- may construct a bare session without a live player).
	if stateSync and session.player and session.player.Parent then
		stateSync.push(session)
	end
	return true
end

--- Read the current onboarding flags (for 9.2 prompts + 8.3 PvP gate).
-- Returns a shallow copy so callers can't mutate the profile accidentally.
function OnboardingService.getFlags(session)
	local ob = session and session.profile and session.profile.Onboarding
	if not ob then
		return {}
	end
	local out = {}
	for flag in pairs(FLAGS) do
		out[flag] = ob[flag] == true
	end
	return out
end

--- True when the player has completed the core first-session funnel
-- (intro + first catch + first store). Used by 8.3 to gate PvP and by the
-- first-session success metric. Income claim is optional for this gate.
function OnboardingService.hasCompletedCoreLoop(session)
	local f = OnboardingService.getFlags(session)
	return f.HasCompletedIntro == true
		and f.HasCaughtFirstFish == true
		and f.HasStoredFirstFish == true
end

function OnboardingService.init(deps)
	stateSync = deps.stateSync
end

return OnboardingService
