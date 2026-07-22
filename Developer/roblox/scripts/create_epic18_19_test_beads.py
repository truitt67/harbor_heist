#!/usr/bin/env python3
"""
Bulk-create EPIC 18 (Zero-Mock Unit Test Coverage) + EPIC 19 (E2E Integration
Suite with Structured Logging) tasks, subtasks, dependencies, and comments.

Created by ChartreuseFox on 2026-07-22 at user request after verifying the repo
has ZERO automated tests (no spec/test files, no TestEZ, no runner; only manual
.rbxlx playthrough beads 13.1 / 16.5 exist).

Follows the pattern of scripts/create_epic14_beads.py (Hermes-K3): every bead is
self-contained with root cause, recipe, and file pointers so a future agent can
execute cold. Uses `br` (0.2.11) — the working tool in this repo; `bd` 0.49.0
currently fails its DB migration here.

Idempotency: aborts if any EPIC 18/19 bead already exists in .beads/issues.jsonl.

Usage: python3 /home/ubuntu/Developer/roblox/scripts/create_epic18_19_test_beads.py
"""

import json
import subprocess
import sys

REPO = "/home/ubuntu/Developer/roblox"
ISSUES_JSONL = REPO + "/.beads/issues.jsonl"

EPIC18 = None  # filled after creation
EPIC19 = None


def run(cmd):
    """RELIABILITY: every br subprocess gets a timeout (pattern from epic14 script)."""
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO, timeout=30)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


def guard_no_duplicates():
    with open(ISSUES_JSONL) as f:
        for line in f:
            try:
                b = json.loads(line)
            except json.JSONDecodeError:
                continue
            t = (b.get("title") or "")
            if t.startswith("EPIC 18:") or t.startswith("EPIC 19:"):
                print(f"ABORT: EPIC 18/19 bead already exists: {b.get('id')} {t}", file=sys.stderr)
                sys.exit(1)


def br_create(title, issue_type, priority, parent, description):
    cmd = ["br", "create", title, "-t", issue_type, "-p", str(priority),
           "-d", description, "--json"]
    if parent:
        cmd += ["--parent", parent]
    out, err, rc = run(cmd)
    if rc != 0:
        print(f"FAIL create '{title}': {err}", file=sys.stderr)
        return None
    try:
        return json.loads(out)["id"]
    except (json.JSONDecodeError, KeyError) as e:
        print(f"FAIL parse create response for '{title}': {e}\nout={out}", file=sys.stderr)
        return None


def br_update_ac(bead_id, ac_text):
    cmd = ["br", "update", bead_id, f"--acceptance-criteria={ac_text}"]
    out, err, rc = run(cmd)
    if rc != 0:
        print(f"FAIL set AC on {bead_id}: {err}", file=sys.stderr)
        return False
    return True


def br_dep_add(issue, depends_on):
    """Wire a 'blocks' dep: `issue` is blocked by `depends_on`."""
    cmd = ["br", "dep", "add", issue, depends_on, "-t", "blocks"]
    out, err, rc = run(cmd)
    if rc != 0:
        print(f"FAIL dep {issue} <- {depends_on}: {err}", file=sys.stderr)
        return False
    return True


def br_comment(bead_id, text):
    cmd = ["br", "comments", "add", bead_id, "--message", text]
    out, err, rc = run(cmd)
    if rc != 0:
        print(f"FAIL comment on {bead_id}: {err}", file=sys.stderr)
        return False
    return True



# ─────────────────────────────────────────────────────────────────────────────
# EPIC DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────

EPIC18_TITLE = "EPIC 18: Zero-Mock Unit Test Coverage (TestEZ)"
EPIC18_DESC = """Umbrella for bringing the repo from ZERO automated tests to full unit-level coverage of all server services and shared modules, under a hard constraint: NO MOCKS / NO FAKES.

## CURRENT STATE (verified 2026-07-22, ChartreuseFox)
- No *.spec.lua / *.test.lua anywhere; no TestEZ; no test tree in default.project.json; no test runner script.
- Verification today is manual .rbxlx playthrough only (beads 13.1, 16.5).
- Machine has: rojo, selene, cargo. MISSING: Roblox Studio, wine, lune, run-in-roblox, wally/foreman/aftman.

## NO-MOCK CONSTRAINT (what it means here)
- Tests require() and exercise the REAL modules: real GameConfig tables, real service functions, real state.
- Determinism comes from Random.new(seed) — seeding the real RNG is NOT mocking.
- Pure-logic modules (GameConfig, DataManager sanitize/migrate, AntiExploitService, QuestService rotation) run as plain Luau — no Roblox API shims allowed; if a module can't run without a DataModel, it is tested inside a real DataModel (Studio/run-in-roblox), never against a fake DataModel.
- Persistence paths use a REAL Roblox DataStore (dedicated test DataStore, throwaway keys) when run in Studio; skipped with an explicit log line when API access is unavailable. No DataStoreService stubs.

## FRAMEWORK
TestEZ (Roblox-standard BDD: describe/it/expect) vendored into the repo. Runner decision (lune for pure-Luau vs run-in-roblox for DataModel-bound) is spiked in TASK 18.1 — this machine currently lacks both, so installation is part of the task.

## SCOPE (13 tasks)
18.1 harness -> 18.2 GameConfig -> 18.3 shared definitions -> 18.4 DataManager pure logic -> 18.5 FishingService -> 18.6 AquariumService -> 18.7 ShopService -> 18.8 FishInventoryService -> 18.9 RaidService -> 18.10 QuestService -> 18.11 AntiExploitService -> 18.12 Collection/Onboarding/AuditLog -> 18.13 coverage gate.
Services intentionally EXCLUDED from unit scope (covered by EPIC 19 e2e instead): WorldBuilder, DockManager, RodService, BoatService, StateSync, Remotes, AnalyticsService (DataModel/presentation-heavy; their logic is thin glue).

## DONE WHEN
Every in-scope module has a spec file exercising every exported function against the real implementation, the suite runs via one command with non-zero exit on failure, and the 18.13 coverage gate reports and enforces thresholds."""

EPIC19_TITLE = "EPIC 19: E2E Integration Suite with Structured Logging"
EPIC19_DESC = """Umbrella for end-to-end integration test scripts that drive the REAL game (real server services, real remotes, real DataStore where available) and produce GREAT, DETAILED structured logs for every run.

## CURRENT STATE (verified 2026-07-22, ChartreuseFox)
- No e2e scripts, no test harness, no logging infrastructure. Manual playthrough only (HarborHeist_test.rbxlx).

## WHAT "E2E" MEANS HERE
- A test client script inside a real Roblox server session drives the REAL RemoteEvents/RemoteFunctions (RequestCast, SubmitCatchInput, RequestStoreFish, RequestClaimIncome, RequestPurchaseUpgrade, RequestRaidAttempt, etc. — 15 events + 17 functions in src/server/Remotes.lua) and asserts on REAL server state via GetState snapshots and observed events.
- No service is stubbed. Where a flow needs money/time, the harness uses real server-side paths (income accrual, session credit through the same code the income loop uses, or the real RaidService window API) — never client-side forgery.

## STRUCTURED LOGGING (the point of the epic)
- A TestLogger module emits JSONL: ISO8601 timestamp, level, scenario id, step id, message, data payload, and full state dumps on assertion failure.
- Every scenario logs: setup, each remote call (name + args + response), each assertion (expected vs actual), timing, and a final summary (pass/fail counts, durations).
- Artifacts land in testlogs/ (gitignored) and are captured by CI.

## KNOWN ENVIRONMENT LIMIT (must be respected)
This machine (2026-07-22) has NO Roblox Studio and no run-in-roblox. TASK 19.1 includes the runner spike (install/verify, or document the exact external requirement). True 2-player raid e2e cannot run headless in solo Studio — TASK 19.8.2 is a scripted 2-client Studio runbook with in-game assertions, explicitly semi-manual.

## SCOPE (10 tasks)
19.1 harness+logger -> 19.2 lifecycle -> 19.3 fishing -> 19.4 aquarium economy -> 19.5 shop -> 19.6 persistence round-trip + v1->v2 migration -> 19.7 lock/defense -> 19.8 raid (19.8.1 automated single-player, 19.8.2 two-player runbook) -> 19.9 abuse/rate-limit -> 19.10 CI+docs.

## DONE WHEN
One command runs the whole suite headless (or the documented Studio runner), every scenario emits JSONL logs a human can audit line-by-line, failures dump full state, and CI gates on exit code."""



