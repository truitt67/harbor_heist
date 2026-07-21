--!strict
-- AuditLogService.lua (EPIC 10, TASK 10.3)
-- Server-side audit logging for high-value transactions.
-- Logs: Legendary catches, all purchases, raid transfers, storage changes.
-- For debugging and balancing.

local AuditLogService = {}

local MAX_ENTRIES = 500
local log: { { timestamp: number, player: string, userId: number, action: string, details: string } } = {}

local function addEntry(player, action, details)
	local entry = {
		timestamp = os.time(),
		player = player and player.Name or "unknown",
		userId = player and player.UserId or 0,
		action = action,
		details = details,
	}
	table.insert(log, entry)
	while #log > MAX_ENTRIES do
		table.remove(log, 1)
	end
	-- Console output for live debugging
	print(("[Audit] %s | player=%s id=%d | %s"):format(
		action, entry.player, entry.userId, details
	))
end

function AuditLogService.logCatch(player, fish)
	if not fish then return end
	local rarity = fish.Rarity or "Unknown"
	-- Always log Legendary, optionally log Epic for balancing
	if rarity == "Legendary" or rarity == "Epic" then
		addEntry(player, "catch", string.format(
			"Caught %s %s (value=$%d, species=%s)",
			rarity, fish.SpeciesId or "?", fish.BaseSellValue or 0, fish.SpeciesId or "?"
		))
	end
end

function AuditLogService.logPurchase(player, kind, level, cost, itemName)
	addEntry(player, "purchase", string.format(
		"Bought %s level %d (%s) for $%d",
		kind, level, itemName or "?", cost or 0
	))
end

function AuditLogService.logStore(player, count, totalValue)
	addEntry(player, "store", string.format(
		"Stored %d fish (total value $%d)", count or 0, totalValue or 0
	))
end

function AuditLogService.logSell(player, count, payout)
	addEntry(player, "sell", string.format(
		"Sold %d fish for $%d", count or 0, payout or 0
	))
end

function AuditLogService.logRaidTransfer(attacker, victim, fish, success)
	if success then
		addEntry(attacker, "raid_success", string.format(
			"Stole %s %s (value=$%d) from %s",
			fish and fish.Rarity or "?", fish and fish.SpeciesId or "?", fish and fish.BaseSellValue or 0,
			victim and victim.Name or "unknown"
		))
		addEntry(victim, "raid_victim", string.format(
			"Lost %s %s (value=$%d) to %s",
			fish and fish.Rarity or "?", fish and fish.SpeciesId or "?", fish and fish.BaseSellValue or 0,
			attacker and attacker.Name or "unknown"
		))
	else
		addEntry(attacker, "raid_failed", string.format(
			"Failed raid on %s", victim and victim.Name or "unknown"
		))
	end
end

function AuditLogService.logLock(player, duration, freeUsesRemaining)
	addEntry(player, "lock", string.format(
		"Locked aquarium for %ds (free uses left: %d)", duration or 0, freeUsesRemaining or 0
	))
end

function AuditLogService.logClaim(player, amount)
	addEntry(player, "claim", string.format(
		"Claimed $%d income", amount or 0
	))
end

function AuditLogService.getLog()
	return log
end

function AuditLogService.getLogForPlayer(userId)
	local out = {}
	for _, entry in ipairs(log) do
		if entry.userId == userId then
			table.insert(out, entry)
		end
	end
	return out
end

function AuditLogService.init(_deps)
	-- No deps needed currently, but keep init for consistency
end

return AuditLogService
