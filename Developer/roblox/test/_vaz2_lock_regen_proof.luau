-- Proof for harborheist-vaz2: per-session lock free-use regen (PVP-03).
-- Layers: (1) regen semantics mirror, (2) source wiring contracts.
--
-- Run: lune run test/_vaz2_lock_regen_proof.luau

local fs = require("@lune/fs")

-- ---- Layer 1: regen semantics (mirror of AquariumService.onSessionLoaded) ----
local LOCK_FREE_USES_MAX = 3 -- GameConfig.Defense.LockFreeUsesMax

local function onSessionLoaded(session)
	if not session then
		return
	end
	local defense = session.profile and session.profile.Defense
	if not defense then
		return
	end
	defense.LockFreeUsesMax = defense.LockFreeUsesMax or LOCK_FREE_USES_MAX
	defense.LockFreeUsesRemaining = defense.LockFreeUsesMax
end

-- Case 1: depleted profile rejoins -> refilled to max.
local s1 = { profile = { Defense = { LockFreeUsesRemaining = 0, LockFreeUsesMax = 3 } } }
onSessionLoaded(s1)
assert(s1.profile.Defense.LockFreeUsesRemaining == 3, "depleted budget must refill to max")

-- Case 2: partially used -> refilled (per-session cadence, not top-up).
local s2 = { profile = { Defense = { LockFreeUsesRemaining = 1, LockFreeUsesMax = 3 } } }
onSessionLoaded(s2)
assert(s2.profile.Defense.LockFreeUsesRemaining == 3, "partial budget must refill to max")

-- Case 3: legacy profile missing LockFreeUsesMax -> max sourced from config.
local s3 = { profile = { Defense = { LockFreeUsesRemaining = 2 } } }
onSessionLoaded(s3)
assert(s3.profile.Defense.LockFreeUsesRemaining == LOCK_FREE_USES_MAX, "missing max must fall back to GameConfig")

-- Case 4: nil session / missing Defense -> no-op, no crash (activate path is the backstop).
onSessionLoaded(nil)
onSessionLoaded({ profile = {} })
print("=== Regen semantics: all 4 cases pass ===")

-- ---- Layer 2: source contracts ----
local aq = fs.readFile("src/server/AquariumService.lua")
local init = fs.readFile("src/server/init.server.lua")

assert(aq:find("function AquariumService.onSessionLoaded", 1, true), "AquariumService.onSessionLoaded missing")
assert(aq:find("defense.LockFreeUsesRemaining = defense.LockFreeUsesMax", 1, true), "reset assignment missing")
assert(not aq:find("regenerate on daily reset (future)", 1, true), "stale 'daily reset (future)' design comment must be gone")
assert(not aq:find("regenerate via daily reset (future bead)", 1, true), "stale activate-path comment must be gone")

local raidSeed = init:find("RaidService.onSessionLoaded(session)", 1, true)
local lockSeed = init:find("AquariumService.onSessionLoaded(session)", 1, true)
local loadPos = init:find("local session = DataManager.load(player)", 1, true)
assert(raidSeed and lockSeed and loadPos, "init.server must wire both session hooks")
assert(lockSeed > loadPos, "lock regen must run after DataManager.load")

-- Doc-comment integrity: the TASK 8.3 block must sit directly above isNewPlayerProtected.
local docTail = init and aq:find("-- selection.\nfunction AquariumService.isNewPlayerProtected", 1, true)
assert(docTail, "TASK 8.3 doc comment must remain attached to isNewPlayerProtected")

print("=== All vaz2 lock-regen proofs passed ===")
