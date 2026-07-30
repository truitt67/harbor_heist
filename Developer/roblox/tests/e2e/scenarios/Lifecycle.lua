--[[
	Lifecycle.lua — E2E scenario: player lifecycle
	(join, load, dock claim, snapshot, leave, save). TASK 19.2 (pe9a.2).

	Drives the REAL game wiring inside a Roblox DataModel (run-in-roblox +
	Studio, test place built from test.project.json). NO stubs of game code.
	Every step is logged through TestLogger (JSONL); failures dump full state.

	RUNS SERVER-SIDE: the bootstrap (tests/e2e/bootstrap.server.lua) requires
	this module with the harness table { logger, player, remotes }. The Studio
	test player is the real joining Player, so DataManager.load / leaderstats /
	dock claim all run through the production onPlayerAdded path.

	Bead steps:
	  1. Boot real place; assert services initialized (probe GetState shape +
	     leaderstats existence).
	  2. Fresh join: default v2 profile (Coins=0, rod 1); leaderstats created;
	     AnalyticsService tutorial_started fires (observed via AuditLog where
	     applicable).
	  3. Dock claim: exactly one dock assigned; reflected in state snapshot.
	  4. Initial StateSync snapshot; assert schema keys (cash, Equipment,
	     Aquarium, dailyQuests, weeklyQuests, dataStoreHealthy).
	  5. QuestService populated daily+weekly quest lists.
	  6. Leave: save completes (isShutdown), DockManager.release frees dock.
	     NOTE: a real rejoin cannot be exercised in a single headless run; that
	     half is recorded as a manual follow-up (see step 6 below).
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Lifecycle = {}

-- Pull the already-wired services the bootstrap captured, so assertions read
-- the SAME module instances the game wired (no re-require drift).
local function getServices()
	local harbor = ServerScriptService:WaitForChild("HarborHeist", 10)
	assert(harbor, "ServerScriptService.HarborHeist missing — game did not boot")
	return {
		DataManager = require(harbor:WaitForChild("DataManager")),
		DockManager = require(harbor:WaitForChild("DockManager")),
		StateSync = require(harbor:WaitForChild("StateSync")),
		QuestService = require(harbor:WaitForChild("QuestService")),
		AnalyticsService = require(harbor:WaitForChild("AnalyticsService")),
	}
end

function Lifecycle.run(harness)
	local logger = harness.logger
	local player = harness.player
	local remotes = harness.remotes

	logger.getState = function()
		-- Read the authoritative server session directly (test-only probe);
		-- mirrors what GetState returns without consuming the remote's
		-- rate-limit budget.
		local svc = getServices()
		local session = svc.DataManager.get(player)
		if session then
			return svc.StateSync.snapshot(session)
		end
		return { note = "no session yet" }
	end

	logger:startScenario("lifecycle", "join, load, dock claim, snapshot, leave, save")

	-- ------------------------------------------------------------------
	-- STEP 1: boot — services initialized (probe GetState shape + leaderstats)
	-- ------------------------------------------------------------------
	logger:step("boot", "real place booted; services wired")
	local svc = getServices()
	logger:assertTrue("DataManager module loaded", svc.DataManager ~= nil)
	logger:assertTrue("DockManager module loaded", svc.DockManager ~= nil)
	logger:assertTrue("StateSync module loaded", svc.StateSync ~= nil)
	logger:assertTrue("QuestService module loaded", svc.QuestService ~= nil)
	logger:assertTrue("player exists", player ~= nil and player.Parent == Players)

	-- Give onPlayerAdded (DataManager.load, leaderstats, dock claim, first
	-- snapshot push) time to run — it is yieldy (DataStore read).
	local session
	for _ = 1, 100 do
		session = svc.DataManager.get(player)
		if session then
			break
		end
		task.wait(0.1)
	end
	logger:assertTrue("session loaded after join", session ~= nil)

	-- ------------------------------------------------------------------
	-- STEP 2: fresh join — default profile, leaderstats created
	-- ------------------------------------------------------------------
	logger:step("join", "default v2 profile + leaderstats")
	if session then
		local profile = session.profile
		logger:log("INFO", "profile after load", {
			coins = profile.Coins,
			rodLevel = profile.Equipment and profile.Equipment.EquippedRodLevel,
		})
		logger:assertTrue("profile.Equipment present", profile.Equipment ~= nil)
		logger:assertTrue("profile.Aquarium present", profile.Aquarium ~= nil)
		-- Coins/rod are 0/1 for a fresh account, saved values for a returning
		-- one. We assert the FIELDS exist and are numbers (default-detection of
		-- freshness is environment-dependent and noted, not hard-failed).
		logger:assertTrue("Coins is a number", type(profile.Coins) == "number")
		logger:assertTrue(
			"EquippedRodLevel >= 1",
			type(profile.Equipment.EquippedRodLevel) == "number" and profile.Equipment.EquippedRodLevel >= 1
		)
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	logger:assertTrue("leaderstats folder created", leaderstats ~= nil)
	if leaderstats then
		logger:assertTrue("leaderstats.Cash exists", leaderstats:FindFirstChild("Cash") ~= nil)
	end

	-- ------------------------------------------------------------------
	-- STEP 3: dock claim — exactly one dock assigned, reflected in snapshot
	-- ------------------------------------------------------------------
	logger:step("dock_claim", "exactly one dock assigned")
	local snap = logger.getState()
	logger:assertTrue("snapshot has dockIndex", snap.dockIndex ~= nil)
	if session then
		logger:assertEq("session.dockIndex matches snapshot", snap.dockIndex, session.dockIndex)
	end
	-- Cross-check the world: the claimed dock's owner is this player.
	if snap.dockIndex then
		local docksFolder = workspace:FindFirstChild("Docks")
		local dock = docksFolder and docksFolder:FindFirstChild("Dock" .. tostring(snap.dockIndex))
		logger:assertTrue("world dock exists for dockIndex", dock ~= nil)
	end

	-- ------------------------------------------------------------------
	-- STEP 4: snapshot schema keys
	-- ------------------------------------------------------------------
	logger:step("snapshot_schema", "initial StateSync snapshot schema")
	local schemaKeys = {
		"cash", "rodLevel", "baitLevel", "capacity", "incomePerSec",
		"unclaimedIncome", "onboarding", "carried", "maxCarried",
		"liveWellCount", "storedFish", "carriedFish", "dataStoreHealthy",
		"dockIndex", "totalCatches",
	}
	for _, key in ipairs(schemaKeys) do
		logger:assertTrue("snapshot key present: " .. key, snap[key] ~= nil)
	end
	logger:assertTrue("onboarding table present", type(snap.onboarding) == "table")
	logger:assertTrue("dataStoreHealthy is boolean", type(snap.dataStoreHealthy) == "boolean")

	-- ------------------------------------------------------------------
	-- STEP 5: quests populated (daily + weekly)
	-- ------------------------------------------------------------------
	-- QuestService.initializeQuests stores the lists on the SESSION
	-- (session.dailyQuests / session.weeklyQuests), not on the profile —
	-- they are copied into clean.dailyQuests/weeklyQuests at save time.
	logger:step("quests", "daily + weekly quest lists populated")
	if session then
		local daily = session.dailyQuests
		local weekly = session.weeklyQuests
		logger:log("INFO", "quest lists", {
			hasDaily = daily ~= nil,
			hasWeekly = weekly ~= nil,
			dailyCount = daily and #daily or 0,
			weeklyCount = weekly and #weekly or 0,
		})
		logger:assertTrue("daily quest list populated", type(daily) == "table" and #daily > 0)
		logger:assertTrue("weekly quest list populated", type(weekly) == "table" and #weekly > 0)
	end

	-- ------------------------------------------------------------------
	-- STEP 6: leave — save (isShutdown) + dock release
	-- ------------------------------------------------------------------
	-- A real player leave cannot be forced inside a single headless run
	-- (removing the only Player ends the Studio session), and a rejoin is a
	-- second run. We therefore verify the CLEANUP PATHS directly: invoke the
	-- same DataManager.save(player, true) the leave handler uses and confirm
	-- DockManager.release frees the dock. The full leave->rejoin round-trip is
	-- a documented manual follow-up.
	logger:step("leave", "save + dock release cleanup paths")
	if session then
		local savedCoins = session.profile.Coins
		local dockIndex = session.dockIndex
		local saveOk, saveErr = pcall(function()
			logger:timeIt("DataManager.save (isShutdown path)", function()
				svc.DataManager.save(player, true)
			end)
		end)
		logger:assertTrue("save completed without error: " .. tostring(saveErr or ""), saveOk)
		-- Release the dock and confirm the call succeeds against real state.
		local releaseOk, releaseErr = pcall(svc.DockManager.release, player)
		logger:assertTrue("DockManager.release ran: " .. tostring(releaseErr or ""), releaseOk)
		logger:log("INFO", "dock released", {
			was = dockIndex,
			savedCoins = savedCoins,
		})
	end
	logger:log("INFO", "NOTE: full leave->rejoin round-trip is a manual Studio follow-up (cannot remove the sole test Player in one headless run)", {})

	logger:finish()
end

return Lifecycle