# ─────────────────────────────────────────────────────────────────────────────
# TASK DEFINITIONS
# (key, title, priority, parent_key, description, acceptance_criteria)
# parent_key: "E18"/"E19" for tasks, task key for subtasks
# ─────────────────────────────────────────────────────────────────────────────

TASKS = [
    # ═══ EPIC 18 — harness ═══
    ("18.1",
     "TASK 18.1: Test harness foundation — vendor TestEZ + decide runner",
     1, "E18",
     """Foundation for ALL unit tests. Two sub-deliverables (subtasks 18.1.1, 18.1.2).

## WHY
Repo has zero test infra. Every spec file needs (a) TestEZ available to require(), (b) a runner that executes specs headless with a pass/fail exit code.

## CONSTRAINTS
- NO MOCKS: the harness must require() real modules from src/. No shim DataModel, no fake DataStoreService, no proxy tables.
- Pure-Luau modules (src/shared/*.lua minus FishVisuals; DataManager sanitize/migrate helpers; AntiExploitService) must be loadable outside a DataModel if the chosen runner is lune — if any in-scope module transitively requires a Roblox-only API, that module moves to the DataModel-runner bucket (documented in the decision comment).
- Determinism: harness exposes a helper to hand specs a seeded Random.new(seed) — the REAL RNG, seeded.

## DELIVERABLES
- test.project.json (rojo) mapping src/shared, src/server, tests/ so TestEZ specs sit beside the real code in a real place file.
- scripts/run_tests.sh: one command, exit 0 on all-pass, exit 1 otherwise, prints TestEZ summary.
- Decision recorded as a bead comment: which runner executes what, and why (18.1.2).""",
     """- [ ] TestEZ vendored and require()-able from a spec file
- [ ] scripts/run_tests.sh runs all specs with exit 0/1 semantics
- [ ] At least one real module (GameConfig) loaded and asserted in a spec — no stubs anywhere
- [ ] Runner decision comment posted on this bead (lune vs run-in-roblox per module bucket)
- [ ] README/AGENTS test-run instructions drafted (final docs land in 19.10)"""),

    ("18.1.1",
     "TASK 18.1.1: Vendor TestEZ + test.project.json rojo mapping",
     1, "18.1",
     """Vendor TestEZ (github.com/Roblox/testez, pin a release tag — record the exact commit in a comment) into the repo (e.g. Packages/TestEZ or test/TestEZ) WITHOUT adding a package manager unless the spike shows one is needed (repo currently has none: no wally/foreman/aftman configs).

Create test.project.json extending default.project.json's tree: same src/shared + src/server mappings, PLUS a Tests container (ServerScriptService/Tests or ReplicatedStorage/Tests) holding specs and the bootstrap runner script.

VERIFY: `rojo build test.project.json -o HarborHeist_tests.rbxlx` succeeds and the place contains both real code and specs.""",
     """- [ ] TestEZ source vendored, commit hash recorded in bead comment
- [ ] test.project.json builds cleanly with rojo
- [ ] Built place contains real src modules + TestEZ + tests container
- [ ] No changes to default.project.json (production place must stay test-free)"""),

    ("18.1.2",
     "TASK 18.1.2: Runner spike — lune for pure-Luau vs run-in-roblox, decide + wire scripts/run_tests.sh",
     1, "18.1",
     """This machine (2026-07-22) has rojo+selene+cargo but NO Studio, wine, lune, or run-in-roblox. Spike both runners:

A) lune (github.com/lune-org/lune — prebuilt binary): can require() Luau files directly via its filesystem loader. Works ONLY for modules that never touch Roblox APIs (Instance, game, DataStoreService, task, os.clock is OK). Classify every in-scope module by grep'ing for Roblox globals (rg -n 'game\\.|Instance\\.|DataStoreService|Players\\.|ReplicatedStorage' src/). Pure modules -> lune bucket.

B) run-in-roblox (cargo install run-in-roblox — needs Roblox Studio installed): required for any DataModel-bound module. If Studio cannot be installed on this box, document the exact external requirement (what must exist, on what OS) and make scripts/run_tests.sh fail with a CLEAR message when the DataModel bucket is requested but Studio is absent — never silently skip.

DELIVERABLE: scripts/run_tests.sh supporting `--pure` (lune bucket, must work on this machine) and `--datamodel` (Studio bucket) and defaulting to `--pure`; decision + module classification posted as bead comment.""",
     """- [ ] Both runners evaluated; install steps recorded in bead comment
- [ ] Module bucket classification (pure vs DataModel-bound) posted as comment
- [ ] scripts/run_tests.sh --pure works on this machine end-to-end
- [ ] Missing-Studio path fails loudly with actionable message (no silent skip)
- [ ] Exit codes: 0 pass, 1 test failure, 2 environment failure"""),
]


