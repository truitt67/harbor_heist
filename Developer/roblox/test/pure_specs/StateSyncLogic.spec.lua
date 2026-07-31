-- StateSync pure-logic unit tests (TASK 41-01-C, harborheist-8la1; EPIC 41 harborheist-m3vj).
--
-- StateSync has game:GetService at the top level (requires GameConfig), so it
-- cannot be required directly in the lune pure runner. Instead, the income
-- math, capacity accessor, income-cache invalidation, and the snapshot()
-- client-state contract are mirrored as pure Luau functions and exercised
-- against the authoritative config values. Source-contract assertions verify
-- that the production code still contains the logic tested here.
--
-- Covers: getCapacity, incomePerSec (sum fish IncomePerMinute/60 x aquarium
-- tier incomeMultiplier x dock tier incomeMultiplier, with caching),
-- invalidateIncomeCache, and snapshot() (totalCatches=max(Stats,PvP), DEC-4
-- raidEligible, liveWellCounts grouping, timer clamps, carried/stored expose).
-- No mocks, fakes, or stubs — only pure logic mirrors + source-file contract
-- checks. push() and setupLeaderstats() touch Roblox Instances/remotes and are
-- verified by source-contract presence only (EPIC 19 covers them at runtime).

local fs = require("@lune/fs")

-- ──────────────────────────────────────────────────────────────────────
-- Config mirrors (must match src/shared/GameConfig.lua)
-- ──────────────────────────────────────────────────────────────────────

local MAX_CARRIED = 5
local RAID_UNLOCK_TOTAL_CATCHES = 10
local DEFENSE_LOCK_FREE_USES_MAX = 3

-- incomeMultiplier per upgrade tier (AquariumUpgradeTiers / DockUpgradeTiers)
local AQUARIUM_TIERS = { [1] = 1.0, [2] = 1.1, [3] = 1.25, [4] = 1.5 }
local DOCK_TIERS = { [1] = 1.0, [2] = 1.15, [3] = 1.35, [4] = 1.6 }

-- ──────────────────────────────────────────────────────────────────────
-- Logic mirrors (verbatim from StateSync.lua production code)
-- ──────────────────────────────────────────────────────────────────────

-- mirrors StateSync.getCapacity (lines 7-11)
local function getCapacity(session)
	return session.profile.Aquarium.Capacity
end

-- mirrors StateSync.incomePerSec (lines 13-49)
local function incomePerSec(session)
	if session.cachedIncomePerSec ~= nil then
		return session.cachedIncomePerSec
	end
	local total = 0
	for _, fish in ipairs(session.profile.Aquarium.StoredFish) do
		total += fish.IncomePerMinute / 60
	end
	local upLevel = session.profile.Aquarium.UpgradeLevel or 1
	local tier = AQUARIUM_TIERS[upLevel]
	if tier then
		total *= tier
	end
	local dockLevel = session.profile.Dock.UpgradeLevel or 1
	local dockTier = DOCK_TIERS[dockLevel]
	if dockTier then
		total *= dockTier
	end
	session.cachedIncomePerSec = total
	return total
end

-- mirrors StateSync.invalidateIncomeCache (lines 56-60)
local function invalidateIncomeCache(session)
	if session ~= nil then
		session.cachedIncomePerSec = nil
	end
end

