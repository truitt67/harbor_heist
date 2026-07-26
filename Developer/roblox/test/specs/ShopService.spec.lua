-- ShopService.spec.lua
-- TASK 18.7: ShopService unit tests (validation, funds, tier gating).
--
-- Tests exercise the REAL ShopService module through a minimal remote-capture
-- harness. Real GameConfig tables provide authoritative costs. Sessions are
-- plain tables matching the real DataManager session shape. Service stubs are
-- thin capture wrappers only.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)
	local ShopService = require(ServerScriptService.HarborHeist.ShopService)

	-- ================================================================
	-- Test harness
	-- ================================================================

	local playerCounter = 0
	local function makeFakePlayer()
		playerCounter += 1
		local p = {
			UserId = 800000 + playerCounter,
			Name = "TestPlayer" .. playerCounter,
			DisplayName = "TestPlayer" .. playerCounter,
			Parent = true,
		}
		return p
	end

	local function makeSession(player)
		return {
			player = player,
			profile = PlayerProfile.default(),
		}
	end

	local sessions = {}
	local notifyCalls = {}
	local pushedSessions = {}
	local invalidatedSessions = {}
	local auditCalls = {}
	local analyticsCalls = {}
	local dockCosmeticCalls = {}
	local saveCalls = {}

	local deps = {
		remotes = {
			RequestPurchaseUpgrade = {},
			notify = function(player, message, color)
				table.insert(notifyCalls, { player = player, message = message, color = color })
			end,
		},
		dataManager = {
			get = function(player) return sessions[player] end,
			save = function(player)
				table.insert(saveCalls, player)
			end,
		},
		stateSync = {
			push = function(session)
				table.insert(pushedSessions, session)
			end,
			invalidateIncomeCache = function(session)
				table.insert(invalidatedSessions, session)
			end,
		},
		antiExploit = {
			checkRate = function(player, action)
				return true, nil
			end,
			logSuspicious = function(player, action, reason)
				table.insert(auditCalls, { type = "suspicious", action = action, reason = reason })
			end,
		},
		auditLog = {
			logPurchase = function(player, kind, level, cost, name)
				table.insert(auditCalls, { type = "purchase", kind = kind, level = level, cost = cost, name = name })
			end,
		},
		analytics = {
			track = function(player, event, data)
				table.insert(analyticsCalls, { event = event, data = data })
			end,
			isFirst = function(userId, event)
				return false
			end,
		},
		dockManager = {
			getDock = function(player)
				return { owner = player }
			end,
			updateDockCosmetics = function(dock, session)
				table.insert(dockCosmeticCalls, { dock = dock, session = session })
			end,
		},
	}

	-- Initialize ShopService — wires RequestPurchaseUpgrade.OnServerInvoke.
	ShopService.init(deps)
	local handler = deps.remotes.RequestPurchaseUpgrade.OnServerInvoke

	local function deepCopy(t)
		local copy = {}
		for k, v in pairs(t) do
			if type(v) == "table" then
				copy[k] = deepCopy(v)
			else
				copy[k] = v
			end
		end
		return copy
	end

	local function deepEqual(a, b)
		if a == b then return true end
		local ta, tb = type(a), type(b)
		if ta ~= tb or ta ~= "table" then return false end
		for k, v in pairs(a) do
			if not deepEqual(v, b[k]) then return false end
		end
		for k, _ in pairs(b) do
			if a[k] == nil then return false end
		end
		return true
	end

	-- ================================================================
	-- Cases
	-- ================================================================

	describe("Happy path purchases", function()
		it("should purchase the Steel Rod and deduct exact cost", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 1000
			sessions[player] = session

			local before = deepCopy(session.profile)
			local result = handler(player, "rod", 2)

			expect(result.ok).to.equal(true)
			expect(session.profile.Coins).to.equal(1000 - GameConfig.Rods[2].cost)
			expect(session.profile.Equipment.EquippedRodLevel).to.equal(2)
			expect(#session.profile.Equipment.OwnedRodLevels).to.equal(2)
			expect(deepEqual(pushedSessions[#pushedSessions], session)).to.equal(true)
		end)

		it("should purchase the Shrimp Bait and equip it", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 500
			sessions[player] = session

			local result = handler(player, "bait", 2)

			expect(result.ok).to.equal(true)
			expect(session.profile.Coins).to.equal(500 - GameConfig.Baits[2].cost)
			expect(session.profile.Equipment.EquippedBaitLevel).to.equal(2)
		end)

		it("should purchase an aquarium capacity upgrade", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 1000
			sessions[player] = session

			local result = handler(player, "aquarium", 2)

			expect(result.ok).to.equal(true)
			expect(session.profile.Coins).to.equal(1000 - GameConfig.AquariumUpgradeTiers[2].cost)
			expect(session.profile.Aquarium.UpgradeLevel).to.equal(2)
			expect(session.profile.Aquarium.Capacity).to.equal(GameConfig.AquariumUpgradeTiers[2].capacity)
			expect(deepEqual(invalidatedSessions[#invalidatedSessions], session)).to.equal(true)
		end)

		it("should purchase a dock upgrade and refresh cosmetics", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session

			local result = handler(player, "dock", 2)

			expect(result.ok).to.equal(true)
			expect(session.profile.Coins).to.equal(5000 - GameConfig.DockUpgradeTiers[2].cost)
			expect(session.profile.Dock.UpgradeLevel).to.equal(2)
			expect(#dockCosmeticCalls).to.equal(1)
			expect(deepEqual(invalidatedSessions[#invalidatedSessions], session)).to.equal(true)
		end)
	end)

	describe("Insufficient funds", function()
		it("should reject when the player cannot afford the rod", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 100
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, "rod", 2)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("poor")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)
	end)

	describe("Tier gating", function()
		it("should reject skipping rod tier 2 to buy rod tier 3", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, "rod", 3)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("wrong_tier")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)

		it("should reject skipping bait tier 2 to buy bait tier 3", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, "bait", 3)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("wrong_tier")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)
	end)

	describe("Invalid input", function()
		it("should reject unknown kind", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, "jetpack", 1)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_kind")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)

		it("should reject out-of-range level", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, "rod", 99)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_level")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)

		it("should reject negative level", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, "rod", -1)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_level")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)

		it("should reject non-string kind", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			sessions[player] = session
			local before = deepCopy(session.profile)

			local result = handler(player, 123, 1)

			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_args")
			expect(deepEqual(session.profile, before)).to.equal(true)
		end)
	end)

	describe("Replay / duplicate purchase", function()
		it("should reject buying the same rod tier twice", function()
			local player = makeFakePlayer()
			local session = makeSession(player)
			session.profile.Coins = 5000
			sessions[player] = session

			local first = handler(player, "rod", 2)
			expect(first.ok).to.equal(true)

			local second = handler(player, "rod", 2)
			expect(second.ok).to.equal(false)
			expect(second.reason).to.equal("wrong_tier")
		end)
	end)
end
