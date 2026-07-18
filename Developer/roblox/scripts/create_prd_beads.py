#!/usr/bin/env python3
"""
Harbor Heist — PRD Compliance Bead Generator

Creates a comprehensive, self-documenting Beads issue tree from PRD.md.
Each bead carries rich descriptions (background, reasoning, considerations,
PRD references) so the structure is self-contained for future-self and
collaborating agents.

Run from repo root:  python3 scripts/create_prd_beads.py
"""

import subprocess, json, os, sys, time

REPO = "/home/ubuntu/Developer/roblox"
os.chdir(REPO)

# ─── helpers ──────────────────────────────────────────────────────────────────

def br(args, check=True):
    result = subprocess.run(["br"] + args, capture_output=True, text=True, timeout=30)
    if check and result.returncode != 0:
        sys.stderr.write(f"ERROR: br {' '.join(args)}\n{result.stderr}\n{result.stdout}\n")
        raise RuntimeError(f"br exit {result.returncode}")
    return result

def create_bead(title, btype, priority, description, parent=None, slug=None, labels=None):
    args = ["create", "--json", "-t", btype, "-p", str(priority), "-d", description]
    if slug:
        args += ["--slug", slug]
    if parent:
        args += ["--parent", parent]
    if labels:
        args += ["-l", labels]
    args.append(title)
    r = br(args)
    return json.loads(r.stdout)["id"]

def add_dep(a, b, t="blocks"):
    br(["dep", "add", a, b, "-t", t])

# ─── shared prose ─────────────────────────────────────────────────────────────

EPOCH = (
    "\n\n## BACKGROUND & JUSTIFICATION\n"
    "Part of the Harbor Heist V1 build — migrating the current prototype to full "
    "PRD compliance (see PRD.md). The current codebase is a working server-authoritative "
    "prototype with 5 rarity tiers, basic cast/store/sell, passive income, and basic "
    "theft/lock PvP. The PRD demands a richer experience: structured data, 12-20 species, "
    "timing minigame, claimable income, collection book, upgrade tree, scheduled opt-in "
    "raids, onboarding, analytics, and anti-exploit. Every bead serves the overarching "
    "goal: a cozy fishing-aquarium game with optional bounded PvP heists that creates "
    "social stories without griefing.\n\n"
    "## PRD TRACEABILITY\n"
    "See PRD.md for the authoritative spec. PRD requirement IDs (e.g. FISH-01, AQUA-03, "
    "PVP-05) are referenced in task acceptance criteria."
)

beads = []  # (key, title, type, pri, slug, desc, ac, parent_key, labels)
deps = []   # (from_key, to_key, dep_type)

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 0: OPEN DECISIONS
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-decisions",
    "EPIC 0: Resolve PRD Open Decisions",
    "epic", 0, "resolve-open-decisions",
    "Resolve the 6 open design decisions at the end of PRD.md before building. These shape "
    "the data model, raid system, bait system, and display strategy. Resolving early prevents "
    "cascading rework. Each decision must be documented with reasoning so future-self "
    "understands the trade-offs." + EPOCH,
    None, None, None))

dec = [
    ("dec-income", "DEC-1: Passive income scope (online-only vs capped offline)", "dec-income-scope",
     "PRD Open Decision #1. AQUA-04 says 'accrues only while in-game for V1' but the income "
     "model section implies elapsed-time calculation with a cap — tension. "
     "RECOMMENDATION: V1 online-only accrual with a claimable income pool (don't auto-add to "
     "cash), capped to prevent extreme accumulation. Offline earnings deferred to V1.1. "
     "This BLOCKS Epic 5 income model. PRD refs: AQUA-04, AQUA-05, income model note.",
    ("epic-decisions", "- [ ] Decision documented in design note\n- [ ] GameConfig/EconomyConfig updated\n- [ ] Epic 5 unblocked")),

    ("dec-raid-model", "DEC-2: Raid interaction model", "dec-raid-interaction",
     "PRD Open Decision #2. Options: skill minigame, timed interaction, or target-selection "
     "+ odds. Current prototype uses target-selection + 50% RNG. "
     "RECOMMENDATION: hybrid — target selection reveals eligible targets; the actual theft "
     "has a short timing element (mobile-friendly, not reflex-only). "
     "BLOCKS Epic 8 raid flow (8.5). PRD refs: PVP-02..PVP-10.",

    ("epic-decisions", "- [ ] Decision documented\n- [ ] Raid flow design (8.5) updated\n- [ ] Mobile feasibility confirmed")),

    ("dec-transfer", "DEC-3: Fish transfer model for raids", "dec-fish-transfer",
     "PRD Open Decision #3. Steal individual fish, value token, or recoverable smuggled crate. "
     "Current: individual fish. RECOMMENDATION: individual fish with legendary protection "
     "(IsRaidProtected flag on Legendary). Concrete, bounded, emotionally impactful. "
     "BLOCKS Epic 8 raid outcome (8.5, 8.8). PRD refs: PVP-05, PVP-08.",

    ("epic-decisions", "- [ ] Decision documented\n- [ ] Raid transfer logic (8.5) updated")),

    ("dec-protection", "DEC-4: Starter protection threshold", "dec-starter-protection",
     "PRD Open Decision #4. When does PvP unlock? RECOMMENDATION: double gate — "
     "(1) progression threshold: first aquarium upgrade OR 10 catches, AND "
     "(2) scheduled raid window opt-in. Prevents griefing, ties to progression. "
     "BLOCKS Epic 8 new-player protection (8.3). PRD refs: PVP-01.",

    ("epic-decisions", "- [ ] Decision documented\n- [ ] OnboardingService threshold (8.3, 9.1) updated")),

    ("dec-bait", "DEC-5: Bait complexity (consumable vs reusable)", "dec-bait-complexity",
     "PRD Open Decision #5. Current: reusable tier upgrades. PRD profile has BaitInventory "
     "with quantities (implying consumable). RECOMMENDATION: V1 reusable tier upgrades "
     "for onboarding simplicity. Consumable bait = V1.1 economy sink. "
     "BLOCKS Epic 6 bait (6.2). PRD refs: ECON-03, BaitDefinitions.",

    ("epic-decisions", "- [ ] Decision documented\n- [ ] Bait design (6.2) updated\n- [ ] BaitDefinitions (2.4) reflects decision")),

    ("dec-display", "DEC-6: Display fidelity (every fish vs curated subset)", "dec-display-fidelity",
     "PRD Open Decision #6. PRD perf section: 'do not spawn unlimited high-detail models.' "
     "Current code caps maxVisibleFish=10. RECOMMENDATION: keep curated subset "
     "(show N highest-rarity fish) + status panel with full counts. "
     "BLOCKS Epic 5 aquarium display (5.6). PRD refs: AQUA-02, performance table.",

    ("epic-decisions", "- [ ] Decision documented\n- [ ] Aquarium display (5.6) updated")),
]

