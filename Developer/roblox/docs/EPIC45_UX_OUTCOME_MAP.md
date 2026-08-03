# EPIC 45 UX Outcome Map

**Bead:** harborheist-ux45-workflow-clarity-etj2.5.4  
**Purpose:** Map each EPIC 45 intervention to an observable success signal using existing AnalyticsService events. Establish baseline (or label "not currently measurable"), define target direction, and identify guardrail metrics.

**Principle:** Do not add telemetry merely because it is measurable. Only propose new instrumentation when the metric will change a product decision. This document uses existing events where possible and documents gaps for future consideration.

---

## WS-A: Guidance and Coaching

### Intervention: Adaptive cast coaching (idle vs off-target cadence)

**Beads:** etj2.1.1, etj2.1.2

**Observable signal:**
- `first_cast` → `first_catch` time delta (funnel timing)
- `fish_catch_failed` count in first 5 minutes (confusion signal)

**Baseline:** Not currently measurable (no live closed-test data). Will be established after EPIC 45 lands and closed-test begins.

**Target direction:** Reduce time-to-first-catch for fresh profiles. Reduce repeated `fish_catch_failed` in first session (players learning the timing window).

**Guardrail metric:** Don't increase repeated no-input casts (players casting without timing → coaching isn't landing).

**Post-change review window:** 7 days after closed-test launch. Compare first-catch rate and time-to-first-catch against pre-EPIC-45 baseline (once established).

**Product decision this informs:** If time-to-first-catch doesn't improve, coaching cadence is too subtle or too aggressive. Adjust A1/A2/B1/B2 thresholds.

---

## WS-B: State Clarity and Consequence Previews

### Intervention: Unavailable-state pattern (LOCKED, MAXED, cooldown)

**Beads:** etj2.2.1, etj2.2.2, etj2.2.3

