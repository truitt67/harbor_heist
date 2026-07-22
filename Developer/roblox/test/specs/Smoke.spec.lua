-- Smoke test: verifies the TestEZ harness loads and shared modules are reachable.
return function()
	describe("TestEZ harness", function()
		it("should load and run basic assertions", function()
			expect(true).to.equal(true)
		end)

		it("should support negation", function()
			expect(true).never.to.equal(false)
		end)
	end)

	describe("Shared.GameConfig", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

		it("should expose the Rarities table", function()
			expect(GameConfig.Rarities).to.be.a("table")
		end)

		it("should contain 5 rarity tiers", function()
			expect(#GameConfig.Rarities).to.equal(5)
		end)

		it("should expose RodDefinitions", function()
			expect(GameConfig.RodDefinitions).to.be.a("table")
		end)

		it("should expose BaitDefinitions", function()
			expect(GameConfig.BaitDefinitions).to.be.a("table")
		end)

		it("should expose the Aquarium config", function()
			expect(GameConfig.Aquarium).to.be.a("table")
		end)
	end)

	describe("Shared.FishDefinitions", function()
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local FishDefinitions = require(ReplicatedStorage.Shared.FishDefinitions)

		it("should expose a Species table", function()
			expect(FishDefinitions.Species).to.be.a("table")
		end)
	end)
end
