-- PanelAnimation pure source-contract tests (harborheist-review-aug2026-6yp6.6).
--
-- PanelAnimation.lua is a shared UI library that touches Roblox services,
-- so it cannot be required directly in the lune pure runner. These are
-- source-contract assertions pinning the :Once() convention for one-shot
-- tween Completed handlers (auto-disconnect after the first fire), so a
-- regression back to :Connect fails the pure suite.

local fs = require("@lune/fs")

return function(describe, it, expect)
	local src = fs.readFile("src/shared/PanelAnimation.lua")

	describe("6yp6.6 PanelAnimation one-shot Completed handlers", function()
		it("no Completed:Connect remains (all converted to :Once)", function()
			expect(src:find(".Completed:Connect(", 1, true) == nil).to.equal(true)
		end)
		it("all 4 fadeTween completion handlers use :Once", function()
			local count = 0
			for _ in src:gmatch("fadeTween%.Completed:Once%(function%(playbackState%)") do count = count + 1 end
			expect(count).to.equal(4)
		end)
		it("handlers keep the natural-completion guard", function()
			local count = 0
			for _ in src:gmatch("playbackState ~= Enum%.PlaybackState%.Completed") do count = count + 1 end
			expect(count >= 4).to.equal(true)
		end)
		it("bead convention comment documents the :Once semantics", function()
			expect(src:find("harborheist-review-aug2026-6yp6.6", 1, true)).to.be.a("number")
		end)
	end)
end
