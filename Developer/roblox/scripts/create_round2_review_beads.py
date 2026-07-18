#!/usr/bin/env python3
"""
Bulk-create beads for the Round-2 dual-pass code review (2026-07-18) and the
two new feature requests that emerged from it (CastResult wiring, Dock
upgrade tree).

Run from /home/ubuntu/Developer/roblox:
    python3 scripts/create_round2_review_beads.py

This script is idempotent-safe: it checks for existing epic titles before
creating, and prints a clear map of what it created.
"""

import subprocess
import json
import time
import sys

REPO = "/home/ubuntu/Developer/roblox"


def br(args, timeout=30):
    """Run br with args, return stdout. Raise on failure."""
    r = subprocess.run(
        ["br"] + args,
        capture_output=True,
        text=True,
        timeout=timeout,
        cwd=REPO,
    )
    if r.returncode != 0:
        raise RuntimeError(f"br {' '.join(args[:2])} failed (exit {r.returncode}):\n{r.stderr[:500]}")
    return r.stdout


def create_bead(title, btype, priority, description, parent=None, slug=None):
    """Create a bead, return its ID."""
    args = ["create", "--json", "-t", btype, "-p", str(priority)]
    if slug:
        args += ["--slug", slug]
    if parent:
        args += ["--parent", parent]
    args += ["-d", description, title]
    result = json.loads(br(args))
    bid = result["id"]
    time.sleep(0.08)  # be gentle to SQLite
    return bid


def add_dep(from_id, to_id, dep_type="blocks"):
    """Add a dependency edge."""
    br(["dep", "add", from_id, to_id, "-t", dep_type])
    time.sleep(0.05)


def set_criteria(bid, criteria):
    """Set acceptance criteria on a bead."""
    br(["update", bid, f"--acceptance-criteria={criteria}"])
    time.sleep(0.05)


def title_exists(title_fragment):
    """Check if a bead with this title already exists."""
    data = json.loads(br(["list", "--all", "--json", "--limit", "200"]))
    for issue in data.get("issues", []):
        if title_fragment.lower() in issue.get("title", "").lower():
            return issue["id"]
    return None


# ════════════════════════════════════════════════════════════════════════════
# BEAD DEFINITIONS
# ════════════════════════════════════════════════════════════════════════════

# Each bead: (key, title, type, priority, slug, description, parent_key)
# Deps: (from_key, to_key, dep_type) — parent-child is auto-created by --parent

