--[[
	FishInventoryService.lua — Server-side fish inventory management.

	Handles per-fish operations: sell individual fish, store individual fish
	from carried to aquarium. All operations are server-validated (PRD INV-06).
	Prevents duplication, negative quantities, over-capacity transfers (INV-05).

	The bulk "SellAll" and "StoreFish" (store-all) remain in AquariumService
	as convenience wrappers. This service adds the granular per-fish API.
]]

local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)

local FishInventoryService = {}

function FishInventoryService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync
	local dockManager = deps.dockManager

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
	-- Sell a single fish from carried inventory (PRD INV-03)
	-- ════════════════════════════════════════════════════════════════════════
	remotes.SellFish.OnServerInvoke = function(player, instanceId)
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		if type(instanceId) ~= "string" or #instanceId == 0 then
			return { ok = false, reason = "bad_id" }
		end

		-- Find in carried first
		local idx = findFishIndex(session.carried, instanceId)
		local fish = nil
		if idx then
			fish = table.remove(session.carried, idx)
		else
			-- Also allow selling from aquarium (stored fish)
			local storedFish = session.profile.Aquarium.StoredFish
			idx = findFishIndex(storedFish, instanceId)
			if idx then
				fish = table.remove(storedFish, idx)
			end
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
		session.profile.Coins = session.profile.Coins + payout
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + payout

		notify(player, string.format("Sold %s %s for $%d!", fish.Rarity, fish.SpeciesId, payout), Color3.fromRGB(130, 255, 130))
		stateSync.push(session)

		-- Update aquarium visual if fish was stored
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
		notify(player, string.format("Stored %s %s. It now earns you cash!", fish.Rarity, fish.SpeciesId), Color3.fromRGB(120, 220, 255))
		stateSync.push(session)

		-- Update aquarium visual
		local dock = dockManager.getDock(player)
		if dock then
			dockManager.updateAquariumVisual(dock, session, capacity)
		end

		return { ok = true, speciesId = fish.SpeciesId }
	end
end

return FishInventoryService
