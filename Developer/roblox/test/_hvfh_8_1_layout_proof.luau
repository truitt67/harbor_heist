-- Numeric proof for TASK 28.1 (hvfh.8.1): mirrors the desktop bar sizing
-- logic in src/client/init.client.lua and asserts no button clips the
-- viewport at the acceptance widths + that an 8th action still fits with
-- zero manual width math.
local BAR_BTN_W = 100
local BAR_BTN_W_MIN = 76
local BAR_GAP = 8
local BAR_SIDE_MARGIN = 36
local BAR_SHORT_VIEWPORT = 700

local function barWidthFor(n, btnW)
	return n * btnW + (n - 1) * BAR_GAP
end

local function layout(n, viewportW)
	local btnW = BAR_BTN_W
	local fullW = barWidthFor(n, BAR_BTN_W)
	if viewportW < fullW + 2 * BAR_SIDE_MARGIN then
		btnW = math.floor((viewportW - 2 * BAR_SIDE_MARGIN - (n - 1) * BAR_GAP) / n + 0.5)
		btnW = math.max(BAR_BTN_W_MIN, math.min(BAR_BTN_W, btnW))
	end
	local useShort = viewportW < BAR_SHORT_VIEWPORT
	local fontScale = (btnW - BAR_BTN_W_MIN) / (BAR_BTN_W - BAR_BTN_W_MIN)
	local textSize = 12 + math.floor(2 * fontScale + 0.5)
	return btnW, math.floor(barWidthFor(n, btnW) + 0.5), textSize, useShort
end

local viewports = { 1920, 1024, 768, 800, 700, 680, 640 }
local fail = 0
for _, n in ipairs({ 7, 8 }) do
	print(string.format("=== #ACTIONS = %d ===", n))
	for _, vw in ipairs(viewports) do
		local btnW, barW, ts, short = layout(n, vw)
		local margin = math.floor((vw - barW) / 2)
		local clip = barW > vw and "  <<< CLIP!" or ""
		-- leftmost button left edge = vw/2 - barW/2 (bar centered); clip if < 0
		local leftEdge = math.floor(vw / 2 - barW / 2)
		local leftClip = leftEdge < 0 and "  <<< LEFT CLIP!" or ""
		print(string.format("  vw=%-5d btnW=%-3d barW=%-4d textSize=%-2d short=%s margin/edge=%-3d%s%s",
			vw, btnW, barW, ts, tostring(short), leftEdge, clip, leftClip))
		if barW > vw or leftEdge < 0 then fail = fail + 1 end
	end
end
-- Acceptance #1: no clipped buttons at 1920x1080, 1024x768, 800x600 (7 actions).
for _, vw in ipairs({ 1920, 1024, 800 }) do
	local _, barW = layout(7, vw)
	assert(barW <= vw, string.format("FAIL: 7-action barW %d > vw %d", barW, vw))
end
-- Acceptance #2: an 8th action keeps every button INSIDE the bar with zero
-- manual width math (bar always == n*btnW + (n-1)*gap), and still fits the
-- 800px acceptance floor. Below ~664px an 8-button bar exceeds the 76px floor
-- the bead sets, so the documented tradeoff is clipping only under that floor.
for n = 7, 8 do
	for _, vw in ipairs({ 1920, 1024, 800 }) do
		local btnW, barW = layout(n, vw)
		assert(barW == n * btnW + (n - 1) * BAR_GAP, "bar not derived from content")
		assert(barW <= vw, string.format("FAIL: %d-action barW %d > vw %d", n, barW, vw))
	end
end
-- Short labels activate below 700px.
assert(layout(7, 680) and select(4, layout(7, 680)) == true, "short labels not on below 700px")
print("\nRESULT: PASS — no clipping at acceptance widths; 8th action fits with zero manual math; short labels on <700px.")
