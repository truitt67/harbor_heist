# Harbor Heist — V1 Product Requirements Document

**Version:** 1.0
**Status:** Draft / Build Specification
**Platform:** Roblox
**Experience Type:** Multiplayer fishing, aquarium-tycoon, collection, and light PvP game
**Visual Direction:** Cozy harbor and aquarium atmosphere with optional, bounded “heist” tension.

## Product summary

**Harbor Heist** is a Roblox multiplayer fishing game where each player owns a dock and live-well aquarium. Players catch fish through a simple skill interaction, keep fish in their aquarium for passive income, sell fish for immediate cash, upgrade their equipment and dock, complete a collection book, and choose whether to participate in time-bounded player-vs-player aquarium raids.

The V1 goal is to create a satisfying first session in which a player catches a fish, sees it displayed in their aquarium, earns money, buys an upgrade, and understands the optional raid/defense system within five minutes. Roblox recommends getting players to the fun quickly, using contextual onboarding rather than lengthy tutorials, and giving starter items that enable immediate participation.[^1]

## Product goals

1. **Deliver an understandable core loop:** catch fish → store or sell → earn/spend → upgrade → catch better fish.
2. **Make the aquarium emotionally valuable:** it is a visible collection, passive-income source, and social status object.
3. **Add fair optional PvP:** raids must create stories and tension without allowing persistent griefing.
4. **Support repeat sessions:** collection goals, upgrade milestones, and rotating catch opportunities should make players want to return.
5. **Provide a buildable V1:** one harbor map, a manageable fish catalog, a small upgrade tree, and limited raid rules.

Roblox identifies average session time, first-session engagement, retention, and monetization as key game-health measures; it also recommends clear short-, mid-, and long-term goals backed by progression.[^2][^1]

## Non-goals

The following are explicitly outside V1 scope:

- Open-world exploration across multiple islands.
- Deep player-to-player trading or an auction house.
- Guilds, clans, player housing, or full social roleplay systems.
- Competitive leaderboards, ranked seasons, or tournaments.
- Complex fishing simulation mechanics such as line tension physics, weather, tides, or boat ownership.
- Large-scale combat, player elimination, or unrestricted base destruction.
- Premium currency or aggressive monetization systems at launch.
- Cross-server economies or global fish markets.


## Audience

**Primary audience:** Roblox players who enjoy cozy simulators, fishing/collection games, visible progression, tycoon-style upgrades, and lightweight social rivalry.

**Secondary audience:** Players who want a low-pressure multiplayer experience with optional risk and reward rather than constant combat.

The game should be understandable to a young and casual audience while still giving experienced players optimization choices through gear, fish rarity, aquarium capacity, and raid timing.

## Player promise

> Build a beautiful aquarium, catch increasingly rare fish, grow your dock into a harbor destination, and decide when your collection is worth protecting—or risking for a bigger reward.

The game must feel mostly peaceful and rewarding; the heist mechanic is a deliberate spice, not the entire product. The cozy fishing-aquarium theme is the central visual identity.

## Core loop

| Step | Player action | Immediate reward | Longer-term purpose |
| :-- | :-- | :-- | :-- |
| 1 | Travel to a fishing spot and cast | Bite opportunity and minigame | Begins the primary activity |
| 2 | Complete timing-based catch interaction | Fish added to inventory | Creates skill and collection reward |
| 3 | Choose to store or sell fish | Passive income or immediate cash | Introduces meaningful choice |
| 4 | Store fish in live well | Visible aquarium display and earnings | Builds attachment and status |
| 5 | Earn cash over time | Currency accumulation | Funds upgrades |
| 6 | Buy rods, bait, capacity, or dock upgrades | Better catch chances or efficiency | Progression and goals |
| 7 | Protect, raid, or avoid raid windows | Optional risk/reward | Social stories and repeat play |

## First five minutes

The opening must be playable with minimal text and no mandatory tutorial wall. Roblox recommends showing the core fun quickly and using context-sensitive prompts rather than long tutorials.[^1]

1. Player spawns at their assigned starter dock.
2. Player sees their empty aquarium/live well and a nearby starter rod rack.
3. Player receives a free basic rod and starter bait automatically.
4. A short prompt directs the player to cast into the nearby starter fishing zone.
5. Player catches a common fish through a simple timing interaction.
6. Player receives a clear choice: **Sell Now** or **Store in Aquarium**.
7. Player stores the fish and sees it appear in the aquarium.
8. The aquarium UI displays passive income beginning to accumulate.
9. Player claims enough starter income or catches additional fish to buy a first upgrade.
10. A contextual prompt explains that aquarium locks and raid windows exist, but PvP remains disabled or unavailable until the player has had time to learn the safe core loop.

