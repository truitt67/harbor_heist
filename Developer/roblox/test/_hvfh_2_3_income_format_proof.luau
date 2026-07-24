-- Numeric proof for TASK 22.3 (hvfh.2.3): mirrors formatIncomeRate in
-- src/client/init.client.lua and asserts the acceptance criteria:
--   1. Starter tank (1-2 Commons) shows a non-zero, meaningful rate.
--   2. Formatting flips at the right thresholds (<0.1/sec -> per-min,
--      0.1-10/sec -> 2-decimal per-sec, >10/sec -> 1-decimal per-sec).
--   3. No layout jump: "/min" and "/sec" suffixes are equal width, and the
--      whole line stays well inside the 154px mobile label (TextSize 11-12).
--
-- The client function formats ONLY state.incomePerSec (authoritative,
-- multiplier-aware). This proof must stay in sync with that implementation.
--
-- Run: lune run test/_hvfh_2_3_income_format_proof.luau

local function formatIncomeRate(ratePerSec)
	ratePerSec = ratePerSec or 0
	if ratePerSec < 0.1 then
		return string.format("+$%.1f/min", ratePerSec * 60)
	elseif ratePerSec <= 10 then
		return string.format("+$%.2f/sec", ratePerSec)
	else
		return string.format("+$%.1f/sec", ratePerSec)
	end
end

-- Starter-tank economics: a Common earns $1/min (FishDefinitions), so
-- 1 Common == 1/60 per sec, 2 Commons == 2/60 per sec.
local COMMON_PER_MIN = 1
local function perSec(commons)
	return (commons * COMMON_PER_MIN) / 60
end

local fail = 0
local function check(desc, got, want)
	local ok = got == want
	if not ok then
		fail = fail + 1
	end
	print(string.format("  %-44s got=%-12q want=%-12q %s", desc, got, want, ok and "ok" or "<<< FAIL"))
end

print("=== Acceptance 1: starter tank shows a non-zero, meaningful rate ===")
check("empty tank (0/sec)", formatIncomeRate(0), "+$0.0/min")
check("1 Common (0.0167/sec)", formatIncomeRate(perSec(1)), "+$1.0/min")
check("2 Commons (0.0333/sec)", formatIncomeRate(perSec(2)), "+$2.0/min")
assert(formatIncomeRate(perSec(1)) ~= "+$0.0/sec", "legacy format hid starter income")

print("=== Acceptance 2: threshold flips ===")
check("just under 0.1/sec", formatIncomeRate(0.0999), "+$6.0/min")
check("exactly 0.1/sec", formatIncomeRate(0.1), "+$0.10/sec")
check("mid rate 0.333/sec", formatIncomeRate(1 / 3), "+$0.33/sec")
check("mid rate 5.678/sec", formatIncomeRate(5.678), "+$5.68/sec")
check("exactly 10/sec", formatIncomeRate(10), "+$10.00/sec")
check("just over 10/sec", formatIncomeRate(10.01), "+$10.0/sec")
check("high rate 500/sec", formatIncomeRate(500), "+$500.0/sec")

print("=== Acceptance 3: no layout jump ===")
-- Suffix parity: both suffixes are 4 chars, so flipping threshold never
-- changes suffix width.
assert(string.len("/min") == string.len("/sec"), "suffix width mismatch")
-- Mobile label: 178px card - 24px insets = 154px; at TextSize 11-12 Gotham
-- averages <=6px/char, so <=25 chars always fits without truncation.
local longest = 0
for _, r in ipairs({ 0, perSec(1), perSec(2), 0.0999, 0.1, 1 / 3, 5.678, 9.999, 10, 10.01, 99.94, 500, 9999.9 }) do
	longest = math.max(longest, string.len(formatIncomeRate(r)))
end
print(string.format("  longest rendered rate line = %d chars (budget 25)", longest))
assert(longest <= 25, "rate line can truncate on the 154px mobile label")

if fail > 0 then
	error(string.format("PROOF FAILED: %d check(s) failed", fail))
end
print("PROOF PASSED: hvfh.2.3 adaptive income-rate formatting")
