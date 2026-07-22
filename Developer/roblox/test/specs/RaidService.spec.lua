-- RaidService.spec.lua
-- TASK 18.9.2: RaidService cooldowns + loss-cap tests.
--
-- Exercises the REAL RaidService public functions that are deterministic from
-- session state: attacker cooldown, per-victim cooldown, and loss cap. These
-- functions read GameConfig.Raid timing constants and session-scoped fields;
-- they do not depend on the global window scheduler or zone state, so we test
-- them directly without calling RaidService.init().

return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
	local RaidService = require(ServerScriptService.HarborHeist.RaidService)
	local PlayerProfile = require(ReplicatedStorage.Shared.PlayerProfile)

	local function makeSession()
		return {
			player = nil,
			profile = PlayerProfile.default(),
		}
	end

	local function deepEqual(a, b)
		if a == b then return true end
		local ta, tb = type(a), type(b)
		if ta ~= tb or ta ~= "table" then return false end
		for k, v in pairs(a) do
			if not deepEqual(v, b[k]) then return false end
		end
		for k, _ in pairs(b) do
			if a[k] == nil then return false end
		end
		return true
	end

	describe("Attacker cooldown", function()
		local cooldownSeconds = GameConfig.Raid.raiderCooldownSeconds

		it("should be off cooldown when no previous raid exists", function()
			local session = makeSession()
			local onCd, remaining = RaidService.isAttackerOnCooldown(session)
			expect(onCd).to.equal(false)
			expect(remaining).to.equal(0)
		end)

		it("should be on cooldown when the last raid was recent", function()
			local session = makeSession()
			session.raidAttackLastAt = os.clock() - (cooldownSeconds / 2)
			local onCd, remaining = RaidService.isAttackerOnCooldown(session)
			expect(onCd).to.equal(true)
			expect(remaining >= 1).to.equal(true)
			expect(remaining <= cooldownSeconds).to.equal(true)
		end)

		it("should be off cooldown when the last raid was long ago", function()
			local session = makeSession()
			session.raidAttackLastAt = os.clock() - (cooldownSeconds + 1)
			local onCd, remaining = RaidService.isAttackerOnCooldown(session)
			expect(onCd).to.equal(false)
			expect(remaining).to.equal(0)
		end)
	end)

	describe("Per-victim cooldown", function()
		local cooldownSeconds = GameConfig.Raid.perVictimCooldownSeconds
		local targetUserId = 123456

		it("should be off cooldown when no victim entry exists", function()
			local session = makeSession()
			local onCd, remaining = RaidService.isVictimOnCooldown(session, targetUserId)
			expect(onCd).to.equal(false)
			expect(remaining).to.equal(0)
		end)

		it("should be on cooldown when the victim entry is recent", function()
			local session = makeSession()
			session.raidTargetCooldowns = { [targetUserId] = os.clock() + (cooldownSeconds / 2) }
			local onCd, remaining = RaidService.isVictimOnCooldown(session, targetUserId)
			expect(onCd).to.equal(true)
			expect(remaining >= 1).to.equal(true)
		end)

		it("should be off cooldown for a different victim", function()
			local session = makeSession()
			session.raidTargetCooldowns = { [targetUserId] = os.clock() + (cooldownSeconds / 2) }
			local onCd, remaining = RaidService.isVictimOnCooldown(session, 999999)
			expect(onCd).to.equal(false)
			expect(remaining).to.equal(0)
		end)

		it("should be off cooldown when the victim entry expired", function()
			local session = makeSession()
			session.raidTargetCooldowns = { [targetUserId] = os.clock() - 1 }
			local onCd, remaining = RaidService.isVictimOnCooldown(session, targetUserId)
			expect(onCd).to.equal(false)
			expect(remaining).to.equal(0)
		end)
	end)

	describe("Loss cap", function()
		it("should be capped at the configured max loss count", function()
			local session = makeSession()
			local maxLosses = GameConfig.Raid.maxLossesPerWindow
			session.raidWindowLosses = { serial = 0, count = maxLosses, value = 0 }
			expect(RaidService.isLossCapped(session)).to.equal(true)
		end)

		it("should not be capped below the max loss count", function()
			local session = makeSession()
			session.raidWindowLosses = { serial = 0, count = 0, value = 0 }
			expect(RaidService.isLossCapped(session)).to.equal(false)
		end)

		it("should reset the loss count when the window serial changes", function()
			local session = makeSession()
			session.raidWindowLosses = { serial = -1, count = 99, value = 0 }
			expect(RaidService.isLossCapped(session)).to.equal(false)
			expect(session.raidWindowLosses.serial).to.equal(0)
			expect(session.raidWindowLosses.count).to.equal(0)
		end)
	end)

	describe("Window state helpers", function()
		it("should report a closed window before the scheduler starts", function()
			expect(RaidService.isWindowOpen()).to.equal(false)
			expect(RaidService.getWindowRemaining()).to.equal(0)
			expect(RaidService.getNextWindowIn()).to.equal(0)
		end)

		it("should return a serializable window state payload", function()
			local state = RaidService.getWindowState()
			expect(state.open).to.equal(false)
			expect(state.remainingSeconds).to.equal(0)
			expect(state.nextWindowInSeconds).to.equal(0)
		end)
	end)
end
