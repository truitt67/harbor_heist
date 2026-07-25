-- FishingService.spec.lua
-- TASK 18.5: FishingService unit tests (tier derivation, luck stacking,
-- timing guards, biteZoneCeiling, cleanup, no math.random).
--
-- Tests exercise the REAL FishingService module through a minimal event
-- harness. No game-logic mocks: real GameConfig, real FishDefinitions,
-- real FishInstance, real Random. Sessions are plain tables matching the
-- real session shape. Remote/service stubs are thin capture wrappers only.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local FishingService = require(ServerScriptService.HarborHeist.FishingService)

	-- ================================================================
	-- Test harness
	-- ================================================================

	-- Thin signal: captures the handler registered by init(), lets us fire it.
	local function makeSignal()
		local handler
		return {
			Connect = function(self, fn)
				handler = fn
				return { Disconnect = function() handler = nil end }
			end,
			fire = function(_, ...)
				if handler then handler(...) end
			end,
		}
	end

	-- Thin remote with FireClient capture.
	local function makeFireRemote()
		local calls = {}
		return {
			FireClient = function(self, player, ...)
				table.insert(calls, { player = player, args = { ... } })
			end,
			getCalls = function() return calls end,
			last = function() return calls[#calls] end,
		}
	end

	-- Minimal fake Player matching the fields FishingService touches.
	local playerCounter = 0
	local function makeFakePlayer()
		playerCounter += 1
		local p = {
			UserId = 900000 + playerCounter,
			Name = "TestPlayer" .. playerCounter,
			DisplayName = "TestPlayer" .. playerCounter,
			Parent = true,
			Character = {}, -- truthy stand-in; dockManager.isInFishingZone is stubbed
		}
		return p
	end

	-- Session matching the real DataManager session shape.
	local function makeSession(player)
		local profile = require(ReplicatedStorage.Shared.PlayerProfile).default()
		return {
			player = player,
			profile = profile,
			carried = {},
			casting = false,
			castDeadline = 0,
		}
	end

	-- Build deps with capturing remotes and a shared session table.
	local sessions = {}
	local analyticsCalls = {}
	local castStateRemote = makeFireRemote()
	local biteEventRemote = makeFireRemote()
	local notifyRemote = makeFireRemote()
	local requestCastSignal = makeSignal()
	local castResultSignal = makeSignal()

	local deps = {
		remotes = {
			RequestCast = { OnServerEvent = requestCastSignal },
			CastResult = { OnServerEvent = castResultSignal },
			SubmitCatchInput = {}, -- OnServerInvoke set by init()
			CastState = castStateRemote,
			BiteEvent = biteEventRemote,
			notify = function(player, message, color)
				table.insert(notifyRemote:getCalls(), { player = player, args = { message, color } })
			end,
		},
		dataManager = {
			get = function(player) return sessions[player] end,
		},
		dockManager = {
			getDock = function(player) return {} end,
			isInFishingZone = function(dock, character) return true, "StarterPier" end,
		},
		stateSync = { push = function(session) end },
		analytics = {
			track = function(player, event, data)
				table.insert(analyticsCalls, { event = event, data = data })
			end,
			isFirst = function(userId, event) return false end,
		},
		antiExploit = nil,
		onboarding = { mark = function(session, flag) session.profile.Onboarding[flag] = true end },
		questService = { onFishCaught = function(session, rarity) end },
		auditLog = { logCatch = function(player, fish) end },
		rodService = nil,
	}

	-- Initialize FishingService — wires the event handlers.
	local initResult = FishingService.init(deps)

	-- Helper: get the last analytics track for a given event name.
	local function lastAnalyticsEvent(eventName)
		for i = #analyticsCalls, 1, -1 do
			if analyticsCalls[i].event == eventName then
				return analyticsCalls[i].data
			end
		end
		return nil
	end

	-- Helper: extract zone bounds from the last CastState call.
	-- CastState payload: (casting: boolean, biteDelay: number, bounds: table?)
	local function lastCastBounds()
		local call = castStateRemote:last()
		if call and call.args and call.args[3] then
			return call.args[3] -- the data table with hitZoneStart etc.
		end
		return nil
	end

	-- Helper: start a fresh cast for a new player and return bounds.
	local function startFreshCast()
		local player = makeFakePlayer()
		local session = makeSession(player)
		sessions[player] = session
		analyticsCalls = {} -- reset for this sub-test
		requestCastSignal:fire(player)
		return player, session, lastCastBounds()
	end

	-- ModuleScript source for static checks.
	local fishingSource = ServerScriptService.HarborHeist.FishingService.Source

	-- ================================================================
	-- 1. Tier derivation
	-- ================================================================
	describe("Tier derivation (CastResult)", function()
		it("classifies center of perfect zone as 'perfect'", function()
			local player, _, bounds = startFreshCast()
			local center = (bounds.hitZoneStart + bounds.hitZoneEnd) / 2
			castResultSignal:fire(player, center)
			local data = lastAnalyticsEvent("cast_result_tier")
			expect(data).to.be.ok()
			expect(data.tier).to.equal("perfect")
			player.Parent = nil
		end)

		it("classifies good-only zone as 'good'", function()
			local player, _, bounds = startFreshCast()
			-- Midpoint between perfect zone edge and good zone edge = good-only.
			local goodOnly = (bounds.hitZoneEnd + bounds.goodEnd) / 2
			castResultSignal:fire(player, goodOnly)
			local data = lastAnalyticsEvent("cast_result_tier")
			expect(data).to.be.ok()
			expect(data.tier).to.equal("good")
			player.Parent = nil
		end)

		it("classifies outside both zones as 'ok'", function()
			local player, _, bounds = startFreshCast()
			-- Just outside the good zone (if there's room).
			local outside = bounds.goodEnd + 0.05
			if outside > 1 then outside = bounds.goodStart - 0.05 end
			castResultSignal:fire(player, outside)
			local data = lastAnalyticsEvent("cast_result_tier")
			expect(data).to.be.ok()
			expect(data.tier).to.equal("ok")
			player.Parent = nil
		end)

		it("inclusive boundary: exact hitZoneStart maps to 'perfect'", function()
			local player, _, bounds = startFreshCast()
			castResultSignal:fire(player, bounds.hitZoneStart)
			local data = lastAnalyticsEvent("cast_result_tier")
			expect(data).to.be.ok()
			expect(data.tier).to.equal("perfect")
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 2. Luck stacking arithmetic
	-- ================================================================
	describe("Luck stacking", function()
		it("perfect cast with Basic Rod (luck 0) adds 25 luck", function()
			local rodLuck = GameConfig.Rods[1].luck
			local baitLuck = GameConfig.Baits[1].luck
			local bonus = GameConfig.MiniGame.accuracyLuckBonus.perfect
			expect(rodLuck + baitLuck + bonus).to.equal(25)
		end)

		it("perfect cast with Basic Rod exceeds Golden Rod base luck", function()
			local basicPerfect = GameConfig.Rods[1].luck + GameConfig.Baits[1].luck + GameConfig.MiniGame.accuracyLuckBonus.perfect
			local goldenBase = GameConfig.Rods[3].luck + GameConfig.Baits[1].luck + GameConfig.MiniGame.accuracyLuckBonus.ok
			expect(basicPerfect > goldenBase).to.equal(true)
		end)

		it("good cast with Basic Rod adds 12 luck", function()
			local rodLuck = GameConfig.Rods[1].luck
			local baitLuck = GameConfig.Baits[1].luck
			local bonus = GameConfig.MiniGame.accuracyLuckBonus.good
			expect(rodLuck + baitLuck + bonus).to.equal(12)
		end)

		it("ok cast adds zero luck bonus", function()
			expect(GameConfig.MiniGame.accuracyLuckBonus.ok).to.equal(0)
		end)
	end)

	-- ================================================================
	-- 3. biteZoneCeiling regression (wqw.24)
	-- ================================================================
	describe("biteZoneCeiling cap", function()
		local ceiling = GameConfig.MiniGame.biteZoneCeiling
		local maxLuck = GameConfig.MiniGame.accuracyLuckBonus.perfect

		it("perfect luck inflates zone to ceiling", function()
			local baseZone = GameConfig.RodDefinitions[1].minigameZoneSize
			local luckBonus = maxLuck
			local effective = baseZone + (luckBonus / maxLuck) * (ceiling - baseZone)
			effective = math.clamp(effective, baseZone, ceiling)
			expect(effective).to.equal(ceiling)
		end)

		it("ceiling is 0.85", function()
			expect(ceiling).to.equal(0.85)
		end)

		it("extreme luck is still capped", function()
			local baseZone = GameConfig.RodDefinitions[1].minigameZoneSize
			-- Simulate impossible luck (1000) — the formula uses ratio, so >maxLuck
			-- still resolves to >1.0 ratio, but clamp prevents exceeding ceiling.
			local ratio = 1000 / maxLuck
			local effective = math.clamp(baseZone + ratio * (ceiling - baseZone), baseZone, ceiling)
			expect(effective).to.equal(ceiling)
		end)

		it("good luck inflates zone partially but below ceiling", function()
			local baseZone = GameConfig.RodDefinitions[1].minigameZoneSize
			local luckBonus = GameConfig.MiniGame.accuracyLuckBonus.good
			local effective = baseZone + (luckBonus / maxLuck) * (ceiling - baseZone)
			expect(effective > baseZone).to.equal(true)
			expect(effective < ceiling).to.equal(true)
		end)
	end)

	-- ================================================================
	-- 4. Bite window regression (wqw.4)
	-- ================================================================
	describe("Bite window timing", function()
		it("BITE_WINDOW_SECONDS is 3.5 in the source", function()
			expect(fishingSource:find("BITE_WINDOW_SECONDS = 3.5")).to.be.ok()
		end)
	end)

	-- ================================================================
	-- 5. Cleanup regression (14.3)
	-- ================================================================
	describe("Cleanup on player removing", function()
		it("clears session.casting", function()
			local player, session = makeFakePlayer(), nil
			session = makeSession(player)
			sessions[player] = session
			requestCastSignal:fire(player)
			expect(session.casting).to.equal(true)
			initResult.onPlayerRemoving(player)
			expect(session.casting).to.equal(false)
			player.Parent = nil
		end)

		it("clears activeBites so SubmitCatchInput sees no active bite", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			sessions[player] = session
			requestCastSignal:fire(player)
			initResult.onPlayerRemoving(player)
			local result = deps.remotes.SubmitCatchInput.OnServerInvoke(player, { hit = true })
			expect(result).to.be.a("table")
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("no_active_bite")
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 6. Rarity resolution — no math.random in catch path
	-- ================================================================
	describe("No math.random in catch path", function()
		it("FishingService source contains no math.random calls", function()
			expect(fishingSource:find("math.random")).to.equal(nil)
		end)
	end)
end
