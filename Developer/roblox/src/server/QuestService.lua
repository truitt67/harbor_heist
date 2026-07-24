local GameConfig = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local PlayerProfile = require(game:GetService("ReplicatedStorage").Shared.PlayerProfile)

local QuestService = {}

local POOL = {
	{ type = "catch_rarity", target = 5,  rarity = 3, reward = 200, desc = "Catch 5 Rare or better fish" },
	{ type = "catch_rarity", target = 3,  rarity = 4, reward = 350, desc = "Catch 3 Epic or better fish" },
	{ type = "catch_rarity", target = 1,  rarity = 5, reward = 600, desc = "Catch a Legendary fish" },
	-- harborheist-kqd0: raid quest templates. The legacy steal_count quests
	-- were removed in gdj.15 when the always-on steal handler was deleted.
	-- Epic 8 RaidService now calls onStealAttempt, so raid-based quests are
	-- completable again. The quest type is "raid_success" (renamed from
	-- "steal_count" to reflect the new raid system). Players with an
	-- already-active steal_count quest keep it until the daily/weekly
	-- rotation replaces it (self-healing — processList only touches quests
	-- whose predicate matches a live event, and onStealAttempt matches BOTH
	-- types for backward compat).
	{ type = "raid_success", target = 1, reward = 300, desc = "Successfully raid 1 aquarium" },
	{ type = "raid_success", target = 3, reward = 750, desc = "Successfully raid 3 aquariums" },
	{ type = "income_earned", target = 500,  reward = 250, desc = "Earn $500 from passive income" },
	{ type = "income_earned", target = 1500, reward = 450, desc = "Earn $1,500 from passive income" },
	{ type = "store_count",  target = 10, reward = 150, desc = "Store 10 fish in your aquarium" },
	{ type = "store_count",  target = 25, reward = 300, desc = "Store 25 fish in your aquarium" },
	{ type = "sell_value",   target = 1000, reward = 200, desc = "Sell $1,000 worth of fish in total" },
	{ type = "sell_value",   target = 2500, reward = 400, desc = "Sell $2,500 worth of fish in total" },
}

-- Module-level deps captured in init(); used by event callbacks below.
local remotes
local stateSync

local function dailyKey(player)
	local now = os.date("!*t")
	return string.format("d_%d_%d_%d", player.UserId, now.year, now.yday)
end

local function weeklyKey(player)
	local now = os.date("!*t")
	local weekStart = now.yday - now.wday + 1
	return string.format("w_%d_%d_%d", player.UserId, now.year, weekStart)
end