-- mirrors StateSync.snapshot (lines 62-145). Calls the local mirrors above so
-- the snapshot contract is exercised end-to-end against the same logic.
local function snapshot(session)
	local now = os.clock()
	local profile = session.profile
	local aquarium = profile.Aquarium
	local liveWellCounts = {}
	for _, fish in ipairs(aquarium.StoredFish) do
		local key = fish.Rarity
		liveWellCounts[key] = (liveWellCounts[key] or 0) + 1
	end
	local totalCatches = math.max((profile.Stats and profile.Stats.TotalCatches) or 0, (profile.PvP and profile.PvP.TotalCatches) or 0)
	return {
		cash = math.floor(profile.Coins),
		totalEarned = math.floor(profile.TotalCoinsEarned),
		rodLevel = profile.Equipment.EquippedRodLevel,
		baitLevel = profile.Equipment.EquippedBaitLevel,
		upgradeLevel = profile.Aquarium.UpgradeLevel or 1,
		lockLevel = profile.Aquarium.LockLevel or 0,
		alarmLevel = profile.Aquarium.AlarmLevel or 0,
		dockLevel = profile.Dock.UpgradeLevel or 1,
		onboarding = profile.Onboarding,
		stunRemaining = math.max(0, (session.stunUntil or 0) - now),
		hasBoat = (session.boatModel ~= nil),
		carried = #session.carried,
		carriedFish = session.carried,
		maxCarried = MAX_CARRIED,
		liveWellCount = #aquarium.StoredFish,
		liveWellCounts = liveWellCounts,
		storedFish = aquarium.StoredFish,
		capacity = getCapacity(session),
		incomePerSec = incomePerSec(session),
		unclaimedIncome = math.floor(aquarium.UnclaimedIncome),
		lockedUntil = math.max(0, (session.lockedUntil or 0) - now),
		lockCooldownUntil = math.max(0, (session.lockCooldownUntil or 0) - now),
		raidOptIn = aquarium.RaidOptIn == true,
		totalCatches = totalCatches,
		raidEligible = (aquarium.UpgradeLevel or 1) > 1 or totalCatches >= RAID_UNLOCK_TOTAL_CATCHES,
		raidUnlockCatches = RAID_UNLOCK_TOTAL_CATCHES,
		lockFreeUsesRemaining = (profile.Defense and profile.Defense.LockFreeUsesRemaining) or 0,
		lockFreeUsesMax = (profile.Defense and profile.Defense.LockFreeUsesMax) or DEFENSE_LOCK_FREE_USES_MAX,
		dataStoreHealthy = true,
		dockIndex = session.dockIndex,
	}
end

-- ──────────────────────────────────────────────────────────────────────
-- Source contract helpers
-- ──────────────────────────────────────────────────────────────────────

local stateSyncSource = fs.readFile("src/server/StateSync.lua")
local gameConfigSource = fs.readFile("src/shared/GameConfig.lua")

-- ──────────────────────────────────────────────────────────────────────
-- Session / fish factories
-- ──────────────────────────────────────────────────────────────────────

local function makeFish(speciesId, rarity, incomePerMinute)
	return {
		SpeciesId = speciesId,
		Rarity = rarity,
		IncomePerMinute = incomePerMinute,
		BaseSellValue = 100,
		IsRaidProtected = (rarity == "Legendary"),
	}
end

local function makeSession()
	return {
		profile = {
			Coins = 0,
			TotalCoinsEarned = 0,
			Equipment = { EquippedRodLevel = 1, EquippedBaitLevel = 1 },
			Aquarium = {
				Capacity = 20,
				UpgradeLevel = 1,
				StoredFish = {},
				UnclaimedIncome = 0,
				RaidOptIn = false,
				LockLevel = 0,
				AlarmLevel = 0,
			},
			Dock = { UpgradeLevel = 1 },
			Collection = { DiscoveredSpecies = {} },
			Stats = { TotalCatches = 0 },
			PvP = { TotalCatches = 0 },
			Defense = { LockFreeUsesRemaining = 3, LockFreeUsesMax = 3 },
			Onboarding = { HasCaughtFirstFish = false },
		},
		carried = {},
		lockedUntil = 0,
		lockCooldownUntil = 0,
		stunUntil = 0,
		dockIndex = 1,
		boatModel = nil,
	}
end

-- Float-safe equality for income math (multipliers like 1.1 / 1.6 are not all
-- exactly representable, so 1.5 * 1.6 != literal 2.4 at the bit level).
local function closeTo(a, b)
	return math.abs(a - b) < 1e-9
end