**First-session success condition:** A new player catches at least one fish, stores at least one fish, claims or observes passive income, and understands their next upgrade goal.

## Functional requirements

### Fishing system

| ID | Requirement |
| :-- | :-- |
| FISH-01 | Players can equip a fishing rod and cast only within designated fishing zones |
| FISH-02 | Casting initiates a bite-roll process determined by zone, bait, rod, and fish-table probabilities |
| FISH-03 | A bite starts a short, readable timing minigame |
| FISH-04 | Successful completion awards one fish item; failure returns the player to a retry-ready state |
| FISH-05 | Fish have a species, rarity, value, passive-income rate, visual model, and collection-book entry |
| FISH-06 | V1 includes five rarity tiers: Common, Uncommon, Rare, Epic, and Legendary |
| FISH-07 | V1 includes approximately 12–20 species across starter and upgraded fishing zones |
| FISH-08 | The server determines catch results, rarity, rewards, and inventory changes |

The initial timing mechanic should be easy to understand but have a small skill ceiling: players must click or tap while a moving marker enters a target zone. Better rods and bait improve opportunities, not automatic success.

### Fish inventory

| ID | Requirement |
| :-- | :-- |
| INV-01 | Players have a finite carry inventory for newly caught fish |
| INV-02 | Fish inventory displays species, rarity, sell value, and store eligibility |
| INV-03 | Players can sell eligible fish for immediate currency |
| INV-04 | Players can move eligible fish from inventory into their aquarium |
| INV-05 | Inventory must prevent duplication, negative quantities, and transfers that exceed aquarium capacity |
| INV-06 | The server validates all inventory movement, sale, and storage requests |

### Aquarium/live-well system

| ID | Requirement |
| :-- | :-- |
| AQUA-01 | Every player has one personal aquarium at their dock |
| AQUA-02 | Stored fish appear as visible, simplified aquarium occupants or representations |
| AQUA-03 | Each stored fish contributes a passive income rate based on rarity and species |
| AQUA-04 | Passive income accrues only while the player is in the experience for V1 |
| AQUA-05 | Players claim accumulated aquarium income through a visible interaction or UI button |
| AQUA-06 | Aquarium capacity limits the number or total weight/value of stored fish |
| AQUA-07 | Aquarium upgrades increase capacity and may improve display quality or income efficiency |
| AQUA-08 | The aquarium clearly displays capacity, lock status, stored value, income rate, and claimable income |
| AQUA-09 | Players can remove a stored fish and sell it, subject to raid-state restrictions |

**V1 passive-income model:** Each stored fish has a fixed income-per-minute value. The server calculates earned income from elapsed server time and stored fish, then caps unclaimed earnings to prevent extreme accumulation or exploit impact.

### Economy and upgrades

| ID | Requirement |
| :-- | :-- |
| ECON-01 | The primary V1 currency is Coins |
| ECON-02 | Players earn Coins from fish sales and aquarium income |
| ECON-03 | Players can purchase rods, bait, aquarium-capacity upgrades, and dock upgrades |
| ECON-04 | Every upgrade has a visible effect: improved chance, access, capacity, income efficiency, or cosmetic progression |
| ECON-05 | Purchases must be server-authoritative and persistent |
| ECON-06 | Upgrade prices must support a first meaningful purchase within the opening session |
| ECON-07 | V1 must not sell direct combat power or raid success for Robux |

**V1 upgrade categories:**

- **Rods:** improve bite frequency, minigame forgiveness, or access to better fish pools.
- **Bait:** modifies target species and rarity probabilities; consumable only if the design remains easy to understand.
- **Aquarium capacity:** increases fish slots or total storage value.
- **Dock upgrades:** improve aquarium income multiplier, unlock display features, or unlock new fishing access.


### Collection book

| ID | Requirement |
| :-- | :-- |
| COLL-01 | Players can open a collection book from the main HUD |
| COLL-02 | The book displays discovered and undiscovered species by zone and rarity |
| COLL-03 | Discovered fish show name, rarity, visual, and optional flavor text |
| COLL-04 | Undiscovered fish conceal precise catch data in V1, but provide general collection progress |
| COLL-05 | Completing defined collection milestones awards non-essential rewards such as Coins, titles, dock décor, or aquarium cosmetics |
| COLL-06 | Collection progress persists between sessions |

