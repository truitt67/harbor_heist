--!strict
-- RaidService.lua (EPIC 8, TASK 8.1 / gdj.1)
-- Global raid-window scheduler. PRD "Recommended V1 raid rule": raid windows
-- occur every 20-30 minutes and last 5 minutes; raids may ONLY happen while
-- a window is open (PVP-02) or in an explicitly opted-in risk zone (gdj.2).
--
-- SCOPE: the scheduler itself + client broadcast + a query API for
-- downstream beads, PLUS the Raid Waters pier opt-in signal (TASK 8.2 /
-- gdj.2, PRD PVP-02): players opt in via the aquarium-panel dock flag
-- (RequestToggleRaidOptIn, owned by AquariumService with the gdj.3
-- new-player gate) or by standing in the physical Raid Waters pier zone
-- (tracked here). Only opted-in aquariums can be targeted (gdj.13 consumes
-- RaidService.isRaidEligible). This module does NOT gate new players
-- (gdj.3) or resolve raid outcomes (gdj.14).
--
-- DESIGN (first principles):
--   1. Server-authoritative clock. The server owns window state; clients
--      only ever receive DURATIONS (remainingSeconds / nextWindowInSeconds),
--      never absolute os.clock() values — os.clock() is machine-local and
--      meaningless across the server/client boundary. A client that wants a
--      countdown starts its own timer from the duration in the broadcast.
--   2. Broadcast on edges, not ticks. Window state changes twice per cycle
--      (open, close), so we fire RaidWindowChanged exactly on those edges
--      instead of spamming every second. Late joiners get the current state
--      pushed once via the PlayerAdded hook.
--   3. Randomized interval. Each inter-window gap is drawn independently
--      from [windowIntervalMin, windowIntervalMax] so players can't set a
--      watch by the last window — the PRD's "20-30 minutes" is a range on
--      purpose (anticipation without perfect predictability).
--   4. No per-player state here. Window state is global. Per-player raid
--      state (opt-in, cooldowns, immunity) belongs to gdj.2/gdj.13 and will
--      live in session/profile fields, not in this module.

local Players = game:GetService("Players")
local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local RaidService = {}

-- Module-level deps captured in init()
local remotes: any = nil
local dataManager: any = nil
local stateSync: any = nil
-- TASK 8.5a (gdj.13): extra deps for server-validated target selection.
-- aquariumService owns the new-player gate + per-target eligibility helpers
-- (isEligibleRaidTarget / isNewPlayerProtected / getStealableFish); we READ
-- them without duplicating the logic. antiExploit rate-limits the remote.
-- analytics records how often the raid UI is opened and how many targets exist.
local aquariumService: any = nil
local antiExploit: any = nil
local analytics: any = nil

local rng = Random.new()

-- Window state. `windowOpen` is the authoritative flag downstream beads
-- (gdj.13 eligibility) check. The two deadline fields are os.clock()-based
-- and SERVER-LOCAL — never send them to clients raw; convert to durations.
local windowOpen = false
local windowEndsAt = 0     -- os.clock() at which the open window closes
local nextWindowAt = 0     -- os.clock() at which the next window opens (when closed)

-- TASK 8.2 (gdj.2): players currently standing in the Raid Waters pier zone.
-- [player] = true; populated by zone Touched/TouchEnded in init. Zone
-- presence is a LIVE opt-in signal (leaving the zone revokes it), while the
-- dock flag (profile.Aquarium.RaidOptIn) is a STICKY opt-in signal that
-- persists until toggled off.
local playersInRaidZone: {[Player]: boolean} = {}

--- True while a raid window is open. gdj.13 (eligibility) gates on this.
function RaidService.isWindowOpen()
	return windowOpen
end

--- Seconds until the current window closes (0 when no window is open).
function RaidService.getWindowRemaining()
	if not windowOpen then
		return 0
	end
	return math.max(0, windowEndsAt - os.clock())
end

