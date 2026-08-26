# Raid System — Two-Player Manual Verification Runbook (TASK 19.8.2)

Manual companion to the automated 19.8.1 E2E coverage (now
`tests/e2e/scenarios/Raid.lua`; formerly the retired `runner.server.lua`
block with 36 assertions). The scenarios prove the server logic end-to-end
with fake players;
this runbook verifies the parts fakes cannot: real client UI, real remotes,
notifications, stun WalkSpeed gating, and the raid minigame feel.

Prereq: Studio signed in (run-in-roblox prerequisite applies to any scripted
step). All commands below run in Studio's **Command Bar** (View → Command Bar)
with the context set to **Server** unless noted.

## 0. Setup

1. Open the built place (`HarborHeist.rbxlx`) or the Rojo-synced project.
2. Test tab → Clients and Servers → **2 Players, 1 Server** → Start.
   Studio spawns a server + two clients (Player1 = attacker, Player2 = victim).
3. Give both players cash for shop purchases (server command bar, once per
   player name):
   ```lua
   local DM = require(game.ServerScriptService.HarborHeist.DataManager)
   local p = game.Players:FindFirstChild("Player1")
   DM.get(p).profile.Coins = 5000
   ```

## 1. Progression gates (new-player protection)

Raid eligibility requires `GameConfig.Raid.unlockTotalCatches` (10) catches OR
any aquarium upgrade. Fast path:

- Both players: buy **Capacity I** ($300) at the shop (docks panel → Upgrades).
- Verify (server):
  ```lua
  local AS = require(game.ServerScriptService.HarborHeist.AquariumService)
  local DM = require(game.ServerScriptService.HarborHeist.DataManager)
  print(AS.isNewPlayerProtected(DM.get(game.Players.Player1))) -- expect false
  print(AS.isNewPlayerProtected(DM.get(game.Players.Player2))) -- expect false
  ```

## 2. Stock the victim + opt both players in

1. Player2 (victim): catch 2–3 fish (any non-Legendary), then **Store** them
   in the aquarium (sell flow → Store, or the aquarium panel).
2. Player2: open the aquarium panel → enable the **RAID opt-in toggle**
   (persists `profile.Aquarium.RaidOptIn`). Verify (server):
   ```lua
   print(DM.get(game.Players.Player2).profile.Aquarium.RaidOptIn) -- true
   ```
3. Player1 (attacker): same toggle — OR walk onto the **Raid Waters pier**
   (live zone opt-in; revokes on leave).

## 3. Open a raid window

Real windows roll every 20–30 min and last 5 min. For verification, force one:

```lua
require(game.ServerScriptService.HarborHeist.RaidService)._setWindowOpen(true, 600)
```

PASS: both clients get the window-open state push (raid UI shows a countdown).

## 4. Target selection (attacker UI)

Player1: open the raid UI.

PASS criteria:
- Player2 listed **available** with the correct stealable-fish count.
- Any non-participant (neither opted in nor on the pier) is NOT listed.
- Cross-check server truth:
  ```lua
  local RS = require(game.ServerScriptService.HarborHeist.RaidService)
  local t = RS.getRaidTargets(game.Players.Player1)
  print(t.canRaid, #t.targets, t.targets[1] and t.targets[1].stealableCount)
  ```

## 5. The raid (happy path)

Player1: select Player2 → start raid → play the timing minigame (stop the
marker in the perfect/good zone).

PASS criteria:
- Success: attacker sees "Heist success"; the stolen fish appears in
  Player1's aquarium (or is fenced for cash if full); Player2 gets the
  "RAID! ... stole your ..." notification naming the fish and value.
- Server truth:
  ```lua
  print(#DM.get(game.Players.Player1).profile.Aquarium.StoredFish) -- +1
  print(#DM.get(game.Players.Player2).profile.Aquarium.StoredFish) -- -1
  print(DM.get(game.Players.Player2).profile.Aquarium.RaidProtectionUntilTimestamp > os.time()) -- true (20 min immunity)
  ```
- Miss (roll failed): attacker sees "Heist failed"; no fish moves; victim
  gets the "tried to raid ... and failed" notification.

## 6. Counterplay + cooldown matrix (each should reject in the UI)

| # | Setup | Expected |
|---|-------|----------|
| 1 | Player1 raids again immediately | Rejected: attacker cooldown (6 min) with remaining seconds shown |
| 2 | Clear attacker cd (`DM.get(p1).raidAttackLastAt = nil`), raid Player2 again | Rejected: per-victim cooldown (30 min) |
| 3 | Player2 locks aquarium (dock panel → Lock), Player1 re-targets | Player2 greyed: "locked"; attempt rejected |
| 4 | Player2 stands in the Safe Harbor plaza | Greyed: "safe_harbor"; attempt rejected |
| 5 | Player2 loses 2 fish in one window | Greyed: "loss_capped" until next window |
| 6 | Window closes mid-minigame (force `_setWindowOpen(false)` after the attempt starts) | Raid still resolves (committed-raid design) |

Between matrix rows, reset what you changed (unlock, leave plaza, clear
`raidTargetCooldowns`, reopen the window).

## 7. Alarm counterplay (optional, needs Alarm upgrade)

1. Player2: buy **Alarm I** ($800).
2. Player1 raids again. On success: Player1 is **stunned** (WalkSpeed gate —
   movement visibly slowed for the stun duration, then restored without
   needing another state push). Player2's notification notes the stun.

## 8. Cleanup

```lua
require(game.ServerScriptService.HarborHeist.RaidService)._setWindowOpen(false)
```

Stop the playtest. Forced windows and seeded cash do not persist beyond the
session (DataStore writes from Studio playtests go to the Studio sandbox; a
published place keeps them — wipe via `DataManager.remove`-equivalent if
needed).

## Notes / known scope

- Legendary fish are never stealable (`IsRaidProtected`); Epic fish have
  reduced steal weight. Stock a Legendary to confirm it is never taken.
- Rate limits (5 raid attempts/min) trip only on the real remote path — if
  the matrix rows run fast, expect and respect the cooldown notification.
- The E2E suite (19.8.1) covers every server-side gate above with fake
  players; this runbook exists to catch client/UI/notify regressions the
  fakes cannot see.
