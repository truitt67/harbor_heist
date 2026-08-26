#!/usr/bin/env bash
# scripts/run_e2e_scenarios.sh — run the scenario-based e2e harness.
#
# The harness (tests/e2e/bootstrap.server.lua + tests/e2e/scenarios/*.lua)
# drives the REAL joining Studio Player through the production onPlayerAdded
# path, so DataManager.load / leaderstats / dock claim all run for real.
# (It replaces the retired monolithic runner tests/e2e/runner.server.lua,
# which drove table-fake players.)
#
# The harness is mounted in test.project.json as ServerScriptService.RunE2E
# (+ ServerScriptService.E2ETests). This script builds that place
# (HarborHeist_scenarios.rbxlx) and boots it via tests/e2e_stub.lua, which runs
# in the plugin context and starts the sim with RunService:Run() (TASK 19.10).
#
# Usage:
#   scripts/run_e2e_scenarios.sh
#
# Exit codes:
#   0 = all scenarios passed
#   1 = one or more scenarios/asserts failed
#   2 = environment failure (missing tool, missing Studio, build failure, no summary)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
LOG_DIR="$PROJECT_ROOT/testlogs"
LOG_FILE="$LOG_DIR/scenarios-${RUN_ID}.log"
mkdir -p "$LOG_DIR"

# --- Pre-flight: tools -------------------------------------------------------
if ! command -v run-in-roblox &>/dev/null; then
	echo "ERROR: run-in-roblox not installed (cargo install run-in-roblox)." >&2
	exit 2
fi
if ! command -v rojo &>/dev/null; then
	echo "ERROR: rojo not installed." >&2
	exit 2
fi

# TASK 19.10: rojo/run-in-roblox are native Windows binaries and cannot
# resolve MSYS-style absolute paths; convert (no-op on real Linux/macOS).
to_native() { command -v cygpath >/dev/null 2>&1 && cygpath -w "$1" || printf '%s' "$1"; }

# --- Build the scenario place (e2e_scenarios.project.json) --------------------
# harborheist-vyv1: use a dedicated project file that EXCLUDES the TestEZ specs
# (test/specs/) and their bootstrap (test/bootstrap.server.lua), which polluted
# the E2E scenario log with 387/7 false failures (TestEZ specs fail in server
# context — they require plugin context). Also maps E2ETests as only
# TestLogger + scenarios instead of the whole tests/e2e/ directory, preventing
# bootstrap.server.lua from running twice (once as E2ETests.bootstrap, once as
# RunE2E).
TEST_PLACE="$PROJECT_ROOT/HarborHeist_scenarios.rbxlx"

echo "=== Building scenario e2e place (e2e_scenarios.project.json) ===" | tee "$LOG_FILE"
cd "$PROJECT_ROOT"
if ! rojo build e2e_scenarios.project.json -o "$(to_native "$TEST_PLACE")" 2>&1 | tee -a "$LOG_FILE"; then
	echo "ERROR: rojo build failed. See $LOG_FILE." | tee -a "$LOG_FILE"
	exit 2
fi
echo "Built scenario place: $TEST_PLACE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# --- Run the scenario harness ------------------------------------------------
echo "=== Running scenario e2e harness ===" | tee -a "$LOG_FILE"
echo "run-in-roblox + Roblox Studio; RunE2E drives the real Studio player" | tee -a "$LOG_FILE"
echo "Run ID: $RUN_ID" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

set +e
run-in-roblox --place "$(to_native "$TEST_PLACE")" --script "$(to_native "$PROJECT_ROOT/tests/e2e_stub.lua")" 2>&1 | tee -a "$LOG_FILE"
set -e

# bootstrap.server.lua prints "[E2E] complete: P/T scenarios passed, A asserts,
# F failures" and calls error() (non-zero) when F>0. run-in-roblox's own exit
# code is unreliable (TASK 19.10), so the complete line is the verdict.
# A CRASHED scenario (pcall caught) increments the bootstrap's crash counter
# but may still print 0 "failures" on the complete line — crashes are tracked
# separately from summary.totalFailures and surfaced as a "scenario crashed"
# log line + an error() call. Detect both so a crash never reads as PASS.
SUMMARY_LINE=$(grep -E "\[E2E\] complete: [0-9]+/[0-9]+ scenarios passed" "$LOG_FILE" | tail -1 || true)
CRASH_LINE=$(grep -E "scenario crashed" "$LOG_FILE" | tail -1 || true)
if [[ -z "$SUMMARY_LINE" ]]; then
	echo "ERROR: scenario harness did not report a complete line (boot failure?)" | tee -a "$LOG_FILE"
	EXIT_CODE=2
elif [[ -n "$CRASH_LINE" ]]; then
	EXIT_CODE=1
elif [[ "$SUMMARY_LINE" =~ ([0-9]+)\ failures ]] && [[ "${BASH_REMATCH[1]}" != "0" ]]; then
	EXIT_CODE=1
else
	EXIT_CODE=0
fi

echo "" | tee -a "$LOG_FILE"
case "$EXIT_CODE" in
	0) echo "Result: PASS ($SUMMARY_LINE)" | tee -a "$LOG_FILE" ;;
	1) echo "Result: TEST FAILURE ($SUMMARY_LINE)" | tee -a "$LOG_FILE" ;;
	*) echo "Result: ENVIRONMENT ERROR" | tee -a "$LOG_FILE" ;;
esac
echo "Full log: $LOG_FILE" | tee -a "$LOG_FILE"

exit "$EXIT_CODE"
