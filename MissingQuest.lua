-- A step needs a quest that is not in the log (or cannot be accepted because a quest before it is
-- missing): a card offers to create a route that gets the quest (or the chain it needs), or to skip
-- the quest, and lists the later quests that skipping may cost.
--
--   * Detection:  FR:UpdateMissingQuest() (called from Engine.lua's Refresh) sets FR.prompt.
--   * The card:   UI.lua shows FR.prompt with two buttons (PromptBox).
--   * "Create route": a temporary guide (a detour) is generated from Questie's database, or from the
--     steps of the other guides when Questie is missing. It is never listed, never saved, and ends by
--     returning to the step it started from (FR:StartDetour / FR:EndDetour).
--   * "Skip quest": the quest and the quests that depend on it are remembered per character
--     (ForeverRouteCharDB.givenUp), so the steps that mention them pass without asking again.
local _, ns = ...
local FR = ns.FR

local DELAY = 1.5        -- seconds a step must stay blocked before the card shows
local MAX_CHAIN = 8      -- longest chain of quests walked back
local MAX_MISSED = 8     -- quests listed in "you may miss"

local cand               -- { step, qid, kind, since }: a blocked step that has not waited long enough yet
local detourDone = {}    -- [qid] = true: a detour for it ended this session, do not ask again
FR.prompt = nil          -- { step, qid, kind, name, chain, needs, missed, routeText, source }

-- Quests skipped for good (per character) --------------------------------------------------

local function Given()
	if not ForeverRouteCharDB then return {} end
	ForeverRouteCharDB.givenUp = ForeverRouteCharDB.givenUp or {}
	return ForeverRouteCharDB.givenUp
end

function FR.IsGivenUp(qid)
	local t = ForeverRouteCharDB and ForeverRouteCharDB.givenUp
	return t ~= nil and t[qid] == true
end

-- Questie ---------------------------------------------------------------------------------
-- Read live, never copied (like Conditions.lua). Every call is protected: a quest, NPC or object
-- that Questie does not know gives nil.

local function Db() return FR.QuestieDB and FR.QuestieDB() end

local function Q(id, key)
	local db = Db()
	if not (db and db.QueryQuestSingle) then return nil end
	local ok, v = pcall(db.QueryQuestSingle, id, key)
	if ok then return v end
end

local function Entity(kind, id, key)
	local db = Db()
	local fn = db and (kind == "obj" and db.QueryObjectSingle or db.QueryNPCSingle)
	if not fn then return nil end
	local ok, v = pcall(fn, id, key)
	if ok then return v end
end

local function Module(name)
	local loader = _G.QuestieLoader
	if loader and loader.ImportModule then
		local ok, m = pcall(loader.ImportModule, loader, name)
		if ok and type(m) == "table" then return m end
	end
end

-- Where an NPC or object stands: { map = uiMapID, x, y } (0-100), the one in the player's zone first.
local function SpawnPoint(kind, id)
	local spawns = Entity(kind, id, "spawns")
	if type(spawns) ~= "table" then return nil end
	local zone = Module("ZoneDB")
	if not (zone and zone.GetUiMapIdByAreaId) then return nil end
	local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local best
	for areaId, list in pairs(spawns) do
		local ok, map = pcall(zone.GetUiMapIdByAreaId, zone, areaId)
		local c = type(list) == "table" and list[1]
		if ok and map and c and tonumber(c[1]) and tonumber(c[2]) and c[1] >= 0 and c[2] >= 0 then
			local pt = { map = map, x = c[1], y = c[2] }
			if map == here then return pt end
			best = best or pt
		end
	end
	return best
end

local function AbsList(t)
	local out = {}
	if type(t) == "table" then
		for _, v in ipairs(t) do
			if tonumber(v) then out[#out + 1] = math.abs(v) end
		end
	end
	return out
end

-- Text -------------------------------------------------------------------------------------

local function Clean(s)
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("::%d+", "")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- For text that goes into generated guide lines: no line breaks, no escape codes.
local function Esc(s)
	return (tostring(s or ""):gsub("[\r\n]+", " "):gsub("|", ""):gsub("<<", "<"))
end

-- The guide index (without Questie) ----------------------------------------------------------
-- Every step of the English guides, found by the quests its lines name. Built once, when it is needed.
--   steps[qid]  = list of { g = guide, n = step number, lines = { ... } }
--   parent[qid] = quests turned in in the step that accepts qid (the chain before it)
--   name[qid]   = the name from "Accept <name>"
local index

local function ScanGuide(g, idx)
	local stepNo, lines, skip = 0, nil, false
	local function Close()
		if not lines then return end
		local refs, accepts, turnins = {}, {}, {}
		for _, ln in ipairs(lines) do
			local a = ln:match("^%.accept%s+(%d+)") or ln:match("^%.daily%s+(%d+)")
			if a then
				a = tonumber(a)
				accepts[#accepts + 1] = a
				refs[a] = true
				local text = ln:match(">>%s*(.-)%s*$")
				if text and not idx.name[a] then idx.name[a] = Clean(text):gsub("^Accept%s+", "") end
			end
			local t = ln:match("^%.turnin%s+%-?(%d+)") or ln:match("^%.dailyturnin%s+%-?(%d+)")
			if t then t = tonumber(t); turnins[#turnins + 1] = t; refs[t] = true end
			local c = ln:match("^%.complete%s+%-?(%d+)") or ln:match("^%.collect%s+%d+%s*,%s*%d+%s*,%s*(%d+)")
			if c then refs[tonumber(c)] = true end
		end
		for q in pairs(refs) do
			local list = idx.steps[q]
			if not list then list = {}; idx.steps[q] = list end
			list[#list + 1] = { g = g, n = stepNo, lines = lines }
		end
		if #turnins > 0 then
			for _, a in ipairs(accepts) do
				if not idx.parent[a] then
					local p = {}
					for _, t in ipairs(turnins) do if t ~= a then p[#p + 1] = t end end
					if #p > 0 then idx.parent[a] = p end
				end
			end
		end
		lines = nil
	end
	for raw in g.raw:gmatch("[^\r\n]+") do
		local line = raw:match("^%s*(.-)%s*$")
		if line:match("^step$") or line:match("^step[%s<]") then
			Close()
			local tag = line:match("<<%s*(.+)$")
			if tag and not FR.Applies(tag) then
				skip, lines = true, nil
			else
				skip, stepNo, lines = false, stepNo + 1, {}
			end
		elseif lines and not skip and line ~= "" and line:sub(1, 2) ~= "--" and not line:match("^#") then
			local code, tag = line:match("^(.-)%s*<<%s*(.+)$")
			if code then
				if FR.Applies(tag) then line = code else line = nil end
			end
			if line and line ~= "" then lines[#lines + 1] = line end
		end
	end
	Close()
end

local function BuildIndex()
	if index and index.count == #FR.guides then return index end
	index = { steps = {}, parent = {}, name = {}, count = #FR.guides }
	for _, g in ipairs(FR.guides) do
		if g.lang == "enUS" and g.raw then ScanGuide(g, index) end
	end
	return index
end

-- Names ------------------------------------------------------------------------------------

-- Names of the quests the open guide accepts (from "Accept <name>"), cached on the guide.
local function GuideNames(g)
	if not (g and g.steps) then return {} end
	if g.questNames then return g.questNames end
	local names = {}
	for _, s in ipairs(g.steps) do
		for _, e in ipairs(s.elements) do
			if e.kind == "accept" and e.qid and e.text and not names[e.qid] then
				names[e.qid] = (Clean(e.text):gsub("^Accept%s+", ""))
			end
		end
	end
	g.questNames = names
	return names
end

local function QuestName(qid)
	local n = Q(qid, "name")
	if type(n) == "string" and n ~= "" then return n end
	n = FR.QuestTitle and FR.QuestTitle(qid)
	if n and n ~= "" then return n end
	n = GuideNames(FR.current)[qid]
	if n and n ~= "" then return n end
	if index and index.name[qid] then return index.name[qid] end
	return string.format(FR.L["quest %d"], qid)
end

-- Chains -----------------------------------------------------------------------------------

-- The quests before `qid` that are still to do. With Questie: preQuestGroup (all of them) or
-- preQuestSingle (any one; none needed when one is done). Without: the quests turned in in the step
-- that accepts it.
local function PreQuests(qid)
	if Db() then
		local out = {}
		local group = AbsList(Q(qid, "preQuestGroup"))
		if #group > 0 then
			for _, p in ipairs(group) do
				if not FR.IsQuestCompleted(p) then out[#out + 1] = p end
			end
			return out
		end
		local single = AbsList(Q(qid, "preQuestSingle"))
		if #single > 0 then
			for _, p in ipairs(single) do
				if FR.IsQuestCompleted(p) then return out end
			end
			for _, p in ipairs(single) do
				if FR.IsOnQuest(p) then return { p } end
			end
			return { single[1] }
		end
		return out
	end
	local out = {}
	for _, p in ipairs(BuildIndex().parent[qid] or {}) do
		if not FR.IsQuestCompleted(p) then out[#out + 1] = p end
	end
	return out
end

-- All the quests before `qid` whatever their state (for "does this quest depend on that one").
local function RawPreQuests(qid)
	if Db() then
		local out = AbsList(Q(qid, "preQuestGroup"))
		for _, p in ipairs(AbsList(Q(qid, "preQuestSingle"))) do out[#out + 1] = p end
		return out
	end
	return BuildIndex().parent[qid] or {}
end

-- { first, ..., qid }: what has to be done, in order. Second value: the chain was cut short.
local function ResolveChain(qid)
	local out, seen, cut = {}, {}, false
	local function Walk(q, depth)
		if seen[q] then return end
		seen[q] = true
		if depth > MAX_CHAIN then cut = true return end
		for _, p in ipairs(PreQuests(q)) do Walk(p, depth + 1) end
		out[#out + 1] = q
	end
	Walk(qid, 0)
	return out, cut
end

local function Depends(c, target, depth, seen)
	if c == target then return true end
	if depth > MAX_CHAIN or seen[c] then return false end
	seen[c] = true
	for _, p in ipairs(RawPreQuests(c)) do
		if Depends(p, target, depth + 1, seen) then return true end
	end
	return false
end

-- What skipping `qid` may cost: the later steps of the open guide that name it or a quest that needs
-- it. { { qid, name, steps, first } ... } by first step, and the number that did not fit the list.
local function MissedPreview(g, from, qid)
	local refs, order = {}, {}
	for i = from + 1, #g.steps do
		local s = g.steps[i]
		local seen = {}
		for _, e in ipairs(s.elements) do
			if e.qid and (e.kind == "accept" or e.kind == "turnin" or e.kind == "complete") and not e.cond then
				local r = refs[e.qid]
				if not r then
					r = { qid = e.qid, steps = 0, first = s.idx or i }
					refs[e.qid] = r
					order[#order + 1] = r
				end
				if not seen[e.qid] then r.steps = r.steps + 1; seen[e.qid] = true end
			end
		end
	end
	local list = {}
	for _, r in ipairs(order) do
		if not FR.IsQuestCompleted(r.qid) and not FR.IsGivenUp(r.qid)
			and Depends(r.qid, qid, 0, {}) then
			r.name = QuestName(r.qid)
			list[#list + 1] = r
		end
	end
	table.sort(list, function(a, b) return a.first < b.first end)
	local more = math.max(0, #list - MAX_MISSED)
	while #list > MAX_MISSED do list[#list] = nil end
	return list, more
end

-- Routes -----------------------------------------------------------------------------------
-- Text in the guide format, one accept step and one turn-in step per quest of the chain.

local function Friendly(name) return "|cRXP_FRIENDLY_" .. Esc(name) .. "|r" end

local function GotoLine(pt)
	return string.format(".goto %d,%.2f,%.2f,12", pt.map, pt.x, pt.y)
end

-- First NPC (then object) of `ids` that has a known place: point, name.
local function FirstPlace(npcs, objs)
	for _, id in ipairs(type(npcs) == "table" and npcs or {}) do
		local pt = SpawnPoint("npc", id)
		if pt then return pt, Entity("npc", id, "name") end
	end
	for _, id in ipairs(type(objs) == "table" and objs or {}) do
		local pt = SpawnPoint("obj", id)
		if pt then return pt, Entity("obj", id, "name") end
	end
end

local function QuestieRoute(q, have)
	local name = QuestName(q)
	local steps = {}
	if not have then
		local by = Q(q, "startedBy")
		local pt, who = FirstPlace(type(by) == "table" and by[1] or nil, type(by) == "table" and by[2] or nil)
		local s = { "step" }
		if pt then s[#s + 1] = "    " .. GotoLine(pt) end
		if who then
			s[#s + 1] = "    >>Talk to " .. Friendly(who)
		else
			s[#s + 1] = "    >>Find where |cRXP_WARN_" .. Esc(name) .. "|r starts (an item or object may start it)"
		end
		s[#s + 1] = "    .accept " .. q .. " >> Accept " .. Esc(name)
		if who then s[#s + 1] = "    .target " .. Esc(who) end
		steps[#steps + 1] = table.concat(s, "\n")
	end
	local fin = Q(q, "finishedBy")
	local pt, who = FirstPlace(type(fin) == "table" and fin[1] or nil, type(fin) == "table" and fin[2] or nil)
	local s = { "step" }
	if pt then s[#s + 1] = "    " .. GotoLine(pt) end
	local obj = Q(q, "objectivesText")
	if type(obj) == "table" and type(obj[1]) == "string" and obj[1] ~= "" then
		s[#s + 1] = "    >>" .. Esc(obj[1]):sub(1, 140)
	end
	s[#s + 1] = "    >>Do the quest, then turn in " .. (who and Friendly(who) or Esc(name))
	s[#s + 1] = "    .turnin " .. q .. " >> Turn in " .. Esc(name)
	if who then s[#s + 1] = "    .target " .. Esc(who) end
	steps[#steps + 1] = table.concat(s, "\n")
	return table.concat(steps, "\n")
end

local function HasLine(entry, kind, q)
	for _, ln in ipairs(entry.lines) do
		if kind == "accept" and (ln:match("^%.accept%s+(%d+)") == tostring(q)) then return true end
		if kind == "turnin" and (ln:match("^%.turnin%s+%-?(%d+)") == tostring(q)) then return true end
	end
	return false
end

-- Lines of a source step that belong to the route: places, targets and text, and the lines of this
-- quest. Conditions, headers and the lines of other quests are left out.
local function KeepLines(lines, q, have)
	local out, own = {}, false
	local id = tostring(q)
	for _, ln in ipairs(lines) do
		local keep = false
		if ln:match("^%.goto") or ln:match("^%.target") or ln:match("^%.mob") or ln:sub(1, 2) == ">>" then
			keep = true
		elseif ln:match("^%.accept%s+" .. id .. "%f[%D]") then
			keep, own = not have, not have
		elseif ln:match("^%.turnin%s+%-?" .. id .. "%f[%D]") or ln:match("^%.complete%s+%-?" .. id .. "%f[%D]") then
			keep, own = true, true
		elseif ln:match("^%.collect%s+%d+%s*,%s*%d+%s*,%s*" .. id .. "%f[%D]") then
			keep, own = true, true
		end
		if keep then out[#out + 1] = "    " .. ln end
	end
	if not own then return nil end
	return "step\n" .. table.concat(out, "\n")
end

local function GuideRoute(q, have)
	local list = BuildIndex().steps[q]
	if not list then return nil end
	local src
	for _, s in ipairs(list) do
		if HasLine(s, "accept", q) then src = s.g break end
	end
	src = src or list[1].g
	local parts, turned = {}, false
	for _, s in ipairs(list) do
		if s.g == src and not turned then
			local text = KeepLines(s.lines, q, have)
			if text then parts[#parts + 1] = text end
			if HasLine(s, "turnin", q) then turned = true end
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "\n")
end

-- The route for the quests of `chain`, or nil when none of them has a known place.
local function BuildRoute(chain)
	local parts = {}
	for _, q in ipairs(chain) do
		local have = FR.IsOnQuest(q)
		local text
		if Db() and Q(q, "name") then text = QuestieRoute(q, have) end
		if not text or text == "" then text = GuideRoute(q, have) end
		if text and text ~= "" then parts[#parts + 1] = text end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "\n")
end

-- Detection --------------------------------------------------------------------------------

-- Does the step still have an open ".accept" for this quest? (Then the quest simply is not accepted yet.)
local function OpenAccept(step, qid)
	for _, e in ipairs(step.elements) do
		if e.kind == "accept" and e.qid == qid and not e.cond then
			local done = FR:ElementState(step, e)
			if not done then return true end
		end
	end
	return false
end

local function Ignored(qid)
	return FR.IsGivenUp(qid) or detourDone[qid]
end

-- The quest a step is stuck on: qid, "log" (a turn-in or objective of a quest that is not in the log) or
-- qid, "prereq" (a quest that Questie says cannot be accepted because a quest before it is missing).
-- Does the step have something else to do besides accepting (a turn-in, objectives, items)? A chain step
-- ".turnin P" + ".accept X" is such a step: X only becomes available once P is handed in.
local function OtherOpenWork(step)
	for _, e in ipairs(step.elements) do
		if e.kind ~= "accept" and e.kind ~= "goto" then
			local done, completable = FR:ElementState(step, e)
			if completable and not done then return true end
		end
	end
	return false
end

-- Is a quest before `qid` in the log (finished or not)? Then the player is working through the chain.
local function PreQuestInLog(qid)
	for _, p in ipairs(RawPreQuests(qid)) do
		if FR.IsOnQuest(p) then return true end
	end
	return false
end

local function Detect(step)
	for _, e in ipairs(step.elements) do
		if e.qid and not e.cond and not e.skipIfMissing and (e.kind == "turnin" or e.kind == "complete")
			and not Ignored(e.qid) then
			local done, completable = FR:ElementState(step, e)
			if completable and not done and not FR.IsOnQuest(e.qid) and not FR.IsQuestCompleted(e.qid)
				and not OpenAccept(step, e.qid) then
				return e.qid, "log"
			end
		end
	end
	if OtherOpenWork(step) then return nil end
	for _, e in ipairs(step.elements) do
		if e.kind == "accept" and e.qid and not e.cond and not Ignored(e.qid) then
			local done, completable = FR:ElementState(step, e)
			if completable and not done then
				local ok, why = FR.QuestAvailable(e.qid)
				if not ok and why == "prereq" and not PreQuestInLog(e.qid) then return e.qid, "prereq" end
			end
		end
	end
end

-- Engine.lua: a step that is stuck on a missing pre-quest is held for the card instead of being passed.
function FR.MissingQuestHolds(step)
	if not (FR.current and not FR.current.detour and FR:Get("missingQuestPrompt")) then return false end
	local _, kind = Detect(step)
	return kind == "prereq"
end

local function BuildPrompt(step, qid, kind)
	local g = FR.current
	local p = { step = step, qid = qid, kind = kind, name = QuestName(qid), source = Db() and "questie" or "guide" }
	local chain, cut = ResolveChain(qid)
	-- A quest that cannot be accepted yet: the guide step takes it once the quests before it are done.
	if kind == "prereq" then chain[#chain] = nil end
	p.chain, p.cut = chain, cut
	p.needs = {}
	for _, q in ipairs(chain) do
		if q ~= qid then p.needs[#p.needs + 1] = QuestName(q) end
	end
	p.routeText = #chain > 0 and BuildRoute(chain) or nil
	p.missed, p.moreMissed = MissedPreview(g, step.idx or FR.stepIndex, qid)
	return p
end

-- Called from Refresh: keeps FR.prompt in step with the current step.
function FR:UpdateMissingQuest()
	local g = self.current
	local step = g and not g.detour and self:Get("missingQuestPrompt") and self:GetStep()
	local qid, kind
	if step and not FR.IsSideStep(step) and not self:IsStepFinished(step) then
		qid, kind = Detect(step)
	end
	if not qid then
		cand, self.prompt = nil, nil
		return
	end
	local p = self.prompt
	if p and p.step == step and p.qid == qid and p.kind == kind then return end
	self.prompt = nil
	if not (cand and cand.step == step and cand.qid == qid and cand.kind == kind) then
		cand = { step = step, qid = qid, kind = kind, since = GetTime() }
		C_Timer.After(DELAY + 0.1, function() FR:QueueRefresh() end)
		return
	end
	if GetTime() - cand.since < DELAY then return end
	self.prompt = BuildPrompt(step, qid, kind)
end

-- The card text ---------------------------------------------------------------------------

function FR:PromptText(p)
	local L = FR.L
	local name = "|cffffd100" .. p.name .. "|r"
	local t = {}
	if p.kind == "prereq" then
		t[#t + 1] = string.format(L["%s cannot be accepted yet: a quest before it is missing."], name)
	else
		t[#t + 1] = string.format(L["%s is not in your quest log."], name)
	end
	if #p.needs > 0 then
		local list = table.concat(p.needs, ", ")
		if p.cut then list = list .. ", ..." end
		t[#t + 1] = string.format(L["First: %s"], list)
	end
	t[#t + 1] = p.routeText and L["A route to get it can be created."] or L["No route to this quest is known."]
	if #p.missed > 0 then
		t[#t + 1] = "|cffff8040" .. L["Skipping it may cost you:"] .. "|r"
		for _, m in ipairs(p.missed) do
			if m.steps > 1 then
				t[#t + 1] = "- " .. string.format(L["%s (%d steps, from step %d)"], m.name, m.steps, m.first)
			else
				t[#t + 1] = "- " .. string.format(L["%s (step %d)"], m.name, m.first)
			end
		end
		if p.moreMissed and p.moreMissed > 0 then
			t[#t + 1] = "- " .. string.format(L["...and %d more"], p.moreMissed)
		end
	end
	if p.source == "guide" then
		t[#t + 1] = "|cff999999" .. L["Based on the guides only (the Questie addon is not installed)."] .. "|r"
	end
	return table.concat(t, "\n")
end

-- Skip quest ------------------------------------------------------------------------------

function FR:MissingQuestSkip()
	local p = self.prompt
	if not p then return end
	local given = Given()
	given[p.qid] = true
	local followers = 0
	for _, m in ipairs(p.missed) do
		if m.qid ~= p.qid and not given[m.qid] then given[m.qid] = true; followers = followers + 1 end
	end
	self.prompt, cand = nil, nil
	self:Print(string.format(FR.L["Skipped %s and %d quest(s) that need it. /fr missed lists them."], p.name, followers))
	self:SkipStep(p.step.idx)
end

-- "Not now": the card goes away and does not come back for this quest until the next /reload.
function FR:MissingQuestDismiss()
	local p = self.prompt
	if not p then return end
	detourDone[p.qid] = true
	self.prompt, cand = nil, nil
	self:Refresh()
end

function FR:PrintMissed(clear)
	local given = Given()
	if clear then
		for k in pairs(given) do given[k] = nil end
		self:Print(FR.L["Forgot the quests you skipped."])
		self:Refresh()
		return
	end
	local ids = {}
	for q in pairs(given) do ids[#ids + 1] = q end
	table.sort(ids)
	if #ids == 0 then
		self:Print(FR.L["You have not skipped any quest."])
		return
	end
	self:Print(FR.L["Quests you skipped (/fr missed clear forgets them):"])
	for _, q in ipairs(ids) do
		DEFAULT_CHAT_FRAME:AddMessage("   " .. QuestName(q) .. " |cff888888(" .. q .. ")|r")
	end
end

-- Detour ----------------------------------------------------------------------------------

-- Takes a detour guide out again (it was never in FR.guides).
function FR:DropDetour(g)
	if not (g and g.detour) then return end
	if self.guidesByTitle[g.title] == g then self.guidesByTitle[g.title] = nil end
	self:ClearMarks(g.title)
end

function FR:StartDetour(p)
	local origin = self.current
	if not (p and p.routeText and origin) or origin.detour then return false end
	local g = {
		title = "Detour\\" .. p.name .. " #" .. p.qid,
		name = p.name,
		short = string.format(FR.L["Route: %s"], p.name),
		group = "Detour",
		subgroup = FR.L["Detour"],
		lang = self:Language(),
		header = {},
		raw = p.routeText,
		order = 0,
		detour = {
			originTitle = origin.title, originStep = self.stepIndex, originKey = self:CurrentStepKey(),
			qid = p.qid, chain = p.chain,
		},
	}
	self:ParseGuide(g)
	if #g.steps == 0 then return false end
	self.guidesByTitle[g.title] = g
	self.prompt, cand = nil, nil
	self.current = g
	self.stepIndex = 1
	self.wpOverride = nil
	self.returnTo, self.pinnedStep, self.replaying = nil, nil, false
	self.sideSeen, self.doneSeen = nil, nil
	self.listDirty = true
	self:Print(string.format(FR.L["Route to %s: %d step(s). The guide goes on afterwards."], p.name, #g.steps))
	self:SkipForward(true)
	self:SaveState()
	self:UpdateUI()
	return true
end

function FR:MissingQuestCreate()
	local p = self.prompt
	if p and p.routeText then self:StartDetour(p) end
end

-- The detour is over (finished or left): back to the step it started from. The quests it was for are
-- not offered again this session, so a quest you chose not to fetch does not ask over and over.
function FR:EndDetour()
	local g = self.current
	local d = g and g.detour
	if not d then return end
	detourDone[d.qid] = true
	for _, q in ipairs(d.chain or {}) do detourDone[q] = true end
	self:DropDetour(g)
	self.current = nil
	self.sideSeen, self.doneSeen = nil, nil
	self.listDirty = true
	if not self:SetGuide(d.originTitle, d.originStep, d.originKey) then
		local suggested = self:FindSuggestedGuide()
		if suggested then self:SetGuide(suggested, 1) end
	end
end
