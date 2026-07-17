local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local AquariumService = {}

local rng = Random.new()

function AquariumService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync

	local function refreshVisual(session)
		local dock = dockManager.getDock(session.player)
		if dock then
			dockManager.updateAquariumVisual(dock, session, stateSync.getCapacity(session))
		end
	end

	remotes.StoreFish.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local storedFish = session.profile.Aquarium.StoredFish
		local capacity = stateSync.getCapacity(session)
		local stored = 0
		while #session.carried > 0 and #storedFish < capacity do
			table.insert(storedFish, table.remove(session.carried))
			stored += 1
		end
		if stored == 0 then
			if #session.carried == 0 then
				remotes.notify(player, "You have no fish to store. Go fish!", Color3.fromRGB(255, 170, 80))
			else
				remotes.notify(player, "Your aquarium is full! Sell some fish.", Color3.fromRGB(255, 170, 80))
			end
		else
			remotes.notify(
				player,
				string.format("Stored %d fish. They now earn you cash every second!", stored),
				Color3.fromRGB(120, 220, 255)
			)
		end
		refreshVisual(session)
		stateSync.push(session)
		return { ok = stored > 0, stored = stored }
	end

	remotes.SellAll.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local storedFish = session.profile.Aquarium.StoredFish
		local payout = 0
		for _, rarityIndex in ipairs(storedFish) do
			payout += GameConfig.Rarities[rarityIndex].value
		end
		for _, rarityIndex in ipairs(session.carried) do
			payout += GameConfig.Rarities[rarityIndex].value
		end
		if payout <= 0 then
			remotes.notify(player, "No fish to sell!", Color3.fromRGB(255, 170, 80))
			return { ok = false }
		end
		-- Clear the table in-place so the profile reference stays valid
		for i = #storedFish, 1, -1 do
			storedFish[i] = nil
		end
		session.carried = {}
		session.profile.Coins = session.profile.Coins + payout
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + payout
		remotes.notify(player, string.format("Sold all fish for $%d!", payout), Color3.fromRGB(130, 255, 130))
		refreshVisual(session)
		stateSync.push(session)
		return { ok = true, payout = payout }
	end

	remotes.LockAquarium.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local now = os.clock()
		if session.lockedUntil > now then
			return { ok = false, reason = "already_locked" }
		end
		if session.lockCooldownUntil > now then
			remotes.notify(
				player,
				string.format("Lock recharging... %ds left.", math.ceil(session.lockCooldownUntil - now)),
				Color3.fromRGB(255, 170, 80)
			)
			return { ok = false, reason = "cooldown" }
		end
		session.lockedUntil = now + GameConfig.Aquarium.lockDuration
		session.lockCooldownUntil = session.lockedUntil + GameConfig.Aquarium.lockCooldown
		-- Also persist as epoch timestamps (TASK 1.1: structured profile)
		session.profile.Aquarium.LockUntilTimestamp = os.time() + GameConfig.Aquarium.lockDuration
		session.profile.Aquarium.LockCooldownUntilTimestamp = os.time() + GameConfig.Aquarium.lockDuration + GameConfig.Aquarium.lockCooldown
		remotes.notify(
			player,
			string.format("Aquarium locked for %ds. Thieves can't touch it!", GameConfig.Aquarium.lockDuration),
			Color3.fromRGB(130, 255, 130)
		)
		refreshVisual(session)
		stateSync.push(session)
		task.delay(GameConfig.Aquarium.lockDuration, function()
			if session.player.Parent then
				refreshVisual(session)
				stateSync.push(session)
				remotes.notify(session.player, "Your aquarium lock expired. Watch out for thieves!", Color3.fromRGB(255, 170, 80))
			end
		end)
		return { ok = true }
	end

	AquariumService.refreshVisual = refreshVisual
end

