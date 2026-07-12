local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local FishingService = {}

local rng = Random.new()

function FishingService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync

	remotes.Cast.OnServerEvent:Connect(function(player)
		local session = dataManager.get(player)
		if not session or session.casting then
			return
		end
		if #session.carried >= GameConfig.MaxCarried then
			remotes.notify(player, "Your hands are full! Store or sell your fish first.", Color3.fromRGB(255, 170, 80))
			return
		end
		local dock = dockManager.getDock(player)
		if not dock then
			return
		end
		if not dockManager.isInFishingZone(dock, player.Character) then
			remotes.notify(player, "Stand in the glowing Fishing Zone at the end of your dock!", Color3.fromRGB(255, 170, 80))
			return
		end

		session.casting = true
		local rod = GameConfig.Rods[session.rodLevel]
		local castTime = rod.castTime + rng:NextNumber(0, 2)
		remotes.CastState:FireClient(player, true, castTime)

		task.delay(castTime, function()
			if not session.player.Parent then
				return
			end
			session.casting = false
			remotes.CastState:FireClient(player, false, 0)

			if not dockManager.isInFishingZone(dock, player.Character) then
				remotes.notify(player, "You left the fishing zone... the fish got away!", Color3.fromRGB(255, 120, 120))
				return
			end

			local luck = rod.luck + GameConfig.Baits[session.baitLevel].luck
			local rarityIndex = GameConfig.rollRarity(luck, rng)
			local rarity = GameConfig.Rarities[rarityIndex]
			table.insert(session.carried, rarityIndex)

			remotes.notify(
				player,
				string.format("You caught a %s fish! (worth $%d)", rarity.name, rarity.value),
				rarity.color
			)
			stateSync.push(session)
		end)
	end)
end

return FishingService
