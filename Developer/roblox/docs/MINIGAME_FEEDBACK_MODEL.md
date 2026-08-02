# Minigame Feedback Model — Skill Tier vs Authoritative Outcome

**Bead:** harborheist-ux45-workflow-clarity-etj2.3.1 (EPIC 45, WS-C)
**Status:** Approved design model (design bead — no code changed here;
implementation is harborheist-ux45-workflow-clarity-etj2.3.2)
**Date:** 2026-08-02
**Author:** GoldenEagle-Aug2
**Copy conformance:** all strings follow docs/DESIGN_SYSTEM.md §15.

Defines how fishing and raid minigames communicate timing skill separately from
the server-authoritative outcome, so players learn from timing without ever
being lied to about who decides results.

---

## 1. Principles

1. **Input acknowledgment is not a result.** The tap flash (`minigameTapAck`,
   `init.client.lua:522`) means "input received" — nothing more. It never
   colors green/red, never previews hit/miss, never implies a tier.
2. **The client never claims a tier.** The client reports a raw marker
   position; the server re-derives the tier from its own stored bounds
   (`RaidService.lua:836-870`, `FishingService.lua:288-335`). No UI element may
   label a tier before the server responds.
3. **Chance is honest.** When a clean timing input still fails on the server's
   probability roll, the copy says so — distinctly from a timing failure. A
   perfect-timing failure must never look like a bug, and never have looked
   like a guaranteed success beforehand.
4. **Every failure teaches one next step.** Outcome + next action
   (§15.3 grammar), one recovery action only.
5. **Never reveal the roll early.** No odds, no "almost won" framing before the
   server response; no defender information beyond existing product rules.

## 2. The four feedback moments

| Moment | Name | Channel | Authoritative? | Latency |
| --- | --- | --- | --- | --- |
| M1 | Input acknowledgment | Neutral white tap flash + haptic tick (existing) | No — "received" only | Instant |
| M2 | Server-confirmed timing tier | Toast/label naming the tier the SERVER derived | Yes (server-derived) | One round trip |
| M3 | Final outcome + reason | Result toast / reveal card | Yes | Same response as M2 |
| M4 | Recovery action | Tail of the M3 message (one action) | — | — |

M2 and M3 arrive in the same server response for raids (tier + reason in one
result table) and may compose into a single message; they must still read as
two facts ("your timing was X" AND "the outcome is Y because Z"), not one
blurred verdict.

## 3. Current-state evidence (as of commit b14740a)

### 3.1 Fishing (`SubmitCatchInput`, `FishingService.lua:404-548`)

| Server outcome | Current copy | Problem |
| --- | --- | --- |
| Cast tier (perfect/good) | "PERFECT CAST! +Luck on this catch." / "Good cast. +Luck on this catch." | Conforms — already tiered |
| Cast tier (none) | "No timing bonus — tap the bar next cast!" | Conforms (positive coaching) |
| `too_slow` (bite window) | "Too slow! The fish got away..." | Scolding `!`, trailing `...`, no next action |
| `missed` (hit=false) | "The fish slipped away..." | Trailing `...`, no next action |
| `missed_reroll` (clean hit, chance failed) | **"The fish slipped away..."** — identical to `missed` | **Player cannot distinguish a timing miss from a chance miss.** Analytics separates them (`missed` vs `missed_reroll`); copy does not. This is the core "game feels inconsistent" bug |
| Success | Reveal card + "You caught X" | Conforms |

### 3.2 Raid (`SubmitRaidResult`, `RaidService.lua:826-935`; client `:5683-5691`)

| Server outcome | Current copy | Problem |
| --- | --- | --- |
| `too_fast` (timing forgery) | "Too fast! Play the minigame fairly." | Accusatory (§15.8 violation) |
| `too_slow` | "Too slow! The raid window of opportunity passed..." | Scolding, trailing `...` |
| `target_unavailable` / `target_no_longer_eligible` / `loss_capped` | Client shows generic "Heist failed — the fish slipped away." | **Lies about the cause** — implies chance miss when the target state changed; teaches the wrong lesson |
| `missed` (chance roll failed) | Server toast "Heist failed! The fish slipped away..." **plus** client toast "Heist failed — the fish slipped away." | **Double notification, divergent duplicates** |
| Success | "Heist perfect! Stole a Rare X worth $180." | Conforms — already tier-aware |

The server already returns `tier` and `reason` to the client for every failure
(`failOutcome`, `RaidService.lua:909`) — the client just doesn't render them.

## 4. Message matrices (approved copy)

### 4.1 Fishing bite minigame

Tier context for bites comes from the cast (M2 already delivered at cast time).
Bite outcomes:

| Situation | M3 message | M4 recovery |
| --- | --- | --- |
| Timeout (`too_slow`) | "Too slow — the fish got away." | "Watch for the splash, then tap fast." |
| Timing miss (`missed`, hit=false) | "The fish slipped away." | "Tap when the marker is inside the zone." |
| Chance miss (`missed_reroll`, clean hit) | "Clean hook — the fish shook free. Timing was right; the fight is chance." | "Same timing next cast." |
| Success | Reveal card (unchanged) | — |

The chance-miss message deliberately contains two facts: skill confirmed
("timing was right") + authority explained ("the fight is chance"). It does not
quote odds and does not apologize.

### 4.2 Raid minigame (tier × reason)

M2+M3 compose as "<tier phrase> — <outcome phrase>. <recovery>"

