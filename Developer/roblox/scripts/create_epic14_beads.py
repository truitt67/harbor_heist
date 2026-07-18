#!/usr/bin/env python3
"""
Bulk-create EPIC 14 (Post-Review Hardening) tasks + wire dependencies.

Created by Hermes-K3 on 2026-07-17 as part of the ultrathink code review follow-up.
Self-contained: each task description includes root cause, fix recipe, PRD refs, and
file:line pointers so a future agent can execute cold.

Usage: python3 /home/ubuntu/Developer/roblox/scripts/create_epic14_beads.py
"""

import json
import subprocess
import sys
import time

REPO = "/home/ubuntu/Developer/roblox"
EPIC_ID = "harborheist-wqw"  # EPIC 14: Post-Review Hardening & Bug Fixes

# Map finding key -> owning epic ID (for cross-epic 'blocks' dep wiring)
EPIC_MAP = {
    "E1": "harborheist-data-model-foundation-73i",
    "E2": "harborheist-game-content-definitions-pmr",
    "E3": "harborheist-fishing-system-rework-h2e",
    "E4": "harborheist-fish-inventory-mgmt-0cw",
    "E5": "harborheist-aquarium-income-rework-9mu",
    "E12": "harborheist-cross-cutting-infra-thj",
}


def run(cmd):
    """Run a command, return (stdout, stderr, returncode)."""
    # RELIABILITY: every br subprocess gets a timeout. An unbounded call can
    # hang the whole automation if br blocks (locked SQLite, stdin prompt).
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO, timeout=30)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


def br_create(title, issue_type, priority, parent, description):
    """Create a bead, return its ID."""
    cmd = [
        "br", "create", title,
        "-t", issue_type,
        "-p", str(priority),
        "--parent", parent,
        "-d", description,
        "--json",
    ]
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
    """Set acceptance criteria (must use =VALUE form for leading-dash safety)."""
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


# ─────────────────────────────────────────────────────────────────────────────
# TASK DEFINITIONS
# Each entry: (key, title, priority, owning_epic_key, description, acceptance_criteria)
# ─────────────────────────────────────────────────────────────────────────────