TASKS += [
    # ═══ EPIC 18 — shared modules ═══
    ("18.2",
     "TASK 18.2: GameConfig unit tests (rollRarity, validate, table invariants)",
     2, "E18",
     """Spec: tests/shared/GameConfig.spec.lua against the REAL src/shared/GameConfig.lua.

## CASES
1. rollRarity(luck, rng): with Random.new(fixed seed) assert (a) determinism — same seed, same sequence; (b) all 5 rarity indexes reachable over 10k rolls; (c) monotonicity — mean rarity index at luck=50 > luck=0 (luck formula w*(1+(luck/100)*(i-1)) must shift mass toward rarer); (d) return value always in 1..#Rarities.
2. Table invariants: Rarities weights positive and sum to 100; values strictly increasing (10/25/70/180/500); RodDefinitions/BaitDefinitions ids 1..3 sequential, cost/luck non-decreasing; Rods/Baits aliases are the SAME table (identity, not copy).
3. MiniGame math guards (regression anchors from EPIC 14/R2): hitZoneWidth(0.3) < goodZoneWidth(0.5) < biteZoneCeiling(0.85); every RodDefinitions.minigameZoneSize < biteZoneCeiling; accuracyLuckBonus keys exactly {perfect, good, ok}.
4. Economy sanity: Aquarium.baseCapacity=20, lockDuration=60, lockCooldown=120, Defense.LockFreeUsesMax=3, MaxCarried=5; Raid table present with windowDuration < windowIntervalMin and maxFishPerRaid=1.
5. GameConfig.validate(): returns/passes clean on the LIVE config; when handed a deliberately broken config copy (e.g. zone widths inverted), it fails/warns — proving the boot check has teeth. Do NOT mutate the real module table; pass a deep copy if the API allows, else test via the documented injection path.

NO MOCKS: all inputs are real tables from the real module; only the rng argument is a real seeded Random.""",
     """- [ ] All 5 case groups implemented and passing
- [ ] Determinism case uses Random.new(seed) with two identical seeds
- [ ] Monotonicity asserted statistically (10k+ rolls, mean comparison)
- [ ] validate() proven to catch at least one injected invariant violation
- [ ] No module state mutated by the spec"""),

    ("18.3",
     "TASK 18.3: Shared definition tests (FishDefinitions, ZoneDefinitions, FishInstance, PlayerProfile)",
     2, "E18",
     """Spec: tests/shared/Definitions.spec.lua against REAL src/shared/{FishDefinitions,ZoneDefinitions,FishInstance,PlayerProfile}.lua.

## CASES
1. FishDefinitions: every species has SpeciesId, DisplayName, valid rarity reference, and IncomePerMinute > 0 (EPIC R2 found income-definition divergence — this test is the regression net for B.2/B.3); 12-20 species per PRD; rarity distribution weights per zone sum correctly.
2. ZoneDefinitions: every zone's rod-level access gate references an EXISTING RodDefinitions id; DisplayName present; spawn locations defined.
3. FishInstance: factory/shape produces records with SpeciesId, Rarity, CaughtTime, IncomePerMinute, IsRaidProtected; IsRaidProtected true for Legendary per GameConfig.Raid.legendaryProtection.nonStealable.
4. PlayerProfile: v2 defaults complete — Coins, TotalCoinsEarned, Equipment (EquippedRodLevel/BaitLevel=1, Unlocked*={1}), Aquarium (StoredFish={}, Capacity=baseCapacity, lock timestamps=0, LockFreeUsesRemaining=LockFreeUsesMax), Dock, Collection, PvP (RaidOptIn=false), Onboarding (all false), Stats, Defense, dailyQuestKey/weeklyQuestKey formats.
5. Cross-referential integrity: every species' rarity name exists in GameConfig.Rarities; every zone's species table references existing SpeciesIds.

These tests catch the exact class of silent config drift EPIC R2 documented.""",
     """- [ ] All 5 case groups implemented and passing
- [ ] Cross-reference case fails if a species/zone references a non-existent id (proven by temporary fixture, not by editing real files)
- [ ] PlayerProfile defaults deep-compared field-by-field
- [ ] Legendary raid protection asserted from the real config chain"""),

    # ═══ EPIC 18 — DataManager ═══
    ("18.4",
     "TASK 18.4: DataManager pure-logic unit tests (sanitize, migration, corruption)",
     2, "E18",
     """Umbrella task for DataManager.lua (794 lines) testable-pure logic — sanitize(), the v1->v2 migration/coercion path, and corruption handling. These functions are pure table-in/table-out (no DataStoreService) per the v1->v2 design; if the spike (18.1.2) finds Roblox globals inside them, refactor the pure helpers OUT (minimal diff, review first) rather than mocking — that refactor is in scope for this task.

DataStore-touching paths (GetAsync/SetAsync/UpdateAsync, autosave loop, BindToClose) are NOT unit scope — covered by e2e 19.6.

Subtasks: 18.4.1 sanitize, 18.4.2 migration fidelity, 18.4.3 corruption resilience.""",
     """- [ ] All three subtasks closed
- [ ] No DataStoreService stub anywhere in the specs
- [ ] Any required pure-helper extraction kept minimal and reviewed"""),

    ("18.4.1",
     "TASK 18.4.1: DataManager.sanitize() unit tests",
     2, "18.4",
     """Spec: tests/server/DataManagerSanitize.spec.lua against the REAL sanitize().

## CASES (from the v1->v2 sanitize contract in DataManager.lua)
1. Valid v2 profile passes through semantically unchanged (deep-compare).
2. Type coercion: non-numeric Coins rejected/zeroed; non-table Equipment rebuilt to defaults; negative values clamped.
3. Timestamp clamping: LockUntilTimestamp/LockCooldownUntilTimestamp clamped to <=600s in the future (documented sanitize bound) — feed os.time()+999999 and assert clamp.
4. Unlock-count clamping: UnlockedRodLevels/UnlockedBaitLevels lists clamped to <= #RodDefinitions/#BaitDefinitions and to actually-existing ids.
5. Aquarium invariants: Capacity >= baseCapacity, StoredFish entries with invalid Rarity indexes dropped or repaired per the real implementation's contract (assert the REAL behavior — read the code first, encode what it does, flag as a comment if behavior looks wrong instead of silently enshrining a bug; file a follow-up bead if so).""",
     """- [ ] All 5 case groups passing against real sanitize()
- [ ] Each clamp asserted with boundary values (exactly at, one over)
- [ ] Any 'looks wrong' real behavior surfaced as a bead comment + follow-up bead, not silently encoded"""),

    ("18.4.2",
     "TASK 18.4.2: v1 -> v2 migration fidelity unit tests",
     2, "18.4",
     """Spec: tests/server/DataManagerMigration.spec.lua. The v1->v2 path (flat cash/rodLevel/liveWell -> structured PlayerProfile) is the highest-risk data code in the repo — EPIC 14 finding 14.2 (migration overwrite) landed here.

## CASES
1. Full-fidelity v1 fixture -> v2: cash->Coins preserved exactly; rodLevel->Equipment.EquippedRodLevel; baitLevel likewise; liveWell[] rarity indexes -> StoredFish FishInstance records (assert each converted record has required FishInstance fields).
2. Already-v2 input is NOT re-migrated/clobbered (regression for 14.2 class: idempotence — migrate(migrate(x)) == migrate(x)).
3. Empty/absent v1 -> fresh default v2 profile.
4. Partially-corrupt v1 (missing fields) -> defaults for missing, preserved for present.
5. Quest keys: dailyQuestKey/weeklyQuestKey formats survive or are regenerated per real contract.

Fixtures: construct v1 tables in the spec from the historical v1 shape (documented in DataManager comments / git history of the flat model) — real shape, hand-built data, no mocks.""",
     """- [ ] All 5 cases passing
- [ ] Idempotence case present (migrate twice == migrate once)
- [ ] Coin/gear values asserted EXACTLY (no approximations)
- [ ] Fixture shape cross-checked against git history and noted in comment"""),

    ("18.4.3",
     "TASK 18.4.3: DataManager corruption-resilience unit tests",
     2, "18.4",
     """Spec: tests/server/DataManagerCorruption.spec.lua.

## CASES
1. Corrupted quest entries (wrong types, missing fields) are filtered out, valid siblings kept.
2. Onboarding table with unknown flags: whitelist enforced — unknown keys dropped, known keys preserved.
3. Garbage top-level input (string, number, array-with-holes, self-referencing-ish junk within Luau limits) -> no throw; returns default or sanitized profile per real contract.
4. Unknown top-level fields: assert the real drop/keep behavior (read code first; encode reality; comment if surprising).
5. StoredFish with holes/duplicates/impossible species -> filtered per real contract.

WHY: sanitize() is the last line of defense between a corrupted DataStore blob and a wiped player profile (the R1 epic's whole thesis).""",
     """- [ ] All 5 cases passing
- [ ] No pcall wrapping in the SPEC to hide throws — sanitize itself must not throw
- [ ] Surprising real behaviors commented + follow-up bead filed if warranted"""),
]


