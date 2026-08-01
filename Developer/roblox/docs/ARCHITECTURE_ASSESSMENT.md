# Architecture Assessment — Patterns to Preserve

**Bead:** harborheist-review-aug2026-6yp6.12 (deep-review epic 6yp6)
**Date:** 2026-08-01
**Audience:** future agents and developers working in this repo

This document aggregates the architecture strengths identified during the
August 2026 deep code review, so future refactors preserve what works and
understand why it was built this way. Each pattern is cross-referenced to
its source. The detailed reasoning also lives in code comments at each
site — this file is the high-level index.

## Verdict

harbor_heist is well-architected for a V1 server-authoritative multiplayer
game. The review found **no critical security or data-integrity bugs**.
The issues fixed by the review epic (6yp6.1–6yp6.8) were memory hygiene
and defensive-coding gaps, not exploits or data-loss paths.

---

## Patterns to Preserve

### 1. DataManager rejoin-race protection — src/server/DataManager.lua

The most sophisticated pattern in the codebase. Three interlocking
mechanisms prevent data loss from the rapid leave→rejoin race:

- **activeSessionsByUserId[userId]** — maps UserId → active session. A
  deferred leave-save checks this inside UpdateAsync; if the player has
  already rejoined (new session replaced the old), the stale save returns
  oldData unchanged (no-op). A stale leave-save can never clobber fresher
  rejoin data.
- **pendingSaveUserIds[userId]** — count of in-flight saves per UserId.
  load() waits (bounded, 16s) for pending saves before GetAsync, so a
  rapid rejoin never loads stale pre-save data.
- **saveDirty coalescing** — a checkpoint save arriving while another is
  in-flight sets saveDirty instead of queuing; the in-flight save's
  trailing write picks up all accumulated changes. N rapid checkpoints
  collapse into at most 2 sequential DataStore writes.

All three are keyed by **UserId** (stable across rejoins), never by Player
object (destroyed on leave). Do not "simplify" any of these away — they
each defend a distinct failure mode.

### 2. FishingService cast generation token — src/server/FishingService.lua

`castGen[player]` is a monotonic token solving the "uncancelable
task.delay" problem (Luau has no task.cancel for task.delay):

- Each cast stamps a generation id; the delayed bite callback captures it.
- CancelCast bumps the generation; when the stale callback fires,
  `castGen[player] ~= myGen` → early return.
- Prevents stale callbacks from firing BiteEvent, notifications, or
  rodService.endCast on a cancelled cast.

**Convention:** use this pattern for ALL task.delay callbacks that user
action can invalidate.

### 3. RaidService TOCTOU fish transfer — src/server/RaidService.lua

resolveRaidSuccess defends the Time-of-Check-Time-of-Use gap in fish
theft:

1. Weighted-pick selects a target fish from the victim's list.
2. Re-find the selected fish by reference in the LIVE list (not the
   captured snapshot).
3. Re-validate IsRaidProtected before removal.
4. Wrap the transfer (remove from victim + insert into attacker) in a
   pcall — a throw between removal and insertion rolls the fish back to
   its original index.
5. Post-transfer side effects (immunity, notifications, saves) are
   explicitly outside the transaction.

Prevents both fish duplication (in both aquariums) and fish loss (in
neither) from partial-failure races.

### 4. Server-authoritative catch resolution — src/server/FishingService.lua

Server authority at every layer of the fishing flow:

- Cast accuracy: client sends raw marker position [0,1]; the server
  re-derives the tier from its OWN stored bounds.
- Luck bonus: derived from server-authoritative cast bounds, never
  client-claimed.
- Catch re-roll: server rolls rng:NextNumber() against effectiveZone —
  a client cannot achieve a 100% catch rate.
- Species/rarity: fully server-rolled via FishDefinitions.getRandomInZone.
- Value/income: from FishInstance (server-created at catch time), never
  client-modifiable.

A forged "always perfect" client is capped at the perfect-honest rate; a
forged "always hit" client is capped by the re-roll. This is the correct
client-trust-minimizing design — preserve it end-to-end.

### 5. RaidService minimum-time check — src/server/RaidService.lua

The harborheist-yxdh check in submitRaidResult blocks timing forgery:

- The client tweens the marker 0→1 over durationSeconds linearly.
- The server records startTime at challenge issue.
- minNeeded = position × duration (earliest the marker can legitimately
  reach the reported position).
- elapsed < minNeeded − NETWORK_GRACE (0.5s) → rejected as "too_fast".

Catches bots that intercept zone bounds and report an instant perfect
position — physically impossible for a real player watching the sweep.

