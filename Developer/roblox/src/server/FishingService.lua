local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)

local FishingService = {}

local rng = Random.new()

function FishingService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync

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
		-- SECURITY: Verify character exists before checking fishing zone
		local inZone, zoneId = false, nil
		if player.Character then
			inZone, zoneId = dockManager.isInFishingZone(dock, player.Character)
		end
		if not inZone then
			remotes.notify(player, "Stand in a fishing zone at your dock!", Color3.fromRGB(255, 170, 80))
			return
		end
		-- TASK 2.2: Enforce rod-level zone access
		local ZoneDefinitions = require(game:GetService("ReplicatedStorage").Shared.ZoneDefinitions)
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
		local castTime = rod.castTime + rng:NextNumber(0, 2)
		remotes.CastState:FireClient(player, true, castTime)

		task.delay(castTime, function()
			-- SECURITY: Verify player still exists before processing catch
			if not session.player.Parent or not player.Parent then
				session.casting = false
				return
			end
			session.casting = false
			remotes.CastState:FireClient(player, false, 0)

			-- SECURITY: Re-check fishing zone and carried capacity before adding fish
			if not player.Character or not dockManager.isInFishingZone(dock, player.Character) then
				remotes.notify(player, "You left the fishing zone... the fish got away!", Color3.fromRGB(255, 120, 120))
				return
			end
			
			if #session.carried >= GameConfig.MaxCarried then
				remotes.notify(player, "Your hands are full! Store or sell your fish first.", Color3.fromRGB(255, 170, 80))
				return
			end

			local luck = rod.luck + GameConfig.Baits[session.profile.Equipment.EquippedBaitLevel].luck
			local rarityIndex = GameConfig.rollRarity(luck, rng)
			-- SECURITY: Validate rarity exists before adding to carried
			if not (type(rarityIndex) == "number" and GameConfig.Rarities[rarityIndex]) then
				warn("[HarborHeist] Invalid rarityIndex caught: " .. tostring(rarityIndex))
				return
			end
			-- Create FishInstance record (TASK 1.2)
			local fish = FishInstance.fromRarityIndex(rarityIndex)
			table.insert(session.carried, fish)

			local rarity = GameConfig.Rarities[rarityIndex]
			remotes.notify(
				player,
				string.format("You caught a %s %s! (worth $%d)", rarity.name, fish.SpeciesId, fish.BaseSellValue),
				rarity.color
			)
			stateSync.push(session)
		end)
	end)
end

return FishingService