--- Seconds until the next window opens (0 while a window is open).
function RaidService.getNextWindowIn()
	if windowOpen then
		return 0
	end
	return math.max(0, nextWindowAt - os.clock())
end

--- Duration-safe state payload for clients. Durations only, no absolute
--- clock values — safe to send over the wire.
function RaidService.getWindowState()
	return {
		open = windowOpen,
		remainingSeconds = RaidService.getWindowRemaining(),
		nextWindowInSeconds = RaidService.getNextWindowIn(),
	}
end

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 8.2 (gdj.2): RAID OPT-IN (PRD PVP-02)
-- Two opt-in signals, both server-read, both honest about scope:
--   1. Dock flag — profile.Aquarium.RaidOptIn (persisted, toggled via the
--      aquarium panel RAID toggle or the RequestToggleRaidOptIn remote).
--      Sticky: stays on until the player turns it off. This is the "enable
--      a dock flag before the window closes" path from the PRD.
--   2. Raid Waters pier — live zone presence (playersInRaidZone). Standing
--      on the marked pier counts as opting in for as long as you stay.
-- ════════════════════════════════════════════════════════════════════════════

--- Is this player CURRENTLY standing in the Raid Waters pier zone?
function RaidService.isInRaidWaters(player: Player): boolean
	return playersInRaidZone[player] == true
end

--- Dock-flag opt-in (persisted profile field), default false (PVP-02).
function RaidService.isOptedIn(player: Player): boolean
	local session = dataManager and dataManager.get(player)
	if not session then
		return false
	end
	return session.profile.Aquarium.RaidOptIn == true
end

--- Full raid-eligibility check consumed by gdj.13 (target selection):
--- window must be open AND the player must have opted in by either path.
--- gdj.3 will layer new-player protection on top of this.
function RaidService.isRaidEligible(player: Player): boolean
	if not windowOpen then
		return false
	end
	return RaidService.isOptedIn(player) or RaidService.isInRaidWaters(player)
end

-- ════════════════════════════════════════════════════════════════════════════
-- TASK 8.5a (gdj.13): RAID TARGET SELECTION + ELIGIBILITY VALIDATION
-- PRD PVP-02 (window/opt-in), PVP-04 (lock state for the raid UI),
-- PVP-06 (attacker cooldown + defender protection), PVP-07 (per-victim
-- cooldown), PVP-10 (server is the sole validator). FIRST half of the split
-- raid flow: enumerate which aquariums an attacker may target right now and
-- validate the attacker's own eligibility. Does NOT resolve any raid outcome
-- (fish transfer, cooldown WRITE, defender immunity WRITE) — that is gdj.14.
--
-- Cooldown storage: session-scoped os.clock() fields, consistent with the
-- existing stun/lock runtime fields (session.stunUntil, session.lockedUntil).
--   session.raidAttackLastAt                 os.clock() of the attacker's last raid (gdj.14 writes)
--   session.raidTargetCooldowns[defenderId]  os.clock() expiry of the per-victim gate (gdj.14 writes)
-- These reset on rejoin (a documented V1 limitation shared with lock-cooldown
-- enforcement); profile.PvP timestamps exist for a future cross-session pass.
-- ════════════════════════════════════════════════════════════════════════════

--- Attacker raid cooldown (PRD PVP-06). Reads session.raidAttackLastAt
--- (written by gdj.14 after a raid). Returns (onCooldown, remainingSeconds).
function RaidService.isAttackerOnCooldown(session: any)
	local last = (session and session.raidAttackLastAt) or 0
	local cooldownEnd = last + GameConfig.Raid.raiderCooldownSeconds
	local now = os.clock()
	if cooldownEnd > now then
		return true, math.ceil(cooldownEnd - now)
	end
	return false, 0
end

