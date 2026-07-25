-- Proof for harborheist-hbyz: cross-session raid cooldown enforcement (PVP-06/07).
-- Two layers, mirroring the implementation:
--   1. Bridge math: persisted os.time() mirrors -> session os.clock() fields
--      must yield the CORRECT remaining cooldown (cooldown - elapsed), must
--      NOT seed when expired, and the write-side prune must bound the map.
--   2. Source contracts: the wiring points that make this actually run
--      (init.server call site AFTER DataManager.load, write-side mirror,
--      sanitize block, PlayerProfile default, stale comment removed).
--
-- Run: lune run test/_hbyz_cooldown_persist_proof.luau

local fs = require("@lune/fs")

-- ---- Layer 1: wall->clock bridge math (mirror of onSessionLoaded + isAttackerOnCooldown) ----
local RAIDER_COOLDOWN = 6 * 60 -- GameConfig.Raid.raiderCooldownSeconds
local PER_VICTIM = 30 * 60 -- GameConfig.Raid.perVictimCooldownSeconds

local function seedAttacker(lastRaidTs, nowWall, clock)
	local elapsed = nowWall - lastRaidTs
	if lastRaidTs > 0 and elapsed >= 0 and elapsed < RAIDER_COOLDOWN then
		return clock - elapsed
	end
	return nil
end

local function attackerRemaining(raidAttackLastAt, clock)
	local last = raidAttackLastAt or 0
	local cooldownEnd = last + RAIDER_COOLDOWN
	if cooldownEnd > clock then
		return math.ceil(cooldownEnd - clock)
	end
	return 0
end

-- Case 1: raid 120s ago, rejoin now -> 240s of cooldown must remain.
local nowWall = 1_000_000
local clock = 55.0 -- arbitrary os.clock() value at load time
local seed = seedAttacker(nowWall - 120, nowWall, clock)
assert(seed ~= nil, "active mirror must seed")
local rem = attackerRemaining(seed, clock)
print(string.format("=== Attacker bridge: elapsed=120s -> remaining=%ds (expect 240) ===", rem))
assert(rem == 240, "remaining must equal cooldown - elapsed")

-- Case 2: raid 400s ago (> 360s cooldown) -> expired, no seed. The security
-- guarantee is "no seed"; the read-side then behaves EXACTLY as it does for a
-- never-raided player (both nil). NOTE: production isAttackerOnCooldown has a
-- pre-existing quirk — (nil or 0) + cooldown reads as on-cooldown while
-- os.clock() < raiderCooldownSeconds — benign because the first raid window
-- opens 20-30 min in (clock >> cooldown by then). Out of scope for hbyz.
local seedExpired = seedAttacker(nowWall - 400, nowWall, clock)
assert(seedExpired == nil, "expired mirror must NOT seed")
assert(
	attackerRemaining(seedExpired, clock) == attackerRemaining(nil, clock),
	"expired mirror must read identically to a never-raided player"
)

-- Case 3: never raided (ts = 0) -> no seed.
assert(seedAttacker(0, nowWall, clock) == nil, "zero mirror must NOT seed")

-- Case 4: per-victim bridge (mirror of onSessionLoaded per-victim loop).
local victimTs = nowWall - 600 -- hit this victim 10 min ago
local remaining = PER_VICTIM - (nowWall - victimTs)
assert(remaining == 1200, "per-victim remaining should be 1200s")
local victimExpiry = clock + remaining
assert(victimExpiry - clock == 1200, "session expiry must sit 1200s ahead of load clock")

-- Case 5: write-side prune bounds the map (mirror of commitAttackerCooldowns prune).
local map = { [111] = nowWall - 100, [222] = nowWall - (PER_VICTIM + 5), [333] = nowWall - 10 }
for uid, ts in pairs(map) do
	if (nowWall - ts) >= PER_VICTIM then
		map[uid] = nil
	end
end
assert(map[111] and map[333] and map[222] == nil, "prune must drop only expired entries")

-- ---- Layer 2: source contracts ----
-- lune runs with CWD = project root (scripts/run_tests.sh cds there).
local raid = fs.readFile("src/server/RaidService.lua")
local init = fs.readFile("src/server/init.server.lua")
local dm = fs.readFile("src/server/DataManager.lua")
local pp = fs.readFile("src/shared/PlayerProfile.lua")

assert(raid:find("function RaidService.onSessionLoaded", 1, true), "RaidService.onSessionLoaded missing")
assert(raid:find("session.raidAttackLastAt = os.clock() - elapsed", 1, true), "attacker bridge seed missing")
assert(raid:find("pvp.RecentTargetTimestamps[targetUserId] = now", 1, true), "write-side per-victim mirror missing")
assert(not raid:find("These reset on rejoin", 1, true), "stale 'reset on rejoin' comment must be gone")

local loadPos = init:find("local session = DataManager.load(player)", 1, true)
local seedPos = init:find("RaidService.onSessionLoaded(session)", 1, true)
assert(loadPos and seedPos, "init.server must load then seed")
assert(seedPos > loadPos, "onSessionLoaded MUST run after DataManager.load (DataStore mirrors)")

assert(dm:find("data.PvP.RecentTargetTimestamps", 1, true), "sanitize must whitelist the mirror map")
assert(dm:find("tonumber(uidKey)", 1, true), "sanitize must coerce DataStore string keys")
assert(pp:find("RecentTargetTimestamps = {},", 1, true), "PlayerProfile default must include the map")

-- Read-side unchanged: cooldown readers still consult only the session fields.
assert(raid:find("local last = (session and session.raidAttackLastAt) or 0", 1, true), "isAttackerOnCooldown read-side changed?")
assert(raid:find("local expiry = cooldowns[targetUserId]", 1, true), "isVictimOnCooldown read-side changed?")

print("=== All hbyz cooldown-persistence proofs passed ===")
