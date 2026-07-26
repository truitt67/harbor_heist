# V1 Closed Test — Full Playthrough Verification (TASK 13.1)

Sign-off mapping the PRD closed-test exit criteria and acceptance
criteria (PRD.md lines 554-594) to concrete evidence. Every criterion is
marked:

- **AUTO** — verified by an automated suite that runs green at HEAD
  (pure 100/100, datamodel TestEZ 410/410, E2E 198/198).
- **RUNBOOK** — verifiable by a scripted manual runbook (real Studio,
  real clients); steps exist and are repeatable.
- **HUMAN** — requires real players in the closed test itself; cannot be
  settled by automation or solo verification.

## Full playthrough loop (join → catch → store → earn → upgrade → raid → defend)

| Beat | Evidence | Status |
|------|----------|--------|
| New player joins, session + dock auto-claim | E2E 19.2; runbook §1-2 | AUTO |
| Casts, completes minigames, receives fish | E2E 19.3; runbook §3-5 | AUTO |
| Fish is server-determined (species/value/rarity) | E2E 19.3, 19.9; datamodel FishingService specs | AUTO |
| Stores in aquarium; capacity enforced | E2E 19.4 (incl. negative path); runbook §6 | AUTO |
| Stored fish visible in aquarium representation | Runbook §6 (tank visual) | RUNBOOK |
| Stored fish generate claimable income | E2E 19.4; runbook §7 | AUTO |
| Sells fish for coins | E2E 19.4; runbook §8 | AUTO |
| Buys rod/bait/capacity/dock upgrades; insufficient-funds rejected | E2E 19.5 | AUTO |
| Upgrades persist (leave/rejoin) | E2E 19.6 (mock store); published-place recheck | AUTO + HUMAN (real DataStore) |
| Raids: window, opt-in, minigame, steal, cooldowns | E2E 19.8.1; 2-player runbook 19.8.2 | AUTO + RUNBOOK |
| Defends: lock activation, cooldown, free uses, expiry | E2E 19.7 | AUTO |

## PRD acceptance criteria

### Core gameplay
- Cast → catch interaction → fish received: **AUTO** (19.3, runbook §3-5)
- Server determines result + updates inventory: **AUTO** (19.3/19.9 — server re-roll, server-constructed fish)
- Sell or store: **AUTO** (19.4)
- Stored fish visible in aquarium: **RUNBOOK** (runbook §6 — tank visual check)
- Claimable passive income in-game: **AUTO** (19.4)
- Buy + persist an upgrade: **AUTO** (19.5 + 19.6)

### Progression and collection
- Rarity / sale value / income contribution displayed: **RUNBOOK** (reveal card, runbook §5; values server-rolled — AUTO 19.3)
- Collection book records discoveries persistently: **AUTO** (datamodel CollectionService.spec) + **RUNBOOK** (collection panel, keybind C)
- Capacity restricts storage: **AUTO** (19.5 capacity recompute per tier; StateSync.getCapacity authoritative) + **RUNBOOK** (runbook §6 fill-to-capacity rejection)
- Upgrades persist after rejoin: **AUTO** (19.6 round-trip + v1→v2 migration incl. the capacityLevel bug found & fixed) + **HUMAN** (published-place DataStore recheck, EPIC19_GAPS G2)

### PvP fairness
- New-player raid protection until progression gates: **AUTO** (19.8.1 — 10 catches or aquarium upgrade)
- Locked aquarium cannot be raided: **AUTO** (19.8.1 victim-lock gate; 19.7 lock mechanics)
- Non-opted-in aquarium cannot be raided: **AUTO** (19.8.1 opt-in gates both sides)
- One raid cannot empty an aquarium: **AUTO** (19.8.1 steal-cap + Legendary exclusion)
- Victim protection period after successful raid: **AUTO** (19.8.1 immunity 1200s)
- Per-victim attacker cooldown: **AUTO** (19.8.1 — 30min per-victim, 6min global)
- All raid outcomes server-validated: **AUTO** (19.8.1 bad_input/self-raid/no_active_raid; 19.9 forged instant-submit)

### Quality
- Mouse/keyboard AND touch: **HUMAN** (client has IS_MOBILE paths; needs on-device verification)
- No client can change currency/rarity/inventory/raid result via invalid remote data: **AUTO** (19.9 abuse battery; 19.8.1 forgery checks; datamodel RaidServiceOutcome specs)
- Playable on target devices without UI overlap/perf degradation: **HUMAN** (device matrix)
- Analytics: first-session funnel + economy/PvP events: **AUTO** (event emission points wired through every verified flow — catch/purchase/raid/lock paths all call analytics.track) + **HUMAN** (dashboard ingest validation)

## Closed-test exit criteria (PRD)

1. **"New players understand the loop"** — readiness: full loop verified
   end-to-end (above); onboarding flow present (OnboardingService,
   first-cast/first-catch funnel events). Settlement requires real
   closed-test players: **HUMAN**.
2. **"Raid losses do not create disproportionate churn"** — fairness
   mechanics all verified (protection, immunity, cooldowns, loss caps).
   Churn itself is a live-metric question and a separate balance bead
   (13.3): **HUMAN / open**.
3. **"No obvious duplication or remote-event exploit"** — **VERIFIED**:
   19.9 battery (spam/forgery/bad payloads), server-authoritative
   currency/rarity/inventory, rate limiting on every mutating remote,
   suspicious-activity logging.

## Verdict

The game is **ready for the human closed test**: every automatable
criterion is green at HEAD, the irreducibly manual criteria have
repeatable runbooks (docs/CATCH_FLOW_RUNBOOK.md,
docs/RAID_TWO_PLAYER_RUNBOOK.md), and the exploit exit criterion is
verified. Remaining before public launch: on-device pass (touch/UI),
published-place persistence recheck, and live-metric raid-churn
evaluation (13.3) during the closed test itself.

## Evidence index

- E2E suite (198 assertions): `scripts/run_e2e.sh` — tasks 19.2-19.9
- Datamodel suite (410): `scripts/run_tests.sh --datamodel`
- Pure suite + gates (100): `scripts/run_tests.sh --pure` (CI: .github/workflows/tests.yml)
- Runbooks: docs/CATCH_FLOW_RUNBOOK.md (21.3), docs/RAID_TWO_PLAYER_RUNBOOK.md (19.8.2)
- Tuning: docs/ACCURACY_TUNING.md (16.5)
- Gap register: docs/EPIC19_GAPS.md