--- Per-victim cooldown (PRD PVP-07). Reads session.raidTargetCooldowns.
--- Returns (onCooldown, remainingSeconds).
function RaidService.isVictimOnCooldown(session: any, targetUserId: number)
	local cooldowns = session and session.raidTargetCooldowns
	if not cooldowns then
		return false, 0
	end
	local expiry = cooldowns[targetUserId]
	if not expiry then
		return false, 0
	end
	local now = os.clock()
	if expiry > now then
		return true, math.ceil(expiry - now)
	end
	return false, 0
end

--- Full attacker eligibility gate for the raid flow (PRD PVP-02 / PVP-06).
--- Window open + opted in (dock flag OR Raid Waters zone) + not new-player
--- protected + not stunned + not on raider cooldown. AquariumService owns the
--- new-player gate (single source of truth); this composes it with the
--- raid-flow gates only RaidService can see (window, zone, cooldown).
--- Returns (canRaid, reason, extra) where extra may carry cooldownRemaining.
function RaidService.validateAttacker(player: Player, session: any)
	if not windowOpen then
		return false, "window_closed"
	end
	if not (RaidService.isOptedIn(player) or RaidService.isInRaidWaters(player)) then
		return false, "not_opted_in"
	end
	if aquariumService and aquariumService.isNewPlayerProtected(session) then
		return false, "new_player_protected"
	end
	if session.stunUntil and session.stunUntil > os.clock() then
		return false, "stunned"
	end
	local onCd, remaining = RaidService.isAttackerOnCooldown(session)
	if onCd then
		return false, "attacker_cooldown", { cooldownRemaining = remaining }
	end
	return true, "ok"
end