TASKS += [
    # ═══ EPIC 18 — gameplay services ═══
    ("18.5",
     "TASK 18.5: FishingService unit tests (tier derivation, luck stacking, timing guards)",
     2, "E18",
     """Spec: tests/server/FishingService.spec.lua against REAL src/server/FishingService.lua (468 lines).

## CASES
1. Tier derivation: server-side accuracy tier from client-reported marker position — position inside perfect zone -> perfect, inside good -> good, else ok. Boundary values at exact zone edges (assert inclusive/exclusive per real code).
2. Luck stacking: rod luck + bait luck + MiniGame.accuracyLuckBonus[tier] combine per real formula; perfect-tier luck (25) with Basic Rod exceeds Golden Rod base (20) — assert the arithmetic that TASK 16.5 tunes.
3. biteZoneCeiling regression (wqw.24): luck-inflated effective zone is capped at 0.85 — feed extreme luck, assert cap.
4. Bite window regression (wqw.4): bite window is 3.5s — assert the constant/path the server uses.
5. Cleanup regression (14.3): the per-player active-bite state is cleared on player-removing path — invoke the real cleanup function with a fabricated-but-real session table and assert no residual entry.
6. Rarity resolution: end-to-end rollRarity call inside catch resolution uses the real seeded rng path; assert no math.random global usage in the catch path (rg the file, encode as lint-style test if feasible).

NO MOCKS: sessions are plain real tables matching the real session shape; rng is real seeded Random; do not stub StateSync/AnalyticsService — if FishingService hard-calls them, that coupling is surfaced in a comment and the spec calls the real collaborators with real minimal state instead.""",
     """- [ ] All 6 cases passing
- [ ] Boundary positions at exact zone edges tested
- [ ] Regressions for wqw.4, wqw.24, 14.3 encoded as permanent tests
- [ ] Any collaborator coupling documented in comment"""),

    ("18.6",
     "TASK 18.6: AquariumService unit tests (income accrual, claim, sell, capacity, lock FSM)",
     2, "E18",
     """Spec: tests/server/AquariumService.spec.lua against REAL src/server/AquariumService.lua (537 lines).

## CASES
1. Income accrual: stored fish with known IncomePerMinute accrues exactly rate*elapsed into the UnclaimedIncome pool (use real accrual function with explicit timestamps — pass times in, never fake os.time globally).
2. Claim: claiming moves pool to Coins EXACTLY and resets pool to 0; claim on empty pool returns the real 'nothing to claim' result.
3. Sell: per-rarity values (10/25/70/180/500) and species sell values computed exactly; sell-all empties StoredFish.
4. Capacity: store rejected at Capacity (base 20; upgraded per Capacity upgrade tiers I/II/III = 30/45/60); boundary at exactly-cap and cap+1.
5. Lock state machine: activate -> LockUntilTimestamp=now+lockDuration(60), LockCooldownUntilTimestamp=now+lockCooldown(120); free uses decrement from LockFreeUsesMax(3) then paid path; activation rejected while locked or in cooldown; expiry transition correct.
6. Raid protection: IsRaidProtected fish excluded from steal-eligible selection (legendaryProtection.nonStealable).

WHY: this is the economy core; EPIC 14 finding 14.6 (sell-from-locked-aquarium) lives here — add that regression case explicitly: selling while locked must behave per the real post-fix contract.""",
     """- [ ] All 6 case groups passing
- [ ] Exact-arithmetic assertions (no rounding tolerance)
- [ ] Lock FSM transitions tested through every legal + illegal edge
- [ ] 14.6 regression case present"""),

    ("18.7",
     "TASK 18.7: ShopService unit tests (validation, funds, tier gating)",
     2, "E18",
     """Spec: tests/server/ShopService.spec.lua against REAL src/server/ShopService.lua (159 lines).

## CASES
1. Happy path: sufficient funds -> purchase succeeds, Coins deducted EXACTLY, unlock recorded (UnlockedRodLevels etc.), equip behavior per real contract.
2. Insufficient funds: rejected, Coins unchanged, no unlock.
3. Tier gating: cannot skip tiers (sequential unlock) — assert per real rule for rods AND baits.
4. Invalid input: unknown category, unknown tier id, negative tier, wrong types -> rejected without state change.
5. Capacity/dock upgrade categories: apply per real tiers (30/45/60) with exact costs.
6. Replay/duplicate purchase: buying an owned tier rejected or idempotent per real contract.

WHY: ECON-05 server-authoritative purchases; the 'first purchase in opening session' tuning (ECON-06) makes exact-cost assertions launch-critical.""",
     """- [ ] All 6 cases passing
- [ ] Every rejection path asserts ZERO state mutation (deep-compare before/after)
- [ ] Exact cost arithmetic asserted from real GameConfig tables"""),

    ("18.8",
     "TASK 18.8: FishInventoryService unit tests (carry cap, integrity, single-sell)",
     2, "E18",
     """Spec: tests/server/FishInventoryService.spec.lua against REAL src/server/FishInventoryService.lua (262 lines).

## CASES
1. Carry cap: MaxCarried=5 enforced — 5 accepted, 6th rejected; boundary exact.
2. Add/remove integrity: removing a fish returns the SAME record (identity/fields), list shrinks by exactly 1.
3. No duplication: rapid sequential add of the same record cannot exceed cap or duplicate entries (assert final list contents exactly).
4. Sell-single: sells the correct fish at its exact value, others untouched.
5. Negative/invalid: remove non-existent fish, sell index out of range -> rejected, state unchanged.
6. Interaction contract with AquariumService store path (store-single moves record, not copy) — assert no aliasing bug where the same table lives in both carried and stored.""",
     """- [ ] All 6 cases passing
- [ ] Case 6 (aliasing/move-semantics) present — silent shared-table bugs are the classic Lua inventory exploit
- [ ] Every rejection asserts zero mutation"""),
]