The collection book is a long-term goal system, consistent with Roblox guidance to give players clear aspirational objectives and progression paths.[^1]

### Raid and defense system

The V1 PvP feature must be **opt-in or time-bounded**. A player should never lose fish simply because they stepped away from the keyboard or joined the game for the first time.


| ID | Requirement |
| :-- | :-- |
| PVP-01 | Raiding is unavailable to new players until they complete onboarding and meet a basic progression threshold |
| PVP-02 | A player can raid only during a clearly labeled raid window or after explicitly opting into a risk zone |
| PVP-03 | Players can activate a temporary aquarium lock using an earned in-game resource, cooldown, or limited free uses |
| PVP-04 | Lock state is visible from the dock, aquarium UI, and any raid-selection interface |
| PVP-05 | A successful raid transfers a limited fish or value amount, never an entire aquarium |
| PVP-06 | Raids have a cooldown for the attacker and a protection period for the defender |
| PVP-07 | A player cannot repeatedly target the same defender within a defined cooldown window |
| PVP-08 | High-rarity fish may have additional protection, raid limits, or insurance in V1 |
| PVP-09 | Defenders receive a clear notification after a completed raid, including what was taken and available recovery/protection actions |
| PVP-10 | The server exclusively validates eligibility, lock status, target state, cooldowns, theft outcome, and transfers |
| PVP-11 | PvP can be disabled in a clearly marked safe harbor/server area if needed for early balancing |
| PVP-12 | Raid rewards and losses are capped per time period |

### Recommended V1 raid rule

Use **scheduled raid windows** rather than always-on theft:

- Raid windows occur every 20–30 minutes and last 5 minutes.
- Players opt in by entering a marked “Raid Waters” pier or enabling a dock flag before the window closes.
- Only opted-in aquariums can be targeted.
- A lock protects the aquarium for a short duration, such as 60–120 seconds.
- A successful raid steals one eligible fish or a capped percentage of eligible value.
- The defender receives a 10–15 minute immunity period after a successful loss.
- Legendary fish are either non-stealable in V1 or protected by a much lower raid probability.

This creates anticipation and social stories while minimizing griefing and accidental losses. It also gives players clear agency over whether they participate.

## User stories

### New player

- As a new player, I want to catch a fish within my first minute so I immediately understand why the game is fun.
- As a new player, I want to see the fish in my aquarium so I feel ownership over my progress.
- As a new player, I want to know whether I should sell or store a fish so I can make an informed choice.
- As a new player, I want a visible next upgrade goal so I know what to do after my first catch.
- As a new player, I want protection from raids until I understand the game.


### Progression player

- As a progressing player, I want better rods and bait to change what I can catch.
- As a collector, I want rare species and a collection book so I have long-term goals.
- As a dock owner, I want my aquarium to visibly improve as I invest in it.
- As an economy-focused player, I want to decide between immediate sale value and long-term passive income.


### Social/PvP player

- As a competitive player, I want raid opportunities to involve skill, timing, or planning rather than random griefing.
- As a defender, I want clear lock tools, warnings, and recovery time so losses feel fair.
- As a social player, I want to visit other docks and admire their aquariums without being forced into PvP.


## User flow

```text
Join Harbor
  -> Spawn at personal dock
  -> Receive starter rod and bait
  -> Cast at starter fishing spot
  -> Complete catch minigame
  -> Receive fish
  -> Choose:
       Sell fish -> Receive Coins -> Visit shop -> Upgrade
       Store fish -> Aquarium displays fish -> Passive income accrues
  -> View collection book
  -> Upgrade rod, bait, aquarium, or dock
  -> Optional:
       Enter Raid Waters / opt in
       -> Review target and lock status
       -> Attempt raid
       -> Receive outcome, cooldown, and notifications
```


## UX and visual requirements

The visual experience should communicate **“cozy harbor aquarium”** first and **“heist”** second.

### Aesthetic direction

- Warm sunset or soft daytime harbor palette.
- Readable, cartoony fish silhouettes with clear rarity cues.
- Clean water, dock wood, glass aquarium reflections, bubbles, plants, rocks, lanterns, and simple nautical props.
- Rarity should use more than color alone: labels, stars, fish shape, animation, and collection-book treatment must reinforce rarity accessibly.
- The player’s dock should become more visually impressive as upgrades are purchased.
- Raid status should use clear, non-threatening language and visuals: a lock icon, timer, alert buoy, or subtle harbor signal.