function AquariumService.handleSteal(deps, attacker, dock)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync

	local victim = dock.owner
	-- SECURITY: Re-verify victim ownership and that it's not attacker
	if not victim or victim == attacker or dock.owner ~= victim then
		return
	end
	local attackerSession = dataManager.get(attacker)
	local victimSession = dataManager.get(victim)
	-- SECURITY: Verify both players are loaded - prevent nil dereferences
	if not attackerSession or not victimSession then
		return
	end

	-- SECURITY: Verify player still exists and is in game
	if not attacker.Parent or not victim.Parent then
		return
	end

	local root = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	-- SECURITY: Use MaxActivationDistance from prompt (10 studs) not magic number 15
	-- Add 2 studs buffer for network latency tolerance
	if not root or (root.Position - dock.aquarium.PrimaryPart.Position).Magnitude > 12 then
		return
	end

	local now = os.clock()
	if attackerSession.stealCooldownUntil > now then
		remotes.notify(
			attacker,
			string.format("Catch your breath! You can steal again in %ds.", math.ceil(attackerSession.stealCooldownUntil - now)),
			Color3.fromRGB(255, 170, 80)
		)
		return
	end

	if victimSession.lockedUntil > now then
		remotes.notify(attacker, "This aquarium is LOCKED. Come back later...", Color3.fromRGB(255, 120, 120))
		return
	end

	if #victimSession.profile.Aquarium.StoredFish == 0 then
		remotes.notify(attacker, "This aquarium is empty. Nothing to steal!", Color3.fromRGB(255, 170, 80))
		return
	end

	attackerSession.stealCooldownUntil = now + GameConfig.Aquarium.stealCooldown
	attackerSession.profile.PvP.StealCooldownUntilTimestamp = os.time() + GameConfig.Aquarium.stealCooldown

	if rng:NextNumber() <= GameConfig.Aquarium.stealChance then
		local victimFish = victimSession.profile.Aquarium.StoredFish
		local stolenIndex = rng:NextInteger(1, #victimFish)
		local rarityIndex = table.remove(victimFish, stolenIndex)
		
		-- SECURITY: Validate rarityIndex is a valid rarity before using it
		if not (type(rarityIndex) == "number" and rarityIndex >= 1 and rarityIndex <= #GameConfig.Rarities) then
			warn("[HarborHeist] Invalid rarityIndex stolen: " .. tostring(rarityIndex))
			return
		end
		
		local rarity = GameConfig.Rarities[rarityIndex]

		local capacity = stateSync.getCapacity(attackerSession)
		local attackerFish = attackerSession.profile.Aquarium.StoredFish
		-- SECURITY: Double-check capacity before insertion
		if #attackerFish < capacity then
			table.insert(attackerFish, rarityIndex)
			remotes.notify(
				attacker,
				string.format("Heist success! You stole a %s fish from %s!", rarity.name, victim.DisplayName),
				rarity.color
			)
		else
			-- SECURITY: Validate rarity value before adding to cash
			if type(rarity.value) ~= "number" or rarity.value < 0 then
				warn("[HarborHeist] Invalid rarity value for index " .. rarityIndex)
				return
			end
			attackerSession.profile.Coins = attackerSession.profile.Coins + rarity.value
			remotes.notify(
				attacker,
				string.format("Heist success! Fenced a %s fish for $%d!", rarity.name, rarity.value),
				rarity.color
			)
		end
		remotes.notify(
			victim,
			string.format("%s stole a %s fish from your aquarium! Lock it up!", attacker.DisplayName, rarity.name),
			Color3.fromRGB(255, 100, 100)
		)
		AquariumService.refreshVisual(victimSession)
		local attackerDock = dockManager.getDock(attacker)
		if attackerDock then
			dockManager.updateAquariumVisual(attackerDock, attackerSession, capacity)
		end
		stateSync.push(attackerSession)
		stateSync.push(victimSession)
	else
		remotes.notify(attacker, "Heist failed! The fish slipped away...", Color3.fromRGB(255, 120, 120))
		remotes.notify(
			victim,
			string.format("%s tried to steal from your aquarium and failed!", attacker.DisplayName),
			Color3.fromRGB(255, 200, 100)
		)
		stateSync.push(attackerSession)
	end
end

function AquariumService.startIncomeLoop(deps)
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			for _, session in pairs(dataManager.allSessions()) do
				local income = stateSync.incomePerSec(session) * GameConfig.IncomeTickSeconds
				if income > 0 then
					session.profile.Coins = session.profile.Coins + income
					session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + income
				end
				stateSync.push(session)
			end
		end
	end)
end

return AquariumService
