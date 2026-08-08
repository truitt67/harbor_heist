-- Economy / persistence consistency contracts (harborheist-2f1p).
--
-- Deep-review pass 3 (fresh-eyes, glm-5.2 + kimi-k3) found three residual
-- defect classes that survived the first two review rounds:
--
--   1. TotalCoinsEarned was written WITHOUT clampCoins at every grant site
--      (Coins was clamped; the lifetime-earned tracker was not). Unbounded
--      drift past MAX_COINS + float accumulation; sanitize only floored,
--      never upper-bounded, so a corrupted huge value round-tripped forever.
--   2. Equipment.BaitInventory existed in PlayerProfile.default() but was
--      missing from DataManager.sanitize()'s whitelist — the field silently
--      reverted to default on every save/load round-trip (pattern #2:
--      sanitize-drops-field). PRD Open Decision #5 may add bait-quantity
--      mechanics that mutate it, so the round-trip must exist BEFORE that
--      ships.
--   3. Two RequestToggleRaidOptIn:InvokeServer() calls in the client were
--      never pcall-wrapped — the oqbp sweep pcalled seven other InvokeServer
--      sites but missed both raid opt-in toggles (panel + aquarium twins).
--      An unprotected throw kills the Activated handler thread for the rest
--      of the session.
--
-- These specs pin the fixes as source contracts so any regression fails
-- the pure bucket.

local fs = require("@lune/fs")

-- Count non-overlapping plain-text occurrences of `needle` in `haystack`.
local function countOccurrences(haystack, needle)
	local count = 0
	local init = 1
	while true do
		local found = haystack:find(needle, init, true)
		if not found then
			break
		end
		count += 1
		init = found + 1
	end
	return count
end

return function(describe, it, expect)
	-- ──────────────────────────────────────────────────────────────────
	-- Contract 1: every TotalCoinsEarned grant routes through clampCoins
	-- ──────────────────────────────────────────────────────────────────

	describe("Source contract: TotalCoinsEarned is clamped at every grant site", function()
		local clampedNeedle = "TotalCoinsEarned = PlayerProfile.clampCoins("

		local grantFiles = {
			"src/server/AquariumService.lua", -- claim + sell-all (2 sites)
			"src/server/FishInventoryService.lua", -- single-fish sell
			"src/server/RaidService.lua", -- fenced raid payout
			"src/server/QuestService.lua", -- quest reward
			"src/server/CollectionService.lua", -- milestone reward
		}

		it("no bare (unclamped) TotalCoinsEarned arithmetic write remains", function()
			for _, path in ipairs(grantFiles) do
				local source = fs.readFile(path)
				-- Every line that writes TotalCoinsEarned via arithmetic must
				-- go through clampCoins. Scan for the legacy patterns:
				--   profile.TotalCoinsEarned = profile.TotalCoinsEarned + X
				--   profile.TotalCoinsEarned += X
				expect(source:find("TotalCoinsEarned = session.profile.TotalCoinsEarned +", 1, true)).to.equal(nil)
				expect(source:find("TotalCoinsEarned = profile.TotalCoinsEarned +", 1, true)).to.equal(nil)
				expect(source:find("TotalCoinsEarned = attackerSession.profile.TotalCoinsEarned +", 1, true)).to.equal(nil)
				expect(source:find("TotalCoinsEarned +=", 1, true)).to.equal(nil)
			end
		end)

		it("each grant file contains the clampCoins-wrapped write", function()
			for _, path in ipairs(grantFiles) do
				local source = fs.readFile(path)
				expect(countOccurrences(source, clampedNeedle) >= 1).to.equal(true)
			end
		end)

		it("AquariumService clamps BOTH grant sites (claim + sell-all)", function()
			local source = fs.readFile("src/server/AquariumService.lua")
			expect(countOccurrences(source, clampedNeedle)).to.equal(2)
		end)
	end)

	describe("Source contract: sanitize upper-bounds TotalCoinsEarned", function()
		it("DataManager.sanitize routes TotalCoinsEarned through clampCoins", function()
			local source = fs.readFile("src/server/DataManager.lua")
			expect(source:find("clean.TotalCoinsEarned = PlayerProfile.clampCoins(", 1, true)).to.be.a("number")
		end)

		it("legacy floor-only sanitize form is gone", function()
			local source = fs.readFile("src/server/DataManager.lua")
			expect(source:find("clean.TotalCoinsEarned = math.max(0, math.floor(", 1, true)).to.equal(nil)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Contract 2: sanitize round-trips BaitInventory (pattern #2 guard)
	-- ──────────────────────────────────────────────────────────────────

	describe("Source contract: sanitize round-trips Equipment.BaitInventory", function()
		it("schema still declares BaitInventory", function()
			local source = fs.readFile("src/shared/PlayerProfile.lua")
			expect(source:find("BaitInventory = { level = 1, quantity = -1 }", 1, true)).to.be.a("number")
		end)

		it("sanitize copies BaitInventory with type-checked fields", function()
			local source = fs.readFile("src/server/DataManager.lua")
			expect(source:find('type(eq.BaitInventory) == "table"', 1, true)).to.be.a("number")
			expect(source:find("clean.Equipment.BaitInventory = {", 1, true)).to.be.a("number")
			expect(source:find("math.floor(bi.quantity)", 1, true)).to.be.a("number")
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Contract 3: zero unprotected InvokeServer calls in the client
	-- ──────────────────────────────────────────────────────────────────

	describe("Source contract: raid opt-in InvokeServer sites are pcall-wrapped", function()
		it("both RequestToggleRaidOptIn invokes are inside pcall", function()
			local source = fs.readFile("src/client/init.client.lua")
			local wrapped = "pcall(function()\n\t\tRemotes.RequestToggleRaidOptIn:InvokeServer()\n\tend)"
			expect(countOccurrences(source, wrapped)).to.equal(2)
		end)

		it("no bare RequestToggleRaidOptIn invoke remains", function()
			local source = fs.readFile("src/client/init.client.lua")
			-- Bare form = the invoke NOT immediately preceded by the pcall
			-- opener. Total invokes minus wrapped invokes must be zero.
			local totalInvokes = countOccurrences(source, "Remotes.RequestToggleRaidOptIn:InvokeServer()")
			local wrappedInvokes = countOccurrences(
				source,
				"pcall(function()\n\t\tRemotes.RequestToggleRaidOptIn:InvokeServer()\n\tend)"
			)
			expect(totalInvokes).to.equal(wrappedInvokes)
		end)
	end)
end