### UX principles

- The player always sees their current Coins, rod, aquarium capacity, and claimable income.
- The “store versus sell” decision must show a direct comparison: immediate sale value versus passive-income contribution.
- Fishing feedback must be immediate: cast cue, bite cue, timing feedback, catch reveal, and rarity presentation.
- Raid warnings must be prominent but not panic-inducing.
- All critical interactions must work on keyboard/mouse and mobile touch controls.
- The design must avoid requiring fast reflexes as the only route to progression; upgrades and collection strategy should also matter.


## Data requirements

Roblox DataStores provide persistent storage across places in an experience, making them appropriate for player progression, inventories, upgrades, and collection state.[^3][^4]

### Player profile data

```lua
PlayerProfile = {
    -- Schema version. Bump on breaking changes; DataManager uses this for migration.
    Version = 2,
    Coins = 0,
    TotalCoinsEarned = 0,

    Equipment = {
        EquippedRodLevel = 1,
        EquippedBaitLevel = 1,
        OwnedRodLevels = { 1 },
        BaitInventory = {
            level = 1, -- equipped bait tier
            quantity = -1 -- -1 means unlimited/reusable bait (DEC-5)
        }
    },

    Aquarium = {
        Capacity = 20, -- Starter Tank capacity; matches GameConfig.lua upgrade tier 1
        UpgradeLevel = 1,
        StoredFish = {
            -- FishInstance records
        },
        UnclaimedIncome = 0,
        LastIncomeTimestamp = 0,
        LockUntilTimestamp = 0,
        RaidProtectionUntilTimestamp = 0,
        RaidOptIn = false
    },

    Dock = {
        UpgradeLevel = 1,
        CosmeticUnlocks = {}
    },

    Collection = {
        DiscoveredSpecies = {
            -- SpeciesId = true
        },
        MilestonesClaimed = {}
    },

    PvP = {
        RaidAttemptsToday = 0,
        LastRaidTimestamp = 0,
        RecentTargetUserIds = {},
        RaidsWon = 0,
        RaidsLost = 0
    },

    Onboarding = {
        HasCompletedIntro = false,
        HasCaughtFirstFish = false,
        HasStoredFirstFish = false,
        HasClaimedIncome = false,
        HasSeenRaidExplanation = false
    }
}
```


### Fish-instance data

Each stored fish should be represented as a unique record rather than only a count, because raids, display selection, and species-specific economics may require individual attributes.

```lua
FishInstance = {
    InstanceId = "uuid-or-server-generated-id",
    SpeciesId = "Bluegill",
    Rarity = "Common",
    BaseSellValue = 15,
    IncomePerMinute = 1,
    CaughtAtTimestamp = 0,
    SourceZoneId = "StarterPier",
    IsRaidProtected = false
}
```


### Static configuration data

Static game-balance values should not be copied into every player profile:

```lua
FishDefinition = {
    SpeciesId = "Bluegill",
    DisplayName = "Bluegill",
    Rarity = "Common",
    ZoneIds = {"StarterPier"},
    BaseSellValue = 15,
    IncomePerMinute = 1,
    CatchWeight = 60,
    ModelId = "Fish_Bluegill",
    CollectionOrder = 1
}
```

Other static configuration tables:

- Rod definitions and stat modifiers.
- Bait definitions and catch-table modifiers.
- Aquarium capacity and upgrade costs.
- Dock upgrades and benefit values.
- Fishing-zone fish tables.
- Raid cooldowns, protections, loss caps, and lock durations.


## Technical requirements

### Architecture

Use a server-authoritative architecture. The client may render UI, animations, aiming, timing feedback, and local effects, but it must not authoritatively determine fish caught, currency earned, inventory movement, upgrade ownership, lock state, or raid outcomes.

Roblox’s security guidance emphasizes securing the client-server boundary; game clients should be treated as untrusted for actions that affect progression or valuable state.[^5]

### Required Roblox services

