local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local EVENT_NAMES = { "RequestCast", "Notify", "StateChanged", "CastState", "OpenAquarium", "OpenShop", "BiteEvent", "QuestProgressChanged", "OpenQuests", "CastResult", "RaidWindowChanged" }
local FUNCTION_NAMES = { "RequestStoreFish", "RequestSellFish", "RequestActivateLock", "RequestPurchaseUpgrade", "GetState", "SubmitCatchInput", "SellFish", "StoreSingleFish", "RequestClaimIncome", "SpawnBoat", "RequestCollection", "ClaimCollectionReward", "RequestToggleRaidOptIn", "GetRaidTargets", "RequestRaidAttempt", "SubmitRaidResult", "MarkOnboardingFlag" }

local folder = Instance.new("Folder")
folder.Name = "Remotes"

for _, name in ipairs(EVENT_NAMES) do
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = folder
	Remotes[name] = event
end

for _, name in ipairs(FUNCTION_NAMES) do
	local fn = Instance.new("RemoteFunction")
	fn.Name = name
	fn.Parent = folder
	Remotes[name] = fn
end

folder.Parent = ReplicatedStorage

-- TASK 24.3 (hvfh.4.3): optional category (catch/discovery/cast/quest/raid-
-- victim/raid-attacker/raid-info/lock/economy/info) so the client can render a
-- glanceable icon/chip instead of relying on color alone (PRD accessibility
-- rule: never color alone). Backward-compatible: existing 2-arg calls forward
-- nil -> client defaults to "info". Luau binds FireClient args positionally,
-- so unmigrated call sites silently drop the 3rd arg until the client-visual
-- half of 24.3 consumes it.
function Remotes.notify(player, message, color, category)
	Remotes.Notify:FireClient(player, message, color, category)
end

return Remotes