for key, title, slug, desc, (parent, ac) in dec:
    beads.append((key, title, "question", 0, slug, desc, ac, parent, None))
    deps.append((key, "epic-decisions", "parent-child"))

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 1: STRUCTURED DATA MODEL
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-foundation",
    "EPIC 1: Structured Data Model Foundation",
    "epic", 0, "data-model-foundation",
    "Refactor the flat data model (cash, rodLevel, baitLevel, liveWell[], carried[]) into the "
    "structured PlayerProfile from PRD.md. THE foundational epic — every gameplay system "
    "(fishing, inventory, aquarium, raids, collection, onboarding) depends on FishInstance "
    "records instead of raw rarity indexes.\n\n"
    "WHY THIS FIRST: Current code stores fish as bare integer rarity indexes. This makes "
    "per-fish attributes (species, sell value, income, raid protection, catch time) impossible. "
    "Raids, collection, species-specific economics, individual fish management ALL require "
    "FishInstance records. Get this right first or face cascading rework.\n\n"
    "FILES: src/server/DataManager.lua, src/shared/GameConfig.lua, src/server/StateSync.lua" + EPOCH,
    None, None, None))

t1 = [
    ("t-1.1", "TASK 1.1: PlayerProfile schema", "profile-schema", 0,
     "Implement full PlayerProfile (PRD.md 271-326): Version, Coins, TotalCoinsEarned, "
     "Equipment{EquippedRodId, OwnedRodIds, BaitInventory}, Aquarium{Capacity, UpgradeLevel, "
     "StoredFish, UnclaimedIncome, LastIncomeTimestamp, LockUntilTimestamp, "
     "RaidProtectionUntilTimestamp, RaidOptIn}, Dock{UpgradeLevel, CosmeticUnlocks}, "
     "Collection{DiscoveredSpecies, MilestonesClaimed}, PvP{RaidAttemptsToday, "
     "LastRaidTimestamp, RecentTargetUserIds, RaidsWon, RaidsLost}, Onboarding{flags}.\n"
     "Migrate DataManager.defaultData() + session to this shape. Session mirrors profile for "
     "live gameplay; persistence stores serializable subset.\n"
     "WHY: This schema is the contract every service reads/writes against."),

    ("t-1.2", "TASK 1.2: FishInstance record structure", "fish-instance", 0,
     "Implement FishInstance (PRD.md 333-344): InstanceId (HttpService:GenerateGUID), SpeciesId, "
     "Rarity, BaseSellValue, IncomePerMinute, CaughtAtTimestamp (os.time()), SourceZoneId, "
     "IsRaidProtected. Factory: FishInstance.new(speciesId, zoneId) looks up FishDefinition.\n"
     "WHY: Per-fish records enable per-fish selling, raid theft, collection tracking, display selection."),

    ("t-1.3", "TASK 1.3: Migrate v1 flat format to structured profile", "migration-v1", 0,
     "Existing players have saved data in old flat format {cash, rodLevel, baitLevel, liveWell{}}. "
     "On load, detect (no Version field or Version<2) and migrate: cash→Coins, rodLevel→EquippedRodId "
     "(map level→id), baitLevel→BaitInventory, liveWell[] rarity indexes→StoredFish[] placeholder "
     "FishInstances. Set Version=2. Log migration. DataStore already has old data — must handle both."),

    ("t-1.4", "TASK 1.4: Profile versioning + migration framework", "profile-versioning", 1,
     "Lightweight migration framework: versioned function chain. Migration registry keyed by source "
     "version. On load, if Version < CURRENT, run in sequence. WHY: V1 will iterate; clean migration "
     "prevents data corruption. Keep simple — not over-engineered."),

    ("t-1.5", "TASK 1.5: Deep-validate sanitize() for full profile", "sanitize-deep", 0,
     "Expand sanitize() to deep-validate entire PlayerProfile: every FishInstance, Equipment IDs "
     "against definitions, Coins clamped [0,MAX], Collection species against FishDefinitions, "
     "PvP timestamps sane. WHY: Client data untrusted; DataStore can corrupt; sanitize-on-load "
     "is last defense. Extend existing good patterns."),
]

for key, title, slug, pri, desc in t1:
    ac = "- [ ] Implemented and tested\n- [ ] No runtime errors with new structure\n- [ ] Existing flows updated to new field paths"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-foundation", None))
    deps.append((key, "epic-foundation", "parent-child"))

deps += [
    ("epic-foundation", "epic-decisions", "blocks"),
    ("t-1.3", "t-1.1", "blocks"),
    ("t-1.4", "t-1.1", "blocks"),
    ("t-1.5", "t-1.1", "blocks"),
    ("t-1.3", "dec-income", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 2: CONTENT — Fish/Rod/Bait/Upgrade Definitions
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-content",
    "EPIC 2: Game Content Definitions",
    "epic", 0, "game-content-definitions",
    "Create the static definition tables (FishDefinitions, RodDefinitions, BaitDefinitions, "
    "UpgradeDefinitions, RaidConfig, EconomyConfig) as shared modules. The current code only "
    "has rarity tiers in GameConfig - no species, no zones, no upgrade tiers.\n\n"
    "WHY: Definitions are the content backbone. Fishing, economy, collection, shop, and raids "
    "all read from these tables. They must exist before any gameplay system can reference them.\n"
    "FILES: src/shared/FishDefinitions.lua, RodDefinitions.lua, BaitDefinitions.lua, etc." + EPOCH,
    None, None, None))

t2 = [
    ("t-2.1", "TASK 2.1: Design 12-20 fish species across 5 rarities", "fish-species", 0,
     "PRD FISH-07: '12-20 species across starter and upgraded zones.' Define FishDefinition records "
     "(PRD.md 352-362): SpeciesId, DisplayName, Rarity, ZoneIds, BaseSellValue, IncomePerMinute, "
     "CatchWeight, ModelId, CollectionOrder. Distribute across rarities (Common most weighted, "
     "Legendary rarest). Create names with nautical/cozy theme.\n"
     "WHY: This is the collectible content that drives engagement and the collection book."),

    ("t-2.2", "TASK 2.2: Define fishing zones with fish tables", "fishing-zones", 0,
     "PRD FISH-01: 'cast only within designated fishing zones.' Define at least 2 zones: "
     "StarterPier (common/uncommon species) and DeepWater (rare+ species, requires rod upgrade). "
     "Each zone has a fish table (species→catch weight). PRD ECON-04: upgrades 'unlock new fishing access.'\n"
     "WHY: Zones create progression gates and visual variety in the harbor."),

    ("t-2.3", "TASK 2.3: Expand RodDefinitions beyond 3 tiers", "rod-definitions", 1,
     "PRD ECON-03: rods improve 'bite frequency, minigame forgiveness, or access to better fish pools.' "
     "Current code has 3 rods with luck + castTime. Expand to include: minigame zone size modifier "
     "(forgiveness), zone access flag (DeepWater unlock), and visual/cosmetic progression. "
     "Each rod has visible effect (PRD ECON-04)."),

    ("t-2.4", "TASK 2.4: BaitDefinitions per DEC-5 decision", "bait-definitions", 1,
     "Per DEC-5 (reusable tiers for V1): define 3-4 bait tiers with luck modifiers and "
     "species-rarity probability shifts. Each bait 'modifies target species and rarity probabilities' "
     "(PRD ECON-03). If DEC-5 flips to consumable, adjust to inventory-quantity model."),

    ("t-2.5", "TASK 2.5: Aquarium capacity upgrade tiers", "aquarium-upgrade-tiers", 1,
     "PRD AQUA-07: 'Aquarium upgrades increase capacity and may improve display quality or income "
     "efficiency.' Define 3-4 capacity tiers (e.g., 10→20→30→50) with escalating costs. "
     "Optionally add income multiplier per tier. Tied to EconomyConfig for cost curves."),

    ("t-2.6", "TASK 2.6: Dock upgrade tiers", "dock-upgrade-tiers", 1,
     "PRD ECON-03: 'Dock upgrades: improve aquarium income multiplier, unlock display features, "
     "or unlock new fishing access.' Define 3-4 dock tiers: income multiplier, cosmetic unlocks "
     "(plants, lights, décor), and possibly DeepWater pier access."),

    ("t-2.7", "TASK 2.7: EconomyConfig — cost curves and balance", "economy-config", 0,
     "Define EconomyConfig with cost curves for all upgrades so first meaningful purchase is "
     "achievable in opening session (PRD ECON-06: 'within first session'). Balance income rates "
     "(incomePerMinute per rarity) vs upgrade costs so progression feels rewarding not grindy. "
     "Reference current GameConfig.Rarities incomePerSec (convert to perMinute)."),
]

