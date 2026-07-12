local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local AquariumService = {}

local rng = Random.new()

function AquariumService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService

	local function refreshVisual(session)
		local dock = dockManager.getDock(session.player)
		if dock then
			dockManager.updateAquariumVisual(dock, session, stateSync.getCapacity(session))
		end
	end
	AquariumService.refreshVisual = function(session)
		refreshVisual(session)
	end

	remotes.StoreFish.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local capacity = stateSync.getCapacity(session)
		local stored = 0
		while #session.carried > 0 and #session.liveWell < capacity do
			table.insert(session.liveWell, table.remove(session.carried))
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
		if stored > 0 and questService then
			questService.onFishStored(session, stored)
		end
		return { ok = stored > 0, stored = stored }
	end

	remotes.SellAll.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local payout = 0
		for _, rarityIndex in ipairs(session.liveWell) do
			payout += GameConfig.Rarities[rarityIndex].value
		end
		for _, rarityIndex in ipairs(session.carried) do
			payout += GameConfig.Rarities[rarityIndex].value
		end
		if payout <= 0 then
			remotes.notify(player, "No fish to sell!", Color3.fromRGB(255, 170, 80))
			return { ok = false }
		end
		session.liveWell = {}
		session.carried = {}
		session.cash += payout
		remotes.notify(player, string.format("Sold all fish for $%d!", payout), Color3.fromRGB(130, 255, 130))
		refreshVisual(session)
		stateSync.push(session)
		if questService then
			questService.onFishSold(session, payout)
		end
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
		local lockDuration = GameConfig.Aquarium.lockDuration
		local lockCooldown = GameConfig.Aquarium.lockCooldown
		if session.lockLevel and session.lockLevel > 0 then
			local upgrade = GameConfig.Upgrades.Lock[session.lockLevel]
			if upgrade then
				lockDuration = upgrade.lockDuration
				lockCooldown = upgrade.lockCooldown
			end
		end
		session.lockedUntil = now + lockDuration
		session.lockCooldownUntil = session.lockedUntil + lockCooldown
		remotes.notify(
			player,
			string.format("Aquarium locked for %ds. Thieves can't touch it!", lockDuration),
			Color3.fromRGB(130, 255, 130)
		)
		refreshVisual(session)
		stateSync.push(session)
		task.delay(lockDuration, function()
			if session.player and session.player.Parent then
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
	local questService = deps.questService

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

	if #victimSession.liveWell == 0 then
		remotes.notify(attacker, "This aquarium is empty. Nothing to steal!", Color3.fromRGB(255, 170, 80))
		return
	end

	attackerSession.stealCooldownUntil = now + GameConfig.Aquarium.stealCooldown

	local alarmLevel = victimSession.alarmLevel or 0
	local alarmConfig = alarmLevel > 0 and GameConfig.Upgrades.Alarm[alarmLevel] or nil
	if alarmConfig and alarmConfig.notifyChance >= rng:NextNumber() then
		remotes.notify(
			victim,
			string.format("ALARM! %s is trying to steal from your aquarium!", attacker.DisplayName),
			Color3.fromRGB(255, 150, 100)
		)
	end

	if rng:NextNumber() <= GameConfig.Aquarium.stealChance then
		local stolenIndex = rng:NextInteger(1, #victimSession.liveWell)
		local rarityIndex = table.remove(victimSession.liveWell, stolenIndex)
		
		-- SECURITY: Validate rarityIndex is a valid rarity before using it
		if not (type(rarityIndex) == "number" and rarityIndex >= 1 and rarityIndex <= #GameConfig.Rarities) then
			warn("[HarborHeist] Invalid rarityIndex stolen: " .. tostring(rarityIndex))
			return
		end
		
		local rarity = GameConfig.Rarities[rarityIndex]

		local capacity = stateSync.getCapacity(attackerSession)
		-- SECURITY: Double-check capacity before insertion
		if #attackerSession.liveWell < capacity then
			table.insert(attackerSession.liveWell, rarityIndex)
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
			attackerSession.cash += rarity.value
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
		if questService then
			questService.onStealAttempt(attackerSession, true)
		end
	else
		remotes.notify(attacker, "Heist failed! The fish slipped away...", Color3.fromRGB(255, 120, 120))
		remotes.notify(
			victim,
			string.format("%s tried to steal from your aquarium and failed!", attacker.DisplayName),
			Color3.fromRGB(255, 200, 100)
		)
		if alarmConfig and alarmConfig.stunDuration > 0 then
			attackerSession.stunUntil = now + alarmConfig.stunDuration
			remotes.notify(
				attacker,
				string.format("ALARM tripped! You're stunned for %ds.", alarmConfig.stunDuration),
				Color3.fromRGB(255, 100, 100)
			)
			task.delay(alarmConfig.stunDuration, function()
				if attackerSession.player and attackerSession.player.Parent then
					stateSync.push(attackerSession)
				end
			end)
		end
		stateSync.push(attackerSession)
		if questService then
			questService.onStealAttempt(attackerSession, false)
		end
	end
end

function AquariumService.startIncomeLoop(deps)
	local dataManager = deps.dataManager
	local stateSync = deps.stateSync
	local questService = deps.questService
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			for _, session in pairs(dataManager.allSessions()) do
				local income = stateSync.incomePerSec(session) * GameConfig.IncomeTickSeconds
				if income > 0 then
					session.cash += income
					if questService then
						questService.onIncomeEarned(session, income)
					end
				end
				stateSync.push(session)
			end
		end
	end)
end

return AquariumService
