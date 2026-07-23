#!/usr/bin/env bash
# scripts/run_tests.sh — Test runner for Harbor Heist
#
# Usage:
#   scripts/run_tests.sh [--pure|--datamodel]
#
# Default: --pure (lune, runs on any machine without Roblox Studio)
#
# Buckets:
#   --pure      Pure-Luau modules (no game/Instance/DataStore at top level).
#               Runs via lune (github.com/lune-org/lune).
#   --datamodel DataModel-bound modules (game:GetService/require at top level).
#               Runs via run-in-roblox + Roblox Studio. Requires test.project.json
#               to be built into a .rbxlx place file first.
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed
#   2 = environment failure (missing tool, missing place file, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUCKET=""

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
	case "$1" in
		--pure)      BUCKET="pure";     shift ;;
		--datamodel) BUCKET="datamodel"; shift ;;
		-h|--help)
			echo "Usage: scripts/run_tests.sh [--pure|--datamodel]"
			echo ""
			echo "Default: --pure (lune)"
			echo ""
			echo "  --pure      Run pure-Luau tests via lune (no Roblox Studio needed)"
			echo "  --datamodel Run DataModel-bound tests via run-in-roblox + Studio"
			echo ""
			echo "Exit codes: 0=pass, 1=test failure, 2=environment error"
			exit 0
			;;
		*)
			echo "ERROR: Unknown argument: '$1'" >&2
			echo "Usage: scripts/run_tests.sh [--pure|--datamodel]" >&2
			exit 2
			;;
	esac
done

# Default to --pure
BUCKET="${BUCKET:-pure}"

# ---------------------------------------------------------------------------
# TASK 21.2: Remote arity contract gate (static; runs for all buckets).
# Fails fast if any client OnClientEvent handler declares fewer params than
# the server sends via FireClient/FireAllClients — the class of bug that
# silently broke the bite minigame in TASK 21.1. No game instance required.
# Bypass with REMOTE_ARITY_GATE=0 (mirrors the COVERAGE_GATE pattern).
# ---------------------------------------------------------------------------
if [[ "${REMOTE_ARITY_GATE:-1}" == "1" ]]; then
	echo "=== Remote arity contract check (TASK 21.2) ==="
	if ! python3 "$PROJECT_ROOT/scripts/remote_arity_check.py"; then
		echo "Remote arity contract gate FAILED — see output above." >&2
		exit 1
	fi
	echo ""
fi

# ---------------------------------------------------------------------------
# --pure bucket: lune
# ---------------------------------------------------------------------------
if [[ "$BUCKET" == "pure" ]]; then
	if ! command -v lune &>/dev/null; then
		echo "ERROR: lune is not installed." >&2
		echo "" >&2
		echo "lune is required for the --pure bucket (runs pure-Luau tests)." >&2
		echo "" >&2
		echo "Install (Linux x86_64):" >&2
		echo "  curl -sSL https://github.com/lune-org/lune/releases/download/v0.10.5/lune-0.10.5-linux-x86_64.zip -o /tmp/lune.zip" >&2
		echo "  unzip /tmp/lune.zip -d /tmp" >&2
		echo "  sudo mv /tmp/lune /usr/local/bin/lune" >&2
		echo "" >&2
		echo "Other platforms: https://github.com/lune-org/lune/releases" >&2
		exit 2
	fi

	echo "=== Running pure-Luau tests (lune bucket) ==="
	echo "lune version: $(lune --version)"
	echo ""

	cd "$PROJECT_ROOT"
	lune run test/pure_runner
	test_exit=$?

	# TASK 18.13 (k5wz.13): coverage gate. Runs the static export-reference
	# analyzer. Exits 1 if any in-scope module drops below its threshold.
	# The report is always generated (testlogs/coverage.txt); the gate only
	# fails the script in --gate mode (CI) or when run_tests is called with
	# the COVERAGE_GATE=1 env var. Pure-test failures take precedence.
	if [[ $test_exit -ne 0 ]]; then
		exit $test_exit
	fi

	if [[ "${COVERAGE_GATE:-1}" == "1" ]]; then
		echo ""
		echo "=== Coverage gate (TASK 18.13) ==="
		if ! python3 "$PROJECT_ROOT/scripts/coverage_report.py" --gate; then
			echo "Coverage gate FAILED — see testlogs/coverage.txt for details"
			exit 1
		fi
	fi

	exit 0
fi

# ---------------------------------------------------------------------------
# --datamodel bucket: run-in-roblox + Roblox Studio
# ---------------------------------------------------------------------------
if [[ "$BUCKET" == "datamodel" ]]; then
	# Check run-in-roblox
	if ! command -v run-in-roblox &>/dev/null; then
		echo "ERROR: run-in-roblox is not installed, and Roblox Studio is not available on this machine." >&2
		echo "" >&2
		echo "DataModel-bound tests require:" >&2
		echo "  1. Roblox Studio (macOS or Windows only — NOT available on Linux)" >&2
		echo "  2. run-in-roblox (cargo install run-in-roblox)" >&2
		echo "" >&2
		echo "To install run-in-roblox:" >&2
		echo "  cargo install run-in-roblox" >&2
		echo "" >&2
		echo "Then build the test place:" >&2
		echo "  rojo build test.project.json -o HarborHeist_tests.rbxlx" >&2
		echo "" >&2
		echo "This Linux machine does NOT have Roblox Studio and cannot run DataModel-bound tests." >&2
		echo "Use --pure for tests that work on this machine." >&2
		exit 2
	fi

	# Check for Roblox Studio (run-in-roblox needs it)
	if ! command -v RobloxStudio &>/dev/null 2>&1; then
		echo "ERROR: Roblox Studio is not installed on this machine." >&2
		echo "run-in-roblox requires Roblox Studio to execute DataModel-bound tests." >&2
		echo "Roblox Studio is only available on macOS and Windows, not Linux." >&2
		echo "" >&2
		echo "Use --pure for tests that work on this machine." >&2
		exit 2
	fi

	# Check for test place file
	TEST_PLACE="$PROJECT_ROOT/HarborHeist_tests.rbxlx"
	if [[ ! -f "$TEST_PLACE" ]]; then
		echo "Test place file not found: $TEST_PLACE" >&2
		echo "Building it now with rojo..." >&2
		cd "$PROJECT_ROOT"
		if ! rojo build test.project.json -o "$TEST_PLACE" 2>&1; then
			echo "ERROR: rojo build failed. Cannot proceed without a test place file." >&2
			echo "Fix the rojo build errors and retry." >&2
			exit 2
		fi
		echo "Built test place successfully." >&2
	fi

	echo "=== Running DataModel-bound tests (run-in-roblox bucket) ==="
	echo "run-in-roblox + Roblox Studio" >&2
	echo ""

	cd "$PROJECT_ROOT"
	run-in-roblox --place "$TEST_PLACE" --script "ServerScriptService.RunTests"
	exit_code=$?
	exit $exit_code
fi

# Should never reach here
echo "ERROR: Unknown bucket: '$BUCKET'" >&2
exit 2
