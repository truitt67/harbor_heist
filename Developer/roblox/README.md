# Harbor Heist — Multiplayer Fishing & Live-Well PvP

A Roblox game where players fish at their personal dock, store fish in a live-well aquarium for passive income, sell fish for cash, buy rod/bait upgrades, and raid (or lock) other players' aquariums.

## How to Play It (Easiest Way — No Tools Needed)

1. Open **Roblox Studio**.
2. Go to **FILE → Open from File...** and pick `HarborHeist.rbxlx` from this folder.
3. Press **Play** (F5) to test solo, or use **Test → Clients and Servers → 2 Players → Start** to test the PvP raiding with two players.
4. To publish: **FILE → Publish to Roblox**.

That's it — the whole harbor (docks, aquariums, shop, water) is built automatically by the server script when the game starts.

### Enable Saving (for published games)
Player data (cash, gear, fish) saves via DataStores. This only works after you publish:
1. Publish the game (FILE → Publish to Roblox).
2. In Studio: **Home → Game Settings → Security → Enable Studio Access to API Services** (for testing saves in Studio).
In un-published Studio sessions the game still runs fine — it just skips saving.

## How to Play the Game

| Action | How |
|---|---|
| Fish | Stand in the glowing **Fishing Zone** at the end of your dock, press the **FISH** button or **F** |
| Store fish | Press **BAG** → **STORE** or **STORE ALL** — stored fish earn cash every second (rarer = more) |
| Sell fish | Open **AQUARIUM** panel → **SELL ALL** for instant cash |
| Upgrade gear | Walk to the **Bait & Tackle Shop** at the plaza center, press E, buy rods/bait (better luck = rarer fish) |
| Steal | During a **Raid Window** (announced in HUD), opt in via the aquarium panel, then target another player's aquarium — one fish max per window if you succeed |
| Defend | Open **AQUARIUM** panel → **LOCK** — blocks all theft for 60s (2 min recharge) |

Fish rarities: Common ($10), Uncommon ($25), Rare ($70), Epic ($180), Legendary ($500) — each also earns passive income per second while stored.

## Project Structure (for editing the code)

```
default.project.json        Rojo project mapping
src/shared/GameConfig.lua   All tuning numbers: rarities, rods, baits, lock/raid rules
src/server/
  init.server.lua           Entry point: wires everything, player join/leave
  WorldBuilder.lua           Builds harbor plaza, water, shop, decorations
  DockManager.lua            Builds 8 docks + aquariums, claims/releases them
  DataManager.lua            DataStore persistence (load/save/autosave/retries)
  FishingService.lua         Server-validated fishing + rarity rolls
  AquariumService.lua        Store, sell, lock, raid defense, passive-income loop
  ShopService.lua            Server-validated purchases
  StateSync.lua              Sends state snapshots to clients + leaderstats
  Remotes.lua                Creates all RemoteEvents/Functions
src/client/init.client.lua  All UI (HUD, aquarium panel, shop, notifications)
```

All gameplay rules are enforced **on the server** — the client only sends requests and renders state, so exploiters can't forge cash, rarity, or raid outcomes.

To rebuild the place file after editing scripts, install [Rojo](https://rojo.space) and run:

```bash
rojo build -o HarborHeist.rbxlx
```

Or use `rojo serve` with the Rojo Studio plugin for live syncing while you edit.

## Tuning the Game
Everything balance-related lives in `src/shared/GameConfig.lua`: rarity weights/values/income, rod & bait tiers and costs, aquarium capacity (20), lock duration (60s), lock cooldown (120s), max carried fish (5), dock count (8), and raid window timing (20–30 min interval, 5 min window, 1 fish max per raid).
