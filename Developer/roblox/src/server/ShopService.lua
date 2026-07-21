local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local PlayerProfile = require(game:GetService("ReplicatedStorage").Shared.PlayerProfile)

local ShopService = {}

function ShopService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync
	local antiExploit = deps.antiExploit -- EPIC 10
	local analytics = deps.analytics -- EPIC 11

	remotes.BuyItem.OnServerInvoke = function(player, kind, level)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "buy")
			if not ok then return { ok = false, reason = reason } end
		end
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		if type(kind) ~= "string" or type(level) ~= "number" then
			if antiExploit then
				antiExploit.logSuspicious(player, "buy", "Invalid args: kind=" .. tostring(kind) .. " level=" .. tostring(level))
			end
			return { ok = false, reason = "bad_args" }
		end
		level = math.floor(level)

		-- Resolve catalog and current level using the local profile schema.
		-- Supports rod, bait (from Equipment) and upgrades that the local
		-- track stores as profile.Aquarium.UpgradeLevel / profile.Dock.UpgradeLevel.
		-- N6: lock and alarm were missing from this dispatch, so buying them
		-- returned bad_kind even though the shop UI listed them for sale.
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
		elseif kind == "lock" then
			catalog = GameConfig.Upgrades.Lock
			currentLevel = session.profile.Aquarium.LockLevel or 0
		elseif kind == "alarm" then
			catalog = GameConfig.Upgrades.Alarm
			currentLevel = session.profile.Aquarium.AlarmLevel or 0
		elseif kind == "dock" then
			-- TASK 17.2 (EPIC 17): dock upgrade tiers. Distinct from the aquarium
			-- track — dock upgrades multiply income (1.0→1.6) without changing
			-- capacity, giving a second parallel investment path.
			catalog = GameConfig.DockUpgradeTiers
			currentLevel = session.profile.Dock.UpgradeLevel or 1
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
		elseif kind == "lock" then
			session.profile.Aquarium.LockLevel = level
		elseif kind == "alarm" then
			session.profile.Aquarium.AlarmLevel = level
		elseif kind == "dock" then
			session.profile.Dock.UpgradeLevel = level
		end
		remotes.notify(
			player,
			string.format("Purchased %s!", item.name),
			Color3.fromRGB(130, 255, 130)
		)
		stateSync.push(session)
		-- EPIC 11 (TASK 11.2): upgrade_purchased + first_upgrade (ONCE, gated).
		-- CORRECTED (fresh-eyes): previously first_upgrade fired every
		-- purchase. kind + level + price feed the monetization funnel.
		-- CORRECTED (round-3 fellow-agent review): `price = price` referenced
		-- an undeclared local and silently sent nil (the analytics pcall never
		-- complained about a missing key, so the funnel lost the price
		-- dimension on every purchase). Use item.cost — the authoritative
		-- price the server just charged.
		if analytics then
			analytics.track(player, "upgrade_purchased", {
				kind = kind,
				level = level,
				price = item.cost,
			})
			if analytics.isFirst(player.UserId, "first_upgrade") then
				analytics.track(player, "first_upgrade", { kind = kind })
			end
		end
		return { ok = true }
	end
end

return ShopService
