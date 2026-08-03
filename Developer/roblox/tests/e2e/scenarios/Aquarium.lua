--[[
	Aquarium.lua — E2E scenario: aquarium economy (store, income claim,
	sell). TASK 19.4, migrated to the modular scenario architecture under
	EPIC 43 (8hnx).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, scenario place built from e2e_scenarios.project.json). NO stubs of
	game code — only the Player is a table-fake (services only need
	UserId/Name/DisplayName/Parent). Every step is logged through TestLogger
	(JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }.

	What this verifies:
	  1. A session + dock claim for a dedicated fake player (real
	     DataManager.load / DockManager.claim paths).
	  2. Store flow: a caught fish (FishInstance injected into carried) moves
	     to profile.Aquarium.StoredFish via the real AquariumService store
	     handler (_G.HARBORHEIST_TEST.aquariumStoreFish).
	  3. Claim flow: injected UnclaimedIncome pays out to Coins via the real
	     claim handler (aquariumClaimIncome) — income accumulation itself is
	     fractional/tick-based, so the claim is tested against an injected
	     $50 rather than waiting for floor(incomePerSec) ticks.
	  4. Sell flow: a second carried fish sells via the real sell handler
	     (aquariumSellFish); carried empties and Coins increase.

	Preserved verbatim from runner.server.lua 19.4: fish species choices
	(Tuna for value floor, Perch for sell), the $50 income injection, and
	count/coin assertions. FireClient calls inside the handlers throw on
	table-fake players AFTER state mutates, so all handler calls are pcall'd
	and profile state (not return values) is the assertion source.

	NOTE: requires the _G.HARBORHEIST_TEST bridge (init.server.lua exposes it
	when ServerScriptService contains E2ERunner or RunE2E). Without it the
	flow steps log a WARN and record no assertions (informational skip —
	the original 19.4 silently ran only its setup asserts in that case).
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Aquarium = {}

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

function Aquarium.run(harness)
	local logger = harness.logger

	logger:startScenario("aquarium_economy", "store fish, claim income, sell fish via real AquariumService handlers")

	local svc = getServices()
	local DataManager = svc.DataManager
	local DockManager = svc.DockManager

	-- ------------------------------------------------------------------
	-- STEP 1: setup — dedicated fake player session + dock claim
	-- ------------------------------------------------------------------
	logger:step("setup", "fake eco player session + dock claim")
	local ecoPlayer = {
		UserId = 333444555,
		Name = "E2EEco",
		DisplayName = "E2EEco",
		Parent = Players,
		Character = nil,
	}
	local ecoSession = DataManager.load(ecoPlayer)
	logger:assertTrue("eco session created", ecoSession ~= nil)
	local ecoDock = DockManager.claim(ecoPlayer)
	logger:assertTrue("eco dock claimed", ecoDock ~= nil)

	local testBridge = _G.HARBORHEIST_TEST
	local bridgeReady = testBridge
		and testBridge.aquariumStoreFish
		and testBridge.aquariumClaimIncome
		and testBridge.aquariumSellFish

	if ecoSession and bridgeReady then
		-- ----------------------------------------------------------
		-- STEP 2: store — injected catch moves carried -> StoredFish
		-- ----------------------------------------------------------
		logger:step("store", "store carried fish into aquarium")
		local FishInstance = require(ReplicatedStorage.Shared.FishInstance)
		-- Higher-value fish ensures income would accumulate above the floor threshold
		local testFish = FishInstance.new("Tuna", "StarterPier")
		table.insert(ecoSession.carried, testFish)
		logger:log("INFO", "injected fish: " .. testFish.SpeciesId, {
			baseSellValue = testFish.BaseSellValue,
		})
		logger:assertEq("carried count before store", 1, #ecoSession.carried)
		logger:assertEq("stored count before store", 0, #ecoSession.profile.Aquarium.StoredFish)

		pcall(testBridge.aquariumStoreFish, ecoPlayer)
		logger:assertEq("stored count after store", 1, #ecoSession.profile.Aquarium.StoredFish)
		logger:assertEq("carried count after store", 0, #ecoSession.carried)

		-- ----------------------------------------------------------
		-- STEP 3: claim — injected UnclaimedIncome pays out to Coins
		-- ----------------------------------------------------------
		logger:step("claim", "claim aquarium income")
		-- Inject income directly: incomePerSec is fractional, so floor-based
		-- accumulation would need many ticks to reach 1+ coin.
		ecoSession.profile.Aquarium.UnclaimedIncome = 50
		local coinsBeforeClaim = ecoSession.profile.Coins
		pcall(testBridge.aquariumClaimIncome, ecoPlayer)
		logger:assertEq("unclaimed income after claim", 0, ecoSession.profile.Aquarium.UnclaimedIncome)
		logger:assertTrue("coins increased after claim", ecoSession.profile.Coins > coinsBeforeClaim)
		logger:log("INFO", "claim completed", { coins = ecoSession.profile.Coins })

		-- ----------------------------------------------------------
		-- STEP 4: sell — second carried fish sells for Coins
		-- ----------------------------------------------------------
		logger:step("sell", "sell carried fish")
		local testFish2 = FishInstance.new("Perch", "StarterPier")
		table.insert(ecoSession.carried, testFish2)
		logger:assertEq("carried count before sell", 1, #ecoSession.carried)

		local coinsBeforeSell = ecoSession.profile.Coins
		pcall(testBridge.aquariumSellFish, ecoPlayer)
		logger:assertEq("carried count after sell", 0, #ecoSession.carried)
		logger:assertTrue("coins increased after sell", ecoSession.profile.Coins > coinsBeforeSell)
		logger:log("INFO", "sell completed", { coins = ecoSession.profile.Coins })
	elseif ecoSession then
		logger:log(
			"WARN",
			"SKIP: no _G.HARBORHEIST_TEST bridge (aquariumStoreFish/ClaimIncome/SellFish) — "
				.. "economy flows not exercised; requires a test/E2E place exposing the bridge "
				.. "(informational; original 19.4 ran setup asserts only in this case)",
			{}
		)
	end

	-- ------------------------------------------------------------------
	-- STEP 5: cleanup — release dock + drop session (always runs; asserts
	-- record failures without throwing)
	-- ------------------------------------------------------------------
	logger:step("cleanup", "release dock + remove eco session")
	local releaseOk, releaseErr = pcall(DockManager.release, ecoPlayer)
	logger:assertTrue("DockManager.release ran: " .. tostring(releaseErr or ""), releaseOk)
	local removeOk, removeErr = pcall(DataManager.remove, ecoPlayer)
	logger:assertTrue("DataManager.remove ran: " .. tostring(removeErr or ""), removeOk)

	logger:finish()
end

return Aquarium
