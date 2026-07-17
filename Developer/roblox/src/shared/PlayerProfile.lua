--[[
	PlayerProfile.lua — Structured profile schema for Harbor Heist V1.

	This module defines the authoritative shape of a player's persistent data.
	It is the contract that DataManager (persistence), StateSync (serialization),
	and every gameplay service read/write against.

	Design notes:
	- Fields mirror PRD.md "Player profile data" (lines 271-326).
	- Fish are currently stored as rarity indexes (1-5). TASK 1.2 (FishInstance)
	  will migrate StoredFish and carried to FishInstance records.
	- Rod/Bait levels are numeric for now (1-3). TASK 2.3 will introduce string IDs.
	- Timestamps use os.time() (epoch seconds), NOT os.clock() — os.clock() resets
	  on server restart and is unsuitable for persisted timer fields.
	- The profile is the PERSISTABLE subset. Runtime-only fields (casting, characterConnection,
	  dockIndex, etc.) live on the session object in DataManager, not here.
]]

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local PlayerProfile = {}

-- Bump this when the schema changes. Migration framework (TASK 1.4) uses this.
PlayerProfile.CURRENT_VERSION = 2
PlayerProfile.MAX_COINS = 999999999
PlayerProfile.MAX_UNCLAIMED_INCOME = 50000

--[[
	Returns a fresh profile with all fields initialized to safe defaults.
	Every sub-table exists (never nil) so downstream code can safely index.
]]
function PlayerProfile.default()
	return {
		Version = PlayerProfile.CURRENT_VERSION,

		Coins = GameConfig.StartingCash,
		TotalCoinsEarned = 0,

		Equipment = {
			EquippedRodLevel = 1,
			EquippedBaitLevel = 1,
			OwnedRodLevels = { 1 },
			BaitInventory = { level = 1, quantity = -1 }, -- -1 = unlimited (reusable, per DEC-5)
		},

		Aquarium = {
			Capacity = GameConfig.Aquarium.baseCapacity,
			UpgradeLevel = 1,
			StoredFish = {}, -- rarity indexes for now; FishInstance records after TASK 1.2
			UnclaimedIncome = 0,
			LastIncomeTimestamp = 0,
			LockUntilTimestamp = 0,
			LockCooldownUntilTimestamp = 0,
			RaidProtectionUntilTimestamp = 0,
			RaidOptIn = false,
		},

		Dock = {
			UpgradeLevel = 1,
			CosmeticUnlocks = {},
		},

		Collection = {
			DiscoveredSpecies = {},
			MilestonesClaimed = {},
		},

		PvP = {
			RaidAttemptsToday = 0,
			LastRaidTimestamp = 0,
			RecentTargetUserIds = {},
			RaidsWon = 0,
			RaidsLost = 0,
			-- Carry over the legacy steal cooldown field until RaidService replaces it
			StealCooldownUntilTimestamp = 0,
		},

		Onboarding = {
			HasCompletedIntro = false,
			HasCaughtFirstFish = false,
			HasStoredFirstFish = false,
			HasClaimedIncome = false,
			HasSeenRaidExplanation = false,
		},
	}
end

--[[
	Clamps a coin value to the valid range [0, MAX_COINS].
	Use on every write path to prevent overflow / negative exploits.
]]
function PlayerProfile.clampCoins(value)
	if type(value) ~= "number" then
		return 0
	end
	return math.floor(math.max(0, math.min(PlayerProfile.MAX_COINS, value)))
end

return PlayerProfile