for key, title, slug, pri, desc in t2:
    ac = "- [ ] Definition module created in src/shared/\n- [ ] Data validated against PRD requirements\n- [ ] Referenced correctly by consuming services"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-content", None))
    deps.append((key, "epic-content", "parent-child"))

deps += [
    ("epic-content", "t-1.1", "blocks"),
    ("t-2.1", "t-1.2", "blocks"),
    ("t-2.4", "dec-bait", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 3: FISHING SYSTEM — Timing Minigame + Species-based Catches
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-fishing",
    "EPIC 3: Fishing System Rework — Timing Minigame",
    "epic", 1, "fishing-system-rework",
    "Replace the current auto-catch (cast→wait→free fish) with a timing-based minigame and "
    "species-based catch resolution per PRD FISH-01..FISH-08.\n\n"
    "Current FishingService: player casts, waits castTime seconds, gets a fish automatically. "
    "PRD FISH-03 requires 'a short, readable timing minigame' — a moving marker the player must "
    "stop in a target zone. PRD FISH-04: success awards fish, failure = retry-ready. PRD FISH-08: "
    "server determines result. FISH-02: bite-roll determined by zone+bait+rod+fish-table.\n\n"
    "The minigame runs client-side for responsiveness (PRD perf table) but RESULT resolution is "
    "server-side. The server tells the client when a bite occurs; client runs the timing UI; "
    "client reports the timing result; server validates and resolves the actual species/value.\n"
    "FILES: src/server/FishingService.lua, src/client/init.client.lua" + EPOCH,
    None, None, None))

t3 = [
    ("t-3.1", "TASK 3.1: Server bite-roll from zone+bait+rod+fish-table", "bite-roll", 1,
     "PRD FISH-02. Server determines when a bite occurs based on: zone fish table weights, "
     "rod luck modifier, bait rarity modifier. Replace current fixed castTime with: cast→wait "
     "(randomized, rod-dependent)→bite event fired to client. Server tracks bite state per player.\n"
     "WHY: Bite timing must be server-determined to prevent client-side prediction exploits."),

    ("t-3.2", "TASK 3.2: Client timing minigame UI", "minigame-client", 1,
     "PRD FISH-03. Client receives bite event, shows a timing UI: a marker sweeps across a bar "
     "with a highlighted target zone. Player clicks/taps to stop. If marker in zone = success. "
     "Better rods = wider target zone (forgiveness, ECON-04). Mobile-friendly: large touch target, "
     "not reflex-only. PRD UX: 'avoid requiring fast reflexes as the only route.'\n"
     "FILES: src/client/init.client.lua — new minigame overlay."),

    ("t-3.3", "TASK 3.3: SubmitCatchInput remote — client reports timing result", "catch-input-remote", 1,
     "PRD server modules list 'SubmitCatchInput'. New RemoteEvent. Client sends timing result "
     "(hit/miss + timing offset) to server. Server validates: (a) player has active bite state, "
     "(b) timing is plausible (within minigame duration), (c) rate-limited. Then server resolves "
     "success/fail and the actual species. PRD FISH-04: success→fish, fail→retry-ready."),

    ("t-3.4", "TASK 3.4: Species-based catch resolution", "species-resolution", 1,
     "PRD FISH-05, FISH-08. On validated successful catch, server rolls species from the zone's "
     "fish table weighted by species CatchWeight, modified by rod+bait luck. Creates FishInstance "
     "via factory (1.2), adds to player's carried inventory. Notify client with species name, "
     "rarity, value. Replaces current rarity-only roll."),

    ("t-3.5", "TASK 3.5: Zone access enforcement", "zone-access", 1,
     "PRD FISH-01: 'cast only within designated fishing zones.' Enforce zone membership "
     "(DockManager.isInFishingZone already exists — extend for multiple zones). Also enforce "
     "rod-based zone access (DeepWater requires upgraded rod, per 2.2/2.3). Server validates "
     "player is in the correct zone for their rod before allowing cast."),
]

for key, title, slug, pri, desc in t3:
    ac = "- [ ] Implemented per PRD FISH-01..FISH-08\n- [ ] Server-authoritative validation confirmed\n- [ ] Mobile input works\n- [ ] No exploit path for free fish"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-fishing", None))
    deps.append((key, "epic-fishing", "parent-child"))

deps += [
    ("epic-fishing", "epic-content", "blocks"),
    ("epic-fishing", "t-1.2", "blocks"),
    ("t-3.2", "t-3.1", "blocks"),
    ("t-3.3", "t-3.1", "blocks"),
    ("t-3.3", "t-3.2", "blocks"),
    ("t-3.4", "t-3.3", "blocks"),
    ("t-3.5", "t-2.2", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 4: FISH INVENTORY — Per-Fish Management
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-inventory",
    "EPIC 4: Fish Inventory — Per-Fish Management",
    "epic", 1, "fish-inventory-mgmt",
    "PRD INV-01..INV-06. The current code has a flat 'carried' array with no per-fish UI. "
    "PRD requires: finite carry inventory displaying species, rarity, sell value, store eligibility; "
    "sell individual fish; move individual fish to aquarium; prevent duplication/negative/exceed-cap.\n\n"
    "With FishInstance records (1.2), the carried array holds FishInstance objects. The client "
    "needs an inventory panel showing each fish with sell/store actions per fish (not just 'sell all').\n"
    "FILES: src/server/FishInventoryService.lua (new), src/client/init.client.lua" + EPOCH,
    None, None, None))

t4 = [
    ("t-4.1", "TASK 4.1: FishInventoryService server module", "inventory-service", 1,
     "New server module managing carried[] inventory of FishInstances. Methods: addFish(session, "
     "fishInstance), removeFish(session, instanceId), sellFish(session, instanceId), "
     "storeFish(session, instanceId, aquariumCapacity). All server-validated (PRD INV-06). "
     "PRD INV-05: prevent duplication, negative quantities, over-capacity transfers."),

    ("t-4.2", "TASK 4.2: Per-fish sell (individual, not just sell-all)", "sell-individual", 1,
     "PRD INV-03: 'Players can sell eligible fish for immediate currency.' Add RequestSellFish "
     "remote taking instanceId. Server validates ownership, removes fish, adds BaseSellValue to "
     "Coins. Keeps existing 'SellAll' as a convenience but adds per-fish. PRD UX: show sell value "
     "per fish in inventory panel."),

    ("t-4.3", "TASK 4.3: Per-fish store to aquarium (individual)", "store-individual", 1,
     "PRD INV-04: 'move eligible fish from inventory into their aquarium.' RequestStoreFish remote "
     "taking instanceId. Server validates ownership + capacity (PRD INV-05). Moves FishInstance from "
     "carried[] to Aquarium.StoredFish[]. Keeps 'StoreAll' convenience."),

    ("t-4.4", "TASK 4.4: Client inventory panel UI", "inventory-ui", 1,
     "Client panel showing carried fish as a list/grid. Each entry: fish icon (rarity color), "
     "species name, rarity label, sell value, two buttons: SELL and STORE. PRD INV-02: displays "
     "species, rarity, sell value, store eligibility. Mobile-friendly touch targets. Replaces "
     "current single 'STORE (n)' button."),
]

