local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)

local FishingService = {}

local rng = Random.new()

local function getEffectiveHitZoneWidth(luck)
	local base = GameConfig.MiniGame.goodZoneWidth
	local bonus = luck / 100 * 0.15
	return math.min(0.85, base + bonus)
end

local function gradeAccuracy(accuracy, hitZoneWidth)
	local center = 0.5
	local dist = math.abs(accuracy - center)
	local perfectWidth = hitZoneWidth * 0.4
	local goodWidth = hitZoneWidth * 0.7
	if dist <= perfectWidth / 2 then
		return "perfect"
	elseif dist <= goodWidth / 2 then
		return "good"
	elseif dist <= hitZoneWidth / 2 then
		return "ok"
	end
	return "miss"
end

local function playerQuery(session)
	return session and session.player and session.player.Parent
end

local function awardCatch(session, accuracyLevel, dock, deps)
	local remotes = deps.remotes
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService

	if not playerQuery(session) then
		return
	end

	if #session.carried >= GameConfig.MaxCarried then
		remotes.notify(session.player, "Your hands are full! Store or sell your fish first.", Color3.fromRGB(255, 170, 80))
		return
	end

	local rod = GameConfig.Rods[session.rodLevel]
	local bait = GameConfig.Baits[session.baitLevel]
	if not rod or not bait then
		return
	end
	local baseLuck = rod.luck + bait.luck
	local bonus = GameConfig.MiniGame.accuracyLuckBonus[accuracyLevel] or 0
	local totalLuck = baseLuck + bonus

	local rarityIndex = GameConfig.rollRarity(totalLuck, rng)
	if not (type(rarityIndex) == "number" and GameConfig.Rarities[rarityIndex]) then
		warn("[HarborHeist] Invalid rarityIndex caught: " .. tostring(rarityIndex))
		return
	end
	local rarity = GameConfig.Rarities[rarityIndex]
	table.insert(session.carried, rarityIndex)

	local tag = ""
	if accuracyLevel == "perfect" then
		tag = " - PERFECT CAST!"
	elseif accuracyLevel == "good" then
		tag = " - Good cast."
	end
	remotes.notify(
		session.player,
		string.format("You caught a %s fish%s (worth $%d)", rarity.name, tag, rarity.value),
		rarity.color
	)
	stateSync.push(session)
	if questService then
		questService.onFishCaught(session, rarityIndex)
	end
end

function FishingService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService

	local pendingCasts = {} -- [player] = { deadline, hitZoneWidth, dock }

	local function failCast(player, reason)
		local session = dataManager.get(player)
		if not session then
			return
		end
		session.casting = false
		session.castDeadline = 0
		pendingCasts[player] = nil
		remotes.CastState:FireClient(player, false, 0, nil)
		if reason and session.player and session.player.Parent then
			remotes.notify(player, reason, Color3.fromRGB(255, 120, 120))
		end
		stateSync.push(session)
	end

	remotes.Cast.OnServerEvent:Connect(function(player)
		local session = dataManager.get(player)
		if not session or not player.Parent then
			return
		end
		if session.casting then
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
		if not player.Character or not dockManager.isInFishingZone(dock, player.Character) then
			remotes.notify(player, "Stand in the glowing Fishing Zone at the end of your dock!", Color3.fromRGB(255, 170, 80))
			return
		end

		session.casting = true
		local rod = GameConfig.Rods[session.rodLevel]
		if not rod then
			session.casting = false
			return
		end
		local castTime = rod.castTime + rng:NextNumber(0, 2)

		local baseLuck = rod.luck + GameConfig.Baits[session.baitLevel].luck
		local hitZoneWidth = getEffectiveHitZoneWidth(baseLuck)
		local hitZoneStart = 0.5 - hitZoneWidth / 2
		local hitZoneEnd = 0.5 + hitZoneWidth / 2

		session.castDeadline = os.clock() + castTime
		session.castHitZoneStart = hitZoneStart
		session.castHitZoneEnd = hitZoneEnd
		pendingCasts[player] = { deadline = session.castDeadline, hitZoneWidth = hitZoneWidth, dock = dock }

		remotes.CastState:FireClient(player, true, castTime, { hitZoneStart = hitZoneStart, hitZoneEnd = hitZoneEnd })

		task.delay(castTime, function()
			local pending = pendingCasts[player]
			if pending and pending.deadline == session.castDeadline and session.casting then
				failCast(player, "You took too long! The fish got away.")
			end
		end)
	end)

	remotes.CastResult.OnServerEvent:Connect(function(player, accuracy)
		local session = dataManager.get(player)
		if not session or not session.casting then
			return
		end
		local pending = pendingCasts[player]
		if not pending then
			return
		end
		if type(accuracy) ~= "number" or accuracy < 0 or accuracy > 1 then
			failCast(player, "Invalid cast data.")
			return
		end
		if os.clock() > pending.deadline + 0.25 then
			failCast(player, "You took too long! The fish got away.")
			return
		end

		local accuracyLevel = gradeAccuracy(accuracy, pending.hitZoneWidth)
		local dock = pending.dock
		pendingCasts[player] = nil
		session.casting = false
		session.castDeadline = 0
		remotes.CastState:FireClient(player, false, 0, nil)

		if accuracyLevel == "miss" then
			remotes.notify(player, "You missed the timing! The fish got away.", Color3.fromRGB(255, 120, 120))
			stateSync.push(session)
			return
		end

		if not player.Character or not dockManager.isInFishingZone(dock, player.Character) then
			remotes.notify(player, "You left the fishing zone... the fish got away!", Color3.fromRGB(255, 120, 120))
			stateSync.push(session)
			return
		end

		awardCatch(session, accuracyLevel, dock, deps)
		stateSync.push(session)
	end)
end

return FishingService
