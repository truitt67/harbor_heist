# STORE ALL Consequence Preview & Partial-Capacity Behavior (EPIC 45)

**Bead:** harborheist-ux45-workflow-clarity-etj2.2.3
**Status:** APPROVED design — implementation target for etj2.2.4
**Evidence as of:** commit `2dff899` (line numbers drift; search quoted strings)
**Governing patterns:** docs/UNAVAILABLE_STATE_PATTERN.md, DESIGN_SYSTEM.md §15/§16

---

## 1. Current-state evidence

| Fact | Where | Consequence |
| --- | --- | --- |
| STORE ALL fires `RequestStoreFish:InvokeServer()` and **ignores the result** | `invStoreAllBtn` (`init.client.lua` — search `"STORE ALL"`) | No debounce: a double-tap during latency fires a second invoke that finds an empty bag and earns the confusing `"You have no fish to store. Go fish!"` toast |
| Server moves `min(carried, capacity − stored)` and returns `{ ok = stored > 0, stored = stored }` | `AquariumService.handleStoreFish` | Partial moves are silent in the result channel the client actually has |
| Server toast on ANY success: `"Stored %d fish. They now earn you cash every second!"` | same | **Partial store lies by omission**: 5 carried / 2 slots → "Stored 2 fish…" with no mention of the 3 left behind |
| Server toast on zero-fit: `"Your aquarium is full! Sell some fish."` | same | Deviates from §15.9 converged form (`"…Sell some fish first."`) — etj2.4.2 territory |
| Snapshot already carries `storedFish` (full array) + `capacity` | `StateSync.lua` | The client can compute an **exact** advisory preview — no new server data needed |
| Button is disabled only when the bag is empty (R3 audit #9) | `renderInventory` | No capacity-awareness at the decision point |

## 2. Design decisions

### D1 — One-tap all-fit path is sacred (AC1, AC3)

When every carried fish fits, NOTHING changes: `STORE ALL`, one tap, no
confirmation, no helper text. STORE ALL is a frequent, fully reversible,
zero-loss core-loop action (stored fish can be sold any time; nothing is
destroyed). A modal here is a confirmation tax on the game's tightest loop
and is **rejected by default**. Revisit only with Studio usability evidence
that the inline preview is misunderstood (§6).

### D2 — Progressive disclosure at the decision point (AC2)

The bulk button's label and a helper line carry the preview, computed from
the latest snapshot (`fits = max(0, capacity − #storedFish)`,
`movable = min(#carriedFish, fits)`):

| State | Button label | Helper (directly above the button, shown only in this row's state) |
| --- | --- | --- |
| All fit (`movable == #carried`, > 0) | `STORE ALL` | — (hidden) |
| Partial (`0 < movable < #carried`) | `STORE 2 OF 5` | `"Only 2 fit — 3 stay in your bag."` |
| None fit (`movable == 0`, carried > 0) | `TANK FULL` (inactive) | `"Sell stored fish to free space."` |
| Empty bag (carried == 0) | `STORE ALL` (inactive, existing R3 #9 behavior) | — (hidden) |

Label ≤ 14 chars in every state (`STORE 2 OF 5` = 12, `TANK FULL` = 9) —
mobile chip limit (§15.6). Helper is one sentence, outcome + next action
(§15.3), digits always (§15.5). The helper is **progressive disclosure**: it
exists only when the result would surprise. Per the unavailable-state
pattern §1, the reason lives in always-visible adjacent text — the inactive
`TANK FULL` button never has to explain itself by tap.

### D3 — The server result toast is the reconciliation channel (AC4, DATA/TRUST)

The client NEVER mutates inventory optimistically and never toasts its own
reconciliation. etj2.2.4 updates the two server messages so the authoritative
channel tells the whole truth:

- Partial: `"Stored 2 fish — 3 didn't fit. Sell stored fish to free space."`
- Full: `"Your aquarium is full! Sell some fish first."` (§15.9 converged form)

This satisfies the feedback model's single-channel rule: preview (advisory,
button surface) → action → authoritative outcome (server toast). The advisory
preview and the server truth can diverge by one round-trip (a raid freed or
a sell filled slots between render and tap) — the server message is always
the truth, and the next state push re-renders the button.

### D4 — Debounce the bulk invoke (AC4)

etj2.2.4 wraps `invStoreAllBtn` in the existing `debouncedAction` pattern
(`setButtonEnabled(false)` around a `pcall`'d invoke, re-enable after).
This kills the double-tap → empty-bag → `"Go fish!"` confusion chain and
gives the "tap registered" feedback R3 audit #8 established for per-fish
rows. The pcall guard matters: a network drop must not leave the button
dead (the fresh-eyes fix on the per-fish path).

### D5 — Stale-state rules (AC4)

1. The preview recomputes on every `renderInventory` (signature-gated, so it
   tracks every state push).
2. An advisory label is NEVER a gate: `STORE ALL` / `STORE 2 OF 5` always
   fire the invoke; only empty-bag and TANK FULL render inactive, and both
   re-evaluate on the next push.
3. If the server moves fewer than previewed, the D3 toast explains; the bag
   re-renders from the pushed snapshot. No client-side arithmetic ever
   decides what moved.

### D6 — Input modalities (AC5)

- **Touch**: same one-tap; no hover dependency anywhere in the design.
- **Keyboard/gamepad**: `invStoreAllBtn` is already KeyboardNav-registered;
  label changes don't affect registration. An inactive `TANK FULL` stays in
  the focus ring (pattern §4) with the helper visible in the same panel.
- **Mobile**: 46px button height (existing), label ≤ 14 chars, helper one
  line at xs size above the button inside the existing panel width.

## 3. What this design explicitly does NOT do

- No modal/dialog on any path (D1).
- No optimistic inventory mutation (D3).
- No capacity rebalance, no per-fish drag/drop, no SELL ALL in the bag
  (existing product decision — bulk sell lives in the aquarium panel).
- No change to the all-fit experience whatsoever.

## 4. Implementation notes for etj2.2.4

- Client: compute `fits`/`movable` in `renderInventory` (the snapshot fields
  `state.storedFish` / `state.capacity` / `state.carried` are all present);
  set `invStoreAllBtn.Text` + helper visibility per D2; wrap the handler per
  D4. Add ONE small helper label instance created next to `invStoreAllBtn`.
- Server: two `remotes.notify` copy changes in `handleStoreFish` per D3 —
  partial branch needs `stored` and `#session.carried` (remaining, already
  in scope after the move loop).
- Contract pins (pure-spec pattern): the three label forms, helper strings,
  server partial-copy with `didn't fit`, debounce wrapper present, no
  optimistic `table.remove` on any client store path.
- Studio matrix: all-fit, partial, zero-fit, empty-bag, double-tap, raid-
  freed-slot race, desktop + mobile (recorded under etj2.5.2).

## 5. Reversal evidence

The inline preview graduates to a modal ONLY if closed-test observation
shows players repeatedly surprised by partial stores despite the label +
helper (e.g. support questions of the form "where did my fish go"). The
decision and its evidence bar are recorded here so a future session can
re-open D1 with data instead of taste.

---

*Binding on etj2.2.4. Copy changes require a §15 review; the modal question
requires the §5 evidence.*
