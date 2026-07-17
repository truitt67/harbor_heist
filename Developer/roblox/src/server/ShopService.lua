local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local ShopService = {}

function ShopService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync

	remotes.BuyItem.OnServerInvoke = function(player, kind, level)
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		if type(kind) ~= "string" or type(level) ~= "number" then
			return { ok = false, reason = "bad_args" }
		end
		level = math.floor(level)

		local catalog, currentLevel
		if kind == "rod" then
			catalog = GameConfig.Rods
			currentLevel = session.profile.Equipment.EquippedRodLevel
		elseif kind == "bait" then
			catalog = GameConfig.Baits
			currentLevel = session.profile.Equipment.EquippedBaitLevel
		else
			return { ok = false, reason = "bad_kind" }
		end

		local item = catalog[level]
		if not item then
			return { ok = false, reason = "bad_level" }
		end
		if level ~= currentLevel + 1 then
			remotes.notify(player, "Buy upgrades in order, one tier at a time!", Color3.fromRGB(255, 170, 80))
			return { ok = false, reason = "wrong_tier" }
		end
		if math.floor(session.profile.Coins) < item.cost then
			remotes.notify(
				player,
				string.format("Not enough cash! %s costs $%d.", item.name, item.cost),
				Color3.fromRGB(255, 120, 120)
			)
			return { ok = false, reason = "poor" }
		end

		session.profile.Coins = session.profile.Coins - item.cost
		if kind == "rod" then
			session.profile.Equipment.EquippedRodLevel = level
			-- Track ownership
			local owned = session.profile.Equipment.OwnedRodLevels
			local alreadyOwned = false
			for _, lvl in ipairs(owned) do
				if lvl == level then alreadyOwned = true break end
			end
			if not alreadyOwned then
				table.insert(owned, level)
			end
		else
			session.profile.Equipment.EquippedBaitLevel = level
		end
		remotes.notify(
			player,
			string.format("Purchased %s! Your luck just got better.", item.name),
			Color3.fromRGB(130, 255, 130)
		)
		stateSync.push(session)
		return { ok = true }
	end
end

return ShopService
