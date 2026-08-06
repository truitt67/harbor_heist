-- Staggered entrance animation for quest rows (harborheist-3mo7.3.37).
-- Source-scan of src/client/init.client.lua — no Roblox globals — so it
-- runs under lune in the pure bucket.
--
-- Background: inventory rows, collection cards, and raid target rows all
-- cascade in via staggerFadeIn; quest rows appeared all at once, breaking
-- list-animation consistency. Wired both daily and weekly quest loops,
-- but with a STRUCTURAL signature gate the other lists don't need:
-- renderQuestPanel rebuilds on EVERY QuestProgressChanged push (each
-- counted catch/sell while the panel is open), and an unconditional
-- stagger would cascade rows on every progress tick. The gate replays
-- the cascade only on structural change (open, rotation, claim), matching
-- the raid target rows' signature-gated policy (their comment: "only
-- replays on real target changes — not every poll tick").
--
-- Signature design: per-quest id + claimed flag. Progress is DELIBERATELY
-- excluded (changes on every push). Gate resets on panel open so a fresh
-- open always cascades.
return function(describe, it, expect)
	local fs = require("@lune/fs")
	local src = fs.readFile("./src/client/init.client.lua")

	local function has(literal, label)
		if not string.find(src, literal, 1, true) then
			error(string.format(
				"%s: pattern not found in init.client.lua — quest stagger contract regressed (harborheist-3mo7.3.37)",
				label))
		end
		expect(true).to.equal(true)
	end

	local function pos(literal)
		local p = string.find(src, literal, 1, true)
		if not p then
			error(string.format("ordering check: pattern not found: %s", literal))
		end
		return p
	end

	describe("Quest row staggered entrance (harborheist-3mo7.3.37)", function()
		it("makeQuestRow returns the row", function()
			has("-- harborheist-3mo7.3.37: return the row so renderQuestPanel can apply", "return contract comment")
			-- The return row statement must exist inside makeQuestRow (before
			-- renderQuestPanel starts).
			local retPos = pos("\treturn row\nend\n\nlocal function renderQuestPanel")
			local defPos = pos("local function makeQuestRow(parent, quest, order)")
			expect(defPos < retPos).to.equal(true)
		end)

		it("both daily and weekly loops stagger via the shared helper", function()
			has("local row = makeQuestRow(questList, q, 10 + i)", "daily loop captures row")
			has("local row = makeQuestRow(questList, q, 110 + i)", "weekly loop captures row")
			-- Per-section index (i, not a running global) keeps each section's
			-- cascade tight, matching inventory/collection/raid. Count the
			-- GATED form specifically — ungated staggerFadeIn(row, i) also
			-- appears in the inventory and raid loops.
			local count = 0
			for _ in string.gmatch(src, "if structuralChange then\n			staggerFadeIn%(row, i%)\n		end") do
				count += 1
			end
			-- daily + weekly = exactly 2 gated calls.
			expect(count).to.equal(2)
		end)

		it("stagger is gated on structural change, not every progress push", function()
			has("local lastQuestSignature = nil", "signature state")
			has("local structuralChange = questSig ~= lastQuestSignature", "gate computation")
			has("if structuralChange then\n\t\t\tstaggerFadeIn(row, i)\n\t\tend", "daily gate")
			has("if structuralChange then\n\t\t\tstaggerFadeIn(row, i)\n\t\tend", "weekly gate")
			-- Progress must NOT be part of the signature (would change every
			-- push and defeat the gate). Pin the id+claimed shape.
			has('table.insert(sigParts, (q.id or "?") .. ":" .. tostring(q.claimed))', "id+claimed signature")
		end)

		it("gate resets on panel open so a fresh open always cascades", function()
			has("lastQuestSignature = nil", "open-reset exists")
			-- The reset must live in toggleQuestPanel (after showPanel), not
			-- only at declaration.
			local resetPos = pos("lastQuestSignature = nil\n\t-- harborheist-p8v7")
			local togglePos = pos("local function toggleQuestPanel()")
			expect(togglePos < resetPos).to.equal(true)
		end)

		it("uses the shared stagger helper (consistent timing with other lists)", function()
			-- staggerFadeIn derives delay from STAGGER_STEP — the same helper
			-- inventory/collection/raid use, so timing matches by construction.
			has("local STAGGER_STEP = 0.035", "shared stagger timing token")
			has("local STAGGER_MAX_INDEX = 8", "shared stagger cap")
		end)
	end)
end
