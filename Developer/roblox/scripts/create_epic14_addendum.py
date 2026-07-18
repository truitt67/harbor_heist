#!/usr/bin/env python3
"""
Addendum to create_epic14_beads.py — adds 8 NEW findings from the background
subagent's independent architecture review (2026-07-17) that the parent
ultrathink review missed.

These are tasks 14.16 through 14.23 under the same EPIC harborheist-wqw.
Self-contained descriptions with root cause, fix recipe, and acceptance criteria.

Usage: python3 /home/ubuntu/Developer/roblox/scripts/create_epic14_addendum.py
"""

import json
import subprocess
import sys

REPO = "/home/ubuntu/Developer/roblox"
EPIC_ID = "harborheist-wqw"


def run(cmd):
    # RELIABILITY: every br subprocess gets a timeout. An unbounded call can
    # hang the whole automation if br blocks (locked SQLite, stdin prompt).
    # Matches the timeout=30 used in create_prd_beads.py / refine_prd_beads.py.
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO, timeout=30)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


def br_create(title, priority, description):
    cmd = ["br", "create", title, "-t", "task", "-p", str(priority),
           "--parent", EPIC_ID, "-d", description, "--json"]
    out, err, rc = run(cmd)
    if rc != 0:
        print(f"FAIL create '{title}': {err}", file=sys.stderr)
        return None
    try:
        return json.loads(out)["id"]
    except (json.JSONDecodeError, KeyError):
        print(f"FAIL parse for '{title}': {out}", file=sys.stderr)
        return None


def br_update_ac(bead_id, ac_text):
    cmd = ["br", "update", bead_id, f"--acceptance-criteria={ac_text}"]
    _, err, rc = run(cmd)
    if rc != 0:
        print(f"FAIL AC on {bead_id}: {err}", file=sys.stderr)
        return False
    return True


