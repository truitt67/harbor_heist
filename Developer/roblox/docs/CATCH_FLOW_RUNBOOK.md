# Catch Flow — Manual Verification Runbook (TASK 21.3)

Manual end-to-end verification of the core loop in Studio Play Solo:
join → auto-dock → cast (accuracy minigame) → bite (hit minigame) →
catch → store/sell → income claim. Complements the automated coverage:
E2E 19.2–19.4 (session/cast-bite/economy via seams) and datamodel specs;
this runbook verifies the parts those cannot reach — real remotes, real
client UI, real ProximityPrompts, real timing.

## Setup

1. Build the playable place:
   ```bash
   cd Developer/roblox
   rojo build default.project.json -o HarborHeist.rbxlx
   ```
2. Open `HarborHeist.rbxlx` in Roblox Studio (signed in).
3. Press **Play** (F5) — single player is sufficient.
4. Open the **Output** window and the **command bar** (View menu). Server
   state checks below run in the command bar in **server** context
   (Play Solo command bar defaults to server; if unsure, prefix checks
   with a print and confirm output appears).

Handy state probe (run any time):
```lua
local DM = require(game.ServerScriptService.HarborHeist.DataManager)
local s = DM.get(game.Players:GetPlayers()[1])
print("coins=", s.profile.Coins,
      "carried=", #s.carried,
      "stored=", #s.profile.Aquarium.StoredFish,
      "unclaimed=", s.profile.Aquarium.UnclaimedIncome,
      "dock=", s.dockIndex)
```

## Steps

### 1. Boot & session
- [ ] Place loads without errors in Output (no red stack traces from
      ServerScriptService.HarborHeist).
- [ ] HUD appears (coins, carried count). Probe prints `coins=0
      carried=0 stored=0` (fresh profile) and a non-nil `dock=`.

### 2. Auto-dock claim
- [ ] On join your dock is claimed automatically — the dock sign shows
      YOUR name (not "Unclaimed Dock") and the aquarium tank visual is
      present at the dock. (Docks are assigned in PlayerAdded via
      `DockManager.claim`; no player action needed. If all docks were
      taken you'd get an "All docks are taken!" notify — impossible in
      Play Solo.)

### 3. Fishing zone & cast
- [ ] Walk onto the Starter Pier fishing zone (water-facing).
- [ ] Press **F** → the cast starts and the **cast-accuracy overlay**
      appears (moving marker against a deadline bar).
- [ ] Click/tap to stop the marker. The client fires
      `CastResult(accuracy)`; the server maps the tier to a luck bonus
      (perfect=25, good=12, ok=0 — GameConfig.MiniGame.accuracyLuckBonus).
- [ ] NEGATIVE: press **F** while standing on land (outside any fishing
      zone) → cast is refused client-side BEFORE `RequestCast` fires
      (status message, no overlay).
- [ ] NEGATIVE: press **F** again while the overlay is open → ignored
      (debounced, no second overlay).

### 4. Bite
- [ ] After a server-rolled delay (zone-dependent), a **bite alert**
      fires and the bite minigame opens (marker sweeping a bar with the
      hit zone; hit zone width = rod's minigameZoneSize, base rod 0.30).

### 5. Bite minigame & catch
- [ ] Click when the marker is inside the zone → the reveal card shows
      species / rarity / sell value. Probe: `carried=1`.
- [ ] First-ever catch of a species → a **discovery** notification
      appears in addition to the card.
- [ ] Click OUTSIDE the zone (or let it time out) → "missed" feedback,
      no fish, `carried` unchanged. The cast is consumed either way.
- [ ] Sanity: the species/value on the card come from the server
      (client never sends a species or price — anti-exploit: 19.9 covers
      forged submits).

### 6. Store at the aquarium
- [ ] Catch 2+ fish (repeat 3–5).
- [ ] At your dock, hold the **Aquarium "Open" prompt** (0.5s hold) →
      aquarium panel opens (or press **T**).
- [ ] Store fish → `carried=0`, `stored=N` in the probe. Tank visual
      updates with fish.
- [ ] NEGATIVE: fill the aquarium to capacity (tier-1 = 20 via shop if
      you want to shortcut, or keep catching) → further stores are
      rejected with a capacity message; carried fish are NOT lost.

### 7. Income accrual & claim
- [ ] With fish stored, wait ~60s → probe shows `unclaimed > 0`
      (income accrues per stored fish).
- [ ] Claim income from the aquarium panel → coins increase by the
      unclaimed amount; `unclaimed=0` after.

### 8. Sell
- [ ] Catch 1 more fish (carried), use the sell action → coins increase
      by the fish's value; carried count decreases.
- [ ] NEGATIVE: sell with nothing carried/stored → rejected / no-op,
      coins unchanged.

### 9. Persistence (caveat!)
- [ ] LOCAL BUILD LIMITATION: this local .rbxlx is NOT published, so
      Studio blocks DataStore and saves are silent no-ops — stop/re-Play
      resets to a fresh profile. This is expected (docs/TESTING.md,
      EPIC19_GAPS G2). Round-trip persistence is verified by E2E 19.6
      (mock store) and should be re-verified against the PUBLISHED place
      periodically: join → catch/store → leave → rejoin → probe shows
      coins/stored/carried restored.

## Pass criteria

All checkboxes above. Any deviation: capture Output logs + probe output,
and file a bead before tuning. For cast-accuracy → luck tuning
specifically, pair this runbook with TASK 16.5 (50+ casts per rod tier).

## Cross-references

- Automated equivalents: E2E scenarios 19.2 (session/Lifecycle), 19.3
  (cast/bite/Fishing), 19.4 (economy/Aquarium), 19.9
  (forgery/rate-limits/AntiExploit) — `scripts/run_e2e_scenarios.sh`.
- Keybinds (client): F fish · G inventory · C collection · T aquarium ·
  Q quests · R raid panel · B boat.
- docs/TESTING.md — environment caveats (DataStore, sign-in, fakes).