TASKS = [
    # ═══════════════════════════════════════════════════════════════════════
    # CRITICAL (P0) — production-breaking
    # ═══════════════════════════════════════════════════════════════════════
    (
        "C1",
        "TASK 14.1: Wire claimButton to ClaimIncome remote (PRD AQUA-05)",
        0,
        "E5",
        """PRD AQUA-05 mandates "Players claim accumulated aquarium income through a visible interaction or UI button."

## ROOT CAUSE
The aquarium income rework (TASK 5.1) moved income from auto-cash to an UnclaimedIncome pool, and the server-side ClaimIncome RemoteFunction exists (src/server/AquariumService.lua:51-67). The client creates claimButton (src/client/init.client.lua:221-226) and updates its label/color based on state.unclaimedIncome (lines 392-397) — but NO Activated handler is ever connected. The button is dead UI.

## IMPACT
The entire passive-income loop is a black hole. Income accrues server-side but players have ZERO way to claim it. PRD first-session success condition ("claims or observes passive income") is unachievable. This is the single highest-impact bug in the codebase.

## FIX RECIPE
In src/client/init.client.lua, after the lockButton.Activated block (around line 545), add:

    claimButton.Activated:Connect(function()
        Remotes.ClaimIncome:InvokeServer()
    end)

## CONSIDERATIONS
- Server already handles the "nothing to claim" case gracefully (returns {ok=false, reason="nothing_to_claim"}), so no client-side guard needed.
- TASK 5.1's description calls for a pulsing/glowing indicator when UnclaimedIncome > 0 — that's tracked separately under EPIC 5's UX work; this task is JUST the handler wiring.
- No server changes needed — this is purely a client-side missing wire.

## FILES
src/client/init.client.lua (one 3-line handler block)""",
        "- [ ] claimButton.Activated handler exists and calls Remotes.ClaimIncome:InvokeServer()\n- [ ] Clicking CLAIM with unclaimedIncome > 0 increases cash and resets unclaimedIncome to 0\n- [ ] Clicking CLAIM with unclaimedIncome == 0 does not error (server returns nothing_to_claim)\n- [ ] UBS clean on src/client/init.client.lua",
    ),
    (
        "C2",
        "TASK 14.2: Fix legacy v1->v2 liveWell migration overwrite bug",
        0,
        "E1",
        """PRD Data Model section (lines 271-326) requires lossless migration from the v1 flat schema to the v2 structured PlayerProfile.

## ROOT CAUSE
DataManager.sanitize() converts legacy v1 `liveWell` (array of rarity indexes) into FishInstance records via sanitizeStoredFish() at src/server/DataManager.lua:70-72, storing the result to clean.Aquarium.StoredFish. HOWEVER, at line 110, the v2 codepath then runs `clean.Aquarium.StoredFish = sanitizeStoredFish(aq.StoredFish)` UNCONDITIONALLY. For a v1 player, `aq.StoredFish` is nil (the field didn't exist in v1), so sanitizeStoredFish returns an empty table — OVERWRITING the freshly-migrated legacy fish.

## IMPACT
Silent data loss. Any player whose data was saved under the v1 prototype schema loses their entire aquarium on next load. This is the worst kind of bug: invisible, irreversible, and hits your most loyal (earliest) players.

## FIX RECIPE
In src/server/DataManager.lua around line 110, guard the v2 overwrite:

    if type(aq.StoredFish) == "table" then
        clean.Aquarium.StoredFish = sanitizeStoredFish(aq.StoredFish)
    end

The legacy conversion at lines 70-72 already handles the v1 case, so no merge logic is needed — just don't clobber it.

## CONSIDERATIONS
- Order matters: legacy conversion (line 70) MUST run before the v2 branch (line 102) so the guard correctly preserves the migrated value.
- Edge case: a player with BOTH liveWell (legacy) AND Aquarium.StoredFish (partial v2 save) — current logic prefers v2, which is correct (v2 is authoritative).
- No test infrastructure exists for this; verification is by code inspection + a manual test with a hand-crafted v1 save blob.

## FILES
src/server/DataManager.lua (one 3-line guard)""",
        "- [ ] Line 110 is guarded with `if type(aq.StoredFish) == \"table\"`\n- [ ] Loading a v1 save with liveWell={1,3,2} results in 3 FishInstance records in Aquarium.StoredFish\n- [ ] Loading a v2 save with Aquarium.StoredFish populated does NOT lose fish\n- [ ] Loading a v2 save with empty Aquarium.StoredFish and no liveWell results in empty StoredFish (not nil)\n- [ ] UBS clean on src/server/DataManager.lua",
    ),
    (
        "C3",
        "TASK 14.3: Fix activeBites memory leak on player disconnect",
        0,
        "E3",
        """Server stability requirement — long-running servers must not leak per-player state.

## ROOT CAUSE
FishingService stores per-player bite state in a module-level table `activeBites` (src/server/FishingService.lua:22) keyed by Player instance. Entries are created on Cast (line 72) and removed on SubmitCatchInput (line 140) or timeout (line 129). But if a player disconnects mid-cast (between Cast and SubmitCatchInput), NOTHING removes activeBites[player]. Because the Player instance is the table KEY, the entry holds a strong reference and the Player object is never garbage-collected.

## IMPACT
Memory leak proportional to disconnected-mid-cast players. On a busy server with players leaving frequently, this accumulates. Worse, if a player rejoins, a stale activeBites entry from their PREVIOUS session could theoretically confuse the new session's Cast handler (though in practice session.casting guards against this).

## FIX RECIPE
Two options; implement BOTH for defense-in-depth:

1. In FishingService.init, add a Players.PlayerRemoving listener:

    Players.PlayerRemoving:Connect(function(player)
        activeBites[player] = nil
    end)

2. Store bite state on the session object instead of a module-level table (session.activeBite = {...}), which gets cleaned up automatically by DataManager.remove(). This is the cleaner long-term fix but requires touching more code.

RECOMMENDED: Option 1 now (5 lines, zero risk), consider Option 2 as part of the EPIC 12 cross-cutting refactor.

## CONSIDERATIONS
- The redundant check `if not player.Parent or not session.player.Parent` at line 81 is related tech debt (player == session.player) — clean that up while in the file.
- The Cast task.delay closure captures `session` strongly; after disconnect the closure still fires once (harmless, just sets session.casting=false on a dead session table). Not a leak, but worth noting.

## FILES
src/server/FishingService.lua (add PlayerRemoving listener; simplify line 81 check)""",
        "- [ ] Players.PlayerRemoving listener in FishingService.init clears activeBites[player]\n- [ ] Disconnecting mid-cast does not leave an entry in activeBites\n- [ ] Line 81 redundant check simplified to `if not player.Parent then`\n- [ ] Cast + immediate disconnect + rejoin does not error\n- [ ] UBS clean on src/server/FishingService.lua",
    ),
    # ═══════════════════════════════════════════════════════════════════════
    # HIGH (P1) — exploits / mechanic violations
    # ═══════════════════════════════════════════════════════════════════════
    (
        "H4",
        "TASK 14.4: Widen bite window for network latency (H4)",
        1,
        "E3",
        """PRD FISH-04: "success awards fish, failure = retry-ready" — the timing minigame must feel fair.

## ROOT CAUSE
The server enforces the bite window by comparing os.clock() elapsed against BITE_WINDOW_SECONDS (3.0s) at src/server/FishingService.lua:127-132. But biteData.biteTime is set server-side at the moment the server FIRES the BiteEvent remote (line 108). Network latency + client processing means a player on 200ms ping has their effective window shortened by ~0.2s+ before they even see the minigame UI. On high-latency connections (mobile, international), legit players consistently fail through no fault of their own.

## IMPACT
UX fairness issue, not an exploit. Feels like the game is broken on slow connections.

## FIX RECIPE
Two complementary fixes:

1. Widen BITE_WINDOW_SECONDS from 3.0 to 3.5 (absorbs typical latency without making the minigame trivially easy).

2. OPTIONAL (better long-term): Send the server timestamp in BiteEvent and have the client compute a latency-compensated remaining-window. This is more complex and only worth doing if playtesting shows the simple widening isn't enough.

RECOMMENDED: Just widen to 3.5s. Revisit if playtests complain.

## CONSIDERATIONS
- The server-side window enforcement is correct (prevents exploiters from waiting arbitrarily long) — this task is purely a tuning knob, not a security fix.
- Don't widen past 4.0s or the minigame loses tension.

## FILES
src/server/FishingService.lua (change BITE_WINDOW_SECONDS constant at line 13)""",
        "- [ ] BITE_WINDOW_SECONDS >= 3.5\n- [ ] Server still rejects SubmitCatchInput after window expires (no exploit)\n- [ ] UBS clean on src/server/FishingService.lua",
    ),
    (
        "H5",
        "TASK 14.5: Document steal-cooldown rejoin exploit as known V1 limitation",
        1,
        "E5",
        """PvP integrity — cooldowns should not be trivially bypassable.

## ROOT CAUSE
Steal cooldown is stored in two places: session.stealCooldownUntil (os.clock, session-only) and session.profile.PvP.StealCooldownUntilTimestamp (os.time, persisted). The persisted timestamp is written at steal attempt (src/server/AquariumService.lua:194) but only SAVED to DataStore on autosave (60s interval) or player leave. If the server crashes or the player force-quits before the next save, the cooldown is lost and they can steal again immediately on rejoin.

## IMPACT
Minor exploit. Steal cooldown is only 20s, so the impact is bounded — a determined player could rejoin-farm steals but the effort-to-reward ratio is poor. Not worth engineering a fix for V1.

## FIX RECIPE
No code change. Add a comment block at src/server/AquariumService.lua:193 documenting the known limitation:

    -- KNOWN LIMITATION (V1): stealCooldownUntil is only persisted on autosave/leave.
    -- A player who force-quits within the autosave window can reset their cooldown
    -- by rejoining. Bounded by the 20s cooldown duration; acceptable for V1.
    -- Fix in EPIC 8 (Raid system) by using raid-window-level cooldown tracking.

Close this task once the comment is added.

## CONSIDERATIONS
- The proper fix (immediate save on steal attempt) would add DataStore write pressure for minimal gain.
- EPIC 8's raid-window system will replace this cooldown model entirely, making this moot.

## FILES
src/server/AquariumService.lua (comment only)""",
        "- [ ] Comment block added at AquariumService.lua:193 documenting the limitation\n- [ ] Comment references EPIC 8 as the proper-fix location\n- [ ] UBS clean on src/server/AquariumService.lua",
    ),
    (
        "H6",
        "TASK 14.6: Prevent selling fish from a LOCKED aquarium (lock bypass)",
        1,
        "E4",
        """PRD AQUA lock mechanic: locked aquariums block ALL theft and modification.

## ROOT CAUSE
FishInventoryService.SellFish (src/server/FishInventoryService.lua:41-88) searches session.carried first, then falls through to session.profile.Aquarium.StoredFish (lines 56-61) WITHOUT checking session.lockedUntil. A player can lock their aquarium (preventing steals), then immediately liquidate their best fish from inside the "locked" aquarium via the SellFish remote.

## IMPACT
Lock mechanic is theater. Informed players can always sell-before-raid, completely defeating the risk/reward tension the PRD's PvP system is built around ("decide when your collection is worth protecting—or risking").

## FIX RECIPE
In src/server/FishInventoryService.lua, in the stored-fish branch (after finding fish in StoredFish, before removing), add:

    if session.lockedUntil > os.clock() then
        -- Re-insert at same index to avoid order shift, then bail
        table.insert(storedFish, idx, fish)
        return { ok = false, reason = "aquarium_locked" }
    end

Note: must re-insert because the fish was already removed by table.remove before this check would run. Restructure to check BEFORE removing if cleaner.

## CONSIDERATIONS
- Carried fish should NOT be subject to this check (they're not in the aquarium).
- PRD AQUA-09 ("remove a stored fish and sell it, subject to raid-state restrictions") explicitly calls for raid-state gating — this fix aligns the code with the PRD.
- Consider also gating StoreSingleFish during lock (currently allowed — storing INTO a locked aquarium is arguably fine, but removing/selling is not).

## FILES
src/server/FishInventoryService.lua (add lock check in SellFish stored-fish branch)""",
        "- [ ] SellFish on a stored fish while lockedUntil > os.clock() returns {ok=false, reason=\"aquarium_locked\"}\n- [ ] Fish is NOT removed from StoredFish when the lock check fails\n- [ ] SellFish on a carried fish while locked still works (carried is not aquarium)\n- [ ] SellAll in AquariumService also respects the lock (audit line 69-99)\n- [ ] UBS clean on src/server/FishInventoryService.lua",
    ),
    (
        "H7",
        "TASK 14.7: Derive aquarium capacity from UpgradeLevel, not persisted field",
        1,
        "E1",
        """Data integrity — capacity should be a function of upgrade tier, not a free-floating persisted value.

## ROOT CAUSE
StateSync.getCapacity (src/server/StateSync.lua:7-9) returns session.profile.Aquarium.Capacity directly. This field is settable via the profile sanitization path (src/server/DataManager.lua:104-106 accepts any number >= 1) and defaults to 20. There's no enforcement that Capacity matches the player's Aquarium.UpgradeLevel via GameConfig.AquariumUpgradeTiers. A tampered or corrupted profile could have Capacity=999 while UpgradeLevel=1.

## IMPACT
Profile tampering could inflate aquarium capacity, bypassing the upgrade progression. Low likelihood (requires DataStore write access, which exploiters don't have on Roblox) but violates the server-authoritative principle.

## FIX RECIPE
In src/server/StateSync.lua, change getCapacity to derive from the tier table:

    function StateSync.getCapacity(session)
        local level = session.profile.Aquarium.UpgradeLevel or 1
        local tier = GameConfig.AquariumUpgradeTiers[level]
        return tier and tier.capacity or GameConfig.Aquarium.baseCapacity
    end

Then REMOVE the Capacity field from PlayerProfile.default() and the sanitize path (or keep it as a cache that's validated on load against the tier table).

## CONSIDERATIONS
- GameConfig.AquariumUpgradeTiers is currently DEAD CONFIG (see TASK 14.9) — this task activates it. Dependency: should land after or alongside 14.9.
- The incomeMultiplier field on tiers is NOT yet consumed by the income loop — that's separate future work under EPIC 5.
- Removing Capacity from the profile is a schema change; if PlayerProfile.CURRENT_VERSION bumps, migration must handle old saves that HAVE the field (just ignore it on load).

## FILES
src/server/StateSync.lua (rewrite getCapacity), src/shared/PlayerProfile.lua (remove or deprecate Capacity field), src/server/DataManager.lua (remove Capacity from sanitize)""",
        "- [ ] getCapacity returns capacity from AquariumUpgradeTiers[UpgradeLevel]\n- [ ] Profile with Capacity=999 but UpgradeLevel=1 reports capacity=20\n- [ ] Upgrading to tier 2 increases capacity to 35\n- [ ] UBS clean on src/server/StateSync.lua",
    ),
    # ═══════════════════════════════════════════════════════════════════════
    # MEDIUM (P2) — code quality / consistency
    # ═══════════════════════════════════════════════════════════════════════
    (
        "M8",
        "TASK 14.8: Remove dead code — sanitizeNested helper",
        2,
        "E1",
        """Code hygiene — dead code confuses future agents and inflates review surface.

## ROOT CAUSE
DataManager.lua:25-29 defines `local function sanitizeNested(data, clean, key, validator)` which is NEVER CALLED anywhere in the codebase. It's leftover from an earlier refactor before the sanitize function was restructured.

## FIX RECIPE
Delete lines 25-29 in src/server/DataManager.lua. Requires explicit user approval per AGENTS.md no-deletions rule.

## CONSIDERATIONS
- Search confirms zero call sites: `rg sanitizeNested src/` returns only the definition.
- Safe to delete — pure dead code, no side effects.

## FILES
src/server/DataManager.lua (delete 5 lines)""",
        "- [ ] sanitizeNested function removed\n- [ ] No references remain (rg confirms)\n- [ ] UBS clean on src/server/DataManager.lua",
    ),
    (
        "M9",
        "TASK 14.9: Activate or remove dead upgrade-tier config tables",
        2,
        "E2",
        """PRD upgrade progression — config should drive behavior, not sit unused.

## ROOT CAUSE
GameConfig.lua defines four upgrade-tier tables that are NEVER READ by any code:
- GameConfig.RodDefinitions (lines 40-44) — duplicate of GameConfig.Rods with added minigameZoneSize field
- GameConfig.BaitDefinitions (lines 49-53) — duplicate of GameConfig.Baits
- GameConfig.AquariumUpgradeTiers (lines 58-63) — capacity + income multiplier tiers
- GameConfig.DockUpgradeTiers (lines 68-73) — dock income multiplier + cosmetic tiers

Meanwhile the live code reads GameConfig.Rods, GameConfig.Baits, and session.profile.Aquarium.Capacity directly.

## IMPACT
Confusing for future agents — looks like upgrade systems exist but they're stubs. Two sources of truth for rods/baits means editing one and not the other causes silent divergence.

## FIX RECIPE
Two-part decision:

1. For Rods/Baits: CONSOLIDATE. Make RodDefinitions the canonical table (it has the id field and minigameZoneSize), then alias: `GameConfig.Rods = GameConfig.RodDefinitions`. Same for Baits. Delete the duplicates. (Handled in TASK 14.10.)

2. For AquariumUpgradeTiers/DockUpgradeTiers: ACTIVATE. These encode PRD-required progression (AQUA-07 capacity upgrades, dock income multipliers). Wire AquariumUpgradeTiers into StateSync.getCapacity (TASK 14.7). DockUpgradeTiers activation is larger scope — defer to EPIC 6 (Economy & Upgrade System).

## CONSIDERATIONS
- This task is the DECISION + the AquariumUpgradeTiers activation. Rod/Bait consolidation is 14.10. DockUpgradeTiers is out of scope.
- minigameZoneSize activation is TASK 14.11.

## FILES
src/shared/GameConfig.lua (remove duplicate tables), src/server/StateSync.lua (read AquariumUpgradeTiers)""",
        "- [ ] Decision documented on each table's fate\n- [ ] AquariumUpgradeTiers consumed by StateSync.getCapacity\n- [ ] Duplicate Rods/Baits tables removed or aliased\n- [ ] UBS clean on src/shared/GameConfig.lua",
    ),
    (
        "M10",
        "TASK 14.10: Consolidate Rods/RodDefinitions and Baits/BaitDefinitions",
        2,
        "E2",
        """Single source of truth — eliminate duplicate config tables.

## ROOT CAUSE
GameConfig.Rods (lines 11-15) and GameConfig.RodDefinitions (lines 40-44) contain identical data (same names, costs, luck, castTime). RodDefinitions adds an `id` field and `minigameZoneSize`. Live code reads GameConfig.Rods; RodDefinitions is read nowhere. Same pattern for Baits/BaitDefinitions.

## IMPACT
Two sources of truth. If someone edits one and not the other, the shop and fishing math silently disagree.

## FIX RECIPE
1. Keep RodDefinitions as canonical (has `id` and `minigameZoneSize`).
2. Replace the old Rods table with an alias: `GameConfig.Rods = GameConfig.RodDefinitions`.
3. Same for Baits: `GameConfig.Baits = GameConfig.BaitDefinitions`.
4. Verify all existing `GameConfig.Rods[level]` accesses still work (they will — array-style access is identical).

## CONSIDERATIONS
- The numeric `id` field on RodDefinitions is 1-indexed matching array position, so `Rods[1] == RodDefinitions[1]` — no index remap needed.
- TASK 14.11 will consume minigameZoneSize from the now-canonical table.

## FILES
src/shared/GameConfig.lua (consolidate tables)""",
        "- [ ] Only one Rods table exists (RodDefinitions), aliased as Rods\n- [ ] Only one Baits table exists (BaitDefinitions), aliased as Baits\n- [ ] Shop and fishing services still function (manual inspection of ShopService.lua and FishingService.lua)\n- [ ] UBS clean on src/shared/GameConfig.lua",
    ),
    (
        "M11",
        "TASK 14.11: Wire rod minigameZoneSize into client timing minigame",
        2,
        "E3",
        """PRD FISH progression — better rods should make the timing minigame easier.

## ROOT CAUSE
RodDefinitions (after TASK 14.10 consolidation) specifies minigameZoneSize: 0.30 for Basic, 0.35 for Steel, 0.40 for Golden. But the client hardcodes the target zone at src/client/init.client.lua:426: `targetZone.Size = UDim2.new(0.3, 0, 1, 0)` — always 30%, regardless of rod.

## IMPACT
Better rods don't actually make the minigame easier, breaking a core progression promise. Players who buy the Golden Rod get faster casts (which works) but NOT the wider target zone (which doesn't).

## FIX RECIPE
In src/client/init.client.lua, in the runMinigame function (around line 455), read the current rod's minigameZoneSize and set the target zone accordingly:

    local zoneSize = 0.30 -- fallback
    if state and GameConfig.Rods[state.rodLevel] then
        zoneSize = GameConfig.Rods[state.rodLevel].minigameZoneSize or 0.30
    end
    local offset = (1 - zoneSize) / 2
    targetZone.Size = UDim2.new(zoneSize, 0, 1, 0)
    targetZone.Position = UDim2.new(offset, 0, 0, 0)

Also update the hit-detection at line 496 to use the dynamic zone bounds instead of hardcoded 0.35/0.65:

    local hit = markerPos >= offset and markerPos <= (offset + zoneSize)

## CONSIDERATIONS
- Depends on TASK 14.10 (consolidation) so minigameZoneSize is on the canonical Rods table.
- Server-side validation doesn't check the zone size (it only checks timing window) so no server change needed.
- targetZone is currently centered at 0.35 with width 0.30 (so 0.35..0.65); the fix generalizes this to any width centered at 0.5.

## FILES
src/client/init.client.lua (runMinigame function + onMinigameTap hit detection)""",
        "- [ ] Target zone width matches current rod's minigameZoneSize\n- [ ] Hit detection uses dynamic bounds, not hardcoded 0.35/0.65\n- [ ] Basic rod = 30% zone, Steel = 35%, Golden = 40%\n- [ ] Zone stays centered at 0.5 regardless of width\n- [ ] UBS clean on src/client/init.client.lua",
    ),
    (
        "M12",
        "TASK 14.12: Randomize species in FishInstance.fromRarityIndex migration",
        2,
        "E4",
        """Migration UX — v1 players should keep aquarium variety.

## ROOT CAUSE
FishInstance.fromRarityIndex (src/shared/FishInstance.lua:84-96) converts legacy rarity-index fish to FishInstance records, but always picks `pool[1]` — the FIRST species in each rarity bucket. All migrated Commons become Bluegill, all Uncommons become Mackerel, etc.

## IMPACT
Cosmetic but sad — a v1 player's diverse aquarium becomes 20 identical Bluegills after migration.

## FIX RECIPE
In src/shared/FishInstance.lua:94, change `local def = pool[1]` to `local def = pool[math.random(1, #pool)]`.

## CONSIDERATIONS
- Uses math.random (not Random.new()) because this is a one-shot migration helper, not a hot loop. Acceptable.
- Depends on the C2 migration fix (TASK 14.2) being in place so migration actually runs.

## FILES
src/shared/FishInstance.lua (one-line change)""",
        "- [ ] fromRarityIndex picks a random species from the rarity pool\n- [ ] Migrating 5 Common fish yields (probabilistically) more than one distinct species\n- [ ] UBS clean on src/shared/FishInstance.lua",
    ),
    (
        "M13",
        "TASK 14.13: Simplify redundant player.Parent check in Cast delay closure",
        2,
        "E3",
        """Code clarity — redundant checks confuse readers.

## ROOT CAUSE
FishingService.lua:81 has `if not player.Parent or not session.player.Parent then`. Since player == session.player (session.player is set to the player at DataManager.load), this is redundant.

## FIX RECIPE
Change to `if not player.Parent then`. One-line simplification.

## CONSIDERATIONS
- Bundle with TASK 14.3 (activeBites leak fix) since both touch the same closure — but tracked separately for clean commit history.

## FILES
src/server/FishingService.lua (line 81)""",
        "- [ ] Line 81 simplified to single player.Parent check\n- [ ] UBS clean on src/server/FishingService.lua",
    ),
    (
        "M14",
        "TASK 14.14: Dynamic aquarium prompt text based on ownership",
        2,
        "E12",
        """UX polish — prompt text should reflect the viewer's relationship to the dock.

## ROOT CAUSE
DockManager sets ProximityPrompt.ActionText = "Open / Steal" statically at build time (src/server/DockManager.lua:96). All players see the same text regardless of whether they own the dock. A visitor sees "Open / Steal" on their OWN aquarium, which is confusing.

## FIX RECIPE
ProximityPrompt properties replicate from server to all clients, so per-player text requires either (a) client-side text override based on ownership, or (b) accepting the generic text. Simplest V1 fix: change static text to "Aquarium" (neutral) and let the OpenAquarium vs steal server-side routing (init.server.lua:48-61) handle the semantics. Better fix (defer to EPIC 12): set prompt text client-side via a LocalScript that checks ownership from state.

RECOMMENDED for V1: change ActionText to "Interact" and ObjectText stays "Aquarium".

## CONSIDERATIONS
- Low priority — pure UX papercut, no functional impact.
- The server-side routing (owner -> OpenAquarium, non-owner -> handleSteal) is correct; only the label is wrong.

## FILES
src/server/DockManager.lua (line 96)""",
        "- [ ] Prompt text is neutral (\"Interact\" or similar)\n- [ ] UBS clean on src/server/DockManager.lua",
    ),
    (
        "M15",
        "TASK 14.15: Cache incomePerSec on session to avoid per-second O(fish) loop",
        2,
        "E5",
        """Performance — avoid recomputing a stable value every second for every player.

## ROOT CAUSE
StateSync.incomePerSec (src/server/StateSync.lua:11-17) iterates the entire StoredFish array on every call. It's called (a) every second in the income loop (AquariumService.startIncomeLoop, line 270), and (b) on every StateSync.push via snapshot() (line 38). With 8 players x 75 fish (max tier), that's 600 fish-iterations per second for the income loop alone, plus more on every state change.

## IMPACT
Trivial at current scale. Will matter if fish capacity grows or player count increases.

## FIX RECIPE
Cache incomePerSec on the session object and invalidate on store/sell/steal events:

1. Add `session.cachedIncomePerSec = nil` in DataManager.load.
2. Add a helper `StateSync.invalidateIncomeCache(session)` that sets it to nil.
3. In StateSync.incomePerSec, compute-and-cache if nil, else return cached.
4. Call invalidateIncomeCache in StoreFish, SellAll, SellFish, StoreSingleFish, and handleSteal (anywhere StoredFish changes).

## CONSIDERATIONS
- Low priority — current perf is fine. This is future-proofing.
- Must catch ALL mutation sites or the cache goes stale (the bug risk is why this is P2, not P0).
- Alternative: compute incomePerSec lazily only in the snapshot (not in the income loop) since the income loop only needs the SUM, not the per-second rate. Actually the income loop uses it directly — so cache is the right call.

## FILES
src/server/StateSync.lua (cache logic), src/server/DataManager.lua (init cache field), src/server/AquariumService.lua (invalidate on store/sell/steal), src/server/FishInventoryService.lua (invalidate on per-fish ops)""",
        "- [ ] incomePerSec is cached on session\n- [ ] Cache invalidated on all StoredFish mutations (store, sell, steal)\n- [ ] Income loop uses cached value\n- [ ] Manual verification: store a fish, income label updates within 1s\n- [ ] UBS clean on all touched files",
    ),
]


