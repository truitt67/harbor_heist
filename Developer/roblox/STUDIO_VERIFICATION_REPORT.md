# Studio Runtime Verification — harborheist-orpl (headless portion)

**Date:** 2026-07-30 · **Machine:** Windows PC with Roblox Studio (`version-ff6341faef444107`)
**Scope:** `harborheist-orpl` (TASK 42.6) — the portion verifiable **hands-free** via
run-in-roblox. The real client-input smoke (cast/bite/raid overlay clicks) remains open.

## Verdict summary

| orpl goal | Result | Evidence |
| --- | --- | --- |
| Router fix landed & wired (harborheist-3xlw) | PASS | Overlay input-router contract gate: handlers `['bite','cast','raid']` registered, `Router dispatch: FOUND` |
| Remote arity contract (TASK 21.2) | PASS | 8 remotes checked, all OK |
| Server-side cast/bite/economy logic | PASS | Datamodel suite **410 passed, 0 failed** (plugin context) |
| Raid server logic | PASS | TestEZ `RaidService` / `RaidServiceOutcome` / `RaidServiceScheduler` specs |
| Persistence + v1→v2 migration | PASS | E2E 19.6 round-trip + migration asserts |
| **Real client clicks (cast overlay, bite marker, raid minigame)** | **OPEN** | run-in-roblox is server-only; E2E 19.3 self-reports `SKIP: no test bridge for activeBites` |

## Runs

### 1. Datamodel suite — PASS (410/410)

```
scripts/run_tests.sh --datamodel   (plugin context via tests/datamodel_stub.lua)
Harbor Heist tests: 410 passed, 0 failed, 0 skipped
```

Pre-flight gates (run for all buckets) both passed:
- Remote arity contract: 8 remotes OK.
- Overlay input-router contract: handlers registered + router dispatch found.
  This is the static guarantee against the harborheist-3xlw regression
  (handlers registered but never dispatched).

### 2. Scenario harness (`scripts/run_e2e_scenarios.sh`) — mixed, failures are environmental

`test.project.json` mounts BOTH the TestEZ specs AND the E2E runner, so this run
re-executed both in the **server/run context** (via `tests/e2e_stub.lua`), NOT the
plugin context. Log: `testlogs/scenarios-20260730T024441Z.log`.

- TestEZ portion: **387 passed / 7 failed** — the 7 are the documented
  `PluginOrOpenCloud` capability errors (`cannot read 'Source'`) + 2 RaidService
  timing assertions (`expected 0, got ~1795.2`). These are server-context artifacts;
  the identical specs pass 410/410 in plugin context. NOT game regressions.
- E2E runner (19.2–19.9): 19.2 lifecycle + 19.6 persistence/migration all PASS.
  19.8 raid failures are all `no_session` on table-fake players (`FireClient` throws
  on fakes — documented harness limitation). 19.7 / 19.5 failed on missing test seams
  `aquariumActivateLock` / `shopPurchase` and the run crashed at
  `E2ETests/runner:1140` (`attempt to index nil with 'aquariumActivateLock'`).

## Follow-up beads to file (harness limitations, not orpl blockers)

1. E2E 19.8 raid blocks return `no_session` for table-fake players — needs a real
   client or a FireClient-safe fake to exercise the raid gates end-to-end.
2. Missing test seams: `aquariumActivateLock` (19.7) and `shopPurchase` (19.5);
   runner crashes at `tests/e2e/runner.server.lua:1140`.
3. `run_e2e_scenarios.sh` runs the TestEZ specs in server context (387/7) while
   `run_tests.sh --datamodel` runs them in plugin context (410/0) — the scenario
   script re-runs specs it doesn't own and reports misleading failures.

## Still required to close orpl

Real client-input smoke in Studio (manual GUI or StudioMCP-driven client):
cast overlay accepts click → `CastResult`; bite marker accepts click → catch;
2-player raid minigame accepts input and resolves. See
`docs/CATCH_FLOW_RUNBOOK.md` and `docs/RAID_TWO_PLAYER_RUNBOOK.md`.

## StudioMCP automation attempt (2026-07-30) — not viable from this host

Tried to wire Roblox Studio's **built-in** MCP server so the client-input smoke
could run hands-free. Findings:

- The built-in server was **enabled** in Studio (Assistant → ⋯ → Manage MCP
  Servers → "Enable Studio as MCP server") and the launcher
  `%LOCALAPPDATA%\Roblox\mcp.bat` → `StudioMCP.exe` (v0.1.0) is present.
- It exposes the exact tools needed: `start_stop_play`, `execute_luau`
  (Edit/Client/Server), `user_keyboard_input`, `user_mouse_input`,
  `get_console_output`, `screen_capture`.
- **Blocker:** the proxy is stdio-transport, so it must be spawned as a child
  process of the MCP client. The Abacus.AI Desktop client auto-generates
  `desktop/runtime/mcp-code.json` at every startup with only its builtin
  `browser` server; hand-adding `Roblox_Studio` is wiped on restart and there
  is no persistent/user-facing mechanism to register a custom stdio server.
  Therefore this client cannot drive Studio's MCP. (No fault of the user —
  the toggle was correctly enabled; the green "client connected" indicator
  never lights because the host app never spawns the proxy.)

**Viable alternatives to close orpl later:**
1. A stdio-capable MCP client that supports user-defined servers (e.g. Cursor,
   Claude Desktop) with the official `Roblox_Studio` config — Studio is already
   listening, so that client connects immediately.
2. The minimal manual smoke (docs runbooks) — ~5 minutes, no command bar needed.
