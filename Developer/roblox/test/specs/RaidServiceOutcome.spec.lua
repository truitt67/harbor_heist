-- RaidServiceOutcome.spec.lua
-- TASK 18.9.3 (k5wz.9.3): RaidService outcome-resolution authority tests.
--
-- THE anti-exploit core — regression net for 14.16 (client-authoritative hit)
-- and the stun exploit (boat-spawn bypass). Exercises the REAL submitRaidResult
-- function through the server-authoritative challenge/resolve protocol.
--
-- STRATEGY: submitRaidResult derives the tier from the client's raw marker
-- position vs the SERVER's stored zone bounds. When no victim is found
-- (Players:GetPlayers returns no match), the response is
-- {ok=true, success=false, tier=<derived>, reason="target_unavailable"} —
-- the tier is still returned, so we can test tier derivation WITHOUT a victim.
-- For statistical successChance tests, we parent a real Player to the Players
-- service so GetPlayers finds it.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Players = game:GetService("Players")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local RaidService = require(ServerScriptService.HarborHeist.RaidService)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)

	-- ================================================================
	-- Harness
	-- ================================================================

	local playerCounter = 0
	local function makeFakePlayer()
		playerCounter += 1
		local p = Instance.new("Player")
		p.UserId = 960000 + playerCounter
		p.Parent = Instance.new("Folder")
		return p
	end

	local function makeSession(player)
		local profile = PlayerProfile.default()
		return {
			player = player,
			profile = profile,
			carried = {},
		}
	end

	-- Build a real stealable fish record (matches FishInstance shape).
	local function makeFish(rarity, value)
		return {
			InstanceId = "fish-" .. tostring(math.random()),
			SpeciesId = "Bluegill",
			Rarity = rarity or "Common",
			BaseSellValue = value or 10,
			IncomePerMinute = 1,
			CaughtAtTimestamp = os.time(),
			SourceZoneId = "StarterPier",
			IsRaidProtected = false,
		}
	end

	-- Sessions table shared between stub dataManager and tests.
	local sessions = {}
	local saveCalls = {}

	-- Deps with capturing stubs. aquariumService MUST be non-nil because
	-- submitRaidResult calls aquariumService.isEligibleRaidTarget without
	-- a nil guard.
	local deps = {
		remotes = {
			notify = function(player, message, color) end,
			RaidWindowChanged = {
				FireClient = function() end,
				FireAllClients = function() end,
			},
		},
		dataManager = {
			get = function(player) return sessions[player] end,
			allSessions = function() return sessions end,
			save = function(player) table.insert(saveCalls, player) end,
		},
		stateSync = {
			push = function(session) end,
			getCapacity = function(session) return 999 end,
			invalidateIncomeCache = function(session) end,
		},
		aquariumService = {
			isEligibleRaidTarget = function(session) return true end,
			isNewPlayerProtected = function(session) return false end,
			getStealableFish = function(session)
				local out = {}
				for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
					if not fish.IsRaidProtected then
						table.insert(out, fish)
					end
				end
				return out
			end,
			refreshVisual = function(session) end,
		},
		antiExploit = nil,
		analytics = { track = function() end, isFirst = function() return false end },
		questService = { onStealAttempt = function() end },
		auditLog = { logRaidTransfer = function() end },
		dockManager = { getDock = function() return nil end },
		worldFolder = nil,
	}

	pcall(RaidService.init, deps)

	-- ================================================================
	-- Helpers
	-- ================================================================

	-- Build an active-raid entry with KNOWN, fixed zone bounds so the tier
	-- classification is deterministic. Center=0.5, matching the server's
	-- rng-drawn center but with fixed values for reproducibility.
	--
	-- perfectZoneSize=0.12 → perfectHalf=0.06 → perfect [0.44, 0.56]
	-- goodZoneSize=0.30   → goodHalf=0.15    → good    [0.35, 0.65]
	local function makeActiveRaid(targetUserId)
		return {
			targetUserId = targetUserId or 999999,
			perfectStart = 0.44,
			perfectEnd = 0.56,
			goodStart = 0.35,
			goodEnd = 0.65,
			markerSpeed = GameConfig.Raid.minigame.markerSpeed,
			startTime = os.clock() - 10, -- long enough ago that immediate submits
			-- pass the harborheist-yxdh minimum-time check (max position 1.0
			-- needs 1.25s at speed 0.8; 10s comfortably exceeds that).
			deadline = os.clock() + 999, -- far in the future
		}
	end

	-- Inject an active raid for a player (the _activeRaids export points to
	-- the real module-local table). submitRaidResult clears it on call
	-- (single-resolution), so re-inject before each invocation.
	local function injectRaid(player, raid)
		RaidService._activeRaids[player] = raid or makeActiveRaid()
	end

	-- ================================================================
	-- CASE 1: Server re-derives tier from marker position vs its own bounds
	-- ================================================================
	describe("Tier re-derivation (server-authoritative bounds)", function()
		it("classifies center of perfect zone (0.50) as 'perfect'", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			sessions[player] = session
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.tier).to.equal("perfect")
			player.Parent = nil
		end)

		it("classifies perfectStart boundary (0.44) as 'perfect' (inclusive)", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.44)
			expect(result.tier).to.equal("perfect")
			player.Parent = nil
		end)

		it("classifies perfectEnd boundary (0.56) as 'perfect' (inclusive)", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.56)
			expect(result.tier).to.equal("perfect")
			player.Parent = nil
		end)

		it("classifies good-only position (0.40) as 'good'", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			-- 0.40 is inside good [0.35,0.65] but below perfect [0.44,0.56]
			local result = RaidService.submitRaidResult(player, 0.40)
			expect(result.tier).to.equal("good")
			player.Parent = nil
		end)

		it("classifies goodStart boundary (0.35) as 'good' (inclusive)", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.35)
			expect(result.tier).to.equal("good")
			player.Parent = nil
		end)

		it("classifies goodEnd boundary (0.65) as 'good' (inclusive)", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.65)
			expect(result.tier).to.equal("good")
			player.Parent = nil
		end)

		it("classifies below good zone (0.20) as 'ok'", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.20)
			expect(result.tier).to.equal("ok")
			player.Parent = nil
		end)

		it("classifies above good zone (0.80) as 'ok'", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 0.80)
			expect(result.tier).to.equal("ok")
			player.Parent = nil
		end)

		it("clamps negative position to 0 then classifies as 'ok'", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, -0.5)
			expect(result.tier).to.equal("ok")
			player.Parent = nil
		end)

		it("clamps position > 1 to 1 then classifies as 'ok'", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, 1.5)
			expect(result.tier).to.equal("ok")
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- CASE 2: Forged tier — client cannot claim a tier; server always
	-- derives it from the raw position. The protocol accepts ONLY a number.
	-- ================================================================
	describe("Forged-tier immunity", function()
		it("an 'ok' position always yields tier='ok', never 'perfect'", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			-- Feed a position firmly in the ok zone.
			local result = RaidService.submitRaidResult(player, 0.10)
			expect(result.tier).to.equal("ok")
			expect(result.tier).never.to.equal("perfect")
			player.Parent = nil
		end)

		it("submitRaidResult accepts only a number position, not a tier string", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			-- A string is rejected as bad_input BEFORE tier derivation.
			local result = RaidService.submitRaidResult(player, "perfect")
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_input")
			player.Parent = nil
		end)

		it("a table payload claiming {tier='perfect'} is rejected as bad_input", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			local result = RaidService.submitRaidResult(player, { tier = "perfect", position = 0.5 })
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_input")
			player.Parent = nil
		end)

		it("source has no tier parameter — submitRaidResult reads only markerPosition", function()
			local source = ServerScriptService.HarborHeist.RaidService.Source
			-- The function signature must be (player, markerPosition), with no
			-- tier argument unpacked from the client payload.
			local sig = source:match("function RaidService%.submitRaidResult%([^)]*%)")
			expect(sig).to.be.ok()
			expect(sig:find("markerPosition")).to.be.ok()
			-- Must NOT accept a 'tier' parameter.
			expect(sig:lower():find("tier")).to.equal(nil)
		end)
	end)

	-- ================================================================
	-- CASE 3: successChance statistical validation (seeded RNG, >=2k rolls)
	-- Requires a victim player in Players:GetPlayers(). The victim is
	-- parented to the Players service so the victim-lookup loop finds it.
	-- ================================================================
	describe("successChance rolls (statistical)", function()
		-- Tolerance: ±3% as specified in the task. With N=2500 rolls per
		-- tier, the standard error for p=0.85 is ~0.007 (0.7%), for p=0.10
		-- is ~0.006 (0.6%). ±3% gives generous headroom for RNG variance
		-- while still catching a misconfigured constant (e.g. 0.50 vs 0.55).
		local TOLERANCE = 0.03
		local ROLLS_PER_TIER = 2500

		-- Restore the RNG to a real Random after each statistical run so
		-- we don't pollute the module-level rng for subsequent specs / the
		-- scheduler loop. _setRng replaces the shared upvalue.
		local function restoreRng()
			RaidService._setRng(Random.new())
		end

		local function statisticalRate(position)
			-- Create a victim player parented to Players so GetPlayers finds it.
			local victim = Instance.new("Player")
			victim.UserId = 970001
			victim.Name = "TestVictim"
			victim.Parent = Players

			local victimSession = makeSession(victim)
			victimSession.profile.Aquarium.RaidOptIn = true
			sessions[victim] = victimSession

			-- Attacker
			local attacker = makeFakePlayer()
			local attackerSession = makeSession(attacker)
			sessions[attacker] = attackerSession

			-- Seed the RNG for reproducibility.
			RaidService._setRng(Random.new(42))

			local successes = 0
			for _ = 1, ROLLS_PER_TIER do
				-- Re-inject the active raid (submitRaidResult clears it).
				injectRaid(attacker, makeActiveRaid(victim.UserId))
				-- Reset victim loss bookkeeping (maxLossesPerWindow=2 would
				-- otherwise cap after 2 successes and skew the rate).
				victimSession.raidWindowLosses = nil
				-- Ensure victim always has exactly one stealable fish.
				victimSession.profile.Aquarium.StoredFish = { makeFish() }
				-- Reset attacker's fish list to avoid unbounded growth.
				attackerSession.profile.Aquarium.StoredFish = {}

				local result = RaidService.submitRaidResult(attacker, position)
				if result.success then
					successes += 1
				end
			end

			local rate = successes / ROLLS_PER_TIER

			-- Cleanup
			victim.Parent = nil
			attacker.Parent = nil
			sessions[victim] = nil
			sessions[attacker] = nil
			restoreRng()

			return rate
		end

		it("perfect tier success rate ≈ 0.85 (±" .. tostring(TOLERANCE) .. ")", function()
			local rate = statisticalRate(0.50)
			local expected = GameConfig.Raid.minigame.successChance.perfect
			expect(math.abs(rate - expected) <= TOLERANCE).to.equal(true)
		end)

		it("good tier success rate ≈ 0.55 (±" .. tostring(TOLERANCE) .. ")", function()
			local rate = statisticalRate(0.40)
			local expected = GameConfig.Raid.minigame.successChance.good
			expect(math.abs(rate - expected) <= TOLERANCE).to.equal(true)
		end)

		it("ok tier success rate ≈ 0.10 (±" .. tostring(TOLERANCE) .. ")", function()
			local rate = statisticalRate(0.10)
			local expected = GameConfig.Raid.minigame.successChance.ok
			expect(math.abs(rate - expected) <= TOLERANCE).to.equal(true)
		end)
	end)

	-- ================================================================
	-- CASE 4: Failed raid — no fish transferred, attacker cooldown burned
	-- ================================================================
	describe("Failed raid (missed roll)", function()
		it("does not transfer fish when the success roll fails", function()
			local victim = Instance.new("Player")
			victim.UserId = 970101
			victim.Name = "TestVictimFailed"
			victim.Parent = Players

			local victimSession = makeSession(victim)
			victimSession.profile.Aquarium.RaidOptIn = true
			local victimFish = makeFish("Common", 10)
			table.insert(victimSession.profile.Aquarium.StoredFish, victimFish)
			sessions[victim] = victimSession

			local attacker = makeFakePlayer()
			local attackerSession = makeSession(attacker)
			sessions[attacker] = attackerSession

			-- Seed RNG so the success roll ALWAYS fails: we need
			-- rng:NextNumber() > chance. A stub that always returns 1.0
			-- guarantees every tier's chance is exceeded (all chances < 1.0).
			local alwaysFailRng = { NextNumber = function(self, a, b)
				if a and b then return b end
				return 1.0
			end }
			RaidService._setRng(alwaysFailRng)

			injectRaid(attacker, makeActiveRaid(victim.UserId))

			local result = RaidService.submitRaidResult(attacker, 0.50)

			expect(result.ok).to.equal(true)
			expect(result.success).to.equal(false)
			expect(result.tier).to.equal("perfect")
			-- Fish must still be in the victim's aquarium.
			expect(#victimSession.profile.Aquarium.StoredFish).to.equal(1)
			-- Attacker must NOT have gained a fish.
			expect(#attackerSession.profile.Aquarium.StoredFish).to.equal(0)

			-- Restore RNG.
			RaidService._setRng(Random.new())

			victim.Parent = nil
			attacker.Parent = nil
			sessions[victim] = nil
			sessions[attacker] = nil
		end)

		it("increments attacker RaidsLost on a failed raid", function()
			local victim = Instance.new("Player")
			victim.UserId = 970102
			victim.Name = "TestVictimFailed2"
			victim.Parent = Players

			local victimSession = makeSession(victim)
			victimSession.profile.Aquarium.RaidOptIn = true
			table.insert(victimSession.profile.Aquarium.StoredFish, makeFish())
			sessions[victim] = victimSession

			local attacker = makeFakePlayer()
			local attackerSession = makeSession(attacker)
			local beforeLost = attackerSession.profile.PvP.RaidsLost or 0
			sessions[attacker] = attackerSession

			local alwaysFailRng = { NextNumber = function(self, a, b)
				if a and b then return b end
				return 1.0
			end }
			RaidService._setRng(alwaysFailRng)

			injectRaid(attacker, makeActiveRaid(victim.UserId))
			RaidService.submitRaidResult(attacker, 0.50)

			expect(attackerSession.profile.PvP.RaidsLost).to.equal(beforeLost + 1)

			RaidService._setRng(Random.new())

			victim.Parent = nil
			attacker.Parent = nil
			sessions[victim] = nil
			sessions[attacker] = nil
		end)
	end)

	-- ================================================================
	-- CASE 5: Stun-exploit regression — boat spawn goes through the
	-- canonical handleSpawnRequest entry (init.server.lua prompt path).
	-- The init.server.lua Script's source is accessible directly on the
	-- HarborHeist node (Rojo compiles init.server.lua as the container Script).
	-- ================================================================
	describe("Stun-exploit regression (canonical boat spawn)", function()
		it("the ProximityPrompt handler delegates to BoatService.handleSpawnRequest", function()
			-- ServerScriptService.HarborHeist IS the init.server.lua Script
			-- (Rojo compiles a dir with init.server.lua into a Script node).
			local initSource = ServerScriptService.HarborHeist.Source
			-- The prompt handler must call handleSpawnRequest, not a
			-- hand-duplicated copy of the spawn logic. This is the fix for
			-- the stun-bypass exploit (14.16 family).
			expect(initSource).to.be.a("string")
			expect(initSource:find("BoatService.handleSpawnRequest")).to.be.ok()
		end)

		it("handleSpawnRequest checks stunUntil before spawning", function()
			local boatSource = ServerScriptService.HarborHeist.BoatService.Source
			expect(boatSource).to.be.a("string")
			-- The canonical entry point must gate on stunUntil.
			expect(boatSource:find("function BoatService.handleSpawnRequest")).to.be.ok()
			expect(boatSource:find("stunUntil")).to.be.ok()
		end)

		it("the stun check returns reason='stunned' when active", function()
			local boatSource = ServerScriptService.HarborHeist.BoatService.Source
			-- The guard must both notify AND return a rejection, not just
			-- silently skip the spawn.
			expect(boatSource:find('reason = "stunned"')).to.be.ok()
		end)
	end)

	-- ================================================================
	-- CASE 6: Duration validation — minimum + maximum time checks.
	-- harborheist-yxdh: the too_fast (minimum-time) guard is now
	-- enforced. A bot that intercepts zone bounds and reports a perfect
	-- marker position instantly is rejected — the marker sweeps 0→1 at
	-- markerSpeed units/sec, so reaching a position requires at least
	-- position/markerSpeed seconds (minus a small network grace).
	-- ================================================================
	describe("Duration validation (timing-forgery guard)", function()
		it("rejects an impossibly-fast result with reason='too_fast'", function()
			-- A fresh raid whose startTime is NOW. The client immediately
			-- reports position 0.50 (perfect-zone center). The marker would
			-- need 0.50/0.8 = 0.625s to reach 0.50; even with the 0.5s
			-- network grace, an instant submit (elapsed ~0) is impossible.
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			RaidService._activeRaids[player] = {
				targetUserId = 999999,
				perfectStart = 0.44,
				perfectEnd = 0.56,
				goodStart = 0.35,
				goodEnd = 0.65,
				markerSpeed = 0.8,
				startTime = os.clock(), -- started just now
				deadline = os.clock() + 999,
			}
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("too_fast")
			player.Parent = nil
		end)

		it("accepts a result submitted after the minimum plausible time", function()
			-- startTime = 2s ago. For position 0.50 at speed 0.8, the
			-- minimum is 0.625s; with 0.5s grace the floor is 0.125s.
			-- 2s elapsed comfortably clears it, so the submit is accepted
			-- (it reaches tier derivation → target_unavailable, but ok=true).
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			RaidService._activeRaids[player] = {
				targetUserId = 999999,
				perfectStart = 0.44,
				perfectEnd = 0.56,
				goodStart = 0.35,
				goodEnd = 0.65,
				markerSpeed = 0.8,
				startTime = os.clock() - 2,
				deadline = os.clock() + 999,
			}
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.ok).to.equal(true)
			expect(result.tier).to.equal("perfect")
			player.Parent = nil
		end)

		it("rejects a result submitted after the deadline (too_slow)", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			-- Inject a raid with a deadline in the past.
			RaidService._activeRaids[player] = {
				targetUserId = 999999,
				perfectStart = 0.44,
				perfectEnd = 0.56,
				goodStart = 0.35,
				goodEnd = 0.65,
				markerSpeed = 0.8,
				startTime = os.clock() - 1,
				deadline = os.clock() - 1, -- already expired
			}
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("too_slow")
			player.Parent = nil
		end)

		it("source has the minimum elapsed-time check (harborheist-yxdh fix)", function()
			local raidSource = ServerScriptService.HarborHeist.RaidService.Source
			-- Extract just the submitRaidResult function body.
			local submitFunc = raidSource:match("function RaidService%.submitRaidResult.-\nfunction")
			expect(submitFunc).to.be.ok()
			-- Verify it checks os.clock() > raid.deadline (maximum time).
			expect(submitFunc:find("os%.clock%(%) > raid%.deadline")).to.be.ok()
			-- Verify the minimum-time guard NOW exists (harborheist-yxdh).
			expect(submitFunc:find("too_fast")).to.be.ok()
			expect(submitFunc:find("raid%.startTime")).to.be.ok()
		end)
	end)

	-- ================================================================
	-- CASE 7: No active raid / bad input edge cases
	-- ================================================================
	describe("Edge cases", function()
		it("returns no_active_raid when no raid is in flight", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			-- Do NOT inject a raid.
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("no_active_raid")
			player.Parent = nil
		end)

		it("returns no_session when the player has no session", function()
			local player = makeFakePlayer()
			-- Do NOT register a session.
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("no_session")
			player.Parent = nil
		end)

		it("clears the active raid after a single resolution (no double-submit)", function()
			local player = makeFakePlayer()
			sessions[player] = makeSession(player)
			injectRaid(player)
			RaidService.submitRaidResult(player, 0.50)
			-- Second submit must see no active raid.
			local result = RaidService.submitRaidResult(player, 0.50)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("no_active_raid")
			player.Parent = nil
		end)
	end)
end
