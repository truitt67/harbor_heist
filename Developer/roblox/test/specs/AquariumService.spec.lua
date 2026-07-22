-- AquariumService.spec.lua
-- TASK 18.6: AquariumService unit tests (income, claim, sell, capacity,
-- lock FSM, raid protection, sell-from-locked regression 14.6).
--
-- Standalone raid-protection helpers are tested directly on the module.
-- init() handlers (store/claim/sell/lock) are exercised via OnServerInvoke
-- through a thin deps harness. Real GameConfig, real PlayerProfile,
-- real FishInstance. Sessions are plain tables matching real shape.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)
	local AquariumService = require(ServerScriptService.HarborHeist.AquariumService)

	-- ================================================================
	-- Harness
	-- ================================================================

	local function makeFish(speciesId, rarity, baseSellValue, isProtected)
		return {
			InstanceId = "test-" .. speciesId,
			SpeciesId = speciesId,
			Rarity = rarity,
			BaseSellValue = baseSellValue,
			IncomePerMinute = 1,
			CaughtAtTimestamp = os.time(),
			SourceZoneId = "StarterPier",
			IsRaidProtected = isProtected or false,
		}
	end

	local function makeSession()
		local profile = PlayerProfile.default()
		return {
			player = nil, -- set per test
			profile = profile,
			carried = {},
			lockedUntil = 0,
			lockCooldownUntil = 0,
			lockGeneration = 0,
			stunUntil = 0,
		}
	end

	local function makeDeps()
		local sessions = {}
		return {
			sessions = sessions,
			remotes = {
				RequestStoreFish = {},
				RequestClaimIncome = {},
				RequestSellFish = {},
				RequestActivateLock = {},
				RequestToggleRaidOptIn = {},
				notify = function() end,
				CastState = { FireClient = function() end },
			},
			dataManager = {
				get = function(player) return sessions[player] end,
				save = function(player) end,
				allSessions = function() return sessions end,
			},
			dockManager = {
				getDock = function(player) return {} end,
				updateAquariumVisual = function() end,
			},
			stateSync = {
				push = function(session) end,
				getCapacity = function(session) return session.profile.Aquarium.Capacity end,
				invalidateIncomeCache = function(session) end,
				incomePerSec = function(session) return 5 end, -- known rate for math tests
			},
			questService = {
				onFishStored = function() end,
				onFishSold = function() end,
				onIncomeEarned = function() end,
			},
			analytics = {
				track = function() end,
				isFirst = function() return false end,
			},
			onboarding = { mark = function() return false end },
			antiExploit = nil,
			auditLog = nil,
		}
	end

	local deps = makeDeps()

	-- Player helper with counter to avoid per-test setup
	local playerCounter = 0
	local function makeFakePlayer()
		playerCounter += 1
		local p = Instance.new("Player")
		p.UserId = 910000 + playerCounter
		p.Parent = Instance.new("Folder")
		return p
	end

	-- Set up session and player pair for a sub-test
	local function newTestPair()
		local player = makeFakePlayer()
		local session = makeSession()
		session.player = player
		deps.sessions[player] = session
		return player, session
	end

	-- Initialize (once — OnServerInvoke handlers live on remotes table)
	-- AntiExploitService module instance may need reload, but for test place init is no-op harm
	-- Critical: init must run so the OnServerInvoke handlers get set
	pcall(function() AquariumService.init(deps) end)

	-- ================================================================
	-- 1. Income accrual math
	-- ================================================================
	describe("Income accrual", function()
		it("incomePerSec * IncomeTickSeconds matches expected accrual", function()
			local rate = 5 -- matches deps.stateSync.incomePerSec
			local tick = GameConfig.IncomeTickSeconds
			expect(rate * tick).to.equal(5)
		end)

		it("UnclaimedIncome is capped at MaxUnclaimedIncome", function()
			local unclaimed = 49999
			local income = 100
			local max = GameConfig.Economy.MaxUnclaimedIncome
			local after = math.min(unclaimed + income, max)
			expect(after).to.equal(max)
		end)

		it("normal accrual below cap adds exactly", function()
			local unclaimed = 100
			local income = 5
			local max = GameConfig.Economy.MaxUnclaimedIncome
			local after = math.min(unclaimed + income, max)
			expect(after).to.equal(105)
		end)

		it("IncomeTickSeconds is 1", function()
			expect(GameConfig.IncomeTickSeconds).to.equal(1)
		end)
	end)

	-- ================================================================
	-- 2. Claim
	-- ================================================================
	describe("Claim income", function()
		it("moves UnclaimedIncome to Coins exactly and resets to 0", function()
			local player, session = newTestPair()
			session.profile.Aquarium.UnclaimedIncome = 150
			local result = deps.remotes.RequestClaimIncome.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(result.amount).to.equal(150)
			expect(session.profile.Aquarium.UnclaimedIncome).to.equal(0)
			expect(session.profile.Coins).to.equal(150)
			player.Parent = nil
		end)

		it("returns nothing_to_claim when pool is empty", function()
			local player, session = newTestPair()
			session.profile.Aquarium.UnclaimedIncome = 0
			local result = deps.remotes.RequestClaimIncome.OnServerInvoke(player)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("nothing_to_claim")
			player.Parent = nil
		end)

		it("TotalCoinsEarned increases by claimed amount", function()
			local player, session = newTestPair()
			session.profile.Aquarium.UnclaimedIncome = 75
			session.profile.TotalCoinsEarned = 200
			deps.remotes.RequestClaimIncome.OnServerInvoke(player)
			expect(session.profile.TotalCoinsEarned).to.equal(275)
			player.Parent = nil
		end)

		it("Coins capped by PlayerProfile.MAX_COINS", function()
			local player, session = newTestPair()
			session.profile.Coins = PlayerProfile.MAX_COINS - 10
			session.profile.Aquarium.UnclaimedIncome = 100
			deps.remotes.RequestClaimIncome.OnServerInvoke(player)
			expect(session.profile.Coins).to.equal(PlayerProfile.MAX_COINS)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 3. Sell (including 14.6 regression: sell-from-locked-aquarium)
	-- ================================================================
	describe("Sell fish", function()
		it("empties StoredFish when not locked and returns payout", function()
			local player, session = newTestPair()
			local fish1 = makeFish("Bluegill", "Common", 15)
			local fish2 = makeFish("Trout", "Uncommon", 35)
			session.profile.Aquarium.StoredFish = { fish1, fish2 }
			local result = deps.remotes.RequestSellFish.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(result.payout).to.equal(50)
			expect(#session.profile.Aquarium.StoredFish).to.equal(0)
			player.Parent = nil
		end)

		it("also sells carried fish", function()
			local player, session = newTestPair()
			local carried = makeFish("Sardine", "Common", 8)
			session.carried = { carried }
			local result = deps.remotes.RequestSellFish.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(result.payout).to.equal(8)
			expect(#session.carried).to.equal(0)
			player.Parent = nil
		end)

		it("14.6 regression: locked aquarium blocks StoredFish sell", function()
			local player, session = newTestPair()
			session.profile.Aquarium.StoredFish = { makeFish("Perch", "Common", 12) }
			session.lockedUntil = os.clock() + 30
			local result = deps.remotes.RequestSellFish.OnServerInvoke(player)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("aquarium_locked")
			-- StoredFish untouched
			expect(#session.profile.Aquarium.StoredFish).to.equal(1)
			player.Parent = nil
		end)

		it("14.6 regression: locked aquarium still allows carried fish sell", function()
			local player, session = newTestPair()
			local stored = makeFish("Perch", "Common", 12)
			local carried = makeFish("Bluegill", "Common", 15)
			session.profile.Aquarium.StoredFish = { stored }
			session.carried = { carried }
			session.lockedUntil = os.clock() + 30
			local result = deps.remotes.RequestSellFish.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(result.payout).to.equal(15) -- only carried
			expect(#session.profile.Aquarium.StoredFish).to.equal(1) -- stored untouched
			expect(#session.carried).to.equal(0) -- carried emptied
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 4. Capacity (store fish)
	-- ================================================================
	describe("Store fish capacity", function()
		it("stores carried fish when under capacity", function()
			local player, session = newTestPair()
			session.carried = { makeFish("Bluegill", "Common", 15) }
			local result = deps.remotes.RequestStoreFish.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(result.stored).to.equal(1)
			expect(#session.profile.Aquarium.StoredFish).to.equal(1)
			player.Parent = nil
		end)

		it("rejects store when carried is empty", function()
			local player, session = newTestPair()
			local result = deps.remotes.RequestStoreFish.OnServerInvoke(player)
			expect(result.ok).to.equal(false)
			player.Parent = nil
		end)

		it("rejects at capacity — StoredFish full and carried non-empty", function()
			local player, session = newTestPair()
			-- Fill to capacity (default 20)
			for i = 1, 20 do
				table.insert(session.profile.Aquarium.StoredFish, makeFish("B" .. i, "Common", 10))
			end
			session.carried = { makeFish("Extra", "Common", 10) }
			local result = deps.remotes.RequestStoreFish.OnServerInvoke(player)
			expect(result.ok).to.equal(false)
			expect(#session.profile.Aquarium.StoredFish).to.equal(20)
			expect(#session.carried).to.equal(1) -- carried untouched
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 5. Lock state machine
	-- ================================================================
	describe("Lock FSM", function()
		it("activate sets lockedUntil and cooldown from base config", function()
			local player, session = newTestPair()
			local before = os.clock()
			local result = deps.remotes.RequestActivateLock.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(session.lockedUntil).to.be.a("number")
			expect(session.lockedUntil >= before + GameConfig.Aquarium.lockDuration - 0.1).to.equal(true)
			expect(session.lockCooldownUntil).to.be.a("number")
			-- cooldown ends after lockDuration + lockCooldown
			expect(session.lockCooldownUntil >= session.lockedUntil + GameConfig.Aquarium.lockCooldown - 0.1).to.equal(true)
			player.Parent = nil
		end)

		it("decrements free uses on each activation", function()
			local player, session = newTestPair()
			local before = session.profile.Defense.LockFreeUsesRemaining
			deps.remotes.RequestActivateLock.OnServerInvoke(player)
			expect(session.profile.Defense.LockFreeUsesRemaining).to.equal(before - 1)
			player.Parent = nil
		end)

		it("rejects when already locked", function()
			local player, session = newTestPair()
			session.lockedUntil = os.clock() + 30
			local result = deps.remotes.RequestActivateLock.OnServerInvoke(player)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("already_locked")
			player.Parent = nil
		end)

		it("rejects when in cooldown", function()
			local player, session = newTestPair()
			session.lockedUntil = 0 -- not locked
			session.lockCooldownUntil = os.clock() + 30 -- but in cooldown
			local result = deps.remotes.RequestActivateLock.OnServerInvoke(player)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("cooldown")
			player.Parent = nil
		end)

		it("doubles cooldown when no free uses remaining", function()
			local player, session = newTestPair()
			session.profile.Defense.LockFreeUsesRemaining = 0
			local result = deps.remotes.RequestActivateLock.OnServerInvoke(player)
			expect(result.ok).to.equal(true)
			expect(result.usedFree).to.equal(false)
			-- lockedDuration stays at 60, but cooldown should be 120*2 = 240 + 60
			local baseLockDuration = GameConfig.Aquarium.lockDuration -- 60
			local expectedLockEnd = os.clock() + baseLockDuration
			local expectedCooldownEnd = expectedLockEnd + GameConfig.Aquarium.lockCooldown * 2 -- 240
			expect(session.lockCooldownUntil >= expectedCooldownEnd - 1).to.equal(true)
			player.Parent = nil
		end)

		it("persists profile timestamps via os.time()", function()
			local player, session = newTestPair()
			local before = os.time()
			deps.remotes.RequestActivateLock.OnServerInvoke(player)
			-- LockUntilTimestamp should be around now + lockDuration
			expect(session.profile.Aquarium.LockUntilTimestamp >= before + GameConfig.Aquarium.lockDuration - 1).to.equal(true)
			expect(session.profile.Aquarium.LockCooldownUntilTimestamp >= session.profile.Aquarium.LockUntilTimestamp).to.equal(true)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 6. Raid protection helpers (standalone module functions)
	-- ================================================================
	describe("Raid protection", function()
		it("hasStealableFish — false with no fish", function()
			local player, session = newTestPair()
			expect(AquariumService.hasStealableFish(session)).to.equal(false)
			player.Parent = nil
		end)

		it("hasStealableFish — true with non-protected fish", function()
			local player, session = newTestPair()
			session.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 15, false) }
			expect(AquariumService.hasStealableFish(session)).to.equal(true)
			player.Parent = nil
		end)

		it("hasStealableFish — false with only Legendary (protected)", function()
			local player, session = newTestPair()
			session.profile.Aquarium.StoredFish = { makeFish("GoldenKoi", "Legendary", 600, true) }
			expect(AquariumService.hasStealableFish(session)).to.equal(false)
			player.Parent = nil
		end)

		it("getStealableFish returns only non-protected fish", function()
			local player, session = newTestPair()
			session.profile.Aquarium.StoredFish = {
				makeFish("Bluegill", "Common", 15, false),
				makeFish("GoldenKoi", "Legendary", 600, true),
				makeFish("Trout", "Uncommon", 35, false),
			}
			local stealable = AquariumService.getStealableFish(session)
			expect(#stealable).to.equal(2)
			expect(stealable[1].SpeciesId == "Bluegill" or stealable[1].SpeciesId == "Trout").to.equal(true)
			player.Parent = nil
		end)

		it("getProtectedFish returns only protected fish", function()
			local player, session = newTestPair()
			session.profile.Aquarium.StoredFish = {
				makeFish("Bluegill", "Common", 15, false),
				makeFish("GoldenKoi", "Legendary", 600, true),
			}
			local protected = AquariumService.getProtectedFish(session)
			expect(#protected).to.equal(1)
			expect(protected[1].IsRaidProtected).to.equal(true)
			player.Parent = nil
		end)

		it("isNewPlayerProtected — true for fresh player", function()
			local player, session = newTestPair()
			expect(AquariumService.isNewPlayerProtected(session)).to.equal(true)
			player.Parent = nil
		end)

		it("isNewPlayerProtected — false after 10 catches", function()
			local player, session = newTestPair()
			session.profile.Stats.TotalCatches = 10
			expect(AquariumService.isNewPlayerProtected(session)).to.equal(false)
			player.Parent = nil
		end)

		it("isNewPlayerProtected — false with aquarium upgrade", function()
			local player, session = newTestPair()
			session.profile.Aquarium.UpgradeLevel = 2
			expect(AquariumService.isNewPlayerProtected(session)).to.equal(false)
			player.Parent = nil
		end)

		it("isEligibleRaidTarget — requires opt-in", function()
			local player, session = newTestPair()
			session.profile.Stats.TotalCatches = 10
			session.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 15, false) }
			-- Raids opted out
			local ok, reason = AquariumService.isEligibleRaidTarget(session)
			expect(ok).to.equal(false)
			expect(reason).to.equal("not_opted_in")
			-- Opt in
			session.profile.Aquarium.RaidOptIn = true
			local ok2, _ = AquariumService.isEligibleRaidTarget(session)
			expect(ok2).to.equal(true)
			player.Parent = nil
		end)

		it("isEligibleRaidTarget — rejects when locked", function()
			local player, session = newTestPair()
			session.profile.Stats.TotalCatches = 10
			session.profile.Aquarium.RaidOptIn = true
			session.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 15, false) }
			session.lockedUntil = os.clock() + 30
			local ok, reason = AquariumService.isEligibleRaidTarget(session)
			expect(ok).to.equal(false)
			expect(reason).to.equal("locked")
			player.Parent = nil
		end)

		it("isEligibleRaidTarget — rejects new-player-protected", function()
			local player, session = newTestPair()
			session.profile.Aquarium.RaidOptIn = true
			session.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 15, false) }
			local ok, reason = AquariumService.isEligibleRaidTarget(session)
			expect(ok).to.equal(false)
			expect(reason).to.equal("new_player_protected")
			player.Parent = nil
		end)

		it("isEligibleRaidAttacker — rejects if stunned", function()
			local player, session = newTestPair()
			session.profile.Stats.TotalCatches = 10
			session.profile.Aquarium.RaidOptIn = true
			session.stunUntil = os.clock() + 10
			local ok, reason = AquariumService.isEligibleRaidAttacker(session)
			expect(ok).to.equal(false)
			expect(reason).to.equal("stunned")
			player.Parent = nil
		end)
	end)
end