| Service | Purpose |
| :-- | :-- |
| `Players` | Player lifecycle and profile initialization |
| `DataStoreService` | Persistent profile, collection, equipment, and upgrade data |
| `ReplicatedStorage` | Shared remotes, modules, UI assets, static config references |
| `ServerScriptService` | Authoritative gameplay services and validation |
| `ServerStorage` | Server-only item templates, protected configuration, fish models if appropriate |
| `Workspace` | Docks, fishing zones, aquarium models, raid areas |
| `TweenService` | Aquarium display, catch reveal, UI and environmental animation |
| `CollectionService` | Tags for fishing zones, docks, aquarium interaction points, and raid areas |
| `MarketplaceService` | Deferred for V1 monetization hooks only |

### Server modules

Recommended V1 module boundaries:

```text
ServerScriptService
  Services
    ProfileService
    FishingService
    FishInventoryService
    AquariumService
    EconomyService
    UpgradeService
    RaidService
    CollectionService
    OnboardingService
    AntiExploitService

ReplicatedStorage
  Remotes
    RequestCast
    SubmitCatchInput
    RequestStoreFish
    RequestSellFish
    RequestClaimIncome
    RequestPurchaseUpgrade
    RequestToggleRaidOptIn
    RequestActivateLock
    RequestRaidAttempt

  Shared
    FishDefinitions
    RodDefinitions
    BaitDefinitions
    UpgradeDefinitions
    RaidConfig
    EconomyConfig
    Types
```


### Remote-event rules

Every remote request must be validated server-side for:

- Player identity and current character state.
- Proximity to the appropriate dock, shop, fishing zone, or interaction point.
- Valid item ownership and sufficient currency.
- Cooldowns and rate limits.
- Valid target, lock state, opt-in state, and raid eligibility.
- Inventory capacity and transaction consistency.
- Reasonable action sequencing; for example, a player cannot sell a fish they never caught.


## Persistence and recovery

- Load player data when the player joins.
- Use safe, throttled saves at meaningful checkpoints and on player exit.
- Save after significant transactions such as purchases, successful catches, fish storage, sales, and raid outcomes, while batching where possible to respect platform limits.
- Use retry behavior and failure handling for datastore operations.
- Prevent data-loss duplication by treating transfer and raid outcomes as atomic server-side transactions where feasible.
- During a datastore failure, disable affected transaction buttons and show a plain-language “Saving unavailable—please try again” message rather than risking inconsistent state.


## Performance requirements

Roblox recommends testing across devices and limiting excessive textures, meshes, and other performance-heavy assets.[^1]


| Area | Requirement |
| :-- | :-- |
| Target devices | Desktop, mobile, tablet, and console-compatible controls where practical |
| Mobile UI | All essential actions usable through touch; no hover-only interaction |
| Map size | One compact harbor designed for short travel times |
| Aquarium display | Use pooled/simplified fish visuals; do not spawn unlimited high-detail animated models |
| Network | Replicate only required aquarium state and nearby visual data |
| Fishing | Minigame runs locally for responsiveness, but result resolution remains server-side |
| Server | Support a small V1 server size, such as 8–16 players, before scaling upward |
| Error handling | No purchase, sale, storage, or raid action may silently fail |

## Security and anti-exploit requirements

- The client cannot set Coins, rarity, fish count, upgrade level, raid success, or lock duration.
- All valuable transactions are created and confirmed on the server.
- Remote events are rate-limited and validate parameters, distance, state, and permissions.
- Server tracks suspicious actions: impossible casting rate, impossible proximity, excessive remote calls, invalid fish IDs, or repeated invalid raid targets.
- All player-to-player asset transfers use server-controlled transaction logic.
- Audit logs should record high-value catches, purchases, storage changes, and raid transfers for debugging and balancing.


## Analytics and success metrics

Roblox provides analytics for growth, technical performance, behavior, retention, and experimentation; its core game-health KPIs include engagement, retention, and monetization.[^6][^2]

### V1 events

Track these events:

- `tutorial_started`
- `starter_rod_received`
- `first_cast`
- `fish_caught`
- `fish_catch_failed`
- `fish_stored`
- `fish_sold`
- `income_claimed`
- `upgrade_shop_opened`
- `upgrade_purchased`
- `collection_book_opened`
- `raid_info_viewed`
- `raid_opt_in_enabled`
- `aquarium_locked`
- `raid_attempted`
- `raid_succeeded`
- `raid_defended`
- `player_left_before_first_catch`
- `player_left_before_first_upgrade`


### Initial success measures

