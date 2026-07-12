local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

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

		local catalog, field = getCatalog(kind)
		if not catalog then
			return { ok = false, reason = "bad_kind" }
		end

		local currentLevel = session[field] or 0
		local item = catalog[level]
		if not item then
			return { ok = false, reason = "bad_level" }
		end
		if level ~= currentLevel + 1 then
			remotes.notify(player, "Buy upgrades in order, one tier at a time!", Color3.fromRGB(255, 170, 80))
			return { ok = false, reason = "wrong_tier" }
		end
		if math.floor(session.cash) < item.cost then
			remotes.notify(
				player,
				string.format("Not enough cash! %s costs $%d.", item.name, item.cost),
				Color3.fromRGB(255, 120, 120)
			)
			return { ok = false, reason = "poor" }
		end

		session.cash -= item.cost
		session[field] = level
		if kind == "rod" and deps.rodService then
			-- Refresh the held rod model so the new tier shows immediately.
			deps.rodService.equip(player, session)
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
