-- QuestService pure-logic unit tests (TASK 41-01-C, harborheist-m3vj.2).
--
-- QuestService has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the quest
-- rotation/progress/reward mechanics are mirrored as pure Luau functions
-- (random draws and dates are passed in as arguments — no mocks, fakes,
-- or stubs). Source-contract assertions verify that the production code
-- still contains the formulas tested here.
--
-- Covers: quest pool shape, daily/weekly key formats (UTC), deterministic
-- per-player-day seeding, distinct-pick rotation, rarity ordinal mapping
-- (derived from GameConfig.Rarities order), progress accumulation and
-- clamping, one-time reward grants via clampCoins, legacy steal_count
-- backward compatibility, and the N4 coin-field routing fix.

local fs = require("@lune/fs")

-- ──────────────────────────────────────────────────────────────────────
-- Config mirrors (must match src/server/QuestService.lua + GameConfig)
-- ──────────────────────────────────────────────────────────────────────

local POOL = {
	{ type = "catch_rarity", target = 5,  rarity = 3, reward = 200, desc = "Catch 5 Rare or better fish" },
	{ type = "catch_rarity", target = 3,  rarity = 4, reward = 350, desc = "Catch 3 Epic or better fish" },
	{ type = "catch_rarity", target = 1,  rarity = 5, reward = 600, desc = "Catch a Legendary fish" },
	{ type = "raid_success", target = 1, reward = 300, desc = "Successfully raid 1 aquarium" },
	{ type = "raid_success", target = 3, reward = 750, desc = "Successfully raid 3 aquariums" },
	{ type = "income_earned", target = 500,  reward = 250, desc = "Earn $500 from passive income" },
	{ type = "income_earned", target = 1500, reward = 450, desc = "Earn $1,500 from passive income" },
	{ type = "store_count",  target = 10, reward = 150, desc = "Store 10 fish in your aquarium" },
	{ type = "store_count",  target = 25, reward = 300, desc = "Store 25 fish in your aquarium" },
	{ type = "sell_value",   target = 1000, reward = 200, desc = "Sell $1,000 worth of fish in total" },
	{ type = "sell_value",   target = 2500, reward = 400, desc = "Sell $2,500 worth of fish in total" },
}

local DAILY_SLOTS = 3
local WEEKLY_SLOTS = 2
local MAX_COINS = 999999999

-- Rarity ordinal mirror (QuestService.lua lines 146-149): derived from
-- GameConfig.Rarities array order so index doubles as rarity rank.
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local RARITY_ORDINAL = {}
for i, name in ipairs(RARITY_ORDER) do
	RARITY_ORDINAL[name] = i
end

-- ──────────────────────────────────────────────────────────────────────
-- Logic mirrors (verbatim from QuestService.lua production code)
-- ──────────────────────────────────────────────────────────────────────

local function clampCoins(value)
	if type(value) ~= "number" then
		return 0
	end
	if value ~= value then
		return 0
	end
	return math.floor(math.max(0, math.min(MAX_COINS, value)))
end

-- Key formats (lines 33-42). Production reads os.date("!*t") (UTC);
-- the mirror takes the date fields as arguments.
local function dailyKey(userId, year, yday)
	return string.format("d_%d_%d_%d", userId, year, yday)
end

local function weeklyKey(userId, year, yday, wday)
	local weekStart = yday - wday + 1
	return string.format("w_%d_%d_%d", userId, year, weekStart)
end

-- Seed derivation (lines 72-74, 80-82): strip non-digits from the key.
local function seedForKey(key)
	local seedString = string.gsub(key, "%D", "")
	return tonumber(seedString) or 0
end

