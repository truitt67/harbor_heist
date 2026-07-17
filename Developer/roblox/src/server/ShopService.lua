local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local PlayerProfile = require(game:GetService("ReplicatedStorage").Shared.PlayerProfile)

local ShopService = {}

local KIND_CATALOGS = {
	rod = { catalog = "Rods", field = "rodLevel" },
	bait = { catalog = "Baits", field = "baitLevel" },
	capacity = { catalog = "Upgrades.Capacity", field = "capacityLevel" },
	lock = { catalog = "Upgrades.Lock", field = "lockLevel" },
	alarm = { catalog = "Upgrades.Alarm", field = "alarmLevel" },
}

local function getCatalog(kind)
	local entry = KIND_CATALOGS[kind]
	if not entry then
		return nil, nil
	end
	if entry.catalog == "Upgrades.Capacity" then
		return GameConfig.Upgrades.Capacity, entry.field
	elseif entry.catalog == "Upgrades.Lock" then
		return GameConfig.Upgrades.Lock, entry.field
	elseif entry.catalog == "Upgrades.Alarm" then
		return GameConfig.Upgrades.Alarm, entry.field
	elseif entry.catalog == "Rods" then
		return GameConfig.Rods, entry.field
	elseif entry.catalog == "Baits" then
		return GameConfig.Baits, entry.field
	end
	return nil, nil
end

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

		-- Resolve catalog and current level using the local profile schema.
		-- Supports rod, bait (from Equipment) and upgrades that the local
		-- track stores as profile.Aquarium.UpgradeLevel / profile.Dock.UpgradeLevel.
		local catalog, currentLevel
		if kind == "rod" then
			catalog = GameConfig.Rods
			currentLevel = session.profile.Equipment.EquippedRodLevel
		elseif kind == "bait" then
			catalog = GameConfig.Baits
			currentLevel = session.profile.Equipment.EquippedBaitLevel
		elseif kind == "aquarium" then
			-- TASK 2.5: aquarium capacity upgrade
			catalog = GameConfig.AquariumUpgradeTiers
			currentLevel = session.profile.Aquarium.UpgradeLevel or 1
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

		-- Deduct cost and apply the upgrade to the right profile field.
		-- N5: clampCoins on purchase too (defense in depth).
		session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins - item.cost)
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
		elseif kind == "bait" then
			session.profile.Equipment.EquippedBaitLevel = level
		elseif kind == "aquarium" then
			-- TASK 2.5: apply upgrade level + recompute capacity
			session.profile.Aquarium.UpgradeLevel = level
			session.profile.Aquarium.Capacity = catalog[level].capacity or catalog[level].Capacity or session.profile.Aquarium.Capacity
		end
		remotes.notify(
			player,
			string.format("Purchased %s!", item.name),
			Color3.fromRGB(130, 255, 130)
		)
		stateSync.push(session)
		return { ok = true }
	end
end

return ShopService
