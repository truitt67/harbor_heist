# DataStore-Degraded Transaction Contract

**Bead:** harborheist-ux45-workflow-clarity-etj2.2.5 (EPIC 45, WS-B)
**Status:** Approved design contract (audit output — no code changed by this bead)
**Date:** 2026-08-02
**Author:** GoldenEagle-Aug2

This document defines what Harbor Heist actually guarantees when the DataStore is
unhealthy, what each economy/progression operation must do in degraded mode, and
the exact player-facing copy that truthfully describes it. Security and data
integrity outrank convenience; copy must never claim durability the code does not
provide.

---

## 1. How DataStore health actually works (proven from code)

All line numbers as of commit `2e9f8db` (main, 2026-08-02).

### 1.1 Health state machine

| Mechanism | Behavior | Evidence |
| --- | --- | --- |
| Failure tracking | Every failed save **or load** increments `consecutiveFailures`; at 3 consecutive failures `isDataStoreHealthy = false` | `src/server/DataManager.lua:31-35`, `recordFailure` at `:52-59` |
| Recovery (confirmed) | Any successful **write** resets the counter and flips healthy. Read successes do NOT reset (read health ≠ write health) | `recordSuccess` at `DataManager.lua:47-50`, comment at `:42-46` |
| Recovery (scheduled) | `tryRecover()` flips healthy after a 60s cooldown since last failure; the ONLY scheduled caller is the 60s autosave loop | `DataManager.lua:837-845`, `:787-790` |
| Saves while unhealthy | **Never blocked.** `save()` always attempts the write regardless of health; health is advisory-only | `DataManager.save` at `:633-765` (no health gate) |
| Client notification | `dataStoreHealthy` rides the state snapshot; the client shows a one-shot warning notification and disables ONLY the CLAIM button (client-side cosmetic) | `src/server/init.server.lua:102`; `src/client/init.client.lua:7055-7063`, `:7253-7267`, pulse guard at `:3411-3419` |
| Health-flip propagation | No proactive push on transition. Client learns of a flip on the next income-tick push (1s cadence, only when income > 0, `AquariumService.lua:557-586`) or next action push. A zero-income player may not learn of an outage until their next action | Gap — see §5, follow-up F3 |

### 1.2 Write path

Every profile write is a single `UpdateAsync` merge of the whole profile
(`DataManager.lua:694-729`) with exponential-backoff retries (`withRetries`,
`:437-453`):

- Transactional checkpoints (during play): 4 attempts, backoff `2^(n-1)*0.25 + jitter`.
- Leave/shutdown saves (`isShutdown=true`): 2 attempts (fast-fail inside the
  handler budget, `:692-729`); waits up to 15s for any in-flight save first
  (`:649-659`).
- Concurrent checkpoint calls coalesce via `saveDirty` into at most 2 sequential
  writes (`:755-764`).
- Rejoin races closed on both sides: `pendingSaveUserIds` load gate (TASK 14.27)
  and `activeSessionsByUserId` stale-save write guard (R1.1) — a stale leave-save
  can never clobber a fresher rejoin session (`:79-100`, `:696-705`).

**Atomicity consequence:** because every mutation lives in ONE profile document
written by ONE `UpdateAsync`, no operation can ever be half-persisted. A purchase
either fully persisted (cash debited + item owned) or fully did not. There is no
"money taken, item lost" state — this is the strongest durability guarantee the
code provides, and copy may lean on it.

### 1.3 The real loss window

In-memory session state is authoritative during play. Data is lost only when ALL
of these hold: the DataStore is failing, the player leaves (or the server shuts
down) before any write succeeds, and the leave save's 2 attempts also fail
(`init.server.lua:280-288`, `DataManager.lua:692-729`). Loss scope: **everything
since the last successful save** — not just purchases, not just coins. Carried
(unsold/unstored) fish, quest progress, and income accrual are included.

---

## 2. Per-operation degraded-mode matrix