--- Enumerate the aquariums `player` may raid right now. Pure server
--- validation (PVP-10): re-checks window state and every eligibility rule at
--- call time, so a stale target list can never authorize a raid. Returns a
--- payload shaped for the client raid UI (8.12). No fish is transferred.
function RaidService.getRaidTargets(player: Player)
	local session = dataManager and dataManager.get(player)
	if not session then
		return { ok = false, reason = "no_session" }
	end
	local canRaid, reason, extra = RaidService.validateAttacker(player, session)
	local response = {
		ok = true,
		canRaid = canRaid,
		reason = reason,
		windowOpen = windowOpen,
		windowRemaining = RaidService.getWindowRemaining(),
		nextWindowInSeconds = RaidService.getNextWindowIn(),
		cooldownRemaining = 0,
		targets = {},
	}
	if extra and extra.cooldownRemaining then
		response.cooldownRemaining = extra.cooldownRemaining
	end
	-- Ineligible attacker / closed window: empty target list. The client UI
	-- still gets window state + reason so it can show a countdown/message,
	-- and no targets leak outside an open window (PVP-02).
	if not canRaid then
		return response
	end
	-- allSessions() returns the LIVE sessions table (DataManager.remove mutates
	-- it synchronously on leave), so snapshot before iterating to avoid
	-- "dictionary modified during iteration" if a player leaves mid-loop.
	local snapshot = {}
	if dataManager then
		for k, s in pairs(dataManager.allSessions()) do
			snapshot[k] = s
		end
	end
	-- Build the target list in a local first (matches the getStealableFish
	-- `local out = {}` pattern), then attach it to the response. Keeps strict
	-- mode happy with a clean array element type and avoids mutating a field
	-- of the response literal during construction.
	local targets = {}
	for _, targetSession in pairs(snapshot) do
		local targetPlayer = targetSession and targetSession.player
		if targetPlayer and targetPlayer.Parent and targetPlayer ~= player then
			-- PVP-07: skip defenders this attacker is still on per-victim
			-- cooldown for, before the (slightly heavier) eligibility check.
			local onVictimCd = RaidService.isVictimOnCooldown(session, targetPlayer.UserId)
			if not onVictimCd and aquariumService then
				local eligible = aquariumService.isEligibleRaidTarget(targetSession)
				if eligible then
					local stealable = aquariumService.getStealableFish(targetSession)
					table.insert(targets, {
						userId = targetPlayer.UserId,
						name = targetPlayer.Name,
						displayName = targetPlayer.DisplayName,
						dockIndex = targetSession.dockIndex or 0,
						stealableCount = #stealable,
					})
				end
			end
		end
	end
	response.targets = targets
	if analytics then
		pcall(function()
			analytics.track(player, "raid_targets_requested", { targetCount = #targets })
		end)
	end
	return response
end

-- NOTE: the opt-in TOGGLE writer lives in AquariumService
-- (remotes.RequestToggleRaidOptIn handler, gdj.3) — it applies the DEC-4
-- new-player gate before flipping profile.Aquarium.RaidOptIn. RaidService
-- deliberately does NOT expose a second writer; this module only READS the
-- flag and owns the Raid Waters zone signal.
-- Push the current window state to one player (join/resync) or everyone
-- (edge transitions). Always sends DURATIONS; client runs its own countdown.
local function pushState(playerOrNil)
	local state = RaidService.getWindowState()
	if playerOrNil then
		remotes.RaidWindowChanged:FireClient(playerOrNil, state.open, state.remainingSeconds, state.nextWindowInSeconds)
	else
		remotes.RaidWindowChanged:FireAllClients(state.open, state.remainingSeconds, state.nextWindowInSeconds)
	end
end

-- The scheduler loop. One task for the whole server lifetime; state lives in
-- module upvalues so task.spawn restart hazards don't apply (this spawns
-- exactly once from init).
local function runScheduler()
	local cfg = GameConfig.Raid
	while true do
		-- Gap phase: wait a random interval, then open.
		local gap = rng:NextNumber(cfg.windowIntervalMin, cfg.windowIntervalMax)
		nextWindowAt = os.clock() + gap
		task.wait(gap)

		-- Open phase.
		windowOpen = true
		windowEndsAt = os.clock() + cfg.windowDuration
		nextWindowAt = 0
		pushState(nil)

		task.wait(cfg.windowDuration)

		-- Close phase.
		windowOpen = false
		windowEndsAt = 0
		pushState(nil)
	end
end

-- TASK 8.2 (gdj.2): find the player whose character contains the hit part.
local function playerFromHit(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

-- TASK 8.2 (gdj.2): wire the physical Raid Waters pier zone built by
-- WorldBuilder.buildRaidWaters. Entering = live opt-in; leaving = revoke.
-- TOUCHED SPAM FIX: Touched fires per limb per physics step. We track a
-- per-player touch count so multi-limb contact doesn't spam notify/push,
-- and TouchEnded only revokes when ALL limbs have left. TouchEnded is also
-- notoriously unreliable in Roblox, so we also poll overlapping parts as a
-- fallback (see pollRaidZone below).
local touchCounts: {[Player]: number} = {}
local lastNotifyAt: {[Player]: number} = {}

local function watchRaidZone(zone: BasePart)
	zone.Touched:Connect(function(hit)
		local plr = playerFromHit(hit)
		if not plr then return end
		local count = touchCounts[plr] or 0
		touchCounts[plr] = count + 1
		if playersInRaidZone[plr] then
			return
		end
		playersInRaidZone[plr] = true
		local session = dataManager and dataManager.get(plr)
		if session and stateSync then
			stateSync.push(session)
		end
		local now = os.clock()
		if (now - (lastNotifyAt[plr] or 0)) > 5 then
			lastNotifyAt[plr] = now
			remotes.notify(plr, "You entered RAID WATERS — you are opted in to raids while you stay here!", Color3.fromRGB(255, 120, 120))
		end
	end)
	zone.TouchEnded:Connect(function(hit)
		local plr = playerFromHit(hit)
		if not plr then return end
		local count = (touchCounts[plr] or 1) - 1
		if count <= 0 then
			touchCounts[plr] = nil
			if playersInRaidZone[plr] then
				playersInRaidZone[plr] = nil
				local session = dataManager and dataManager.get(plr)
				if session and stateSync then
					stateSync.push(session)
				end
			end
		else
			touchCounts[plr] = count
		end
	end)
end

local function pollRaidZone(zone: BasePart)
	task.spawn(function()
		while true do
			task.wait(1)
			if not zone.Parent then break end
			local ok, overlapping = pcall(function()
				return workspace:GetPartBoundsInBox(zone.CFrame, zone.Size)
			end)
			if not ok then break end
			local seen: {[Player]: boolean} = {}
			for _, part in ipairs(overlapping) do
				local plr = playerFromHit(part)
				if plr then seen[plr] = true end
			end
			for plr in pairs(playersInRaidZone) do
				if not seen[plr] and (touchCounts[plr] or 0) <= 0 then
					playersInRaidZone[plr] = nil
					touchCounts[plr] = nil
					local session = dataManager and dataManager.get(plr)
					if session and stateSync then
						stateSync.push(session)
					end
				end
			end
		end
	end)
end

function RaidService.init(deps)
	remotes = deps.remotes
	dataManager = deps.dataManager
	stateSync = deps.stateSync
	-- TASK 8.5a (gdj.13): target selection reuses AquariumService's eligibility
	-- helpers and is rate-limited + analysed via the shared services.
	aquariumService = deps.aquariumService
	antiExploit = deps.antiExploit
	analytics = deps.analytics

	-- NOTE: RequestToggleRaidOptIn.OnServerInvoke is owned by
	-- AquariumService.init (gdj.3, runs before this init in init.server).
	-- Do NOT assign a handler here — an earlier draft of gdj.2 did, and it
	-- silently overwrote AquariumService's new-player-gated version.

	-- TASK 8.5a (gdj.13): GetRaidTargets — server-validated target list for
	-- the client raid UI (PRD PVP-10). Enumerates eligible aquariums without
	-- resolving any outcome (that is gdj.14 / RequestRaidAttempt).
	remotes.GetRaidTargets.OnServerInvoke = function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "get_raid_targets")
			if not ok then
				return { ok = false, reason = reason }
			end
		end
		return RaidService.getRaidTargets(player)
	end

	-- TASK 8.2 (gdj.2): physical Raid Waters pier zone.
	local worldFolder = deps.worldFolder
	local raidZone = worldFolder and worldFolder:FindFirstChild("RaidWaters") and worldFolder.RaidWaters:FindFirstChild("Zone")
	if raidZone then
		watchRaidZone(raidZone)
		pollRaidZone(raidZone)
	else
		warn("[HarborHeist] RaidWaters zone not found — Raid Waters opt-in path disabled.")
	end

	-- Late joiners get the current state once, so their HUD/countdown is
	-- correct even if they joined mid-window or mid-gap. Fired AFTER their
	-- session exists (init.server orders RaidService.init before PlayerAdded
	-- connections fire for future players; the catch-up loop at the bottom
	-- of init.server handles anyone already present).
	-- Also hooks CharacterAdded for respawn cleanup (TouchEnded is unreliable
	-- when character is destroyed mid-touch).
	Players.PlayerAdded:Connect(function(player)
		task.wait(0.5)
		if player.Parent then
			pushState(player)
		end
		player.CharacterAdded:Connect(function()
			playersInRaidZone[player] = nil
			touchCounts[player] = nil
		end)
	end)

	-- Catch-up for players already in the server when init runs (Studio
	-- play-solo, where PlayerAdded may have fired before this module loaded).
	for _, player in ipairs(Players:GetPlayers()) do
		pushState(player)
		player.CharacterAdded:Connect(function()
			playersInRaidZone[player] = nil
			touchCounts[player] = nil
		end)
	end

	-- TASK 8.2 (gdj.2): drop zone-presence when a player leaves so the
	-- playersInRaidZone table can't leak stale Player references.
	Players.PlayerRemoving:Connect(function(player)
		playersInRaidZone[player] = nil
		touchCounts[player] = nil
		lastNotifyAt[player] = nil
	end)

	task.spawn(runScheduler)
end

return RaidService