for key, title, slug, pri, desc in t4:
    ac = "- [ ] Per-fish operations server-validated\n- [ ] No duplication/overflow exploits\n- [ ] UI shows all required fish attributes\n- [ ] Mobile-usable"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-inventory", None))
    deps.append((key, "epic-inventory", "parent-child"))

deps += [
    ("epic-inventory", "epic-foundation", "blocks"),
    ("t-4.2", "t-4.1", "blocks"),
    ("t-4.3", "t-4.1", "blocks"),
    ("t-4.4", "t-4.2", "blocks"),
    ("t-4.4", "t-4.3", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 5: AQUARIUM & INCOME — Claimable Income + Display
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-aquarium",
    "EPIC 5: Aquarium & Income Rework — Claimable Income",
    "epic", 1, "aquarium-income-rework",
    "PRD AQUA-01..AQUA-09. Current code auto-adds income to cash every tick. PRD AQUA-05 requires "
    "'claim accumulated aquarium income through a visible interaction or UI button.' This is a "
    "significant behavior change: income accrues to UnclaimedIncome pool, player must claim it.\n\n"
    "PRD income model: 'Each stored fish has a fixed income-per-minute value. Server calculates "
    "earned income from elapsed server time and stored fish, then caps unclaimed earnings.'\n\n"
    "Also: stored fish now FishInstance records (not rarity indexes), capacity upgrades (2.5), "
    "display per DEC-6. FILES: src/server/AquariumService.lua, src/client/init.client.lua" + EPOCH,
    None, None, None))

t5 = [
    ("t-5.1", "TASK 5.1: Accrue income to UnclaimedIncome pool (not auto-cash)", "income-pool", 1,
     "PRD AQUA-05. Change income loop: instead of session.cash += income, accumulate to "
     "session.Aquarium.UnclaimedIncome. Calculate from elapsed time × sum(IncomePerMinute of "
     "StoredFish) / 60. Cap at MAX_UNCLAIMED (prevent extreme accumulation, PRD income model note). "
     "Server stores LastIncomeTimestamp for accurate elapsed calculation."),

    ("t-5.2", "TASK 5.2: Claim income interaction + RequestClaimIncome remote", "claim-income", 1,
     "PRD AQUA-05. New RequestClaimIncome remote. Server validates, transfers UnclaimedIncome → "
     "Coins, resets pool, updates LastIncomeTimestamp. Client shows a 'CLAIM $X' button when "
     "UnclaimedIncome > 0. Analytics event: income_claimed."),

    ("t-5.3", "TASK 5.3: Income calculation from FishInstance IncomePerMinute", "income-calc", 1,
     "PRD AQUA-03: 'Each stored fish contributes passive income based on rarity and species.' "
     "Sum IncomePerMinute across all StoredFish FishInstances (not flat rarity indexes). "
     "Apply dock upgrade multiplier (2.6) if applicable. Recompute on store/sell/steal events."),

    ("t-5.4", "TASK 5.4: Aquarium capacity enforcement from upgrade tier", "capacity-enforce", 1,
     "PRD AQUA-06: 'capacity limits number or total weight/value.' Use Aquarium.UpgradeLevel → "
     "capacity from AquariumUpgradeDefinitions (2.5). Enforce on store (4.3) and steal receipt. "
     "Display current/max in aquarium UI."),

    ("t-5.5", "TASK 5.5: Remove individual stored fish + sell (AQUA-09)", "remove-stored-fish", 1,
     "PRD AQUA-09: 'Players can remove a stored fish and sell it, subject to raid-state restrictions.' "
     "Allow removing a FishInstance from aquarium to inventory or direct-sell. During active lock or "
     "raid protection, restrict removal (prevent pre-raid hiding of fish)."),

    ("t-5.6", "TASK 5.6: Aquarium display per DEC-6 (curated subset + counts)", "aquarium-display", 1,
     "PRD AQUA-02 + DEC-6. Show curated subset of highest-rarity fish as physical models "
     "(extend current maxVisibleFish cap). Add status panel showing full counts by rarity tier. "
     "Visual: fish colored by rarity, positioned in water volume. Performance: pool models, no "
     "unlimited spawning (PRD perf table)."),

    ("t-5.7", "TASK 5.7: Aquarium UI shows capacity, lock, income rate, claimable", "aquarium-ui", 1,
     "PRD AQUA-08: 'clearly displays capacity, lock status, stored value, income rate, claimable income.' "
     "Update aquarium panel (client) to show all five data points. Lock status with timer. "
     "Income rate (per min). Claimable amount with CLAIM button (5.2)."),
]

for key, title, slug, pri, desc in t5:
    ac = "- [ ] Income accrues to claimable pool (not auto-cash)\n- [ ] Capacity enforced\n- [ ] UI shows all AQUA-08 data points\n- [ ] No income exploit path"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-aquarium", None))
    deps.append((key, "epic-aquarium", "parent-child"))

deps += [
    ("epic-aquarium", "epic-foundation", "blocks"),
    ("epic-aquarium", "dec-income", "blocks"),
    ("epic-aquarium", "dec-display", "blocks"),
    ("t-5.2", "t-5.1", "blocks"),
    ("t-5.3", "t-1.2", "blocks"),
    ("t-5.4", "t-2.5", "blocks"),
    ("t-5.5", "t-4.1", "blocks"),
    ("t-5.6", "dec-display", "blocks"),
    ("t-5.7", "t-5.2", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 6: ECONOMY & UPGRADES — Shop System
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-economy",
    "EPIC 6: Economy & Upgrade System",
    "epic", 1, "economy-upgrade-system",
    "PRD ECON-01..ECON-07. Expand ShopService beyond rod+bait to include aquarium capacity upgrades "
    "and dock upgrades. All server-authoritative (ECON-05). Upgrade prices support first purchase "
    "in opening session (ECON-06). Never sell combat power/raid success for Robux (ECON-07).\n\n"
    "Current ShopService: sequential rod/bait tier purchase. Expand to 4 categories per PRD.\n"
    "FILES: src/server/ShopService.lua → src/server/UpgradeService.lua (rename/expand)" + EPOCH,
    None, None, None))

