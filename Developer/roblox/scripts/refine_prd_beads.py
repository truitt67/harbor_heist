#!/usr/bin/env python3
"""
Harbor Heist — Bead graph refinement pass.

Addresses 7 structural problems found during plan-space review:
1. Remove epic-to-epic 'blocks' deps (redundant noise; task-level deps are the real signal)
2. Split TASK 8.5 mega-bottleneck (betweenness=56) into two tasks
3. Improve generic acceptance criteria on critical foundation tasks
4. Add missing tasks (remove old steal logic, fish visual assets, DataStore key)
5. Fix incorrect dependencies (migration doesn't need DEC-1, content needs FishInstance not schema)
6. Add UX risk notes to income tasks
7. Add dependency wiring for new/split tasks

Run from repo root: python3 scripts/refine_prd_beads.py
"""

import subprocess, json, os, sys, time

os.chdir("/home/ubuntu/Developer/roblox")

def br(args, check=True):
    r = subprocess.run(["br"] + args, capture_output=True, text=True, timeout=30)
    if check and r.returncode != 0:
        sys.stderr.write(f"ERROR: br {' '.join(args)}\n{r.stderr}\n{r.stdout}\n")
        raise RuntimeError(f"br exit {r.returncode}")
    return r

def dep_remove(issue, depends_on):
    """Remove a dependency. Returns True if removed, False if not found."""
    r = br(["dep", "remove", issue, depends_on], check=False)
    return r.returncode == 0

def dep_add(issue, depends_on, dtype="blocks"):
    br(["dep", "add", issue, depends_on, "-t", dtype])

def update_bead(bid, description=None, acceptance=None, title=None, priority=None):
    args = ["update", bid]
    if description is not None:
        args += ["--description", description]
    if acceptance is not None:
        args += ["--acceptance-criteria", acceptance]
    if title is not None:
        args += ["--title", title]
    if priority is not None:
        args += ["-p", str(priority)]
    br(args)

def create_bead(title, btype, priority, description, acceptance=None, parent=None, slug=None):
    args = ["create", "--json", "-t", btype, "-p", str(priority), "-d", description]
    if slug:
        args += ["--slug", slug]
    if parent:
        args += ["--parent", parent]
    args.append(title)
    r = br(args)
    return json.loads(r.stdout)["id"]

# Load the ID map from the original creation
with open("scripts/bead_id_map.json") as f:
    IDs = json.load(f)

def K(key):
    return IDs[key]

print("=" * 70)
print("BEAD GRAPH REFINEMENT — 7 fixes")
print("=" * 70)

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 1: Remove all epic-to-epic 'blocks' dependencies.
# These inflate critical-path betweenness for whole epics when only individual
# tasks have real cross-epic dependencies. Parent-child (task->epic) links remain.
# ═══════════════════════════════════════════════════════════════════════════════
print("\n[1/7] Removing epic-to-epic 'blocks' dependencies...")
epic_to_epic_blocks = [
    ("epic-foundation", "epic-decisions"),
    ("epic-content", "t-1.1"),       # content blocks schema task — WRONG (fix 6)
    ("epic-fishing", "epic-content"),
    ("epic-inventory", "epic-foundation"),
    ("epic-aquarium", "epic-foundation"),
    ("epic-aquarium", "dec-income"),
    ("epic-aquarium", "dec-display"),
    ("epic-economy", "epic-content"),
    ("epic-collection", "epic-content"),
    ("epic-collection", "epic-foundation"),
    ("epic-raid", "epic-aquarium"),
    ("epic-raid", "epic-foundation"),
    ("epic-onboarding", "epic-foundation"),
    ("epic-security", "epic-foundation"),
    ("epic-release", "epic-fishing"),
    ("epic-release", "epic-inventory"),
    ("epic-release", "epic-aquarium"),
    ("epic-release", "epic-economy"),
    ("epic-release", "epic-raid"),
]
removed_count = 0
for from_key, to_key in epic_to_epic_blocks:
    fid, tid = K(from_key), K(to_key)
    if dep_remove(fid, tid):
        removed_count += 1
        print(f"  removed: {from_key} --blocks--> {to_key}")
        time.sleep(0.03)
