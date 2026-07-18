# Fellow-Agent Code Review — Round 2 (2026-07-18, Hermes-K3)

Wide-net review of ALL Lua code written by fellow agents (RedBear / GoldenEagle),
beyond the latest commits. Focused on files not previously reviewed:
DockManager, BoatService, RodService, QuestService, WorldBuilder,
FishDefinitions, ZoneDefinitions.

## Bugs Found & Fixed (beads filed + closed)

### 1. Quest progress gap on single-fish paths (harborheist-41o)
**File:** `src/server/FishInventoryService.lua`
**Root cause:** `StoreSingleFish` and `SellFish` handlers never called
`questService.onFishStored` / `questService.onFishSold`. Only the bulk paths
(`StoreFish`/`SellAll` in AquariumService) fired those hooks. So `store_count`
and `sell_value` quests only progressed on bulk actions — players using the
single-fish buttons got zero quest credit. FishInventoryService was written as
a separate service (single-fish granularity) without wiring the same quest
hooks as AquariumService.
**Fix:** Added `questService` to FishInventoryService deps; fire
`onFishStored(session, 1)` on StoreSingleFish success and
`onFishSold(session, payout)` on SellFish success. Both paths now consistent.
**Verified:** luau clean.

### 2. Stun-escape exploit via SpawnBoat (harborheist-3kl)
**File:** `src/server/BoatService.lua`
**Root cause:** `SpawnBoat.OnServerInvoke` teleports the player's character to
the boat dock with no stun check. A thief stunned after a failed steal
(WalkSpeed=8) could call SpawnBoat and instantly teleport away, defeating the
stun's purpose (slow the getaway so the victim can react). The SpawnBoat
handler predates the stun system; no cross-system validation.
**Fix:** Added stun check at the top of the SpawnBoat handler — blocks with
`stunned` reason + notify if `session.stunUntil > os.clock()`, matching the
steal handler's own stun enforcement (AquariumService).
**Verified:** luau clean.

## Areas Reviewed, No Bugs Found

- **DockManager** (455 LOC): claim/release lifecycle, isInFishingZone spatial
  math, updateAquariumVisual + lock status label. `lockedUntil` nil-compare
  concern verified safe (initialized to 0 in DataManager). `getDockByAquarium`
  is defined but never called (dead code, not a bug).
- **BoatService** (437 LOC): despawn lifecycle clears all 3 module tables
  (boats/despawnTasks/seatConnections) on every path. No player-keyed leaks.
- **RodService** (437 LOC): equip/unequip/cast-FX lifecycle clean;
  onPlayerRemoving clears both activeCasts and rods.
- **QuestService** (211 LOC): quest pool, daily/weekly key rotation,
  progress hooks, claim logic. All 5 event hooks (catch/steal/income/store/
  sell) are wired — but see Bug 1 (two were only wired on bulk paths).
- **WorldBuilder** (297 LOC): purely declarative part placement + lighting.
  No state, no leaks.
- **FishDefinitions** (274 LOC): weighted species roll with luck shift is
  mathematically sound (no div-by-zero, RARITY_ORDER lookup safe).
- **ZoneDefinitions** (54 LOC): trivial, clean.
- **StateSync** (112 LOC): nil-safe session field access, leaderstats sync,
  no leaks. Income multiplier chain (Aquarium x Dock) correct.
- **DataManager save path**: nested-table aliasing into UpdateAsync is safe
  (UpdateAsync serializes synchronously within the callback; sanitize creates
  a fresh table per attempt).

## Cross-Cutting Observations

- Client only sends validated inputs; server re-derives everything
  (catch timing, cast accuracy, purchases) from session state. No
  client-trust violations found.
- The stun system had exactly one escape vector (SpawnBoat) — now closed.
- Quest hooks are the pattern most prone to gaps when a new code path is
  added; any future store/sell variant must fire the same hooks.
