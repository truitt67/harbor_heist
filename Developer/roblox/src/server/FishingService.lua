local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)
local FishDefinitions = require(game:GetService("ReplicatedStorage").Shared.FishDefinitions)
local ZoneDefinitions = require(game:GetService("ReplicatedStorage").Shared.ZoneDefinitions)

local FishingService = {}

local rng = Random.new()

-- Bite timing configuration (seconds)
local BITE_MIN_DELAY = 2.0
local BITE_MAX_DELAY = 6.0
local BITE_WINDOW_SECONDS = 3.0 -- how long the player has to respond after bite

function FishingService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService
	local analytics = deps.analytics -- EPIC 11
	local rodService = deps.rodService

	local function failCast(player, reason)
		-- RELIABILITY: Always clear the pending entry, even when the session is
		-- already gone (player left) - otherwise the Player key leaks in the table.
		if rodService then
			rodService.endCast(player, false)
		end
		local session = dataManager.get(player)
		if not session then
			return
		end
		session.casting = false
		session.castDeadline = 0
		remotes.CastState:FireClient(player, false, 0, nil)
		if reason and session.player and session.player.Parent then
			remotes.notify(player, reason, Color3.fromRGB(255, 120, 120))
		end
		stateSync.push(session)
	end

	-- Track active bite state per player (not persisted)
	local activeBites = {} -- player -> { zoneId, rod, baitLevel, biteTime }

	-- RELIABILITY (TASK 14.3): player-keyed table must be cleared on disconnect
	-- or it leaks Player instances and leaves session.casting stuck true.
	local function onPlayerRemoving(player)
		local session = dataManager.get(player)
		if session then
			session.casting = false
		end
		activeBites[player] = nil
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
	-- SECURITY: Verify character exists and is in a fishing zone
		local inZone, zoneId = false, nil
		if player.Character then
			inZone, zoneId = dockManager.isInFishingZone(dock, player.Character)
		end
		if not inZone then
			remotes.notify(player, "Stand in a fishing zone at your dock!", Color3.fromRGB(255, 170, 80))
			return
		end
		-- TASK 2.2: Enforce rod-level zone access
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
		-- TASK 3.1: Server-side bite roll

		-- Bite delay is randomized; better rods = shorter average wait
		local baseDelay = rod.castTime
		local biteDelay = baseDelay + rng:NextNumber(BITE_MIN_DELAY, BITE_MAX_DELAY)

		-- N16 (CastResult wiring): compute the cast-overlay hit zone bounds from
		-- the authoritative RodDefinitions table. The client renders the zone
		-- from these bounds, and CastResult's accuracy is validated against them
		-- when the marker stops. Better rods get a wider target zone.
		--
		-- ZONE SEMANTICS (fixed round-2): the OUTER, WIDER band is the "good"
		-- zone (goodZoneWidth, 0.5); the INNER, NARROWER band is the "perfect"
		-- bullseye (hitZoneWidth, 0.3, overridden by rod.minigameZoneSize).
		-- The config field names are confusingly swapped — hitZoneWidth is the
		-- NARROW inner perfect target, goodZoneWidth is the WIDE outer good band.
		-- The client's perfectZoneFrame is nested INSIDE hitZoneFrame, confirming
		-- the perfect region is the inner one. A perfectly-timed click earns the
		-- accuracyLuckBonus.perfect tier; landing in the good band earns .good.
		local rodDef = GameConfig.RodDefinitions[session.profile.Equipment.EquippedRodLevel]
		local perfectSize = (rodDef and rodDef.minigameZoneSize) or GameConfig.MiniGame.hitZoneWidth
		local goodSize = GameConfig.MiniGame.goodZoneWidth
		-- Center the GOOD (outer) zone so it fits fully inside [0,1]. Clamping on
		-- the OUTER band guarantees the inner perfect band (narrower) also fits.
		local halfGood = goodSize / 2
		local zoneCenter = rng:NextNumber(halfGood, 1 - halfGood)
		-- Outer "good" band (wider)
		local goodStart = zoneCenter - halfGood
		local goodEnd = zoneCenter + halfGood
		-- Inner "perfect" bullseye (narrower, centered on the same point)
		local halfPerfect = perfectSize / 2
		local hitZoneStart = zoneCenter - halfPerfect
		local hitZoneEnd = zoneCenter + halfPerfect
		-- The cast deadline is the absolute os.clock() at which the marker reaches
		-- position 1.0 (end of track). The client computes accuracy from where the
		-- marker was when the player clicked.
		local castDeadline = os.clock() + biteDelay

		remotes.CastState:FireClient(player, true, biteDelay, {
			hitZoneStart = hitZoneStart, -- inner perfect bounds
			hitZoneEnd = hitZoneEnd,
			goodStart = goodStart,       -- outer good bounds
			goodEnd = goodEnd,
			castDeadline = castDeadline,
		})

		-- EPIC 11 (TASK 11.2): first_cast fires ONCE per player (the wrapper
		-- stamps firstCastAt). CORRECTED (fresh-eyes): gate on isFirst so it
		-- doesn't fire on every cast and pollute the funnel metric.
		if analytics then
			if analytics.isFirst(player.UserId, "first_cast") then
				analytics.track(player, "first_cast", { zone_id = zoneId })
			end
		end

		-- Store bite state for later validation
		activeBites[player] = {
			zoneId = zoneId,
			rodLevel = session.profile.Equipment.EquippedRodLevel,
			baitLevel = session.profile.Equipment.EquippedBaitLevel,
			biteTime = os.clock() + biteDelay,
			-- N16: cast-overlay bounds + deadline, consumed by CastResult to
			-- derive an accuracy tier. luckBonus starts at 0 and is set when the
			-- player submits their cast result (well before the bite fires).
			hitZoneStart = hitZoneStart,
			hitZoneEnd = hitZoneEnd,
			goodStart = goodStart,
			goodEnd = goodEnd,
			castDeadline = castDeadline,
			luckBonus = 0,
			castResultReceived = false,
		}

		-- Fire the bite event to the client when the bite occurs
		task.delay(biteDelay, function()
			if not player.Parent or not session.player.Parent then
				session.casting = false
				activeBites[player] = nil
				return
			end
			session.casting = false
			remotes.CastState:FireClient(player, false, 0)

			-- Re-verify zone and capacity before offering the bite.
			-- N11: re-fetch the dock at bite time instead of trusting the
			-- cast-time capture — a dock released/lost mid-cast leaves a
			-- stale reference that validates against the wrong geometry.
			local currentDock = dockManager.getDock(player)
			local stillInZone, currentZoneId = false, nil
			if currentDock and player.Character then
				stillInZone, currentZoneId = dockManager.isInFishingZone(currentDock, player.Character)
			end
			if not stillInZone or currentZoneId ~= zoneId then
				remotes.notify(player, "You left the fishing zone... the fish got away!", Color3.fromRGB(255, 120, 120))
				activeBites[player] = nil
				return
			end
			if #session.carried >= GameConfig.MaxCarried then
				remotes.notify(player, "Your hands are full! Store or sell your fish first.", Color3.fromRGB(255, 170, 80))
				activeBites[player] = nil
				return
			end

			-- Fire bite event to client (triggers the timing minigame)
			local biteData = activeBites[player]
			if biteData then
				biteData.biteTime = os.clock() -- reset to actual bite moment
				remotes.BiteEvent:FireClient(player, zoneId, BITE_WINDOW_SECONDS)
			end
		end)
	end)

	-- N16 (CastResult wiring): the cast-overlay timing bar sends the marker's
	-- position when the player clicked. The server re-derives the accuracy
	-- tier from its OWN authoritative bounds (stored on activeBites by the
	-- Cast handler) rather than trusting any tier the client might claim.
	-- The luckBonus is then consumed by the species roll in SubmitCatchInput.
	remotes.CastResult.OnServerEvent:Connect(function(player, accuracy)
		local session = dataManager.get(player)
		if not session or not player.Parent then
			return
		end

		local biteData = activeBites[player]
		if not biteData or biteData.castResultReceived then
			-- No active cast, or the player already submitted (double-fire guard).
			-- The bite may also have already fired, in which case the bonus is
			-- moot for this cast — silently ignore.
			return
		end

		-- Clamp the client's reported marker position to the valid [0,1] range.
		-- A crafted client could send -99 or 99; clamping prevents nonsense.
		accuracy = type(accuracy) == "number" and math.clamp(accuracy, 0, 1) or 0

		-- Derive the accuracy tier from the server-authoritative bounds.
		-- hitZoneStart/hitZoneEnd is the INNER "perfect" bullseye (narrow);
		-- goodStart/goodEnd is the OUTER "good" band (wide, contains perfect).
		-- Check the inner band FIRST (it's a subset of the outer). Anything
		-- outside the outer band is "ok" (no bonus).
		local tier
		if accuracy >= biteData.hitZoneStart and accuracy <= biteData.hitZoneEnd then
			tier = "perfect"
		elseif accuracy >= biteData.goodStart and accuracy <= biteData.goodEnd then
			tier = "good"
		else
			tier = "ok"
		end

		-- Map the tier to a luck bonus from the authoritative config.
		-- The client cannot inflate this: it only controls the raw position,
		-- and the server re-computes the tier against its own bounds.
		biteData.luckBonus = GameConfig.MiniGame.accuracyLuckBonus[tier] or 0
		biteData.castResultReceived = true

		-- EPIC 11 (TASK 11.2): record the cast-accuracy tier distribution.
		-- Powers the "are players engaging with the cast minigame?" question.
		if analytics then
			analytics.track(player, "cast_result_tier", { tier = tier })
		end

		-- Feedback so the player knows their cast quality registered.
		if tier == "perfect" then
			remotes.notify(player, "PERFECT CAST! +Luck on this catch.", Color3.fromRGB(134, 239, 172))
		elseif tier == "good" then
			remotes.notify(player, "Good cast. +Luck on this catch.", Color3.fromRGB(120, 190, 255))
		end
	end)

	-- TASK 3.3: Client submits catch input after the minigame
	remotes.SubmitCatchInput.OnServerInvoke = function(player, timingResult)
		local session = dataManager.get(player)
		if not session or not player.Parent then
			return { ok = false, reason = "no_session" }
		end

		local biteData = activeBites[player]
		if not biteData then
			return { ok = false, reason = "no_active_bite" }
		end

		-- Validate timing: player must respond within the bite window
		local elapsed = os.clock() - biteData.biteTime
		if elapsed > BITE_WINDOW_SECONDS then
			activeBites[player] = nil
			remotes.notify(player, "Too slow! The fish got away...", Color3.fromRGB(255, 120, 120))
			if analytics then
				analytics.track(player, "fish_catch_failed", { reason = "too_slow" })
			end
			return { ok = false, reason = "too_slow" }
		end

		-- Validate the timing result is plausible
		if type(timingResult) ~= "table" or type(timingResult.hit) ~= "boolean" then
			return { ok = false, reason = "bad_input" }
		end

		-- Clear the bite state
		activeBites[player] = nil

		if not timingResult.hit then
			remotes.notify(player, "The fish slipped away...", Color3.fromRGB(255, 120, 120))
			if analytics then
				analytics.track(player, "fish_catch_failed", { reason = "missed" })
			end
			return { ok = false, reason = "missed" }
		end

		-- TASK 14.16 (SECURITY): the marker position is computed on the client, so
		-- the server can never prove a claimed hit is real. Root-cause mitigation:
		-- treat the client hit as a REQUEST and resolve it against a server-side
		-- success probability equal to the equipped rod's minigame zone size.
		-- Honest clients are unaffected (they only send hit=true when inside the
		-- zone); always-hit exploiters are gated to the same long-run success
		-- rate as honest play, and better rods keep their wider-zone advantage.
		local rodDef = GameConfig.RodDefinitions[biteData.rodLevel]
		local zoneSize = (rodDef and rodDef.minigameZoneSize) or 0.30
		if rng:NextNumber() > zoneSize then
			remotes.notify(player, "The fish slipped away...", Color3.fromRGB(255, 120, 120))
			if analytics then
				analytics.track(player, "fish_catch_failed", { reason = "missed_reroll" })
			end
			return { ok = false, reason = "missed" }
		end

		-- TASK 3.4: Species-based catch resolution
		local zoneId = biteData.zoneId
		local rod = GameConfig.Rods[biteData.rodLevel]
		local bait = GameConfig.Baits[biteData.baitLevel]
		if not rod or not bait then
			return { ok = false, reason = "invalid_gear" }
		end

		-- Roll species from the zone's fish table, weighted by CatchWeight and
		-- luck-shifted toward rarer species (TASK FISH-02: luck is now real).
		-- N16 (CastResult): add the cast-accuracy luck bonus on top of the gear
		-- luck. A well-timed cast (perfect = +25, good = +12) measurably shifts
		-- the species distribution toward rarer fish, rewarding skill expression.
		-- Defaults to 0 when no CastResult was submitted (e.g. player idled).
		local luck = rod.luck + bait.luck + (biteData.luckBonus or 0)
		local speciesDef = FishDefinitions.getRandomInZone(zoneId, rng, luck)
		if not speciesDef then
			warn("[HarborHeist] No species found in zone: " .. zoneId)
			return { ok = false, reason = "no_species" }
		end

		-- Create FishInstance record
		local fish = FishInstance.new(speciesDef.SpeciesId, zoneId)
		table.insert(session.carried, fish)

		-- EPIC 11 (TASK 11.2): fish_caught fires every successful catch.
		-- first_catch fires ONCE (gated by isFirst). CORRECTED (fresh-eyes):
		-- previously fired every catch, polluting the funnel metric.
		-- Includes rarity + species so the dashboard can break down catch
		-- composition.
		if analytics then
			analytics.track(player, "fish_caught", {
				species_id = fish.SpeciesId,
				rarity = fish.Rarity,
				zone_id = zoneId,
			})
			if analytics.isFirst(player.UserId, "first_catch") then
				analytics.track(player, "first_catch", { species_id = fish.SpeciesId })
			end
		end

		-- N11: fire the catch quest hook. This was defined on QuestService but
		-- never called, so `catch_rarity` quests (3 of the 11 quest templates)
		-- could never progress. Pass the string rarity; QuestService normalizes.
		if questService then
			questService.onFishCaught(session, fish.Rarity)
		end

		-- TASK 7.1: Track species discovery
		if not session.profile.Collection.DiscoveredSpecies[fish.SpeciesId] then
			session.profile.Collection.DiscoveredSpecies[fish.SpeciesId] = true
			remotes.notify(player, string.format("New species discovered: %s!", fish.SpeciesId), Color3.fromRGB(255, 215, 0))
		end

		-- Find rarity color for notification
		local rarityColor = Color3.fromRGB(255, 255, 255)
		for _, r in ipairs(GameConfig.Rarities) do
			if r.name == fish.Rarity then
				rarityColor = r.color
				break
			end
		end

		remotes.notify(
			player,
			string.format("You caught a %s %s! (worth $%d)", fish.Rarity, fish.SpeciesId, fish.BaseSellValue),
			rarityColor
		)
		stateSync.push(session)
		return { ok = true, speciesId = fish.SpeciesId, rarity = fish.Rarity, value = fish.BaseSellValue }
	end

	return {
		onPlayerRemoving = onPlayerRemoving,
	}
end

return FishingService