BEADS = [
    # ────────────────────────────────────────────────────────────────────────
    # EPIC 15: Round-2 Code Review — Dual-Pass Bug Hunt
    # ────────────────────────────────────────────────────────────────────────
    (
        "epic-round2",
        "EPIC 15: Round-2 Dual-Pass Code Review (2026-07-18)",
        "epic",
        0,
        "round2-review",
        """BACKGROUND: On 2026-07-17, all 19 Lua source files were written/modified in a single burst (~22:28-22:37 UTC) as part of the PRD-compliance implementation push (Epics 1-9). The next session was wiped by a daily reset, so the review had to reconstruct 'what was just written' from file mtimes before it could review anything.

METHODOLOGY: A dual-pass review was executed per the ultrathink-analysis skill's recommended pattern for >5-file reviews:
  1. PARENT PASS — Full read of every file by the primary reviewer, tracing cross-references and checking against the PRD.
  2. SUBAGENT PASS — An independent background audit subagent read all 19 files with the distilled server-authority-gap-checklist (11 exploit/bug classes from the Harbor Heist round-1 review).
  3. RECONCILIATION — ~60% overlap confirmed findings; ~40% were unique to one pass.

RESULTS: 13 bugs found and fixed, 2 design decisions flagged for user input, 4 new bug classes added to the skill's checklist. All fixes syntax-verified via `luau` compiler.

This epic tracks ALL findings from that session — both the fixed bugs (for record-keeping and regression-prevention) and the two design decisions that need user input. Each bug bead links to the relevant existing EPIC 14 task where one exists.

WHY THIS EPIC EXISTS: The existing EPIC 14 (Post-Review Hardening) was created from the round-1 review. This epic captures the round-2 findings, many of which are NEW bug classes (raw-parameter deref, client-server kind mismatch, cosmetic-field-on-nonexistent-session, advertised-multiplier-never-applied) that round-1's checklist didn't cover. The skill's reference file (server-authority-gap-checklist.md) was extended with entries #12-15 to capture these.

CONSIDERATIONS:
- 3 bugs were CRITICAL (would crash or silently break core gameplay on first use)
- 5 bugs were HIGH (features non-functional, progression broken)
- The subagent found 2 issues the parent pass missed (TOCTOU steal, dead code)
- 4 new bug classes were distilled and added to the permanent checklist
- Two items were flagged as DESIGN DECISIONS (not bugs): the dead CastResult remote and the brutal honest-client catch rate. These became EPIC 16 and a task in EPIC 6 respectively.""",
        None,
    ),

    # BUG 15.1: nil-deref on first join (CRITICAL, FIXED)
    (
        "bug-15.1",
        "BUG 15.1 [FIXED]: DataManager nil-deref on first join (data.dailyQuestKey)",
        "bug",
        0,
        "bug-15-1-nil-deref-first-join",
        """SEVERITY: CRITICAL — 100% reproducible crash on EVERY new player's first join.

ROOT CAUSE: DataManager.load() (line 335) read `data.dailyQuestKey` from the raw saved-data parameter, but `data` is nil for brand-new players (no DataStore entry) or when the datastore load fails. Indexing nil throws "attempt to index nil with 'dailyQuestKey'", crashing the session initialization.

WHY IT WAS MISSED: The sanitize() call above it (`local profile = sanitize(saved)`) looks like it handles everything, so the later `data.dailyQuestKey` reads seem safe. But `data` is the original function parameter, not the sanitized output. This only crashes on first join or datastore failure — easy to miss in testing if you always have existing save data.

FIX APPLIED (N2): Read from `profile.dailyQuestKey` (the sanitized result, guaranteed non-nil) instead of `data.dailyQuestKey`.

This is a NEW bug class (#12 in the server-authority-gap-checklist): raw-parameter dereference in load functions. Added to the skill's permanent checklist.

FILES: src/server/DataManager.lua:335-338
RELATED: No existing EPIC 14 task covered this. Supersedes the round-1 assumption that load paths were safe.""",
        "epic-round2",
    ),

    # BUG 15.2: migration overwrite (CRITICAL, FIXED)
    (
        "bug-15.2",
        "BUG 15.2 [FIXED]: Legacy liveWell migration overwritten by unconditional sanitizeStoredFish(nil)",
        "bug",
        0,
        "bug-15-2-migration-overwrite",
        """SEVERITY: CRITICAL — silent total fish loss for v1 saves with a partial Aquarium table.

ROOT CAUSE: In DataManager.sanitize(), line 146 ran `clean.Aquarium.StoredFish = sanitizeStoredFish(aq.StoredFish)` UNCONDITIONALLY. When `aq.StoredFish` is nil (a v1 save with only `liveWell`), `sanitizeStoredFish(nil)` returns `{}`, overwriting the fish just migrated from `liveWell` at line 107.

The round-1 review (EPIC 14, TASK 14.2) identified this class and added a "fix" at line 172, but the guard was in the WRONG PLACE — it re-ran sanitizeStoredFish when `aq.StoredFish` WAS a table (redundant), instead of guarding line 146 where the actual clobbering happened.

FIX APPLIED (N3): Made line 146 conditional (`if type(aq.StoredFish) == "table" then`). Removed the redundant line-172 block.

This is checklist item #3 (Legacy Migration Overwrite) — the same class as round-1, but the round-1 fix was incomplete. The lesson: when adding a guard, verify it guards the ACTUAL overwrite site, not a redundant re-execution.

FILES: src/server/DataManager.lua:146-153 (was 146 unconditional + 172-174 redundant)
RELATED: harborheist-wqw.2 (TASK 14.2: Fix legacy v1->v2 liveWell migration overwrite bug) — this is the SAME bug; the round-1 fix was incomplete.""",
        "epic-round2",
    ),

    # BUG 15.3: quest rewards not credited (CRITICAL, FIXED)
    (
        "bug-15.3",
        "BUG 15.3 [FIXED]: Quest rewards never credited — session.cash does not exist",
        "bug",
        0,
        "bug-15-3-quest-rewards-not-credited",
        """SEVERITY: CRITICAL — quest completion shows "+$X" toast but credits ZERO coins, AND errors silently ("arithmetic on nil value").

ROOT CAUSE: QuestService.processList (line 87) wrote `session.cash += q.reward`. The session object (DataManager.lua:311-339) has no `cash` field — money lives at `session.profile.Coins`. The `session.cash +=` operation creates a new transient field that is never read by anything and never persisted. Worse, `+=` on nil errors with "attempt to perform arithmetic on a nil value" inside the quest loop.

FIX APPLIED (N4): Replaced with:
  session.profile.Coins = PlayerProfile.clampCoins(session.profile.Coins + q.reward)
  session.profile.TotalCoinsEarned = session.profile.TotalCoinsEarned + q.reward

This routes through clampCoins (matching every other coin-grant path) and tracks lifetime earnings. Added `require(PlayerProfile)` import to QuestService.

IMPACT: Every daily and weekly quest (11 templates, 3 daily + 2 weekly slots) was silently broken. Players could see the completion notification but received no reward. The error happened inside a loop in a potentially task.spawn'd context, so it may have silently broken ALL quest progression (not just the completing quest).

FILES: src/server/QuestService.lua:1 (import), 87-92 (fix)""",
        "epic-round2",
    ),

    # BUG 15.4: lock/alarm/capacity upgrade system non-functional (HIGH, FIXED)
    (
        "bug-15.4",
        "BUG 15.4 [FIXED]: Lock/Alarm/Capacity upgrade system non-functional (5-file chain broken)",
        "bug",
        1,
        "bug-15-4-upgrade-system-broken",
        """SEVERITY: HIGH — 3 of 5 shop upgrade categories were unbuyable AND non-functional even if purchased.

ROOT CAUSE: A 5-file chain of broken connections:
  1. PlayerProfile.default() had NO LockLevel/AlarmLevel fields (sanitize dropped them)
  2. DataManager.sanitize() wrote them to top-level `clean.lockLevel` (orphan fields, not in schema)
  3. ShopService.BuyItem returned `bad_kind` for "lock"/"alarm" (only handled rod/bait/aquarium)
  4. Client sent kind="capacity" but server only accepted "aquarium" (kind mismatch)
  5. Client built shop rows from GameConfig.Upgrades.Capacity (3 entries) but server sold from GameConfig.AquariumUpgradeTiers (4 entries, different prices)
  6. AquariumService read `victimSession.alarmLevel` (nonexistent session field) — alarms never triggered
  7. AquariumService lock-duration scaling was a stub (`if UpgradeLevel > 1 then -- future`)
  8. StateSync.snapshot didn't expose any upgrade levels — client always saw 0
  9. RodService.read `session.rodLevel` (nonexistent) — rod visual always level 1

FIX APPLIED (N5-N10):
  - Added LockLevel, AlarmLevel to PlayerProfile.Aquarium schema
  - Sanitize persists them in the nested Aquarium table + maps legacy top-level fields
  - ShopService handles "lock", "alarm" kinds with proper catalog + currentLevel dispatch
  - Client sends "aquarium" (not "capacity") and uses AquariumUpgradeTiers catalog
  - Client KIND_META and refreshShop use "aquarium" key consistently
  - AquariumService.handleSteal reads profile.Aquarium.AlarmLevel
  - AquariumService.LockAquarium scales duration/cooldown from Upgrades.Lock[lockLevel]
  - StateSync.snapshot exposes upgradeLevel, lockLevel, alarmLevel
  - RodService reads profile.Equipment.EquippedRodLevel
  - Removed dead KIND_CATALOGS/getCatalog from ShopService

This is checklist item #13 (Client-Server Kind/String Mismatch) and #14 (Cosmetic Field On Nonexistent Session Attribute). Both added to the permanent checklist.

FILES: PlayerProfile.lua, DataManager.lua, ShopService.lua, AquariumService.lua, StateSync.lua, RodService.lua, GameConfig.lua, init.client.lua
RELATED: harborheist-wqw.9 (TASK 14.9: Activate or remove dead upgrade-tier config tables) and harborheist-wqw.23 (TASK 14.23). These tasks are now SUPERSEDED by this fix.""",
        "epic-round2",
    ),

    # BUG 15.5: onFishCaught never called (HIGH, FIXED)
    (
        "bug-15.5",
        "BUG 15.5 [FIXED]: onFishCaught quest hook never called + rarity type mismatch",
        "bug",
        1,
        "bug-15-5-onfishcaught-not-called",
        """SEVERITY: HIGH — 3 of 11 quest templates (catch_rarity) could never progress.

ROOT CAUSE: QuestService.onFishCaught(session, rarityIndex) was defined but never called anywhere. Even if it HAD been called, it expected a numeric rarity index, but FishInstance.Rarity is a STRING ("Common", "Rare", etc.). The comparison `rarityIndex >= (q.rarity or 1)` with a string on the left and number on the right would error in Luau.

FIX APPLIED (N11):
  1. FishingService.SubmitCatchInput now calls `questService.onFishCaught(session, fish.Rarity)` after a successful catch
  2. QuestService.onFishCaught now accepts either a string or number, normalizing via a RARITY_ORDINAL lookup table: {Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5}

IMPACT: "Catch 5 Rare+", "Catch 3 Epic+", "Catch a Legendary" quests were all dead. Now they progress on every catch that meets the rarity threshold.

FILES: src/server/QuestService.lua (onFishCaught + RARITY_ORDINAL), src/server/FishingService.lua (call site)""",
        "epic-round2",
    ),

    # BUG 15.6: unclamped coin write on steal-fence (HIGH, FIXED)
    (
        "bug-15.6",
        "BUG 15.6 [FIXED]: Unclamped coin write on steal-fence (AquariumService:282)",
        "bug",
        1,
        "bug-15-6-unclamped-steal-fence",
        """SEVERITY: HIGH — the ONLY coin-granting path in the codebase that bypassed clampCoins.

ROOT CAUSE: When an attacker's aquarium is full and they fence a stolen fish for coins, AquariumService.handleSteal did `attackerSession.profile.Coins = attackerSession.profile.Coins + stolenFish.BaseSellValue` — raw write, no clamp, no TotalCoinsEarned update.

EXPLOIT: Near the MAX_COINS ceiling (999,999,999), a large fencing payout could overflow past the cap. Also, a crafted/hijacked BaseSellValue (if sanitize regressed) could go negative — this was the one path that wouldn't clamp to >= 0.

FIX APPLIED (N12): Route through PlayerProfile.clampCoins + update TotalCoinsEarned.

This is checklist item #9 (Unclamped Economy Writes). The round-1 review caught most sites; this one was added later (the steal-fence path) and missed the clamp.

FILES: src/server/AquariumService.lua:282-285
RELATED: harborheist-security-antiexploit-xqd.4 (TASK 10.4: Transaction atomicity)""",
        "epic-round2",
    ),

    # BUG 15.7: incomeMultiplier never applied (HIGH, FIXED)
    (
        "bug-15.7",
        "BUG 15.7 [FIXED]: AquariumUpgradeTiers.incomeMultiplier advertised but never applied",
        "bug",
        1,
        "bug-15-7-income-multiplier-dead",
        """SEVERITY: HIGH — lie-to-player economy bug. Shop advertised "+50% income" for Mega Tank; calculation ignored it.

ROOT CAUSE: StateSync.incomePerSec() summed `fish.IncomePerMinute / 60` for all stored fish with no multiplier. The AquariumUpgradeTiers config defined `incomeMultiplier` (1.0 → 1.5) but nothing consumed it.

FIX APPLIED (N13): Apply `tier.incomeMultiplier` after summing fish income. Reads `session.profile.Aquarium.UpgradeLevel`, looks up the tier, multiplies the total.

IMPACT: A player who spent 8000 coins on a Mega Tank got more capacity (75 vs 20 fish) but ZERO income bonus per fish. Now they get the advertised 1.5x multiplier.

NOTE: The DockUpgradeTiers.incomeMultiplier has the SAME dead-multiplier problem. That's being addressed by EPIC 17 (Dock upgrade tree feature), not this fix.

FILES: src/server/StateSync.lua:13-25
This is checklist item #15 (Advertised Multiplier Never Applied). Added to the permanent checklist.""",
        "epic-round2",
    ),

    # BUG 15.8: rod visual always level 1 (HIGH, FIXED)
    (
        "bug-15.8",
        "BUG 15.8 [FIXED]: Rod visual always level 1 (session.rodLevel does not exist)",
        "bug",
        1,
        "bug-15-8-rod-visual-always-l1",
        """SEVERITY: HIGH (cosmetic progression) — Golden Rod buyers still saw the Basic Rod stick.

ROOT CAUSE: RodService.equip() read `session.rodLevel` — a field that doesn't exist on the session object. The equipped rod level lives at `session.profile.Equipment.EquippedRodLevel`. The `or 1` fallback meant the visual was always level 1.

This is a variant of checklist item #14 (Cosmetic Field On Nonexistent Session Attribute). The code was written against a pre-migration session schema and never updated.

FIX APPLIED (N14): `local level = (session.profile and session.profile.Equipment and session.profile.Equipment.EquippedRodLevel) or 1`

FILES: src/server/RodService.lua:151
RELATED: harborheist-wqw.10 (TASK 14.10: Consolidate Rods/RodDefinitions)""",
        "epic-round2",
    ),

    # BUG 15.9: TOCTOU steal resolution (CRITICAL, FIXED — found by subagent)
    (
        "bug-15.9",
        "BUG 15.9 [FIXED]: TOCTOU race in steal resolution — stale index could steal raid-protected fish",
        "bug",
        0,
        "bug-15-9-toctou-steal-resolution",
        """SEVERITY: CRITICAL (latent) — raid-protected Legendary fish could be stolen despite IsRaidProtected check.

FOUND BY: Background audit subagent (C6 in its report). The parent pass missed this because the race window is currently safe (single-threaded Luau, no yields between eligibility check and table.remove). But the code is FRAGILE — any future refactor that adds a yield (task.spawn, remote call) between snapshot and remove would make it exploitable.

ROOT CAUSE: handleSteal builds an `eligible` list of INDICES (positions in victimFish) for non-raid-protected fish. After the rng roll picks `stolenIndex = eligible[N]`, `table.remove(victimFish, stolenIndex)` removes at that index. If the victim sold/stored a fish between the eligibility snapshot and the remove (via a concurrent SellAll or StoreSingleFish), the indices shift, and `table.remove(victimFish, 3)` could now point at a DIFFERENT fish — possibly a raid-protected Legendary.

FIX APPLIED (N15): Capture the fish REFERENCE (not index) at selection time. Re-find it in the live list via identity comparison (`fish == targetFish`), re-validate `not fish.IsRaidProtected`, then remove. If the target vanished or became protected, fail-safe as a miss rather than stealing the wrong fish.

FILES: src/server/AquariumService.lua:264-296 (was 264-266)
RELATED: harborheist-raid-defense-system-gdj.8 (TASK 8.8: Legendary fish raid protection, PVP-08). This is the same PRD requirement; the round-1 implementation of PVP-08 had a latent race.""",
        "epic-round2",
    ),

    # BUG 15.10: dead pendingCasts (LOW, FIXED — found by subagent)
    (
        "bug-15.10",
        "BUG 15.10 [FIXED]: Dead pendingCasts table in FishingService (M2 from subagent)",
        "bug",
        3,
        "bug-15-10-dead-pendingcasts",
        """SEVERITY: LOW — dead code smell.

FOUND BY: Background audit subagent (M2 in its report).

ROOT CAUSE: FishingService.init() declared `local pendingCasts = {}` and cleared it in `failCast()` (`pendingCasts[player] = nil`), but NOTHING ever wrote to it. The actual cast state tracking uses `session.casting` + `activeBites`. The pendingCasts table was vestigial from an earlier design.

FIX APPLIED: Removed the declaration and the clear in failCast().

FILES: src/server/FishingService.lua (removed lines 23 + 28)
RELATED: harborheist-wqw.8 (TASK 14.8: Remove dead code — sanitizeNested helper). Same class of cleanup.""",
        "epic-round2",
    ),

    # ────────────────────────────────────────────────────────────────────────
    # EPIC 16: Cast-Accuracy Minigame Wiring (CastResult)
    # ────────────────────────────────────────────────────────────────────────
    (
        "epic-castresult",
        "EPIC 16: Cast-Accuracy Minigame Wiring (CastResult remote)",
        "epic",
        1,
        "castresult-wiring",
        """BACKGROUND: The codebase has TWO separate timing minigames that were both implemented but only ONE was wired end-to-end:

  1. CAST-OVERLAY MINIGAME (client lines 996-1090): Triggered by CastState:FireClient(true, castTime). Shows a marker sweeping across a bar with a green "hit zone". Player clicks to stop it. Fires `CastResult:FireServer(accuracy)`. This measures CAST ACCURACY — did you release at the right moment during the cast windup?

  2. BITE MINIGAME (client lines 1183-1304): Triggered by BiteEvent. Shows a separate ping-pong marker. Player taps to stop it. Fires `SubmitCatchInput({hit=bool})`. This measures REACTION TIMING — did you respond fast enough when the fish bit?

PROBLEM: The cast-overlay minigame was fully built (UI, animation, input handling) but `CastResult` had NO server handler. The accuracy value was fired into the void. Meanwhile, GameConfig.MiniGame.accuracyLuckBonus (perfect=25, good=12, ok=0) was defined but never consumed — a dead config table that was clearly INTENDED to be driven by the cast accuracy.

DESIGN DECISION (user-directed, 2026-07-18): Wire CastResult rather than remove the minigame. The cast-overlay becomes a skill-based luck bonus: a well-timed cast grants a temporary luck boost that improves species rarity on the subsequent catch.

HOW IT WORKS (post-wiring):
  1. Server computes authoritative hit-zone bounds (centered randomly per cast) from RodDefinitions.minigameZoneSize
  2. Server sends bounds + castDeadline to client via CastState
  3. Client renders the zone from server bounds and animates the marker
  4. Player clicks → client sends CastResult with marker position
  5. Server re-derives accuracy tier from marker position vs server-authoritative bounds
  6. Server stores luckBonus on activeBites (consumed by the catch species roll later)

This is NOT the same as the bite minigame's security mitigation (N16's rng:NextNumber > zoneSize check). The cast overlay is a BONUS mechanism, not a gate — you can still catch fish without a good cast, but a good cast shifts the odds.

WHY THIS MATTERS: The fishing loop is the core engagement loop. Right now, casting is a passive wait (castTime delay). The cast-overlay minigame adds active skill expression to the FIRST half of the loop, complementing the bite minigame's reflex test in the second half. This gives players two skill checks per catch instead of one, deepening the moment-to-moment gameplay.

CONSIDERATIONS:
- The server must be authoritative on the hit-zone bounds (not the client) to prevent "always perfect" exploits
- The luckBonus is consumed by FishDefinitions.getRandomInZone's luck parameter, which shifts weights toward rarer species
- accuracyLuckBonus values (25/12/0) are substantial — a "perfect" cast adds 25 luck, equivalent to a Golden Rod (20) + Magic Bait (15) combined. This may need balance tuning post-launch.
- The cast overlay's existing `castHitZone` client variable must be replaced with server-provided bounds

RELATED EXISTING BEADS:
- harborheist-wqw.11 (TASK 14.11: Wire rod minigameZoneSize into client timing minigame) — partially overlaps; this epic subsumes it
- harborheist-fishing-system-rework-h2e.2 (TASK 3.2: Client timing minigame UI) — closed, but only the bite minigame was wired""",
        None,
    ),

    # TASK 16.1: Server sends hit-zone bounds in CastState
    (
        "task-16.1",
        "TASK 16.1: Server sends authoritative hit-zone bounds in CastState",
        "task",
        1,
        "task-16-1-server-hitzone-bounds",
        """WHAT: Modify FishingService's Cast.OnServerEvent handler to compute per-cast hit-zone bounds from RodDefinitions and send them to the client in the CastState:FireClient call.

The client already expects a 4th argument (a table with hitZoneStart, hitZoneEnd, goodStart, goodEnd) — see init.client.lua:1402-1408. The server just wasn't sending it.

IMPLEMENTATION (partially done — this task completes and verifies it):
  1. Look up rodDef = GameConfig.RodDefinitions[equippedRodLevel]
  2. zoneSize = rodDef.minigameZoneSize or GameConfig.MiniGame.hitZoneWidth (0.3)
  3. goodSize = GameConfig.MiniGame.goodZoneWidth (0.5)
  4. Center the zone randomly: zoneCenter = rng:NextNumber(zoneSize/2, 1 - zoneSize/2)
  5. Compute bounds: hitZoneStart/End, goodStart/End
  6. Send as 4th arg: remotes.CastState:FireClient(player, true, biteDelay, { hitZoneStart=..., ... })
  7. Store bounds on activeBites for later CastResult validation

ACCEPTANCE CRITERIA:
- [ ] CastState:FireClient includes a 4th table argument with all 5 fields
- [ ] Hit-zone center is randomized per cast (not always center)
- [ ] Zone width matches the equipped rod's minigameZoneSize
- [ ] Bounds stored on activeBites for CastResult validation
- [ ] Client renders the zone from server-provided bounds (not hardcoded 0.35-0.65)

FILES: src/server/FishingService.lua (Cast.OnServerEvent handler, ~line 98)
DEPENDS ON: Nothing (config tables already exist)""",
        "epic-castresult",
    ),

    # TASK 16.2: CastResult server handler
    (
        "task-16.2",
        "TASK 16.2: Add CastResult server handler — compute accuracy tier, store luckBonus",
        "task",
        1,
        "task-16-2-castresult-handler",
        """WHAT: Add a server-side handler for the CastResult RemoteEvent. It receives the client's reported marker position, re-derives the accuracy tier from the server-authoritative bounds (stored on activeBites by TASK 16.1), and stores the resulting luckBonus.

SECURITY: The server must NOT trust the client's claimed accuracy tier. It must re-compute the tier from the raw marker position against its own bounds. A client can lie about where the marker was, but the server clamps the resulting luckBonus to the config-defined maximums.

IMPLEMENTATION:
  remotes.CastResult.OnServerEvent:Connect(function(player, accuracy)
    -- accuracy is the marker position [0,1] when the player clicked
    local biteData = activeBites[player]
    if not biteData or biteData.castResultReceived then return end
    biteData.castResultReceived = true
    -- Clamp accuracy to [0,1] (client could send out-of-range)
    accuracy = math.clamp(type(accuracy) == "number" and accuracy or 0, 0, 1)
    -- Derive tier from server-authoritative bounds
    local tier
    if accuracy >= biteData.goodStart and accuracy <= biteData.goodEnd then
      tier = "perfect"
    elseif accuracy >= biteData.hitZoneStart and accuracy <= biteData.hitZoneEnd then
      tier = "good"
    else
      tier = "ok"
    end
    biteData.luckBonus = GameConfig.MiniGame.accuracyLuckBonus[tier] or 0
  end)

ACCEPTANCE CRITERIA:
- [ ] CastResult.OnServerEvent handler registered
- [ ] Handler validates activeBites exists and isn't already processed
- [ ] Marker position clamped to [0,1]
- [ ] Tier derived from server bounds (goodStart/End → perfect, hitZoneStart/End → good, else ok)
- [ ] luckBonus set from GameConfig.MiniGame.accuracyLuckBonus[tier]
- [ ] Client cannot inflate luckBonus by sending a crafted accuracy value

FILES: src/server/FishingService.lua (new handler, after Cast.OnServerEvent block)
DEPENDS ON: TASK 16.1 (needs bounds on activeBites)""",
        "epic-castresult",
    ),

    # TASK 16.3: Apply luckBonus in catch resolution
    (
        "task-16.3",
        "TASK 16.3: Apply cast-accuracy luckBonus in catch species roll",
        "task",
        1,
        "task-16-3-apply-luckbonus",
        """WHAT: In SubmitCatchInput's catch resolution, add the cast-accuracy luckBonus to the rod+bait luck before calling FishDefinitions.getRandomInZone.

IMPLEMENTATION (one-line change at the existing luck computation):
  -- Before (current):
  local luck = rod.luck + bait.luck
  -- After:
  local luck = rod.luck + bait.luck + (biteData.luckBonus or 0)

This feeds into getRandomInZone's luck parameter, which multiplies each species' CatchWeight by (1 + luck/100 * (rarityOrder - 1)). A "perfect" cast (luckBonus=25) with a Golden Rod (luck=20) + Magic Bait (luck=15) gives total luck=60, which meaningfully shifts the species distribution toward rarer fish.

BALANCE NOTE: The accuracyLuckBonus values (25/12/0) are large relative to rod+bait luck (0-35 combined). This is intentional — cast skill should matter MORE than gear for rarity, rewarding active play. But it may need tuning after playtesting. Track in harborheist-release-prep-mxl.2 (economy balance pass).

ACCEPTANCE CRITERIA:
- [ ] biteData.luckBonus added to the luck variable in SubmitCatchInput
- [ ] A "perfect" cast measurably increases rare-fish odds (verified via test casts)
- [ ] An "ok" cast (luckBonus=0) produces the same odds as before this change
- [ ] luckBonus consumed exactly once (idempotent if handler fires twice)

FILES: src/server/FishingService.lua (SubmitCatchInput handler, ~line 207)
DEPENDS ON: TASK 16.2 (needs luckBonus on activeBites)""",
        "epic-castresult",
    ),

    # TASK 16.4: Update client cast overlay to use server bounds
    (
        "task-16.4",
        "TASK 16.4: Update client cast-overlay to render server-provided hit-zone bounds",
        "task",
        1,
        "task-16-4-client-server-bounds",
        """WHAT: The client's CastState handler (init.client.lua:1399-1449) already reads hitZone bounds from the 3rd argument, but falls back to hardcoded 0.35-0.65 when absent. Now that the server always sends bounds, update the client to:
  1. Use the server-provided goodStart/goodEnd for the "perfect zone" sub-frame
  2. Remove the hardcoded fallback (or keep it as a safety net with a comment)
  3. Position the marker glow / hit-zone frames from the server bounds

The client currently has a `castHitZone` variable (line 56) and uses it in the CastState handler. The hitZoneFrame and perfectZoneFrame (lines 1028-1048) need to be sized/positioned from the server bounds.

IMPLEMENTATION:
  - In CastState handler, read bounds from the 4th arg: bounds.hitZoneStart, bounds.hitZoneEnd, bounds.goodStart, bounds.goodEnd
  - Set hitZoneFrame.Size = UDim2.new(bounds.hitZoneEnd - bounds.hitZoneStart, 0, 1, 0)
  - Set hitZoneFrame.Position = UDim2.new(bounds.hitZoneStart, 0, 0, 0)
  - Set perfectZoneFrame relative to hitZoneFrame using goodStart/goodEnd
  - When CastResult fires, pass the marker's current X.Scale position as `accuracy`

ACCEPTANCE CRITERIA:
- [ ] Cast overlay hit-zone width visually matches the equipped rod's minigameZoneSize
- [ ] Perfect zone (brighter green) renders inside the hit zone at server-specified bounds
- [ ] Better rods visibly show a wider target zone
- [ ] Marker position sent to server as a [0,1] float in CastResult

FILES: src/client/init.client.lua (CastState handler ~1399, cast overlay setup ~996-1090)
DEPENDS ON: TASK 16.1 (server must send bounds)""",
        "epic-castresult",
    ),

    # TASK 16.5: Balance tuning for accuracyLuckBonus
    (
        "task-16.5",
        "TASK 16.5: Playtest + tune accuracyLuckBonus values (perfect=25/good=12/ok=0)",
        "task",
        2,
        "task-16-5-balance-accuracy-luck",
        """WHAT: After TASK 16.1-16.4 are wired, playtest the cast-accuracy luck bonus and tune the values in GameConfig.MiniGame.accuracyLuckBonus if needed.

CURRENT VALUES: { perfect = 25, good = 12, ok = 0 }

CONCERN: These values are large relative to rod+bait luck (0-35 combined). A "perfect" cast with a Basic Rod (luck=0) + Basic Bait (luck=0) gives luck=25, which is more than a Golden Rod (luck=20). This means a skilled new player can out-fish a geared but unskilled player — which is arguably GOOD (rewards skill over grind) but may feel bad for players who spent coins on gear.

TUNING OPTIONS:
  A) Keep as-is (skill > gear) — rewards active engagement, may frustrate gear-focused players
  B) Reduce to perfect=15/good=7/ok=0 — gear matters more, skill is a smaller bonus
  C) Scale with rod tier — better rods amplify the accuracy bonus (synergy between gear + skill)

This is a BALANCE decision, not an implementation task. Defer to playtest data. Create a follow-up bead if tuning is needed.

ACCEPTANCE CRITERIA:
- [ ] Playtested 50+ casts across rod tiers 1-3 with varying accuracy
- [ ] Rare/Epic/Legendary catch rates feel rewarding but not trivial
- [ ] Decision documented (keep / adjust / scale) with reasoning

FILES: src/shared/GameConfig.lua:53-57 (if adjusted)
DEPENDS ON: TASK 16.3 (must be wired before playtesting), harborheist-release-prep-mxl.2 (economy balance pass)""",
        "epic-castresult",
    ),

    # ────────────────────────────────────────────────────────────────────────
    # EPIC 17: Dock Upgrade Tree Feature
    # ────────────────────────────────────────────────────────────────────────
    (
        "epic-dock",
        "EPIC 17: Dock Upgrade Tree Feature",
        "epic",
        1,
        "dock-upgrade-tree",
        """BACKGROUND: The DockUpgradeTiers config table (GameConfig.lua:105-110) defines 4 tiers with incomeMultiplier (1.0 → 1.6) and cosmetic unlocks (LampPost, Planters, GoldenTrim). This config has existed since the initial PRD-compliance implementation but was NEVER WIRED — there's no purchase path, no income-multiplier consumption, no cosmetic rendering, and no UI.

The round-2 review (EPIC 15) flagged this as checklist item #15 (Advertised Multiplier Never Applied). The user directed: "wire as feature."

DESIGN: Dock upgrades are an INCOME MULTIPLIER progression path, distinct from Aquarium upgrades (which add capacity + a smaller income multiplier). This gives players two parallel investment tracks:
  - Aquarium upgrades: more fish capacity + moderate income multiplier (1.0-1.5)
  - Dock upgrades: NO capacity change, but a LARGER income multiplier (1.0-1.6) + cosmetic flair

This creates a meaningful choice: do you spend 8000 on a Mega Tank (more fish, 1.5x) or 10000 on a Golden Trim dock (same fish, 1.6x + cosmetics)? The answer depends on playstyle — hoarders want capacity, min-maxers want the higher multiplier.

PRD ALIGNMENT:
  - TASK 2.6 (closed) defined the tier structure
  - TASK 6.4 (open) covers the purchase flow — this epic IMPLEMENTS it
  - The cosmetic unlocks (LampPost, Planters, GoldenTrim) are per-tier visual rewards

WHY THIS MATTERS: The income loop (store fish → earn passive income → buy upgrades → store more fish) is the core retention loop. Adding a second upgrade track doubles the progression depth without adding new mechanics — it's pure economy expansion using existing systems.

CONSIDERATIONS:
- DockUpgradeTiers is 1-indexed (level 1 = base, free). Purchases start at level 2.
- The income multiplier STACKS with the Aquarium multiplier (both apply in incomePerSec). A maxed player (Aquarium 4 + Dock 4) gets 1.5 * 1.6 = 2.4x base income per fish.
- Cosmetic unlocks need visual implementation (lamp posts, planters, gold trim on the dock model). This is scoped as a separate task (TASK 17.5) and can be deferred post-launch if needed.
- The profile already has `Dock = { UpgradeLevel = 1, CosmeticUnlocks = {} }` — the schema is ready.

RELATED EXISTING BEADS:
- harborheist-economy-upgrade-system-pdq.4 (TASK 6.4: Dock upgrade purchase + income multiplier) — this epic fulfills it
- harborheist-game-content-definitions-pmr.6 (TASK 2.6: Dock upgrade tiers) — closed, defined the config""",
        None,
    ),

    # TASK 17.1: Add name/desc to DockUpgradeTiers
    (
        "task-17.1",
        "TASK 17.1: Add display name + desc to DockUpgradeTiers config entries",
        "task",
        1,
        "task-17-1-dock-tier-names",
        """WHAT: The DockUpgradeTiers entries currently have only { level, cost, incomeMultiplier, cosmeticUnlocks }. Add `name` and `desc` fields so the shop can display them (matching the pattern used for AquariumUpgradeTiers in BUG 15.4's fix).

PROPOSED VALUES:
  { level = 1, name = "Basic Dock",        cost = 0,     incomeMultiplier = 1.0,  cosmeticUnlocks = {}, desc = "Your starting dock" }
  { level = 2, name = "Lamp-Lit Dock",     cost = 1200,  incomeMultiplier = 1.15, cosmeticUnlocks = { "LampPost" }, desc = "+15% income, adds lamp posts" }
  { level = 3, name = "Garden Dock",       cost = 4000,  incomeMultiplier = 1.35, cosmeticUnlocks = { "LampPost", "Planters" }, desc = "+35% income, adds planters" }
  { level = 4, name = "Golden Harbor Dock",cost = 10000, incomeMultiplier = 1.6,  cosmeticUnlocks = { "LampPost", "Planters", "GoldenTrim" }, desc = "+60% income, golden trim" }

ACCEPTANCE CRITERIA:
- [ ] All 4 DockUpgradeTiers entries have name + desc fields
- [ ] Names are distinct and evocative (not "Dock 1", "Dock 2")
- [ ] Descs mention the income multiplier % and cosmetic unlock

FILES: src/shared/GameConfig.lua:105-110
DEPENDS ON: Nothing""",
        "epic-dock",
    ),

    # TASK 17.2: Add dock kind to ShopService
    (
        "task-17.2",
        "TASK 17.2: Add 'dock' kind to ShopService.BuyItem handler",
        "task",
        1,
        "task-17-2-dock-shop-handler",
        """WHAT: Add a `dock` branch to the BuyItem dispatch (matching the pattern for rod/bait/aquarium/lock/alarm added in BUG 15.4).

IMPLEMENTATION:
  elseif kind == "dock" then
    catalog = GameConfig.DockUpgradeTiers
    currentLevel = session.profile.Dock.UpgradeLevel or 1

And in the apply-upgrade section:
  elseif kind == "dock" then
    session.profile.Dock.UpgradeLevel = level
    -- Cosmetic unlocks are derived from the tier, no need to store separately
    -- (but profile.Dock.CosmeticUnlocks exists if we want to track which are active)

ACCEPTANCE CRITERIA:
- [ ] BuyItem accepts kind="dock" and dispatches to DockUpgradeTiers
- [ ] currentLevel reads from profile.Dock.UpgradeLevel
- [ ] Upgrade applied to profile.Dock.UpgradeLevel
- [ ] Sequential tier enforcement works (must buy level N+1 when at N)
- [ ] Cost deducted via clampCoins

FILES: src/server/ShopService.lua (BuyItem handler)
DEPENDS ON: TASK 17.1 (config must have names for the purchase notification)""",
        "epic-dock",
    ),

    # TASK 17.3: Apply dock incomeMultiplier in incomePerSec
    (
        "task-17.3",
        "TASK 17.3: Apply DockUpgradeTiers.incomeMultiplier in StateSync.incomePerSec",
        "task",
        1,
        "task-17-3-dock-income-multiplier",
        """WHAT: After the Aquarium multiplier (BUG 15.7 fix), also apply the Dock tier's incomeMultiplier. These stack multiplicatively.

IMPLEMENTATION (extends the N13 fix):
  -- After the aquarium multiplier block:
  local dockLevel = session.profile.Dock.UpgradeLevel or 1
  local dockTier = GameConfig.DockUpgradeTiers[dockLevel]
  if dockTier and dockTier.incomeMultiplier then
    total *= dockTier.incomeMultiplier
  end

BALANCE: A maxed player (Aquarium 4: 1.5x, Dock 4: 1.6x) gets 1.5 * 1.6 = 2.4x base income per fish. With 75 fish at ~10 income/min avg, that's 75 * 10 / 60 * 2.4 = 30 coins/sec passive. This is strong but bounded by MaxUnclaimedIncome (50,000) and requires ~20,800 coins invested (8000 aquarium + 12800 dock). Payback at 30/sec is ~12 minutes — reasonable for an endgame investment.

ACCEPTANCE CRITERIA:
- [ ] Dock multiplier applied after Aquarium multiplier
- [ ] Multipliers stack (1.5 * 1.6 = 2.4, not 1.5 + 1.6 = 3.1)
- [ ] Base dock (level 1, multiplier 1.0) produces no change
- [ ] Income display updates correctly after dock purchase

FILES: src/server/StateSync.lua (incomePerSec, after N13 block)
DEPENDS ON: Nothing (DockUpgradeTiers already exists; profile.Dock.UpgradeLevel already in schema)""",
        "epic-dock",
    ),

    # TASK 17.4: Expose dockLevel in snapshot + client shop
    (
        "task-17.4",
        "TASK 17.4: Expose dockLevel in StateSync.snapshot + add dock catalog to client shop",
        "task",
        1,
        "task-17-4-dock-snapshot-client",
        """WHAT: Wire the dock level through to the client so the shop can display owned/locked/affordable states.

SERVER (StateSync.snapshot):
  dockLevel = profile.Dock.UpgradeLevel or 1,

CLIENT SHOP:
  1. Add to SHOP_CATALOG: addCatalog("dock", GameConfig.DockUpgradeTiers, 50)
  2. Add to KIND_META: dock = { tag = "DOCK", color = UI.boat }
  3. Add to itemSubText: elseif entry.kind == "dock" then return "+" .. math.floor(((it.incomeMultiplier or 1) - 1) * 100 + 0.5) .. "% income" .. (it.cosmeticUnlocks and #it.cosmeticUnlocks > 0 and "  •  " .. table.concat(it.cosmeticUnlocks, ", ") or "")
  4. Add to refreshShop: elseif entry.kind == "dock" then currentLevel = state.dockLevel or 1

ACCEPTANCE CRITERIA:
- [ ] StateSync.snapshot includes dockLevel
- [ ] Client shop shows a DOCK row for each DockUpgradeTiers entry
- [ ] Dock rows show income multiplier % and cosmetic unlocks in subtext
- [ ] refreshShop correctly shows OWNED / buyable / LOCKED states
- [ ] Purchasing a dock upgrade updates the shop and income display

FILES: src/server/StateSync.lua (snapshot), src/client/init.client.lua (shop catalog + KIND_META + refreshShop)
DEPENDS ON: TASK 17.2 (server must accept "dock" kind), TASK 17.3 (income must reflect the multiplier)""",
        "epic-dock",
    ),

    # TASK 17.5: Cosmetic rendering for dock upgrades
    (
        "task-17.5",
        "TASK 17.5: Render dock cosmetic upgrades (lamp posts, planters, golden trim)",
        "task",
        2,
        "task-17-5-dock-cosmetics",
        """WHAT: When a player upgrades their dock, render the cosmetic unlocks on their dock model in the world. The DockUpgradeTiers cosmeticUnlocks field lists which props each tier adds: { "LampPost" }, { "LampPost", "Planters" }, { "LampPost", "Planters", "GoldenTrim" }.

IMPLEMENTATION APPROACH:
  1. In DockManager.buildDock(), create the cosmetic props but hide them (Enabled=false / Transparency=1) by default
  2. Add a DockManager.updateCosmetics(dock, upgradeLevel) function that shows/hides props based on the tier
  3. Call updateCosmetics on dock claim (onPlayerAdded) and on dock upgrade purchase (ShopService)
  4. Store the prop instances on the dock table for fast access

PROPS TO BUILD:
  - LampPost: already exists in WorldBuilder.buildDecorations (6 plaza lamp posts). Reuse the model: pole + glowing ball + PointLight. Place 2 at the dock entrance.
  - Planters: small wooden boxes with a green foliage PartMesh. Place 2-4 along the walkway edges.
  - GoldenTrim: change the walkway part Color from WoodPlanks-brown to a gold tint (Color3.fromRGB(200, 170, 50)) + Material = Metal. Optionally add a subtle ParticleEmitter sparkle.

ACCEPTANCE CRITERIA:
- [ ] Dock at level 1 shows no cosmetics
- [ ] Dock at level 2 shows lamp posts (glowing at night)
- [ ] Dock at level 3 shows lamp posts + planters
- [ ] Dock at level 4 shows lamp posts + planters + golden trim
- [ ] Cosmetics update immediately on upgrade purchase (no rejoin needed)
- [ ] Cosmetics are purely visual (no gameplay effect)

FILES: src/server/DockManager.lua (buildDock + updateCosmetics), src/server/ShopService.lua (call updateCosmetics after dock purchase), src/server/init.server.lua (call on dock claim)
DEPENDS ON: TASK 17.2 (upgrade must apply), TASK 17.4 (client must show the tier)
NOTE: This task can be deferred post-launch if cosmetic rendering is lower priority than gameplay features. The income multiplier (TASK 17.3) is the gameplay-critical part.""",
        "epic-dock",
    ),

    # TASK 17.6: Sanitize Dock.UpgradeLevel clamping
    (
        "task-17.6",
        "TASK 17.6: Clamp Dock.UpgradeLevel in sanitize() against DockUpgradeTiers",
        "task",
        1,
        "task-17-6-dock-sanitize-clamp",
        """WHAT: The sanitize() function currently accepts Dock.UpgradeLevel if it's >= 1, but doesn't clamp it against the DockUpgradeTiers table length. A crafted save with UpgradeLevel = 999 would be loaded and honored, causing DockUpgradeTiers[999] lookups to return nil downstream.

This is checklist item #10 (Persisted Capacity Trusted Without Tier Cross-Check) applied to the Dock track. The same fix pattern used for Aquarium.UpgradeLevel (N6 in DataManager) should be applied here.

IMPLEMENTATION (in the Dock branch of sanitize):
  if type(data.Dock.UpgradeLevel) == "number" and data.Dock.UpgradeLevel >= 1 then
    clean.Dock.UpgradeLevel = math.floor(data.Dock.UpgradeLevel)
  end
  -- Clamp against authoritative tier table (mirrors the Aquarium N6 pattern):
  local DockUpgradeTiers = GameConfig.DockUpgradeTiers
  local dockLevel = clean.Dock.UpgradeLevel or 1
  if DockUpgradeTiers and #DockUpgradeTiers > 0 then
    dockLevel = math.max(1, math.min(dockLevel, #DockUpgradeTiers))
    clean.Dock.UpgradeLevel = dockLevel
  end

ACCEPTANCE CRITERIA:
- [ ] Dock.UpgradeLevel clamped to [1, #DockUpgradeTiers] in sanitize
- [ ] A crafted save with UpgradeLevel=999 is clamped to 4 on load
- [ ] Existing valid saves are unaffected
- [ ] Pattern mirrors the Aquarium.UpgradeLevel clamp (N6)

FILES: src/server/DataManager.lua (Dock branch of sanitize, ~line 190)
DEPENDS ON: Nothing (defensive hardening, can be done independently)""",
        "epic-dock",
    ),
]

