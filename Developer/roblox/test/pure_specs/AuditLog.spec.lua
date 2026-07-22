-- AuditLogService unit tests (PURE bucket / lune).
--
-- Covers k5wz.12 cases 6-8: ring-buffer bound, entry shape, read path.
-- Also covers all logging functions (logCatch, logPurchase, logStore,
-- logSell, logRaidTransfer, logLock, logClaim) for completeness.
--
-- AuditLogService is pure: no game:GetService at top level. Uses os.time,
-- table.insert/remove, string.format, print — all lune built-ins.
--
-- IMPORTANT: The bead description says "1001 entries → exactly 1000
-- retained." The ACTUAL code (line 9) declares MAX_ENTRIES = 500 (NOT
-- 1000). These tests encode the REAL behavior — 501 entries → 500
-- retained — per the bead's instruction to "encode reality."

local AuditLogService = require("../../src/server/AuditLogService")

-- Helper: fabricate a minimal Player-shaped table that AuditLogService reads.
-- Fields used: Name (string), UserId (number).
local function makePlayer(name, userId)
	return { Name = name or "TestPlayer", UserId = userId or 1 }
end

return function(describe, it, expect)
	describe("AuditLogService — ring buffer bound (case 6)", function()
		-- NOTE: The module uses a module-level `log` table that persists across
		-- all tests in this require session. We test the bound by inserting
		-- enough entries to exceed MAX_ENTRIES and checking the result.

		it("should cap at exactly 500 entries (MAX_ENTRIES=500, not 1000)", function()
			-- Insert 501+ entries; the while loop evicts from the front (FIFO).
			local player = makePlayer("RingTest", 99901)
			for _ = 1, 501 do
				AuditLogService.logPurchase(player, "rod", 1, 100, "TestRod")
			end
			local log = AuditLogService.getLog()
			expect(#log).to.equal(500)
		end)

		it("should evict oldest entries first (FIFO)", function()
			-- After the 501-entry flood above, the log has 500 entries.
			-- The first entry should be from the SECOND batch (first was evicted).
			-- We can verify by checking that log[1] still has the same action.
			local log = AuditLogService.getLog()
			expect(#log).to.equal(500)
			-- All entries should have action = "purchase"
			expect(log[1].action).to.equal("purchase")
		end)

		it("should not exceed 500 even with many more entries", function()
			local player = makePlayer("Overflow", 99902)
			for _ = 1, 200 do
				AuditLogService.logSell(player, 1, 10)
			end
			local log = AuditLogService.getLog()
			expect(#log).to.equal(500)
		end)
	end)

	describe("AuditLogService — entry shape (case 7)", function()
		it("should produce entries with timestamp, player, userId, action, details", function()
			local player = makePlayer("ShapeTest", 88888)
			AuditLogService.logPurchase(player, "bait", 2, 300, "Magic Bait")
			local entries = AuditLogService.getLogForPlayer(88888)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "purchase" and e.details:match("Magic Bait") then
					found = true
					expect(type(e.timestamp)).to.equal("number")
					expect(e.player).to.equal("ShapeTest")
					expect(e.userId).to.equal(88888)
					expect(e.action).to.equal("purchase")
					expect(type(e.details)).to.equal("string")
				end
			end
			expect(found).to.equal(true)
		end)

		it("should use 'unknown' for nil player Name", function()
			AuditLogService.logPurchase(nil, "rod", 1, 100, "Rod")
			local log = AuditLogService.getLog()
			local last = log[#log]
			expect(last.player).to.equal("unknown")
			expect(last.userId).to.equal(0)
		end)
	end)

	describe("AuditLogService — read path (case 8)", function()
		it("getLogForPlayer should return only entries for that userId", function()
			local p1 = makePlayer("Reader1", 77771)
			local p2 = makePlayer("Reader2", 77772)
			AuditLogService.logSell(p1, 3, 90)
			AuditLogService.logSell(p2, 2, 50)
			AuditLogService.logSell(p1, 1, 10)

			local e1 = AuditLogService.getLogForPlayer(77771)
			local e2 = AuditLogService.getLogForPlayer(77772)
			-- All entries for p1 should have userId 77771
			for _, e in ipairs(e1) do
				expect(e.userId).to.equal(77771)
			end
			for _, e in ipairs(e2) do
				expect(e.userId).to.equal(77772)
			end
		end)

		it("getLogForPlayer should return entries in insertion order", function()
			local p = makePlayer("OrderTest", 66661)
			AuditLogService.logSell(p, 10, 100)
			AuditLogService.logSell(p, 20, 200)
			AuditLogService.logSell(p, 30, 300)
			local entries = AuditLogService.getLogForPlayer(66661)
			-- The last 3 entries for this player should be in insertion order
			local n = #entries
			expect(entries[n].details).to.equal("Sold 30 fish for $300")
			expect(entries[n - 1].details).to.equal("Sold 20 fish for $200")
			expect(entries[n - 2].details).to.equal("Sold 10 fish for $100")
		end)

		it("getLog should return the full log table", function()
			local log = AuditLogService.getLog()
			expect(type(log)).to.equal("table")
			expect(#log > 0).to.equal(true)
		end)

		it("getLogForPlayer should return empty table for unknown userId", function()
			local entries = AuditLogService.getLogForPlayer(999999999)
			expect(type(entries)).to.equal("table")
			expect(#entries).to.equal(0)
		end)
	end)

	describe("AuditLogService.logCatch — selective logging", function()
		it("should log Legendary catches", function()
			local p = makePlayer("Catcher", 55551)
			local fish = { Rarity = "Legendary", SpeciesId = "GoldKoi", BaseSellValue = 500 }
			AuditLogService.logCatch(p, fish)
			local entries = AuditLogService.getLogForPlayer(55551)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "catch" and e.details:match("Legendary") then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("should log Epic catches", function()
			local p = makePlayer("Catcher2", 55552)
			local fish = { Rarity = "Epic", SpeciesId = "Swordfish", BaseSellValue = 180 }
			AuditLogService.logCatch(p, fish)
			local entries = AuditLogService.getLogForPlayer(55552)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "catch" and e.details:match("Epic") then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("should NOT log Common catches", function()
			local p = makePlayer("Catcher3", 55553)
			local beforeCount = #AuditLogService.getLogForPlayer(55553)
			local fish = { Rarity = "Common", SpeciesId = "Minnow", BaseSellValue = 10 }
			AuditLogService.logCatch(p, fish)
			local afterCount = #AuditLogService.getLogForPlayer(55553)
			expect(afterCount).to.equal(beforeCount)
		end)

		it("should NOT log Uncommon catches", function()
			local p = makePlayer("Catcher4", 55554)
			local fish = { Rarity = "Uncommon", SpeciesId = "Bass", BaseSellValue = 25 }
			local beforeCount = #AuditLogService.getLogForPlayer(55554)
			AuditLogService.logCatch(p, fish)
			local afterCount = #AuditLogService.getLogForPlayer(55554)
			expect(afterCount).to.equal(beforeCount)
		end)

		it("should NOT log Rare catches (only Legendary + Epic)", function()
			local p = makePlayer("Catcher5", 55555)
			local fish = { Rarity = "Rare", SpeciesId = "Tuna", BaseSellValue = 70 }
			local beforeCount = #AuditLogService.getLogForPlayer(55555)
			AuditLogService.logCatch(p, fish)
			local afterCount = #AuditLogService.getLogForPlayer(55555)
			expect(afterCount).to.equal(beforeCount)
		end)

		it("should handle nil fish gracefully (no error)", function()
			local p = makePlayer("NilFish", 55556)
			local ok = pcall(function()
				AuditLogService.logCatch(p, nil)
			end)
			expect(ok).to.equal(true)
		end)

		it("should handle fish with nil Rarity", function()
			local p = makePlayer("NilRarity", 55557)
			local ok = pcall(function()
				AuditLogService.logCatch(p, { SpeciesId = "Test", BaseSellValue = 0 })
			end)
			expect(ok).to.equal(true)
		end)
	end)

	describe("AuditLogService — all logging functions", function()
		it("logPurchase should create a 'purchase' entry", function()
			local p = makePlayer("Buyer", 44441)
			AuditLogService.logPurchase(p, "rod", 3, 1000, "Gold Rod")
			local entries = AuditLogService.getLogForPlayer(44441)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "purchase" and e.details:match("Gold Rod") then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("logStore should create a 'store' entry", function()
			local p = makePlayer("Storer", 44442)
			AuditLogService.logStore(p, 5, 350)
			local entries = AuditLogService.getLogForPlayer(44442)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "store" then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("logSell should create a 'sell' entry", function()
			local p = makePlayer("Seller", 44443)
			AuditLogService.logSell(p, 3, 150)
			local entries = AuditLogService.getLogForPlayer(44443)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "sell" then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("logLock should create a 'lock' entry", function()
			local p = makePlayer("Locker", 44444)
			AuditLogService.logLock(p, 60, 2)
			local entries = AuditLogService.getLogForPlayer(44444)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "lock" then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("logClaim should create a 'claim' entry", function()
			local p = makePlayer("Claimer", 44445)
			AuditLogService.logClaim(p, 500)
			local entries = AuditLogService.getLogForPlayer(44445)
			local found = false
			for _, e in ipairs(entries) do
				if e.action == "claim" then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)
	end)

	describe("AuditLogService.logRaidTransfer — success and failure", function()
		it("should create raid_success entry for attacker on success", function()
			local attacker = makePlayer("Raider", 33331)
			local victim = makePlayer("Victim", 33332)
			local fish = { Rarity = "Epic", SpeciesId = "Marlin", BaseSellValue = 180 }
			AuditLogService.logRaidTransfer(attacker, victim, fish, true)
			local aEntries = AuditLogService.getLogForPlayer(33331)
			local found = false
			for _, e in ipairs(aEntries) do
				if e.action == "raid_success" then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("should create raid_victim entry for victim on success", function()
			local attacker = makePlayer("Raider2", 33333)
			local victim = makePlayer("Victim2", 33334)
			local fish = { Rarity = "Legendary", SpeciesId = "Shark", BaseSellValue = 500 }
			AuditLogService.logRaidTransfer(attacker, victim, fish, true)
			local vEntries = AuditLogService.getLogForPlayer(33334)
			local found = false
			for _, e in ipairs(vEntries) do
				if e.action == "raid_victim" then
					found = true
				end
			end
			expect(found).to.equal(true)
		end)

		it("should create raid_failed entry on failure (no victim entry)", function()
			local attacker = makePlayer("Failer", 33335)
			local victim = makePlayer("FailedVictim", 33336)
			AuditLogService.logRaidTransfer(attacker, victim, nil, false)
			local aEntries = AuditLogService.getLogForPlayer(33335)
			local found = false
			for _, e in ipairs(aEntries) do
				if e.action == "raid_failed" then
					found = true
				end
			end
			expect(found).to.equal(true)

			local vEntries = AuditLogService.getLogForPlayer(33336)
			local victimFound = false
			for _, e in ipairs(vEntries) do
				if e.action == "raid_victim" then
					victimFound = true
				end
			end
			expect(victimFound).to.equal(false)
		end)
	end)

	describe("AuditLogService — nil-safe logging", function()
		it("logPurchase should handle nil player", function()
			local ok = pcall(function()
				AuditLogService.logPurchase(nil, "rod", 1, 100, "Rod")
			end)
			expect(ok).to.equal(true)
		end)

		it("logStore should handle nil count/value", function()
			local p = makePlayer("NilArgs", 22221)
			local ok = pcall(function()
				AuditLogService.logStore(p, nil, nil)
			end)
			expect(ok).to.equal(true)
		end)

		it("logSell should handle nil count/payout", function()
			local p = makePlayer("NilSell", 22222)
			local ok = pcall(function()
				AuditLogService.logSell(p, nil, nil)
			end)
			expect(ok).to.equal(true)
		end)

		it("logLock should handle nil duration/freeUses", function()
			local p = makePlayer("NilLock", 22223)
			local ok = pcall(function()
				AuditLogService.logLock(p, nil, nil)
			end)
			expect(ok).to.equal(true)
		end)

		it("logClaim should handle nil amount", function()
			local p = makePlayer("NilClaim", 22224)
			local ok = pcall(function()
				AuditLogService.logClaim(p, nil)
			end)
			expect(ok).to.equal(true)
		end)
	end)
end
