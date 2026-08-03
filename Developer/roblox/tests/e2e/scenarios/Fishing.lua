--[[
	Fishing.lua — E2E scenario: fishing loop (catch resolution). TASK 19.3,
	migrated to the modular scenario architecture under EPIC 43 (c4fs).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, scenario place built from e2e_scenarios.project.json). NO stubs of
	game code — only the Player is a table-fake (services only need
	UserId/Name/DisplayName/Parent). Every step is logged through TestLogger
	(JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }.

	What this verifies:
	  1. A session + dock claim for a dedicated fake fisher (real
	     DataManager.load / DockManager.claim paths).
	  2. Catch resolution through the REAL FishingService submit handler:
	     a bite entry is injected into FishingService._activeBites via the
	     _G.HARBORHEIST_TEST bridge (exposed by init.server.lua only in
	     test/E2E places), then _submitCatch is invoked directly.
	  3. RNG is seeded (testBridge.setFishingRng) so the catch roll lands
	     inside the effective zone — deterministic, no flaky misses.
	  4. The caught fish lands in session.carried with SpeciesId/Rarity/
	     BaseSellValue, and the miss/retry path still resolves a catch.

	Preserved verbatim from runner.server.lua 19.3: the activeBites injection
	shape, the seed-search (seeds 1..10, first NextNumber() <= 0.85), the
	carried-check-before-notify result synthesis (FireClient on a fake player
	may error AFTER the fish is added), and the RNG-miss retry (Random.new(1)
	pre-consumed 5x — note tryCatch's internal seed-search then re-seeds
	anyway; redundancy kept for behavioral parity).

	NOTE: requires the _G.HARBORHEIST_TEST bridge. init.server.lua exposes it
	when ServerScriptService contains E2ERunner (old monolithic place) or
	RunE2E (scenario bootstrap). Without the bridge this scenario logs a WARN
	and records no assertions (informational skip, matching the original).
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Fishing = {}

-- Pull the already-wired services so assertions read the SAME module
-- instances the game wired (no re-require drift).
local function getServices()
	local harbor = ServerScriptService:WaitForChild("HarborHeist", 10)
	assert(harbor, "ServerScriptService.HarborHeist missing — game did not boot")
	return {
		DataManager = require(harbor:WaitForChild("DataManager")),
		DockManager = require(harbor:WaitForChild("DockManager")),
	}
end

function Fishing.run(harness)
	local logger = harness.logger
	local remotes = harness.remotes

	logger:startScenario("fishing", "bite injection, seeded catch resolution, carried verification, miss/retry")

	local svc = getServices()
	local DataManager = svc.DataManager
	local DockManager = svc.DockManager

	-- ------------------------------------------------------------------
	-- STEP 1: setup — dedicated fake fisher session + dock claim
	-- ------------------------------------------------------------------
	-- A fake player (not harness.player) keeps this scenario isolated from
	-- the real Studio player's session/dock, exactly as runner 19.3 did.
	logger:step("setup", "fake fisher session + dock claim")
	local fisher = {
		UserId = 222333444,
		Name = "E2EFisher",
		DisplayName = "E2EFisher",
		Parent = Players,
		Character = nil,
		-- Stub methods needed for StateSync.push and other operations
		FindFirstChild = function()
			return nil
		end,
		IsA = function()
			return false
		end,
		GetFullName = function()
			return "E2EFisher"
		end,
	}
	local fisherSession = DataManager.load(fisher)
	logger:assertTrue("fisher session created", fisherSession ~= nil)
	local fisherDock = DockManager.claim(fisher)
	logger:assertTrue("fisher dock claimed", fisherDock ~= nil)

	local submitRemote = remotes:FindFirstChild("SubmitCatchInput")
	logger:assertTrue("SubmitCatchInput remote exists", submitRemote ~= nil)

	-- ------------------------------------------------------------------
	-- STEP 2: bridge check + catch resolution
	-- ------------------------------------------------------------------
	logger:step("catch", "inject bite via _G.HARBORHEIST_TEST, resolve seeded catch")
	local testBridge = _G.HARBORHEIST_TEST
	local bridgeReady = testBridge
		and testBridge.activeBites
		and testBridge.submitCatch

	if submitRemote and fisherSession and bridgeReady then
		logger:log("INFO", "test bridge available — injecting bite state", {})

		local function injectBite()
			testBridge.activeBites[fisher] = {
				zoneId = "StarterPier",
				rodLevel = 1,
				baitLevel = 1,
				biteTime = os.clock(),
				hitZoneStart = 0.35,
				hitZoneEnd = 0.65,
				goodStart = 0.25,
				goodEnd = 0.75,
				castDeadline = os.clock() + 100,
				luckBonus = 100, -- High luck bonus to maximize effectiveZone (0.85)
				castResultReceived = true,
			}
		end

		local function tryCatch()
			injectBite()
			task.wait(0.1)

			-- Seed RNG to ensure catch succeeds (avoid RNG-based misses).
			-- Use a seed that produces a low first value (<= 0.85 effectiveZone).
			if testBridge.setFishingRng then
				for seed = 1, 10 do
					local testRng = Random.new(seed)
					local testVal = testRng:NextNumber()
					if testVal <= 0.85 then
						testBridge.setFishingRng(testRng)
						break
					end
				end
			end

			-- Call submitCatch and catch any errors from FireClient on fake player
			local ok, result = pcall(testBridge.submitCatch, fisher, { hit = true })

			-- Check if fish was added to carried (happens before notify calls)
			if #fisherSession.carried > 0 then
				-- Fish was added successfully, ignore any FireClient errors
				return {
					ok = true,
					speciesId = fisherSession.carried[1].SpeciesId,
					rarity = fisherSession.carried[1].Rarity,
					value = fisherSession.carried[1].BaseSellValue,
				}
			end

			if not ok then
				-- Handler threw and no fish was added
				return nil, result
			end
			return result
		end

		-- First attempt
		local result, errMsg = tryCatch()

		-- If handler threw (StateSync.push error), check if fish was added anyway
		if result == nil and errMsg then
			if #fisherSession.carried > 0 then
				result = {
					ok = true,
					speciesId = fisherSession.carried[1].SpeciesId,
					rarity = fisherSession.carried[1].Rarity,
					value = fisherSession.carried[1].BaseSellValue,
				}
			end
		end

		logger:assertTrue("submitCatch returns result", result ~= nil)

		if result and result.ok then
			logger:log("INFO", "catch result", {
				ok = result.ok,
				species = tostring(result.speciesId),
				rarity = tostring(result.rarity),
				value = result.value,
			})
			logger:assertTrue("catch succeeded (ok=true)", result.ok)
			logger:assertTrue("result has speciesId", result.speciesId ~= nil)
			logger:assertTrue("result has rarity", result.rarity ~= nil)
			logger:assertTrue("result has value > 0", (result.value or 0) > 0)
			logger:assertEq("carried count == 1 after catch", 1, #fisherSession.carried)
			if #fisherSession.carried > 0 then
				local fish = fisherSession.carried[1]
				logger:assertTrue("caught fish has SpeciesId", fish.SpeciesId ~= nil)
				logger:assertTrue("caught fish has Rarity", fish.Rarity ~= nil)
				logger:assertTrue("caught fish has BaseSellValue", fish.BaseSellValue ~= nil)
				logger:log("INFO", "caught: " .. tostring(fish.Rarity) .. " " .. tostring(fish.SpeciesId), {
					baseSellValue = fish.BaseSellValue,
				})
			end
		elseif result and result.reason == "missed" then
			-- RNG-dependent miss on first try — retry with a seeded RNG
			logger:log("INFO", "first catch missed (RNG) — retrying with seeded RNG", {})
			if testBridge.setFishingRng then
				-- Random.new(1) with a few consumed values returns small numbers
				-- (always <= effectiveZone for a guaranteed catch)
				local forcedRng = Random.new(1)
				for _ = 1, 5 do
					forcedRng:NextNumber()
				end
				testBridge.setFishingRng(forcedRng)
			end
			local result2 = tryCatch()
			if result2 and result2.ok then
				logger:log("INFO", "retry catch succeeded", {})
				logger:assertTrue("retry catch ok", result2.ok)
				logger:assertEq("carried count after retry", 1, #fisherSession.carried)
			else
				logger:log("ERROR", "retry also missed", {
					reason = tostring(result2 and result2.reason),
				})
				logger:assertTrue("catch succeeds (RNG-dependent) — missed twice", false)
			end
		elseif result then
			logger:assertTrue("catch succeeds — reason=" .. tostring(result.reason), false)
		end
	else
		logger:log(
			"WARN",
			"SKIP: no _G.HARBORHEIST_TEST bridge (activeBites/submitCatch) — catch path not exercised; "
				.. "requires a test/E2E place exposing the bridge (informational, matches runner 19.3)",
			{}
		)
	end

	-- ------------------------------------------------------------------
	-- STEP 3: cleanup — release dock + drop session (always runs; asserts
	-- record failures without throwing)
	-- ------------------------------------------------------------------
	logger:step("cleanup", "release dock + remove fisher session")
	local releaseOk, releaseErr = pcall(DockManager.release, fisher)
	logger:assertTrue("DockManager.release ran: " .. tostring(releaseErr or ""), releaseOk)
	local removeOk, removeErr = pcall(DataManager.remove, fisher)
	logger:assertTrue("DataManager.remove ran: " .. tostring(removeErr or ""), removeOk)

	logger:finish()
end

return Fishing
