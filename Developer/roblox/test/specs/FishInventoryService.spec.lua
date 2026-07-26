-- FishInventoryService.spec.lua
-- TASK 18.8: FishInventoryService unit tests (capacity, integrity,
-- no duplication, sell-single, validation, no aliasing).
--
-- Exercises the REAL module via OnServerInvoke through a thin deps harness.
-- Real GameConfig, real FishInstance, real PlayerProfile. Sessions are
-- plain tables matching the DataManager session shape. No game-logic mocks.

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)
	local FishInstance = require(ReplicatedStorage.Shared.FishInstance)
	local FishInventoryService = require(ServerScriptService.HarborHeist.FishInventoryService)

	-- ================================================================
	-- Harness
	-- ================================================================

	-- Creates a valid FishInstance with a known species. Uses the real
	-- factory so validate() passes; InstanceId is a generated GUID.
	local function makeFish(speciesId)
		return FishInstance.new(speciesId, "StarterPier")
	end

	local function makeSession()
		local profile = PlayerProfile.default()
		return {
			player = nil,
			profile = profile,
			carried = {},
			lockedUntil = 0,
		}
	end

	local function makeDeps()
		local sessions = {}
		return {
			sessions = sessions,
			remotes = {
				SellFish = {},
				StoreSingleFish = {},
				notify = function() end,
			},
			dataManager = {
				get = function(player) return sessions[player] end,
				save = function() end,
			},
			dockManager = {
				getDock = function() return {} end,
				updateAquariumVisual = function() end,
			},
			stateSync = {
				push = function() end,
				getCapacity = function(session)
					return session.profile.Aquarium.Capacity
				end,
				invalidateIncomeCache = function() end,
			},
			analytics = {
				track = function() end,
				isFirst = function() return false end,
			},
			questService = {
				onFishSold = function() end,
				onFishStored = function() end,
			},
			onboarding = { mark = function() return false end },
			antiExploit = nil,
			auditLog = nil,
		}
	end

	local deps = makeDeps()
	pcall(function() FishInventoryService.init(deps) end)

	-- Player helper
	local playerCounter = 0
	local function makeFakePlayer()
		playerCounter += 1
		local p = {
			UserId = 920000 + playerCounter,
			Name = "TestPlayer" .. playerCounter,
			DisplayName = "TestPlayer" .. playerCounter,
			Parent = true,
		}
		return p
	end

	local function newTestPair()
		local player = makeFakePlayer()
		local session = makeSession()
		session.player = player
		deps.sessions[player] = session
		return player, session
	end

	-- ================================================================
	-- 1. SellFish from carried
	-- ================================================================
	describe("SellFish from carried", function()
		it("removes the correct fish and pays its base value", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			local result = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId)
			expect(result.ok).to.equal(true)
			expect(result.payout).to.equal(fish.BaseSellValue)
			expect(result.speciesId).to.equal("Bluegill")
			expect(#session.carried).to.equal(0)
			player.Parent = nil
		end)

		it("leaves other carried fish untouched", function()
			local player, session = newTestPair()
			local f1 = makeFish("Bluegill")
			local f2 = makeFish("Trout")
			local f3 = makeFish("Perch")
			session.carried = { f1, f2, f3 }
			local result = deps.remotes.SellFish.OnServerInvoke(player, f2.InstanceId)
			expect(result.ok).to.equal(true)
			expect(result.speciesId).to.equal("Trout")
			expect(#session.carried).to.equal(2)
			-- Verify remaining fish IDs (in some order)
			local ids = {}
			for _, f in ipairs(session.carried) do ids[f.InstanceId] = true end
			expect(ids[f1.InstanceId]).to.equal(true)
			expect(ids[f3.InstanceId]).to.equal(true)
			expect(ids[f2.InstanceId]).to.equal(nil)
			player.Parent = nil
		end)

		it("increments Coins via clampCoins", function()
			local player, session = newTestPair()
			session.profile.Coins = 100
			local fish = makeFish("Trout") -- BaseSellValue=35
			session.carried = { fish }
			deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId)
			expect(session.profile.Coins).to.equal(135)
			expect(session.profile.TotalCoinsEarned).to.equal(35)
			player.Parent = nil
		end)

		it("returns the EXACT speciesId of the sold fish", function()
			local player, session = newTestPair()
			local fish = makeFish("Bass")
			session.carried = { fish }
			local result = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId)
			expect(result.speciesId).to.equal(fish.SpeciesId)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 2. SellFish from aquarium (fromAquarium=true)
	-- ================================================================
	describe("SellFish from aquarium", function()
		it("removes from StoredFish and pays out correctly", function()
			local player, session = newTestPair()
			local fish = makeFish("Snapper")
			session.profile.Aquarium.StoredFish = { fish }
			local result = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId, true)
			expect(result.ok).to.equal(true)
			expect(result.payout).to.equal(fish.BaseSellValue)
			expect(#session.profile.Aquarium.StoredFish).to.equal(0)
			player.Parent = nil
		end)

		it("14.6 regression: rejects while aquarium is locked", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.profile.Aquarium.StoredFish = { fish }
			session.lockedUntil = os.clock() + 60
			local result = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId, true)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("aquarium_locked")
			-- Stored fish untouched
			expect(#session.profile.Aquarium.StoredFish).to.equal(1)
			player.Parent = nil
		end)

		it("rejects during raid protection window", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.profile.Aquarium.StoredFish = { fish }
			session.profile.Aquarium.RaidProtectionUntilTimestamp = os.time() + 60
			local result = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId, true)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("raid_protected")
			expect(#session.profile.Aquarium.StoredFish).to.equal(1)
			player.Parent = nil
		end)

		it("falls back to carried when fromAquarium is not true", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			session.profile.Aquarium.StoredFish = {}
			-- Calling without fromAquarium arg (defaults to nil/false) — sells from carried
			local result = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId)
			expect(result.ok).to.equal(true)
			expect(#session.carried).to.equal(0)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 3. StoreSingleFish (capacity + move semantics)
	-- ================================================================
	describe("StoreSingleFish", function()
		it("moves a fish from carried to StoredFish", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			local result = deps.remotes.StoreSingleFish.OnServerInvoke(player, fish.InstanceId)
			expect(result.ok).to.equal(true)
			expect(result.speciesId).to.equal("Bluegill")
			expect(#session.carried).to.equal(0)
			expect(#session.profile.Aquarium.StoredFish).to.equal(1)
			player.Parent = nil
		end)

		it("rejects when fish not in carried", function()
			local player, session = newTestPair()
			local result = deps.remotes.StoreSingleFish.OnServerInvoke(player, "non-existent-id")
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("not_in_carried")
			player.Parent = nil
		end)

		it("rejects at aquarium capacity — StoreSingleFish rejected", function()
			local player, session = newTestPair()
			-- Fill to capacity (default 20 from PlayerProfile)
			for i = 1, 20 do
				table.insert(session.profile.Aquarium.StoredFish, makeFish("Sardine"))
			end
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			local result = deps.remotes.StoreSingleFish.OnServerInvoke(player, fish.InstanceId)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("aquarium_full")
			expect(#session.profile.Aquarium.StoredFish).to.equal(20)
			expect(#session.carried).to.equal(1) -- carried untouched
			player.Parent = nil
		end)

		it("accepts exactly at capacity-1, then stores one more to reach cap", function()
			local player, session = newTestPair()
			-- Fill to capacity-1 = 19
			for i = 1, 19 do
				table.insert(session.profile.Aquarium.StoredFish, makeFish("Sardine"))
			end
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			local result = deps.remotes.StoreSingleFish.OnServerInvoke(player, fish.InstanceId)
			expect(result.ok).to.equal(true)
			expect(#session.profile.Aquarium.StoredFish).to.equal(20)
			expect(#session.carried).to.equal(0)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 4. Integrity & anti-duplication
	-- ================================================================
	describe("Integrity & anti-duplication", function()
		it("the stored record is the SAME object that was in carried (no copy)", function()
			local player, session = newTestPair()
			local fish = makeFish("Trout")
			session.carried = { fish }
			deps.remotes.StoreSingleFish.OnServerInvoke(player, fish.InstanceId)
			-- Lua tables compare by reference — verify the table identity moved
			expect(session.profile.Aquarium.StoredFish[1] == fish).to.equal(true)
			player.Parent = nil
		end)

		it("selling a fish twice resolves to fish_not_found on second call", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			local first = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId)
			expect(first.ok).to.equal(true)
			local second = deps.remotes.SellFish.OnServerInvoke(player, fish.InstanceId)
			expect(second.ok).to.equal(false)
			expect(second.reason).to.equal("fish_not_found")
			player.Parent = nil
		end)

		it("no aliasing: store moves the table so removed-from-carried is in-stored only", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			deps.remotes.StoreSingleFish.OnServerInvoke(player, fish.InstanceId)
			-- carried is empty
			expect(#session.carried).to.equal(0)
			-- stored holds exactly one fish (the same reference)
			expect(#session.profile.Aquarium.StoredFish).to.equal(1)
			expect(session.profile.Aquarium.StoredFish[1] == fish).to.equal(true)
			player.Parent = nil
		end)
	end)

	-- ================================================================
	-- 5. Validation & error paths
	-- ================================================================
	describe("Validation & errors", function()
		it("rejects empty InstanceId string", function()
			local player, session = newTestPair()
			local result = deps.remotes.SellFish.OnServerInvoke(player, "")
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_id")
			player.Parent = nil
		end)

		it("rejects nil InstanceId", function()
			local player, session = newTestPair()
			local result = deps.remotes.SellFish.OnServerInvoke(player, nil)
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("bad_id")
			player.Parent = nil
		end)

		it("rejects non-existent InstanceId — state unchanged", function()
			local player, session = newTestPair()
			local fish = makeFish("Bluegill")
			session.carried = { fish }
			local result = deps.remotes.SellFish.OnServerInvoke(player, "not-a-real-id")
			expect(result.ok).to.equal(false)
			expect(result.reason).to.equal("fish_not_found")
			expect(#session.carried).to.equal(1) -- state unchanged
			player.Parent = nil
		end)
	end)
end