Policies: **block** (refuse the action), **proceed** (apply in-memory now),
**queue** (defer until healthy), **retry** (automatic re-attempt),
**reject** (refuse permanently).

| # | Operation | Current behavior (evidence) | Checkpoint today | Approved degraded policy | Rationale |
| --- | --- | --- | --- | --- | --- |
| 1 | **Claim income** | Coins credited in-memory immediately; CLAIM button disabled client-side ONLY (server does not gate) — `init.client.lua:7253-7267`, `AquariumService.lua:118-126` | Yes (spawned, coalesced) | **Proceed + retry.** Remove the client-side-only CLAIM disable (it lies: server honors claim anyway, and claim is the same durability class as every other op) | In-session state is authoritative; single-document write makes the claim atomic; worst case is full rollback of recent progress, never partial |
| 2 | **Sell fish** (bulk + single) | In-memory payout immediate — `AquariumService.lua:203-215`, `FishInventoryService.lua:143-155` | Yes | **Proceed + retry** | Same atomicity argument |
| 3 | **Store fish** (bulk + single) | In-memory move carried→stored immediate — `AquariumService.lua:70-90`, `FishInventoryService.lua:232-244` | Yes | **Proceed + retry** | Same atomicity argument |
| 4 | **Shop purchase** | Cash debited + item granted in-memory immediate — `ShopService.lua:135-150` | Yes | **Proceed + retry.** Do NOT block purchases | Whole purchase is one profile write: it either fully persists or fully never happened. Player can never lose cash without the item. Blocking would punish players for an infra fault |
| 5 | **Quest reward grant** | Coins + completion flag in-memory only — `QuestService.lua:99-112` | **NO** at audit time — waited for autosave (≤60s), another action's checkpoint, or leave save. **FIXED by harborheist-sde2**: grant now spawns a coalesced checkpoint | **Proceed + retry** (checkpoint shipped) | Was the only economy path without a transactional checkpoint — same class of gap as the audit-log gap fixed in harborheist-gt44 |
| 6 | **Raid fish transfer** | Attacker + victim profiles mutated; BOTH checkpointed on success AND on failure — `RaidService.lua:790-802`, `:895-910` | Yes (both parties) | **Proceed + retry** | Both sides of the transfer checkpoint; no orphan-state window beyond the shared loss window |
| 7 | **Fish catch → carried** | Carried fish (max 5) held in session; no checkpoint until store/sell/autosave | No (by design) | **Proceed.** Accepted risk, explicitly disclosed as low-stakes | Worst case: loss of ≤5 unsaved carried fish; checkpointing every catch would hammer the DataStore budget for negligible value |
| 8 | **Autosave** | All sessions every 60s, spawned in parallel, snapshot-first — `DataManager.lua:783-807` | N/A (is the checkpoint) | **Retry.** Continues while unhealthy; each success self-heals the flag | Already correct |
| 9 | **Leave save** | 2 attempts, waits ≤15s for in-flight, then session removed — `init.server.lua:280-288`, `DataManager.lua:649-659`, `:767-777` | N/A | **Retry (2 attempts), then accept loss.** No requeue after `remove()` — a journal is out of scope for this contract (non-goal) | This is the irreducible loss window; copy must disclose it honestly |
| 10 | **Server shutdown (BindToClose)** | All players saved in parallel with pcall, 30s budget — `DataManager.lua:809-830` | N/A | **Retry (2 attempts each)** | Already correct |
| 11 | **Recovery semantics** | `tryRecover` after 60s cooldown; confirmed by next successful write; client told via next push + "Saving restored!" notification | N/A | **Retry + notify.** Add proactive push on health transitions (follow-up F3) so the banner appears/clears within ~1s for ALL players, not just those with income | Current passive propagation can leave the warning invisible or stale for idle players |

**Deliberately NOT adopted:** blocking all economy actions while degraded (punishes
players for infra faults, and in-session play is fully consistent), and a
write-ahead transaction journal (explicit non-goal of this bead).

---

## 3. Truthful player-facing copy

### 3.1 What the current copy gets wrong

Current string (`init.client.lua:7059`):