| Metric | V1 target / interpretation |
| :-- | :-- |
| Time to first cast | Under 60 seconds |
| Time to first catch | Under 2 minutes for most new players |
| First stored fish | Most new players accomplish this in first session |
| First upgrade | Achievable during the first 10–15 minutes |
| Five-minute retention | Use this to identify onboarding, performance, or core-loop friction |
| Average session duration | Track as an early engagement signal |
| Return rate | Observe whether collection and upgrade goals bring players back |
| Raid participation | Measure separately from baseline retention; do not assume more raids means healthier gameplay |
| Raid-loss churn | Watch whether players leave immediately after losses and rebalance protection if necessary |

Roblox specifically recommends monitoring first-session retention, ensuring players have fun within five minutes, and investigating onboarding or performance changes when that retention falls.[^1]

## Monetization approach

**V1 recommendation:** launch without gameplay-altering Robux purchases until the core loop, retention, and raid balance are validated.

Potential post-V1 monetization:

- Aquarium skins, glass styles, plants, lights, signs, and dock décor.
- Cosmetic boat skins or fishing-rod visual variants.
- Optional VIP cosmetic dock area.
- Additional saved aquarium display layouts.
- Seasonal collection cosmetics.

Avoid selling:

- Guaranteed Legendary fish.
- Raid success.
- Unlimited locks.
- Direct theft immunity.
- Major catch-power advantages that make non-paying players targets.

Cosmetic-first monetization fits the product’s collection and visual-flex goals without undermining raid fairness.

## Acceptance criteria

### Core gameplay

- A new player can cast, complete a catch interaction, and receive a fish.
- The server determines the fish result and updates the player inventory.
- The player can sell the fish or store it in the aquarium.
- Stored fish visibly appear in the aquarium or in a clearly linked aquarium representation.
- Stored fish generate claimable passive income while the player remains in-game.
- The player can buy and persist at least one rod, bait, capacity, or dock upgrade.


### Progression and collection

- Fish display rarity, sale value, and income contribution.
- The collection book records newly discovered species persistently.
- Aquarium capacity restricts storage correctly.
- Upgrades persist after leaving and rejoining.


### PvP fairness

- New players are protected from raids until onboarding/progression requirements are met.
- A locked aquarium cannot be raided.
- A non-opted-in aquarium cannot be raided under the selected raid-window model.
- One raid cannot empty an aquarium.
- Successful raid victims receive a protection period.
- Attackers cannot repeatedly target the same victim without cooldown.
- All raid outcomes are validated by the server.


### Quality

- Core gameplay works with mouse/keyboard and touch.
- No client can change currency, fish rarity, inventory, or raid result by sending invalid remote data.
- The game is playable on targeted device classes without major UI overlap or performance degradation.
- Analytics events record the first-session funnel and all major economy/PvP actions.


## Release plan

### Internal prototype

Build only:

- One dock template.
- One starter fishing zone.
- Three fish species.
- One rod.
- Store/sell choice.
- Basic aquarium capacity.
- Passive income.
- No PvP.

**Exit criteria:** The core loop is fun without upgrades or raids.

### Closed V1 test

Add:

- Full V1 fish catalog.
- Starter and upgraded fishing zones.
- Rod/bait/capacity/dock upgrades.
- Collection book.
- Aquarium display improvements.
- Scheduled opt-in raids, locks, cooldowns, and protections.
- Basic analytics instrumentation.

**Exit criteria:** New players understand the loop, raid losses do not create disproportionate churn, and no obvious duplication or remote-event exploit exists.

### Public V1 launch

Launch with:

- One polished harbor.
- Clear thumbnail/icon/game description reflecting cozy aquarium fishing.
- A limited event or launch collection target.
- Monitoring plan for first-five-minute retention, economy balance, performance, and raid sentiment.


## Open decisions

1. **Passive income scope:** Should fish earn only while the player is online for V1, or should there be capped offline earnings later?
2. **Raid interaction:** Should a raid be a short skill minigame, a timed dock interaction, or a target-selection system with server-side odds?
3. **Fish transfer:** Should raids steal individual fish, a value token, or a temporary “smuggled crate” that can be recovered?
4. **Starter protection:** What exact threshold unlocks raids: time played, first aquarium upgrade, collection milestones, or player choice?
5. **Bait complexity:** Should bait be consumable from launch, or should V1 use reusable bait types to keep onboarding simple?
6. **Display fidelity:** Does every stored fish need to appear physically in the aquarium, or should the aquarium show a curated subset with a count/status panel for performance?