# Dependencies (from_key, to_key, dep_type)
# parent-child is auto-created by --parent; only wire blocks here
DEPS = [
    # EPIC 16 internal deps
    ("task-16.2", "task-16.1", "blocks"),       # CastResult handler needs bounds on activeBites
    ("task-16.3", "task-16.2", "blocks"),       # luckBonus application needs the handler
    ("task-16.4", "task-16.1", "blocks"),       # client rendering needs server to send bounds
    ("task-16.5", "task-16.3", "blocks"),       # playtesting needs the full chain wired

    # EPIC 17 internal deps
    ("task-17.2", "task-17.1", "blocks"),       # shop handler needs config names
    ("task-17.3", "task-17.1", "blocks"),       # income multiplier needs config (not strictly, but logically)
    ("task-17.4", "task-17.2", "blocks"),       # client shop needs server handler
    ("task-17.4", "task-17.3", "blocks"),       # client display needs income calculation
    ("task-17.5", "task-17.2", "blocks"),       # cosmetics need upgrade to apply
    ("task-17.5", "task-17.4", "blocks"),       # cosmetics need client tier awareness

    # Cross-epic: dock sanitize clamp is independent (no deps)
    # Cross-epic: CastResult playtesting depends on release balance pass
    # ("task-16.5", "harborheist-release-prep-mxl.2", "blocks"),  # commented out — external bead, may not exist at runtime
]


