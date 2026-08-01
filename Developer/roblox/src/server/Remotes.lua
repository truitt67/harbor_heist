local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- harborheist-a2ug.2: semantic color keys for server→client toasts.
-- Replaces ~46 raw Color3.fromRGB literals across 10 files with a
-- one-word key that resolves to the canonical UIPalette token.
local UIPalette = require(ReplicatedStorage.Shared.UIPalette)
local NOTIFY_COLORS = {
	warn = UIPalette.color("warn"),
	error = UIPalette.color("bad"),
	success = UIPalette.color("money"),
	info = UIPalette.color("accentSoft"),
	discovery = UIPalette.color("discovery"),
	reward = UIPalette.color("discovery"),
}

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
-- color can be a Color3 (legacy) or a semantic string key
-- ("warn", "error", "success", "info", "discovery", "reward") resolved via
-- NOTIFY_COLORS built from UIPalette. Unknown keys fall back to
-- accentSoft + a one-time warn().
function Remotes.notify(player, message, color, category)
	if type(color) == "string" then
		local resolved = NOTIFY_COLORS[color]
		if not resolved then
			warn("[Remotes.notify] Unknown color key: " .. color .. " — falling back to accentSoft")
			resolved = NOTIFY_COLORS.info
		end
		color = resolved
	end
	Remotes.Notify:FireClient(player, message, color, category)
end

return Remotes
