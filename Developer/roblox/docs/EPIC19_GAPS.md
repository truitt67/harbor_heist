# EPIC 19 — Gaps & Findings Register

Gaps, environment limitations, and bugs surfaced while building the E2E
suite (tasks 19.2–19.10). Status legend: FIXED / DOCUMENTED (accepted,
workaround in place) / FOLLOW-UP (needs scheduling).

## G1 — v1 capacityLevel migration lost purchased capacity — FIXED

Found by: 19.6 (first failing assertion: "migration Capacity recomputed —
expected 35, got 20").
`DataManager.sanitize()` converted legacy `capacityLevel` into
`Aquarium.UpgradeLevel`, but the N6 capacity recompute only ran for
payloads carrying an `Aquarium` sub-table — v1 payloads never had one, so
migrated players kept the tier-1 default `Capacity` despite a higher
`UpgradeLevel` (`StateSync.getCapacity` reads `Capacity` as authoritative;
they would stay wrong until their next upgrade purchase).
Fix: the recompute is hoisted to run on every sanitize path, making
`Capacity == tiers[UpgradeLevel].capacity` universal. Commit bb86f91.

## G2 — Studio blocks DataStore for unpublished places — DOCUMENTED

Found by: 19.6 ("You must publish this place to the web to access
DataStore"; `GetDataStore` throws and DataManager's module-level pcall
turned every `save()` into a silent no-op — 19.2's round-trip phases had
been passing vacuously on defaults).
Workaround: `DataManager._setStores(v2, v1)` seam; the E2E injects an
in-memory mock with real deep-copy semantics (reference-storing mocks
hide aliasing bugs). The runner probes first and prefers the real store
when the place IS published.
FOLLOW-UP: schedule periodic E2E validation against the published place
so the real DataStore path (UpdateAsync merge transforms included) stays
honest.

## G3 — Notify-first code paths are unobservable with fake players — DOCUMENTED

`FireClient` on table-fake players throws, so any handler that notifies
before returning (raid `too_fast`/`too_slow`, fish-catch miss/success
messages, shop `wrong_tier`/`poor`) cannot be asserted by return value in
E2E. Those paths are verified via session/profile state; their reason
strings are covered by datamodel TestEZ specs (410/410).
No action — the two suites are complementary by design.

## G4 — Test runners used the broken pre-0.3.0 --script invocation — FIXED

`run_tests.sh --datamodel` and `run_e2e.sh` passed an instance path
(`ServerScriptService.RunTests`) to run-in-roblox; >= 0.3.0 executes a
FILE in the plugin context. Additionally the datamodel suite must run in
the plugin VM specifically: specs reading `ModuleScript.Source` fail with
capability errors in the run-mode server VM, and planning errors silently
drop whole spec files (410 tests presented as 389+5 failures).
Fix: checked-in stubs (`tests/datamodel_stub.lua`, `tests/e2e_stub.lua`)
+ both scripts repointed; exit codes now derived from suite summary lines
because run-in-roblox exits 0 on any completed plugin script. (19.10)

## G5 — Studio sign-in silently expires — DOCUMENTED

run-in-roblox requires an interactively signed-in Studio; auto-updates
can drop the session and every run then times out with no server output.
Detection: newest `*Studio*last.log` under
`%LOCALAPPDATA%\Roblox\logs` mentions the login dialog/start page.
Resolution is always manual re-login (credentials are never automated).

## G6 — Raid zone watchers untested at E2E level — FOLLOW-UP

Raid Waters pier / Safe Harbor plaza opt-in via physical zones
(`watchRaidZone`, `watchSafeHarborZone`, touch counting + polling) is
only covered indirectly — fake players have no Character/Parts, and zone
entry needs real physics. The 2-player runbook
(`docs/RAID_TWO_PLAYER_RUNBOOK.md`) covers it manually; automated
coverage would need real player instances in a 2-client Studio session.

## G7 — 2-player interactions not automatable in the single-session E2E — DOCUMENTED

Real remote firing (`OnServerInvoke` write-only from server context),
client UI, and WalkSpeed stun gating all require real clients. Covered by
the manual runbook (19.8.2); E2E uses module-function seams with fakes
for everything server-side.