# ════════════════════════════════════════════════════════════════════════════
# EXECUTION
# ════════════════════════════════════════════════════════════════════════════

def main():
    print("=" * 70)
    print("Creating Round-2 Review + Feature beads")
    print("=" * 70)

    # Check for existing epics to avoid duplication
    existing = {}
    data = json.loads(br(["list", "--all", "--json", "--limit", "200"]))
    for issue in data.get("issues", []):
        existing[issue["title"]] = issue["id"]

    created = {}
    skipped = []

    for key, title, btype, pri, slug, desc, parent_key in BEADS:
        # Check for duplicates by title fragment
        dup_id = None
        for etitle, eid in existing.items():
            if title.split("]")[0].split("(")[0].strip().rstrip(":") in etitle:
                dup_id = eid
                break

        if dup_id:
            print(f"  SKIP (exists): {title[:65]}... → {dup_id}")
            created[key] = dup_id
            skipped.append(key)
            continue

        parent_id = created.get(parent_key) if parent_key else None
        bid = create_bead(title, btype, pri, desc, parent=parent_id, slug=slug)
        created[key] = bid
        print(f"  CREATED: {title[:65]}... → {bid}")

    print()
    print("=" * 70)
    print(f"Wiring {len(DEPS)} dependencies")
    print("=" * 70)

    for from_key, to_key, dep_type in DEPS:
        if from_key in skipped or to_key in skipped:
            print(f"  SKIP (bead existed): {from_key} → {to_key}")
            continue
        from_id = created.get(from_key)
        to_id = created.get(to_key)
        if not from_id or not to_id:
            print(f"  SKIP (missing key): {from_key}({from_id}) → {to_key}({to_id})")
            continue
        try:
            add_dep(from_id, to_id, dep_type)
            print(f"  DEP: {from_key} → {to_key} ({dep_type})")
        except RuntimeError as e:
            if "cycle" in str(e).lower() or "already" in str(e).lower():
                print(f"  SKIP (exists/cycle): {from_key} → {to_key}")
            else:
                print(f"  ERROR: {from_key} → {to_key}: {e}")

    print()
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"  Beads defined: {len(BEADS)}")
    print(f"  Beads created: {len(created) - len(skipped)}")
    print(f"  Beads skipped (existed): {len(skipped)}")
    print(f"  Dependencies wired: {len(DEPS)}")
    print()
    print("Key → ID map:")
    for key, bid in sorted(created.items()):
        print(f"  {key:20} → {bid}")

    return created


if __name__ == "__main__":
    main()
