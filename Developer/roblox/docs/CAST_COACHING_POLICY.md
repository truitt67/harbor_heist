# Cast Coaching Policy — Idle & Off-Target Casts (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.1.1
**Status:** APPROVED policy — implementation target for etj2.1.2
**Evidence as of:** commit `31829a2` (line numbers drift; search the quoted strings)

Scope: the **cast-accuracy** minigame only (the timing bar after `RequestCast`,
before the bite). The later **bite** minigame has its own coaching
(`docs/MINIGAME_FEEDBACK_MODEL.md` §4.1, implemented in etj2.3.3) and is
explicitly out of scope here — the two must never share copy.

---

## 1. Current-state evidence

| Case | Detection | Feedback today | Gap |
| --- | --- | --- | --- |
| **Class A — idle cast**: overlay opens, ZERO taps before the server times the cast out | Client: `CastState(false)` arrives while `castAwaitingInput` is true (`init.client.lua` — search `coachShownIdleCast`) | Toast `"No timing bonus — tap the bar next cast!"`, **once per client session** | Policy undocumented; one-shot can be missed; string is ambiguous about WHICH miss happened |
| **Class B — off-target cast**: tap received, accuracy lands outside the good band → server derives tier `"none"`, `luckBonus` stays 0 | Server: `FishingService.lua` `CastResult` handler (`cast_result_tier` analytics, tier `"none"`) | **NOTHING.** Server notifies only on `perfect`/`good` (`"PERFECT CAST! +Luck on this catch."` / `"Good cast. +Luck on this catch."`) | Player who taps but misses the band gets silence — the same invisible penalty as never tapping, with no lesson |

Doc-drift note: `MINIGAME_FEEDBACK_MODEL.md` §3.1 lists `"No timing bonus — tap
the bar next cast!"` as the tier-none (Class B) string. The string exists
exactly once in the codebase and fires only for Class A. §3.1 is corrected to
point here.

Supporting mechanics this policy builds on:

- Toast system: `TOAST_LIFETIME` 3.6s, queue cap 8, non-severe categories tail
  the queue and are evicted oldest-first under pressure (`showNotification`).