t6 = [
    ("t-6.1", "TASK 6.1: Generalize purchase to all upgrade categories", "generalize-purchase", 1,
     "Expand BuyItem remote to handle kind in {rod, bait, aquarium, dock}. Each has its own "
     "definition table (2.3-2.6) and cost curve. Server validates: ownership, sufficient Coins, "
     "sequential tier requirement, applies upgrade to profile. PRD ECON-04: 'every upgrade has a "
     "visible effect.'"),

    ("t-6.2", "TASK 6.2: Bait purchase flow per DEC-5", "bait-purchase", 1,
     "If DEC-5 = reusable tiers: bait purchases upgrade tier like rods. If consumable: purchases "
     "add to BaitInventory quantity with a selected active bait. Implement per decision outcome. "
     "PRD: bait 'modifies target species and rarity probabilities.'"),

    ("t-6.3", "TASK 6.3: Aquarium capacity upgrade purchase", "aquarium-upgrade-buy", 1,
     "Purchase increases Aquarium.UpgradeLevel → capacity from 2.5. Server updates profile, "
     "updates income recalculation (5.3). Visual: aquarium grows or gets more display slots."),

    ("t-6.4", "TASK 6.4: Dock upgrade purchase + income multiplier", "dock-upgrade-buy", 1,
     "Purchase increases Dock.UpgradeLevel. Applies income multiplier (2.6) to aquarium income "
     "calculation (5.3). Unlocks cosmetic décor on dock visual. Server-authoritative (ECON-05)."),

    ("t-6.5", "TASK 6.5: Shop UI — 4 categories, owned/locked/affordable states", "shop-ui-categories", 1,
     "Expand client shop panel to 4 sections (Rod, Bait, Aquarium, Dock). Each item shows cost, "
     "effect description, and state: OWNED (current tier or below), AFFORDABLE (next tier, enough "
     "cash), LOCKED (future tier or insufficient cash). PRD ECON-06: first purchase reachable in "
     "first session — validate cost curve."),
]

for key, title, slug, pri, desc in t6:
    ac = "- [ ] All 4 upgrade categories purchasable\n- [ ] Server-authoritative, no free upgrades\n- [ ] Coins correctly deducted\n- [ ] Upgrades persist (DataStore)\n- [ ] UI states correct"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-economy", None))
    deps.append((key, "epic-economy", "parent-child"))

deps += [
    ("epic-economy", "epic-content", "blocks"),
    ("t-6.1", "t-2.3", "blocks"),
    ("t-6.2", "dec-bait", "blocks"),
    ("t-6.2", "t-2.4", "blocks"),
    ("t-6.3", "t-2.5", "blocks"),
    ("t-6.4", "t-2.6", "blocks"),
    ("t-6.5", "t-6.1", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 7: COLLECTION BOOK
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-collection",
    "EPIC 7: Collection Book",
    "epic", 2, "collection-book",
    "PRD COLL-01..COLL-06. Entirely new system. Players discover species by catching them; "
    "the collection book records discoveries and shows progress. Completing milestones awards "
    "non-essential rewards (Coins, titles, décor).\n\n"
    "This is the long-term goal system (PRD: 'clear aspirational objectives and progression paths'). "
    "Requires FishDefinitions (2.1) and Collection sub-table in PlayerProfile (1.1).\n"
    "FILES: src/server/CollectionService.lua (new), src/client/init.client.lua" + EPOCH,
    None, None, None))

t7 = [
    ("t-7.1", "TASK 7.1: Track species discovery on catch", "track-discovery", 2,
     "PRD COLL-06: 'progress persists.' On successful catch (3.4), mark SpeciesId in "
     "Collection.DiscoveredSpecies if not already discovered. Fire analytics event. "
     "Notify player on first discovery ('New species discovered: X!')."),

    ("t-7.2", "TASK 7.2: Collection book server module + remote", "collection-service", 2,
     "New CollectionService module. RequestCollection remote returns discovered/undiscovered "
     "status per species. PRD COLL-04: 'undiscovered fish conceal precise catch data.' "
     "Server sends: discovered species with full data, undiscovered with only rarity + silhouette."),

    ("t-7.3", "TASK 7.3: Collection book client UI", "collection-ui", 2,
     "PRD COLL-01, COLL-02. Book panel accessible from HUD. Grid of species grouped by zone/rarity. "
     "Discovered: name, rarity color, visual, flavor text (COLL-03). Undiscovered: silhouette + "
     "'???' with rarity hint. Progress bar 'X / Y species discovered.'"),

    ("t-7.4", "TASK 7.4: Collection milestones + rewards", "collection-milestones", 2,
     "PRD COLL-05: 'Completing milestones awards non-essential rewards.' Define milestones: "
     "discover 5/10/15/20 species, discover all of a rarity, discover all in a zone. "
     "Rewards: Coins, titles (string), dock décor unlocks. Claimable via Collection panel. "
     "Track MilestonesClaimed[] to prevent re-claiming."),
]

for key, title, slug, pri, desc in t7:
    ac = "- [ ] Discoveries persist\n- [ ] Book shows discovered + undiscovered correctly\n- [ ] Milestones award rewards once\n- [ ] No exploit to unlock undiscovered data"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-collection", None))
    deps.append((key, "epic-collection", "parent-child"))

deps += [
    ("epic-collection", "epic-content", "blocks"),
    ("epic-collection", "epic-foundation", "blocks"),
    ("t-7.1", "t-3.4", "blocks"),
    ("t-7.2", "t-7.1", "blocks"),
    ("t-7.3", "t-7.2", "blocks"),
    ("t-7.4", "t-7.2", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 8: RAID & DEFENSE — Scheduled Opt-In Raids
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-raid",
    "EPIC 8: Raid & Defense System — Scheduled Opt-In",
    "epic", 1, "raid-defense-system",
    "PRD PVP-01..PVP-12 + Recommended V1 Raid Rule. MASSIVE rework of the current always-on theft.\n\n"
    "Current: any player can steal from any unlocked aquarium anytime (50% chance, 20s cooldown). "
    "PRD demands: scheduled raid windows (every 20-30 min, last 5 min), opt-in via Raid Waters pier "
    "or dock flag, new-player protection (PVP-01), lock tools, cooldowns, per-victim immunity, "
    "legendary protection, capped losses, server-only validation.\n\n"
    "This is the 'deliberate spice, not the entire product' — bounded tension that creates social "
    "stories without griefing. FILES: src/server/RaidService.lua (new, replaces steal logic in "
    "AquariumService.handleSteal)" + EPOCH,
    None, None, None))

