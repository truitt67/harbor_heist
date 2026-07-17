local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local EVENT_NAMES = { "Cast", "Notify", "StateChanged", "CastState", "OpenAquarium", "OpenShop", "BiteEvent", "QuestProgressChanged", "OpenQuests", "CastResult" }
local FUNCTION_NAMES = { "StoreFish", "SellAll", "LockAquarium", "BuyItem", "GetState", "SubmitCatchInput", "SellFish", "StoreSingleFish", "ClaimIncome", "SpawnBoat" }

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

function Remotes.notify(player, message, color)
	Remotes.Notify:FireClient(player, message, color)
end

return Remotes
