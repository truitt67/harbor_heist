-- DockManager pure source-contract tests (harborheist-review-aug2026-6yp6.8).
--
-- DockManager.lua touches Roblox services at the top level so it cannot be
-- required directly in the lune pure runner. These are source-contract
-- assertions: they verify the defensive FindFirstChild + nil-guard pattern
-- (matching release()) stays in place at the three sites the deep review
-- flagged, so a regression to direct indexing fails the pure suite.
--
-- Sites: claim() InfoSign/OwnerLabel/AquariumPrompt; updateAquariumVisual
-- FishDisplay (with early return) and Water (guarded fallback).

local fs = require("@lune/fs")

return function(describe, it, expect)
	local src = fs.readFile("src/server/DockManager.lua")

	describe("6yp6.8 DockManager defensive property access", function()
		it("claim() reads PrimaryPart through a guarded local", function()
			local claimPos = src:find("function DockManager.claim(player)", 1, true)
			expect(claimPos).to.be.a("number")
			local basePos = src:find("local aquariumBase = dock.aquarium.PrimaryPart", claimPos, true)
			expect(basePos).to.be.a("number")
			local guardPos = src:find("if aquariumBase then", basePos, true)
			expect(guardPos).to.be.a("number")
		end)
		it("claim() uses FindFirstChild for InfoSign and AquariumPrompt (before release())", function()
			local claimPos = src:find("function DockManager.claim(player)", 1, true)
			local releasePos = src:find("function DockManager.release(player)", 1, true)
			expect(releasePos).to.be.a("number")
			local signPos = src:find('local sign = aquariumBase:FindFirstChild("InfoSign")', 1, true)
			local promptPos = src:find('local prompt = aquariumBase:FindFirstChild("AquariumPrompt")', 1, true)
			expect(signPos).to.be.a("number")
			expect(promptPos).to.be.a("number")
			-- The claim() copies are the FIRST occurrences (claim precedes release).
			expect(claimPos < signPos).to.equal(true)
			expect(signPos < releasePos).to.equal(true)
			expect(claimPos < promptPos).to.equal(true)
			expect(promptPos < releasePos).to.equal(true)
		end)
		it("no residual direct indexing of sign/prompt anywhere", function()
			expect(src:find("dock.aquarium.PrimaryPart.InfoSign", 1, true) == nil).to.equal(true)
			expect(src:find("dock.aquarium.PrimaryPart.AquariumPrompt", 1, true) == nil).to.equal(true)
		end)
		it("updateAquariumVisual uses FindFirstChild for FishDisplay with early return", function()
			expect(src:find('local display = dock.aquarium:FindFirstChild("FishDisplay")', 1, true)).to.be.a("number")
			expect(src:find("if not display then return end", 1, true)).to.be.a("number")
			expect(src:find("local display = dock.aquarium.FishDisplay", 1, true) == nil).to.equal(true)
		end)
		it("updateAquariumVisual guards the Water part", function()
			expect(src:find('local waterPart = dock.aquarium:FindFirstChild("Water")', 1, true)).to.be.a("number")
			expect(src:find("waterPart and waterPart.CFrame", 1, true)).to.be.a("number")
			expect(src:find("dock.aquarium.Water.CFrame", 1, true) == nil).to.equal(true)
		end)
		it("release() defensive pattern still intact (the reference implementation)", function()
			expect(src:find('local ownerLabel = sign:FindFirstChild("OwnerLabel")', 1, true)).to.be.a("number")
			expect(src:find('ownerLabel.Text = "Unclaimed Dock"', 1, true)).to.be.a("number")
		end)
	end)
end
