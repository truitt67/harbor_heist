local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)
local FishDefinitions = require(game:GetService("ReplicatedStorage").Shared.FishDefinitions)
local ZoneDefinitions = require(game:GetService("ReplicatedStorage").Shared.ZoneDefinitions)

local FishingService = {}

local rng = Random.new()

-- Bite timing configuration (seconds)
local BITE_MIN_DELAY = 2.0
local BITE_MAX_DELAY = 6.0
local BITE_WINDOW_SECONDS = 3.0 -- how long the player has to respond after bite

function FishingService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync

	-- Track active bite state per player (not persisted)
	local activeBites = {} -- player -> { zoneId, rod, baitLevel, biteTime }

	remotes.Cast.OnServerEvent:Connect(function(player)
		local session = dataManager.get(player)
		-- SECURITY: Verify player session exists and player is still in game
		if not session or not player.Parent then
			return
		end
		if session.casting then
			return
		end
		-- SECURITY: Double-check carried array is within bounds
		if #session.carried >= GameConfig.MaxCarried then
			remotes.notify(player, "Your hands are full! Store or sell your fish first.", Color3.fromRGB(255, 170, 80))
			return
		end
		local dock = dockManager.getDock(player)
		if not dock then
			return
		end
		-- SECURITY: Verify character exists and is in a fishing zone
		local inZone, zoneId = false, nil
		if player.Character then
			inZone, zoneId = dockManager.isInFishingZone(dock, player.Character)
		end
		if not inZone then
			remotes.notify(player, "Stand in a fishing zone at your dock!", Color3.fromRGB(255, 170, 80))
			return
		end
		-- TASK 2.2: Enforce rod-level zone access
		if not ZoneDefinitions.canAccess(zoneId, session.profile.Equipment.EquippedRodLevel) then
			local zone = ZoneDefinitions.get(zoneId)
			remotes.notify(player, string.format("You need a better rod to fish in %s!", zone.DisplayName), Color3.fromRGB(255, 170, 80))
			return
		end

		session.casting = true
		local rod = GameConfig.Rods[session.profile.Equipment.EquippedRodLevel]
		if not rod then
			session.casting = false
			return
		end

		-- TASK 3.1: Server-side bite roll
		-- Bite delay is randomized; better rods = shorter average wait
		local baseDelay = rod.castTime
		local biteDelay = baseDelay + rng:NextNumber(BITE_MIN_DELAY, BITE_MAX_DELAY)
		remotes.CastState:FireClient(player, true, biteDelay)

		-- Store bite state for later validation
		activeBites[player] = {
			zoneId = zoneId,
			rodLevel = session.profile.Equipment.EquippedRodLevel,
			baitLevel = session.profile.Equipment.EquippedBaitLevel,
			biteTime = os.clock() + biteDelay,
		}

		-- Fire the bite event to the client when the bite occurs
		task.delay(biteDelay, function()
			if not player.Parent or not session.player.Parent then
				session.casting = false
				activeBites[player] = nil
				return
			end
			session.casting = false
			remotes.CastState:FireClient(player, false, 0)

			-- Re-verify zone and capacity before offering the bite
			local stillInZone, currentZoneId = false, nil
			if player.Character then
				stillInZone, currentZoneId = dockManager.isInFishingZone(dock, player.Character)
			end
			if not stillInZone or currentZoneId ~= zoneId then
				remotes.notify(player, "You left the fishing zone... the fish got away!", Color3.fromRGB(255, 120, 120))
				activeBites[player] = nil
				return
			end
			if #session.carried >= GameConfig.MaxCarried then
				remotes.notify(player, "Your hands are full! Store or sell your fish first.", Color3.fromRGB(255, 170, 80))
				activeBites[player] = nil
				return
			end

			-- Fire bite event to client (triggers the timing minigame)
			local biteData = activeBites[player]
			if biteData then
				biteData.biteTime = os.clock() -- reset to actual bite moment
				remotes.BiteEvent:FireClient(player, zoneId, BITE_WINDOW_SECONDS)
			end
		end)
	end)

	-- TASK 3.3: Client submits catch input after the minigame
	remotes.SubmitCatchInput.OnServerInvoke = function(player, timingResult)
		local session = dataManager.get(player)
		if not session or not player.Parent then
			return { ok = false, reason = "no_session" }
		end

		local biteData = activeBites[player]
		if not biteData then
			return { ok = false, reason = "no_active_bite" }
		end

		-- Validate timing: player must respond within the bite window
		local elapsed = os.clock() - biteData.biteTime
		if elapsed > BITE_WINDOW_SECONDS then
			activeBites[player] = nil
			remotes.notify(player, "Too slow! The fish got away...", Color3.fromRGB(255, 120, 120))
			return { ok = false, reason = "too_slow" }
		end

		-- Validate the timing result is plausible
		if type(timingResult) ~= "table" or type(timingResult.hit) ~= "boolean" then
			return { ok = false, reason = "bad_input" }
		end

		-- Clear the bite state
		activeBites[player] = nil

		if not timingResult.hit then
			remotes.notify(player, "The fish slipped away...", Color3.fromRGB(255, 120, 120))
			return { ok = false, reason = "missed" }
		end

		-- TASK 3.4: Species-based catch resolution
		local zoneId = biteData.zoneId
		local rod = GameConfig.Rods[biteData.rodLevel]
		local bait = GameConfig.Baits[biteData.baitLevel]
		if not rod or not bait then
			return { ok = false, reason = "invalid_gear" }
		end

		-- Roll species from the zone's fish table, weighted by CatchWeight,
		-- modified by rod+bait luck
		local luck = rod.luck + bait.luck
		local speciesDef = FishDefinitions.getRandomInZone(zoneId, rng)
		if not speciesDef then
			warn("[HarborHeist] No species found in zone: " .. zoneId)
			return { ok = false, reason = "no_species" }
		end

		-- Create FishInstance record
		local fish = FishInstance.new(speciesDef.SpeciesId, zoneId)
		table.insert(session.carried, fish)

		-- Find rarity color for notification
		local rarityColor = Color3.fromRGB(255, 255, 255)
		for _, r in ipairs(GameConfig.Rarities) do
			if r.name == fish.Rarity then
				rarityColor = r.color
				break
			end
		end

		remotes.notify(
			player,
			string.format("You caught a %s %s! (worth $%d)", fish.Rarity, fish.SpeciesId, fish.BaseSellValue),
			rarityColor
		)
		stateSync.push(session)
		return { ok = true, speciesId = fish.SpeciesId, rarity = fish.Rarity, value = fish.BaseSellValue }
	end
end

return FishingService