def main():
    print(f"Creating {len(TASKS)} tasks under EPIC {EPIC_ID}...\n")
    key_to_id = {}

    # Phase 1: create all tasks
    for key, title, priority, _epic_key, description, ac in TASKS:
        bead_id = br_create(title, "task", priority, EPIC_ID, description)
        if not bead_id:
            print(f"ABORT: failed to create {key}", file=sys.stderr)
            sys.exit(1)
        key_to_id[key] = bead_id
        print(f"  {key} -> {bead_id}  {title}")

        if not br_update_ac(bead_id, ac):
            print(f"  WARN: AC set failed on {bead_id}", file=sys.stderr)

    # Phase 2: wire cross-epic 'blocks' deps so the owning epic's plan reflects reality.
    # Direction: this-task BLOCKS a task in the owning epic would mean the epic task
    # can't start until we finish — that's backwards. We want the OPPOSITE: these
    # hardening tasks are PRECONDITIONS for the owning epic's follow-on work, so
    # we don't wire deps INTO other epics (those epics are already planned). Instead
    # we wire INTER-TASK deps within EPIC 14 to sequence the work correctly.
    print("\nWiring inter-task dependencies...")

    # Internal sequencing deps (blocks = must finish first):
    # - 14.10 (consolidate Rods) blocks 14.11 (wire minigameZoneSize) — 14.11 reads the canonical table
    # - 14.2 (fix migration) blocks 14.12 (randomize migration species) — 14.12 only matters if migration runs
    # - 14.9 (activate upgrade tiers) blocks 14.7 (capacity from tier) — 14.7 consumes the tier table
    deps = [
        ("M10", "M11", "14.10 blocks 14.11: consolidation makes minigameZoneSize canonical"),
        ("C2", "M12", "14.2 blocks 14.12: migration must work before we care about species variety"),
        ("M9", "H7", "14.9 blocks 14.7: tier table must be activated before capacity derivation"),
    ]
    for src_key, dst_key, note in deps:
        src_id = key_to_id[src_key]
        dst_id = key_to_id[dst_key]
        if br_dep_add(dst_id, src_id):  # dst is blocked BY src
            print(f"  {dst_id} blocked-by {src_id}   ({note})")

    # Phase 3: verify
    print("\nVerifying graph health...")
    out, _, _ = run(["br", "dep", "cycles"])
    if "no cycles" in out.lower() or out == "" or "0" in out:
        print("  Cycles: none (good)")
    else:
        print(f"  Cycles output: {out}")

    print("\nDone. Key -> ID map:")
    for k, v in key_to_id.items():
        print(f"  {k}: {v}")

    # Persist the map for future reference
    map_path = f"{REPO}/scripts/epic14_bead_id_map.json"
    with open(map_path, "w") as f:
        json.dump({"epic_id": EPIC_ID, "tasks": key_to_id}, f, indent=2)
    print(f"\nID map written to {map_path}")


if __name__ == "__main__":
    main()