### 6. DataManager deep sanitize — src/server/DataManager.lua

sanitize() is the last line of defense against corrupted DataStore data:

- Every field type-checked before assignment; numerics clamped to valid
  ranges (coins, capacity, upgrade levels, timer timestamps).
- Fish validated via FishInstance.validate() (instance ID, species
  existence, sell value, income).
- Quests structure-validated; onboarding flags whitelisted to the 5 known
  keys (junk keys dropped).
- Legacy v1 data converted (flat fields → structured profile, rarity
  indexes → FishInstances); collection milestones accept both map and
  legacy array form; JSON round-trip coercion handled.

**Never trust persisted data.** Any new profile field needs a sanitize
path from day one.

### 7. v1→v2 migration with rollback anchor — src/server/DataManager.lua

The breaking format change was shipped without risking the only copy:

- v2 is read first; if empty, v1 is read, sanitized, written to v2.
- v1 is left intact as a rollback anchor for the closed-test grace period.
- Migration is logged with print (expected), not warn (error).
- The migrated profile is persisted to v2 immediately (deferred one
  frame), so a disconnect before the first autosave still persists.

The correct pattern for format changes in a live game: rollback possible,
bad migration can't corrupt the only copy.

### 8. PlayerProfile.clampCoins NaN rejection — src/shared/PlayerProfile.lua

```lua
if value ~= value then return 0 end
```

NaN passes Lua's type() guard (type(NaN) == "number") and propagates
through math.min/max/floor. `(NaN < cost)` is always false, so a
NaN-coined player could buy everything for free. The identity check
`value ~= value` is the standard NaN test (NaN is the only value not
equal to itself). Subtle, critical, and easy to delete by mistake —
don't.

---

## Patterns to Watch (not bugs — risk areas)

1. **Full-snapshot push every income tick** — appropriate for V1 CCU;
   the delta-sync escape hatch is documented in
   AquariumService.startIncomeLoop (6yp6.9). Revisit if CCU grows.
2. **`while true do` loops** — standard in Roblox, but each adds a
   coroutine. Track the count as features grow.
3. **task.delay callbacks referencing player/session state** — always
   check player.Parent and session validity (see the bite callback guard
   in FishingService and the stun callback guard in RaidService).
4. **Connection lifecycle** — see the convention below.

## Connection Lifecycle Convention (established by this epic)

The review found a mix of explicit-disconnect and fire-and-forget
patterns. The convention now in force:

- **Per-element connections** (buttons, panels, any recreated UI): store
  per-interaction and auto-disconnect via the element's `Destroying`
  signal. Reference implementation: AnimationSystem.lua (6yp6.5).
- **Per-instance one-shot signals** (tween Completed, etc.): use `:Once`,
  not `:Connect` + manual disconnect. Reference: PanelAnimation.lua
  (6yp6.6).
- **Tracked connections replaced at runtime** (camera-bound signals):
  store the handle, disconnect the stale one before rebinding. Reference:
  aquarium viewport binding in init.client.lua (6yp6.4).
- **Static session-lifetime connections**: returning/storing the handle
  is sufficient — see applyScrollbarAutoHide (6yp6.2).
- **Lifecycle-scoped trackers** (per-toast etc.): disconnect in the
  teardown path before the fade/destroy. Reference: toast dismiss
  (6yp6.1).

All of these are pinned by source-contract assertions in test/pure_specs/
(ClientChrome, AnimationSystemLogic, PanelAnimationLogic, DockManagerLogic)
so regressions fail the pure suite.

## Related review-epic fixes (all landed 2026-08-01)

| Bead | Fix |
| --- | --- |
| 6yp6.1 | Toast AbsoluteSize connection stored + disconnected in dismiss() |
| 6yp6.2 | Scrollbar/action-stack connections return/store handles (7 sites) |
| 6yp6.4 | Aquarium viewport stale-camera connection disconnected on rebind |
| 6yp6.5 | AnimationSystem micro-interaction Destroying cleanup + registry eviction |
| 6yp6.6 | PanelAnimation Completed:Once one-shot convention (4 sites) |
| 6yp6.7 | Onboarding state access pinned inside render()'s nil guard (contracts) |
| 6yp6.8 | DockManager FindFirstChild defensive access (3 sites) |
| 6yp6.9 | V1 design-decision comments (3 sites) + pinning contracts |

Studio-gated verification (device/UI behavior) remains tracked under the
QA epics; every fix above is covered by pure-spec contracts runnable on
Linux via `scripts/run_tests.sh --pure`.
