# EPIC 11 Critical Fix Notice (2026-07-18)

Fresh-eyes review of the initial EPIC 11 (Analytics Instrumentation) implementation found a **critical bug** that would have shipped a completely broken analytics pipeline.

## The Bug

`AnalyticsService.lua` called `svc:FireClientEvent(eventName, userId, enriched)` — a **non-existent method** on Roblox's AnalyticsService (confused with RemoteEvent:FireClient). Because `track()` is pcall-wrapped, the error was silently swallowed on every single event fire. The entire 24-event catalog produced ZERO dashboard data.

## The Fix

The correct Roblox API (verified against create.roblox.com/docs/reference/engine/classes/AnalyticsService) is:

```lua
AnalyticsService:FireCustomEvent(player: Instance, eventCategory: string, customData: Variant)
```

- Takes a **Player instance** (not userId) as the first arg
- `eventCategory` is the event name string
- `customData` is the structured fields table

Note: all methods on the legacy AnalyticsService are marked Deprecated in favor of newer v2/event-based APIs, but FireCustomEvent remains functional and is the standard for V1 custom events.

## Other Fixes Applied

1. **first_* events fired every occurrence** — first_cast/first_catch/first_store/first_sale/first_upgrade all fired alongside their every-occurrence counterparts (fish_caught etc.), polluting funnel metrics. Now gated by `analytics.isFirst(userId, milestone)` so they fire EXACTLY once per player.
2. **starter_rod_received fired on every respawn** (CharacterAdded). Now gated by `session.starterRodTracked` — fires once per session.
3. **Engine service resolved on every event fire** (~20/min/player, pcall+GetService each time). Now memoized — resolved once on first track() call.
4. **Funnel stamps on wrong events** — time_to_first_X was stamped on every-occurrence events (fish_caught) not the dedicated first_catch events. Now stamps on first_* events, matching their semantic.

## Lesson

If you touch AnalyticsService, use FireCustomEvent. And never trust a pcall to surface API mistakes — a pcall'd call to a non-existent method just returns false and moves on.
