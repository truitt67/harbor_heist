# Cast-Accuracy Tuning Report (TASK 16.5)

Data gathered 2026-07-26 via a Monte Carlo harness driving the REAL
server path (bite injection + `SubmitCatchInput(hit=true)` with a real
`Random.new()` RNG — no seeds, no shortcuts). 540 casts total:
60 casts per cell across 3 rod tiers x 3 accuracy tiers.

## Mechanic under test

`FishingService` submit-catch re-roll:

```
effectiveZone = baseZone + (luckBonus / maxLuck) * (ceiling - baseZone)
catch if rng:NextNumber() <= effectiveZone
```

- baseZone = rod minigameZoneSize: rod 1 = 0.30, rod 2 = 0.35, rod 3 = 0.40
- luckBonus = accuracyLuckBonus[tier]: ok = 0, good = 12, perfect = 25
- maxLuck = accuracyLuckBonus.perfect (25), ceiling = biteZoneCeiling (0.85)

## Observed vs analytic catch rates (n=60 per cell)

| Rod | Tier    | Luck | Observed | Analytic | Delta  |
|-----|---------|------|----------|----------|--------|
| 1   | ok      | 0    | 0.300    | 0.300    | 0.000  |
| 1   | good    | 12   | 0.600    | 0.564    | +0.036 |
| 1   | perfect | 25   | 0.817    | 0.850    | -0.033 |
| 2   | ok      | 0    | 0.333    | 0.350    | -0.017 |
| 2   | good    | 12   | 0.650    | 0.590    | +0.060 |
| 2   | perfect | 25   | 0.850    | 0.850    | 0.000  |
| 3   | ok      | 0    | 0.433    | 0.400    | +0.033 |
| 3   | good    | 12   | 0.633    | 0.616    | +0.017 |
| 3   | perfect | 25   | 0.817    | 0.850    | -0.033 |

Sampling noise at n=60 is ±~0.06 (1 sigma for p≈0.5), so every cell
matches the analytic formula within noise. The implementation is
faithful to the design formula.

## Tuning decision: KEEP current values

`accuracyLuckBonus = { perfect = 25, good = 12, ok = 0 }`,
`biteZoneCeiling = 0.85`.

Rationale:

1. **Skill expression is meaningful on every rod.** ok->perfect
   multiplier: rod 1 = 2.8x, rod 2 = 2.4x, rod 3 = 2.1x. Accuracy always
   matters; it matters MOST on the starter rod, which is the right shape
   for onboarding (skill substitutes for gear early).
2. **good is a real middle step** (~48% of the way up: 0.56-0.62), so
   partial accuracy is visibly rewarded — no cliff between perfect and
   nothing.
3. **The 0.85 perfect ceiling preserves tension.** Even a perfect cast
   misses ~1 in 6, so the bite minigame never feels ceremonial. This
   also caps always-hit exploiters at the perfect-honest rate (19.9
   verifies the server re-roll, not the client claim).
4. **Rod progression survives the ceiling.** At perfect, all rods
   converge to 0.85 — but rods still differentiate through base floor
   (0.30/0.35/0.40 for sloppy casts), castTime (4/3/2s — throughput),
   minigameZoneSize (easier hits), and luck (species rarity weighting).
   Flattening ONLY at perfect play is acceptable; a perfect-playing
   Golden Rod owner is earning their ceiling.

No config change. If a future manual feel-pass (runbook:
docs/CATCH_FLOW_RUNBOOK.md) judges perfect casts too reliable, the
single knob to turn is `biteZoneCeiling` (0.85 -> ~0.75 tightens
endgame), not the per-tier luck values — the interpolation shape itself
validated cleanly.

## Reproduction

The harness was a temporary block appended to
`tests/e2e/runner.server.lua` (before the Summary section), run via the
standard E2E path (`scripts/run_e2e.sh` equivalent), then reverted —
it is NOT part of the committed suite. To re-run: 60 fake players
rotated across submits to respect the submit_catch rate limit
(10/10s/player), bites injected via `_G.HARBORHEIST_TEST.activeBites`
with the target rodLevel/luckBonus, fresh `Random.new()` via
`setFishingRng`, catch counted by carried delta. Grep the Studio log
for `[TUNE 16.5]`.
