-- E2E stub for run-in-roblox: boots the E2E place's server sim.
-- run-in-roblox (>= 0.3.0) executes this file in the PLUGIN context, where
-- Studio is in EDIT mode — server Scripts under ServerScriptService do not
-- run until the sim starts. RunService:Run() starts it, which boots
-- init.server.lua (services) and the E2ERunner script (tests/e2e).
--
-- Keep this file in sync with any change to the suite's runtime — the wait
-- below must outlast the slowest block (19.8's raid-minigame timing waits
-- pushed the suite past the original 30s).
local RunService = game:GetService("RunService")
local ok, err = pcall(function()
	RunService:Run()
end)
if not ok then
	warn("[E2E-STUB] RunService:Run() failed: " .. tostring(err))
else
	print("[E2E-STUB] Run() called — server VM should now boot")
end

-- Keep the plugin alive long enough for server output to stream back.
task.wait(120)
print("[E2E-STUB] done")
