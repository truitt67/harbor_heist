1|-- E2E Runner — server-side E2E tests for Harbor Heist.
2|-- Runs as a SERVER SCRIPT in a place booted via RunService:Run().
3|--
4|-- Architecture: the server VM boots (init.server.lua), building the real
5|-- world, docks, remotes, and all services. This script then exercises the
6|-- REAL service APIs directly (DataManager.load, DockManager.claim, etc.)
7|-- against a table-fake player (same pattern as the datamodel TestEZ specs),
8|-- verifying real service behavior end-to-end through the actual DataModel.
9|--
10|-- What this verifies that the pure/datanode specs can't:
11|--   - Real WorldBuilder output (docks exist in workspace)
12|--   - Real DockManager.buildAll + claim against actual Part instances
13|--   - Real service init ordering (all 17 services boot without error)
14|--   - Real AquariumService income loop (task.spawn from real init)
15|--   - Real RaidService scheduler boot
16|--   - Full service interconnection via the production deps table
17|--
18|-- Usage: run-in-roblox --place HarborHeist_e2e.rbxlx --script <stub>
19|
20|local Players = game:GetService("Players")
21|local ServerScriptService = game:GetService("ServerScriptService")
22|local ReplicatedStorage = game:GetService("ReplicatedStorage")
23|
24|-- ============================================================
25|-- Results tracking
26|-- ============================================================
27|local PASS = 0
28|local FAIL = 0
29|local function report(name, passed, detail)
30|	local status = passed and "PASS" or "FAIL"
31|	local line = string.format("[E2E] %s: %s", status, name)
32|	if detail then
33|		line = line .. " — " .. tostring(detail)
34|	end
35|	print(line)
36|	if passed then PASS += 1 else FAIL += 1 end
37|end
38|
39|local function assertEq(name, expected, actual)
40|	if expected == actual then
41|		report(name, true)
42|	else
43|		report(name, false, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
44|	end
45|end
46|
47|local function assertTrue(name, value)
48|	report(name, not not value)
49|end
50|
51|-- ============================================================
52|-- Wait for server boot to complete
53|-- ============================================================
54|print("[E2E] waiting for server boot...")
55|
56|local deadline = os.clock() + 30
57|repeat
58|	task.wait(0.5)
59|until workspace:FindFirstChild("HarborWorld") or os.clock() > deadline
60|
61|local harborWorld = workspace:FindFirstChild("HarborWorld")
62|local remotes = ReplicatedStorage:FindFirstChild("Remotes")
63|
64|if not harborWorld or not remotes then
65|	print("[E2E] FATAL: server did not boot within 30s")
66|	return
67|end
68|
69|task.wait(1) -- settle for service init completion
70|print("[E2E] server booted — HarborWorld + Remotes present")
71|
72|-- ============================================================
73|-- Access the real initialized services
74|-- ============================================================
75|local hh = ServerScriptService:FindFirstChild("HarborHeist")
76|if not hh then
77|	print("[E2E] FATAL: HarborHeist service container not found")
78|	return
79|end
80|
local DataManager = require(hh:WaitForChild("DataManager"))
local DockManager = require(hh:WaitForChild("DockManager"))
local StateSync = require(hh:WaitForChild("StateSync"))
88|
89|print("[E2E] services acquired")
90|
91|-- ============================================================
92|-- Verify server boot integrity
93|-- ============================================================
94|print("[E2E 19.2] === Player Lifecycle ===")
95|
96|-- Boot verification: real world built with docks
97|local dockCount = 0
98|for _, child in ipairs(harborWorld:GetChildren()) do
99|	if child.Name:match("^Dock") then
100|		dockCount += 1
101|	end
102|end
103|assertTrue("19.2 world has docks", dockCount > 0)
104|print("[E2E 19.2] dock count = " .. dockCount)
105|
106|-- Remotes present (real init.server created them)
107|local eventCount, funcCount = 0, 0
108|for _, child in ipairs(remotes:GetChildren()) do
109|	if child:IsA("RemoteEvent") then eventCount += 1
110|	elseif child:IsA("RemoteFunction") then funcCount += 1 end
111|end
112|assertTrue("19.2 remotes built (11 events)", eventCount >= 11)
113|assertTrue("19.2 remotes built (17 functions)", funcCount >= 17)
114|print(string.format("[E2E 19.2] remotes: %d events, %d functions", eventCount, funcCount))
115|
116|-- ============================================================
117|-- Player lifecycle using a fake player + real service APIs
118|-- ============================================================
119|-- We can't create a real Player Instance from server scripts started via
120|-- plugin Run() (CreateLocalPlayer needs LocalUser capability). But the
121|-- services only need a table with UserId/Name/DisplayName/Parent for their
122|-- player reference. We test the REAL service behavior (DataManager.load
123|-- against the real DataStore, DockManager.claim against real dock Parts,
124|-- StateSync.snapshot against the real profile) using this fake.
125|
126|local player = {
127|	UserId = 123456789,
128|	Name = "E2ETestPlayer",
129|	DisplayName = "E2ETestPlayer",
130|	Parent = Players, -- truthy so `if not player.Parent` checks pass
131|	Character = nil,
132|}
133|
134|-- Phase 1: DataManager.load (creates session from DataStore/profile defaults)
135|print("[E2E 19.2] phase=load")
136|local session = DataManager.load(player)
137|assertTrue("19.2 DataManager.load creates session", session ~= nil)
138|
139|if session then
140|	-- Profile fields
141|	assertTrue("19.2 session has profile", session.profile ~= nil)
142|	assertTrue("19.2 session.player is our fake", session.player == player)
143|
144|	-- New player defaults
145|	local profile = session.profile
146|	assertEq("19.2 profile.Coins == 0 (starting cash is 0)", 0, profile.Coins)
147|	print("[E2E 19.2] starting coins = " .. tostring(profile.Coins))
148|	assertEq("19.2 profile.Equipment.EquippedRodLevel == 1", 1, profile.Equipment.EquippedRodLevel)
149|	assertEq("19.2 profile.Equipment.EquippedBaitLevel == 1", 1, profile.Equipment.EquippedBaitLevel)
150|	assertEq("19.2 profile.Aquarium.StoredFish is empty", 0, #profile.Aquarium.StoredFish)
151|	assertEq("19.2 profile.Aquarium.UpgradeLevel == 1", 1, profile.Aquarium.UpgradeLevel)
152|	assertEq("19.2 profile.Aquarium.UnclaimedIncome == 0", 0, profile.Aquarium.UnclaimedIncome)
153|
154|	-- Session runtime fields
155|	assertEq("19.2 session.carried is empty", 0, #session.carried)
156|	assertTrue("19.2 session.casting == false", session.casting == false)
157|	assertTrue("19.2 session.dockIndex == nil (not claimed yet)", session.dockIndex == nil)
158|end
159|
160|-- Phase 2: DockManager.claim (assigns a real dock with Parts)
161|print("[E2E 19.2] phase=dock_claim")
162|local dock = DockManager.claim(player)
163|assertTrue("19.2 DockManager.claim returns dock", dock ~= nil)
164|if dock then
165|	print("[E2E 19.2] claimed dock index = " .. tostring(dock.index))
166|	assertTrue("19.2 dock has owner", dock.owner == player)
167|	assertTrue("19.2 dock has aquarium Part", dock.aquarium ~= nil)
168|	assertTrue("19.2 dock has spawnCFrame", dock.spawnCFrame ~= nil)
169|
170|	-- Verify sign updated (real GUI text on a real Part)
171|	local sign = dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
172|	if sign then
173|		local label = sign:FindFirstChild("OwnerLabel")
174|		if label then
175|			print("[E2E 19.2] dock sign text = " .. tostring(label.Text))
176|			assertTrue("19.2 dock sign updated with player name", label.Text:match("E2ETest") ~= nil)
177|		end
178|	end
179|end
180|
181|-- Phase 3: StateSync.snapshot (real profile → real snapshot)
182|print("[E2E 19.2] phase=snapshot")
183|local snapshot = StateSync.snapshot(session)
184|assertTrue("19.2 StateSync.snapshot returns table", snapshot ~= nil)
185|if snapshot then
186|	assertEq("19.2 snapshot.cash == 0 (starting)", 0, snapshot.cash or -1)
187|	assertEq("19.2 snapshot.rodLevel == 1", 1, snapshot.rodLevel)
188|	assertEq("19.2 snapshot.liveWellCount == 0 (new player)", 0, snapshot.liveWellCount or -1)
189|	assertEq("19.2 snapshot.carried == 0 (new player)", 0, snapshot.carried or -1)
190|	assertEq("19.2 snapshot.upgradeLevel == 1", 1, snapshot.upgradeLevel)
191|	assertTrue("19.2 snapshot.incomePerSec >= 0", (snapshot.incomePerSec or -1) >= 0)
192|	assertTrue("19.2 snapshot.capacity > 0", (snapshot.capacity or 0) > 0)
193|	assertTrue("19.2 snapshot.onboarding is table", type(snapshot.onboarding) == "table")
194|	print("[E2E 19.2] snapshot.capacity = " .. tostring(snapshot.capacity))
195|	print("[E2E 19.2] snapshot.incomePerSec = " .. tostring(snapshot.incomePerSec))
196|end
197|
198|-- Phase 4: Save (DataStore write, real DataStore v2 in Studio)
199|print("[E2E 19.2] phase=save")
200|local saveOk, saveErr = pcall(function()
201|	DataManager.save(player)
202|end)
203|assertTrue("19.2 DataManager.save succeeds", saveOk)
204|if not saveOk then
205|	print("[E2E 19.2] save error: " .. tostring(saveErr))
206|end
207|
208|-- Phase 5: Reload (verify save → load round-trip)
209|print("[E2E 19.2] phase=reload")
210|-- Remove session first so load doesn't return the cached one
211|DataManager.remove(player)
212|task.wait(0.5)
213|local session2 = DataManager.load(player)
214|assertTrue("19.2 reload creates session", session2 ~= nil)
215|if session2 then
216|	-- Should have same coins (was saved)
217|	assertEq("19.2 reload profile.Coins matches saved", session.profile.Coins, session2.profile.Coins)
218|	print("[E2E 19.2] reloaded coins = " .. tostring(session2.profile.Coins))
219|end
220|
221|-- Phase 6: Dock release (cleanup)
222|print("[E2E 19.2] phase=dock_release")
223|DockManager.release(player)
224|if dock then
225|	assertTrue("19.2 dock released (owner nil)", dock.owner == nil)
226|	local sign = dock.aquarium.PrimaryPart:FindFirstChild("InfoSign")
227|	if sign then
228|		local label = sign:FindFirstChild("OwnerLabel")
229|		if label then
230|			print("[E2E 19.2] dock sign after release = " .. tostring(label.Text))
231|			assertTrue("19.2 dock sign reset", not label.Text:match("E2ETest"))
232|		end
233|	end
234|end
235|
236|-- Phase 7: Cleanup
237|DataManager.remove(player)
238|
239|-- TASK 19.3 (Fishing Loop) MIGRATED to tests/e2e/scenarios/Fishing.lua (EPIC 43, c4fs)
240|
241|-- TASK 19.4 (Aquarium Economy) MIGRATED to tests/e2e/scenarios/Aquarium.lua (EPIC 43, 8hnx)
242|
243|-- TASK 19.5 (Shop Purchases) MIGRATED to tests/e2e/scenarios/Shop.lua (EPIC 43, 7dho)
244|
245|-- TASK 19.6 (Persistence & Migration) MIGRATED to tests/e2e/scenarios/Persistence.lua (EPIC 43, z9mz)
246|
247|-- TASK 19.7 (Lock/Defense Flow) MIGRATED to tests/e2e/scenarios/LockDefense.lua (EPIC 43, tbvq)
248|
-- TASK 19.8 (Raid System, incl. r7an no_session) MIGRATED to tests/e2e/scenarios/Raid.lua (EPIC 43, xpei)

-- TASK 19.9 (Abuse & Anti-Exploit Battery) MIGRATED to tests/e2e/scenarios/AntiExploit.lua (EPIC 43, 7t2j)

-- ============================================================
-- Summary
255|-- ============================================================
256|print(string.format("[E2E] SUMMARY: %d passed, %d failed", PASS, FAIL))
257|if FAIL > 0 then
258|	error(string.format("[E2E] FAILED: %d assertion(s) failed", FAIL), 0)
259|end
260|print("[E2E] COMPLETE")
261|