return function(describe, it, expect)
	-- ════════════════════════════════════════════════════════════════════
	-- getCapacity
	-- ════════════════════════════════════════════════════════════════════
	describe("getCapacity", function()
		it("returns the default profile.Aquarium.Capacity", function()
			local s = makeSession()
			expect(getCapacity(s)).to.equal(20)
		end)

		it("returns an upgraded capacity verbatim", function()
			local s = makeSession()
			s.profile.Aquarium.Capacity = 50
			expect(getCapacity(s)).to.equal(50)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- incomePerSec — core economy math
	-- ════════════════════════════════════════════════════════════════════
	describe("incomePerSec", function()
		it("is 0 for an empty aquarium", function()
			local s = makeSession()
			expect(closeTo(incomePerSec(s), 0)).to.equal(true)
		end)

		it("sums IncomePerMinute/60 across stored fish", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60), makeFish("Trout", "Uncommon", 120) }
			-- (60 + 120) / 60 = 3.0, no multipliers at tier 1
			expect(closeTo(incomePerSec(s), 3.0)).to.equal(true)
		end)

		it("applies the aquarium tier income multiplier", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60) }
			s.profile.Aquarium.UpgradeLevel = 2
			-- 1.0/sec * 1.1
			expect(closeTo(incomePerSec(s), 1.1)).to.equal(true)
		end)

		it("applies the dock tier income multiplier", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60) }
			s.profile.Dock.UpgradeLevel = 2
			-- 1.0/sec * 1.15
			expect(closeTo(incomePerSec(s), 1.15)).to.equal(true)
		end)

		it("stacks aquarium and dock multipliers (maxed = 1.5 * 1.6 = 2.4x)", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60) }
			s.profile.Aquarium.UpgradeLevel = 4
			s.profile.Dock.UpgradeLevel = 4
			-- 1.0/sec * 1.5 * 1.6 = 2.4
			expect(closeTo(incomePerSec(s), 2.4)).to.equal(true)
		end)

		it("applies tier multipliers to the summed fish income", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60), makeFish("Trout", "Uncommon", 120) }
			s.profile.Aquarium.UpgradeLevel = 2
			-- 3.0/sec * 1.1 = 3.3
			expect(closeTo(incomePerSec(s), 3.3)).to.equal(true)
		end)

		it("caches the computed value on the session", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60) }
			expect(s.cachedIncomePerSec).to.equal(nil)
			incomePerSec(s)
			expect(s.cachedIncomePerSec).to.be.a("number")
		end)

		it("returns the cached value without recomputing", function()
			local s = makeSession()
			s.cachedIncomePerSec = 999 -- pre-seeded cache; must be returned verbatim
			expect(incomePerSec(s)).to.equal(999)
		end)

		it("treats a legit 0 (empty aquarium) as cacheable, not a recompute trigger", function()
			local s = makeSession()
			expect(incomePerSec(s)).to.equal(0) -- empty -> 0
			expect(s.cachedIncomePerSec).to.equal(0) -- cached (nil-check, not truthiness)
			-- A second call returns the cached 0 (no StoredFish to change it)
			expect(incomePerSec(s)).to.equal(0)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- invalidateIncomeCache
	-- ════════════════════════════════════════════════════════════════════
	describe("invalidateIncomeCache", function()
		it("clears the cached value so incomePerSec recomputes", function()
			local s = makeSession()
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60) }
			s.cachedIncomePerSec = 999
			invalidateIncomeCache(s)
			expect(s.cachedIncomePerSec).to.equal(nil)
			expect(closeTo(incomePerSec(s), 1.0)).to.equal(true) -- recomputed, not 999
		end)

		it("is nil-safe (no error on a nil session)", function()
			local ok = pcall(invalidateIncomeCache, nil)
			expect(ok).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- snapshot — client-state contract
	-- ════════════════════════════════════════════════════════════════════
	describe("Snapshot economy + equipment fields", function()
		it("floors Coins/TotalCoinsEarned and reads rod/bait levels", function()
			local s = makeSession()
			s.profile.Coins = 150.7
			s.profile.TotalCoinsEarned = 300.2
			s.profile.Equipment.EquippedRodLevel = 3
			s.profile.Equipment.EquippedBaitLevel = 2
			local snap = snapshot(s)
			expect(snap.cash).to.equal(150)
			expect(snap.totalEarned).to.equal(300)
			expect(snap.rodLevel).to.equal(3)
			expect(snap.baitLevel).to.equal(2)
		end)

		it("exposes upgrade/lock/alarm/dock tier levels with safe defaults", function()
			local s = makeSession()
			local snap = snapshot(s)
			expect(snap.upgradeLevel).to.equal(1)
			expect(snap.lockLevel).to.equal(0)
			expect(snap.alarmLevel).to.equal(0)
			expect(snap.dockLevel).to.equal(1)
			s.profile.Aquarium.UpgradeLevel = 3
			s.profile.Aquarium.LockLevel = 2
			s.profile.Aquarium.AlarmLevel = 1
			s.profile.Dock.UpgradeLevel = 4
			local snap2 = snapshot(s)
			expect(snap2.upgradeLevel).to.equal(3)
			expect(snap2.lockLevel).to.equal(2)
			expect(snap2.alarmLevel).to.equal(1)
			expect(snap2.dockLevel).to.equal(4)
		end)
	end)

	describe("Snapshot carried + stored fish", function()
		it("counts carried, exposes carriedFish + maxCarried, and liveWellCount/Counts", function()
			local s = makeSession()
			s.carried = { makeFish("Bluegill", "Common", 60), makeFish("Trout", "Uncommon", 120) }
			s.profile.Aquarium.StoredFish = {
				makeFish("Bluegill", "Common", 60),
				makeFish("Bluegill", "Common", 60),
				makeFish("Snapper", "Rare", 80),
			}
			local snap = snapshot(s)
			expect(snap.carried).to.equal(2)
			expect(snap.carriedFish).to.equal(s.carried)
			expect(snap.maxCarried).to.equal(5)
			expect(snap.liveWellCount).to.equal(3)
			expect(snap.liveWellCounts.Common).to.equal(2)
			expect(snap.liveWellCounts.Rare).to.equal(1)
			expect(snap.storedFish).to.equal(s.profile.Aquarium.StoredFish)
		end)
	end)

	describe("Snapshot capacity + income + unclaimed", function()
		it("wires capacity and incomePerSec from the mirrors and floors unclaimed", function()
			local s = makeSession()
			s.profile.Aquarium.Capacity = 45
			s.profile.Aquarium.StoredFish = { makeFish("Bluegill", "Common", 60) }
			s.profile.Aquarium.UnclaimedIncome = 123.9
			local snap = snapshot(s)
			expect(snap.capacity).to.equal(45)
			expect(closeTo(snap.incomePerSec, 1.0)).to.equal(true)
			expect(snap.unclaimedIncome).to.equal(123)
		end)
	end)

	describe("Snapshot timer clamps", function()
		it("clamps stunRemaining to >=0 and reports remaining stun", function()
			local s = makeSession()
			s.stunUntil = os.clock() + 5
			local snap = snapshot(s)
			expect(snap.stunRemaining > 4.9 and snap.stunRemaining <= 5).to.equal(true)
			s.stunUntil = os.clock() - 10
			expect(snapshot(s).stunRemaining).to.equal(0)
		end)

		it("clamps lockedUntil / lockCooldownUntil to >=0", function()
			local s = makeSession()
			s.lockedUntil = os.clock() + 30
			s.lockCooldownUntil = os.clock() + 90
			local snap = snapshot(s)
			expect(snap.lockedUntil > 29 and snap.lockedUntil <= 30).to.equal(true)
			expect(snap.lockCooldownUntil > 89 and snap.lockCooldownUntil <= 90).to.equal(true)
			s.lockedUntil = os.clock() - 5
			expect(snapshot(s).lockedUntil).to.equal(0)
		end)

		it("reports hasBoat from boatModel presence", function()
			local s = makeSession()
			expect(snapshot(s).hasBoat).to.equal(false)
			s.boatModel = {}
			expect(snapshot(s).hasBoat).to.equal(true)
		end)
	end)

	describe("Snapshot raid eligibility + onboarding + lock free uses", function()
		it("totalCatches = max(Stats, PvP)", function()
			local s = makeSession()
			s.profile.Stats.TotalCatches = 7
			s.profile.PvP.TotalCatches = 10
			expect(snapshot(s).totalCatches).to.equal(10)
			s.profile.Stats.TotalCatches = 10
			s.profile.PvP.TotalCatches = 3
			expect(snapshot(s).totalCatches).to.equal(10)
			s.profile.Stats.TotalCatches = 0
			s.profile.PvP.TotalCatches = 0
			expect(snapshot(s).totalCatches).to.equal(0)
		end)

		it("raidEligible uses the DEC-4 gate (upgrade OR unlockTotalCatches)", function()
			local s = makeSession()
			expect(snapshot(s).raidEligible).to.equal(false) -- fresh: upgrade1, 0 catches
			s.profile.Aquarium.UpgradeLevel = 2
			expect(snapshot(s).raidEligible).to.equal(true) -- upgrade path
			s.profile.Aquarium.UpgradeLevel = 1
			s.profile.Stats.TotalCatches = 10
			expect(snapshot(s).raidEligible).to.equal(true) -- catches path
			s.profile.Stats.TotalCatches = 9
			expect(snapshot(s).raidEligible).to.equal(false) -- just short
			expect(snapshot(s).raidUnlockCatches).to.equal(10)
		end)

		it("raidOptIn mirrors the profile flag", function()
			local s = makeSession()
			expect(snapshot(s).raidOptIn).to.equal(false)
			s.profile.Aquarium.RaidOptIn = true
			expect(snapshot(s).raidOptIn).to.equal(true)
		end)

		it("exposes onboarding + lock free-use counts", function()
			local s = makeSession()
			local snap = snapshot(s)
			expect(snap.onboarding).to.equal(s.profile.Onboarding)
			expect(snap.lockFreeUsesRemaining).to.equal(3)
			expect(snap.lockFreeUsesMax).to.equal(3)
			s.profile.Defense.LockFreeUsesRemaining = 1
			expect(snapshot(s).lockFreeUsesRemaining).to.equal(1)
		end)

		it("dataStoreHealthy defaults true and dockIndex is passed through", function()
			local s = makeSession()
			s.dockIndex = 4
			local snap = snapshot(s)
			expect(snap.dataStoreHealthy).to.equal(true)
			expect(snap.dockIndex).to.equal(4)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract verification
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract verification", function()
		it("StateSync.lua declares the pure functions under test", function()
			expect(stateSyncSource:find("function StateSync.getCapacity", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("function StateSync.incomePerSec", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("function StateSync.invalidateIncomeCache", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("function StateSync.snapshot", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("function StateSync.push", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("function StateSync.setupLeaderstats", 1, true)).to.be.a("number")
		end)

		it("getCapacity reads profile.Aquarium.Capacity", function()
			expect(stateSyncSource:find("session.profile.Aquarium.Capacity", 1, true)).to.be.a("number")
		end)

		it("incomePerSec caches via nil-check and sums IncomePerMinute/60", function()
			expect(stateSyncSource:find("session.cachedIncomePerSec ~= nil", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("fish.IncomePerMinute / 60", 1, true)).to.be.a("number")
		end)

		it("incomePerSec applies aquarium + dock tier multipliers", function()
			expect(stateSyncSource:find("AquariumUpgradeTiers[upLevel]", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("tier.incomeMultiplier", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("DockUpgradeTiers[dockLevel]", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("dockTier.incomeMultiplier", 1, true)).to.be.a("number")
		end)

		it("invalidateIncomeCache nils the cache and is nil-safe", function()
			expect(stateSyncSource:find("session.cachedIncomePerSec = nil", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("if session ~= nil then", 1, true)).to.be.a("number")
		end)

		it("snapshot derives totalCatches = max(Stats, PvP) and groups liveWellCounts", function()
			expect(stateSyncSource:find("profile.PvP and profile.PvP.TotalCatches", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("liveWellCounts[key] = (liveWellCounts[key] or 0) + 1", 1, true)).to.be.a("number")
		end)

		it("snapshot implements the DEC-4 raidEligible gate + unlock constant", function()
			expect(stateSyncSource:find("raidEligible = (aquarium.UpgradeLevel or 1) > 1 or totalCatches >= GameConfig.Raid.unlockTotalCatches", 1, true)).to.be.a("number")
			expect(stateSyncSource:find("raidUnlockCatches = GameConfig.Raid.unlockTotalCatches", 1, true)).to.be.a("number")
		end)

		it("snapshot exposes lock free-use counts from Defense", function()
			expect(stateSyncSource:find("lockFreeUsesRemaining = (profile.Defense and profile.Defense.LockFreeUsesRemaining)", 1, true)).to.be.a("number")
		end)

		it("GameConfig.lua still carries the mirrored constants", function()
			expect(gameConfigSource:find("MaxCarried = 5", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("unlockTotalCatches = 10", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("LockFreeUsesMax = 3", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("incomeMultiplier = 1.1", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("incomeMultiplier = 1.15", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("incomeMultiplier = 1.5", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("incomeMultiplier = 1.6", 1, true)).to.be.a("number")
		end)
	end)
end