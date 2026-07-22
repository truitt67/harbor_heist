--[[
	FishInventoryService.lua — Server-side fish inventory management.

	Handles per-fish operations: sell individual fish, store individual fish
	from carried to aquarium. All operations are server-validated (PRD INV-06).
	Prevents duplication, negative quantities, over-capacity transfers (INV-05).

	The bulk "RequestSellFish" and "RequestStoreFish" (store-all) remain in AquariumService
	as convenience wrappers. This service adds the granular per-fish API.
]]

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)
local PlayerProfile = require(game:GetService("ReplicatedStorage").Shared.PlayerProfile)

local FishInventoryService = {}

function FishInventoryService.init(deps)
	local remotes = deps.remotes
	local antiExploit = deps.antiExploit
	local auditLog = deps.auditLog
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync
	local dockManager = deps.dockManager
	local analytics = deps.analytics -- EPIC 11
	local questService = deps.questService -- quest progress: store_count
	local onboarding = deps.onboarding -- EPIC 9

	-- Helper: find a fish in a list by InstanceId
	local function findFishIndex(list, instanceId)
		for i, fish in ipairs(list) do
			if fish.InstanceId == instanceId then
				return i
			end
		end
		return nil
	end

	-- Helper: notify client
	local function notify(player, msg, color)
		remotes.notify(player, msg, color)
	end

	-- ════════════════════════════════════════════════════════════════════════
	-- Sell a single fish from carried inventory (PRD INV-03), or from the
	-- aquarium when fromAquarium=true (PRD AQUA-09 / TASK 5.5, gated on
	-- lock + raid-protection state).
	-- ════════════════════════════════════════════════════════════════════════
	remotes.SellFish.OnServerInvoke = function(player, instanceId, fromAquarium)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "sell")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		if type(instanceId) ~= "string" or #instanceId == 0 then
			return { ok = false, reason = "bad_id" }
		end

		-- Find the fish: carried by default, StoredFish when fromAquarium=true.
		-- N3 (CRITICAL): previously fell through to search Aquarium.StoredFish
		-- on a miss, which let an exploiter fire SellFish(id) + StoreSingleFish(id)
		-- in the same frame to double-pay. SellFish now only sells from carried
		-- UNLESS the caller passes an explicit fromAquarium=true flag (TASK 5.5).
		local fish = nil
		local soldFromStored = false
		if fromAquarium == true then
			-- TASK 5.5 (9mu.5 / PRD AQUA-09): direct-sell one STORED fish.
			-- Restricted during an active lock or raid protection so a player
			-- cannot hide fish from an imminent raid by liquidating them (same
			-- gate pattern as wqw.6 RequestSellFish + isEligibleRaidTarget).
			local locked = (session.lockedUntil or 0) > os.clock()
			if locked then
				notify(player, "Aquarium is locked — stored fish can't be sold until the lock expires.", Color3.fromRGB(255, 170, 80))
				return { ok = false, reason = "aquarium_locked" }
			end
			local raidProtected = (session.profile.Aquarium.RaidProtectionUntilTimestamp or 0) > os.time()
			if raidProtected then
				notify(player, "Raid protection active — stored fish can't be removed right now.", Color3.fromRGB(255, 170, 80))
				return { ok = false, reason = "raid_protected" }
			end
			local storedFish = session.profile.Aquarium.StoredFish
			local idx = findFishIndex(storedFish, instanceId)
			if idx then
				fish = table.remove(storedFish, idx)
				soldFromStored = true
			end
		else
			local idx = findFishIndex(session.carried, instanceId)
			if idx then
				fish = table.remove(session.carried, idx)
			end
		end

		-- TASK 14.15 (wqw.15) + sc0 (fresh-eyes): invalidate the cached incomePerSec
		-- IMMEDIATELY after removing a stored fish — BEFORE the validate check below.
		-- If validate rejects the fish (corrupt record), the early return previously
		-- skipped invalidateIncomeCache, leaving a stale cache. Moving it here ensures
		-- the cache is invalidated regardless of the validate outcome. (Unreachable in
		-- practice — sanitize guarantees stored fish are valid — but defensive.)
		if soldFromStored then
			stateSync.invalidateIncomeCache(session)
		end

		if not fish then
			return { ok = false, reason = "fish_not_found" }
		end

		-- Validate the fish record before selling
		if not FishInstance.validate(fish) then
			warn("[HarborHeist] Invalid fish record sold: " .. tostring(instanceId))
			return { ok = false, reason = "invalid_fish" }
		end

		local payout = fish.BaseSellValue
		-- N5: clampCoins on the per-fish sell path too.
		session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + payout)
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + payout

		-- TASK 10.3 (fresh-eyes, 9mu.5): audit the single-fish money path too —
		-- RequestSellFish logs every sale, but SellFish (carried AND aquarium sources)
		-- previously wrote coins with no audit entry, and a stored-fish sale can
		-- liquidate a high-value Epic/Legendary fish.
		if auditLog then
			auditLog.logSell(player, 1, payout)
		end

		notify(player, string.format("Sold %s %s for $%d!", fish.Rarity, fish.SpeciesId, payout), Color3.fromRGB(130, 255, 130))
		stateSync.push(session)
		-- TASK 12.2 (thj.2): persist on single-fish sell (not just autosave).
		-- Spawned so the handler returns immediately; coalesced by
		-- DataManager.save's isSaving guard.
		task.spawn(function()
			dataManager.save(player)
		end)

		-- QUEST GAP FIX (fresh-eyes fellow-agent review): bulk RequestSellFish in
		-- AquariumService fires onFishSold, but this single-fish path never did —
		-- so sell_value quests only progressed on RequestSellFish. Fire the same hook
		-- here (value=payout) so both paths progress quests consistently.
		if questService then
			questService.onFishSold(session, payout)
		end

		-- EPIC 11 (TASK 11.2): fish_sold + first_sale (ONCE, gated).
		-- CORRECTED (fresh-eyes): previously first_sale fired every sale.
		-- Tracks the monetization loop — how often players convert catches
		-- to coins.
		if analytics then
			analytics.track(player, "fish_sold", {
				species_id = fish.SpeciesId,
				rarity = fish.Rarity,
				payout = payout,
				source = soldFromStored and "aquarium" or "carried",
			})
			if analytics.isFirst(player.UserId, "first_sale") then
				analytics.track(player, "first_sale", { payout = payout })
			end
		end

		-- Refresh the aquarium visual after a stored-fish sale (no-op for
		-- carried sales, which never changed the aquarium contents).
		local dock = dockManager.getDock(player)
		if dock then
			dockManager.updateAquariumVisual(dock, session, stateSync.getCapacity(session))
		end

		return { ok = true, payout = payout, speciesId = fish.SpeciesId }
	end

	-- ════════════════════════════════════════════════════════════════════════
	-- Store a single fish from carried to aquarium (PRD INV-04)
	-- ════════════════════════════════════════════════════════════════════════
	remotes.StoreSingleFish.OnServerInvoke = function(player, instanceId)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "store")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		if type(instanceId) ~= "string" or #instanceId == 0 then
			return { ok = false, reason = "bad_id" }
		end

		-- Must be in carried (not already stored)
		local idx = findFishIndex(session.carried, instanceId)
		if not idx then
			return { ok = false, reason = "not_in_carried" }
		end

		local storedFish = session.profile.Aquarium.StoredFish
		local capacity = stateSync.getCapacity(session)
		if #storedFish >= capacity then
			notify(player, "Your aquarium is full! Sell some fish first.", Color3.fromRGB(255, 170, 80))
			return { ok = false, reason = "aquarium_full" }
		end

		local fish = table.remove(session.carried, idx)
		if not FishInstance.validate(fish) then
			warn("[HarborHeist] Invalid fish record stored: " .. tostring(instanceId))
			return { ok = false, reason = "invalid_fish" }
		end

		table.insert(storedFish, fish)
		-- TASK 14.15 (wqw.15): a fish was added to StoredFish -> invalidate the
		-- cached incomePerSec so the next push/income-tick recomputes it.
		-- (NOTE: SellFish's fromAquarium=true path also removes a stored fish
		-- and invalidates via its own `if soldFromStored` block above; only the
		-- carried SellFish path doesn't touch StoredFish/affect incomePerSec.)
		stateSync.invalidateIncomeCache(session)
		notify(player, string.format("Stored %s %s. It now earns you cash!", fish.Rarity, fish.SpeciesId), Color3.fromRGB(120, 220, 255))
		stateSync.push(session)
		-- TASK 12.2 (thj.2): persist on single-fish store (not just autosave).
		-- Spawned so the handler returns immediately; coalesced by
		-- DataManager.save's isSaving guard.
		task.spawn(function()
			dataManager.save(player)
		end)

		-- QUEST GAP FIX (fresh-eyes fellow-agent review): the bulk RequestStoreFish path
		-- in AquariumService fires onFishStored, but this single-fish path never
		-- did — so store_count quests only progressed on bulk stores. Fire the
		-- same hook here (count=1) so both paths progress quests consistently.
		if questService then
			questService.onFishStored(session, 1)
		end

		-- EPIC 9 (TASK 9.1): flip the first-store onboarding flag. Idempotent.
		if onboarding then
			onboarding.mark(session, "HasStoredFirstFish")
		end

		-- EPIC 11 (TASK 11.2): fish_stored + first_store (ONCE, gated).
		-- CORRECTED (fresh-eyes): previously first_store fired every store.
		-- The store action is the conversion into the income-generation
		-- economy.
		if analytics then
			analytics.track(player, "fish_stored", {
				species_id = fish.SpeciesId,
				rarity = fish.Rarity,
				aquarium_count = #storedFish,
			})
			if analytics.isFirst(player.UserId, "first_store") then
				analytics.track(player, "first_store", { species_id = fish.SpeciesId })
			end
		end

		-- Update aquarium visual
		local dock = dockManager.getDock(player)
		if dock then
			dockManager.updateAquariumVisual(dock, session, capacity)
		end

		return { ok = true, speciesId = fish.SpeciesId }
	end
end

return FishInventoryService
