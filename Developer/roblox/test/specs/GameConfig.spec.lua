-- GameConfig unit tests (DataModel / TestEZ bucket).
--
-- GameConfig uses Color3.fromRGB at the top level, so it must run inside a
-- real Roblox DataModel. This spec is loaded by test/bootstrap.server.lua
-- via TestEZ in the test place built from test.project.json.

return function()
	describe("GameConfig.rollRarity", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

		it("should be deterministic with the same seeded Random", function()
			local rng1 = Random.new(12345)
			local rng2 = Random.new(12345)
			for _ = 1, 100 do
				expect(GameConfig.rollRarity(0, rng1)).to.equal(GameConfig.rollRarity(0, rng2))
			end
		end)

		it("should return only valid rarity indexes", function()
			local rng = Random.new(1)
			for _ = 1, 1000 do
				local r = GameConfig.rollRarity(0, rng)
				expect(r >= 1 and r <= #GameConfig.Rarities).to.equal(true)
			end
		end)

		it("should make all 5 rarities reachable over 10k rolls", function()
			local seen = {}
			local rng = Random.new(42)
			for _ = 1, 10000 do
				local r = GameConfig.rollRarity(0, rng)
				seen[r] = true
			end
			for i = 1, #GameConfig.Rarities do
				expect(seen[i]).to.be.ok()
			end
		end)

		it("should shift rarity mass toward rarer tiers as luck increases", function()
			local rngLow = Random.new(999)
			local rngHigh = Random.new(999)
			local sumLow = 0
			local sumHigh = 0
			for _ = 1, 10000 do
				sumLow += GameConfig.rollRarity(0, rngLow)
				sumHigh += GameConfig.rollRarity(50, rngHigh)
			end
			local meanLow = sumLow / 10000
			local meanHigh = sumHigh / 10000
			expect(meanHigh > meanLow).to.equal(true)
		end)
	end)

	describe("GameConfig table invariants", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

		it("should have Rarities weights that sum to 100", function()
			local total = 0
			for _, r in ipairs(GameConfig.Rarities) do
				expect(r.weight > 0).to.equal(true)
				total += r.weight
			end
			expect(total).to.equal(100)
		end)

		it("should have strictly increasing rarity values", function()
			for i = 2, #GameConfig.Rarities do
				expect(GameConfig.Rarities[i].value > GameConfig.Rarities[i - 1].value).to.equal(true)
			end
		end)

		it("should have sequential rod ids and non-decreasing cost/luck", function()
			for i, rod in ipairs(GameConfig.RodDefinitions) do
				expect(rod.id).to.equal(i)
				if i > 1 then
					expect(rod.cost >= GameConfig.RodDefinitions[i - 1].cost).to.equal(true)
					expect(rod.luck >= GameConfig.RodDefinitions[i - 1].luck).to.equal(true)
				end
			end
		end)

		it("should have sequential bait ids and non-decreasing cost/luck", function()
			for i, bait in ipairs(GameConfig.BaitDefinitions) do
				expect(bait.id).to.equal(i)
				if i > 1 then
					expect(bait.cost >= GameConfig.BaitDefinitions[i - 1].cost).to.equal(true)
					expect(bait.luck >= GameConfig.BaitDefinitions[i - 1].luck).to.equal(true)
				end
			end
		end)

		it("should keep Rods and Baits aliases identical to canonical tables", function()
			expect(GameConfig.Rods).to.equal(GameConfig.RodDefinitions)
			expect(GameConfig.Baits).to.equal(GameConfig.BaitDefinitions)
		end)
	end)

	describe("GameConfig MiniGame math guards", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

		it("should keep zone widths ordered", function()
			expect(GameConfig.MiniGame.hitZoneWidth < GameConfig.MiniGame.goodZoneWidth).to.equal(true)
			expect(GameConfig.MiniGame.goodZoneWidth < GameConfig.MiniGame.biteZoneCeiling).to.equal(true)
		end)

		it("should keep every rod minigameZoneSize below the bite ceiling", function()
			for _, rod in ipairs(GameConfig.RodDefinitions) do
				expect(rod.minigameZoneSize < GameConfig.MiniGame.biteZoneCeiling).to.equal(true)
			end
		end)

		it("should have exactly the accuracyLuckBonus keys perfect/good/ok", function()
			expect(GameConfig.MiniGame.accuracyLuckBonus.perfect).to.be.ok()
			expect(GameConfig.MiniGame.accuracyLuckBonus.good).to.be.ok()
			expect(GameConfig.MiniGame.accuracyLuckBonus.ok).to.be.ok()
			expect(GameConfig.MiniGame.accuracyLuckBonus.perfect).to.equal(25)
			expect(GameConfig.MiniGame.accuracyLuckBonus.good).to.equal(12)
			expect(GameConfig.MiniGame.accuracyLuckBonus.ok).to.equal(0)
			local count = 0
			for _ in pairs(GameConfig.MiniGame.accuracyLuckBonus) do
				count += 1
			end
			expect(count).to.equal(3)
		end)
	end)

	describe("GameConfig economy sanity", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

		it("should have the expected aquarium base constants", function()
			expect(GameConfig.Aquarium.baseCapacity).to.equal(20)
			expect(GameConfig.Aquarium.lockDuration).to.equal(60)
			expect(GameConfig.Aquarium.lockCooldown).to.equal(120)
		end)

		it("should have the expected defense/carry constants", function()
			expect(GameConfig.Defense.LockFreeUsesMax).to.equal(3)
			expect(GameConfig.MaxCarried).to.equal(5)
		end)

		it("should have sane raid-window timing", function()
			expect(GameConfig.Raid).to.be.a("table")
			expect(GameConfig.Raid.windowDuration < GameConfig.Raid.windowIntervalMin).to.equal(true)
			expect(GameConfig.Raid.maxFishPerRaid).to.equal(1)
		end)
	end)

	describe("GameConfig.validate", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

		it("should pass on the live config", function()
			local ok = pcall(GameConfig.validate)
			expect(ok).to.equal(true)
		end)

		it("should catch an injected invariant violation and restore the config", function()
			local original = GameConfig.MiniGame.goodZoneWidth
			GameConfig.MiniGame.goodZoneWidth = 1.5
			local ok, err = pcall(GameConfig.validate)
			GameConfig.MiniGame.goodZoneWidth = original
			expect(ok).to.equal(false)
			expect(tostring(err):find("goodZoneWidth")).to.be.ok()
		end)
	end)
end