t8 = [
    ("t-8.1", "TASK 8.1: RaidService server module — window scheduler", "raid-scheduler", 1,
     "PRD raid rule: 'Raid windows occur every 20-30 minutes and last 5 minutes.' Server runs a "
     "global raid-window scheduler. Broadcasts window-open/window-close events to all clients "
     "(client shows countdown / 'RAID WATERS OPEN' indicator). Only during window can raids occur. "
     "PRD PVP-02: 'raid only during a clearly labeled raid window or after explicitly opting in.'"),

    ("t-8.2", "TASK 8.2: Raid opt-in system (RaidOptIn flag + Raid Waters pier)", "raid-optin", 1,
     "PRD: 'opt in by entering a marked Raid Waters pier or enabling a dock flag before window closes.' "
     "Add RaidOptIn boolean to Aquarium profile (1.1). Physical Raid Waters zone in harbor + "
     "dock flag toggle. Only opted-in aquariums can be targeted (PVP-02). RequestToggleRaidOptIn remote."),

    ("t-8.3", "TASK 8.3: New-player protection gate (per DEC-4)", "new-player-protection", 1,
     "PRD PVP-01: 'unavailable to new players until onboarding + progression threshold.' Per DEC-4: "
     "double gate — (1) progression: first aquarium upgrade OR 10 catches, (2) raid window opt-in. "
     "Check Onboarding flags + profile stats before allowing raid participation (attack or being targeted)."),

    ("t-8.4", "TASK 8.4: Lock system rework (earned resource / limited free uses)", "lock-rework", 1,
     "PRD PVP-03: 'activate a temporary aquarium lock using an earned in-game resource, cooldown, "
     "or limited free uses.' Current: lock 60s, cooldown 120s, always available. Rework: limited "
     "free uses per session (e.g., 3) + cooldown. Lock visible on dock, UI, raid-selection (PVP-04)."),

    ("t-8.5", "TASK 8.5: Raid attempt flow + outcome logic (per DEC-2, DEC-3)", "raid-flow", 1,
     "PRD PVP-05, PVP-10. Raid attempt flow per DEC-2 (hybrid timing): attacker selects target → "
     "short timing element → server validates + resolves. Outcome per DEC-3 (individual fish): "
     "transfer one eligible FishInstance (not Legendary if protected). Server exclusively validates "
     "eligibility, lock, target state, cooldowns, theft outcome, transfer (PVP-10)."),

    ("t-8.6", "TASK 8.6: Attacker cooldown + per-victim cooldown (PVP-06, PVP-07)", "raid-cooldowns", 1,
     "PVP-06: 'Raids have a cooldown for the attacker.' PVP-07: 'cannot repeatedly target same "
     "defender within defined window.' Track PvP.LastRaidTimestamp (attacker cooldown), "
     "PvP.RecentTargetUserIds[] (per-victim cooldown, e.g., can't re-hit same player for 10 min)."),

    ("t-8.7", "TASK 8.7: Defender immunity period after successful loss (PVP-06)", "defender-immunity", 1,
     "PRD raid rule: 'defender receives a 10-15 minute immunity period after a successful loss.' "
     "Set Aquarium.RaidProtectionUntilTimestamp on successful raid. During immunity, aquarium cannot "
     "be targeted even if opted-in. PRD PVP-06: 'a protection period for the defender.'"),

    ("t-8.8", "TASK 8.8: Legendary fish raid protection (PVP-08)", "legendary-protection", 1,
     "PRD PVP-08: 'High-rarity fish may have additional protection, raid limits, or insurance.' "
     "PRD raid rule: 'Legendary fish either non-stealable or much lower raid probability.' "
     "Set IsRaidProtected on Legendary FishInstances (1.2). Raid target selection excludes or "
     "heavily down-weights protected fish."),

    ("t-8.9", "TASK 8.9: Loss caps per time period (PVP-12)", "loss-caps", 1,
     "PRD PVP-12: 'Raid rewards and losses are capped per time period.' Track fish lost per defender "
     "per raid window. Cap at N fish or X% value per window. Prevents aquarium emptying even across "
     "multiple attackers (PVP-05: 'never an entire aquarium')."),

    ("t-8.10", "TASK 8.10: Defender notification + recovery info (PVP-09)", "defender-notify", 1,
     "PRD PVP-09: 'Defenders receive a clear notification after a completed raid, including what was "
     "taken and available recovery/protection actions.' Notify victim with attacker name, species "
     "stolen, and prompt to lock aquarium or claim immunity. Non-panic-inducing visual (PRD UX)."),

    ("t-8.11", "TASK 8.11: Safe harbor area with PvP disabled (PVP-11)", "safe-harbor", 2,
     "PRD PVP-11: 'PvP can be disabled in a clearly marked safe harbor/server area.' Designate "
     "plaza/central area as safe zone — aquariums there (if any) or players there cannot raid/be raided. "
     "Early-balancing safety valve. May be minimal V1 (just the plaza, no aquariums there)."),

    ("t-8.12", "TASK 8.12: Raid UI — opt-in toggle, window countdown, target selection", "raid-ui", 1,
     "Client UI: raid window countdown indicator (global), opt-in toggle button, raid target "
     "selection panel (shows opted-in enemy docks with lock status), raid attempt button. "
     "PRD UX: 'raid warnings prominent but not panic-inducing.' Lock icon, timer, alert buoy visuals."),
]

for key, title, slug, pri, desc in t8:
    ac = "- [ ] Server validates all raid logic (PVP-10)\n- [ ] No griefing path (new players protected, windows enforced)\n- [ ] One raid cannot empty aquarium\n- [ ] Defender immunity works\n- [ ] Client can opt-in/out clearly"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-raid", None))
    deps.append((key, "epic-raid", "parent-child"))

deps += [
    ("epic-raid", "epic-aquarium", "blocks"),
    ("epic-raid", "epic-foundation", "blocks"),
    ("t-8.3", "dec-protection", "blocks"),
    ("t-8.4", "t-1.1", "blocks"),
    ("t-8.5", "dec-raid-model", "blocks"),
    ("t-8.5", "dec-transfer", "blocks"),
    ("t-8.5", "t-8.1", "blocks"),
    ("t-8.5", "t-8.2", "blocks"),
    ("t-8.5", "t-8.3", "blocks"),
    ("t-8.5", "t-8.4", "blocks"),
    ("t-8.6", "t-8.5", "blocks"),
    ("t-8.7", "t-8.5", "blocks"),
    ("t-8.8", "t-1.2", "blocks"),
    ("t-8.9", "t-8.5", "blocks"),
    ("t-8.10", "t-8.5", "blocks"),
    ("t-8.12", "t-8.5", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 9: ONBOARDING — First Five Minutes
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-onboarding",
    "EPIC 9: Onboarding & First Five Minutes",
    "epic", 1, "onboarding-first-five",
    "PRD 'First Five Minutes' section (lines 65-80) + Onboarding profile (1.1). Contextual "
    "onboarding, not a tutorial wall. Track progression flags. Gate PvP behind onboarding (8.3).\n\n"
    "First-session success: catch ≥1 fish, store ≥1 fish, observe income, understand next upgrade. "
    "FILES: src/server/OnboardingService.lua (new), src/client/init.client.lua" + EPOCH,
    None, None, None))

t9 = [
    ("t-9.1", "TASK 9.1: OnboardingService + progression flags tracking", "onboarding-service", 1,
     "Track Onboarding flags (1.1): HasCompletedIntro, HasCaughtFirstFish, HasStoredFirstFish, "
     "HasClaimedIncome, HasSeenRaidExplanation. Update flags on relevant events (catch, store, "
     "claim, raid window first seen). These gate PvP (8.3) and drive contextual prompts."),

    ("t-9.2", "TASK 9.2: Contextual prompts (no tutorial wall)", "contextual-prompts", 1,
     "PRD: 'contextual prompts rather than long tutorials.' Show short directional prompts based "
     "on Onboarding flags: 'Cast into the glowing zone!' (before first cast), 'Store your fish!' "
     "(after first catch), 'Claim your income!' (when income available), 'Raids are optional — "
     "learn more' (when first raid window appears). Dismissible, non-blocking."),

    ("t-9.3", "TASK 9.3: Starter rod + bait auto-grant", "starter-grant", 1,
     "PRD first-five #3: 'receives a free basic rod and starter bait automatically.' On first join, "
     "grant StarterRod + starter bait tier in Equipment. Current code starts with rodLevel=1, "
     "baitLevel=1 — formalize as explicit grant + OwnedRodIds tracking."),

    ("t-9.4", "TASK 9.4: Sell-vs-store comparison prompt", "sell-store-prompt", 1,
     "PRD UX: 'store versus sell decision must show direct comparison.' On first catch (or always), "
     "show comparison: 'Sell now for $X' vs 'Store for $Y/min income.' Helps new players make "
     "informed choice (PRD user story). Contextual, not forced every time."),
]

