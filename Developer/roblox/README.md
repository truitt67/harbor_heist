# Harbor Heist — Multiplayer Fishing & Live-Well PvP

A server-authoritative Roblox game: fish at your personal dock, store catches in a
live-well aquarium for passive income, sell for cash, upgrade rods/bait/aquarium,
and raid (or lock down) other players' aquariums during timed raid windows.

Currently in closed V1 test, launch-pending final balance/decision finalization.
Active development runs off the Beads tracker (`br ready`): EPIC 47 *Pre-Launch
Remediation* — data integrity, PvP fairness, economy retune, premium UX polish —
is in flight. See `AGENTS.md`.

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
| Store fish | **BAG** → **STORE** / **STORE ALL** — stored fish earn passive cash/min while stored (rarer = more). |
| Sell | **AQUARIUM** panel → **SELL ALL** for instant cash. |
| Upgrade | Walk to the **Bait & Tackle Shop** (plaza center), press **E**: rods, bait, aquarium capacity, locks, alarms. |
| Raid | During an announced **Raid Window**, opt in via the aquarium panel and target a rival aquarium — max 1 fish per successful raid. |
| Defend | **AQUARIUM** → **LOCK** blocks theft (60s base, 120s recharge). Alarms stun the thief. |

Rarities and actual sell values (per-species `BaseSellValue` in
`src/shared/FishDefinitions.lua`): Common $8–15, Uncommon $30–40, Rare $80–110,
Epic $200–300, Legendary $600–1000. Stored fish also pay passive income by
species ($0.5–100/min, rarer = more). Species, zones, and rarity weights live in
`src/shared/FishDefinitions.lua` + `ZoneDefinitions.lua`.

### Controls (keyboard)

| Key | Action |
|---|---|
| **F** / **Space** | Cast / fish (Space defers to panel buttons when a panel is open) |
| **G** or **I** | Toggle BAG |
| **C** | Collection log |
| **T** | AQUARIUM panel |
| **S** | Bait & Tackle shop |
| **Q** | Quests |
| **R** | Raid panel |
| **B** | Boat |
| **H** | Keyboard-shortcut help |
| **Tab** | Cycle panel controls (keyboard/controller navigation) |

On touch devices every action has an on-screen button; bindings above mirror
`src/client/init.client.lua` (`UserInputService.InputBegan`) and `KeyboardNav.lua`.

## Project Structure

```
default.project.json      Rojo mapping for the playable place
test.project.json         Rojo mapping for the TestEZ datamodel suite
e2e_scenarios.project.json Rojo mapping for the E2E scenario suite
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
scripts/                  run_tests.sh, run_e2e_scenarios.sh, contract gates, bead tooling
docs/                     TESTING.md, runbooks, tuning, decisions
```

All gameplay rules are enforced **on the server**. The client only sends requests and
renders state — exploiters can't forge cash, rarity, or raid outcomes.

## Build & Toolchain

Tools: `rojo`, `lune`, `selene` must be on PATH. Tooling machines install them
via [rokit](https://rokit.ra1n.dev); direct GitHub-release binaries under
`~/.local/bin` are equivalent (this is how the Linux dev host is set up).
`run-in-roblox` is additionally required only for the Studio-driven suites.
Rebuild the place after editing scripts:

```bash
rojo build -o HarborHeist.rbxlx        # playable place
rojo build test.project.json -o HarborHeist_tests.rbxlx
```

Or `rojo serve` + the Rojo Studio plugin for live sync while editing.

## Testing

Three suites plus static gates — full details in **`docs/TESTING.md`**.

```bash
scripts/run_tests.sh --pure        # 1239 pure-Luau tests (lune) — runs anywhere, CI
scripts/run_tests.sh --datamodel   # 410 TestEZ tests — needs Studio
scripts/run_e2e_scenarios.sh      # E2E scenarios — needs Studio
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

- 5 rarities (Common→Legendary: catch weights, sell values, income/min), 3 rods
  (Basic/Steel/Golden) and 3 baits (Basic/Shrimp/Magic) with luck bonuses.
- Aquarium Tank track: Starter/Expanded/Large/Mega (capacity 20 → 35/50/75,
  income multiplier 1.0→1.5).
- Defense: lock 60s base / 120s recharge + Lock I–III (up to 150s lock / 30s
  recharge); Alarm I–III (stun 3–8s, always notifies).
- Dock cosmetic/income track: Basic/Lamp-Lit/Garden/Golden Harbor (income 1.0→1.6).
- Raids: window every 20–30 min, 5 min duration, 1 fish per raid, 6 min raider
  cooldown, 30 min per-victim cooldown, max 2 losses per window.
- Misc: max 5 carried fish, 8 docks, 3 free lock uses.

## Working in this Repo

See **`AGENTS.md`** for the full agent workflow: standalone-checkout environment
notes (what's installed, what needs Studio), Beads (`br`) issue tracking including
the EPIC 47 remediation program, quality gates (`--pure` suite + coverage gate +
selene delta), and the commit/push protocol. Stage explicit paths only — never
`git add -A`.
