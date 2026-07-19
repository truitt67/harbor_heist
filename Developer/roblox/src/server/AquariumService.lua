local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local PlayerProfile = require(game:GetService("ReplicatedStorage").Shared.PlayerProfile)

local AquariumService = {}

local rng = Random.new()

function AquariumService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService
	local analytics = deps.analytics -- EPIC 11
	local onboarding = deps.onboarding -- EPIC 9

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
		local storedFish = session.profile.Aquarium.StoredFish
		local capacity = stateSync.getCapacity(session)
		local stored = 0
		while #session.carried > 0 and #storedFish < capacity do
			local fish = table.remove(session.carried)
			table.insert(storedFish, fish)
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
		-- EPIC 9 (TASK 9.1): flip the first-store onboarding flag (bulk path).
		if stored > 0 and onboarding then
			onboarding.mark(session, "HasStoredFirstFish")
		end
		return { ok = stored > 0, stored = stored }
	end

	remotes.ClaimIncome.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false, reason = "no_session" }
		end
		local unclaimed = session.profile.Aquarium.UnclaimedIncome
		if unclaimed <= 0 then
			return { ok = false, reason = "nothing_to_claim" }
		end
		-- Transfer unclaimed income to coins
		-- N5: route every coin write through clampCoins so the MAX_COINS cap
		-- cannot be overflowed by claiming a large pool near the ceiling.
		session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + unclaimed)
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + unclaimed
		session.profile.Aquarium.UnclaimedIncome = 0
		remotes.notify(player, string.format("Claimed $%d in aquarium income!", unclaimed), Color3.fromRGB(130, 255, 130))
		stateSync.push(session)
		-- EPIC 11 (TASK 11.2): income_claimed. Amount is the key field —
		-- dashboard uses it to track economy flow + claim frequency.
		if analytics then
			analytics.track(player, "income_claimed", { amount = unclaimed })
		end
		-- EPIC 9 (TASK 9.1): flip the first-claim onboarding flag. Idempotent.
		if onboarding then
			onboarding.mark(session, "HasClaimedIncome")
		end
		return { ok = true, amount = unclaimed }
	end

	remotes.SellAll.OnServerInvoke = function(player)
		local session = dataManager.get(player)
		if not session then
			return { ok = false }
		end
		local storedFish = session.profile.Aquarium.StoredFish
		local payout = 0
		-- Sell stored fish (FishInstance records)
		for _, fish in ipairs(storedFish) do
			payout += fish.BaseSellValue
		end
		-- Sell carried fish (FishInstance records)
		for _, fish in ipairs(session.carried) do
			payout += fish.BaseSellValue
		end
		if payout <= 0 then
			remotes.notify(player, "No fish to sell!", Color3.fromRGB(255, 170, 80))
			return { ok = false }
		end
		-- Clear the table in-place so the profile reference stays valid
		for i = #storedFish, 1, -1 do
			storedFish[i] = nil
		end
		-- Clear carried in-place too (never reassign the table reference)
		for i = #session.carried, 1, -1 do
			session.carried[i] = nil
		end
		-- N5: same clampCoins discipline on the sell path.
		session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + payout)
		session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + payout
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
		-- Upgrade-scaled lock duration. The base config is the fallback; each
		-- Lock tier in GameConfig.Upgrades.Lock overrides duration + cooldown.
		-- N7: previously this block was a stub (`if UpgradeLevel > 1 then` with
		-- an empty body), so buying Lock I/II/III changed nothing about the lock.
		local lockLevel = session.profile.Aquarium.LockLevel or 0
		local lockDuration = GameConfig.Aquarium.lockDuration
		local lockCooldown = GameConfig.Aquarium.lockCooldown
		if lockLevel > 0 and GameConfig.Upgrades.Lock[lockLevel] then
			local tier = GameConfig.Upgrades.Lock[lockLevel]
			lockDuration = tier.lockDuration
			lockCooldown = tier.lockCooldown
		end
		session.lockedUntil = now + lockDuration
		session.lockCooldownUntil = session.lockedUntil + lockCooldown
		-- Generation token: a re-lock invalidates any pending "lock expired"
		-- notification from a previous lock's delayed closure.
		session.lockGeneration = (session.lockGeneration or 0) + 1
		local generation = session.lockGeneration
		-- Also persist as epoch timestamps (TASK 1.1: structured profile)
		session.profile.Aquarium.LockUntilTimestamp = os.time() + lockDuration
		session.profile.Aquarium.LockCooldownUntilTimestamp = os.time() + lockDuration + lockCooldown
		remotes.notify(
			player,
			string.format("Aquarium locked for %ds. Thieves can't touch it!", lockDuration),
			Color3.fromRGB(130, 255, 130)
		)
		refreshVisual(session)
		stateSync.push(session)
		-- EPIC 11 (TASK 11.2): aquarium_locked. Tracks defensive engagement.
		if analytics then
			analytics.track(player, "aquarium_locked", {
				lock_level = lockLevel,
				duration = lockDuration,
			})
		end
		task.delay(lockDuration, function()
			if session.player.Parent and session.lockGeneration == generation then
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
	if not victim or victim == attacker then
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
	-- SECURITY: A stunned thief must not be able to keep stealing; the stun was
	-- previously only a client-side WalkSpeed tweak with no server enforcement.
	if (attackerSession.stunUntil or 0) > now then
		remotes.notify(
			attacker,
			string.format("You're stunned for %ds!", math.ceil(attackerSession.stunUntil - now)),
			Color3.fromRGB(255, 100, 100)
		)
		return
	end
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

	local victimFish = victimSession.profile.Aquarium.StoredFish
	-- Check eligibility BEFORE consuming the attacker's cooldown:
	-- an aquarium whose fish are all raid-protected must not burn it.
	local eligible = {}
	for i, fish in ipairs(victimFish) do
		if not fish.IsRaidProtected then
			table.insert(eligible, i)
		end
	end
	if #eligible == 0 then
		remotes.notify(attacker, "All fish here are protected! Nothing to steal.", Color3.fromRGB(255, 170, 80))
		return
	end

	attackerSession.stealCooldownUntil = now + GameConfig.Aquarium.stealCooldown
	attackerSession.profile.PvP.StealCooldownUntilTimestamp = os.time() + GameConfig.Aquarium.stealCooldown

	-- EPIC 11 (TASK 11.2): raid_attempted fires once per committed steal
	-- attempt (after eligibility passes + cooldown consumed). outcome is
	-- resolved below into raid_succeeded or raid_defended.
	if analytics then
		analytics.track(attacker, "raid_attempted", { victim_id = victim.UserId })
	end

	local alarmLevel = victimSession.profile.Aquarium.AlarmLevel or 0
	local alarmConfig = alarmLevel > 0 and GameConfig.Upgrades.Alarm[alarmLevel] or nil
	if alarmConfig and alarmConfig.notifyChance >= rng:NextNumber() then
		remotes.notify(
			victim,
			string.format("ALARM! %s is trying to steal from your aquarium!", attacker.DisplayName),
			Color3.fromRGB(255, 150, 100)
		)
	end

	if rng:NextNumber() <= GameConfig.Aquarium.stealChance then
		-- N15 (C6 TOCTOU): capture the fish REFERENCE at selection time, not
		-- just its index. The index can shift if the victim sells/stores a fish
		-- between the eligibility snapshot (line 241) and this remove. Re-find
		-- the reference in the live list and re-validate it's still
		-- non-raid-protected before removing — a stale index could otherwise
		-- hand the attacker a raid-protected Legendary (PVP-08 violation).
		local stolenIndex = eligible[rng:NextInteger(1, #eligible)]
		local targetFish = victimFish[stolenIndex]
		local liveIndex = nil
		if targetFish and not targetFish.IsRaidProtected then
			for i, fish in ipairs(victimFish) do
				if fish == targetFish and not fish.IsRaidProtected then
					liveIndex = i
					break
				end
			end
		end
		if not liveIndex then
			-- The target was removed or became protected between snapshot and
			-- resolution. Treat as a miss rather than stealing the wrong fish.
			remotes.notify(attacker, "The fish got away in the chaos!", Color3.fromRGB(255, 120, 120))
			stateSync.push(attackerSession)
			stateSync.push(victimSession)
			if questService then
				questService.onStealAttempt(attackerSession, false)
			end
			return
		end
		local stolenFish = table.remove(victimFish, liveIndex)
		
		local rarityName = stolenFish.Rarity
		local rarityColor = Color3.fromRGB(255, 255, 255)
		for _, r in ipairs(GameConfig.Rarities) do
			if r.name == rarityName then
				rarityColor = r.color
				break
			end
		end

		local capacity = stateSync.getCapacity(attackerSession)
		local attackerFish = attackerSession.profile.Aquarium.StoredFish
		-- SECURITY: Double-check capacity before insertion
		if #attackerFish < capacity then
			table.insert(attackerFish, stolenFish)
			remotes.notify(
				attacker,
				string.format("Heist success! You stole a %s %s from %s!", rarityName, stolenFish.SpeciesId, victim.DisplayName),
				rarityColor
			)
		else
			-- N12: route through clampCoins like every other coin grant. The raw
			-- write could overflow past MAX_COINS near the ceiling.
			attackerSession.profile.Coins = PlayerProfile.clampCoins(attackerSession.profile.Coins + stolenFish.BaseSellValue)
			attackerSession.profile.TotalCoinsEarned = attackerSession.profile.TotalCoinsEarned + stolenFish.BaseSellValue
			remotes.notify(
				attacker,
				string.format("Heist success! Fenced a %s %s for $%d!", rarityName, stolenFish.SpeciesId, stolenFish.BaseSellValue),
				rarityColor
			)
		end
		remotes.notify(
			victim,
			string.format("%s stole a %s %s from your aquarium! Lock it up!", attacker.DisplayName, rarityName, stolenFish.SpeciesId),
			Color3.fromRGB(255, 100, 100)
		)
		-- EPIC 11 (TASK 11.2): raid_succeeded (attacker) + raid_defended=false
		-- from victim's perspective. Fire on both sides for funnel analysis.
		if analytics then
			analytics.track(attacker, "raid_succeeded", {
				victim_id = victim.UserId,
				species_id = stolenFish.SpeciesId,
				rarity = rarityName,
			})
			analytics.track(victim, "raid_defended", { defended = false, attacker_id = attacker.UserId })
		end
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
		-- EPIC 11 (TASK 11.2): raid_defended=true (victim perspective).
		-- Attacker's raid_attempted already fired above; this captures the
		-- defense outcome for the victim-side funnel.
		if analytics then
			analytics.track(victim, "raid_defended", { defended = true, attacker_id = attacker.UserId })
		end
		if alarmConfig and alarmConfig.stunDuration > 0 then
			attackerSession.stunUntil = now + alarmConfig.stunDuration
			-- SECURITY: Apply the slow on the server too instead of relying on
			-- the client to slow itself down.
			local humanoid = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 8
			end
			remotes.notify(
				attacker,
				string.format("ALARM tripped! You're stunned for %ds.", alarmConfig.stunDuration),
				Color3.fromRGB(255, 100, 100)
			)
			task.delay(alarmConfig.stunDuration, function()
				if attackerSession.player and attackerSession.player.Parent then
					local hum = attacker.Character and attacker.Character:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.WalkSpeed = 16
					end
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
		-- Snapshot sessions to avoid mutation-during-iteration if a player
			-- leaves mid-tick (RedBear's safety pattern).
			local sessionsSnapshot = {}
			for k, session in pairs(dataManager.allSessions()) do
				sessionsSnapshot[k] = session
			end
			for _, session in pairs(sessionsSnapshot) do
				-- TASK 5.1: Accrue income to UnclaimedIncome pool (not auto-cash)
				local income = stateSync.incomePerSec(session) * GameConfig.IncomeTickSeconds
				if income > 0 then
					local unclaimed = session.profile.Aquarium.UnclaimedIncome
					local maxUnclaimed = GameConfig.Economy.MaxUnclaimedIncome
					session.profile.Aquarium.UnclaimedIncome = math.min(unclaimed + income, maxUnclaimed)
					if questService then
						questService.onIncomeEarned(session, income)
					end
				end
				if session.player and session.player.Parent then
					stateSync.push(session)
				end
			end
		end
	end)
end

return AquariumService