> "Saving unavailable -- try again. Your progress is safe but purchases may not persist."

| Claim | Verdict |
| --- | --- |
| "Your progress is safe" | **False.** Progress since the last successful save is lost if the player leaves before a write succeeds (§1.3) |
| "purchases may not persist" | **Misleading.** Purchases are exactly as durable as everything else — one atomic profile write; a purchase can never half-persist (§1.2). Singling out purchases implies other progress is safer, which is backwards |
| "try again" | **Vague.** Try WHAT again? The player took no failed action; retries are automatic |
| CLAIM-only disable | **Inconsistent.** Server honors claim anyway; every other economy action proceeds ungated. The disable implies claim is uniquely dangerous, which is false |

### 3.2 Approved replacement message

Degraded (shown as a persistent banner while `dataStoreHealthy == false`, not a
one-shot toast):

> **Saving interrupted — retrying automatically.**
> Everything you earn counts right now and saves itself when the connection
> recovers. Stay in game to make sure recent progress is kept.

Recovered:

> **Saving restored — you're all caught up.**

**As-implemented strings (etj2.2.6, fitted to the §15.6 length limits — the
43-char header exceeded the 40-char banner-header budget, so "automatically"
moved into the body):**

- Banner header: `Saving interrupted — retrying`
- Banner body: `Everything you earn counts and saves automatically when connection recovers. Stay in game to keep recent progress.`
- Recovery toast: `Saving restored — you're all caught up.`

Rules this copy follows (and future copy must keep):

1. Names the actual state (interrupted, retrying) — never "unavailable -- try again".
2. Promises only what §1 proves: in-session actions count; saves are automatic;
   recovery restores persistence.
3. Discloses the real risk honestly: leaving before recovery can lose recent
   progress — phrased as a constructive action ("stay in game"), not a threat.
4. Makes no distinction between purchases and other progress — there is none.
5. No action is disabled; nothing implies one economic action is riskier than
   another.

Anti-cheat/security messages are unaffected by this contract and remain distinct
and firm (per EPIC 45 WS-D governance).

---

## 4. Evidence from tests

- `test/pure_specs/StateSyncLogic.spec.lua:425-429` — `dataStoreHealthy` defaults
  `true` and passes through the snapshot builder.
- `tests/e2e/scenarios/Lifecycle.lua:140-147` — snapshot includes
  `dataStoreHealthy` as a boolean (Studio-gated suite; NOT verified on Linux).
- No pure-spec coverage exists for the health state machine itself
  (`recordFailure`/`recordSuccess`/`tryRecover`) — noted as a coverage gap;
  follow-up F1/F3 implementation beads should add pure-spec contracts where the
  logic is extractable.

## 5. Follow-up beads (created by this audit)

| ID | Bead | Pri | Class | Status | Summary |
| --- | --- | --- | --- | --- | --- |
| F1 | harborheist-sde2 | P2 | Integrity (code) | **DONE** (2026-08-02) | Transactional checkpoint on quest reward grant in `QuestService.lua` (spawned `dataManager.save(session.player)` gated on granted flags) + source-contract pure spec |
| F2 | harborheist-ux45-workflow-clarity-etj2.2.6 | P2 | Presentational (EPIC 45) | **DONE** (2026-08-02) | Persistent DataStoreBanner with §3.2 fitted copy; false toast removed; CLAIM-only disable + pulse-guard carve-out removed; recovery toast per §3.2 |
| F3 | harborheist-ux45-workflow-clarity-etj2.2.7 | P3 | Presentational (EPIC 45) | **DONE** (2026-08-03) | Proactive `stateSync` push on DataStore health transitions (`DataManager.onHealthChange` callback → snapshot push) so idle/zero-income players see banner appear and clear promptly |

F1 was scoped as integrity (server mutation durability), not copy. F2/F3 are
purely presentational and belong under EPIC 45 WS-B/WS-D. None of these block
launch; the pre-audit behavior was safe-but-mislabeled, not lossy beyond §1.3.
