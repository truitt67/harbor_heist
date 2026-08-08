# Studio Verification Matrix (consolidated)

**Purpose:** ONE ordered checklist for the Windows/Roblox Studio session(s) that
verify all remaining launch-gated work. Pre-staged headless from bead bodies so
the Studio session starts with zero archaeology.

**Covers beads:** `harborheist-orpl` (TASK 42.6), `harborheist-rswb`,
`harborheist-zapr`, `harborheist-6c2y`, `harborheist-kqbq.23.2` (EPIC-44),
`harborheist-ux45-workflow-clarity-etj2.5.2` (EPIC 45), plus the
`harborheist-gx6h` Studio row added 2026-08-08.

**Execution rules (from the beads):**

1. Fold rows into the `orpl` / `rswb` Studio runs where practical — one pass,
   one result recorded per bead even when a single run satisfies several rows
   (etj2.5.2 COORDINATION). Coordinate via Agent Mail before duplicating runs.
2. Every row records: bead, setup, steps, expected, observed, pass/fail,
   device/viewport, screenshot/video note, follow-up ID (etj2.5.2 EVIDENCE).
3. Keep these states DISTINCT in the result: headless-passed, Studio-passed,
   device-passed, not-verified (etj2.5.2 AC5).
4. Failures create `--deps discovered-from:<bead>` follow-ups and the row
   stays open.
5. Windows specifics: `docs/TESTING.md` → "Running on Windows (Studio present)"
   (Git-Bash launcher trap, CRLF→LF normalization, plugin-vs-server context).

---

## Section 1 — Boot & world (orpl / rswb)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 1.1 | orpl, rswb | Fresh place, solo Play | Start game; wait for harbor build | Plaza, 8 docks, aquariums, shop, water built by server; no console errors |
| 1.2 | rswb | Solo Play | Open each panel: AQUARIUM, FISH BAG, COLLECTION, SHOP, QUESTS, RAID, onboarding, sell/store prompt, help | Panels render tokenized colors/spacing/typography per DESIGN_SYSTEM; no hardcoded-look drift |
| 1.3 | rswb | Solo Play | Toast triggers: insufficient funds, quest complete, raid events | Toast accent/ellipsis spec (kqbq.18), density cap, 44px action targets on mobile |

## Section 2 — Core loop: cast → bite → catch (orpl)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 2.1 | orpl | Claim dock, equip Basic rod | Click FISH / press F; time cast bar | Cast overlay shows, server validates, bobber lands |
| 2.2 | orpl | Cast landed | Hit bite window | Bite marker appears, timing ack, catch resolves server-side |
| 2.3 | orpl, etj2.1.2 | Miss the bite window intentionally | Watch timeout copy | Calm recovery guidance (etj2.3.3), adaptive idle-cast coaching after repeated idles (etj2.1.2) |
| 2.4 | etj2.5.2 | Fresh profile | Play first session | Onboarding flow + idle coaching reads as self-explanatory |

## Section 3 — Store / sell economy (etj2.5.2)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 3.1 | etj2.2.4 | Bag with fish, tank nearly empty | STORE ALL | All-fit path: one tap, stored, income starts |
| 3.2 | etj2.2.4 | Bag fish exceed remaining capacity | STORE ALL | Partial path: capacity preview BEFORE commit; overflow explained; authoritative reconciliation after |
| 3.3 | etj2.2.4 | Tank full | STORE ALL | Full path: blocked state explains why + recovery (sell first / upgrade) |
| 3.4 | etj2.5.2 | Any stored fish | SELL ALL | Two-step payout confirmation; previewed amount matches payout |

## Section 4 — Shop (etj2.5.2 / rswb)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 4.1 | etj2.2.2 | Cash below cheapest upgrade | Walk to shop, press E | Insufficient-funds state states price + recovery |
| 4.2 | etj2.2.2 | One track at max | Inspect maxed item | Maxed track explains prerequisite/max at decision point |
| 4.3 | rswb | All shop tabs | Browse rods/bait/tank/locks/alarms/docks | Tokenized visuals; buy buttons 44px mobile |