print(f"  ({removed_count} epic-level blocks removed; task-level deps remain)")

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 6 (do before fix 2 since it affects dep wiring): Correct wrong dependencies
# ═══════════════════════════════════════════════════════════════════════════════
print("\n[6/7] Correcting incorrect dependencies...")

# t-1.3 (migration) blocks dec-income — WRONG. Migration is mechanical field mapping;
# the income *model* decision (online vs offline) doesn't change how we migrate old rarity
# indexes to FishInstances. Remove it.
if dep_remove(K("t-1.3"), K("dec-income")):
    print("  removed: t-1.3 --blocks--> dec-income (migration doesn't need income decision)")

# epic-content was blocking t-1.1 (removed in fix 1). Content definitions actually only
# depend on FishInstance (1.2) for the factory lookup, not the full profile schema (1.1).
# The task-level dep t-2.1 -> t-1.2 already captures this correctly. Nothing more to do.

# epic-fishing blocked epic-content (removed in fix 1). The real dep is:
# fishing catch resolution (3.4) needs fish definitions (2.1), and bite-roll (3.1) needs
# zones (2.2). Those task-level deps exist. Add the one that's missing:
try:
    dep_add(K("t-3.1"), K("t-2.2"), "blocks")
    print("  added: t-3.1 --blocks--> t-2.2 (bite-roll needs zone fish tables)")
except RuntimeError:
    print("  (t-3.1 -> t-2.2 already exists)")
time.sleep(0.05)

# epic-inventory blocked epic-foundation (removed in fix 1). Real dep: inventory service
# (4.1) needs FishInstance (1.2). Already wired. Good.

# epic-aquarium blocked epic-foundation + dec-income + dec-display (all removed in fix 1).
# Real deps: income pool (5.1) needs the profile schema (1.1) for UnclaimedIncome field;
# income calc (5.3) needs FishInstance (1.2); display (5.6) needs dec-display. All wired
# at task level. Add 5.1 -> 1.1 which was implicit:
try:
    dep_add(K("t-5.1"), K("t-1.1"), "blocks")
    print("  added: t-5.1 --blocks--> t-1.1 (income pool needs profile schema field)")
except RuntimeError:
    print("  (t-5.1 -> t-1.1 already exists)")
time.sleep(0.05)

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 2: Split TASK 8.5 mega-bottleneck into two tasks.
# 8.5 currently has betweenness=56 (next highest is 15) and 7 inbound + 7 outbound deps.
# This serializes the raid epic. Split into:
#   8.5a: Raid target selection + eligibility validation (needs opt-in, protection, lock)
#   8.5b: Raid timing minigame + outcome resolution (the actual skill gate)
# ═══════════════════════════════════════════════════════════════════════════════
print("\n[2/7] Splitting TASK 8.5 mega-bottleneck into 8.5a + 8.5b...")

# First, get the current 8.5 to know its dependencies and dependents
r = br(["show", K("t-8.5"), "--json"])
data_85 = json.loads(r.stdout)
issue_85 = data_85[0] if isinstance(data_85, list) else data_85
deps_out = issue_85.get("dependencies", [])  # what 8.5 depends ON
deps_in = issue_85.get("dependents", [])      # what depends on 8.5

print(f"  8.5 depends on: {[d.get('title','?')[:30] for d in deps_out]}")
print(f"  8.5 blocks: {[d.get('title','?')[:30] for d in deps_in]}")