- Onboarding prompt: single widget, one stage at a time; `firstWait` ("A fish
  usually bites within a few seconds — stay ready!") appears during the same
  pre-bite wait where the cast overlay lives; `firstCast` auto-dismisses when
  casting starts. Session-scoped dismissal is the established pattern.
- Esc-cancel (`kqbq.12.2`) clears `castAwaitingInput` before firing
  `CancelCast`, so an intentional bail NEVER counts as an idle cast. This is
  load-bearing for the policy: Class A means "the bar genuinely timed out."
- Server analytics already track `cast_result_tier` (perfect/good/none) on
  every `CastResult` — the telemetry hook for §6 requires no new events.

## 2. Miss-class definitions (acceptance #2)

The two failure classes are mechanically and pedagogically different, and the
copy must keep them distinct:

- **Class A — input not received.** The player never tapped. The lesson is
  *the bar needs a tap at all*. Blame-free framing: the bar "filled up."
- **Class B — timing was inaccurate.** The player tapped but landed outside
  the good band. The lesson is *tap inside the labeled zone*. The overlay
  renders the zones with literal `GOOD` / `PERFECT` micro-labels
  (DESIGN_SYSTEM.md §13), so copy names the **GOOD band** verbatim — the
  player can map the word to what they saw.

## 3. The policy

All coach state is **client session state** (or server session state for
Class B — see §4). Nothing persists to the profile (decision + rationale in
§5). A "session" = one client run; rejoining re-arms everything below.

### 3.1 Triggers and cadence

| # | Rule | Value |
| --- | --- | --- |
| T1 | **First trigger (A)** | First idle cast of the session → coach toast **A1** (existing behavior, new copy) |
| T2 | **Repeat trigger (A)** | If 3 FURTHER idle casts occur after A1 was shown (i.e. the 4th idle cast of the session), show **A2 exactly once** |
| T3 | **First trigger (B)** | First off-target cast of the session → coach toast **B1** |
| T4 | **Repeat trigger (B)** | Second off-target cast → **B2 exactly once** |
| T5 | **Demonstrated-success suppression** | After the player lands ANY cast inside the good band (client observes its own submitted accuracy against the server-sent zone bounds — internal suppression logic only, never a displayed tier claim), classes A and B are both **permanently suppressed for the session** |
| T6 | **Maximum frequency** | ≤ 1 coach toast per cast; ≤ 4 coach toasts per session total (A1, A2, B1, B2) |
| T7 | **Reset boundary** | Session end. A new session re-arms T1–T4 |

Why these numbers: the bead's plan-space review prescribes "coach on the
first no-input miss, repeat once after a bounded number of later no-input
misses, then suppress after demonstrated successful timing." Three intervening
misses (T2) is the bounded number: one miss could be distraction, two could be
confusion, three consecutive idle casts after being told means the toast
either wasn't seen or wasn't understood — exactly once more, with reworded
copy, then we stop talking. Class B repeats on the very next miss (T4) because
an off-target player is *engaged* (they tapped) and a second immediate miss is
the highest-value teaching moment; after that, the missing luck bonus is the
consequence and the labeled overlay is the coach.

### 3.2 Escalation

Escalation changes **copy only, never placement**. Both classes stay on the
toast channel (transient, non-blocking, single-channel per the feedback
model). The onboarding prompt widget is reserved for progression stages
(`firstCast`/`firstWait`/`firstStore`/…) and must not be borrowed for
transient coaching — two coach surfaces competing for the same attention
budget is the nag failure mode this policy exists to prevent.

### 3.3 Suppression conditions (beyond T5)

A coach toast is **dropped, not queued and not counted against the trigger
counts**, when any of these holds at the moment it would fire:

- S1 — an onboarding prompt is currently visible (any stage; firstWait in
  particular shares the screen with the cast overlay). The trigger stays armed
  and fires on the next occurrence.
- S2 — the toast queue is full (`activeToastCount >= maxVisibleToasts()`).
  Coach toasts are the lowest-priority traffic in the game; they never
  queue-jump (non-severe category, existing behavior) and are dropped rather
  than backlogged — a coaching toast surfacing 30s late teaches the wrong
  lesson at the wrong moment.
- S3 — a raid or bite overlay is active (cannot co-occur with a cast-overlay
  timeout under the initiation-gating model, but stated for completeness).

## 4. Implementation notes for etj2.1.2

- **Class A stays client-side.** The client already detects the condition
  (`castAwaitingInput` surviving into `CastState(false)`); the server cannot
  distinguish "never tapped" from "input lost to latency," and the existing
  toast is already here. Replace the single `coachShownIdleCast` boolean with
  a small state record: idle count, A1/A2 shown flags, demonstrated-success
  flag.
- **Class B moves server-side, session-scoped.** Symmetry with the existing
  perfect/good notifies (the server owns tier feedback — principle 2 of the
  feedback model: the client never claims a tier). In the `CastResult`
  handler, on `tier == "none"`, count per-session occurrences in the existing
  session table and `remotes.notify` B1/B2 on occurrences 1 and 2 only. No
  profile field, no migration.
- **T5 client hook:** in `overlayInputHandlers.cast`, when the submitted
  accuracy falls inside `castHitZone.goodStart_..goodEnd_`, set the
  demonstrated-success flag. This reads server-sent bounds and the player's
  own input; it displays nothing and grants nothing, so it does not violate
  the "client never claims a tier" rule.
- **S1 check:** read `onboardingPrompt.Visible` at fire time.
- **S2 check:** compare `activeToastCount` against `maxVisibleToasts()` before
  calling `showNotification` (both already exist at file scope).
- **Regression coverage (pure-spec pattern):** source-contract specs using
  `string:find` on `init.client.lua` / `FishingService.lua` pinning (a) the
  four copy strings verbatim, (b) the two-trigger structure per class,
  (c) Esc-cancel still clearing `castAwaitingInput`, (d) no `Profile` write on
  the new paths. Same pattern as the etj2.3.x contract pins.

## 5. Persistence decision (acceptance #4)

**Decision: no persistent profile flag.** All four coach triggers re-arm every
session.

Rationale:

1. The cost of re-arming is bounded and tiny: at most 4 short toasts per
   session, each only on an actual miss — a player who learned yesterday and
   still plays well today sees ZERO of them (T5 suppresses on demonstrated
   success, and a skilled player simply never triggers T1/T3).
2. The benefit of persistence is speculative: "learned cast timing" would
   only save those ≤4 conditional toasts for players who both learned AND
   still occasionally idle/miss — precisely the players who may need the
   refresher after a week away.
3. Persistence has real cost: a new `PlayerProfile` field is a migration
   surface and a permanent schema commitment (cf. the onboarding flags, which
   gate *progression stages* — a durable concept — not transient coaching).
4. Reversal path exists: §6 defines the evidence that would justify
   revisiting. Until closed-test data shows session-reset coaching is
   insufficient, session state wins.

## 6. Success criteria and retune triggers (acceptance #5 evidence plan)

Telemetry already available (no new events required for v1):

- `cast_result_tier` distribution (server, per cast): the `none` share should
  drop for new players after this ships; a flat line says the coaching isn't
  landing.
- `first_cast` / `fish_caught` funnel (AnalyticsService): idle-cast-heavy new
  players who never reach `fish_caught` are the cohort to watch.

Playtest evidence that justifies retuning:

- Retune cadence if: playtesters verbalize the mechanic but still miss
  (copy problem, not cadence) OR report the reminder as nagging (T2 too
  eager).
- Add persistence if: returning closed-test players show a `none`-tier share
  in session N+1 statistically indistinguishable from session 1 — i.e. the
  session reset is demonstrably failing to stick. Only then is a profile flag
  earned.

## 7. Copy matrix (§15-conformant, ≤ 90 chars, outcome + next action)

| ID | Fires on | Copy | Class distinction |
| --- | --- | --- | --- |
| A1 | 1st idle cast | `The cast bar filled up — tap it before it fills to keep your luck bonus.` | "filled up" = you didn't act |
| A2 | 4th idle cast (3 after A1) | `Still no luck bonus — one tap on the cast bar before it fills is all it takes.` | patient reminder, names the single required action |
| B1 | 1st off-target tap | `That tap missed the GOOD band — tap inside it to keep the luck bonus.` | "missed the GOOD band" = you acted, aim was off |
| B2 | 2nd off-target tap | `The luck bonus needs the GOOD band — watch the marker and tap inside it.` | escalates with the specific skill: watch the marker |

All four: sentence case, em-dash pivot, terminal period, no exclamation (not
celebrations), no blame, ≤ 90 chars (mobile toast limit, §15.6). The legacy A
string `"No timing bonus — tap the bar next cast!"` is retired — it named the
penalty but neither the cause nor the class.

## 8. Interaction with firstWait / firstCast (acceptance #3)

- **firstCast** ("Press F to cast into the glowing zone at your dock!"):
  pre-cast guidance. Auto-dismisses the moment a cast starts; cannot collide
  with post-timeout coaching. Unaffected.
- **firstWait** ("A fish usually bites within a few seconds — stay ready!"):
  appears on the first cast's pre-bite wait — the SAME wait during which the
  cast overlay is open. A first-time player who idles their first cast would
  see the prompt AND be eligible for A1. Rule S1 resolves this: the prompt
  owns attention, A1 is dropped without consuming the trigger, and the NEXT
  idle cast coaches. The firstWait prompt itself auto-dismisses when the wait
  ends, so the surfaces never stack.
- **Zone cue / zone-refusal streak** (`a2ug.15`): coaching for casting from
  OUTSIDE the fishing zone — a different failure (refused request, not a timed
  overlay). No interaction; listed to keep the coaching surface map complete.

## 9. Studio test cases (acceptance #5)

| # | Scenario | Expected |
| --- | --- | --- |
| 1 | First idle cast of a session | A1 toast once; no repeat on cast 2–3 idles |
| 2 | Four idle casts in one session | A1 on #1, A2 on #4, silence on #5+ |
| 3 | Idle cast AFTER a demonstrated good/perfect cast | No coach toast (T5) |
| 4 | First + second off-target taps | B1 then B2; silence on #3+ |
| 5 | Idle cast while firstWait prompt visible (fresh account, first cast) | No toast; trigger stays armed — next idle coaches |
| 6 | Idle cast with a full toast queue (e.g. raid flurry) | Coach dropped, not backlogged |
| 7 | Esc-cancel a pending cast | No coach (castAwaitingInput cleared — intentional bail) |
| 8 | Rejoin (new session) and idle a cast | A1 re-fires (session reset) |
| 9 | Mix: off-target, then idle, then off-target | B1, A1, B2 — counters independent |
| 10 | Mobile viewport: each coach string | Fits ≤ 2 lines (≤ 90 chars) |

---

*Binding on etj2.1.2 (implementation). Copy changes after this point require
a §15 review; cadence changes require the §6 evidence.*