TASKS += [
    # ═══ EPIC 18 — raid/quest/security/meta services ═══
    ("18.9",
     "TASK 18.9: RaidService unit tests (scheduler, eligibility, outcome authority)",
     2, "E18",
     """Umbrella for REAL src/server/RaidService.lua (1066 lines — largest service). Three subtasks split the concern: 18.9.1 scheduler+gating, 18.9.2 cooldowns+caps, 18.9.3 outcome resolution.

## WHY
RaidService holds the worst exploit class fixed to date (14.16 client-authoritative hit; stun exploit via boat spawn) and the most timing rules (windowInterval 20-30min, windowDuration 5min, raiderCooldown 6min, defenderProtection 20min, perVictimCooldown 30min, maxLossesPerWindow 2). All timing logic must be tested with EXPLICIT clock parameters — never by faking os.time/os.clock globally; if the service reads clocks directly in a way that blocks this, note it in a comment and test through the real public functions with real short durations instead.""",
     """- [ ] All three subtasks closed
- [ ] No global clock faking anywhere
- [ ] Forged-input authority cases (18.9.3) all passing"""),

    ("18.9.1",
     "TASK 18.9.1: RaidService window scheduler + opt-in gating tests",
     2, "18.9",
     """Spec: tests/server/RaidServiceScheduler.spec.lua.

## CASES
1. Window interval: next-window scheduling lands within [windowIntervalMin=1200s, windowIntervalMax=1800s] across many iterations (seeded rng if the scheduler rolls).
2. Window duration: open->close transition after windowDuration=300s (drive with explicit times).
3. Opt-in default: RaidOptIn defaults false (GameConfig.Raid.optInDefault) — a never-opted player is never enrolled.
4. Toggle semantics: opt-in during closed window registers for next window; opt-out removes eligibility.
5. New-player protection: defenderProtectionSeconds=1200 — a player younger than that cannot be targeted (assert boundary at exactly 1200s account/session age per real age source).
6. Broadcast: RaidWindowChanged fired on open and close with correct remaining-time payload (invoke real broadcast path with real Remotes module — if Remotes requires a live DataModel, this case moves to e2e 19.8.1; comment the split).""",
     """- [ ] Cases 1-5 passing (case 6 either passing or moved+commented)
- [ ] Boundary assertions at exact protection threshold
- [ ] Scheduler statistical check over >=100 iterations"""),

    ("18.9.2",
     "TASK 18.9.2: RaidService cooldowns + loss-cap tests",
     2, "18.9",
     """Spec: tests/server/RaidServiceCooldowns.spec.lua.

## CASES
1. raiderCooldownSeconds=360: second attempt by same raider inside 360s rejected; at 361s allowed (drive with explicit timestamps).
2. perVictimCooldownSeconds=1800: same victim untargetable within 1800s of a successful steal.
3. maxLossesPerWindow=2: after 2 losses in one window, defender cannot lose a 3rd (attempts rejected/protected per real contract).
4. maxFishPerRaid=1: a single successful raid transfers exactly 1 fish.
5. Steal-weight selection: legendaryProtection.nonStealable=true -> Legendary never selected; epicStealWeightMultiplier=0.3 -> Epic selected materially less than Common over many seeded rolls.
6. Cooldown persistence regression (14.17): cooldown fields survive the save/sanitize path — feed a profile with active cooldowns through the REAL sanitize (18.4 sibling) and assert timestamps retained (clamped to the 600s sanitize bound — assert interplay: a 1800s victim cooldown vs the 600s clamp; if sanitize clamps raid cooldowns, that's a REAL BUG from 14.17's fix — surface it loudly in a comment and file a follow-up bead).""",
     """- [ ] All 6 cases passing OR case 6 converted into a filed bug bead with evidence
- [ ] Boundary values at exact cooldown edges
- [ ] Seeded statistical check for steal weights (>=1k rolls)"""),

    ("18.9.3",
     "TASK 18.9.3: RaidService outcome-resolution authority tests (forged-input suite)",
     2, "18.9",
     """Spec: tests/server/RaidServiceOutcome.spec.lua. THE anti-exploit core — regression net for 14.16 (client-authoritative hit) and the stun exploit.

## CASES
1. Server re-derives tier: client reports markerPosition; server computes perfect/good/ok from ITS zone bounds (perfectZoneSize=0.12, goodZoneSize=0.30). Feed positions at exact boundaries.
2. Forged tier: a client claiming 'perfect' with an out-of-zone position gets the SERVER-derived tier, not the claimed one (assert resolution uses server tier).
3. successChance rolls: perfect=0.85/good=0.55/ok=0.10 — seeded rng; statistical pass over >=2k rolls per tier (tolerance documented in spec, e.g. +-3%).
4. Failed raid: no fish transferred, cooldowns still applied per real contract.
5. Stun-exploit regression: the boat-spawn path on raid capture goes through the canonical handleSpawnRequest entry ONLY — a stunned thief cannot spawn a boat via the prompt path (encode the real guard added in the fix; rg BoatService for handleSpawnRequest).
6. Duration validation: minigame result submitted impossibly fast (<< durationSeconds=8) rejected per real contract, if such a check exists — if it does NOT exist, comment + follow-up bead (timing-forgery gap).""",
     """- [ ] All 6 cases passing OR gaps filed as follow-up beads with evidence
- [ ] Forged-tier case explicitly asserts claimed value ignored
- [ ] Statistical chance checks seeded + tolerance documented"""),

    ("18.10",
     "TASK 18.10: QuestService unit tests (rotation, progress, claim-once)",
     2, "E18",
     """Spec: tests/server/QuestService.spec.lua against REAL src/server/QuestService.lua (236 lines).

## CASES
1. Key rotation: dailyQuestKey (YYYY-MM-DD) and weeklyQuestKey (YYYY-Www) — a profile with yesterday's key gets fresh daily quests on initialize; weekly likewise.
2. Quest generation: generated set matches GameConfig quest definitions (ids valid, targets positive).
3. Progress: increment path adds exact amounts, clamps at target, fires QuestProgressChanged through the real path (DataModel-dependent part may move to e2e — comment if split).
4. Claim: reward granted exactly once — second claim rejected; Coins delta exact.
5. Expiry: quests from a stale key are not claimable after rotation.
6. Regression anchor: recent quest-hooks fix (see git log 'analytics API, quest hooks') — encode the hook firing order as a test if the fix touched progress wiring.""",
     """- [ ] All 6 cases passing
- [ ] Claim-once asserted with exact Coin arithmetic
- [ ] Rotation tested with explicit key strings (no date faking)"""),

    ("18.11",
     "TASK 18.11: AntiExploitService unit tests (rate-limit windows, log caps)",
     2, "E18",
     """Spec: tests/server/AntiExploitService.spec.lua against REAL src/server/AntiExploitService.lua (139 lines).

## CASES
1. Every RATE_LIMITS entry honored at its boundary: cast 5/10s, store 10/10s, sell 10/10s, buy 10/10s, lock 5/10s, raid_attempt 5/60s, get_state 20/10s (read the real table first — assert whatever it actually declares; mismatch with docs = comment). Call exactly maxCalls -> all allowed; call maxCalls+1 within window -> rate_limited.
2. Window slide: after windowSeconds elapse (explicit injected timestamps if the API accepts them; else real short sleeps kept <2s total), calls allowed again; old timestamps pruned.
3. Per-player isolation: player A limited does not affect player B.
4. Unknown action: assert real behavior (allow or deny by default — encode reality; comment if deny-by-default is NOT the behavior, since that's a hardening gap).
5. logSuspicious: entries appended with action+reason; per-player log capped at 50 — 60 calls leave exactly 50, oldest dropped.
6. Memory bound: callHistory for a leaving player is cleaned (real cleanup path) — no unbounded growth.

NOTE: checkRate(player, action) signature — if it takes a Player instance, fabricate the minimal real-shaped table the implementation actually reads (document fields used) or test inside the DataModel bucket; no mocking frameworks.""",
     """- [ ] All 6 cases passing
- [ ] Boundary assertions at exact maxCalls for every action
- [ ] Unknown-action default behavior documented in comment"""),

    ("18.12",
     "TASK 18.12: CollectionService + OnboardingService + AuditLogService unit tests",
     2, "E18",
     """Spec: tests/server/MetaServices.spec.lua against the REAL three small services (293 + 140 + 110 lines).

## CollectionService
1. Discovery: new species catch -> DiscoveredSpecies updated exactly once (repeat catch no dup).
2. Milestones: claimable at threshold; reward granted exactly (Coins delta); MilestonesClaimed prevents double-claim.
3. RequestCollection payload matches real discovery state.

## OnboardingService
4. Idempotence: mark(HasCompletedIntro) twice -> still true, no error, no side effects; every known flag accepted; unknown flag rejected per real contract.
5. Persistence shape: flags live under Onboarding in PlayerProfile.

## AuditLogService
6. Ring bound: 1001 appended entries -> exactly 1000 retained, oldest evicted (FIFO).
7. Entry shape: action, actor, timestamp, payload present.
8. Read path returns most-recent-first or insertion order per real contract (encode reality).

WHY bundled: three small services with one shared theme — bounded, idempotent bookkeeping. Splitting further adds ceremony without coverage value.""",
     """- [ ] All 8 cases passing
- [ ] Double-claim and duplicate-discovery cases present
- [ ] Ring-buffer boundary at exactly 1000 asserted"""),

    # ═══ EPIC 18 — gate ═══
    ("18.13",
     "TASK 18.13: Coverage measurement + enforcement gate",
     2, "E18",
     """Blocked by 18.2-18.12. Turns 'we wrote tests' into 'we can prove coverage'.

## DELIVERABLES
1. Coverage approach for Luau: evaluate (a) luacov under lune for the pure bucket, (b) function-call instrumentation via a require-wrapper that records which exported functions were exercised (NO behavior change — observation only, not mocking), (c) TestEZ + manual checklist of exported functions per module. Choose the lightest that produces a real number; record decision in comment.
2. Coverage report artifact: per-module function coverage %, written to testlogs/coverage.txt (and printed).
3. Gate: scripts/run_tests.sh fails (exit 1) if any in-scope module drops below threshold. Thresholds: 100% of exported functions exercised for GameConfig, DataManager pure helpers, AntiExploitService, QuestService, FishInventoryService, ShopService; >=90% for AquariumService, RaidService, FishingService, CollectionService, OnboardingService, AuditLogService (remaining % = DataModel-bound paths covered by EPIC 19 instead — each uncovered function must be listed in the report with a one-line reason).
4. Definition-of-done documentation: 'full unit coverage without mocks' is defined as the above — every exported function of every in-scope module executed at least once against the real implementation, plus the assertion density already encoded by 18.2-18.12.""",
     """- [ ] Coverage tool chosen + decision comment posted
- [ ] Report lists every exported function per in-scope module: covered or reason-not-covered
- [ ] Gate fails the suite below thresholds
- [ ] Uncovered-function reasons all reference EPIC 19 e2e tasks"""),
]


