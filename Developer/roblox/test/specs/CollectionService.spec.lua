-- CollectionService unit tests (DataModel / TestEZ bucket).
--
-- Covers k5wz.12 cases 1-3: discovery, milestones, and RequestCollection
-- payload. CollectionService uses game:GetService at the top level and must
-- run inside a real Roblox DataModel via TestEZ in the test place.
--
-- Run: scripts/run_tests.sh --datamodel (requires Roblox Studio)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishDefinitions = require(Shared:WaitForChild("FishDefinitions"))
local PlayerProfile = require(Shared:WaitForChild("PlayerProfile"))
local CollectionService = require(game:GetService("ServerScriptService"):WaitForChild("HarborHeist"):WaitForChild("CollectionService"))

-- Helper: build a session with a fresh Collection profile section and a
-- given set of discovered species.
local function makeSession(discoveredSpecies)
	local profile = PlayerProfile.default()
	if discoveredSpecies then
		for _, id in ipairs(discoveredSpecies) do
			profile.Collection.DiscoveredSpecies[id] = true
		end
	end
	return { profile = profile, player = nil }
end

return function()
	describe("CollectionService.buildBook (case 3 — payload shape)", function()
		it("should return a table with discovered, undiscovered, ordered, totalSpecies, discoveredCount, milestones", function()
			local session = makeSession()
			local book = CollectionService.buildBook(session)
			expect(type(book.discovered)).to.equal("table")
			expect(type(book.undiscovered)).to.equal("table")
			expect(type(book.ordered)).to.equal("table")
			expect(type(book.totalSpecies)).to.equal("number")
			expect(type(book.discoveredCount)).to.equal("number")
			expect(type(book.milestones)).to.equal("table")
		end)

		it("should have discoveredCount=0 for a fresh session", function()
			local session = makeSession()
			local book = CollectionService.buildBook(session)
			expect(book.discoveredCount).to.equal(0)
		end)

		it("should have totalSpecies > 0 (FishDefinitions has species)", function()
			local session = makeSession()
			local book = CollectionService.buildBook(session)
			expect(book.totalSpecies > 0).to.equal(true)
		end)

		it("should put discovered species in the discovered map with full data", function()
			-- Discover the first species in FishDefinitions
			local firstId = nil
			for _, def in pairs(FishDefinitions.Species) do
				firstId = def.SpeciesId
				break
			end
			local session = makeSession({ firstId })
			local book = CollectionService.buildBook(session)
			expect(book.discovered[firstId]).to.be.ok()
			expect(book.discovered[firstId].speciesId).to.equal(firstId)
			expect(book.discovered[firstId].displayName).to.be.ok()
			expect(book.discovered[firstId].rarity).to.be.ok()
			expect(book.discovered[firstId].baseSellValue).to.be.ok()
			expect(book.discovered[firstId].incomePerMinute).to.be.ok()
		end)

		it("should put undiscovered species in undiscovered map with ONLY rarity + silhouette (COLL-04)", function()
			local session = makeSession()
			local book = CollectionService.buildBook(session)
			-- Find an undiscovered species
			local firstUndiscovered = book.ordered[1]
			local entry = book.undiscovered[firstUndiscovered]
			expect(entry).to.be.ok()
			expect(entry.silhouette).to.equal(true)
			expect(entry.rarity).to.be.ok()
			-- COLL-04: NO name, NO value, NO zone
			expect(entry.displayName).to.equal(nil)
			expect(entry.baseSellValue).to.equal(nil)
			expect(entry.zoneIds).to.equal(nil)
		end)

		it("should not have a species in BOTH discovered and undiscovered", function()
			-- Discover one species
			local firstId = nil
			for _, def in pairs(FishDefinitions.Species) do
				firstId = def.SpeciesId
				break
			end
			local session = makeSession({ firstId })
			local book = CollectionService.buildBook(session)
			for _, id in ipairs(book.ordered) do
				local inDiscovered = book.discovered[id] ~= nil
				local inUndiscovered = book.undiscovered[id] ~= nil
				expect(inDiscovered and inUndiscovered).to.equal(false)
			end
		end)

		it("should produce ordered as a stable list of SpeciesIds", function()
			local session1 = makeSession()
			local session2 = makeSession()
			local book1 = CollectionService.buildBook(session1)
			local book2 = CollectionService.buildBook(session2)
			expect(#book1.ordered).to.equal(#book2.ordered)
			for i, id in ipairs(book1.ordered) do
				expect(id).to.equal(book2.ordered[i])
			end
		end)
	end)

	describe("CollectionService.buildBook — discovery update (case 1)", function()
		it("should reflect a newly discovered species in the book", function()
			local session = makeSession()
			local firstId = nil
			for _, def in pairs(FishDefinitions.Species) do
				firstId = def.SpeciesId
				break
			end
			-- Before discovery
			local book1 = CollectionService.buildBook(session)
			expect(book1.discovered[firstId]).to.equal(nil)
			expect(book1.undiscovered[firstId]).to.be.ok()

			-- Simulate FishingService discovery write
			session.profile.Collection.DiscoveredSpecies[firstId] = true

			-- After discovery
			local book2 = CollectionService.buildBook(session)
			expect(book2.discovered[firstId]).to.be.ok()
			expect(book2.undiscovered[firstId]).to.equal(nil)
			expect(book2.discoveredCount).to.equal(book1.discoveredCount + 1)
		end)

		it("should handle repeat discovery without duplication (idempotent)", function()
			local firstId = nil
			for _, def in pairs(FishDefinitions.Species) do
				firstId = def.SpeciesId
				break
			end
			local session = makeSession({ firstId })
			-- "Discover" the same species again
			session.profile.Collection.DiscoveredSpecies[firstId] = true
			local book = CollectionService.buildBook(session)
			expect(book.discoveredCount).to.equal(1)
			expect(book.discovered[firstId]).to.be.ok()
		end)
	end)

	describe("CollectionService.getMilestones (case 2)", function()
		it("should return milestones array with id, kind, label, have, need, complete, claimed, reward", function()
			local session = makeSession()
			local milestones = CollectionService.getMilestones(session)
			expect(#milestones > 0).to.equal(true)
			for _, m in ipairs(milestones) do
				expect(type(m.id)).to.equal("string")
				expect(type(m.kind)).to.equal("string")
				expect(type(m.label)).to.equal("string")
				expect(type(m.have)).to.equal("number")
				expect(type(m.need)).to.equal("number")
				expect(type(m.complete)).to.equal("boolean")
				expect(type(m.claimed)).to.equal("boolean")
				expect(type(m.reward)).to.equal("table")
			end
		end)

		it("should have count_5, count_10, count_15 milestones", function()
			local session = makeSession()
			local milestones = CollectionService.getMilestones(session)
			local ids = {}
			for _, m in ipairs(milestones) do
				ids[m.id] = true
			end
			expect(ids.count_5).to.be.ok()
			expect(ids.count_10).to.be.ok()
			expect(ids.count_15).to.be.ok()
		end)

		it("should mark count_5 complete when 5+ species discovered", function()
			-- Discover the first 5 species
			local discovered = {}
			local count = 0
			for _, def in pairs(FishDefinitions.Species) do
				if count >= 5 then break end
				table.insert(discovered, def.SpeciesId)
				count = count + 1
			end
			local session = makeSession(discovered)
			local milestones = CollectionService.getMilestones(session)
			local m5 = nil
			for _, m in ipairs(milestones) do
				if m.id == "count_5" then m5 = m end
			end
			expect(m5).to.be.ok()
			expect(m5.complete).to.equal(true)
			expect(m5.have).to.equal(5)
			expect(m5.need).to.equal(5)
		end)

		it("should NOT mark count_10 complete with only 5 species", function()
			local discovered = {}
			local count = 0
			for _, def in pairs(FishDefinitions.Species) do
				if count >= 5 then break end
				table.insert(discovered, def.SpeciesId)
				count = count + 1
			end
			local session = makeSession(discovered)
			local milestones = CollectionService.getMilestones(session)
			local m10 = nil
			for _, m in ipairs(milestones) do
				if m.id == "count_10" then m10 = m end
			end
			expect(m10).to.be.ok()
			expect(m10.complete).to.equal(false)
		end)

		it("should have claimed=false for unclaimed milestones", function()
			local session = makeSession()
			local milestones = CollectionService.getMilestones(session)
			for _, m in ipairs(milestones) do
				expect(m.claimed).to.equal(false)
			end
		end)

		it("should have claimed=true when MilestonesClaimed has the id", function()
			local session = makeSession()
			-- Mark a milestone as claimed
			session.profile.Collection.MilestonesClaimed["count_5"] = true
			local milestones = CollectionService.getMilestones(session)
			local m5 = nil
			for _, m in ipairs(milestones) do
				if m.id == "count_5" then m5 = m end
			end
			expect(m5.claimed).to.equal(true)
		end)

		it("should produce milestones in deterministic (id-sorted) order", function()
			local session1 = makeSession()
			local session2 = makeSession()
			local ms1 = CollectionService.getMilestones(session1)
			local ms2 = CollectionService.getMilestones(session2)
			expect(#ms1).to.equal(#ms2)
			for i, m in ipairs(ms1) do
				expect(m.id).to.equal(ms2[i].id)
			end
		end)
	end)

	describe("CollectionService.init — remote wiring", function()
		it("should exist as an exported function", function()
			expect(type(CollectionService.init)).to.equal("function")
		end)
	end)
end