| Tier / reason | Message | Notes |
| --- | --- | --- |
| perfect + success | "Heist perfect! Stole a {Rarity} {Species} worth ${value}." | Existing — keep |
| good/ok + success | "Heist {tier}! Stole a {Rarity} {Species} worth ${value}." | Existing — keep |
| perfect + chance miss | "Perfect grab — the fish slipped free. Even perfect timing isn't a sure thing." | Skill confirmed, chance honest, no odds quoted |
| good + chance miss | "Good grab — the fish slipped free. Cleaner timing raises your odds." | Teaches the tier ladder |
| ok + chance miss | "Weak grab — the fish slipped free. Aim for the center band." | Teaches the tier ladder |
| any + `target_unavailable` | "Your target left the harbor. Pick another aquarium." | Truthful cause + action |
| any + `target_no_longer_eligible` | "That aquarium locked down mid-heist. Pick another target." | Truthful cause + action |
| any + `loss_capped` | "That aquarium has lost enough this window — it's protected now. Pick another target." | Product-rule protection, no defender detail |
| any + `no_stealable_fish` | "That aquarium has no stealable fish left. Pick another target." | From resolveRaidSuccess — target-state class |
| any + `fish_gone` | "The target changed mid-heist. Pick another aquarium." | From resolveRaidSuccess — target-state class |
| any + `too_slow` | "The raid window closed. The next one opens soon." | Calm recovery (§15.7) |
| any + `too_fast` (anti-forgery) | "That attempt didn't count — the marker hadn't reached that position." | §15.8 firm, describes enforcement not character |
| `bad_input` / silent rejects | No player message (unchanged) | Unreachable by legitimate clients |

**Defender side:** unchanged ("%s tried to raid your aquarium and failed!") —
no new defender information is exposed.

**De-duplication rule (implementation requirement for etj2.3.2):** exactly one
attacker-facing message per resolved raid. The server stops sending
`remotes.notify` for the `missed` path (`RaidService.lua:927`) and the client
renders M2+M3 from `result.tier`/`result.reason` — the result table is the
single channel. Timeout (`too_slow`) is the one exception: it can be detected
client-side for instant feedback and the server message is the backstop; the
client must not show both.

## 5. Audio / haptic / visual roles

Defined here at the role level so etj2.3.2 doesn't re-derive them; all motion
work itself belongs to EPIC 44 systems (AnimationSystem/Gradients) and is NOT
duplicated by this model.

| Channel | M1 (ack) | M2 (tier) | M3 (outcome) |
| --- | --- | --- | --- |
| Visual | Neutral white flash (existing) | Tier word in toast text; tier chip color (perfect=`brand.quest` gold, good=`accent.base`, ok=`text.secondary`) | Toast color: success=good, chance-miss=warn, state/block=warn, security=bad |
| Audio | Existing tick (mobile haptic) | None (avoid stacking stingers on M3) | Existing category stingers: success=raid-attacker success path, failure=existing error stinger |
| Haptic | `hapticPressEnd()` tick (existing) | None | Success: UINotification-class pulse; failure: none (no punishment buzzing) |

## 6. Accessibility

- Tier and outcome are always conveyed by TEXT (the words "Perfect", "Good",
  "Weak", and the reason phrase), never by color alone.
- The tier chip (if implemented visually) must pair an icon SHAPE with its
  color: perfect=star, good=circle, ok=triangle — readable under colorblindness
  and grayscale.
- Toasts already meet contrast via Contrast.spec; any new tier-chip
  color/surface pair must add a Contrast.spec case before shipping.

## 7. Security / trust constraints (binding on etj2.3.2)

1. The client must render tier ONLY from the server's response — never from
   local marker math shown before the round trip.
2. No copy may quote success probabilities, even though `GameConfig.Raid.
   minigame.successChance` is client-readable. "Chance is real" yes; "85%" no
   (product decision — preserves tension, avoids odds-lawyering).
3. Target-state messages must not reveal WHY a target is ineligible beyond the
   product-rule surface ("locked down", "left", "protected") — no lock timers,
   no alarm status, no fish counts.
4. The `too_fast` path stays a silent security signal server-side (already
   logged via AntiExploit); the player message stays mechanical.

## 8. Studio test cases (for etj2.3.2 implementation)

1. Force each raid tier (perfect/good/ok) × each reason via the E2E mock store;
   assert EXACTLY ONE attacker toast per resolution and the §4.2 string.
2. Assert no tier label renders before the server response (tap, screenshot
   mid-flight).
3. Assert the `missed` path no longer double-notifies (count toasts = 1).
4. Fishing: force `missed` vs `missed_reroll` via mock rng; assert distinct
   §4.1 strings.
5. Defender receives the existing defended message; attacker receives no
   defender internals (lock time remaining, etc.).
6. Grayscale screenshot pass: tier distinguishable by text/shape alone.

## 9. Analytics hypotheses (validate post-launch)

1. Distinct `missed_reroll` copy reduces session-abandon within 30s of a
   perfect-tier chance miss (vs the `missed` baseline) — the "game feels
   rigged" quit.
2. Tier-ladder coaching on good/ok chance misses increases subsequent-perfect
   rate over the next 5 raid attempts.
3. Truthful target-state messages reduce immediate re-attempts against
   ineligible targets (wasted taps) by making the block legible.
4. The calmer fishing timeout copy reduces repeated instant re-casts that
   spam `submit_catch` rate limits.
