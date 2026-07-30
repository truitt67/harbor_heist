# Harbor Heist — Multiplayer Fishing & Live-Well PvP

A server-authoritative Roblox game: fish at your personal dock, store catches in a
live-well aquarium for passive income, sell for cash, upgrade rods/bait/aquarium,
and raid (or lock down) other players' aquariums during timed raid windows.

Currently in closed V1 test, launch-pending final balance/decision finalization.

## Quick Start (no toolchain)

1. Open **Roblox Studio**.
2. **FILE → Open from File...** → pick `HarborHeist.rbxlx`.
3. **Play** (F5) solo, or **Test → Clients and Servers → 2 Players → Start** to
   exercise PvP raiding.
4. Publish with **FILE → Publish to Roblox**.

The entire harbor (plaza, docks, aquariums, shop, water) is built by the server at
startup — the place file is just an empty world plus scripts.

### Saving / DataStores

Player data (cash, gear, fish, collection, quests) persists via DataStores, but only
on a published place:

1. Publish the game.
2. Studio: **Home → Game Settings → Security → Enable Studio Access to API Services**.

Unpublished Studio sessions run fine — saves are silently skipped (see the DataStore
caveat in `docs/TESTING.md`).

## How to Play

| Action | How |
|---|---|
| Fish | Stand in the glowing **Fishing Zone** at your dock, press **FISH** / **F**. Time the cast bar, then hit the bite window. |
| Store fish | **BAG** → **STORE** / **STORE ALL** — stored fish earn cash/sec (rarer = more). |
| Sell | **AQUARIUM** panel → **SELL ALL** for instant cash. |
| Upgrade | Walk to the **Bait & Tackle Shop** (plaza center), press **E**: rods, bait, aquarium capacity, locks, alarms. |
| Raid | During an announced **Raid Window**, opt in via the aquarium panel and target a rival aquarium — max 1 fish per successful raid. |
| Defend | **AQUARIUM** → **LOCK** blocks theft (60s base, 120s recharge). Alarms stun the thief. |

Rarities: Common ($10), Uncommon ($25), Rare ($70), Epic ($180), Legendary ($500) —
each also pays passive income/sec while stored. Species, zones, and rarity weights
live in `src/shared/FishDefinitions.lua` + `ZoneDefinitions.lua`.

## Project Structure

```
default.project.json      Rojo mapping for the playable place
test.project.json         Rojo mapping for the TestEZ datamodel suite
e2e.project.json          Rojo mapping for the E2E suite
selene.toml               Luau lint config

src/shared/
  GameConfig.lua          All tuning: rarities, rods, baits, aquarium, lock/raid rules
  FishDefinitions.lua     Species tables per zone + catch weights
  ZoneDefinitions.lua     Fishing-zone geometry/definitions
  FishInstance.lua        Per-catch record (id, species, rarity, value)
  FishVisuals.lua         Fish rendering data
  PlayerProfile.lua       Profile schema + migration
  PanelAnimation*.lua     Shared panel animation

src/server/
  init.server.lua         Entry point: service wiring + player join/leave
  WorldBuilder.lua        Builds harbor plaza, water, shop, decorations
  DockManager.lua         8 docks + aquariums: build, claim, release, zone checks
  DataManager.lua         DataStore persistence: load/save/autosave/retry/migration
  FishingService.lua      Server-validated cast/bite/catch + luck + rarity rolls
  FishInventoryService.lua Carried/stored fish moves, sell, anti-duplication
  AquariumService.lua     Store, sell, lock, raid defense, passive-income loop
  ShopService.lua         Server-validated purchases (rods/bait/capacity/locks/alarms)
  RaidService.lua         Raid windows, opt-in, theft resolution, cooldowns
  RodService.lua          Rod model + cast/bobber/FX visuals
  BoatService.lua         Boat cosmetics
  QuestService.lua        Quest templates + progress (catch_rarity etc.)
  CollectionService.lua   Species-discovery collection log
  OnboardingService.lua   First-session onboarding flags/progression
  AnalyticsService.lua    Funnel/event analytics (first_cast, fish_caught, ...)
  AntiExploitService.lua  Rate limiting + suspicious-action tracking
  AuditLogService.lua     Audit logging for high-value events
  StateSync.lua           State snapshots to clients + leaderstats
  Remotes.lua             Creates all RemoteEvents/Functions (PRD naming)

src/client/
  init.client.lua         All UI: HUD, aquarium/shop panels, notifications
  AnimationSystem.lua     Client animation framework
  GradientLibrary.lua     UI gradients
  KeyboardNav.lua         Keyboard/controller navigation

test/                     Pure-Luau specs (lune), TestEZ specs, coverage gate
tests/                    Datamodel + E2E stubs, e2e scenarios
scripts/                  run_tests.sh, run_e2e.sh, contract gates, bead tooling
docs/                     TESTING.md, runbooks, tuning, decisions
```

All gameplay rules are enforced **on the server**. The client only sends requests and
renders state — exploiters can't forge cash, rarity, or raid outcomes.

## Build & Toolchain

Tools (`rojo`, `lune`, `selene`, `luau`, `run-in-roblox`) are provided via rokit.
Rebuild the place after editing scripts:

```bash
rojo build -o HarborHeist.rbxlx        # playable place
rojo build test.project.json -o HarborHeist_tests.rbxlx
```

Or `rojo serve` + the Rojo Studio plugin for live sync while editing.

## Testing

Three suites plus static gates — full details in **`docs/TESTING.md`**.

```bash
scripts/run_tests.sh --pure        # 100 pure-Luau tests (lune) — runs anywhere, CI
scripts/run_tests.sh --datamodel   # 410 TestEZ tests — needs Studio
scripts/run_e2e.sh                 # E2E scenarios — needs Studio
```

- The **pure** suite is portable and is what CI runs.
- The **datamodel** and **E2E** suites need Roblox Studio (signed in). On Linux mark
  them NOT-verified; on a Windows PC with Studio they run — see the
  "Running on Windows (Studio present)" section in `docs/TESTING.md` for the
  Git-Bash/CRLF gotchas.
- Static gates: remote-arity contract, overlay input-router contract, and a coverage
  gate run with the suites. Lint with `selene` (never add NEW errors over baseline).

## Tuning

All balance numbers live in `src/shared/GameConfig.lua`:

- Rarities (weights, values, income/sec) and 5 rod / bait tiers.
- Aquarium: base capacity 20, upgrades to 30/45/60; lock 60s base + Lock I–III
  (up to 150s lock / 30s recharge); Alarm I–III (stun 3–8s).
- Raids: window every 20–30 min, 5 min duration, 1 fish per raid, 6 min raider
  cooldown, 30 min per-victim cooldown, max 2 losses per window.
- Misc: max 5 carried fish, 8 docks, 3 free lock uses.

## Working in this Repo

See **`AGENTS.md`** for the full agent workflow: Beads (`br`) issue tracking, Agent
Mail coordination, file reservations, UBS quality gate, and the commit/push
protocol. Stage explicit paths only — never `git add -A` from the repo root.
