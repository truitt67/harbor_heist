# Testing — Harbor Heist

Three test suites plus static gates. Run everything relevant before
committing; CI (`.github/workflows/tests.yml`) runs the portable gates.

## 1. Pure suite (lune) — runs anywhere

```bash
scripts/run_tests.sh --pure
```

- `test/pure_specs/` under lune: 100 tests.
- Remote arity contract gate (TASK 21.2) runs first; coverage gate
  (TASK 18.13) runs after. Both must pass.
- No Roblox Studio required. This is what CI runs.

## 2. Datamodel suite (TestEZ) — needs Studio

```bash
scripts/run_tests.sh --datamodel
```

- `test/specs/` under TestEZ: 410 tests.
- Builds `HarborHeist_tests.rbxlx` (test.project.json) and runs it via
  run-in-roblox with `tests/datamodel_stub.lua`.
- REQUIRED: the stub runs TestEZ in the **plugin context**. Several specs
  read `ModuleScript.Source` for static source guards; that needs the
  PluginOrOpenCloud capability, which the run-mode server VM lacks. Running
  the suite from a server bootstrap fails those specs and silently drops
  whole spec files on planning errors.
- Requires: Roblox Studio (signed in), run-in-roblox >= 0.3.0. The script
  derives its exit code from the TestEZ summary line (run-in-roblox itself
  always exits 0 when the plugin script completes).

### Running on Windows (Studio present)

On a Windows PC with Studio installed this bucket CAN run (the Linux agents
mark it "NOT-verified-on-Linux"). Toolchain needed: `rojo`, `run-in-roblox`,
`lune` (rokit), and a signed-in Studio. Three gotchas cost real time:

- **Use real Git Bash, not the WSL shim.** `C:\Users\<you>\AppData\Local\
  Microsoft\WindowsApps\bash.exe` is a WSL launcher that fails any redirected
  run with `ERROR: Input redirection is not supported`. Use
  `C:\Program Files\Git\bin\bash.exe` instead.
- **The script has CRLF line endings; bash needs LF.** Run a normalized copy
  or bash dies with `$'\r': command not found` / `set: pipefail\r: invalid
  option name`.
- **Run the copy in place.** `run_tests.sh` derives `PROJECT_ROOT` from its
  own path, so a copy in `/tmp` can't find `scripts/*.py`. Put the normalized
  copy next to the real script.

Verified one-liner (Git Bash, from `Developer/roblox/`):

```bash
"C:\Program Files\Git\bin\bash.exe" -c \
  "sed 's/\r$//' scripts/run_tests.sh > scripts/.rt_lf.sh && \
   bash scripts/.rt_lf.sh --datamodel; rm -f scripts/.rt_lf.sh"
```

Notes: Studio may run an install/update on first launch — wait for
`RobloxStudioBeta.exe` to appear, then the suite runs headless. Read the
result from the log's `Harbor Heist tests: N passed, M failed` line, not the
shell's exit code (wrapper artifacts can make it non-zero even on a green
run). Last verified: 410 passed, 0 failed.

## 3. E2E suite — needs Studio

```bash
scripts/run_e2e.sh
```

- `tests/e2e/runner.server.lua`: 198 assertions (tasks 19.2–19.9).
- Builds `HarborHeist_e2e.rbxlx` (e2e.project.json) and boots it via
  `tests/e2e_stub.lua` (plugin context → `RunService:Run()` starts the
  sim; server scripts run, including the runner).
- Logs to `testlogs/run-<id>.log` + summary JSON; exit code derived from
  the suite's `[E2E] SUMMARY` line.
- Covers: session lifecycle (19.2), cast/bite flow (19.3), aquarium
  economy (19.4), shop purchases (19.5), persistence + v1→v2 migration
  (19.6), lock/defense (19.7), raids (19.8), abuse/anti-exploit (19.9).

### Second, scenario-based harness (not wired to a runner yet)

There is a **separate, newer** e2e harness alongside `runner.server.lua`:
`tests/e2e/bootstrap.server.lua` + `tests/e2e/scenarios/*.lua` (currently just
`Lifecycle.lua`). It is mounted in `test.project.json` as
`ServerScriptService.RunE2E` (+ `E2ETests`), requires `tests/e2e/TestLogger.lua`,
and drives the **real** joining Studio Player (vs. the runner's table-fake
players). Its header says to invoke it via `scripts/run_e2e.sh
ServerScriptService.RunE2E`, but `run_e2e.sh` currently ignores that arg and
boots `e2e.project.json` / `runner.server.lua` instead. So today this scenario
harness has no automated entry point — treat it as scaffolding for the next e2e
pass, not part of the green suite. It does NOT run during `--datamodel` (the
datamodel log shows zero `[E2E]` output). If you intend to run it, wire
`run_e2e.sh` to accept the target and build/run `test.project.json` accordingly.

### E2E environment caveats

- **DataStore**: Studio blocks ALL DataStore access for unpublished local
  builds (`GetDataStore` throws; DataManager's pcall makes saves silent
  no-ops). The 19.6 persistence tests inject an in-memory mock via
  `DataManager._setStores` with real deep-copy semantics; on a published
  place the real store is used. Validate against the published place
  periodically.
- **Studio sign-in**: run-in-roblox needs an interactively signed-in
  Studio. Sign-in can silently expire (e.g. after auto-update) — if runs
  time out with no server output, open Studio and sign in again.
- **Fake players**: the runner uses table-fake players; `FireClient` on
  them throws, so notify-first code paths are verified via state, not
  return values. Reason strings for those paths are covered by the
  datamodel specs.

## Static checks (selene)

Compare before/after on any file you touch; never add NEW errors or
warnings. The lua51 std config produces parse_error artifacts on typed
Luau (`+=`, type annotations) — those are pre-existing noise; the signal
is the errors/warnings count. Known baseline on touched server files:
34 errors / 5 warnings (pre-existing).

## Manual runbooks

- `docs/RAID_TWO_PLAYER_RUNBOOK.md` — 2-player raid verification (19.8.2).