## Section 5 — Defense & raids (etj2.5.2 / orpl)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 5.1 | orpl | 2-player test, raid window announced | Opt in, raid rival aquarium | Full raid minigame: target pick, theft resolution, outcome |
| 5.2 | etj2.3.2 | Win and lose raids | Watch result screens | Outcome coaching states tier + failure reason (win/lose/stunned) |
| 5.3 | etj2.3.3 | Let raid timer expire | Watch timeout | Calm recovery guidance with next-window timing |
| 5.4 | etj2.5.2 | Mid-raid | Switch target before committing | Target-change path behaves; no stale state |
| 5.5 | etj2.5.2 | Victim side | LOCK during raid; alarm trips thief | Lock blocks theft; alarm stuns; victim notified |
| 5.6 | etj2.5.2 | DataStore-degraded seam | Trigger degraded copy via safe seam | Degraded banner/toast copy matches DATASTORE_DEGRADED_CONTRACT.md truth |

## Section 6 — Desktop modality (kqbq.23.2 / gx6h)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 6.1 | kqbq.20 | Desktop | Hover action-bar buttons | Tooltips: delay on hover, immediate on keyboard focus, hidden when suppressed |
| 6.2 | kqbq.20 | Desktop | Tab through every panel; Enter/Space activates; Esc cancels overlays | Full keyboard parity |
| 6.3 | **gx6h** | Desktop, keyboard only | Open panel (auto-focus), close panel (focus restore), Tab-cycle | UIStroke focus ring visible on auto-focus and restore paths, not only Tab — no double ring vs engine selection |
| 6.4 | **gx6h** | **Gamepad** (console emulation or controller) | D-pad through action bar + panels | Accent focus ring follows D-pad selection; Enter/A activates; ring never duplicates |
| 6.5 | rswb | Ultra-wide viewport (21:9+) | Inspect HUD + panels | Layout holds; HUD six-digit cash fits; no clipping |

## Section 7 — Mobile modality (kqbq.23.2 / 6c2y)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 7.1 | 6c2y | Mobile portrait 375px | Full session | Stack fade, toast density cap, 44px targets, safe-area insets |
| 7.2 | 6c2y | Short landscape (~375px height) | Full session | Panels fit; landscape scroll works; nothing clipped by home indicator |
| 7.3 | kqbq.21 | Mobile | Long lists (shop/collection) | Scroll affordance, scrollbar auto-hide, grab handle |
| 7.4 | kqbq.21 | Mobile | Panel drag-to-dismiss | Grab-handle dismiss + re-show race handled (3mo7 precedent) |

## Section 8 — Motion & delight (kqbq.23.2)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 8.1 | kqbq.17 | Desktop + mobile | Panel open/close sweeps | Entries decelerate; exits 0.8x; EASE tokens; no jank |
| 8.2 | kqbq.18 | All buttons | Press/hover/disabled | Press=In/release=Spring feel; disabled recipe legible; ripple on dark+light |
| 8.3 | kqbq.19 | Cast/bite/raid | Full loop | One visual language: markers, labels, tap ack |
| 8.4 | kqbq.22 | Empty states | Fresh profile: empty bag/tank/collection | Delightful empty states; income pulse; scroll restore after close→reopen |
| 8.5 | etj2.3.4 | Two overlays racing | Trigger accepted contention cases | Races visible + recoverable (no silent dead end) |

## Section 9 — Accessibility evidence (etj2.5.2 / gx6h)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 9.1 | etj2.4.5 | Desktop | Sweep status, rarity, focus states | No color-only meaning (icons/labels present) per etj2.4.5 audit |
| 9.2 | etj2.4.4 | CONTRAST_MATRIX.md samples | Sample composited contrast in rendered UI | Remediated pairs pass; borderline claimReady only on large text |
| 9.3 | gx6h | Keyboard + gamepad | Row 6.3/6.4 evidence | WCAG 2.4.7 focus-visible evidence with screenshots |

## Section 10 — Performance (zapr)

| # | Bead | Setup | Steps | Expected |
|---|------|-------|-------|----------|
| 10.1 | zapr | Studio + low-end target device | Play session with panels animating, raid active | 60fps on target; frame-rate/memory/CPU notes recorded |
| 10.2 | zapr | Same | Profile AnimationSystem springs + tweens during stress | No jank sources; optimize any offenders (file follow-up beads) |

---

## After execution

1. Record results per row (this file or per-bead evidence files).
2. Update beads: `rswb`/`orpl`/`zapr`/`6c2y`/`kqbq.23.2`/`etj2.5.2` →
   closed or follow-up beads filed.
3. Then run `harborheist-ux45-workflow-clarity-etj2.5.5` (task-based usability)
   and the two closeout beads (`kqbq.23.3`, `etj2.5.3`).
4. Mail the result summary to all active agents.
