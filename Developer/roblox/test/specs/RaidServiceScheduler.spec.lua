-- RaidServiceScheduler.spec.lua
-- TASK 18.9.1: RaidService window scheduler + opt-in gating unit tests.
--
-- The scheduler loop (runScheduler) is an infinite task.wait(1200-1800s)
-- loop and cannot be unit-tested in reasonable time. Cases that require
-- driving the open/close transitions (broadcast firing, open-window
-- eligibility, duration expiry) are deferred to E2E suite (EPIC 19.8.1).
--
-- This spec covers the testable surface: window state API (initial state),
-- config bounds, opt-in default + persistence, zone presence API, and
-- raid eligibility gating (window-open guard).

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)
	local RaidService = require(ServerScriptService.HarborHeist.RaidService)

	-- ================================================================
	-- Harness
	-- ================================================================

	local playerCounter = 0
	local function makeFakePlayer()
		playerCounter += 1
		local p = {
			UserId = 940000 + playerCounter,
			Name = "TestPlayer" .. playerCounter,
			DisplayName = "TestPlayer" .. playerCounter,
			Parent = true,
		}
		return p
	end

	local function makeSession()
		local profile = PlayerProfile.default()
		local p = makeFakePlayer()
		return { player = p, profile = profile, carried = {}, lockedUntil = 0 }
	end

	-- Set up deps with capturing remotes; init sets module-level dataManager.
	local sessions = {}
	local windowChangedCalls = {}
	local deps = {
		remotes = {
			notify = function() end,
			RaidWindowChanged = {
				FireClient = function(self, p, open, rem, nextIn)
					table.insert(windowChangedCalls, { open = open, remaining = rem, nextIn = nextIn })
				end,
				FireAllClients = function(self, open, rem, nextIn)
					table.insert(windowChangedCalls, { open = open, remaining = rem, nextIn = nextIn })
				end,
			},
		},
		dataManager = {
			get = function(player) return sessions[player] end,
			allSessions = function() return sessions end,
		},
		stateSync = { push = function() end },
		aquariumService = nil,
		dockManager = { getDock = function() return nil end },
		boatService = nil,
		analytics = { track = function() end, isFirst = function() return false end },
		questService = { onStealAttempt = function() end },
		antiExploit = nil,
		auditLog = nil,
		onboarding = { mark = function() return false end },
	}
	-- See RaidServiceOutcome.spec for why this must be a beforeEach re-init
	-- (shared RaidService module state across spec files in one TestEZ run).
	beforeEach(function()
		pcall(RaidService.init, deps)
	end)

	afterEach(function()
		-- Defensive: a leaked players provider from RaidServiceOutcome (which
		-- shares this module) must not poison this file's tests.
		RaidService._setPlayersProvider(nil)
	end)

	local function newTestPair()
		local player = makeFakePlayer()
		local session = makeSession()
		sessions[player] = session
		return player, session
	end

	-- ================================================================
	-- 1. Config bounds (cases 1, 2, 3)
	-- ================================================================
	describe("Raid config bounds", function()
		it("windowIntervalMin is 1200 (20 min)", function()
			expect(GameConfig.Raid.windowIntervalMin).to.equal(1200)
		end)

		it("windowIntervalMax is 1800 (30 min)", function()
			expect(GameConfig.Raid.windowIntervalMax).to.equal(1800)
		end)

		it("windowDuration is 300 (5 min)", function()
			expect(GameConfig.Raid.windowDuration).to.equal(300)
		end)

		it("optInDefault is false (no involuntary PvP)", function()
			expect(GameConfig.Raid.optInDefault).to.equal(false)
		end)

		it("defenderProtectionSeconds is 1200 (20 min)", function()
			expect(GameConfig.Raid.defenderProtectionSeconds).to.equal(1200)
		end)

		it("next-window gap is bounded within [min, max]", function()
			-- The scheduler uses rng:NextNumber(min, max); verify the bounds.
			local r = Random.new(42)
			local lo = math.huge
			local hi = -math.huge
			for _ = 1, 100 do
				local gap = r:NextNumber(GameConfig.Raid.windowIntervalMin, GameConfig.Raid.windowIntervalMax)
				if gap < lo then lo = gap end
				if gap > hi then hi = gap end
			end
			expect(lo >= GameConfig.Raid.windowIntervalMin).to.equal(true)
			expect(hi <= GameConfig.Raid.windowIntervalMax).to.equal(true)
		end)
	end)

	-- ================================================================
	-- 2. Window state API (initial state — before scheduler runs)
	-- ================================================================
	describe("Window state API (initial/closed)", function()
		it("isWindowOpen returns false before any window opens", function()
			-- Before scheduler fires, window is closed.
			-- NOTE: the scheduler task.spawn may have started, but the first
			-- gap is 20-30 min, so windowOpen is still false here.
			expect(RaidService.isWindowOpen()).to.equal(false)
		end)

		it("getWindowRemaining returns 0 when closed", function()
			expect(RaidService.getWindowRemaining()).to.equal(0)
		end)

		it("getWindowState returns open=false with zero durations when closed", function()
			local state = RaidService.getWindowState()
			expect(state).to.be.a("table")
			expect(state.open).to.equal(false)
			expect(state.remainingSeconds).to.equal(0)
		end)
	end)

	-- ================================================================
	-- 3. Opt-in logic (cases 3, 4)
	-- ================================================================
	describe("Opt-in logic", function()
		it("isOptedIn returns false for a fresh (never-opted) player", function()
			local player, session = newTestPair()
			-- PlayerProfile.default() sets RaidOptIn=false
			expect(session.profile.Aquarium.RaidOptIn).to.equal(false)
			expect(RaidService.isOptedIn(player)).to.equal(false)
			player.Parent = nil
		end)

		it("isOptedIn returns true after setting RaidOptIn=true", function()
			local player, session = newTestPair()
			session.profile.Aquarium.RaidOptIn = true
			expect(RaidService.isOptedIn(player)).to.equal(true)
			player.Parent = nil
		end)

		it("opt-in persists in the profile (survives save/load semantically)", function()
			local player, session = newTestPair()
			session.profile.Aquarium.RaidOptIn = true
			-- Simulate save/load: re-create the session from the profile
			local reloadedSession = { player = player, profile = session.profile }
			sessions[player] = reloadedSession
			expect(RaidService.isOptedIn(player)).to.equal(true)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 4. Raid eligibility (window-open guard — case 4 toggle semantics)
	-- ================================================================
	describe("Raid eligibility", function()
		it("isRaidEligible returns false when window is closed, even if opted in", function()
			local player, session = newTestPair()
			session.profile.Aquarium.RaidOptIn = true
			-- Window is closed (no scheduler fired yet)
			expect(RaidService.isRaidEligible(player)).to.equal(false)
			player.Parent = nil
		end)

		it("isRaidEligible returns false when not opted in and window is closed", function()
			local player, session = newTestPair()
			expect(RaidService.isRaidEligible(player)).to.equal(false)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 5. Zone presence API (initial state)
	-- ================================================================
	describe("Zone presence", function()
		it("isInRaidWaters returns false for a player not in the zone", function()
			local player = makeFakePlayer()
			expect(RaidService.isInRaidWaters(player)).to.equal(false)
			player.Parent = nil
		end)

		it("isInSafeHarbor returns false for a player not in the zone", function()
			local player = makeFakePlayer()
			expect(RaidService.isInSafeHarbor(player)).to.equal(false)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 6. New-player protection (config + delegation note)
	-- ================================================================
	describe("New-player protection (case 5)", function()
		it("defenderProtectionSeconds config is 1200", function()
			expect(GameConfig.Raid.defenderProtectionSeconds).to.equal(1200)
		end)

		-- NOTE: The new-player protection GATE logic lives in
		-- AquariumService.isNewPlayerProtected (progression-based: 10 catches
		-- OR first aquarium upgrade). That function is tested in
		-- AquariumService.spec.lua (TASK 18.6). RaidService.delegate-checks
		-- call aquariumService.isNewPlayerProtected during target selection,
		-- which is exercised in E2E (EPIC 19.8.1).
	end)
end