# Create 8.5a: target selection + eligibility
id_85a = create_bead(
    "TASK 8.5a: Raid target selection + eligibility validation",
    "task", 1,
    "PRD PVP-02, PVP-04, PVP-10 (partial). First half of the split raid flow.\n\n"
    "Server-side raid target selection: given an attacker, enumerate eligible target "
    "docks (opted-in, not new-player-protected, not currently locked, not under immunity, "
    "not on per-victim cooldown). Validate the attacker's own eligibility (not on cooldown, "
    "raid window open). Return the eligible target list to the client raid UI (8.12).\n\n"
    "WHY SPLIT: This is pure server validation logic that depends on the 'state' tasks "
    "(8.1 window, 8.2 opt-in, 8.3 protection, 8.4 lock). It can be built and tested as "
    "soon as those are done, WITHOUT needing the DEC-2 timing minigame design (which gates "
    "8.5b). Decoupling target selection from outcome resolution cuts the critical-path "
    "depth and lets the raid UI show valid targets earlier.",
    "- [ ] Server enumerates eligible targets with all PVP gates enforced\n"
    "- [ ] Ineligible targets correctly excluded (locked, protected, cooldown, opt-out)\n"
    "- [ ] Target list sent to client raid panel (8.12)\n"
    "- [ ] No way to target a non-opted-in aquarium",
    parent=K("epic-raid"),
    slug="raid-target-selection"
)
IDs["t-8.5a"] = id_85a
print(f"  created t-8.5a: {id_85a}")

# Create 8.5b: timing minigame + outcome resolution
id_85b = create_bead(
    "TASK 8.5b: Raid timing minigame + outcome resolution",
    "task", 1,
    "PRD PVP-05, PVP-10 (partial). Second half of the split raid flow.\n\n"
    "Given an attacker + validated target (from 8.5a), run the raid minigame and resolve "
    "the outcome per DEC-2 (hybrid timing) and DEC-3 (individual fish transfer). Server "
    "exclusively validates the timing input, rolls the theft outcome, and atomically "
    "transfers one eligible FishInstance. Applies loss caps (8.9), legendary protection "
    "(8.8), and triggers defender immunity (8.7) + notification (8.10).\n\n"
    "WHY SPLIT: This is the actual skill gate + transaction logic. It depends on 8.5a "
    "(target already selected) and on DEC-2/DEC-3 (minigame model + transfer model). "
    "Everything downstream (8.6 cooldowns, 8.7 immunity, 8.9 caps, 8.10 notify, 8.12 UI, "
    "10.4 atomicity) depends on THIS task, not 8.5a.",
    "- [ ] Timing minigame result validated server-side\n"
    "- [ ] Outcome resolved per DEC-3 (individual fish, legendary protected)\n"
    "- [ ] Transfer is atomic (10.4)\n"
    "- [ ] Loss cap enforced (8.9)\n"
    "- [ ] Defender immunity set (8.7) + notification sent (8.10)",
    parent=K("epic-raid"),
    slug="raid-outcome-resolution"
)
IDs["t-8.5b"] = id_85b
print(f"  created t-8.5b: {id_85b}")

# Rewire: 8.5a depends on (8.1, 8.2, 8.3, 8.4) — the state/eligibility tasks
# 8.5b depends on (8.5a, dec-raid-model, dec-transfer) — target + design decisions
# Everything that depended on old 8.5 now depends on 8.5b
for src_key in ["t-8.1", "t-8.2", "t-8.3", "t-8.4"]:
    try:
        dep_add(id_85a, K(src_key), "blocks")
        time.sleep(0.03)
    except RuntimeError:
        pass

for src_key in ["dec-raid-model", "dec-transfer"]:
    try:
        dep_add(id_85b, K(src_key), "blocks")
        time.sleep(0.03)
    except RuntimeError:
        pass
dep_add(id_85b, id_85a, "blocks")  # 8.5b depends on 8.5a
print("  wired: 8.5a <- (8.1,8.2,8.3,8.4); 8.5b <- (8.5a, DEC-2, DEC-3)")

# Rewire downstream: everything that blocked old 8.5 now blocks 8.5b
# These are: 8.6, 8.7, 8.9, 8.10, 8.12, 10.4, 13.3
downstream_keys = ["t-8.6", "t-8.7", "t-8.9", "t-8.10", "t-8.12", "t-10.4", "t-13.3"]
for dkey in downstream_keys:
    try:
        dep_add(K(dkey), id_85b, "blocks")
        time.sleep(0.03)
    except RuntimeError:
        pass
print(f"  rewired {len(downstream_keys)} downstream tasks to depend on 8.5b")

