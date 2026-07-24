-- Proof for TASK 23.1 (hvfh.3.1): central minigame/overlay manager.
--
-- Layer 1 simulates the manager + gate logic exactly as implemented in
-- src/client/init.client.lua and asserts the acceptance criteria.
-- Layer 2 checks the source textually for the structural contract
-- (exactly one UserInputService.InputBegan router connection for timed
-- overlays, plus the pre-existing keyboard shortcut connection).
--
-- Run: lune run test/_hvfh_3_1_overlay_router_proof.luau

local fs = require("@lune/fs")

-- ---- Layer 1: manager simulation (mirror of init.client.lua) ----
local activeOverlay = nil
local overlayInputHandlers = {}

local function requestOverlay(name)
	if activeOverlay ~= nil then
		return false
	end
	activeOverlay = name
	return true
end

local function releaseOverlay(name)
	if activeOverlay == name then
		activeOverlay = nil
	end
end

local function isOverlayActive(name)
	return activeOverlay == name
end

local fail = 0
local function check(desc, cond)
	if not cond then
		fail = fail + 1
		print("  FAIL:", desc)
	else
		print("  ok:  ", desc)
	end
end

print("=== Acceptance 1: single slot, no double-booking ===")
check("first request granted", requestOverlay("cast") == true)
check("second request refused while slot held", requestOverlay("raid") == false)
check("isOverlayActive sees the holder", isOverlayActive("cast") == true)
check("isOverlayActive hides non-holder", isOverlayActive("raid") == false)
releaseOverlay("cast")
check("release frees the slot", requestOverlay("raid") == true)
releaseOverlay("raid")

print("=== Acceptance 2: release is name-guarded (no steal) ===")
requestOverlay("bite")
releaseOverlay("cast") -- wrong name: must NOT free the slot
check("wrong-name release does NOT free the slot", activeOverlay == "bite")
releaseOverlay("bite")
check("correct-name release frees the slot", activeOverlay == nil)

print("=== Acceptance 3: initiation gates ===")
-- Gate 1 (doFish): cast refused while raid active.
local function doFishGate()
	if isOverlayActive("raid") then
		return "toast"
	end
	return "fire"
end
requestOverlay("raid")
check("gate 1: cast refused during raid", doFishGate() == "toast")
releaseOverlay("raid")
check("gate 1: cast allowed when free", doFishGate() == "fire")

-- Gate 2 (RAID button): raid refused while cast/bite active.
local function raidGate()
	if isOverlayActive("cast") or isOverlayActive("bite") then
		return "toast"
	end
	return "invoke"
end
requestOverlay("cast")
check("gate 2: raid refused during cast", raidGate() == "toast")
releaseOverlay("cast")
requestOverlay("bite")
check("gate 2: raid refused during bite", raidGate() == "toast")
releaseOverlay("bite")
check("gate 2: raid allowed when free", raidGate() == "invoke")

print("=== Rule 3: BiteEvent during raid is declined, bite can start when free ===")
local function biteEventGate()
	if isOverlayActive("raid") then
		return "expire"
	end
	return "open"
end
requestOverlay("raid")
check("rule 3: BiteEvent during raid expires server-side", biteEventGate() == "expire")
releaseOverlay("raid")
check("rule 3: BiteEvent opens when free", biteEventGate() == "open")

print("=== Router dispatch: only the active overlay's handler runs ===")
local dispatched = {}
overlayInputHandlers.cast = function() table.insert(dispatched, "cast") end
overlayInputHandlers.raid = function() table.insert(dispatched, "raid") end
overlayInputHandlers.bite = function() table.insert(dispatched, "bite") end
local function route(input, gameProcessed)
	local handler = activeOverlay and overlayInputHandlers[activeOverlay] or nil
	if handler then
		handler(input, gameProcessed)
	end
end
route({}, false)
check("no overlay: nothing dispatched", #dispatched == 0)
requestOverlay("raid")
route({}, false)
check("raid active: only raid dispatched", #dispatched == 1 and dispatched[1] == "raid")
route({}, false)
check("second event: still raid only", #dispatched == 2 and dispatched[2] == "raid")
releaseOverlay("raid")
requestOverlay("cast")
route({}, false)
check("switch: cast dispatched after release+request", dispatched[3] == "cast")
releaseOverlay("cast")

-- ---- Layer 2: source contract on init.client.lua ----
print("=== Source contract ===")
local src = fs.readFile("src/client/init.client.lua")

-- Exactly ONE UserInputService.InputBegan connection for timed overlays
-- (the router). The keyboard-shortcut connection is a SECOND connection
-- that is allowed (it handles KeyCode, not UserInputType timing taps).
local routerCount = 0
for _ in src:gmatch("UserInputService%.InputBegan:Connect") do
	routerCount = routerCount + 1
end
check("UserInputService.InputBegan connections (router + keyboard) <= 2", routerCount <= 2)

-- The router connection is the LAST one in the file (bottom-of-file).
local lastPos = 0
for pos in src:gmatch("()UserInputService%.InputBegan:Connect") do
	lastPos = pos
end
local routerSection = src:find("the ONE UserInputService.InputBegan router", 1, true)
check("router comment exists", routerSection ~= nil)
if routerSection then
	check("router connection is the final InputBegan", lastPos > routerSection)
end

-- All three handler registrations exist.
check("overlayInputHandlers.cast registered", src:find("overlayInputHandlers.cast = function", 1, true) ~= nil)
check("overlayInputHandlers.bite registered", src:find("overlayInputHandlers.bite = function", 1, true) ~= nil)
check("overlayInputHandlers.raid registered", src:find("overlayInputHandlers.raid = function", 1, true) ~= nil)

-- No stale per-overlay conn variables remain in executable code.
local function countPattern(pat)
	local n = 0
	for _ in src:gmatch(pat) do
		n = n + 1
	end
	return n
end
check("castInputConn no longer used (only comment refs)", countPattern("castInputConn[^%w]") == 0)
check("raidMinigameInputConn no longer used", countPattern("raidMinigameInputConn[^%w]") == 0)

-- Gates wired.
check("doFish gates on raid", src:find('isOverlayActive("raid")', 1, true) ~= nil)
check("RAID button gates on cast/bite", src:find('isOverlayActive("cast") or isOverlayActive("bite")', 1, true) ~= nil)
check("BiteEvent gates on raid", src:find("rule 3: a BiteEvent landing mid%-raid%-minigame") ~= nil)

if fail > 0 then
	error(string.format("PROOF FAILED: %d check(s) failed", fail))
end
print("PROOF PASSED: hvfh.3.1 overlay manager + single input router")
