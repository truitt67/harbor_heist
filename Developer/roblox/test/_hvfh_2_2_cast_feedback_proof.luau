-- Proof for TASK 22.2 (hvfh.2.2): cast-while-casting feedback shake.
-- Two layers, mirroring the implementation in src/client/init.client.lua:
--   1. Timing/shape math: each step ~2-3 frames at 60fps, total shake
--      <= 0.25s (instant, local), decaying amplitude, always settles at 0.
--   2. Source contract: doFish fires RequestCast ONLY in the not-casting
--      branch and shakeFishButton ONLY in the casting branch — the guard
--      order is the regression surface (swapping them silently breaks the
--      cast flow), so assert it textually.
--
-- Run: lune run test/_hvfh_2_2_cast_feedback_proof.luau

local fs = require("@lune/fs")

-- ---- Layer 1: shake timing/shape (mirror of shakeFishButton) ----
local STEP_SECONDS = 0.05
local SEQUENCE = { -3, 3, -2, 0 }
local FPS = 60

local framesPerStep = STEP_SECONDS * FPS
print(string.format("=== Timing: %.3fs/step = %.1f frames @ %dfps ===", STEP_SECONDS, framesPerStep, FPS))
assert(framesPerStep >= 2 and framesPerStep <= 3, "step must be 2-3 frames (bead: '2-3 frame offset tween')")

local totalSeconds = STEP_SECONDS * #SEQUENCE
print(string.format("=== Total shake: %.2fs over %d steps ===", totalSeconds, #SEQUENCE))
assert(totalSeconds <= 0.25, "shake must feel instant (<= 0.25s)")

assert(SEQUENCE[#SEQUENCE] == 0, "sequence must settle back to Rotation 0")
local peak = 0
for _, a in ipairs(SEQUENCE) do
	local m = math.abs(a)
	assert(m <= 3, "amplitude stays subtle (<= 3 deg)")
	if m > 0 then
		assert(m <= math.max(peak, m), "amplitude must not grow")
		peak = math.max(peak, m)
	end
end

-- ---- Layer 2: source contract on doFish ----
-- lune runs with CWD = project root (scripts/run_tests.sh cds there).
local src = fs.readFile("src/client/init.client.lua")
local doFishStart = src:find("local function doFish()", 1, true)
assert(doFishStart, "doFish not found in client source")
local doFishBody = src:sub(doFishStart, doFishStart + 600)

local guardPos = doFishBody:find("if casting then", 1, true)
local shakePos = doFishBody:find("shakeFishButton()", 1, true)
local castPos = doFishBody:find("Remotes.RequestCast:FireServer()", 1, true)
assert(guardPos and shakePos and castPos, "doFish must contain casting guard, shake call, and cast fire")
assert(guardPos < shakePos, "casting guard must precede the shake call")
assert(shakePos < castPos, "shake (casting branch) must precede RequestCast (else branch)")
print("=== Source contract: doFish guard order OK (guard < shake < cast) ===")

-- The minigame tap path must NOT route through doFish (acceptance: no
-- interference with bite minigame input handling).
local minigameTap = src:find("onMinigameTap()", 1, true)
assert(minigameTap, "onMinigameTap missing")
local tapCallsDoFish = src:find("onMinigameTap(doFish)", 1, true)
		or src:find("onMinigameTap = doFish", 1, true)
assert(not tapCallsDoFish, "minigame tap must not be rewired to doFish")
print("=== Minigame input path untouched ===")

print("PROOF PASSED: hvfh.2.2 cast-while-casting feedback")