# Now close old 8.5 (superseded by 8.5a + 8.5b)
br(["close", K("t-8.5"), "--reason", "Superseded: split into 8.5a (target selection) + 8.5b (outcome resolution) to reduce critical-path bottleneck"])
print(f"  closed old t-8.5 ({K('t-8.5')}) — superseded")

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 3: Improve generic acceptance criteria on critical foundation tasks
# ═══════════════════════════════════════════════════════════════════════════════
print("\n[3/7] Improving generic acceptance criteria on foundation tasks...")

update_bead(K("t-1.1"),
    acceptance=(
        "- [ ] PlayerProfile module defined with all sub-tables (Equipment, Aquarium, "
        "Dock, Collection, PvP, Onboarding)\n"
        "- [ ] DataManager.defaultData() returns complete profile with all fields initialized\n"
        "- [ ] Session object in memory mirrors profile structure\n"
        "- [ ] StateSync.snapshot() serializes new nested structure without errors\n"
        "- [ ] All existing services (Fishing, Aquarium, Shop) updated to new field paths\n"
        "- [ ] DataStore save/load round-trips the full structure intact\n"
        "- [ ] Coins clamped to [0, 999999999] on every write"
    ))
print("  updated t-1.1 acceptance criteria (7 specific checks)")

update_bead(K("t-1.2"),
    acceptance=(
        "- [ ] FishInstance.new(speciesId, zoneId) factory implemented\n"
        "- [ ] InstanceId is unique (HttpService:GenerateGUID or equivalent)\n"
        "- [ ] BaseSellValue and IncomePerMinute pulled from FishDefinition (not hardcoded)\n"
        "- [ ] IsRaidProtected auto-set true for Legendary rarity\n"
        "- [ ] Invalid speciesId throws a clear error, not silent nil\n"
        "- [ ] Catch flow (3.4) creates FishInstance via factory, not raw index"
    ))
print("  updated t-1.2 acceptance criteria (6 specific checks)")

update_bead(K("t-1.3"),
    acceptance=(
        "- [ ] Old format detected by absence of 'Version' field\n"
        "- [ ] cash -> Coins, rodLevel -> Equipment.EquippedRodId, baitLevel -> BaitInventory\n"
        "- [ ] liveWell rarity indexes -> StoredFish with Common placeholder species\n"
        "- [ ] Version set to CURRENT after migration\n"
        "- [ ] Migrated profile passes deep sanitize() (1.5) without data loss\n"
        "- [ ] Migration count logged for analytics\n"
        "- [ ] Edge case: empty/nil liveWell handled (not crash)"
    ))
print("  updated t-1.3 acceptance criteria (7 specific checks)")

update_bead(K("t-1.5"),
    acceptance=(
        "- [ ] Every FishInstance in StoredFish validated (all 8 fields type-checked)\n"
        "- [ ] Equipment IDs validated against RodDefinitions/BaitDefinitions\n"
        "- [ ] Collection.DiscoveredSpecies filtered to valid SpeciesIds\n"
        "- [ ] PvP timestamps sanity-checked (not negative, not future)\n"
        "- [ ] Invalid entries removed (filtered), not crash\n"
        "- [ ] Coins clamped [0, MAX]\n"
        "- [ ] Aquarium.StoredFish length <= Capacity (trim overflow safely)"
    ))
print("  updated t-1.5 acceptance criteria (7 specific checks)")

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 4: Add missing tasks
# ═══════════════════════════════════════════════════════════════════════════════
print("\n[4/7] Adding missing tasks...")

