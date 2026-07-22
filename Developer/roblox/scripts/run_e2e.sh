#!/usr/bin/env bash
# scripts/run_e2e.sh — E2E integration test runner for Harbor Heist.
#
# Usage:
#   scripts/run_e2e.sh [script-path]
#
#   script-path  Optional: the in-place script instance to execute.
#                Defaults to "ServerScriptService.RunTests".
#                When E2E scenarios are added (tasks 19.2+), pass
#                "ServerScriptService.RunE2E" or similar.
#
# Builds the test place via Rojo, launches it through run-in-roblox +
# Roblox Studio, and streams output to BOTH stdout and
# testlogs/run-<runid>.log.
#
# Exit codes:
#   0 = all E2E tests passed
#   1 = one or more E2E tests failed
#   2 = environment failure (missing tool, missing Studio, build failure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_SCRIPT="${1:-ServerScriptService.RunTests}"

# --- Generate run ID and prepare log directory ---
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
LOG_DIR="$PROJECT_ROOT/testlogs"
LOG_FILE="$LOG_DIR/run-${RUN_ID}.log"

mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Pre-flight: check for run-in-roblox
# ---------------------------------------------------------------------------
if ! command -v run-in-roblox &>/dev/null; then
	cat >&2 <<'ERROR'
===================================================================
ERROR: run-in-roblox is not installed.
===================================================================

E2E tests require run-in-roblox + Roblox Studio because they drive
real Remotes, DataStores, and game services that only exist inside
a Roblox DataModel.

Required tools (IN THIS ORDER):
  1. Roblox Studio (macOS or Windows — NOT available on Linux)
     Download: https://www.roblox.com/create
  2. run-in-roblox (Rust CLI that boots a headless Studio run)
     Install:  cargo install run-in-roblox
     Requires: cargo (Rust toolchain) + Roblox Studio installed

This machine is Linux without Studio, so E2E tests CANNOT run here.

For development on this machine, use:
  scripts/run_tests.sh --pure   (unit tests via lune — no Studio needed)

To run E2E on macOS/Windows:
  cargo install run-in-roblox
  scripts/run_e2e.sh
===================================================================
ERROR
	exit 2
fi

# ---------------------------------------------------------------------------
# Pre-flight: check for Roblox Studio
# ---------------------------------------------------------------------------
# run-in-roblox relies on a Studio installation. On macOS the binary is
# "RobloxStudio"; on Windows it is typically found via the registry.
if ! command -v RobloxStudio &>/dev/null 2>&1; then
	# Try common Windows paths under Wine (unlikely but documented)
	STUDIO_WIN="/c/Program Files/Roblox/Versions/RobloxStudioBeta.exe"
	if [[ ! -f "$STUDIO_WIN" ]]; then
		cat >&2 <<'ERROR'
===================================================================
ERROR: Roblox Studio is not installed.
===================================================================

run-in-roblox requires Roblox Studio to execute E2E tests.
Roblox Studio is only available on macOS and Windows, NOT Linux.

  Roblox Studio download: https://www.roblox.com/create

This machine does NOT have Roblox Studio and cannot run E2E tests.
Use scripts/run_tests.sh --pure for tests that work on this machine.

If you believe Studio IS installed but not on PATH, ensure the
RobloxStudio executable is reachable and retry.
===================================================================
ERROR
		exit 2
	fi
fi

# ---------------------------------------------------------------------------
# Build the test place
# ---------------------------------------------------------------------------
TEST_PLACE="$PROJECT_ROOT/HarborHeist_tests.rbxlx"

echo "=== Building test place ===" | tee "$LOG_FILE"
cd "$PROJECT_ROOT"
if ! rojo build test.project.json -o "$TEST_PLACE" 2>&1 | tee -a "$LOG_FILE"; then
	echo "" | tee -a "$LOG_FILE"
	echo "ERROR: rojo build failed. See $LOG_FILE for details." | tee -a "$LOG_FILE"
	exit 2
fi
echo "Built test place: $TEST_PLACE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Run E2E tests
# ---------------------------------------------------------------------------
echo "=== Running E2E tests ===" | tee -a "$LOG_FILE"
echo "run-in-roblox + Roblox Studio" | tee -a "$LOG_FILE"
echo "In-place script: $RUN_SCRIPT" | tee -a "$LOG_FILE"
echo "Run ID: $RUN_ID" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# run-in-roblox streams output; we tee to both stdout and the log file.
# We disable errexit around the pipeline so a test failure (exit 1) does
# not abort the script before we can write the summary.
set +e
run-in-roblox --place "$TEST_PLACE" --script "$RUN_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e

echo "" | tee -a "$LOG_FILE"
echo "=== E2E run complete ===" | tee -a "$LOG_FILE"
echo "Run ID: $RUN_ID" | tee -a "$LOG_FILE"
case "$EXIT_CODE" in
	0) echo "Result: PASS (exit 0)" | tee -a "$LOG_FILE" ;;
	1) echo "Result: TEST FAILURE (exit 1)" | tee -a "$LOG_FILE" ;;
	*) echo "Result: ENVIRONMENT ERROR (exit $EXIT_CODE)" | tee -a "$LOG_FILE" ;;
esac
echo "Full log: $LOG_FILE" | tee -a "$LOG_FILE"

# ---------------------------------------------------------------------------
# Write summary JSON for CI/tooling
# ---------------------------------------------------------------------------
SUMMARY_FILE="$LOG_DIR/summary-${RUN_ID}.json"
cat > "$SUMMARY_FILE" <<EOF
{
  "run_id": "$RUN_ID",
  "exit_code": $EXIT_CODE,
  "log_file": "$LOG_FILE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "place_file": "$TEST_PLACE",
  "script": "$RUN_SCRIPT",
  "result": "$(case "$EXIT_CODE" in 0) echo pass;; 1) echo fail;; *) echo env_error;; esac)"
}
EOF
echo "Summary: $SUMMARY_FILE" | tee -a "$LOG_FILE"

exit "$EXIT_CODE"