**Observable signal:**
- `upgrade_shop_opened` → `upgrade_purchased` conversion rate
- Repeated `upgrade_shop_opened` without `upgrade_purchased` (frustration signal: player opened shop but didn't buy)

**Baseline:** Not currently measurable.

**Target direction:** Increase shop conversion rate. Reduce repeated shop opens without purchases (players understand LOCKED/MAXED states and don't retry).

**Guardrail metric:** Don't decrease `upgrade_purchased` volume (clarity shouldn't block purchases).

**Post-change review window:** 14 days after closed-test launch. Compare shop conversion rate against pre-EPIC-45 baseline.

**Product decision this informs:** If conversion drops, state clarity is too aggressive (players feel blocked). If repeated opens don't decrease, clarity isn't landing (players still confused).

---

### Intervention: STORE ALL consequence preview

**Beads:** etj2.2.3, etj2.2.4

**Observable signal:**
- `fish_sold` count distribution (how many fish per sale?)
- Repeated `fish_sold` events in short window (player sold 1-2 fish, then tried STORE ALL again → preview wasn't clear)

**Baseline:** Not currently measurable.

**Target direction:** Reduce repeated STORE ALL attempts at full capacity (players understand the preview and don't retry).

**Guardrail metric:** Don't decrease `fish_sold` volume (preview shouldn't block sales).

**Post-change review window:** 14 days after closed-test launch.

**Product decision this informs:** If repeated attempts don't decrease, preview isn't clear (players don't understand capacity constraint).

---

### Intervention: DataStore degraded banner

**Beads:** etj2.2.5, etj2.2.6, etj2.2.7

**Observable signal:**
- `suspicious_action` count during/after DataStore outage (confusion signal: players trying to act while banner is up)
- Time between banner clear and next `income_claimed` (recovery signal: players notice banner is gone and resume normal play)

**Baseline:** Not currently measurable (DataStore outages are rare).

**Target direction:** Reduce `suspicious_action` during degraded mode (players understand the banner and don't panic). Reduce recovery time after banner clears (players notice the all-clear).

**Guardrail metric:** Don't increase `suspicious_action` (banner shouldn't cause confusion).

**Post-change review window:** Next DataStore outage (opportunistic).

**Product decision this informs:** If `suspicious_action` spikes during degraded mode, banner copy isn't clear (players don't understand what's broken).

---

## WS-C: Outcome Learning and Resilient Recovery

### Intervention: Two-layer minigame feedback (timing vs chance)

**Beads:** etj2.3.1, etj2.3.2

**Observable signal:**
- `cast_result_tier` distribution (PERFECT / GOOD / MISS)
- `fish_catch_failed` count (chance-miss signal)
- Repeated `fish_catch_failed` with same timing pattern (player not learning the window)

**Baseline:** Not currently measurable.

**Target direction:** Reduce repeated `fish_catch_failed` in short window (players learning from feedback). Increase `cast_result_tier` = GOOD/PERFECT over time (players improving timing).

**Guardrail metric:** Don't decrease `fish_caught` volume (feedback shouldn't discourage attempts).

**Post-change review window:** 7 days after closed-test launch. Compare catch-fail rate against pre-EPIC-45 baseline.

**Product decision this informs:** If catch-fail rate doesn't decrease, feedback isn't landing (players don't understand timing vs chance).

---

### Intervention: Raid result coaching

**Beads:** etj2.3.2, etj2.3.3

**Observable signal:**
- `raid_attempted` → `raid_succeeded` conversion rate
- Repeated `raid_attempted` without `raid_succeeded` (frustration signal: player trying but not winning)
- `raid_attempted` abandonment (player starts raid minigame but never submits → inferred from `raid_attempted` without `raid_succeeded`/`raid_defended`)

**Baseline:** Not currently measurable.

**Target direction:** Increase raid success rate (players learning from coaching). Reduce repeated attempts without success (players understand why they failed).

**Guardrail metric:** Don't decrease `raid_attempted` volume (coaching shouldn't discourage raids).

**Post-change review window:** 14 days after closed-test launch.

**Product decision this informs:** If success rate doesn't improve, coaching isn't clear (players don't understand the raid minigame).

---

### Intervention: Fishing recovery copy (timeout, zone-leave)

**Beads:** etj2.3.3, etj2.3.4

**Observable signal:**
- `fish_catch_failed` count (timeout signal)
- Repeated `fish_catch_failed` in short window (player not learning from recovery copy)

**Baseline:** Not currently measurable.

**Target direction:** Reduce repeated `fish_catch_failed` with same reason (players learning from recovery copy).

**Guardrail metric:** Don't decrease `fish_caught` volume (recovery copy shouldn't discourage fishing).

**Post-change review window:** 7 days after closed-test launch.

**Product decision this informs:** If repeated failures don't decrease, recovery copy isn't landing (players don't understand what went wrong).

---

### Intervention: Overlay contention recovery

**Beads:** etj2.3.4, etj2.3.5

**Observable signal:**
- Inferred from `cast_result_tier` timing (player tried to cast while minigame active → overlay blocked)
- "Finish the minigame first" toast frequency (conflict signal: not tracked directly, but can infer from timing)

**Baseline:** Not currently measurable.

**Target direction:** Reduce overlay conflicts (players understand the overlay is busy and don't retry).

**Guardrail metric:** Don't break overlay initiation gating (server authority remains intact).

**Post-change review window:** 7 days after closed-test launch.

**Product decision this informs:** If conflicts don't decrease, recovery copy isn't clear (players don't understand the overlay is busy).

---

## WS-D: Content and Accessibility Governance

### Intervention: Copy standards (§15)

**Beads:** etj2.4.1, etj2.4.2

**Observable signal:**
- Inferred from user behavior: repeated taps on same control (frustration signal)
- No direct event tracks copy comprehension

**Baseline:** Not currently measurable.

**Target direction:** Reduce repeated taps on same control (players understand the copy and don't retry).

**Guardrail metric:** Don't decrease any core loop volume (clarity shouldn't block actions).

**Post-change review window:** 14 days after closed-test launch. Qualitative: monitor support tickets / negative feedback for copy confusion.

**Product decision this informs:** If repeated taps don't decrease, copy isn't clear (players don't understand the message).

---

### Intervention: Contrast matrix

**Beads:** etj2.4.3, etj2.4.4, etj2.4.5

**Observable signal:**
- No direct event tracks visual comprehension
- Inferred from qualitative feedback (support tickets, negative reviews)

**Baseline:** Not currently measurable.

**Target direction:** Reduce support tickets / negative feedback about visual clarity.

**Guardrail metric:** Don't change visual hierarchy (accessibility shouldn't break brand).

**Post-change review window:** 14 days after closed-test launch. Qualitative only.

**Product decision this informs:** If support tickets spike, contrast isn't sufficient (players can't read the UI).

---

## Gaps and Future Instrumentation

**Gap 1: Repeated action signals**  
We don't track "player tapped the same control N times in M seconds." This would help validate WS-B (state clarity) and WS-D (copy clarity).  
**Decision:** Do not add new event yet. Infer from repeated `upgrade_shop_opened` without `upgrade_purchased`. If post-change data shows we need more granularity, file a follow-up bead.

**Gap 2: Minigame abandonment**  
We don't track "player started raid minigame but never submitted." This would help validate WS-C (raid coaching).  
**Decision:** Do not add new event yet. Infer from `raid_attempted` without `raid_succeeded`/`raid_defended`. If post-change data shows we need more granularity, file a follow-up bead.

**Gap 3: Timeout reasons**  
`fish_catch_failed` doesn't have a reason field (timeout vs zone-leave vs chance-miss). This would help validate WS-C (fishing recovery copy).  
**Decision:** Do not add new field yet. If post-change data shows we need more granularity, file a follow-up bead.

**Gap 4: STORE ALL retries**  
We don't track "player tried STORE ALL at full capacity." This would help validate WS-B (consequence preview).  
**Decision:** Do not add new event yet. Infer from `fish_sold` with low count followed by another `fish_sold` attempt. If post-change data shows we need more granularity, file a follow-up bead.

---

## Summary

**Total interventions mapped:** 11  
**Existing events sufficient:** 11 (no new events proposed)  
**Baseline status:** All "not currently measurable" (no live closed-test data yet)  
**Post-change review windows:** 7 days (coaching, recovery), 14 days (state clarity, copy, contrast)

**Next steps:**
1. Land EPIC 45 implementation (all workstreams complete)
2. Launch closed test
3. Establish baseline from first 7 days of data
4. Compare against targets at 7-day and 14-day review windows
5. If gaps remain, file follow-up instrumentation beads

**Privacy note:** All events are aggregate gameplay telemetry. No invasive recording. No PII beyond `player_user_id` (required for funnel analysis). Event volume is low (~20 events/min/player).