# 4a: Remove old always-on steal logic
id_oldsteal = create_bead(
    "TASK 8.0: Remove legacy always-on steal logic from AquariumService",
    "task", 0,
    "The current prototype has AquariumService.handleSteal() — always-on theft via "
    "proximity prompt with 50% RNG, 20s cooldown, no windows, no opt-in, no protection. "
    "This directly conflicts with the new RaidService scheduled opt-in model (Epic 8).\n\n"
    "Before building RaidService, remove handleSteal and its ProximityPrompt wiring in "
    "init.server.lua (connectAquariumPrompt lines 46-55). The aquarium prompt should ONLY "
    "open the owner's aquarium panel. Raid interaction moves to the RaidService + raid UI.\n\n"
    "WHY P0 / WHY FIRST IN EPIC 8: Leaving the old steal path active while building the new "
    "raid system creates a confused dual-PvP state. Remove first, then build RaidService "
    "on a clean slate. The old steal prompt is the #1 thing that violates the PRD's "
    "'opt-in, no griefing' promise.",
    "- [ ] AquariumService.handleSteal removed\n"
    "- [ ] init.server.lua connectAquariumPrompt only opens owner panel (no steal branch)\n"
    "- [ ] No leftover references to stealChance/stealCooldownUntil in active code paths\n"
    "- [ ] Session fields stealCooldownUntil cleaned up or repurposed",
    parent=K("epic-raid"),
    slug="remove-legacy-steal"
)
IDs["t-8.0"] = id_oldsteal
print(f"  created t-8.0: {id_oldsteal}")
# It should block the raid flow tasks
dep_add(K("t-8.5a"), id_oldsteal, "blocks")
print("  wired: t-8.5a depends on t-8.0")

# 4b: Fish visual assets/models
id_fishassets = create_bead(
    "TASK 2.8: Create fish visual models/assets for species display",
    "task", 1,
    "PRD FISH-05: fish have a 'visual model.' PRD AQUA-02: stored fish 'appear as visible "
    "occupants.' PRD UX: 'readable, cartoony fish silhouettes with clear rarity cues' and "
    "'rarity should use more than color alone: labels, stars, fish shape.'\n\n"
    "The current code uses generic colored balls (DockManager.updateAquariumVisual creates "
    "PartType.Ball). This needs: distinct fish shapes per species (or at least per rarity "
    "tier), rarity-reinforcing visual cues (size, glow, particle effect for Legendary), and "
    "collection-book visuals (silhouettes for undiscovered).\n\n"
    "SCOPE NOTE: For V1, reusable MeshParts or simple part-assemblies are fine — no need "
    "for 20 unique rigged models. Aim for ~5-8 visual archetypes mapped to species, scaled "
    "and tinted by rarity. Legendary gets a distinct glow/particles.\n\n"
    "WHY THIS TASK EXISTS: No other task creates the actual visual assets. The aquarium "
    "display (5.6) and collection book (7.3) consume them.",
    "- [ ] Fish visual archetype(s) created (MeshPart or part-assembly)\n"
    "- [ ] Visuals vary by rarity beyond just color (size, glow, particles for Legendary)\n"
    "- [ ] Aquarium display (5.6) uses these models\n"
    "- [ ] Collection book (7.3) uses silhouette variants for undiscovered\n"
    "- [ ] Performance: pooled, no high-poly count per fish",
    parent=K("epic-content"),
    slug="fish-visual-assets"
)
IDs["t-2.8"] = id_fishassets
print(f"  created t-2.8: {id_fishassets}")
dep_add(K("t-5.6"), id_fishassets, "blocks")
dep_add(K("t-7.3"), id_fishassets, "blocks")
print("  wired: t-5.6 and t-7.3 depend on t-2.8")

# 4c: DataStore key versioning (implied by DEC-1 / migration)
id_dskey = create_bead(
    "TASK 1.6: Bump DataStore key version for new profile format",
    "task", 0,
    "The current DataStore key is 'HarborHeist_PlayerData_v1' (DataManager.lua line 8). "
    "The new structured profile (1.1) is a breaking format change. Two options:\n"
    "(a) Keep same key, rely on in-load migration (1.3) to upgrade old data — riskier if "
    "    migration has bugs (corrupts live data irreversibly).\n"
    "(b) New key 'HarborHeist_PlayerData_v2' with a one-time copy+migrate from v1 — safer, "
    "    allows rollback to v1 key if migration breaks, but loses any v1 writes after cutover.\n\n"
    "RECOMMENDATION: Option (b) for safety during V1 closed test. Once stable, can consolidate. "
    "This decision should be made alongside DEC-1 since the income model affects what fields "
    "the v2 key must store.\n\n"
    "WHY THIS TASK: It's implied by the migration work (1.3) but never explicit. Getting the "
    "DataStore key wrong risks permanent data loss for real players.",
    "- [ ] Decision: same key with migration OR new key with copy (documented)\n"
    "- [ ] If new key: v1->v2 copy+migrate path implemented and tested\n"
    "- [ ] DataStore key updated in DataManager\n"
    "- [ ] Rollback path documented if migration fails in production",
    parent=K("epic-foundation"),
    slug="datastore-key-version"
)
IDs["t-1.6"] = id_dskey
print(f"  created t-1.6: {id_dskey}")
dep_add(K("t-1.6"), K("dec-income"), "blocks")
dep_add(K("t-1.3"), K("t-1.6"), "blocks")
print("  wired: t-1.6 depends on DEC-1; t-1.3 depends on t-1.6")