TASKS += [
    # ═══ EPIC 19 — harness ═══
    ("19.1",
     "TASK 19.1: E2E harness — runner + TestLogger structured logging",
     1, "E19",
     """Blocked by 18.1 (reuses its TestEZ install + test.project.json). Two subtasks: 19.1.1 TestLogger, 19.1.2 runner spike.

## WHY
EPIC 18 proves units; this epic proves the WIRED GAME. Every e2e scenario needs (a) a way to boot the real place headless (or scripted-in-Studio) and (b) the detailed structured logging that is this epic's whole point.

## HARNESS SHAPE
- A server-side E2E bootstrap (in the test place only, NEVER in default.project.json) that: waits for the real init.server.lua wiring to finish, hands scenarios a real test Player (the Studio player), exposes real server-side helpers (force raid window via RaidService's real API, credit coins via the same session-mutation path the income loop uses — labeled TEST-ONLY, guarded so they cannot load in production).
- Scenario scripts drive REAL remotes from a client script, exactly like a real player would.
- Zero stubs of game code anywhere.""",
     """- [ ] Both subtasks closed
- [ ] Test-only helpers provably absent from production place (rojo build default.project.json contains no e2e code)
- [ ] One scenario skeleton (19.2) demonstrated end-to-end"""),

    ("19.1.1",
     "TASK 19.1.1: TestLogger module — JSONL structured logs, state dumps, summaries",
     1, "19.1",
     """Deliverable: tests/e2e/TestLogger.lua (shared by all scenarios).

## REQUIRED FEATURES
1. JSONL events, one per line: {ts (ISO8601 UTC), level (DEBUG/INFO/STEP/ASSERT/ERROR), scenario, step, msg, data}.
2. Scenario lifecycle API: startScenario(id, description), step(id, description), assertEq(name, expected, actual) / assertTrue / assertNear(tolerance), finish() — every assert logs expected vs actual; on failure ALSO logs a full state dump (GetState snapshot + relevant local state).
3. Remote-call logging helper: wrapRemote(name, fn, args) logs the call args, response payload, and latency for every remote invocation — this is what makes the logs 'great and detailed' for audits.
4. Sinks: print() (captured by runner stdout) AND file append under testlogs/<scenario>-<runid>.jsonl where the environment allows file writes (document where it cannot).
5. Summary report: per-run totals (scenarios pass/fail, asserts run, durations) printed last and written to testlogs/summary-<runid>.json.
6. Timer API: timeIt(name, fn) for perf-sensitive flows (income tick timing).

NO external deps; pure Luau so it runs in both lune and DataModel buckets.""",
     """- [ ] All 6 features implemented
- [ ] A failure in a demo scenario produces a JSONL line containing full state dump
- [ ] Every remote call in demo scenario logged with args+response+latency
- [ ] Summary file written with counts and durations"""),

    ("19.1.2",
     "TASK 19.1.2: E2E runner spike — headless place execution with captured output",
     1, "19.1",
     """This machine (2026-07-22) lacks Studio, wine, run-in-roblox. Spike in order:
A) cargo install run-in-roblox + verify Roblox Studio presence; if Studio absent, attempt the documented Linux options (grimdark/wine) ONLY if quick — do not burn hours; instead
B) produce scripts/run_e2e.sh that: builds the test place via rojo, launches the runner, streams Output to stdout AND testlogs/run-<runid>.log, propagates exit code (0 pass / 1 test fail / 2 env fail), and fails LOUDLY with exact install instructions when Studio is missing (no silent skip).
C) Document in a bead comment the verified working path (or the precise external requirement: OS, Studio version, command) so any agent can execute cold.

Also: the bootstrap must detect 'running under test place' vs production and refuse to load e2e code in production (place file name / RunService:IsStudio() + a test-only flag module).""",
     """- [ ] scripts/run_e2e.sh exists with 0/1/2 exit semantics
- [ ] Missing-Studio failure is loud + actionable (exact commands)
- [ ] Verified-path comment posted (what works on THIS machine)
- [ ] Production place provably excludes e2e bootstrap"""),

    # ═══ EPIC 19 — flows ═══
    ("19.2",
     "TASK 19.2: E2E — player lifecycle (join, load, dock claim, snapshot, leave, save)",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Lifecycle.lua.

## STEPS (each logged via TestLogger)
1. Boot real place; assert all 18 services initialized (probe via GetState shape + leaderstats existence).
2. Fresh join: DataManager.load produces default v2 profile (Coins=0, rod 1); leaderstats created; AnalyticsService 'tutorial_started' fires (observe via AuditLogService real log where applicable).
3. Dock claim: exactly one of 8 docks assigned to the player; claim reflected in state snapshot.
4. Initial StateSync snapshot received client-side; assert schema keys (Coins, Equipment, Aquarium, dailyQuests, weeklyQuests, dataStoreHealthy flag).
5. QuestService.initializeQuests populated daily+weekly quest lists.
6. Leave: save completes (isShutdown path), DockManager.release frees the dock; rejoin gets the SAME dock class of experience with saved Coins.
ASSERT + log before/after snapshots at every step.""",
     """- [ ] All 6 steps asserted + JSONL logged
- [ ] Before/after state dumps attached to every assert
- [ ] Scenario passes via scripts/run_e2e.sh"""),

    ("19.3",
     "TASK 19.3: E2E — fishing loop (cast, bite, minigame submit, catch)",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Fishing.lua. Drive the REAL remote chain: RequestCast -> CastState event -> BiteEvent -> SubmitCatchInput -> CastResult.

## STEPS
1. RequestCast accepted; CastState arrives with casting=true + deadline + rod preview; log all payload fields.
2. BiteEvent arrives within castTime+biteWindow for the equipped rod; log actual latency.
3. SubmitCatchInput with a REAL computed position inside the perfect zone -> CastResult success; inventory +1; fish has SpeciesId/Rarity/Value; state snapshot Coins/inventory consistent.
4. Whiff path: submit an out-of-zone position -> failure result, no fish, retry-ready state.
5. Rate-limit path: 6 casts in <10s -> 6th rejected (rate_limited) — ties into 18.11 with a real remote.
6. Zone/bait variation: assert equipped rod/bait alter roll inputs (observe via repeated seeded catches where deterministic, else statistical with logged sample size).

LOG: every remote call wrapped (args, response, latency); failure dumps full state.""",
     """- [ ] All 6 steps passing + logged
- [ ] Both success and failure minigame paths covered
- [ ] Rate-limit rejection observed through the real remote"""),

    ("19.4",
     "TASK 19.4: E2E — aquarium economy (store, income ticks, claim, sell)",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Economy.lua.

## STEPS
1. Seed: catch fish via the REAL fishing flow (reuse 19.3 helpers — real path, no injection).
2. Store: RequestStoreFish moves carried -> StoredFish; snapshot shows exact records; capacity math correct.
3. Income: wait through real income ticks (IncomeTickSeconds=1); assert UnclaimedIncome grows by exactly sum(IncomePerMinute)/60 per second across N ticks (tolerance +-1 tick; logged).
4. Claim: RequestClaimIncome -> Coins delta EXACTLY equals claimed pool; pool resets to 0.
5. Sell-all: RequestSellFish -> Coins delta equals sum of sell values; StoredFish emptied.
6. Capacity rejection: fill to Capacity via repeated real stores; next store rejected; log rejection payload.
7. Locked-sell regression (14.6): lock aquarium, attempt sell, assert real post-fix behavior.

WHY: the passive-income loop is the retention engine and was the site of the dead claimButton P0 (14.1) — this scenario walks that exact button's remote.""",
     """- [ ] All 7 steps passing + logged
- [ ] Coin deltas asserted exactly at each economic transition
- [ ] 14.6 regression covered end-to-end"""),

    ("19.5",
     "TASK 19.5: E2E — shop purchases (rod, bait, capacity; insufficient funds)",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Shop.lua.

## STEPS
1. Seed funds via the test-only server helper that credits the session through the SAME code path the income claim uses (real mutation, labeled test-only); log the credit event.
2. Buy rod tier 2 via RequestPurchaseUpgrade: Coins deducted exactly (500), Equipment.UnlockedRodLevels updated, RodService equip observed in snapshot.
3. Buy bait tier 2 (300): same assertions.
4. Buy capacity upgrade tier I (30 capacity): Aquarium.Capacity reflects upgrade; exact cost.
5. Tier-skip attempt (tier 3 before 2): rejected per real contract; state unchanged.
6. Insufficient funds: spend down, attempt purchase -> rejected, zero mutation (deep-compare snapshot).
7. Rate-limit: >10 buy calls in 10s -> rate_limited.

LOG: full snapshot before/after each purchase with the Coins delta called out.""",
     """- [ ] All 7 steps passing + logged
- [ ] Exact-cost assertions from real GameConfig tables
- [ ] Zero-mutation proofs on every rejection"""),
]


TASKS += [
    ("19.6",
     "TASK 19.6: E2E — persistence round-trip + v1->v2 migration against a REAL DataStore",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Persistence.lua. REQUIRES Studio with 'Enable Studio Access to API Services' — when unavailable, the scenario must SKIP with an explicit ERROR-level log line (never silently pass).

## SETUP
Use a DEDICATED test DataStore (e.g. HarborHeist_E2E_Test_v2 / _v1) so real player data is never touched; throwaway key per run (e2e_<runid>).

## STEPS
1. Round-trip: join -> mutate (catch/store/claim/buy via real flows from 19.3-19.5) -> force real save -> reload profile straight from the test DataStore -> field-by-field deep diff vs session state; log every field compared (one ASSERT line per field group).
2. Rejoin simulation: new session load from the same key -> state matches post-mutation snapshot exactly.
3. Migration: write a REAL v1-format payload into the legacy test store (shape per 18.4.2 fixture) -> load through DataManager -> assert v2 structure + preserved values + immediate v2 write-back occurred + v1 payload still intact.
4. Corruption: write garbage into the v2 key -> load -> assert sanitize path produces a playable default, ERROR log emitted, no crash.
5. Dirty-flag coalescing: trigger N rapid saves, assert trailing-save behavior per real implementation (observable via DataStore request counting where possible; else log-based inference — comment which).

LOG: DataStore request/response payloads (redacting nothing — test data), latencies, retry counts.""",
     """- [ ] All 5 steps passing against a real test DataStore (or loud-skip proven when API access absent)
- [ ] Deep field-by-field diff logged
- [ ] Migration preserves exact values and leaves v1 intact
- [ ] Dedicated test store + throwaway keys provably used"""),

    ("19.7",
     "TASK 19.7: E2E — lock/defense flow (activate, cooldown, free uses, expiry)",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Defense.lua.

## STEPS
1. RequestActivateLock: snapshot shows LockUntilTimestamp=now+60, LockCooldownUntilTimestamp=now+120, LockFreeUsesRemaining decremented (3->2); log all three.
2. While locked: aquarium interactions that should be blocked are blocked (assert per real contract — raid targeting covered in 19.8); sell/store behavior per 14.6 fix contract.
3. Double-activate while locked: rejected, state unchanged.
4. Activate during cooldown: rejected with the real reason payload.
5. Free-use exhaustion: burn remaining free uses (via test-only time acceleration on the REAL lock function if available — else document real-time cost and keep scenario short by testing the transition logic at boundaries) -> paid path engages per real contract.
6. Expiry: after lock duration, Locked=false and raid-eligibility restored (time-accelerated through real API or asserted at timestamp math level + short real wait).

LOG every timestamp asserted with the actual os.time() at assertion moment (drift transparency).""",
     """- [ ] All 6 steps passing + logged
- [ ] Zero-mutation proof on both rejection paths
- [ ] Any time-acceleration used is via real service APIs, commented"""),

    ("19.8",
     "TASK 19.8: E2E — raid system (automated single-player + 2-player runbook)",
     2, "E19",
     """Umbrella. 19.8.1 = fully automated single-player coverage of window/opt-in plumbing. 19.8.2 = scripted TWO-CLIENT Studio runbook for the actual steal (headless solo Studio cannot fabricate a second real Player — honest limit, documented).

Split rationale: everything automatable is automated; the irreducibly 2-player part becomes a rigorous, logged, repeatable runbook instead of the current ad-hoc manual playtest (feeds bead 13.1).""",
     """- [ ] Both subtasks closed
- [ ] Automated portion runs via scripts/run_e2e.sh
- [ ] Runbook produces comparable JSONL logs from both clients"""),

    ("19.8.1",
     "TASK 19.8.1: E2E — raid window + opt-in plumbing (automated, single-player)",
     2, "19.8",
     """Scenario: tests/e2e/scenarios/RaidPlumbing.lua.

## STEPS
1. Force-open a raid window via the test-only server helper calling RaidService's REAL window API; RaidWindowChanged broadcast observed client-side with correct remaining time; log payload.
2. RequestToggleRaidOptIn(true): PvP.RaidOptIn=true in snapshot; log.
3. GetRaidTargets: with only the test player in-session, assert self-exclusion (own dock absent) and empty/eligible-list semantics per real contract; log full target list.
4. RequestRaidAttempt with no valid target: rejected with real reason; zero mutation.
5. raid_attempt rate limit: >5 attempts/60s -> rate_limited.
6. Window close: forced close broadcast observed; opt-in state persistence per real contract (assert whether opt-in resets or carries — encode reality, comment if surprising).
7. SubmitRaidResult without an active attempt: rejected (protocol desync guard — regression anchor from R2's verified invariants).""",
     """- [ ] All 7 steps passing + logged
- [ ] Broadcast payloads logged verbatim
- [ ] Self-exclusion asserted explicitly"""),

    ("19.8.2",
     "TASK 19.8.2: E2E — two-player raid runbook (scripted 2-client Studio test, semi-manual)",
     2, "19.8",
     """Deliverable: docs/E2E_RAID_RUNBOOK.md + an in-game assertion harness (tests/e2e/scenarios/RaidTwoPlayer.lua) that BOTH clients auto-load under the test place, which logs every step and fails loudly on assertion violations (so the human runner only verifies 'both clients printed PASS').

## RUNBOOK OUTLINE (bead expands each into numbered, expected-result steps)
1. Setup: Studio Test -> 2 Players, test place; both clients load harness; runid shared via a lobby code both testers type (or server-assigned pairing id logged on both).
2. Both players fish + store (real flows) so defender has stealable fish (non-Legendary, plus one Legendary to verify protection).
3. Force raid window (server console command provided by harness); both opt in.
4. Raider: GetRaidTargets contains defender; RequestRaidAttempt; play minigame twice — once deliberately PERFECT, once deliberately whiffed.
5. PERFECT attempt: assert (both clients' logs) success roll respected, exactly 1 fish transferred, defender loss count 1, per-victim cooldown started, Legendary NOT among stealable candidates.
6. Whiffed attempt: no transfer, raider cooldown 360s enforced on retry.
7. Loss cap: engineer 2 successful steals in one window -> 3rd attempt blocked (maxLossesPerWindow=2).
8. Stun/boat: on capture, stunned thief cannot spawn boat via prompt (stun-exploit regression); canonical spawn path still works.
9. Logs: both clients write JSONL; runner merges testlogs/*-2p-*.jsonl into the summary.

HUMAN time estimate: ~20 min. Every step has an explicit EXPECTED + LOGGED-AS pair.""",
     """- [ ] Runbook written with numbered steps + expected results
- [ ] In-game harness asserts automatically (human checks PASS/FAIL, not game state)
- [ ] All 9 outline areas covered
- [ ] Merged JSONL from both clients produced"""),

    ("19.9",
     "TASK 19.9: E2E — abuse & anti-exploit battery (spam, forgery, bad payloads)",
     2, "E19",
     """Scenario: tests/e2e/scenarios/Abuse.lua. The hostile-client suite — everything an exploiter would try, driven through REAL remotes.

## CASES (each: action -> expected rejection -> assert zero state mutation -> assert logSuspicious/rate-limit side effects per real contract)
1. Spam every RemoteFunction past its limit (cast/store/sell/buy/lock/raid_attempt/get_state at the real RATE_LIMITS) -> rate_limited responses; server suspicious-log entries asserted via AuditLogService where visible.
2. Forged fishing tier: SubmitCatchInput claiming perfect with out-of-zone position -> server-derived tier used (mirror of 18.9.3 at the wire level).
3. Impossible timing: SubmitCatchInput/SubmitRaidResult far outside the real windows -> rejected.
4. Bad payloads: wrong types (string for number), negative amounts, huge numbers, nils, tables-with-holes -> rejected, no crash; server stays healthy (subsequent GetState OK).
5. Unknown/never-registered remote names invoked via raw RemoteFunction path -> error handled (assert server does not crash).
6. Replay: same purchase/store request fired twice rapidly -> exactly one effect.
7. Currency forgery: any client attempt to set Coins directly (no such remote exists — assert NO remote exposes it; rg the client for StateChanged writes and assert client never mutates server state).

LOG: every forged call's args + server response verbatim; this file doubles as the security audit trail.""",
     """- [ ] All 7 case groups passing + logged
- [ ] Server health asserted after the battery (GetState still OK)
- [ ] Zero-mutation proof attached to every rejection"""),

    # ═══ EPIC 19 — CI/docs ═══
    ("19.10",
     "TASK 19.10: CI wiring, docs, and gap-filing (unit + e2e one command)",
     1, "E19",
     """Blocked by 18.13 and 19.2-19.9. Final integration.

## DELIVERABLES
1. scripts/test_all.sh: runs unit suite (18.x) then e2e suite (19.x); aggregate exit code; prints both summaries; designed for CI (no TTY assumptions).
2. testlogs/ artifact discipline: .gitignore entry, retention note, CI upload step (if/when CI exists — repo has none today; add a minimal CI config ONLY if the team wants one, else document the manual gate: run before every release per EPIC 13).
3. README.md + AGENTS.md: new 'Testing' section — how to run unit tests, e2e, the 2-player runbook, and the no-mocks rule for future tests (CONTRIBUTING-grade guidance so no agent adds a mock framework later).
4. Gap-filing: run the suites, file br beads for EVERY failure or uncovered gap discovered (linked with discovered-from deps to this task).
5. Bead hygiene: comment on 13.1 (manual playthrough) noting which scenarios are now automated so the manual runbook shrinks.
6. UBS on all changed files before commit; br sync --flush-only; commit + push per AGENTS.md landing protocol.""",
     """- [ ] scripts/test_all.sh exits non-zero on any failure
- [ ] Docs updated (README + AGENTS Testing section)
- [ ] Every discovered gap filed as a bead with discovered-from link
- [ ] Comment posted on 13.1 mapping automated coverage
- [ ] UBS clean on changed files; landed per protocol"""),
]

# ─────────────────────────────────────────────────────────────────────────────
# DEPENDENCIES (issue_key blocked by depends_on_key) — 'blocks' edges
# ─────────────────────────────────────────────────────────────────────────────

DEPS = [
    # Epic 18 harness gates everything
    ("18.1", "18.1.1"), ("18.1", "18.1.2"),
] + [("18.%d" % i, "18.1") for i in range(2, 13)] + [
    # coverage gate needs all spec tasks
    ("18.13", "18.%d" % i) for i in range(2, 13)
] + [
    # umbrella tasks gated by their subtasks
    ("18.4", "18.4.1"), ("18.4", "18.4.2"), ("18.4", "18.4.3"),
    ("18.9", "18.9.1"), ("18.9", "18.9.2"), ("18.9", "18.9.3"),
    # Epic 19 harness + flows
    ("19.1", "19.1.1"), ("19.1", "19.1.2"),
    ("19.1", "18.1"),  # e2e harness reuses unit TestEZ install
] + [("19.%d" % i, "19.1") for i in range(2, 10)] + [
    ("19.8", "19.8.1"), ("19.8", "19.8.2"),
    # raid plumbing scenario also leans on raid unit knowledge
    ("19.8.1", "18.9"),
    # persistence e2e leans on migration unit coverage
    ("19.6", "18.4"),
    # abuse e2e leans on rate-limit unit coverage
    ("19.9", "18.11"),
    # CI/docs last
    ("19.10", "18.13"),
] + [("19.10", "19.%d" % i) for i in range(2, 10)]



# ─────────────────────────────────────────────────────────────────────────────
# COMMENTS (target_key, text) — provenance + coordination context
# ─────────────────────────────────────────────────────────────────────────────

COMMENTS = [
    ("E18",
     "Provenance: created 2026-07-22 by ChartreuseFox (Abacus AI) at direct user request: 'Do we have full unit test coverage without mocks? If not, create a comprehensive granular set of beads.' Verified beforehand: zero spec/test files, no TestEZ, no runner — this epic is greenfield, no duplicate of any existing bead (nearest neighbors are MANUAL playtest beads 13.1 / 16.5, which stay manual until EPIC 19 lands).\n\nWorking agreement for whoever picks this up: the no-mocks rule is the whole point. If a module seems untestable without a fake, the correct move is a MINIMAL pure-helper extraction in the module under test (review first), moving the case to the EPIC 19 e2e bucket, or filing a gap bead — never introducing a mock framework. Seed randomness with Random.new(seed); pass clocks in explicitly.\n\nEnv snapshot 2026-07-22: rojo + selene + cargo present; Studio/lune/run-in-roblox absent. 18.1.2 owns the runner decision."),
    ("E19",
     "Provenance: created 2026-07-22 by ChartreuseFox at direct user request ('complete e2e integration test scripts with great, detailed logging'). Greenfield — no e2e infra exists today.\n\nRelationship to existing beads: 13.1 (manual full playthrough) and 16.5 (playtest tuning) remain valid; 19.10 includes shrinking the manual runbook as scenarios automate. This epic deliberately does NOT close or alter those beads.\n\nHard honesty constraint: solo headless Studio cannot produce a second real Player, so the actual PvP steal is a scripted 2-client runbook (19.8.2), not a fake. Test-only server helpers must use real service code paths and must be provably excluded from the production place (default.project.json stays clean)."),
    ("18.1",
     "Environment findings to save the next agent a probe: present = rojo (/usr/local/bin/rojo), selene, cargo/rustc, ast-grep, rg, br 0.2.11 (beads), bd 0.49.0 (broken DB migration — do not use), uv/python3. Missing = Roblox Studio, wine, sober, lune, run-in-roblox, foreman/aftman/wally, stylua. Recommendation: vendor TestEZ as source (no package manager needed), use lune for the pure-Luau bucket (single prebuilt binary, easiest path on this box), and keep the DataModel bucket behind scripts/run_tests.sh --datamodel with a loud missing-Studio error."),
    ("18.13",
     "Clarifying 'full unit test coverage' for this repo (per user phrasing): every exported function of every in-scope module executed at least once against the REAL implementation, with the assertion density encoded by 18.2-18.12. In-scope = GameConfig, FishDefinitions, ZoneDefinitions, FishInstance, PlayerProfile, DataManager (pure parts), FishingService, AquariumService, ShopService, FishInventoryService, RaidService, QuestService, AntiExploitService, CollectionService, OnboardingService, AuditLogService. Out of unit scope (e2e instead) = WorldBuilder, DockManager, RodService, BoatService, StateSync, Remotes, AnalyticsService, init.server.lua wiring — each exclusion must appear in the coverage report with its EPIC 19 covering task."),
    ("19.8",
     "Why the split: run-in-roblox / solo Studio yields exactly ONE real Player instance. Roblox offers no API to fabricate a second real Player server-side, and a hand-rolled 'virtual player' table would be exactly the kind of fake this project forbids — it would bypass DataManager.load, DockManager.claim, and the real client remote path. Therefore: window/opt-in/plumbing is automated with the one real player (19.8.1), and the steal itself is a rigorous scripted 2-client runbook (19.8.2) that upgrades today's ad-hoc manual testing into logged, assertion-driven runs."),
]

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main():
    guard_no_duplicates()

    ids = {}
    failures = 0

    epic18 = br_create(EPIC18_TITLE, "epic", 1, None, EPIC18_DESC)
    epic19 = br_create(EPIC19_TITLE, "epic", 1, None, EPIC19_DESC)
    if not epic18 or not epic19:
        print("ABORT: epic creation failed", file=sys.stderr)
        sys.exit(1)
    ids["E18"] = epic18
    ids["E19"] = epic19
    print(f"created {epic18} = {EPIC18_TITLE}")
    print(f"created {epic19} = {EPIC19_TITLE}")

    for key, title, prio, parent_key, desc, ac in TASKS:
        parent_id = ids.get(parent_key)
        if not parent_id:
            print(f"FAIL: unknown parent key {parent_key} for {key}", file=sys.stderr)
            failures += 1
            continue
        bead_id = br_create(title, "task", prio, parent_id, desc)
        if not bead_id:
            failures += 1
            continue
        ids[key] = bead_id
        if not br_update_ac(bead_id, ac):
            failures += 1
        print(f"created {bead_id} = {title}")

    for issue_key, dep_key in DEPS:
        a, b = ids.get(issue_key), ids.get(dep_key)
        if not a or not b:
            print(f"FAIL dep {issue_key} <- {dep_key}: missing id", file=sys.stderr)
            failures += 1
            continue
        if not br_dep_add(a, b):
            failures += 1

    for target_key, text in COMMENTS:
        t = ids.get(target_key)
        if not t:
            failures += 1
            continue
        if not br_comment(t, text):
            failures += 1

    out, err, rc = run(["br", "dep", "cycles"])
    print("dep cycles check:", out or err or "(clean)")

    map_path = REPO + "/scripts/epic18_19_bead_id_map.json"
    with open(map_path, "w") as f:
        json.dump(ids, f, indent=2, sort_keys=True)
    print(f"wrote {map_path}")
    print(f"DONE: {len(ids)} beads ({failures} failures). Run: br sync --flush-only && git add .beads/ && commit")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
