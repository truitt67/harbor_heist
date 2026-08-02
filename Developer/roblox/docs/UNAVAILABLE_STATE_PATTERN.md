# Unavailable-State Content Pattern (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.2.1
**Status:** APPROVED pattern — binding on etj2.2.2 (shop prerequisites) and all
future blocked/unavailable states. Surfaced in DESIGN_SYSTEM.md §16.
**Evidence as of:** commit `cf52d4f` (line numbers drift; search quoted strings)

---

## 1. The grammar

Every unavailable state carries up to three facts, in a fixed slot order:

> **STATE** — *reason* — *recovery*

- **STATE** names what the control is right now. It lives ON the control
  (or its badge), ≤ 14 characters, ALL CAPS per §15.2 chip convention.
- **Reason** says why, once. It lives in adjacent helper text, never on the
  control, never hover-only.
- **Recovery** is the one next step (§15.3). It tails the reason when the
  next step is not self-evident from the control the player just used.

Slot assignment by surface:

| Surface | STATE slot | Reason slot | Recovery slot |
| --- | --- | --- | --- |
| Tiny button / chip (≤ 14 chars) | On the control | Adjacent helper text (always visible) | Tail of the helper, or omitted if self-evident |
| List row | Trailing label/chip | Row subtitle (the existing subText slot) | Tail of the subtitle |
| Panel-wide block | Panel empty-state header | Empty-state body | Body's final sentence |
| Transient failure (a tap that failed) | — | Toast | Toast (§15.7 `"Couldn't X — try again."`) |
| System-wide degradation | Banner header (≤ 40 chars) | Banner body (≤ 120) | Banner body |

Rules that apply everywhere:

1. **Never invent a second reason vocabulary.** Reasons are dictionary
   labels from a single map (the raid-target `reasonLabel` pattern), so they
   stay translatable and consistent.
2. **Never color alone.** Semantic status colors are preserved, but every
   state also carries text (or an icon chip). Color is reinforcement, not
   the signal.
3. **If the block is timed, name the time** (§15.7): `LOCKED 45s`,
   `RECHARGE 30s`. Durations follow §15.5 (`45s`, `2m`, never `1m 30s`).
4. **Unknown duration = name the condition, not a fake number.** If the
   server sent no countdown, show the bare reason (`Protected`), never a
   guessed or frozen timer.
5. **One state per control.** If two conditions apply, show the one that
   resolves LAST (a locked AND recharging control shows the recharge).

## 2. State taxonomy

The six canonical states and their treatments:

| State | Primary label | Reason (helper) | Recovery | Color / icon | Focus behavior |
| --- | --- | --- | --- | --- | --- |
| **Disabled** (generic, no specific cause) | Existing label, tertiary text | Usually none needed — only add helper if the cause is non-obvious | — | `surface.elevated` bg + `text.tertiary` (setButtonEnabled) | Stays in focus ring; activation no-ops silently |
| **Locked by prerequisite** | `LOCKED` | Names the prerequisite: `"Requires Steel Rod"` | Implied by the named prerequisite; add `"Buy it first."` only if the path is ambiguous | `surface.secondary` bg + `text.tertiary` | Stays in focus ring; helper must be always-visible |
| **Cooldown** | `RECHARGE 30s` (live) | None on control; row subtitle may add context | The countdown IS the recovery | `surface.elevated` + `text.tertiary` | Stays in focus ring; no tap-to-explain needed (time explains itself) |
| **Maxed** | `MAXED` badge (no button) | Top-tier name in the row | None — maxed is an achievement, not a block | `status.good` text | Not focusable (no control exists) |
| **Unhealthy / degraded** (system-level) | Banner header, e.g. `"Saving interrupted — retrying"` | Banner body states what still works | Body states the player's one move (`"Stay in game to keep recent progress."`) | `status.warn` — never error red; nothing is broken, actions still count | N/A (banner is not a control). Per docs/DATASTORE_DEGRADED_CONTRACT.md §3.2 |
| **Temporarily unavailable** (transient) | Control returns to ready state | Toast names what didn't happen | `"Couldn't X — try again."` | Toast category color | Control never gets STUCK disabled by a transient failure |

