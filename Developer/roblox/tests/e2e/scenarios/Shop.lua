--[[
	Shop.lua — E2E scenario: shop purchases (rod, bait, aquarium capacity;
	insufficient funds; validation failures). TASK 19.5, migrated to the
	modular scenario architecture under EPIC 43 (7dho).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, scenario place built from e2e_scenarios.project.json). NO stubs of
	game code — only the Player is a table-fake (services only need
	UserId/Name/DisplayName/Parent). Every step is logged through TestLogger
	(JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }.

	What this verifies (all through the REAL ShopService purchase handler,
	exposed as _G.HARBORHEIST_TEST.shopPurchase):
	  1. Insufficient funds: a \$0 player cannot buy rod 2 (state unchanged).
	  2. Success paths: rod 2, bait 2, aquarium tier 2 — equipment levels,
	     coin deduction, OwnedRodLevels tracking, capacity from GameConfig.
	  3. wrong_tier: rebuying the equipped tier is rejected (state unchanged).
	  4. Validation: bad_kind / bad_level / bad_args return ok=false with the
	     exact reason codes.

	Preserved verbatim from runner.server.lua 19.5: call pcall semantics —
	the success path mutates profile state BEFORE remotes.notify (FireClient
	throws on table-fake players), so profile state is authoritative; the
	poor/wrong_tier paths notify before returning, verified by UNCHANGED
	state; the bad_* paths return before any notify, so their return tables
	are asserted directly. Rate-limit budget note: 8 buy calls, limit is 10
	per 10s per player.

	NOTE: unlike the fishing/aquarium scenarios, the original 19.5 treats a
	missing shopPurchase seam as a hard FAILURE (not an informational skip).
	That stricter semantics is preserved — the seam must exist in any place
	this scenario runs.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = {}

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

function Shop.run(harness)
	local logger = harness.logger

	logger:startScenario("shop_purchases", "insufficient funds, rod/bait/aquarium success paths, validation failures")

	local svc = getServices()
	local DataManager = svc.DataManager
	local DockManager = svc.DockManager

	-- ------------------------------------------------------------------
	-- STEP 1: setup — dedicated fake shopper session + dock claim
	-- ------------------------------------------------------------------
	logger:step("setup", "fake shopper session + dock claim")
	local shopper = {
		UserId = 444555666,
		Name = "E2EShopper",
		DisplayName = "E2EShopper",
		Parent = Players,
		Character = nil,
	}
	local shopperSession = DataManager.load(shopper)
	logger:assertTrue("shopper session created", shopperSession ~= nil)
	local shopperDock = DockManager.claim(shopper)
	logger:assertTrue("shopper dock claimed", shopperDock ~= nil)

	local testBridge = _G.HARBORHEIST_TEST
	local shopPurchase = testBridge and testBridge.shopPurchase
	-- Original 19.5 semantics: missing seam is a hard failure, not a skip.
	logger:assertTrue("shopPurchase test seam available", shopPurchase ~= nil)

	if shopPurchase and shopperSession then
		local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
		local profile = shopperSession.profile
		local rod2 = GameConfig.Rods[2]
		local bait2 = GameConfig.Baits[2]
		local aq2 = GameConfig.AquariumUpgradeTiers[2]

		-- ----------------------------------------------------------
		-- STEP 2: insufficient funds (starting coins = 0)
		-- ----------------------------------------------------------
		logger:step("poor", "insufficient funds rejected, state unchanged")
		logger:assertEq("starting coins == 0", 0, profile.Coins)
		pcall(shopPurchase, shopper, "rod", 2)
		logger:assertEq("poor: coins unchanged", 0, profile.Coins)
		logger:assertEq("poor: rod level still 1", 1, profile.Equipment.EquippedRodLevel)

		-- ----------------------------------------------------------
		-- STEP 3: fund + buy rod 2 (success path)
		-- ----------------------------------------------------------
		logger:step("rod2", "buy rod 2 — level, deduction, ownership")
		profile.Coins = 10000
		pcall(shopPurchase, shopper, "rod", 2)
		logger:assertEq("rod2: equipped level == 2", 2, profile.Equipment.EquippedRodLevel)
		logger:assertEq("rod2: coins deducted by cost", 10000 - rod2.cost, profile.Coins)
		local ownsRod2 = false
		for _, lvl in ipairs(profile.Equipment.OwnedRodLevels) do
			if lvl == 2 then
				ownsRod2 = true
				break
			end
		end
		logger:assertTrue("rod2: ownership tracked in OwnedRodLevels", ownsRod2)
		logger:log("INFO", "rod2 purchased: " .. rod2.name, {
			cost = rod2.cost,
			coins = profile.Coins,
		})

		-- ----------------------------------------------------------
		-- STEP 4: wrong tier — rebuying rod 2 while equipped
		-- ----------------------------------------------------------
		logger:step("wrong_tier", "rebuy of equipped tier rejected")
		local coinsBeforeWrongTier = profile.Coins
		pcall(shopPurchase, shopper, "rod", 2)
		logger:assertEq("wrong_tier: rod level unchanged", 2, profile.Equipment.EquippedRodLevel)
		logger:assertEq("wrong_tier: coins unchanged", coinsBeforeWrongTier, profile.Coins)

		-- ----------------------------------------------------------
		-- STEP 5: buy bait 2 (success path)
		-- ----------------------------------------------------------
		logger:step("bait2", "buy bait 2 — level + deduction")
		pcall(shopPurchase, shopper, "bait", 2)
		logger:assertEq("bait2: equipped level == 2", 2, profile.Equipment.EquippedBaitLevel)
		logger:assertEq("bait2: coins deducted by cost", coinsBeforeWrongTier - bait2.cost, profile.Coins)

		-- ----------------------------------------------------------
		-- STEP 6: aquarium capacity upgrade (success path)
		-- ----------------------------------------------------------
		logger:step("aquarium2", "buy aquarium tier 2 — capacity + deduction")
		local coinsBeforeAq = profile.Coins
		local capBefore = profile.Aquarium.Capacity
		pcall(shopPurchase, shopper, "aquarium", 2)
		logger:assertEq("aquarium2: upgrade level == 2", 2, profile.Aquarium.UpgradeLevel)
		logger:assertEq("aquarium2: capacity == tier 2 capacity", aq2.capacity, profile.Aquarium.Capacity)
		logger:assertTrue("aquarium2: capacity increased", profile.Aquarium.Capacity > capBefore)
		logger:assertEq("aquarium2: coins deducted by cost", coinsBeforeAq - aq2.cost, profile.Coins)
		logger:log("INFO", "aquarium upgraded", {
			capacityBefore = capBefore,
			capacityAfter = profile.Aquarium.Capacity,
			coins = profile.Coins,
		})

		-- ----------------------------------------------------------
		-- STEP 7: validation failures (no notify — return values assertable)
		-- ----------------------------------------------------------
		logger:step("validation", "bad_kind / bad_level / bad_args")
		local okBadKind, resBadKind = pcall(shopPurchase, shopper, "castle", 2)
		logger:assertTrue("bad_kind: handler did not throw", okBadKind)
		logger:assertTrue("bad_kind: ok == false", resBadKind ~= nil and resBadKind.ok == false)
		logger:assertEq("bad_kind: reason", "bad_kind", resBadKind and resBadKind.reason)

		local okBadLevel, resBadLevel = pcall(shopPurchase, shopper, "rod", 99)
		logger:assertTrue("bad_level: handler did not throw", okBadLevel)
		logger:assertEq("bad_level: reason", "bad_level", resBadLevel and resBadLevel.reason)

		local okBadArgs, resBadArgs = pcall(shopPurchase, shopper, 123, "rod")
		logger:assertTrue("bad_args: handler did not throw", okBadArgs)
		logger:assertEq("bad_args: reason", "bad_args", resBadArgs and resBadArgs.reason)
	end

	-- ------------------------------------------------------------------
	-- STEP 8: cleanup — release dock + drop session (always runs; asserts
	-- record failures without throwing)
	-- ------------------------------------------------------------------
	logger:step("cleanup", "release dock + remove shopper session")
	local releaseOk, releaseErr = pcall(DockManager.release, shopper)
	logger:assertTrue("DockManager.release ran: " .. tostring(releaseErr or ""), releaseOk)
	local removeOk, removeErr = pcall(DataManager.remove, shopper)
	logger:assertTrue("DataManager.remove ran: " .. tostring(removeErr or ""), removeOk)

	logger:finish()
end

return Shop
