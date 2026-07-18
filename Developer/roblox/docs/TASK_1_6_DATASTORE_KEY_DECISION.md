# TASK 1.6 — DataStore Key Version Bump (Decision Record)

**Status:** IMPLEMENTED (Option b)
**Bead:** harborheist-data-model-foundation-73i.6
**Date:** 2026-07-18 (Hermes-K3-c)

## Decision

**Option (b): new DataStore key `HarborHeist_PlayerData_v2` with one-time
copy+migrate from v1.** Chosen over Option (a) (same key, in-load migration
overwrite) for closed-test safety.

## Why

The structured profile (TASK 1.1, `PlayerProfile.CURRENT_VERSION = 2`) is a
**breaking format change** from v1's flat fields (`cash`, `rodLevel`,
`baitLevel`, `capacityLevel`, `liveWell`). Migrating in place on the same key
(Option a) means a buggy migration permanently corrupts the ONLY copy of a
player's data — unacceptable for real players in a closed test.

Option (b) gives us:
1. **Rollback anchor.** v1 data is left intact during the grace period. If the
   v2 migration misbehaves, we revert `STORE_NAME_V2` back to the v1 name and
   players are restored exactly as they were.
2. **No irreversible write.** v1 is read-only during migration; nothing is
   deleted until the migration is proven stable.

## Implementation

- `DataManager.lua` now holds two store references:
  - `dataStore` → `HarborHeist_PlayerData_v2` (authoritative; all reads/writes)
  - `dataStoreV1` → `HarborHeist_PlayerData_v1` (read-only migration source)
- `DataManager.load(player)`:
  1. Reads v2 first. If present, done (normal path).
  2. If v2 is empty, reads v1. `sanitize()` (TASK 1.3) converts the flat v1
     format to the structured v2 profile.
  3. Sets `needsMigrationSave = true` and, at end of load, `task.defer`s an
     immediate `DataManager.save(player)` so the migrated profile is written
     to v2 right away (next load hits v2 directly).
- `DataManager.save` writes to v2 via `UpdateAsync` (unchanged code path —
  `dataStore` now points at v2).

## Migration Guarantees

- **Idempotent:** re-running load on a migrated player reads v2 (non-empty) and
  skips the v1 fallback entirely.
- **Non-destructive:** v1 data is never modified or deleted by this task.
- **Failure-safe:** if the v1 read fails, `saved` stays nil and the player gets
  a fresh `PlayerProfile.default()` — same as a brand-new player. No crash.

## Rollback Path (if migration fails)

1. In `DataManager.lua`, change `STORE_NAME_V2` back to
   `"HarborHeist_PlayerData_v1"` and remove/disable the v1 fallback block.
2. Redeploy. All players load their original v1 data.
3. Investigate the migration bug; fix; re-attempt with a fresh v2 key name
   (e.g. `_v3`) to avoid half-migrated v2 rows.

## Follow-up (NOT in this task)

- **Delete v1 data** after the closed test confirms migration stability
  (recommend: file a new bead for post-test cleanup, with explicit approval
  per the no-deletions rule). Until then, v1 rows remain as rollback anchors.
- DEC-1 (passive income scope) may add fields the v2 key must store — the
  sanitize() defaults handle absent fields, so this is forward-compatible.

## Acceptance Criteria

- [x] Decision: new key with copy (this document)
- [x] v1->v2 copy+migrate path implemented (load fallback + deferred save)
- [x] DataStore key updated in DataManager (STORE_NAME_V2)
- [x] Rollback path documented (above)
