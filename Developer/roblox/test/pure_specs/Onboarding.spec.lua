-- OnboardingService unit tests (PURE bucket / lune).
--
-- Covers k5wz.12 cases 4-5: idempotence, flag acceptance, unknown flag
-- rejection, persistence shape, getFlags shallow-copy behavior, and the
-- hasCompletedCoreLoop / hasCompletedFirstSession composite checks.
--
-- OnboardingService is pure: no game:GetService at top level. The only
-- Roblox API access (stateSync.push, session.player.Parent) is inside
-- mark() behind nil guards, so it's safe to exercise without a DataModel.

local OnboardingService = require("../../src/server/OnboardingService")

-- Helper: create a minimal session with a fresh Onboarding profile.
local function makeSession(overrides)
	local ob = {
		HasCompletedIntro = false,
		HasCaughtFirstFish = false,
		HasStoredFirstFish = false,
		HasClaimedIncome = false,
		HasSeenRaidExplanation = false,
		HasSeenSellStoreComparison = false,
	}
	if overrides then
		for k, v in pairs(overrides) do
			ob[k] = v
		end
	end
	return { profile = { Onboarding = ob } }
end

return function(describe, it, expect)
	describe("OnboardingService.mark — idempotence (case 4)", function()
		it("should flip a flag from false to true on first call", function()
			local session = makeSession()
			local flipped = OnboardingService.mark(session, "HasCaughtFirstFish")
			expect(flipped).to.equal(true)
			expect(session.profile.Onboarding.HasCaughtFirstFish).to.equal(true)
		end)

		it("should return false (not flip) on second call to same flag", function()
			local session = makeSession({ HasCaughtFirstFish = true })
			local flipped = OnboardingService.mark(session, "HasCaughtFirstFish")
			expect(flipped).to.equal(false)
			expect(session.profile.Onboarding.HasCaughtFirstFish).to.equal(true)
		end)

		it("should not produce an error on repeated calls", function()
			local session = makeSession()
			OnboardingService.mark(session, "HasCompletedIntro")
			local ok2 = pcall(function()
				OnboardingService.mark(session, "HasCompletedIntro")
			end)
			expect(ok2).to.equal(true)
		end)

		it("should not re-set a flag that is already true", function()
			local session = makeSession({ HasCompletedIntro = true })
			local before = session.profile.Onboarding.HasCompletedIntro
			OnboardingService.mark(session, "HasCompletedIntro")
			expect(session.profile.Onboarding.HasCompletedIntro).to.equal(before)
		end)
	end)

	describe("OnboardingService.mark — all known flags accepted (case 4)", function()
		local knownFlags = {
			"HasCompletedIntro",
			"HasCaughtFirstFish",
			"HasStoredFirstFish",
			"HasClaimedIncome",
			"HasSeenRaidExplanation",
			"HasSeenSellStoreComparison",
		}
		for _, flag in ipairs(knownFlags) do
			it(("should accept flag '%s'"):format(flag), function()
				local session = makeSession()
				local flipped = OnboardingService.mark(session, flag)
				expect(flipped).to.equal(true)
				expect(session.profile.Onboarding[flag]).to.equal(true)
			end)
		end
	end)

	describe("OnboardingService.mark — unknown flag rejected (case 4)", function()
		it("should return false for a bogus flag name", function()
			local session = makeSession()
			local result = OnboardingService.mark(session, "BogusFlagName")
			expect(result).to.equal(false)
		end)

		it("should not create a new key in Onboarding for a bogus flag", function()
			local session = makeSession()
			OnboardingService.mark(session, "DoesNotExist")
			expect(session.profile.Onboarding.DoesNotExist).to.equal(nil)
		end)

		it("should return false for nil flag", function()
			local session = makeSession()
			expect(OnboardingService.mark(session, nil)).to.equal(false)
		end)

		it("should return false for empty string flag", function()
			local session = makeSession()
			expect(OnboardingService.mark(session, "")).to.equal(false)
		end)

		it("should return false for numeric flag", function()
			local session = makeSession()
			expect(OnboardingService.mark(session, 123)).to.equal(false)
		end)
	end)

	describe("OnboardingService.mark — nil/invalid session safety", function()
		it("should return false for nil session", function()
			expect(OnboardingService.mark(nil, "HasCompletedIntro")).to.equal(false)
		end)

		it("should return false for session without profile", function()
			expect(OnboardingService.mark({}, "HasCompletedIntro")).to.equal(false)
		end)

		it("should return false for session without Onboarding table", function()
			local session = { profile = {} }
			expect(OnboardingService.mark(session, "HasCompletedIntro")).to.equal(false)
		end)
	end)

	describe("OnboardingService.getFlags — shallow copy behavior", function()
		it("should return a table with all known flags", function()
			local session = makeSession()
			local flags = OnboardingService.getFlags(session)
			expect(flags.HasCompletedIntro).to.equal(false)
			expect(flags.HasCaughtFirstFish).to.equal(false)
			expect(flags.HasStoredFirstFish).to.equal(false)
			expect(flags.HasClaimedIncome).to.equal(false)
			expect(flags.HasSeenRaidExplanation).to.equal(false)
			expect(flags.HasSeenSellStoreComparison).to.equal(false)
		end)

		it("should reflect flagged state correctly", function()
			local session = makeSession({ HasCaughtFirstFish = true, HasClaimedIncome = true })
			local flags = OnboardingService.getFlags(session)
			expect(flags.HasCaughtFirstFish).to.equal(true)
			expect(flags.HasClaimedIncome).to.equal(true)
			expect(flags.HasCompletedIntro).to.equal(false)
		end)

		it("should return a SHALLOW COPY — mutating result does not affect profile", function()
			local session = makeSession()
			local flags = OnboardingService.getFlags(session)
			flags.HasCompletedIntro = true
			expect(session.profile.Onboarding.HasCompletedIntro).to.equal(false)
		end)

		it("should return empty table for nil session", function()
			local flags = OnboardingService.getFlags(nil)
			expect(type(flags)).to.equal("table")
			local count = 0
			for _ in pairs(flags) do count = count + 1 end
			expect(count).to.equal(0)
		end)

		it("should return empty table for session without Onboarding", function()
			local session = { profile = {} }
			local flags = OnboardingService.getFlags(session)
			expect(type(flags)).to.equal("table")
		end)

		it("should treat non-boolean true values as false (strict == equality)", function()
			-- REAL BEHAVIOR: getFlags uses ob[flag] == true (strict equality).
			-- In Luau, 1 == true is false (not truthy-coerced). This means
			-- a corrupt profile with numeric 1 instead of boolean true
			-- would report the flag as incomplete. This is a potential
			-- data-integrity finding worth surfacing — but we encode
			-- reality, not desired behavior.
			local session = makeSession()
			session.profile.Onboarding.HasCompletedIntro = 1
			local flags = OnboardingService.getFlags(session)
			expect(flags.HasCompletedIntro).to.equal(false)
		end)
	end)

	describe("OnboardingService.hasCompletedCoreLoop (case 5)", function()
		it("should return false when no flags are set", function()
			expect(OnboardingService.hasCompletedCoreLoop(makeSession())).to.equal(false)
		end)

		it("should return false when only intro is set", function()
			local s = makeSession({ HasCompletedIntro = true })
			expect(OnboardingService.hasCompletedCoreLoop(s)).to.equal(false)
		end)

		it("should return false when intro + catch but not store", function()
			local s = makeSession({ HasCompletedIntro = true, HasCaughtFirstFish = true })
			expect(OnboardingService.hasCompletedCoreLoop(s)).to.equal(false)
		end)

		it("should return true when intro + catch + store are all set", function()
			local s = makeSession({
				HasCompletedIntro = true,
				HasCaughtFirstFish = true,
				HasStoredFirstFish = true,
			})
			expect(OnboardingService.hasCompletedCoreLoop(s)).to.equal(true)
		end)

		it("should return true even if income flag is NOT set (core loop is lighter)", function()
			local s = makeSession({
				HasCompletedIntro = true,
				HasCaughtFirstFish = true,
				HasStoredFirstFish = true,
				HasClaimedIncome = false,
			})
			expect(OnboardingService.hasCompletedCoreLoop(s)).to.equal(true)
		end)

		it("should return false for nil session", function()
			expect(OnboardingService.hasCompletedCoreLoop(nil)).to.equal(false)
		end)
	end)

	describe("OnboardingService.hasCompletedFirstSession (case 5)", function()
		it("should return false when no flags set", function()
			expect(OnboardingService.hasCompletedFirstSession(makeSession())).to.equal(false)
		end)

		it("should return false when core loop complete but income not claimed", function()
			local s = makeSession({
				HasCompletedIntro = true,
				HasCaughtFirstFish = true,
				HasStoredFirstFish = true,
				HasClaimedIncome = false,
			})
			expect(OnboardingService.hasCompletedFirstSession(s)).to.equal(false)
		end)

		it("should return true when all four required flags are set", function()
			local s = makeSession({
				HasCompletedIntro = true,
				HasCaughtFirstFish = true,
				HasStoredFirstFish = true,
				HasClaimedIncome = true,
			})
			expect(OnboardingService.hasCompletedFirstSession(s)).to.equal(true)
		end)

		it("should return false for nil session", function()
			expect(OnboardingService.hasCompletedFirstSession(nil)).to.equal(false)
		end)

		it("should return false when only three of four set", function()
			local s = makeSession({
				HasCompletedIntro = true,
				HasCaughtFirstFish = true,
				HasClaimedIncome = true,
			})
			expect(OnboardingService.hasCompletedFirstSession(s)).to.equal(false)
		end)
	end)

	describe("OnboardingService — persistence shape (case 5)", function()
		it("should store flags under profile.Onboarding", function()
			local session = makeSession()
			OnboardingService.mark(session, "HasCaughtFirstFish")
			local ob = session.profile.Onboarding
			expect(type(ob)).to.equal("table")
			expect(ob.HasCaughtFirstFish).to.equal(true)
		end)

		it("should not move flags outside the Onboarding subtable", function()
			local session = makeSession()
			OnboardingService.mark(session, "HasCompletedIntro")
			expect(session.profile.HasCompletedIntro).to.equal(nil)
		end)

		it("should keep existing flags when setting a new one", function()
			local session = makeSession({ HasCompletedIntro = true })
			OnboardingService.mark(session, "HasCaughtFirstFish")
			expect(session.profile.Onboarding.HasCompletedIntro).to.equal(true)
			expect(session.profile.Onboarding.HasCaughtFirstFish).to.equal(true)
		end)
	end)
end