The deliberate exception — **"not yet" is not disabled** (harborheist-cl05):
an unaffordable-but-purchasable shop row stays TAPPABLE (`surface.secondary`
bg + `status.warn` price), because the tap itself explains the shortfall.
A control may only be made inactive when tapping it could never teach
anything (OWNED, LOCKED, RECHARGE).

OWNED vs MAXED: `OWNED` = you hold this tier (row-level, button inert);
`MAXED` = the whole track is complete (track collapses to one summary row,
badge in `status.good`). Maxed never reads as a failure state.

## 3. Countdowns and stale state

1. **1Hz local tick, server-authoritative truth.** Countdown text updates
   once per second locally (the raid-target `raidTargetCountdownLabels`
   pattern), but the underlying availability flips ONLY on a server state
   push.
2. **Zero is not available.** When a local countdown reaches 0, swap the
   label to the bare reason (`Protected • 4m` → `Protected`) and keep the
   control unavailable until the server confirms. Never self-enable on a
   client-side timer.
3. **Re-assert visuals on class change only.** A state CLASS transition
   (ready → locked → recharging) re-asserts colors/Active; the 1Hz text tick
   must not restart tweens or re-run layout (the lock-button `lockClass`
   pattern).
4. **Stale = neutral, not wrong.** If a state push makes a displayed reason
   stale, render() rewrites it on the next frame; no control may keep a
   countdown running past a state change that invalidated it.

## 4. Focus and input modalities

- KeyboardNav keeps disabled buttons in the focus ring (registration is
  explicit; `ActivateFocused` no-ops on `Active == false`). This is the
  correct behavior — a focused-but-disabled control is discoverable — so the
  reason MUST NOT depend on activation or hover.
- **Touch has no hover; gamepad has no tooltips.** Any reason that exists
  only in a hover tooltip fails mobile and controller. Tooltips may RESTATE
  a reason on desktop, never carry it alone.
- Screen-reader / focus order: the helper text belongs to the same row
  container as the control so focus lands on a coherent unit.

## 5. Worked examples

**Desktop shop row, prerequisite-locked (target state for etj2.2.2):**

```
Steel Rod II                         $400
Upgrades your cast distance.         LOCKED
Requires Steel Rod I.
```
Today the LOCKED row's subtitle shows the item description, not the
prerequisite — that deviation is what etj2.2.2 fixes.

**Mobile raid-target row, cooling down (conformant today):**

```
Clayton's Dock                       Protected • 4m
```
At 0s the subtitle becomes `Protected` (bare) until the server push confirms
the target is raidable again.

**Aquarium lock button, full cycle (conformant today):**

```
LOCK 60s  →  LOCKED 45s (tappable: early unlock)  →  RECHARGE 30s (inert)  →  LOCK 60s
```

**DataStore-degraded banner (conformant today, etj2.2.6):**

```
● Saving interrupted — retrying
  Everything you earn counts and saves automatically when connection
  recovers. Stay in game to keep recent progress.
```

**Transient failure (conformant today, §15.7):**

```
Couldn't sell that fish — try again.        [toast, control back to ready]
```

## 6. Conformance inventory (evidence)

| Site | State | Status |
| --- | --- | --- |
| `setButtonEnabled` (init.client.lua) | Generic disabled | Conformant — color-swap pattern, no fake opacity |
| Shop `OWNED` rows | Owned tier | Conformant |
| Shop unaffordable row | "Not yet" exception | Conformant (cl05) |
| Shop `LOCKED` row | Prerequisite | **Deviation** — subtitle shows description, not the prerequisite → etj2.2.2 |
| Shop `MAXED` summary | Maxed | Conformant |
| Raid-target reason labels + 1Hz countdowns | Cooldown / locked / protected | Conformant — the model implementation |
| Aquarium lock `LOCKED %ds` / `RECHARGE %ds` | Active window / cooldown | Conformant |
| DataStore-degraded banner | Unhealthy/degraded | Conformant (etj2.2.6 + contract §3.2) |

---

*Dependent work: etj2.2.2 (shop prerequisite explanations) implements the one
deviation above. Any new blocked state must name its taxonomy row before
shipping.*
