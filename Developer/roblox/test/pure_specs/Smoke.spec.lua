-- Smoke test for the pure-bucket (lune) test runner.
-- Verifies that the test framework works and that pure modules load.
--
-- This spec uses the test framework globals (describe/it/expect) injected
-- by test/pure_runner.luau. It requires real modules via lune filesystem
-- paths (NOT game:GetService), which works because these modules have no
-- Roblox API calls at the top level.

return function(describe, it, expect)
	describe("Lune test framework", function()
		it("should provide describe/it/expect", function()
			expect(describe).to.be.a("function")
			expect(it).to.be.a("function")
			expect(expect).to.be.a("function")
		end)

		it("should support equality assertions", function()
			expect(1 + 1).to.equal(2)
			expect("hello").to.equal("hello")
		end)

		it("should support negation via never", function()
			expect(1).never.to.equal(2)
			expect(true).never.to.equal(false)
		end)

		it("should support type assertions", function()
			expect({}).to.be.a("table")
			expect("string").to.be.a("string")
		end)
	end)

	describe("AntiExploitService (pure module)", function()
		local AntiExploit = require("../../src/server/AntiExploitService")

		it("should load without Roblox globals", function()
			expect(AntiExploit).to.be.a("table")
		end)

		it("should expose checkRate function", function()
			expect(AntiExploit.checkRate).to.be.a("function")
		end)

		it("should reject nil player", function()
			local ok, reason = AntiExploit.checkRate(nil, "cast")
			expect(ok).to.equal(false)
			expect(reason).to.equal("no_player")
		end)

		it("should reject orphaned player (nil Parent)", function()
			local fakePlayer = { Name = "Test", UserId = 1, Parent = nil }
			local ok, reason = AntiExploit.checkRate(fakePlayer, "cast")
			expect(ok).to.equal(false)
			expect(reason).to.equal("no_player")
		end)

		it("should allow first call within rate limit", function()
			local fakePlayer = { Name = "Test", UserId = 2, Parent = true }
			local ok = AntiExploit.checkRate(fakePlayer, "cast")
			expect(ok).to.equal(true)
		end)

		it("should rate-limit after maxCalls exceeded", function()
			local fakePlayer = { Name = "Spammer", UserId = 3, Parent = true }
			-- maxCalls=5, windowSeconds=10 for "cast"
			for _ = 1, 5 do
				AntiExploit.checkRate(fakePlayer, "cast")
			end
			local ok, reason = AntiExploit.checkRate(fakePlayer, "cast")
			expect(ok).to.equal(false)
			expect(reason).to.equal("rate_limited")
		end)

		it("should reject unknown action gracefully", function()
			local fakePlayer = { Name = "Test", UserId = 4, Parent = true }
			local ok = AntiExploit.checkRate(fakePlayer, "nonexistent_action")
			expect(ok).to.equal(true)
		end)

		it("should expose logSuspicious and getLog", function()
			expect(AntiExploit.logSuspicious).to.be.a("function")
			expect(AntiExploit.getLog).to.be.a("function")
		end)

		it("should clear log by userId", function()
			local fakePlayer = { Name = "Test", UserId = 5, Parent = true }
			AntiExploit.logSuspicious(fakePlayer, "test", "test reason")
			expect(#AntiExploit.getLog(5)).to.be.ok()
			AntiExploit.clearLog(5)
			expect(#AntiExploit.getLog(5)).to.equal(0)
		end)
	end)

	describe("OnboardingService (pure module)", function()
		local Onboarding = require("../../src/server/OnboardingService")

		it("should load without Roblox globals", function()
			expect(Onboarding).to.be.a("table")
		end)

		it("should expose mark function", function()
			expect(Onboarding.mark).to.be.a("function")
		end)

		it("should flip flag on first call", function()
			local session = {
				profile = {
					Onboarding = {
						HasCompletedIntro = false,
						HasCaughtFirstFish = false,
						HasStoredFirstFish = false,
						HasClaimedIncome = false,
						HasSeenRaidExplanation = false,
						HasSeenSellStoreComparison = false,
					},
				},
			}
			local flipped = Onboarding.mark(session, "HasCaughtFirstFish")
			expect(flipped).to.equal(true)
			expect(session.profile.Onboarding.HasCaughtFirstFish).to.equal(true)
		end)

		it("should be idempotent (no re-flip)", function()
			local session = {
				profile = {
					Onboarding = {
						HasCompletedIntro = true,
						HasCaughtFirstFish = false,
						HasStoredFirstFish = false,
						HasClaimedIncome = false,
						HasSeenRaidExplanation = false,
						HasSeenSellStoreComparison = false,
					},
				},
			}
			Onboarding.mark(session, "HasCompletedIntro")
			local flipped = Onboarding.mark(session, "HasCompletedIntro")
			expect(flipped).to.equal(false)
		end)

		it("should reject unknown flag", function()
			local session = { profile = { Onboarding = {} } }
			local result = Onboarding.mark(session, "BogusFlag")
			expect(result).to.equal(false)
		end)

		it("should return false for nil session", function()
			local result = Onboarding.mark(nil, "HasCompletedIntro")
			expect(result).to.equal(false)
		end)

		it("hasCompletedCoreLoop should require intro+catch+store", function()
			local session = {
				profile = {
					Onboarding = {
						HasCompletedIntro = true,
						HasCaughtFirstFish = true,
						HasStoredFirstFish = false,
						HasClaimedIncome = false,
						HasSeenRaidExplanation = false,
						HasSeenSellStoreComparison = false,
					},
				},
			}
			expect(Onboarding.hasCompletedCoreLoop(session)).to.equal(false)
			Onboarding.mark(session, "HasStoredFirstFish")
			expect(Onboarding.hasCompletedCoreLoop(session)).to.equal(true)
		end)

		it("hasCompletedFirstSession should also require income", function()
			local session = {
				profile = {
					Onboarding = {
						HasCompletedIntro = true,
						HasCaughtFirstFish = true,
						HasStoredFirstFish = true,
						HasClaimedIncome = false,
						HasSeenRaidExplanation = false,
						HasSeenSellStoreComparison = false,
					},
				},
			}
			expect(Onboarding.hasCompletedFirstSession(session)).to.equal(false)
			Onboarding.mark(session, "HasClaimedIncome")
			expect(Onboarding.hasCompletedFirstSession(session)).to.equal(true)
		end)
	end)

	describe("AuditLogService (pure module)", function()
		local Audit = require("../../src/server/AuditLogService")

		it("should load without Roblox globals", function()
			expect(Audit).to.be.a("table")
		end)

		it("should expose logging functions", function()
			expect(Audit.logPurchase).to.be.a("function")
			expect(Audit.logCatch).to.be.a("function")
			expect(Audit.logSell).to.be.a("function")
		end)

		it("should record purchase entries", function()
			local player = { Name = "Buyer", UserId = 100 }
			Audit.logPurchase(player, "rod", 2, 500, "Silver Rod")
			local entries = Audit.getLogForPlayer(100)
			expect(#entries).to.be.ok()
			expect(entries[1].action).to.equal("purchase")
		end)

		it("should getLog (full log)", function()
			expect(Audit.getLog).to.be.a("function")
			local log = Audit.getLog()
			expect(log).to.be.a("table")
		end)
	end)
end
