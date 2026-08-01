local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local FishInstance = require(game:GetService("ReplicatedStorage").Shared.FishInstance)
local FishDefinitions = require(game:GetService("ReplicatedStorage").Shared.FishDefinitions)
local ZoneDefinitions = require(game:GetService("ReplicatedStorage").Shared.ZoneDefinitions)

local FishingService = {}

local rng = Random.new()

-- Bite timing configuration (seconds)
local BITE_MIN_DELAY = 2.0
local BITE_MAX_DELAY = 6.0
local BITE_WINDOW_SECONDS = 3.5 -- how long the player has to respond after bite (TASK 14.4: widened from 3.0 to absorb typical network latency)

function FishingService.init(deps)
	local remotes = deps.remotes
	local dataManager = deps.dataManager
	local dockManager = deps.dockManager
	local stateSync = deps.stateSync
	local questService = deps.questService
	local analytics = deps.analytics -- EPIC 11
	local onboarding = deps.onboarding -- EPIC 9
	local antiExploit = deps.antiExploit
	local auditLog = deps.auditLog
	local rodService = deps.rodService

	-- ydf6: rarity-name -> definition lookup (color etc.) so the catch FX
	-- (RodService.endCast -> leapFish) can be fed from the rolled rarity.
	local rarityByName = {}
	for _, rarityDef in ipairs(GameConfig.Rarities) do
		rarityByName[rarityDef.name] = rarityDef
	end

	-- Track active bite state per player (not persisted)
	local activeBites = {} -- player -> { zoneId, rod, baitLevel, biteTime }
	-- harborheist-kqbq.12.1: per-cast generation token. task.delay returns
	-- void (Luau has no task.cancel for void delays), so cancelling an
	-- in-progress cast cannot directly abort the pending bite callback.
	-- Each cast stamps a monotonic id; the bite callback captures it and
	-- early-returns if the id changed (cancel or supersede). This is the
	-- mechanism that "cancels the pending bite timer" — without it a stale
	-- callback would fire spurious CastState:false + zone-leave/"hands
	-- full" notifies and a redundant endCast after the player cancelled.
	local castGen = {} -- player -> monotonic cast id (nil = no active cast)

	-- RELIABILITY (TASK 14.3): player-keyed table must be cleared on disconnect
	-- or it leaks Player instances and leaves session.casting stuck true.
	local function onPlayerRemoving(player)
		local session = dataManager.get(player)
		if session then
			session.casting = false
		end
		activeBites[player] = nil
		-- harborheist-kqbq.12.1: invalidate any in-flight bite callback
		-- (also frees the per-player key so the table cannot leak Player
		-- instances). The player.Parent check in the callback is the primary
		-- guard; this is consistent defense-in-depth with the cancel path.
		castGen[player] = nil
	end

	remotes.RequestCast.OnServerEvent:Connect(function(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "cast")
			if not ok then
				if reason == "rate_limited" then
					remotes.notify(player, "Slow down! You are casting too fast.", "warn", "cast")
				end
				return
			end
		end
		local session = dataManager.get(player)
		if not session or not player.Parent then
			return
		end
		if session.casting then
			return
		end
		-- harborheist-egvu: reject a new cast while a bite is pending
		-- resolution. session.casting flips false BEFORE BiteEvent fires, so
		-- without this guard a mid-minigame RequestCast passes the check
		-- above and overwrites activeBites[player] — the in-flight catch
		-- then validates against the NEW cast's zone/rod/castDeadline.
		-- Stale entries (crashed client never submits) expire after the
		-- window + 2s grace so fishing can never softlock.
		local pendingBite = activeBites[player]
		if pendingBite then
			if os.clock() - pendingBite.biteTime < BITE_WINDOW_SECONDS + 2 then
				return
			end
			activeBites[player] = nil
		end
		if #session.carried >= GameConfig.MaxCarried then
			remotes.notify(player, "Your hands are full! Store or sell your fish first.", "warn", "cast")
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
			remotes.notify(player, "Stand in a fishing zone at your dock!", "warn", "zone")
			return
		end
		-- TASK 2.2: Enforce rod-level zone access
		if not ZoneDefinitions.canAccess(zoneId, session.profile.Equipment.EquippedRodLevel) then
			local zone = ZoneDefinitions.get(zoneId)
			remotes.notify(player, string.format("You need a better rod to fish in %s!", zone.DisplayName), "warn", "cast")
			return
		end

		-- harborheist-kqbq.12.1: stamp a monotonic cast id so a later
		-- CancelCast (or a superseding cast) can invalidate the pending
		-- task.delay bite callback by bumping this token.
		local myGen = (castGen[player] or 0) + 1
		castGen[player] = myGen
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

		-- ydf6: rod FX — swing, bobber flight + splash, line beam from rod tip.
		if rodService then
			rodService.startCast(player, dock, biteDelay)
		end

		-- Fire the bite event to the client when the bite occurs
		task.delay(biteDelay, function()
			if not player.Parent then
				session.casting = false
				activeBites[player] = nil
				return
			end
			-- harborheist-kqbq.12.1: cancel/supersede race guard. If the
			-- player cancelled this cast (CancelCast bumped castGen) or
			-- started a new one, this stale callback's captured id no longer
			-- matches — bail before firing CastState/BiteEvent/notifies so a
			-- cancel is clean (no "the fish got away" after Esc).
			if castGen[player] ~= myGen then
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
				remotes.notify(player, "You left the fishing zone... the fish got away!", "error", "missed")
				activeBites[player] = nil
				if rodService then
					rodService.endCast(player, false)
				end
				return
			end
			if #session.carried >= GameConfig.MaxCarried then
				remotes.notify(player, "Your hands are full! Store or sell your fish first.", "warn", "cast")
				activeBites[player] = nil
				if rodService then
					rodService.endCast(player, false)
				end
				return
			end

			-- Fire bite event to client (triggers the timing minigame)
			local biteData = activeBites[player]
			if biteData then
				biteData.biteTime = os.clock() -- reset to actual bite moment
				remotes.BiteEvent:FireClient(player, zoneId, BITE_WINDOW_SECONDS)

				-- If the player never responds to the bite (AFK / ignored it),
				-- nothing used to clean up — activeBites[player] leaked and the
				-- bobber FX floated until the player left. Schedule a sweeper that
				-- fires just after the bite window closes; if the entry is STILL
				-- the same one (a new cast replaces the table entry, so identity
				-- comparison guards against killing a subsequent cast's state),
				-- the player never responded.
				local scheduledBite = biteData
				task.delay(BITE_WINDOW_SECONDS + 0.5, function()
					if activeBites[player] == scheduledBite then
						activeBites[player] = nil
						if rodService then
							rodService.endCast(player, false)
						end
						if player.Parent then
							remotes.notify(player, "The fish got away...", "error", "missed")
						end
					end
				end)
			end
		end)
	end)

	-- N16 (CastResult wiring): the cast-overlay timing bar sends the marker's
	-- position when the player clicked. The server re-derives the accuracy
	-- tier from its OWN authoritative bounds (stored on activeBites by the
	-- RequestCast handler) rather than trusting any tier the client might claim.
	-- The luckBonus is then consumed by the species roll in SubmitCatchInput.
	remotes.CastResult.OnServerEvent:Connect(function(player, accuracy)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "cast_result")
			if not ok then
				if reason == "rate_limited" then
					remotes.notify(player, "Slow down! You're casting too fast.", "warn", "cast")
				end
				return
			end
		end
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
			remotes.notify(player, "PERFECT CAST! +Luck on this catch.", "success", "cast")
		elseif tier == "good" then
			remotes.notify(player, "Good cast. +Luck on this catch.", "info", "cast")
		end
	end)

	-- harborheist-kqbq.12.1: Esc/cancel for the cast overlay. Desktop players
	-- expect to bail out of the current context; today RequestCast schedules a
	-- 2-6s bite regardless, so a client-only hide would desync (BiteEvent would
	-- arrive for a hidden overlay). The server authoritatively cancels the
	-- pending cast: the cancel is valid ONLY during the pre-bite wait
	-- (session.casting == true). Once the bite fires (casting flips false in
	-- the task.delay callback above, BEFORE BiteEvent), the bite minigame is
	-- forfeit-by-design and non-cancellable. Because task.delay is uncancelable,
	-- "cancelling the pending bite timer" = bumping the castGen token so the
	-- in-flight callback becomes a no-op (see the guard above). Cleanup reuses
	-- the exact activeBites=nil + rodService.endCast(false) pattern used by the
	-- zone-leave / hands-full / catch paths — no forked logic. No luck/rarity/
	-- species state is touched; cancel NEVER refunds or re-rolls.
	local function handleCancelCast(player)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "cancel_cast")
			if not ok then
				if reason == "rate_limited" then
					remotes.notify(player, "Slow down! You are cancelling too fast.", "warn", "cast")
				end
				return
			end
		end
		local session = dataManager.get(player)
		if not session or not player.Parent then
			return
		end
		-- Race guard: only cancellable while the bite is still pending. If
		-- casting is false the bite already fired (or no cast is in progress) —
		-- treat as non-cancellable and ignore.
		if not session.casting then
			return
		end
		-- Invalidate the pending task.delay bite callback (the "cancel the
		-- timer" step) so it early-returns without firing BiteEvent/notifies.
		castGen[player] = (castGen[player] or 0) + 1
		-- Reuse the existing cleanup path (mirrors zone-leave/hands-full/catch).
		session.casting = false
		activeBites[player] = nil
		if rodService then
			rodService.endCast(player, false)
		end
		-- Authoritatively hide the cast overlay on the client (the client Esc
		-- wiring in kqbq.12.2 also hides locally; this is the server source of
		-- truth so a cancel is consistent even before 12.2 lands).
		remotes.CastState:FireClient(player, false, 0)
		remotes.notify(player, "Cast cancelled.", "info", "cast")
	end

	remotes.CancelCast.OnServerEvent:Connect(handleCancelCast)

	-- TASK 3.3: Client submits catch input after the minigame
	local function handleSubmitCatchInput(player, timingResult)
		if antiExploit then
			local ok, reason = antiExploit.checkRate(player, "submit_catch")
			if not ok then
				return { ok = false, reason = reason }
			end
		end
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
			remotes.notify(player, "Too slow! The fish got away...", "error", "missed")
			if rodService then
				rodService.endCast(player, false)
			end
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
			remotes.notify(player, "The fish slipped away...", "error", "missed")
			if rodService then
				rodService.endCast(player, false)
			end
			if analytics then
				analytics.track(player, "fish_catch_failed", { reason = "missed" })
			end
			return { ok = false, reason = "missed" }
		end

		-- TASK 14.16 (SECURITY) + TASK 14.24 (DECISION C): the marker position is
		-- computed on the client, so the server can never prove a claimed hit is
		-- real. Root-cause mitigation: treat the client hit as a REQUEST resolved
		-- against a server-side success probability (the re-roll). The re-roll
		-- stays as the security floor — an always-hit exploiter can never reach a
		-- 100% catch rate, and species/rarity/value remain server-rolled, so no
		-- client can forge the catch outcome.
		--
		-- DECISION C (wqw.24): the bare re-roll made the bite minigame theater —
		-- an honest player who perfectly timed the tap STILL missed
		-- (1 - zoneSize) of the time, so the earlier "honest clients are
		-- unaffected" claim was wrong. Fix (server-only, authority preserved):
		-- the server-authoritative cast-accuracy luckBonus (set in the CastResult
		-- handler from the SERVER's own zone bounds — the client cannot claim a
		-- better tier than a perfect honest cast) inflates the effective bite
		-- zone from the rod's base up to MiniGame.biteZoneCeiling. A perfect cast
		-- raises catch odds toward the ceiling; an ok/no cast keeps the base floor.
		-- Exploiters are capped at the perfect-honest rate, never above it.
		local rodDef = GameConfig.RodDefinitions[biteData.rodLevel]
		local baseZone = (rodDef and rodDef.minigameZoneSize) or 0.30
		local luckBonus = biteData.luckBonus or 0
		local maxLuck = GameConfig.MiniGame.accuracyLuckBonus.perfect
		local ceiling = GameConfig.MiniGame.biteZoneCeiling or 0.85
		-- Interpolate base -> ceiling by the cast-accuracy fraction (0..1).
		local effectiveZone = baseZone
		if maxLuck and maxLuck > 0 and luckBonus > 0 then
			effectiveZone = baseZone + (luckBonus / maxLuck) * (ceiling - baseZone)
		end
		effectiveZone = math.clamp(effectiveZone, baseZone, ceiling)
		if rng:NextNumber() > effectiveZone then
			remotes.notify(player, "The fish slipped away...", "error", "missed")
			if rodService then
				rodService.endCast(player, false)
			end
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

		-- ydf6: rod FX — reel the bobber in and leap the caught fish (rarity
		-- colored) from the water to the player's chest.
		if rodService then
			rodService.endCast(player, true, rarityByName[fish.Rarity])
		end

		-- TASK 10.3: audit log for high-value catches (Legendary/Epic)
		if auditLog then
			auditLog.logCatch(player, fish)
		end

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
				-- TASK 14.24: effective bite zone actually used by the re-roll
				-- (base floor inflated by the cast-accuracy luckBonus) plus the
				-- bonus itself. Powers post-launch tuning of biteZoneCeiling.
				effective_zone = effectiveZone,
				cast_luck_bonus = luckBonus,
			})
			if analytics.isFirst(player.UserId, "first_catch") then
				analytics.track(player, "first_catch", { species_id = fish.SpeciesId })
			end
		end

		-- EPIC 9 (TASK 9.1): flip the first-catch onboarding flag. Idempotent.
		if onboarding then
			onboarding.mark(session, "HasCaughtFirstFish")
		end

		-- TASK 8.3 (gdj.3): track total catches for new-player protection gate.
		-- DEC-4: "first aquarium upgrade OR 10 total catches" unlocks raid eligibility.
		-- Increment on every successful catch; stored in both Stats and PvP for compat.
		if session.profile.Stats then
			session.profile.Stats.TotalCatches = (session.profile.Stats.TotalCatches or 0) + 1
		end
		if session.profile.PvP then
			session.profile.PvP.TotalCatches = (session.profile.PvP.TotalCatches or 0) + 1
		end

		-- N11: fire the catch quest hook. This was defined on QuestService but
		-- never called, so `catch_rarity` quests (3 of the 11 quest templates)
		-- could never progress. Pass the string rarity; QuestService normalizes.
		if questService then
			questService.onFishCaught(session, fish.Rarity)
		end

		-- [harborheist-a2ug.6] Ephemeral session catch counter (NOT persisted —
		-- resets each session, matching the client catchesThisSession counter
		-- that drives the reveal-card condition). Used to decide whether the
		-- client will show a reveal card for this catch, so we can suppress the
		-- duplicate discovery toast server-side.
		session.catchesThisSession = (session.catchesThisSession or 0) + 1

		-- TASK 7.1: Track species discovery
		-- [harborheist-a2ug.6] Suppress the discovery toast when the client will
		-- show a reveal card for this catch (Rare+ rarity OR first catch of the
		-- session — mirrors the client card condition at onMinigameTap). The card
		-- renders a NEW DISCOVERY ribbon for these; the toast remains the only
		-- celebration surface for Common/Uncommon discoveries on later catches.
		local isNewDiscovery = not session.profile.Collection.DiscoveredSpecies[fish.SpeciesId]
		if isNewDiscovery then
			session.profile.Collection.DiscoveredSpecies[fish.SpeciesId] = true
			local cardEligible = fish.Rarity == "Rare" or fish.Rarity == "Epic" or fish.Rarity == "Legendary" or session.catchesThisSession == 1
			if not cardEligible then
				remotes.notify(player, string.format("New species discovered: %s!", fish.SpeciesId), "discovery", "discovery")
			end
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
			rarityColor,
			"catch"
		)
		stateSync.push(session)
		return { ok = true, speciesId = fish.SpeciesId, rarity = fish.Rarity, value = fish.BaseSellValue, isNewDiscovery = isNewDiscovery or nil }
	end

	remotes.SubmitCatchInput.OnServerInvoke = handleSubmitCatchInput

	-- Test seams (same pattern as RaidService): expose internal state so E2E
	-- tests can inspect/seed bite state and substitute the RNG for
	-- deterministic catch rolls, without needing to fire remote events
	-- (which require a real client connection the server can't simulate).
	return {
		onPlayerRemoving = onPlayerRemoving,
		_activeBites = activeBites,
		_setRng = function(newRng) rng = newRng end,
		-- Expose the submit handler for direct E2E invocation (bypasses the
		-- RemoteFunction which passes nil as the player when called from
		-- server context via InvokeServer).
		_submitCatch = handleSubmitCatchInput,
		-- harborheist-kqbq.12.1: expose the cancel handler for direct E2E
		-- invocation (bypasses OnServerEvent, which needs a real client), and
		-- the generation token so tests can assert a cancel bumps it.
		_cancelCast = handleCancelCast,
		_castGen = castGen,
	}
end

return FishingService