-- Distinct pick (lines 44-65). nextInteger(lo, hi) is the injected draw
-- (production uses Random.new(seed):NextInteger).
local function pickDistinct(pool, count, nextInteger)
	local chosen = {}
	local used = {}
	while #chosen < count and #used < #pool do
		local i = nextInteger(1, #pool)
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

-- Rotation gate (lines 67-86): reroll when the key changed OR the list
-- is empty; otherwise keep the existing quests untouched.
local function initializeQuests(session, dKey, wKey, nextInteger)
	if session.dailyQuestKey ~= dKey or #session.dailyQuests == 0 then
		session.dailyQuestKey = dKey
		session.dailyQuests = pickDistinct(POOL, DAILY_SLOTS, nextInteger)
	end
	if session.weeklyQuestKey ~= wKey or #session.weeklyQuests == 0 then
		session.weeklyQuestKey = wKey
		session.weeklyQuests = pickDistinct(POOL, WEEKLY_SLOTS, nextInteger)
	end
end

-- Progress engine (lines 88-116). N4 (CRITICAL): money lives in
-- session.profile.Coins — the old session.cash line errored AND credited
-- nothing. Rewards route through clampCoins + TotalCoinsEarned.
local function processList(session, list, predicate, incrFn)
	local changed = false
	for _, q in ipairs(list) do
		if not q.claimed and predicate(q) then
			q.progress = incrFn(q)
			changed = true
			if q.progress >= q.target then
				q.progress = q.target
				q.claimed = true
				session.profile.Coins = clampCoins(session.profile.Coins + q.reward)
				session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + q.reward
			end
		end
	end
	return changed
end

local function progressQuests(session, predicate, incrFn)
	if not session then
		return false
	end
	local changed = processList(session, session.dailyQuests, predicate, incrFn)
	changed = processList(session, session.weeklyQuests, predicate, incrFn) or changed
	return changed
end

-- Event handlers (lines 151-195).
local function onFishCaught(session, rarity)
	local rarityIndex = type(rarity) == "number" and rarity or RARITY_ORDINAL[rarity] or 1
	return progressQuests(
		session,
		function(q) return q.type == "catch_rarity" and (rarityIndex >= (q.rarity or 1)) end,
		function(q) return q.progress + 1 end
	)
end

local function onStealAttempt(session, success)
	if not success then
		return false
	end
	return progressQuests(
		session,
		function(q) return q.type == "raid_success" or q.type == "steal_count" end,
		function(q) return q.progress + 1 end
	)
end

local function onIncomeEarned(session, amount)
	return progressQuests(
		session,
		function(q) return q.type == "income_earned" end,
		function(q) return q.progress + amount end
	)
end

local function onFishStored(session, count)
	return progressQuests(
		session,
		function(q) return q.type == "store_count" end,
		function(q) return q.progress + count end
	)
end

local function onFishSold(session, totalValue)
	return progressQuests(
		session,
		function(q) return q.type == "sell_value" end,
		function(q) return q.progress + totalValue end
	)
end

-- ──────────────────────────────────────────────────────────────────────
-- Test helpers
-- ──────────────────────────────────────────────────────────────────────

local function makeSession(coins)
	return {
		dailyQuestKey = "",
		weeklyQuestKey = "",
		dailyQuests = {},
		weeklyQuests = {},
		profile = { Coins = coins or 0, TotalCoinsEarned = 0 },
	}
end

-- Deterministic draw sequence: cycles through the given values.
local function seqDraws(values)
	local idx = 0
	return function(_lo, _hi)
		idx = idx + 1
		return values[((idx - 1) % #values) + 1]
	end
end

local function questOf(qtype, target, rarity, reward)
	return {
		id = "test", type = qtype, target = target, rarity = rarity,
		progress = 0, claimed = false, reward = reward or 100, desc = "test quest",
	}
end

-- ──────────────────────────────────────────────────────────────────────
-- Source contract helpers
-- ──────────────────────────────────────────────────────────────────────

local questSource = fs.readFile("src/server/QuestService.lua")
local gameConfigSource = fs.readFile("src/shared/GameConfig.lua")

return function(describe, it, expect)
	-- ════════════════════════════════════════════════════════════════════
	-- Quest pool shape
	-- ════════════════════════════════════════════════════════════════════
	describe("Quest pool shape", function()
		it("pool has 11 templates", function()
			expect(#POOL).to.equal(11)
		end)

		it("every template has positive target and reward", function()
			for _, t in ipairs(POOL) do
				expect(t.target > 0).to.equal(true)
				expect(t.reward > 0).to.equal(true)
				expect(type(t.desc)).to.equal("string")
			end
		end)

		it("catch_rarity templates gate on Rare(3) / Epic(4) / Legendary(5)", function()
			local rarities = {}
			for _, t in ipairs(POOL) do
				if t.type == "catch_rarity" then
					rarities[t.rarity] = true
				end
			end
			expect(rarities[3]).to.equal(true)
			expect(rarities[4]).to.equal(true)
			expect(rarities[5]).to.equal(true)
		end)

		it("raid_success templates exist (kqd0 raid quest revival)", function()
			local count = 0
			for _, t in ipairs(POOL) do
				if t.type == "raid_success" then count += 1 end
			end
			expect(count).to.equal(2)
		end)

		it("higher-target templates pay more within a type (except catch_rarity)", function()
			-- catch_rarity is exempt by design: its difficulty axis is the
			-- rarity threshold, not the count (target 1 Legendary pays 600
			-- vs target 5 Rare paying 200).
			local byType = {}
			for _, t in ipairs(POOL) do
				if t.type ~= "catch_rarity" then
					byType[t.type] = byType[t.type] or {}
					table.insert(byType[t.type], t)
				end
			end
			for _, list in pairs(byType) do
				table.sort(list, function(a, b) return a.target < b.target end)
				for i = 2, #list do
					expect(list[i].reward > list[i - 1].reward).to.equal(true)
				end
			end
		end)

		it("catch_rarity reward grows with the rarity threshold", function()
			local list = {}
			for _, t in ipairs(POOL) do
				if t.type == "catch_rarity" then
					table.insert(list, t)
				end
			end
			table.sort(list, function(a, b) return a.rarity < b.rarity end)
			for i = 2, #list do
				expect(list[i].reward > list[i - 1].reward).to.equal(true)
			end
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Daily/weekly key formats
	-- ════════════════════════════════════════════════════════════════════
	describe("Quest key formats", function()
		it("daily key is d_<userId>_<year>_<yday>", function()
			expect(dailyKey(123, 2026, 212)).to.equal("d_123_2026_212")
		end)

		it("weekly key anchors to week start (yday - wday + 1)", function()
			-- yday 100, wday 4 → weekStart 97
			expect(weeklyKey(123, 2026, 100, 4)).to.equal("w_123_2026_97")
		end)
		it("weekly key changes across week boundaries", function()
			-- yday 100 (Sunday, wday 1) → weekStart 100; next Sunday yday 107 → 107
			local thisWeek = weeklyKey(123, 2026, 100, 1)
			local nextWeek = weeklyKey(123, 2026, 107, 1)
			expect(thisWeek == nextWeek).to.equal(false)
		end)

		it("weekly key is stable within the same week", function()
			-- yday 100 Sunday (wday 1) and yday 106 Saturday (wday 7) share weekStart 100
			expect(weeklyKey(123, 2026, 100, 1)).to.equal(weeklyKey(123, 2026, 106, 7))
		end)

		it("keys differ per player", function()
			expect(dailyKey(1, 2026, 212) == dailyKey(2, 2026, 212)).to.equal(false)
		end)

		it("seed strips all non-digits from the key", function()
			expect(seedForKey("d_123_2026_212")).to.equal(1232026212)
			expect(seedForKey("w_7_2026_97")).to.equal(7202697)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Distinct-pick rotation
	-- ════════════════════════════════════════════════════════════════════
	describe("Distinct-pick rotation", function()
		it("picks the requested number of distinct templates", function()
			local chosen = pickDistinct(POOL, DAILY_SLOTS, seqDraws({ 1, 2, 3 }))
			expect(#chosen).to.equal(3)
			local types = {}
			for _, q in ipairs(chosen) do
				local key = q.type .. tostring(q.target)
				expect(types[key]).to.equal(nil)
				types[key] = true
			end
		end)

		it("re-draws on collision until distinct", function()
			local chosen = pickDistinct(POOL, 2, seqDraws({ 1, 1, 1, 2 }))
			expect(#chosen).to.equal(2)
			expect(chosen[1].target).never.to.equal(chosen[2].target)
		end)

		it("quest ids are q<position>_<reward>_<target>", function()
			-- draw 3 → POOL[3] (reward 600, target 1); draw 4 → POOL[4] (reward 300, target 1)
			local chosen = pickDistinct(POOL, 2, seqDraws({ 3, 4 }))
			expect(chosen[1].id).to.equal("q1_600_1")
			expect(chosen[2].id).to.equal("q2_300_1")
		end)

		it("new quests start unclaimed at zero progress", function()
			local chosen = pickDistinct(POOL, 1, seqDraws({ 5 }))
			expect(chosen[1].progress).to.equal(0)
			expect(chosen[1].claimed).to.equal(false)
		end)

		it("requesting more than the pool size terminates at pool size", function()
			local chosen = pickDistinct(POOL, 99, seqDraws({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }))
			expect(#chosen).to.equal(#POOL)
		end)

		it("same draw sequence produces the same quests (determinism)", function()
			local a = pickDistinct(POOL, 3, seqDraws({ 7, 2, 9 }))
			local b = pickDistinct(POOL, 3, seqDraws({ 7, 2, 9 }))
			expect(a[1].id).to.equal(b[1].id)
			expect(a[2].id).to.equal(b[2].id)
			expect(a[3].id).to.equal(b[3].id)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Rotation gate (initializeQuests)
	-- ════════════════════════════════════════════════════════════════════
	describe("Rotation gate (initializeQuests)", function()
		it("rolls both lists on first init", function()
			local s = makeSession()
			initializeQuests(s, "d_1_2026_212", "w_1_2026_97", seqDraws({ 1, 2, 3, 4, 5 }))
			expect(s.dailyQuestKey).to.equal("d_1_2026_212")
			expect(#s.dailyQuests).to.equal(DAILY_SLOTS)
			expect(#s.weeklyQuests).to.equal(WEEKLY_SLOTS)
		end)

		it("keeps quests when the key is unchanged", function()
			local s = makeSession()
			initializeQuests(s, "d_1_2026_212", "w_1_2026_97", seqDraws({ 1, 2, 3, 4, 5 }))
			s.dailyQuests[1].progress = 3
			initializeQuests(s, "d_1_2026_212", "w_1_2026_97", seqDraws({ 6, 7, 8, 9, 10 }))
			expect(s.dailyQuests[1].progress).to.equal(3)
		end)

		it("re-rolls when the day key changes", function()
			local s = makeSession()
			initializeQuests(s, "d_1_2026_212", "w_1_2026_97", seqDraws({ 1, 2, 3, 4, 5 }))
			initializeQuests(s, "d_1_2026_213", "w_1_2026_97", seqDraws({ 11, 10, 9, 8, 7 }))
			expect(s.dailyQuestKey).to.equal("d_1_2026_213")
			expect(s.dailyQuests[1].progress).to.equal(0)
			-- weekly untouched (same week key)
			expect(s.weeklyQuestKey).to.equal("w_1_2026_97")
		end)

		it("re-rolls an empty list even with an unchanged key", function()
			local s = makeSession()
			initializeQuests(s, "d_1_2026_212", "w_1_2026_97", seqDraws({ 1, 2, 3, 4, 5 }))
			s.dailyQuests = {}
			initializeQuests(s, "d_1_2026_212", "w_1_2026_97", seqDraws({ 4, 5, 6, 7, 8 }))
			expect(#s.dailyQuests).to.equal(DAILY_SLOTS)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Rarity ordinal mapping
	-- ════════════════════════════════════════════════════════════════════
	describe("Rarity ordinal mapping", function()
		it("maps names to ordinals 1-5 in config order", function()
			expect(RARITY_ORDINAL.Common).to.equal(1)
			expect(RARITY_ORDINAL.Uncommon).to.equal(2)
			expect(RARITY_ORDINAL.Rare).to.equal(3)
			expect(RARITY_ORDINAL.Epic).to.equal(4)
			expect(RARITY_ORDINAL.Legendary).to.equal(5)
		end)

		it("unknown rarity name falls back to 1 (Common)", function()
			local s = makeSession()
			s.dailyQuests = { questOf("catch_rarity", 5, 1) }
			onFishCaught(s, "Mythical")
			expect(s.dailyQuests[1].progress).to.equal(1)
		end)

		it("numeric rarity passes through (legacy callers)", function()
			local s = makeSession()
			s.dailyQuests = { questOf("catch_rarity", 1, 5) }
			onFishCaught(s, 5)
			expect(s.dailyQuests[1].claimed).to.equal(true)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Progress + completion + rewards
	-- ════════════════════════════════════════════════════════════════════
	describe("Progress, completion, and rewards", function()
		it("Rare catch progresses Rare+ quest but not Epic+ quest", function()
			local s = makeSession()
			s.dailyQuests = { questOf("catch_rarity", 5, 3), questOf("catch_rarity", 3, 4) }
			onFishCaught(s, "Rare")
			expect(s.dailyQuests[1].progress).to.equal(1)
			expect(s.dailyQuests[2].progress).to.equal(0)
		end)

		it("Legendary catch progresses every catch_rarity quest", function()
			local s = makeSession()
			s.dailyQuests = { questOf("catch_rarity", 5, 3), questOf("catch_rarity", 3, 4), questOf("catch_rarity", 1, 5) }
			onFishCaught(s, "Legendary")
			expect(s.dailyQuests[1].progress).to.equal(1)
			expect(s.dailyQuests[2].progress).to.equal(1)
			expect(s.dailyQuests[3].claimed).to.equal(true)
		end)

		it("progress clamps at target and grants the reward once", function()
			local s = makeSession(100)
			s.dailyQuests = { questOf("catch_rarity", 2, 3, 200) }
			onFishCaught(s, "Epic")
			expect(s.dailyQuests[1].claimed).to.equal(false)
			onFishCaught(s, "Epic")
			expect(s.dailyQuests[1].claimed).to.equal(true)
			expect(s.dailyQuests[1].progress).to.equal(2)
			expect(s.profile.Coins).to.equal(300)
			expect(s.profile.TotalCoinsEarned).to.equal(200)
			-- further events do not re-grant
			onFishCaught(s, "Epic")
			expect(s.profile.Coins).to.equal(300)
		end)

		it("reward grant clamps at MAX_COINS", function()
			local s = makeSession(MAX_COINS - 50)
			s.dailyQuests = { questOf("raid_success", 1, nil, 300) }
			onStealAttempt(s, true)
			expect(s.profile.Coins).to.equal(MAX_COINS)
		end)

		it("income accumulates across events and completes mid-stream", function()
			local s = makeSession()
			s.dailyQuests = { questOf("income_earned", 500, nil, 250) }
			onIncomeEarned(s, 200)
			expect(s.dailyQuests[1].claimed).to.equal(false)
			onIncomeEarned(s, 400) -- 600 total, clamps to 500
			expect(s.dailyQuests[1].progress).to.equal(500)
			expect(s.dailyQuests[1].claimed).to.equal(true)
			expect(s.profile.Coins).to.equal(250)
		end)

		it("store and sell events accumulate their amounts", function()
			local s = makeSession()
			s.dailyQuests = { questOf("store_count", 10, nil, 150) }
			s.weeklyQuests = { questOf("sell_value", 1000, nil, 200) }
			onFishStored(s, 7)
			onFishStored(s, 5) -- 12 total, clamps to 10
			expect(s.dailyQuests[1].progress).to.equal(10)
			expect(s.dailyQuests[1].claimed).to.equal(true)
			onFishSold(s, 400)
			expect(s.weeklyQuests[1].progress).to.equal(400)
			expect(s.weeklyQuests[1].claimed).to.equal(false)
		end)

		it("failed steal attempts do not progress raid quests", function()
			local s = makeSession()
			s.dailyQuests = { questOf("raid_success", 1, nil, 300) }
			onStealAttempt(s, false)
			expect(s.dailyQuests[1].progress).to.equal(0)
		end)

		it("legacy steal_count quests still complete (kqd0 backward compat)", function()
			local s = makeSession()
			s.dailyQuests = { questOf("steal_count", 1, nil, 100) }
			onStealAttempt(s, true)
			expect(s.dailyQuests[1].claimed).to.equal(true)
		end)

		it("one event can complete quests in both lists", function()
			local s = makeSession(0)
			s.dailyQuests = { questOf("raid_success", 1, nil, 300) }
			s.weeklyQuests = { questOf("raid_success", 3, nil, 750) }
			onStealAttempt(s, true)
			expect(s.dailyQuests[1].claimed).to.equal(true)
			expect(s.weeklyQuests[1].progress).to.equal(1)
			expect(s.profile.Coins).to.equal(300)
		end)

		it("nil session is a safe no-op", function()
			expect(onFishCaught(nil, "Rare")).to.equal(false)
		end)
	end)

	-- ════════════════════════════════════════════════════════════════════
	-- Source contract verification
	-- ════════════════════════════════════════════════════════════════════
	describe("Source contract verification", function()
		it("QuestService pool keeps the 11 live templates", function()
			expect(questSource:find('{ type = "catch_rarity", target = 5,  rarity = 3, reward = 200', 1, true)).to.be.a("number")
			expect(questSource:find('{ type = "raid_success", target = 1, reward = 300', 1, true)).to.be.a("number")
			expect(questSource:find('{ type = "income_earned", target = 1500, reward = 450', 1, true)).to.be.a("number")
			expect(questSource:find('{ type = "sell_value",   target = 2500, reward = 400', 1, true)).to.be.a("number")
		end)

		it("QuestService keys use UTC dates", function()
			expect(questSource:find('os.date("!*t")', 1, true)).to.be.a("number")
		end)

		it("QuestService derives the seed by stripping non-digits", function()
			expect(questSource:find('string.gsub(dKey, "%D", "")', 1, true)).to.be.a("number")
			expect(questSource:find("Random.new(seed)", 1, true)).to.be.a("number")
		end)

		it("QuestService re-rolls on key change OR empty list", function()
			expect(questSource:find("session.dailyQuestKey ~= dKey or #session.dailyQuests == 0", 1, true)).to.be.a("number")
		end)

		it("N4: rewards route through profile.Coins + clampCoins, never session.cash", function()
			expect(questSource:find("session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + q.reward)", 1, true)).to.be.a("number")
			-- session.cash may only appear in COMMENTS (the N4 fix notes); no live usage
			for line in questSource:gmatch("[^\n]+") do
				local pos = line:find("session%.cash")
				if pos then
					local commentPos = line:find("%-%-")
					expect(commentPos ~= nil and commentPos < pos).to.equal(true)
				end
			end
		end)

		it("lifetime earnings track quest rewards", function()
			expect(questSource:find("session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + q.reward", 1, true)).to.be.a("number")
		end)

		it("gt44: quest rewards are audit-logged", function()
			expect(questSource:find("auditLog = deps.auditLog", 1, true)).to.be.a("number")
			expect(questSource:find("auditLog.logQuestReward(session.player, q.desc, q.reward)", 1, true)).to.be.a("number")
		end)

		it("rarity ordinal derives from GameConfig.Rarities order (lunp)", function()
			expect(questSource:find("RARITY_ORDINAL[rarity.name] = i", 1, true)).to.be.a("number")
			expect(questSource:find("for i, rarity in ipairs(GameConfig.Rarities)", 1, true)).to.be.a("number")
		end)

		it("onStealAttempt matches raid_success AND legacy steal_count", function()
			expect(questSource:find('q.type == "raid_success" or q.type == "steal_count"', 1, true)).to.be.a("number")
		end)

		it("failed steals return before progressing", function()
			expect(questSource:find("if not success then", 1, true)).to.be.a("number")
		end)

		it("quest rate limit is wired live (xdt)", function()
			expect(questSource:find('antiExploit.checkRate(player, "quest")', 1, true)).to.be.a("number")
			expect(questSource:find("local antiExploit = deps.antiExploit", 1, true)).to.be.a("number")
		end)

		it("GameConfig quest slots: 3 daily, 2 weekly", function()
			expect(gameConfigSource:find("DailySlots = 3", 1, true)).to.be.a("number")
			expect(gameConfigSource:find("WeeklySlots = 2", 1, true)).to.be.a("number")
		end)
	end)
end