TASKS = [
    (
        "TASK 14.16: Server-side validation of catch minigame hit (CRITICAL authority gap)",
        0,
        """EXPLOIT — the single largest server-authority hole in the codebase.

## ROOT CAUSE
The catch minigame's hit determination is CLIENT-SIDE: the client computes `hit = markerPos >= 0.35 and markerPos <= 0.65` (src/client/init.client.lua:496) and sends `{hit = <boolean>}` to the server. The server at src/server/FishingService.lua:135-145 only validates `type(timingResult.hit) == "boolean"` — it NEVER re-derives whether the hit was legitimate. An exploiter can fire:

    SubmitCatchInput:InvokeServer({hit = true})

...during any active bite window and ALWAYS catch the fish, regardless of where the marker actually was. The server clears activeBites[player] on first submit (line 140) so repeat submissions fail, but a single forged hit=true always succeeds.

## IMPACT
The entire skill-based timing minigame is a formality. Exploiters bypass it completely and catch every fish. This undermines the core gameplay loop and any economy balance built on catch rates.

## FIX RECIPE
The server cannot see the client's marker position (client-only state), so true server-side hit validation requires re-architecting the minigame protocol. Two options, in order of preference:

OPTION A (server-driven marker, RECOMMENDED): Server picks a random target window [t0, t1] within [0,1] at bite time, sends it to the client in BiteEvent. Client renders marker + target, reports only the marker position at tap time. Server checks `t0 <= markerPos <= t1`. This moves hit validation server-side without trusting the client's boolean.

OPTION B (plausibility check, quicker): Server validates that the reported markerPos is within the CURRENT rod's minigameZoneSize bounds (from GameConfig.Rods[rodLevel].minigameZoneSize, after TASK 14.10/14.11 wire it up). This catches the trivial always-hit-true exploit but not a smart exploiter who sends markerPos in the zone.

RECOMMENDED: Option A. It's a protocol change but eliminates the exploit class entirely.

## CONSIDERATIONS
- Depends on TASK 14.10 (rod consolidation) and 14.11 (minigameZoneSize wiring) for the zone-size data.
- The target zone is currently CENTERED at 0.5 with width 0.30. If we keep it centered, Option B is weaker (exploiter knows the zone). Option A with a RANDOM center is much stronger.
- Client must render the target zone at the server-specified position, not hardcoded center.

## FILES
src/server/FishingService.lua (BiteEvent payload + SubmitCatchInput validation), src/client/init.client.lua (render server-specified zone, report markerPos not hit boolean)""",
        "- [ ] Server picks target zone bounds at bite time and sends in BiteEvent\n- [ ] Client renders zone from server data (not hardcoded)\n- [ ] Client sends markerPos, not hit boolean\n- [ ] Server validates markerPos is within the zone it chose\n- [ ] Exploiter sending hit=true with markerPos outside zone is rejected\n- [ ] UBS clean on FishingService.lua and init.client.lua",
    ),
    (
        "TASK 14.17: Preserve PvP.StealCooldownUntilTimestamp in sanitize()",
        0,
        """BUG — steal cooldown is wiped on every save.

## ROOT CAUSE
DataManager.sanitize() at src/server/DataManager.lua:170-190 processes the PvP sub-table. It preserves RaidAttemptsToday (line 171), LastRaidTimestamp (line 174), RecentTargetUserIds (line 177), RaidsWon (line 184), and RaidsLost (line 187) — but NOT StealCooldownUntilTimestamp. The save path (line 306-323) calls sanitize(oldData) inside UpdateAsync, then writes existing.PvP = profile.PvP. Because sanitize drops StealCooldownUntilTimestamp, the field is reset to 0 (from PlayerProfile.default()) on every save.

## IMPACT
Steal cooldown does not survive even a clean autosave (which runs every 60s). A player can steal, wait 60s for autosave, rejoin, and steal again immediately — the 20s cooldown is effectively unenforceable across sessions.

## FIX RECIPE
In src/server/DataManager.lua, in the PvP sanitize block (after line 189), add:

    if type(data.PvP.StealCooldownUntilTimestamp) == "number" then
        clean.PvP.StealCooldownUntilTimestamp = data.PvP.StealCooldownUntilTimestamp
    end

## CONSIDERATIONS
- This supersedes TASK 14.5 (which documented the rejoin exploit as a "known limitation"). With this fix, the cooldown actually persists, so 14.5's caveat shrinks to "only lost if server crashes within 60s of the steal attempt" — genuinely acceptable for V1.
- The load path (DataManager.lua:266-268) already reads this field correctly — it's only the sanitize that drops it.

## FILES
src/server/DataManager.lua (one 3-line addition in PvP sanitize block)""",
        "- [ ] StealCooldownUntilTimestamp preserved in sanitize PvP block\n- [ ] Steal, save, rejoin within 20s -> cooldown still active\n- [ ] Steal, save, rejoin after 20s -> cooldown expired (correct)\n- [ ] UBS clean on src/server/DataManager.lua",
    ),
    (
        "TASK 14.18: Build per-fish inventory UI (SellFish/StoreSingleFish client)",
        1,
        """PRD INV-02/INV-03 — per-fish management UI is a V1 requirement.

## ROOT CAUSE
The FishInventoryService (added in commit 948de25) implements SellFish and StoreSingleFish remotes (src/server/FishInventoryService.lua:41,93) and they're registered in Remotes.lua:6. But the client (src/client/init.client.lua) has NO UI for them — it only calls the bulk SellAll and StoreFish. The per-fish API is dead from the player's perspective.

## IMPACT
PRD INV-02 ("displays species, rarity, sell value, store eligibility") and INV-03 ("sell individual fish") are unimplemented from the player's perspective. Players cannot choose WHICH fish to sell/store — only all-or-nothing. This removes the core "store vs sell" decision the PRD's core loop is built around.

## FIX RECIPE
Add an inventory panel to src/client/init.client.lua:

1. New panel (similar to aquariumPanel) listing session.carried fish.
2. Each row: species name, rarity color, sell value, [SELL] and [STORE] buttons.
3. SELL button calls Remotes.SellFish:InvokeServer(instanceId).
4. STORE button calls Remotes.StoreSingleFish:InvokeServer(instanceId).
5. Panel opens via a new "INVENTORY" button on the action bar, or replaces the current STORE button's behavior (single click = open panel, showing per-fish options).
6. Re-render on StateChanged (carried count changes).

The snapshot (StateSync.snapshot, src/server/StateSync.lua:19) currently only sends `carried = #session.carried` (a COUNT). To render per-fish rows, the snapshot must include the actual fish array. Add `carriedFish = session.carried` to the snapshot.

## CONSIDERATIONS
- Snapshot size grows: 5 fish x ~100 bytes = 500 bytes extra per push. Negligible.
- Mobile-friendly touch targets (PRD UX requirement) — buttons must be >= 44px.
- Depends on nothing in EPIC 14; can be built in parallel with the P0 criticals.

## FILES
src/client/init.client.lua (new inventory panel + button wiring), src/server/StateSync.lua (add carriedFish to snapshot)""",
        "- [ ] Snapshot includes carriedFish array with full FishInstance records\n- [ ] Client renders a row per carried fish with species/rarity/value\n- [ ] SELL button per fish calls SellFish and removes that fish\n- [ ] STORE button per fish calls StoreSingleFish and moves it to aquarium\n- [ ] Panel updates on StateChanged\n- [ ] UBS clean on both files",
    ),
    (
        "TASK 14.19: Wire luck stat into species roll (currently dead)",
        1,
        """Progression integrity — rods/bait should actually improve catch rarity.

## ROOT CAUSE
src/server/FishingService.lua:157 computes `local luck = rod.luck + bait.luck` and then NEVER USES IT. The species roll at line 158 calls `FishDefinitions.getRandomInZone(zoneId, rng)` which uses ONLY CatchWeight — no luck modifier. Meanwhile GameConfig.rollRarity(luck, rng) (src/shared/GameConfig.lua:90) exists and implements luck-weighted rarity rolling, but it's never called either. The result: buying a Steel Rod (+8 luck) or Magic Bait (+15 luck) changes NOTHING about what fish you catch. Only cast time (rod.castTime) has any effect.

## IMPACT
Core progression is a lie. Players spend 500-2500 coins on gear that does nothing for catch quality. The PRD's "upgrade -> catch better fish" loop is broken.

## FIX RECIPE
Modify FishDefinitions.getRandomInZone to accept an optional luck parameter and weight rarer species higher:

    function FishDefinitions.getRandomInZone(zoneId, rng, luck)
        luck = luck or 0
        local pool = FishDefinitions.ByZone[zoneId]
        if not pool or #pool == 0 then return nil end
        local total = 0
        local weights = {}
        for i, def in ipairs(pool) do
            -- Boost weight by luck, scaled by rarity tier (rarer = more boost)
            local rarityBoost = 1
            for ri, r in ipairs(GameConfig.Rarities) do
                if r.name == def.Rarity then
                    rarityBoost = 1 + (luck / 100) * (ri - 1)
                    break
                end
            end
            local w = def.CatchWeight * rarityBoost
            weights[i] = w
            total += w
        end
        local roll = (rng and rng:NextNumber() or math.random()) * total
        local acc = 0
        for i, def in ipairs(pool) do
            acc += weights[i]
            if roll <= acc then return def end
        end
        return pool[1]
    end

Then in FishingService.lua:158, pass the luck: `FishDefinitions.getRandomInZone(zoneId, rng, luck)`.

## CONSIDERATIONS
- The luck formula mirrors GameConfig.rollRarity's approach (weight *= (1 + luck/100 * (rarityIndex - 1))) for consistency.
- With max gear (Golden Rod +20, Magic Bait +15 = 35 luck), a Legendary's weight is boosted by 1 + 0.35 * 4 = 2.4x — noticeable but not game-breaking.
- FishDefinitions needs access to GameConfig for the rarity ordering; it currently doesn't require it. Add the require.
- This obsoletes GameConfig.rollRarity (which operates on the old 5-tier system, not species). Mark rollRarity as deprecated or remove it (with approval).

## FILES
src/shared/FishDefinitions.lua (getRandomInZone signature + weighting), src/server/FishingService.lua (pass luck), src/shared/GameConfig.lua (deprecate rollRarity)""",
        "- [ ] getRandomInZone accepts and applies luck\n- [ ] FishingService passes rod.luck + bait.luck\n- [ ] Higher luck measurably increases rare/epic/legendary catch rate\n- [ ] UBS clean on FishDefinitions.lua and FishingService.lua",
    ),
    (
        "TASK 14.20: Make onPlayerRemoving save non-blocking",
        1,
        """Reliability — prevent data loss on fast player exits.

## ROOT CAUSE
src/server/init.server.lua:104-114 (onPlayerRemoving) calls DataManager.save(player) SYNCHRONOUSLY. DataManager.save does UpdateAsync inside withRetries with up to 4 attempts and exponential backoff (~0.25 + 0.5 + 1.0 + 2.0 = ~3.75s worst case, plus the actual DataStore call time). Roblox's PlayerRemoving handler has a limited execution budget; on fast exits or server shutdown, this can be killed mid-save, silently losing the player's recent progress.

## IMPACT
Data loss on crash-y exits or when the leave handler budget is exceeded.

## FIX RECIPE
Two complementary fixes:

1. In DataManager.save, reduce max retries from 4 to 2 when called from a shutdown context (add an optional `isShutdown` param). On shutdown, a fast-failing save is better than a slow save that gets killed.

2. In init.server.lua onPlayerRemoving, wrap the save in task.spawn so the handler returns immediately:

    task.spawn(function()
        DataManager.save(player)
        DockManager.release(player)
        DataManager.remove(player)
    end)

   NOTE: Roblox's BindToClose gives ~30s, but PlayerRemoving does NOT block shutdown. Spawning means the save might not complete before the player object is fully destroyed — but DataManager.save only reads session data (already captured), so it's safe as long as sessions[player] isn't cleared first.

## CONSIDERATIONS
- Order matters: release dock and remove session AFTER save completes.
- If the server is shutting down (BindToClose), the save in bindToClose's loop is the authoritative one; onPlayerRemoving's save is best-effort.

## FILES
src/server/init.server.lua (spawn save), src/server/DataManager.lua (optional retry-count param)""",
        "- [ ] onPlayerRemoving does not block on save\n- [ ] Save still completes in normal (non-shutdown) exits\n- [ ] BindToClose path unchanged\n- [ ] UBS clean on init.server.lua and DataManager.lua",
    ),
    (
        "TASK 14.21: Wire PvP.RaidsWon/RaidsLost stats in handleSteal",
        2,
        """Stats completeness — schema fields exist but are never written.

## ROOT CAUSE
PlayerProfile.PvP defines RaidsWon and RaidsLost (src/shared/PlayerProfile.lua:72-73) and sanitize preserves them (DataManager.lua:184-189). But AquariumService.handleSteal (src/server/AquariumService.lua:143-260) never increments them — win or lose, the stats stay at 0 forever.

## FIX RECIPE
In handleSteal:
- On successful steal (line 226-250): increment attackerSession.profile.PvP.RaidsWon and victimSession.profile.PvP.RaidsLost.
- On failed steal (line 251-259): increment victimSession.profile.PvP.RaidsWon (successful defense) and attackerSession.profile.PvP.RaidsLost.

## CONSIDERATIONS
- Naming is "Raids" but the current mechanic is single-fish steals. When EPIC 8 (raid system) lands, these counters should reflect full raids. For now, count steals as micro-raids.
- Also increment RaidAttemptsToday and set LastRaidTimestamp while in there (they're also never written).

## FILES
src/server/AquariumService.lua (handleSteal win/loss paths)""",
        "- [ ] Successful steal increments attacker RaidsWon and victim RaidsLost\n- [ ] Failed steal increments victim RaidsWon and attacker RaidsLost\n- [ ] RaidAttemptsToday incremented on every attempt\n- [ ] LastRaidTimestamp set on every attempt\n- [ ] UBS clean on AquariumService.lua",
    ),
    (
        "TASK 14.22: Wire Onboarding flags into gameplay events",
        2,
        """PRD first-five-minutes — onboarding flags should track tutorial milestones.

## ROOT CAUSE
PlayerProfile.Onboarding defines 5 flags (HasCompletedIntro, HasCaughtFirstFish, HasStoredFirstFish, HasClaimedIncome, HasSeenRaidExplanation) all defaulting to false (src/shared/PlayerProfile.lua:79-84). No code ever sets them to true. The PRD's contextual onboarding flow (lines 65-80) requires these flags to drive progressive disclosure of mechanics.

## FIX RECIPE
Set flags at the appropriate gameplay events:
- HasCaughtFirstFish: FishingService.lua after line 166 (fish added to carried), if not already set.
- HasStoredFirstFish: AquariumService.lua StoreFish after successful store, and FishInventoryService.lua StoreSingleFish.
- HasClaimedIncome: AquariumService.lua ClaimIncome after successful claim.
- HasCompletedIntro: client-side after dismissing the welcome notification (or server-side after first StateSync.push).
- HasSeenRaidExplanation: when the raid explanation UI is shown (EPIC 8/9 scope — defer).

For V1, implement the first three (catch, store, claim) — they're one-liners in existing handlers. The other two depend on UI work tracked in EPIC 9.

## CONSIDERATIONS
- These flags drive EPIC 9's contextual prompts. Setting them now (even without the UI) unblocks that work.
- No client notification needed when flags flip — they're for the onboarding system's internal logic.

## FILES
src/server/FishingService.lua, src/server/AquariumService.lua, src/server/FishInventoryService.lua""",
        "- [ ] HasCaughtFirstFish set on first catch\n- [ ] HasStoredFirstFish set on first store\n- [ ] HasClaimedIncome set on first claim\n- [ ] Flags persist across sessions\n- [ ] UBS clean on touched files",
    ),
    (
        "TASK 14.23: Document aquarium/dock upgrade tiers as stubbed (no remote/UI)",
        2,
        """Documentation — prevent future agents from thinking upgrade systems work.

## ROOT CAUSE
GameConfig.AquariumUpgradeTiers (lines 58-63) and DockUpgradeTiers (lines 68-73) define full upgrade progressions, and PlayerProfile has UpgradeLevel fields for both. But there is NO remote, NO UI button, and NO service code that increments UpgradeLevel or reads the tier tables. The features are config-only stubs.

## FIX RECIPE
Add a prominent comment block at the top of each tier table in src/shared/GameConfig.lua:

    -- STATUS: STUBBED (V1) — no remote, UI, or service consumes this table.
    -- Activation tracked in EPIC 6 (Economy & Upgrade System).
    -- See TASK 14.7 (capacity derivation) for the first consumer.

And in PlayerProfile.lua on the UpgradeLevel fields:

    -- NOTE: never mutated by any service as of V1; stays at 1 unless EPIC 6 lands.

## CONSIDERATIONS
- Pure documentation task. No code behavior change.
- Prevents the confusion I (and the subagent) experienced ("these look implemented but aren't").

## FILES
src/shared/GameConfig.lua, src/shared/PlayerProfile.lua (comments only)""",
        "- [ ] Comment on AquariumUpgradeTiers marking it stubbed\n- [ ] Comment on DockUpgradeTiers marking it stubbed\n- [ ] Comment on PlayerProfile UpgradeLevel fields noting no mutator\n- [ ] UBS clean (comments don't affect lint)",
    ),
]


