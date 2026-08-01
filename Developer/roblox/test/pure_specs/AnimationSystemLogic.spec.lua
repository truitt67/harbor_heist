-- AnimationSystem pure-logic unit tests (harborheist-hej1).
--
-- AnimationSystem.lua has game:GetService at the top level so it cannot be
-- required directly in the lune pure runner. Instead, the Spring physics
-- math and the Transition text-transparency guard are mirrored as pure
-- Luau functions and exercised against theoretical expectations.
-- Source-contract assertions verify that the production code still
-- contains the logic tested here.
--
-- Covers: Spring convergence, damping, settling; the restoring-force sign
-- (the a843112 fix — previously inverted, causing divergence); and the
-- supportsTextTransparency guard (the 24912eb fix — prevents TweenService
-- errors on Frame elements).

local fs = require("@lune/fs")

return function(describe, it, expect)
	-- ──────────────────────────────────────────────────────────────────
	-- Spring physics mirror (must match src/client/AnimationSystem.lua)
	-- ──────────────────────────────────────────────────────────────────

	local function makeSpring(stiffness, damping)
		return {
			stiffness = stiffness or 0.85,
			damping = damping or 0.65,
			currentValue = 0,
			targetValue = 0,
			velocity = 0,
			isAnimating = false,
		}
	end

	-- Mirrors Spring:update(dt) from AnimationSystem.lua (post-a843112 fix)
	local function springUpdate(s, dt)
		if not s.isAnimating then
			return true
		end
		if s.currentValue == nil or s.targetValue == nil then
			return true
		end
		local displacement = s.targetValue - s.currentValue
		local force = (s.stiffness * displacement) - (s.damping * s.velocity)
		s.velocity = s.velocity + (force * dt)
		s.currentValue = s.currentValue + (s.velocity * dt)
		if math.abs(displacement) < 0.01 and math.abs(s.velocity) < 0.01 then
			s.currentValue = s.targetValue
			s.isAnimating = false
			return true
		end
		return false
	end

	-- Simulate N steps of the spring; returns the spring and step count
	local function simulate(spring, dt, maxSteps)
		local steps = 0
		for _ = 1, maxSteps do
			steps = steps + 1
			if springUpdate(spring, dt) then
				break
			end
		end
		return spring, steps
	end

	-- Settling time for spring(k, c) ≈ 8/c seconds; at dt=0.016 that is
	-- ~769 steps for the default c=0.65. We use 2000 steps for headroom.
	local SIM_STEPS = 2000

	describe("Spring physics (harborheist-hej1, a843112 fix)", function()
		it("converges to target from below", function()
			local s = makeSpring(0.85, 0.65)
			s.currentValue = 0
			s.targetValue = 100
			s.isAnimating = true
			simulate(s, 0.016, SIM_STEPS)
			expect(s.isAnimating).to.equal(false)
			expect(math.abs(s.currentValue - 100) < 0.01).to.equal(true)
		end)

		it("converges to target from above", function()
			local s = makeSpring(0.85, 0.65)
			s.currentValue = 100
			s.targetValue = 0
			s.isAnimating = true
			simulate(s, 0.016, SIM_STEPS)
			expect(s.isAnimating).to.equal(false)
			expect(math.abs(s.currentValue - 0) < 0.01).to.equal(true)
		end)

		it("settles immediately when already at target with zero velocity", function()
			local s = makeSpring(0.85, 0.65)
			s.currentValue = 50
			s.targetValue = 50
			s.velocity = 0
			s.isAnimating = true
			local settled = springUpdate(s, 0.016)
			expect(settled).to.equal(true)
			expect(s.isAnimating).to.equal(false)
		end)

		it("does not diverge (the a843112 regression guard)", function()
			local s = makeSpring(0.85, 0.65)
			s.currentValue = 10
			s.targetValue = 50
			s.isAnimating = true
			simulate(s, 0.016, SIM_STEPS)
			expect(math.abs(s.currentValue - 50) < 1.0).to.equal(true)
			expect(s.isAnimating).to.equal(false)
		end)

		it("higher stiffness produces higher peak velocity", function()
			local soft = makeSpring(0.3, 0.65)
			soft.currentValue = 0
			soft.targetValue = 100
			soft.isAnimating = true
			local softPeak = 0
			for _ = 1, SIM_STEPS do
				if springUpdate(soft, 0.016) then break end
				softPeak = math.max(softPeak, math.abs(soft.velocity))
			end

			local stiff = makeSpring(0.95, 0.65)
			stiff.currentValue = 0
			stiff.targetValue = 100
			stiff.isAnimating = true
			local stiffPeak = 0
			for _ = 1, SIM_STEPS do
				if springUpdate(stiff, 0.016) then break end
				stiffPeak = math.max(stiffPeak, math.abs(stiff.velocity))
			end

			expect(stiffPeak > softPeak).to.equal(true)
		end)

		it("higher damping reduces overshoot", function()
			local lowDamp = makeSpring(0.85, 0.05)
			lowDamp.currentValue = 0
			lowDamp.targetValue = 100
			lowDamp.isAnimating = true
			local lowMaxOver = 0
			for _ = 1, 500 do
				if springUpdate(lowDamp, 0.016) then break end
				if lowDamp.currentValue > 100 then
					lowMaxOver = math.max(lowMaxOver, lowDamp.currentValue - 100)
				end
			end

			local highDamp = makeSpring(0.85, 0.9)
			highDamp.currentValue = 0
			highDamp.targetValue = 100
			highDamp.isAnimating = true
			local highMaxOver = 0
			for _ = 1, 500 do
				if springUpdate(highDamp, 0.016) then break end
				if highDamp.currentValue > 100 then
					highMaxOver = math.max(highMaxOver, highDamp.currentValue - 100)
				end
			end

			expect(highMaxOver < lowMaxOver).to.equal(true)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- supportsTextTransparency logic (24912eb fix)
	-- ──────────────────────────────────────────────────────────────────

	local TEXT_CLASSES = {
		TextLabel = true,
		TextButton = true,
		TextBox = true,
	}

	local function supportsTextTransparency(className)
		return TEXT_CLASSES[className] == true
	end

	describe("supportsTextTransparency (harborheist-hej1, 24912eb fix)", function()
		it("returns true for TextLabel", function()
			expect(supportsTextTransparency("TextLabel")).to.equal(true)
		end)
		it("returns true for TextButton", function()
			expect(supportsTextTransparency("TextButton")).to.equal(true)
		end)
		it("returns true for TextBox", function()
			expect(supportsTextTransparency("TextBox")).to.equal(true)
		end)
		it("returns false for Frame", function()
			expect(supportsTextTransparency("Frame")).to.equal(false)
		end)
		it("returns false for ImageLabel", function()
			expect(supportsTextTransparency("ImageLabel")).to.equal(false)
		end)
		it("returns false for ScrollingFrame", function()
			expect(supportsTextTransparency("ScrollingFrame")).to.equal(false)
		end)
	end)

	-- ──────────────────────────────────────────────────────────────────
	-- Source contract verification
	-- ──────────────────────────────────────────────────────────────────

	local animSource = fs.readFile("src/client/AnimationSystem.lua")

	describe("Source contract verification", function()
		it("Spring:update uses correct (non-negated) restoring force", function()
			expect(animSource:find("force = (self.stiffness * displacement) - (self.damping * self.velocity)", 1, true)).to.be.a("number")
		end)

		it("Spring:update does NOT use inverted restoring force", function()
			local found = animSource:find("force = %-%(self.stiffness", 1)
			expect(found).to.equal(nil)
		end)

		it("supportsTextTransparency function exists", function()
			expect(animSource:find("local function supportsTextTransparency", 1, true)).to.be.a("number")
		end)

		it("supportsTextTransparency checks TextLabel", function()
			expect(animSource:find('element:IsA("TextLabel")', 1, true)).to.be.a("number")
		end)

		it("supportsTextTransparency checks TextButton", function()
			expect(animSource:find('element:IsA("TextButton")', 1, true)).to.be.a("number")
		end)

		it("supportsTextTransparency checks TextBox", function()
			expect(animSource:find('element:IsA("TextBox")', 1, true)).to.be.a("number")
		end)

		it("Transition:fade conditionally adds TextTransparency", function()
			expect(animSource:find("if supportsTextTransparency(element) then", 1, true)).to.be.a("number")
		end)

		-- harborheist-kqbq.17.2: transitions accept Theme.motion TweenInfo presets
		it("resolveTransitionInfo helper exists (kqbq.17.2)", function()
			expect(animSource:find("local function resolveTransitionInfo", 1, true)).to.be.a("number")
		end)
		it("resolveTransitionInfo checks typeof TweenInfo", function()
			expect(animSource:find('typeof(duration) == "TweenInfo"', 1, true)).to.be.a("number")
		end)
		it("Transition:slide uses resolveTransitionInfo", function()
			expect(animSource:find("resolveTransitionInfo(duration, self, Enum.EasingStyle.Back", 1, true)).to.be.a("number")
		end)
		it("resolveTransitionInfo used by slide/scale/rotate/fadeSlide", function()
			local count = 0
			for _ in animSource:gmatch("resolveTransitionInfo") do count = count + 1 end
			expect(count >= 4).to.equal(true)
		end)
		it("Transition:fade accepts TweenInfo via typeof guard", function()
			expect(animSource:find('if typeof(duration) == "TweenInfo" then', 1, true)).to.be.a("number")
		end)
	end)
end