for key, title, slug, pri, desc in t9:
    ac = "- [ ] Flags tracked and persist\n- [ ] Prompts contextual, dismissible\n- [ ] Starter items granted on first join\n- [ ] First-session success condition achievable"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-onboarding", None))
    deps.append((key, "epic-onboarding", "parent-child"))

deps += [
    ("epic-onboarding", "epic-foundation", "blocks"),
    ("t-9.2", "t-9.1", "blocks"),
    ("t-9.3", "t-1.1", "blocks"),
    ("t-9.4", "t-3.4", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 10: SECURITY & ANTI-EXPLOIT
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-security",
    "EPIC 10: Security & Anti-Exploit Hardening",
    "epic", 0, "security-antiexploit",
    "PRD security/anti-exploit section (lines 477-484). The current code already has good "
    "server-authoritative patterns (nil guards, bounds checks, capacity re-checks, distance "
    "validation). This epic formalizes it into an AntiExploitService + adds rate limiting, "
    "suspicious-action tracking, and audit logging.\n\n"
    "WHY P0: exploits destroy game economies and trust. PRD: 'No client can change currency, "
    "rarity, inventory, or raid result.' All valuable transactions server-confirmed." + EPOCH,
    None, None, None))

t10 = [
    ("t-10.1", "TASK 10.1: Rate limiting on all remotes", "rate-limiting", 0,
     "PRD: 'Remote events are rate-limited.' Implement per-player rate limiting: cast, store, sell, "
     "buy, claim, raid. Track call timestamps; reject if exceeding threshold (e.g., cast > 10/sec "
     "is impossible). Prevents spam exploits. Centralize in AntiExploitService.checkRate(player, action)."),

    ("t-10.2", "TASK 10.2: AntiExploitService — suspicious action tracking", "exploit-tracking", 0,
     "PRD: 'Server tracks suspicious actions: impossible casting rate, impossible proximity, "
     "excessive remote calls, invalid fish IDs, repeated invalid raid targets.' Log + flag accounts. "
     "Threshold-based alerting. Not auto-ban (false positives) but audit trail for review."),

    ("t-10.3", "TASK 10.3: Audit logging for high-value transactions", "audit-logging", 0,
     "PRD: 'Audit logs should record high-value catches, purchases, storage changes, and raid "
     "transfers.' Server-side log (console or file) for: Legendary catches, all purchases, raid "
     "transfers (attacker, victim, species, value). For debugging and balancing."),

    ("t-10.4", "TASK 10.4: Transaction atomicity (no dup on partial failure)", "transaction-atomic", 0,
     "PRD persistence: 'Prevent data-loss duplication by treating transfer and raid outcomes as "
     "atomic server-side transactions.' Ensure raid fish transfer + both profile updates happen "
     "atomically — if either fails, neither persists. Critical for raid fairness."),

    ("t-10.5", "TASK 10.5: DataStore failure handling — disable transactions gracefully", "ds-failure-ui", 1,
     "PRD persistence: 'During datastore failure, disable affected transaction buttons and show "
     "plain-language message rather than risking inconsistent state.' Detect save failures, "
     "notify client to disable purchase/sell buttons, show 'Saving unavailable—try again.'"),
]

for key, title, slug, pri, desc in t10:
    ac = "- [ ] All remotes rate-limited\n- [ ] Suspicious actions logged\n- [ ] No dup/negative/exploit path exists\n- [ ] Raid transfers atomic\n- [ ] Failure handling user-visible"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-security", None))
    deps.append((key, "epic-security", "parent-child"))

deps += [
    ("epic-security", "epic-foundation", "blocks"),
    ("t-10.4", "t-8.5", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 11: ANALYTICS
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-analytics",
    "EPIC 11: Analytics Instrumentation",
    "epic", 2, "analytics-instrumentation",
    "PRD analytics section (lines 487-513). Track the 24 V1 events listed. Use Roblox analytics "
    "service (AnalyticsService). Feed into first-session funnel + economy/PvP balance monitoring.\n\n"
    "Lower priority than gameplay but required for V1 closed test exit criteria. "
    "FILES: src/server/AnalyticsService.lua (new wrapper)" + EPOCH,
    None, None, None))

t11 = [
    ("t-11.1", "TASK 11.1: AnalyticsService wrapper + event firing", "analytics-service", 2,
     "Wrapper around AnalyticsService:TrackEvent. Fire all 24 PRD events: tutorial_started, "
     "starter_rod_received, first_cast, fish_caught, fish_catch_failed, fish_stored, fish_sold, "
     "income_claimed, upgrade_shop_opened, upgrade_purchased, collection_book_opened, "
     "raid_info_viewed, raid_opt_in_enabled, aquarium_locked, raid_attempted, raid_succeeded, "
     "raid_defended, player_left_before_first_catch, player_left_before_first_upgrade, etc."),

    ("t-11.2", "TASK 11.2: Wire events into all gameplay flows", "analytics-wiring", 2,
     "Instrument each event at the correct code path: catch (3.4), store (4.3), sell (4.2), claim "
     "(5.2), purchase (6.x), discovery (7.1), raid attempt/outcome (8.5), onboarding flags (9.1), "
     "player leave with incomplete funnel. Ensure no duplicate events."),

    ("t-11.3", "TASK 11.3: Success-metric instrumentation", "success-metrics", 2,
     "PRD success measures: time_to_first_cast (<60s), time_to_first_catch (<2min), first stored "
     "fish, first upgrade. Instrument timestamps on first-session events to measure these. "
     "player_left_before_first_catch / first_upgrade events for churn analysis."),
]

for key, title, slug, pri, desc in t11:
    ac = "- [ ] All 24 events fire correctly\n- [ ] No duplicate events\n- [ ] Timestamps recorded for funnel metrics\n- [ ] Events visible in Roblox analytics dashboard"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-analytics", None))
    deps.append((key, "epic-analytics", "parent-child"))

deps += [
    ("t-11.2", "t-11.1", "blocks"),
    ("t-11.3", "t-11.1", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 12: CROSS-CUTTING — Remotes refactor, persistence, performance
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-cross",
    "EPIC 12: Cross-Cutting — Remotes, Persistence, Performance",
    "epic", 1, "cross-cutting-infra",
    "Infrastructure work that spans all epics: refactor Remotes to match PRD naming, harden "
    "persistence (save on checkpoints, retry, BindToClose), and performance pass (pooled visuals, "
    "network replication scope, mobile UI).\n\n"
    "FILES: src/server/Remotes.lua, src/server/DataManager.lua, src/server/StateSync.lua" + EPOCH,
    None, None, None))