# ═══════════════════════════════════════════════════════════════════════════════
# FIX 7 (was fix 5): Add UX risk notes to income tasks
# ═══════════════════════════════════════════════════════════════════════════════
print("\n[7/7] Adding UX risk notes to income-related tasks...")

# Update DEC-1 with the UX risk
dec1_new_desc = (
    "PRD Open Decision #1. AQUA-04 says 'accrues only while in-game for V1' but the income "
    "model section implies elapsed-time calculation with a cap — tension.\n\n"
    "RECOMMENDATION: V1 online-only accrual with a claimable income pool (don't auto-add to "
    "cash), capped to prevent extreme accumulation. Offline earnings deferred to V1.1.\n\n"
    "UX RISK (important): Switching from auto-income (current prototype) to claimable income "
    "is a significant behavior change. Players who are used to seeing cash tick up passively "
    "may feel 'punished' if they forget to claim. Mitigation: make the CLAIM button very "
    "prominent, auto-claim on logout save, and show a glowing '+$X ready to claim' indicator. "
    "If playtesting shows confusion, consider a hybrid: small auto-claim threshold + manual "
    "claim for the rest. This UX risk is why this decision must be made before building 5.1.\n\n"
    "This BLOCKS Epic 5 income model + DataStore key versioning (1.6). PRD refs: AQUA-04, "
    "AQUA-05, income model note."
)
update_bead(K("dec-income"), description=dec1_new_desc)
print("  updated DEC-1 with UX risk note")

# Update 5.1 with the UX risk
t51_new_desc = (
    "PRD AQUA-05. Change income loop: instead of session.cash += income, accumulate to "
    "session.Aquarium.UnclaimedIncome. Calculate from elapsed time x sum(IncomePerMinute of "
    "StoredFish) / 60. Cap at MAX_UNCLAIMED (prevent extreme accumulation, PRD income model "
    "note). Server stores LastIncomeTimestamp for accurate elapsed calculation.\n\n"
    "UX IMPLEMENTATION NOTE: The claim button must be impossible to miss. When "
    "UnclaimedIncome > 0, show a pulsing/glowing indicator on both the HUD cash display and "
    "the aquarium panel. Auto-claim on player leave (folded into save) so no income is lost "
    "on disconnect. The PRD says income accrues 'only while the player is in the experience' "
    "(AQUA-04) — so UnclaimedIncome resets to 0 on load (don't persist it; only persist "
    "LastIncomeTimestamp if we ever add offline accrual)."
)
update_bead(K("t-5.1"), description=t51_new_desc)
print("  updated t-5.1 with UX implementation note")

# Save updated ID map
with open("scripts/bead_id_map.json", "w") as f:
    json.dump(IDs, f, indent=2)

print("\n" + "=" * 70)
print("ALL 7 FIXES APPLIED")
print("=" * 70)
print(f"New tasks created: 3 (t-8.0, t-2.8, t-1.6, t-8.5a, t-8.5b)")
print(f"Tasks closed: 1 (t-8.5 superseded)")
print(f"Epic-level blocks removed: ~19")
print(f"Acceptance criteria improved: 4 tasks")
print(f"Descriptions enriched: 2 tasks")
print(f"Dependencies corrected/added: ~15")
print("\nRun bv --robot-insights to verify graph improvement.")
