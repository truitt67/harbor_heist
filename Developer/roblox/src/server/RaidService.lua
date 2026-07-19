--!strict
-- RaidService.lua (EPIC 8, TASK 8.1 / gdj.1)
-- Global raid-window scheduler. PRD "Recommended V1 raid rule": raid windows
-- occur every 20-30 minutes and last 5 minutes; raids may ONLY happen while
-- a window is open (PVP-02) or in an explicitly opted-in risk zone (gdj.2).
--
-- SCOPE (this bead): the scheduler itself + client broadcast + a query API
-- for downstream beads. This module does NOT validate raid eligibility
-- (gdj.13), does NOT manage opt-in (gdj.2), and does NOT gate new players
-- (gdj.3). It answers exactly one question for the rest of the server:
-- "is a raid window open right now, and for how much longer?"
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

local rng = Random.new()

-- Window state. `windowOpen` is the authoritative flag downstream beads
-- (gdj.13 eligibility) check. The two deadline fields are os.clock()-based
-- and SERVER-LOCAL — never send them to clients raw; convert to durations.
local windowOpen = false
local windowEndsAt = 0     -- os.clock() at which the open window closes
local nextWindowAt = 0     -- os.clock() at which the next window opens (when closed)

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

function RaidService.init(deps)
	remotes = deps.remotes

	-- Late joiners get the current state once, so their HUD/countdown is
	-- correct even if they joined mid-window or mid-gap. Fired AFTER their
	-- session exists (init.server orders RaidService.init before PlayerAdded
	-- connections fire for future players; the catch-up loop at the bottom
	-- of init.server handles anyone already present).
	Players.PlayerAdded:Connect(function(player)
		-- Small delay so the client's OnClientEvent handler (connected during
		-- its own init script) is guaranteed to be listening. The client
		-- connects handlers synchronously during module load, but the remote
		-- fire could still race the player's network join — one frame is
		-- enough margin, matching RodService.equip's task.wait(0.1) pattern.
		task.wait(0.5)
		if player.Parent then
			pushState(player)
		end
	end)

	-- Catch-up for players already in the server when init runs (Studio
	-- play-solo, where PlayerAdded may have fired before this module loaded).
	for _, player in ipairs(Players:GetPlayers()) do
		pushState(player)
	end

	task.spawn(runScheduler)
end

return RaidService