t12 = [
    ("t-12.1", "TASK 12.1: Refactor Remotes to PRD naming convention", "remotes-refactor", 1,
     "PRD server modules list (lines 415-426): RequestCast, SubmitCatchInput, RequestStoreFish, "
     "RequestSellFish, RequestClaimIncome, RequestPurchaseUpgrade, RequestToggleRaidOptIn, "
     "RequestActivateLock, RequestRaidAttempt. Rename existing + add new. Update all references. "
     "Current names (Cast, StoreFish, SellAll, LockAquarium, BuyItem) → PRD names."),

    ("t-12.2", "TASK 12.2: Save on meaningful checkpoints (not just autosave+leave)", "checkpoint-saves", 1,
     "PRD persistence: 'save after significant transactions — purchases, catches, storage, sales, "
     "raid outcomes.' Add DataManager.save() calls after each high-value transaction. Batch where "
     "possible to respect platform limits. Current: only autosave (60s) + leave. Add transactional saves."),

    ("t-12.3", "TASK 12.3: Performance — pooled aquarium fish visuals", "perf-pool-visuals", 2,
     "PRD perf table: 'Use pooled/simplified fish visuals; do not spawn unlimited high-detail "
     "animated models.' Pool fish display parts in DockManager.updateAquariumVisual — reuse instances "
     "instead of creating/destroying per update. Cap concurrent animated models server-wide."),

    ("t-12.4", "TASK 12.4: Network replication scope — replicate only nearby data", "network-scope", 2,
     "PRD perf table: 'Replicate only required aquarium state and nearby visual data.' Don't push "
     "all players' full aquarium state to every client. Use Region3 or distance-based filtering for "
     "aquarium display data. StateSync.push currently fires to the owning player only (good) — verify."),

    ("t-12.5", "TASK 12.5: Mobile UI audit — all actions touch-usable", "mobile-ui-audit", 2,
     "PRD perf table: 'All essential actions usable through touch; no hover-only interaction.' "
     "Audit all UI panels (inventory, shop, aquarium, collection, raid) for mobile. Minimum tap "
     "target sizes, no hover-dependent states, viewport scaling for small screens."),
]

for key, title, slug, pri, desc in t12:
    ac = "- [ ] Remotes match PRD naming\n- [ ] Saves fire on transactions\n- [ ] No perf regression under load\n- [ ] Mobile fully usable"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-cross", None))
    deps.append((key, "epic-cross", "parent-child"))

deps += [
    ("t-12.2", "t-1.1", "blocks"),
    ("t-12.3", "t-5.6", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EPIC 13: RELEASE — Closed Test & Launch Prep
# ═══════════════════════════════════════════════════════════════════════════════
beads.append(("epic-release",
    "EPIC 13: Release — Closed V1 Test & Launch Prep",
    "epic", 2, "release-prep",
    "PRD release plan (lines 593-631). Internal prototype exit criteria → closed V1 test exit "
    "criteria → public launch. This epic tracks the verification and polish work needed to ship.\n\n"
    "NOT implementation — these are QA, balance, and launch-readiness tasks." + EPOCH,
    None, None, None))

t13 = [
    ("t-13.1", "TASK 13.1: Closed V1 test — full playthrough verification", "closed-test-verify", 2,
     "PRD closed test exit criteria: 'New players understand the loop, raid losses do not create "
     "disproportionate churn, and no obvious duplication or remote-event exploit exists.' "
     "Full playthrough: new player joins → catches → stores → earns → upgrades → raids → defends. "
     "Verify all PRD acceptance criteria (lines 554-591)."),

    ("t-13.2", "TASK 13.2: Economy balance pass — first purchase timing", "economy-balance", 2,
     "PRD ECON-06: 'first meaningful purchase within opening session.' Playtest and tune cost "
     "curves so a new player can afford first upgrade in 5-10 min of play. Validate income rates "
     "vs costs. Adjust EconomyConfig (2.7) based on playtest data."),

    ("t-13.3", "TASK 13.3: Raid balance — loss churn check", "raid-balance", 2,
     "PRD: 'investigating whether players leave immediately after losses and rebalance protection "
     "if necessary.' Playtest raid frequency, loss impact, immunity timing. Tune lock/cooldown/"
     "immunity values so losses feel fair, not punishing."),

    ("t-13.4", "TASK 13.4: Visual polish — cozy harbor aesthetic pass", "visual-polish", 2,
     "PRD UX/visual: 'cozy harbor aquarium first, heist second.' Lighting, water, dock materials, "
     "fish models, rarity cues (not color alone — labels, stars, shape). Raid visuals non-threatening "
     "(lock icon, buoy, not red alarms). Sunset palette."),

    ("t-13.5", "TASK 13.5: Game icon, thumbnail, description for launch", "launch-assets", 3,
     "PRD public launch: 'thumbnail/icon/game description reflecting cozy aquarium fishing.' "
     "Create game icon, thumbnail, description. Limited launch event or collection target."),
]

for key, title, slug, pri, desc in t13:
    ac = "- [ ] All PRD acceptance criteria verified\n- [ ] Balance tuned from playtest\n- [ ] Visual polish complete\n- [ ] Launch assets ready"
    beads.append((key, title, "task", pri, slug, desc, ac, "epic-release", None))
    deps.append((key, "epic-release", "parent-child"))

deps += [
    ("epic-release", "epic-fishing", "blocks"),
    ("epic-release", "epic-inventory", "blocks"),
    ("epic-release", "epic-aquarium", "blocks"),
    ("epic-release", "epic-economy", "blocks"),
    ("epic-release", "epic-raid", "blocks"),
    ("t-13.2", "t-2.7", "blocks"),
    ("t-13.3", "t-8.5", "blocks"),
]

# ═══════════════════════════════════════════════════════════════════════════════
# EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

print(f"=== DEFINED {len(beads)} beads, {len(deps)} dependencies ===")
print("Creating beads...")

created_ids = {}  # key → bead id
failed = []

# Create beads
for key, title, btype, pri, slug, desc, ac, parent_key, labels in beads:
    try:
        # Build full description: desc + acceptance criteria
        full_desc = desc
        if ac:
            full_desc += "\n\n## ACCEPTANCE CRITERIA\n" + ac

        parent_id = created_ids.get(parent_key) if parent_key else None
        bid = create_bead(title, btype, pri, full_desc, parent=parent_id, slug=slug, labels=labels)
        created_ids[key] = bid
        print(f"  ✓ {key:16s} → {bid}  [{btype}]  {title[:60]}")
        time.sleep(0.05)  # be gentle to the DB
    except Exception as e:
        failed.append((key, str(e)))
        print(f"  ✗ {key:16s} FAILED: {e}")

print(f"\n=== Created {len(created_ids)}/{len(beads)} beads, {len(failed)} failed ===")

if failed:
    print("FAILURES:")
    for k, e in failed:
        print(f"  {k}: {e}")

# Add dependencies
print(f"\nWiring {len(deps)} dependencies...")
dep_ok = 0
dep_fail = 0
for from_key, to_key, dep_type in deps:
    fid = created_ids.get(from_key)
    tid = created_ids.get(to_key)
    if not fid or not tid:
        print(f"  ✗ SKIP {from_key}→{to_key}: missing id ({fid=}, {tid=})")
        dep_fail += 1
        continue
    try:
        add_dep(fid, tid, dep_type)
        dep_ok += 1
        time.sleep(0.03)
    except Exception as e:
        # Dependencies may already exist if parent was used — that's fine
        if "already" in str(e).lower() or "duplicate" in str(e).lower():
            dep_ok += 1
        else:
            print(f"  ✗ DEP {from_key}({fid})→{to_key}({tid}): {e}")
            dep_fail += 1

print(f"\n=== Wired {dep_ok} dependencies, {dep_fail} failed ===")
print("\nDONE. Summary:")
print(f"  Beads created: {len(created_ids)}")
print(f"  Dependencies:  {dep_ok}")
print(f"\nID mapping saved to scripts/bead_id_map.json")

# Save mapping for reference
with open("scripts/bead_id_map.json", "w") as f:
    json.dump(created_ids, f, indent=2)

print("\nFirst 5 IDs:")
for k, v in list(created_ids.items())[:5]:
    print(f"  {k}: {v}")