local function pickDistinct(pool, count, rng)
	local chosen = {}
	local used = {}
	while #chosen < count and #used < #pool do
		local i = rng:NextInteger(1, #pool)
		if not used[i] then
			used[i] = true
			local t = pool[i]
			table.insert(chosen, {
				id = string.format("q%d_%d_%d", #chosen + 1, t.reward, t.target),
				type = t.type,
				target = t.target,
				rarity = t.rarity,
				progress = 0,
				claimed = false,
				reward = t.reward,
				desc = t.desc,
			})
		end
	end
	return chosen
end

function QuestService.initializeQuests(session)
	local dKey = dailyKey(session.player)
	local wKey = weeklyKey(session.player)

	if session.dailyQuestKey ~= dKey or #session.dailyQuests == 0 then
		local seedString = string.gsub(dKey, "%D", "")
		local seed = tonumber(seedString) or 0
		local rng = Random.new(seed)
		session.dailyQuestKey = dKey
		session.dailyQuests = pickDistinct(POOL, GameConfig.Quests.DailySlots, rng)
	end

	if session.weeklyQuestKey ~= wKey or #session.weeklyQuests == 0 then
		local seedString = string.gsub(wKey, "%D", "")
		local seed = tonumber(seedString) or 0
		local rng = Random.new(seed)
		session.weeklyQuestKey = wKey
		session.weeklyQuests = pickDistinct(POOL, GameConfig.Quests.WeeklySlots, rng)
	end
end

local function processList(session, list, scope, predicate, incrFn)
	local changed = false
	for _, q in ipairs(list) do
		if not q.claimed and predicate(q) then
			q.progress = incrFn(q)
			changed = true
			if q.progress >= q.target then
				q.progress = q.target
				q.claimed = true
				-- N4 (CRITICAL): session has no `cash` field — money lives in
				-- session.profile.Coins. The old `session.cash += q.reward` line
				-- errored on every quest completion ("arithmetic on nil value")
				-- AND credited nothing. Route through clampCoins + track lifetime
				-- earnings, matching every other coin-grant path in the codebase.
				session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + q.reward)
				session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + q.reward
				if remotes and session.player and session.player.Parent then
					remotes.notify(
						session.player,
						string.format("%s complete: %s (+$%d)", scope, q.desc, q.reward),
						Color3.fromRGB(255, 215, 0),
						"quest"
					)
				end
			end
		end
	end
	return changed
end

local function progressQuests(session, predicate, incrFn)
	if not session then
		return
	end
	local changed = processList(session, session.dailyQuests, "Daily quest", predicate, incrFn)
	changed = processList(session, session.weeklyQuests, "Weekly quest", predicate, incrFn) or changed
	if changed then
		if stateSync then
			stateSync.push(session)
		end
		if remotes and session.player and session.player.Parent then
			remotes.QuestProgressChanged:FireClient(session.player, {
				dailyKey = session.dailyQuestKey,
				dailyQuests = session.dailyQuests,
				weeklyKey = session.weeklyQuestKey,
				weeklyQuests = session.weeklyQuests,
			})
		end
	end
end

-- Map rarity name -> ordinal for `catch_rarity` quest comparisons.
-- FishInstance.Rarity is a string ("Common".."Legendary"); quests store a
-- numeric threshold (3 = Rare+, 4 = Epic+, 5 = Legendary).
-- harborheist-lunp: derive from GameConfig.Rarities (ordered Common ->
-- Legendary, so the array index doubles as rarity rank) instead of hardcoding —
-- same dt9.5 pattern as FishDefinitions.RARITY_ORDER and DockManager, so a
-- rarity reorder/rename cannot silently desync quest thresholds.
local RARITY_ORDINAL = {}
for i, rarity in ipairs(GameConfig.Rarities) do
	RARITY_ORDINAL[rarity.name] = i
end

function QuestService.onFishCaught(session, rarity)
	-- Accept either a string rarity name (from FishInstance) or a numeric
	-- ordinal (legacy callers). Normalize to a number before comparing.
	local rarityIndex = type(rarity) == "number" and rarity or RARITY_ORDINAL[rarity] or 1
	progressQuests(
		session,
		function(q) return q.type == "catch_rarity" and (rarityIndex >= (q.rarity or 1)) end,
		function(q) return q.progress + 1 end
	)
end

function QuestService.onStealAttempt(session, success)
	if not success then
		return
	end
	progressQuests(
		session,
		function(q) return q.type == "raid_success" or q.type == "steal_count" end,
		function(q) return q.progress + 1 end
	)
end

function QuestService.onIncomeEarned(session, amount)
	progressQuests(
		session,
		function(q) return q.type == "income_earned" end,
		function(q) return q.progress + amount end
	)
end

function QuestService.onFishStored(session, count)
	progressQuests(
		session,
		function(q) return q.type == "store_count" end,
		function(q) return q.progress + count end
	)
end

function QuestService.onFishSold(session, totalValue)
	progressQuests(
		session,
		function(q) return q.type == "sell_value" end,
		function(q) return q.progress + totalValue end
	)
end

function QuestService.pushProgress(session)
	if not remotes or not session.player or not session.player.Parent then
		return
	end
	remotes.QuestProgressChanged:FireClient(session.player, {
		dailyKey = session.dailyQuestKey,
		dailyQuests = session.dailyQuests,
		weeklyKey = session.weeklyQuestKey,
		weeklyQuests = session.weeklyQuests,
	})
end

function QuestService.init(deps)
	remotes = deps.remotes
	stateSync = deps.stateSync
	local dataManager = deps.dataManager
	-- Round-4 review (harborheist-xdt): wire antiExploit so the OpenQuests
	-- rate-limit guard below is LIVE, not dead code. Was referenced but never
	-- extracted from deps, so `if antiExploit then` always evaluated false and
	-- the EPIC-10 quest=10/10s rate limit never applied.
	local antiExploit = deps.antiExploit

	for _, session in pairs(dataManager.allSessions()) do
		QuestService.initializeQuests(session)
		QuestService.pushProgress(session)
	end

	remotes.OpenQuests.OnServerEvent:Connect(function(player)
		if antiExploit then
			local ok = antiExploit.checkRate(player, "quest")
			if not ok then return end
		end
		local session = dataManager.get(player)
		if session then
			QuestService.initializeQuests(session)
			QuestService.pushProgress(session)
		end
	end)
end

return QuestService
