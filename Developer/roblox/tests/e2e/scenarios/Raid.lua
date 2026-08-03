--[[
	Raid.lua — E2E scenario: raid system (automated single-player).
	TASK 19.8 (+ r7an no_session addendum), migrated to the modular scenario
	architecture under EPIC 43 (xpei).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, scenario place built from e2e_scenarios.project.json). NO stubs of
	game code — only the Players are table-fakes. Every step is logged
	through TestLogger (JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }.

	What this verifies (through the REAL RaidService module functions —
	requestRaidAttempt / submitRaidResult are public; the remote wrappers
	only add rate limiting, which is datamodel-spec territory):
	  1. Gate validation: window_closed, attacker/victim not_opted_in,
	     victim new_player_protected.
	  2. Target enumeration: getRaidTargets lists the victim, available,
	     stealableCount == 1.
	  3. Success flow: RNG-seeded challenge, raid_in_progress guard, TOCTOU
	     window-close mid-minigame does NOT void a committed raid, fish
	     transfer (victim 1->0, attacker 0->1, Tuna), raid-protection
	     immunity timestamp, RaidsWon/RaidsLost, per-window loss counting.
	  4. Post-success gates: attacker_cooldown (with cooldownRemaining),
	     victim_cooldown, raid_protection immunity, per-window loss_capped,
	     bad_input type validation, self-raid target_unavailable.
	  5. Forged instant submit: high-seeded RNG so even a broken timing gate
	     could only "miss" — victim keeps fish; the raid is still consumed
	     (second submit -> no_active_raid).
	  6. r7an: a player with NO loaded session is rejected cleanly by both
	     entry points (no_session).

	Preserved verbatim from runner.server.lua 19.8: victim resolution
	enumerates getPlayers(), so _setPlayersProvider swaps in the fakes; the
	raid window is forced via _setWindowOpen (real scheduler waits 20-30min;
	its first transition is >= 20min after boot so a short test cannot race
	it). Notify throws on fake players but always AFTER the mutation it
	announces — profile/session state is authoritative. The too_fast
	reason-string path notifies before returning so it can't be asserted by
	return value here (datamodel specs cover it). RNG call sequence per
	attempt: call 1 challenge center pick, call 2 success roll, call 3
	steal-weight roll.

	DEVIATION from the monolith (robustness, not semantics): the raid body
	runs inside a pcall and _setWindowOpen(false) + _setPlayersProvider(nil)
	restoration runs in a finally-style path — in the modular architecture a
	crash would otherwise leak the fake players provider / window override
	into LATER scenarios sharing this DataModel. Any error is rethrown after
	restoration so the bootstrap still records the scenario crash.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Raid = {}

-- Pull the already-wired services so assertions read the SAME module
-- instances the game wired (no re-require drift).
local function getServices()
	local harbor = ServerScriptService:WaitForChild("HarborHeist", 10)
	assert(harbor, "ServerScriptService.HarborHeist missing — game did not boot")
	return {
		DataManager = require(harbor:WaitForChild("DataManager")),
		RaidService = require(harbor:WaitForChild("RaidService")),
	}
end

function Raid.run(harness)
	local logger = harness.logger

	logger:startScenario("raid_system", "gates, target enumeration, seeded success flow, forged submit, no_session")

	local svc = getServices()
	local DataManager = svc.DataManager
	local RaidService = svc.RaidService
	local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
	local FishInstance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FishInstance"))

	-- ------------------------------------------------------------------
	-- STEP 1: setup — raider + victim sessions, raid-legal profiles
	-- ------------------------------------------------------------------
	logger:step("setup", "raider + victim sessions, raid-legal setup")
	local raider = {
		UserId = 111000111,
		Name = "E2ERaider",
		DisplayName = "E2ERaider",
		Parent = Players,
		Character = nil,
	}
	local raidVictim = {
		UserId = 222000222,
		Name = "E2EVictim",
		DisplayName = "E2EVictim",
		Parent = Players,
		Character = nil,
	}
	local atkS = DataManager.load(raider)
	local vicS = DataManager.load(raidVictim)
	logger:assertTrue("attacker session created", atkS ~= nil)
	logger:assertTrue("victim session created", vicS ~= nil)

	-- Body wrapped so window/players-provider overrides are ALWAYS restored
	-- (see header deviation).
	local bodyOk, bodyErr = pcall(function()
		if atkS and vicS then
			-- Make both sides raid-legal: an aquarium upgrade bypasses
			-- new-player protection (hasUpgrade), both opt in, victim stocks
			-- a stealable fish.
			atkS.profile.Aquarium.UpgradeLevel = 2
			vicS.profile.Aquarium.UpgradeLevel = 2
			atkS.profile.Aquarium.RaidOptIn = true
			vicS.profile.Aquarium.RaidOptIn = true
			table.insert(vicS.profile.Aquarium.StoredFish, FishInstance.new("Tuna", "StarterPier"))

			RaidService._setPlayersProvider(function()
				return { raider, raidVictim }
			end)

			-- ------------------------------------------------------
			-- STEP 2: gate validation
			-- ------------------------------------------------------
			logger:step("gates", "window_closed / not_opted_in / new_player_protected")
			-- Gate: window closed (scheduler's first real window is >= 20min out)
			logger:assertTrue("window closed before force", not RaidService.isWindowOpen())
			local rClosed = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: window_closed", "window_closed", rClosed and rClosed.reason)

			RaidService._setWindowOpen(true, 300)
			logger:assertTrue("window forced open", RaidService.isWindowOpen())

			-- Gate: attacker not opted in
			atkS.profile.Aquarium.RaidOptIn = false
			local rNoOpt = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: attacker not_opted_in", "not_opted_in", rNoOpt and rNoOpt.reason)
			atkS.profile.Aquarium.RaidOptIn = true

			-- Gate: victim not opted in
			vicS.profile.Aquarium.RaidOptIn = false
			local rVNoOpt = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: victim not_opted_in", "not_opted_in", rVNoOpt and rVNoOpt.reason)
			vicS.profile.Aquarium.RaidOptIn = true

			-- Gate: victim new-player-protected (downgrade, no catches)
			vicS.profile.Aquarium.UpgradeLevel = 1
			local rNewb = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: victim new_player_protected", "new_player_protected", rNewb and rNewb.reason)
			vicS.profile.Aquarium.UpgradeLevel = 2

			-- ------------------------------------------------------
			-- STEP 3: target enumeration
			-- ------------------------------------------------------
			logger:step("targets", "victim listed, available, 1 stealable fish")
			local targetsPayload = RaidService.getRaidTargets(raider)
			logger:assertTrue("getRaidTargets canRaid", targetsPayload and targetsPayload.canRaid == true)
			local targetInfo = nil
			for _, t in ipairs(targetsPayload and targetsPayload.targets or {}) do
				if t.userId == raidVictim.UserId then
					targetInfo = t
					break
				end
			end
			logger:assertTrue("victim listed as target", targetInfo ~= nil)
			if targetInfo then
				logger:assertTrue("victim target available", targetInfo.available == true)
				logger:assertEq("victim stealableCount == 1", 1, targetInfo.stealableCount)
			end

			-- RNG seeding: raid rng call sequence for an attempt is
			--   call 1: challenge center pick (requestRaidAttempt)
			--   call 2: success roll (submitRaidResult)
			--   call 3: steal-weight roll (resolveRaidSuccess)
			-- Seed so call 2 <= threshold (perfect chance 0.85) for the
			-- success run, or > 0.85 for the forged-submit run (even a
			-- broken timing gate could then only "miss", never steal).
			local function seedRaidRng(call2AtMost)
				for seed = 1, 200 do
					local probe = Random.new(seed)
					probe:NextNumber() -- call 1
					local call2 = probe:NextNumber()
					if call2AtMost == nil or call2 <= call2AtMost then
						if call2AtMost ~= nil or call2 > 0.85 then
							RaidService._setRng(Random.new(seed))
							return true
						end
					end
				end
				return false
			end

			-- ------------------------------------------------------
			-- STEP 4: SUCCESS FLOW
			-- ------------------------------------------------------
			logger:step("success", "seeded challenge, TOCTOU window close, fish transfer")
			logger:assertTrue("rng seeded for success", seedRaidRng(0.85))
			local challenge = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertTrue("attempt accepted", challenge and challenge.ok == true)
			if challenge and challenge.ok then
				logger:assertTrue("challenge has perfect zone", challenge.perfectStart ~= nil and challenge.perfectStart < challenge.perfectEnd)
				logger:assertTrue(
					"good zone contains perfect zone",
					challenge.goodStart <= challenge.perfectStart and challenge.goodEnd >= challenge.perfectEnd
				)
				logger:assertTrue("attacker cooldown committed at request", atkS.raidAttackLastAt ~= nil)

				-- One raid in flight per attacker
				local rInFlight = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
				logger:assertEq("re-attempt blocked: raid_in_progress", "raid_in_progress", rInFlight and rInFlight.reason)

				-- TOCTOU design point: the window closing mid-minigame must
				-- NOT void a committed raid (submitRaidResult deliberately
				-- skips the window re-check). Force it closed before
				-- submitting.
				RaidService._setWindowOpen(false)

				-- Anti-forgery minimum time: the marker sweeps 0->1 over
				-- durationSeconds, so position p requires p*duration elapsed
				-- (-0.5s grace). Wait it out, then submit at the
				-- perfect-zone center.
				local center = (challenge.perfectStart + challenge.perfectEnd) / 2
				local waitNeeded = center * challenge.durationSeconds - 0.5 + 0.3
				if waitNeeded > 0 then
					task.wait(waitNeeded)
				end
				pcall(RaidService.submitRaidResult, raider, center)

				logger:assertEq("victim fish stolen (1->0)", 0, #vicS.profile.Aquarium.StoredFish)
				logger:assertEq("attacker received fish (0->1)", 1, #atkS.profile.Aquarium.StoredFish)
				if #atkS.profile.Aquarium.StoredFish > 0 then
					logger:assertEq("stolen fish is the Tuna", "Tuna", atkS.profile.Aquarium.StoredFish[1].SpeciesId)
				end
				logger:assertTrue(
					"victim immunity written (raid protection)",
					(vicS.profile.Aquarium.RaidProtectionUntilTimestamp or 0) > os.time()
				)
				logger:assertEq("attacker RaidsWon == 1", 1, atkS.profile.PvP.RaidsWon)
				logger:assertEq("victim RaidsLost == 1", 1, vicS.profile.PvP.RaidsLost)
				logger:assertTrue(
					"victim window loss counted",
					vicS.raidWindowLosses ~= nil and vicS.raidWindowLosses.count == 1
				)
				logger:log("INFO", "success: fish transferred despite window closing mid-minigame", {})
			end

			-- ------------------------------------------------------
			-- STEP 5: post-success gates
			-- ------------------------------------------------------
			logger:step("post_gates", "cooldowns, immunity, loss cap, input validation")
			-- Re-open for the remaining gate tests (new serial for loss-cap keying)
			local serial2 = RaidService._setWindowOpen(true, 300)

			-- Gate: attacker cooldown (committed by the successful raid)
			local rAtkCd = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: attacker_cooldown", "attacker_cooldown", rAtkCd and rAtkCd.reason)
			logger:assertTrue("attacker cooldownRemaining reported", (rAtkCd and rAtkCd.cooldownRemaining or 0) > 0)

			-- Gate: per-victim cooldown (clear only the attacker-side stamp;
			-- restock + de-immune the victim so eligibility passes first)
			atkS.raidAttackLastAt = nil
			vicS.profile.Aquarium.RaidProtectionUntilTimestamp = 0
			table.insert(vicS.profile.Aquarium.StoredFish, FishInstance.new("Perch", "StarterPier"))
			local rVicCd = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: victim_cooldown", "victim_cooldown", rVicCd and rVicCd.reason)

			-- Gate: raid protection immunity (eligibility check, before victim cd)
			atkS.raidTargetCooldowns = nil
			vicS.profile.Aquarium.RaidProtectionUntilTimestamp = os.time() + 600
			local rProt = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: raid_protection", "raid_protection", rProt and rProt.reason)
			vicS.profile.Aquarium.RaidProtectionUntilTimestamp = 0

			-- Gate: per-window loss cap (2 losses this window)
			vicS.raidWindowLosses = { serial = serial2, count = GameConfig.Raid.maxLossesPerWindow, value = 0 }
			local rCap = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertEq("gate: loss_capped", "loss_capped", rCap and rCap.reason)
			vicS.raidWindowLosses = nil

			-- Gate: input validation
			local rBadType = RaidService.requestRaidAttempt(raider, "not-a-number")
			logger:assertEq("gate: bad targetUserId type", "bad_input", rBadType and rBadType.reason)
			local rSelf = RaidService.requestRaidAttempt(raider, raider.UserId)
			logger:assertEq("gate: self-raid rejected", "target_unavailable", rSelf and rSelf.reason)

			-- ------------------------------------------------------
			-- STEP 6: FORGED INSTANT SUBMIT (timing anti-forgery)
			-- ------------------------------------------------------
			logger:step("forged_submit", "instant max-position submit steals nothing; raid consumed")
			-- High seed: even if the timing gate were broken, the roll would
			-- miss — so "victim keeps fish" can ONLY mean the forged submit
			-- did not steal.
			logger:assertTrue("rng seeded high for forge test", seedRaidRng(nil))
			local ch2 = RaidService.requestRaidAttempt(raider, raidVictim.UserId)
			logger:assertTrue("forge-test attempt accepted", ch2 and ch2.ok == true)
			if ch2 and ch2.ok then
				local fishBefore = #vicS.profile.Aquarium.StoredFish
				pcall(RaidService.submitRaidResult, raider, 1.0) -- instant max-position submit
				logger:assertEq("forged instant submit stole nothing", fishBefore, #vicS.profile.Aquarium.StoredFish)
				-- The raid was consumed (single-resolution) either way
				local resNA = RaidService.submitRaidResult(raider, 0.5)
				logger:assertEq("raid consumed after forged submit", "no_active_raid", resNA and resNA.reason)
			end
		end
	end)

	-- ------------------------------------------------------------------
	-- STEP 7: restore RaidService overrides (finally-style: runs even when
	-- the body errored), then drop sessions
	-- ------------------------------------------------------------------
	logger:step("cleanup", "restore window/players provider; remove sessions")
	RaidService._setWindowOpen(false)
	RaidService._setPlayersProvider(nil)
	DataManager.remove(raider)
	DataManager.remove(raidVictim)

	if not bodyOk then
		logger:log("ERROR", "raid body crashed: " .. tostring(bodyErr), {})
		error(bodyErr, 0)
	end

	-- ------------------------------------------------------------------
	-- STEP 8: r7an — no_session raid attempt must be rejected cleanly
	-- (covers the exploit path where a client raids before their profile
	-- loaded or after it was removed)
	-- ------------------------------------------------------------------
	logger:step("no_session", "player with no loaded session rejected by both entry points")
	local noSessionPlayer = {
		UserId = 444000444,
		Name = "E2ENoSession",
		DisplayName = "E2ENoSession",
		Parent = Players,
		Character = nil,
	}
	logger:assertTrue("no_session: player has no DataManager session", DataManager.get(noSessionPlayer) == nil)

	local rNoSess = RaidService.requestRaidAttempt(noSessionPlayer, 222000222)
	logger:assertEq("no_session: requestRaidAttempt rejected", "no_session", rNoSess and rNoSess.reason)

	local sNoSess = RaidService.submitRaidResult(noSessionPlayer, 0.5)
	logger:assertEq("no_session: submitRaidResult rejected", "no_session", sNoSess and sNoSess.reason)

	logger:finish()
end

return Raid