def main():
    print(f"Creating {len(TASKS)} addendum tasks under EPIC {EPIC_ID}...\n")
    ids = []
    acs = []
    for title, priority, description, ac in TASKS:
        bead_id = br_create(title, priority, description)
        if not bead_id:
            print("ABORT", file=sys.stderr)
            sys.exit(1)
        ids.append(bead_id)
        acs.append(ac)
        print(f"  {bead_id}  {title}")

    print("\nSetting acceptance criteria...")
    for bead_id, ac in zip(ids, acs):
        br_update_ac(bead_id, ac)

    # Wire 14.16's deps: needs 14.10 (rod consolidation) for minigameZoneSize
    print("\nWiring dependencies...")
    # Find IDs
    out, _, _ = run(["br", "list", "--all", "--json", "--limit", "200"])
    issues = json.loads(out)["issues"]
    by_title = {}
    for iss in issues:
        by_title[iss["title"]] = iss["id"]

    id_14_10 = by_title.get("TASK 14.10: Consolidate Rods/RodDefinitions and Baits/BaitDefinitions")
    id_14_16 = by_title.get("TASK 14.16: Server-side validation of catch minigame hit (CRITICAL authority gap)")
    if id_14_10 and id_14_16:
        run(["br", "dep", "add", id_14_16, id_14_10, "-t", "blocks"])
        print(f"  {id_14_16} blocked-by {id_14_10}  (14.16 needs canonical minigameZoneSize)")

    # Verify
    out, _, _ = run(["br", "dep", "cycles"])
    print(f"\nCycles: {out}")

    print(f"\nDone. Created {len(ids)} addendum tasks.")
    for i in ids:
        print(f"  {i}")


if __name__ == "__main__":
    main()
