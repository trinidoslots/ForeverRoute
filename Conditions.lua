-- Quest state queries and the "<< Class/Race" tag rules used by the guides.
local _, ns = ...
local FR = ns.FR

-- Quest log --------------------------------------------------------------------
-- Scanned directly instead of relying only on C_QuestLog, because not every
-- client build ships every C_QuestLog function.

local questLog = {}      -- [questID] = { index = n, complete = bool, title = s }
local logDirty = true

-- Objectives are read from the game once per frame and quest: one window update
-- asks for them dozens of times (every line, every refresh).
local objCache, objTime = {}, nil

function FR:InvalidateQuestLog()
	logDirty = true
	objTime = nil
	if FR.ResetQuestAvailability then FR.ResetQuestAvailability() end
end

local function ScanQuestLog()
	if not logDirty then return end
	logDirty = false
	for k in pairs(questLog) do questLog[k] = nil end
	if GetQuestLogTitle and GetNumQuestLogEntries then
		for i = 1, GetNumQuestLogEntries() or 0 do
			local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
			if not isHeader and questID and questID > 0 then
				questLog[questID] = { index = i, complete = (isComplete == 1 or isComplete == true), title = title }
			end
		end
	elseif C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID and info.questID > 0 then
				local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
				questLog[info.questID] = { index = i, complete = complete and true or false, title = info.title }
			end
		end
	end
end

local function IsOnQuest(id)
	if not id then return false end
	ScanQuestLog()
	if questLog[id] then return true end
	if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) and true or false end
	if GetQuestLogIndexByID then return (GetQuestLogIndexByID(id) or 0) > 0 end
	return false
end
FR.IsOnQuest = IsOnQuest

local turnedIn = {}
FR.turnedIn = turnedIn

local function IsCompleted(id)
	if not id then return false end
	if turnedIn[id] then return true end
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
	end
	if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
	return false
end
FR.IsQuestCompleted = IsCompleted

-- In the log and all objectives finished.
local function IsReadyToTurnIn(id)
	if not id then return false end
	ScanQuestLog()
	local q = questLog[id]
	if q then return q.complete end
	if C_QuestLog and C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) and true or false end
	return false
end
FR.IsQuestReady = IsReadyToTurnIn

-- Objectives of a quest in the log as { text, finished } entries.
local function Objectives(id)
	local now = GetTime()
	if objTime ~= now then
		for k in pairs(objCache) do objCache[k] = nil end
		objTime = now
	end
	local cached = objCache[id]
	if cached then return cached end
	local list = {}
	objCache[id] = list
	if C_QuestLog and C_QuestLog.GetQuestObjectives then
		local objs = C_QuestLog.GetQuestObjectives(id)
		if objs then
			for i, o in ipairs(objs) do list[i] = { text = o.text, finished = o.finished and true or false, type = o.type } end
			if #list > 0 then return list end
		end
	end
	ScanQuestLog()
	local q = questLog[id]
	if q and GetQuestLogLeaderBoard and GetNumQuestLeaderBoards then
		for i = 1, GetNumQuestLeaderBoards(q.index) or 0 do
			local text, _, finished = GetQuestLogLeaderBoard(i, q.index)
			if text then list[#list + 1] = { text = text, finished = finished and true or false } end
		end
	end
	return list
end

-- The guides name an objective by its number (.complete 370,1), but the game
-- may list the objectives in another order. The comment after the command
-- ("--Captain Perrine (1)") names the creature or item, so look for an
-- objective whose text contains that name (English, or the game language through the
-- NPC name table) and fall back to the number.
local function Pick(list, n, hint)
	if hint and hint ~= "" then
		local names = { hint:lower() }
		local de = FR.npcNames and FR.npcNames[hint]
		if de then names[#names + 1] = de:lower() end
		local first
		for i, o in ipairs(list) do
			local t = (o.text or ""):lower()
			for _, name in ipairs(names) do
				if t:find(name, 1, true) then
					if i == n then return i end
					first = first or i
				end
			end
		end
		if first then return first end
	end
	return n
end
FR.PickObjective = Pick

-- Objective n of a quest in the log: text ("Mindless Zombie slain: 3/8"),
-- finished, or nil when the quest is not in the log. hint = name from the
-- guide (see Pick).
function FR.GetObjective(id, n, hint)
	local list = Objectives(id)
	local o = list[Pick(list, n, hint)]
	if o then return o.text, o.finished end
	return nil
end

-- Kind of an objective ("monster", "item", "object", ...), or nil.
function FR.ObjectiveType(id, n, hint)
	local list = Objectives(id)
	local o = list[Pick(list, n, hint)]
	return o and o.type or nil
end

function FR.ObjectiveDone(id, n, hint)
	local text, finished = FR.GetObjective(id, n, hint)
	if text == nil then return nil end
	return finished
end

function FR.QuestTitle(id)
	ScanQuestLog()
	if questLog[id] and questLog[id].title then return questLog[id].title end
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
		if ok and t then return t end
	end
	return nil
end

-- Can the quest be accepted? ---------------------------------------------------------
-- Asked of the Questie addon when it is loaded (like RestedXP does): its quest database knows
-- the pre-quests, exclusive quests, race / class / skill / reputation requirements and the
-- level. Nothing is copied from it. A quest Questie does not know is "available" (it may be a
-- new Forever quest), and so is every quest when Questie is missing or not ready yet.
local questieDB
local function QuestieDB()
	if questieDB then return questieDB end
	local loader = _G.QuestieLoader
	if loader and loader.ImportModule then
		local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
		if ok and type(db) == "table" and db.IsDoable and db.QueryQuestSingle then questieDB = db end
	end
	return questieDB
end

FR.QuestieDB = QuestieDB   -- MissingQuest.lua reads quest data through it

local availCache = {}   -- [questID] = { t = GetTime(), ok = bool, why = "prereq" | "level" | "other", level = n }
local function ResetAvailability() for k in pairs(availCache) do availCache[k] = nil end end
FR.ResetQuestAvailability = ResetAvailability

-- Why Questie says no. IsDoable alone only returns false: it is also false for quests Questie hides
-- (its blacklist, e.g. "removed with Cata" quests that Forever still has), so the reason is read from
-- IsDoableVerbose. Only a missing pre-quest counts as "prereq"; Questie's hidden list is ignored.
local function QuestieWhy(db, id)
	local states = db.DoableStates
	if db.IsDoableVerbose and type(states) == "table" then
		-- pcall returns: ok, text, unavailable, state
		local ok, _, _, state = pcall(db.IsDoableVerbose, id, false, true, true)
		if ok and state ~= nil then
			if state == states.NO_PREQUESTSINGLE or state == states.NO_PREQUESTGROUP then return false, "prereq" end
			if state == states.AVAILABLE or state == states.BLACKLISTED or state == states.EVENT_INACTIVE
				or state == states.COMPLETED or state == states.QUEST_LOG or state == states.PARENT_ACTIVE
				or state == states.LEVEL_TOO_LOW then
				return true   -- (a level that is too low is judged below from requiredLevel)
			end
			return false, "other"
		end
	end
	local s3, doable = pcall(db.IsDoable, id)
	if s3 and doable == false then return false, "other" end
	return true
end

-- true when the quest can be accepted (or nothing is known); false, "prereq" | "level" | "other", level
-- when Questie says it cannot be accepted right now.
function FR.QuestAvailable(id)
	if not id then return true end
	local db = QuestieDB()
	local questie = _G.Questie
	if not (db and questie and questie.db and questie.db.char and questie.db.char.complete) then return true end
	local now = GetTime()
	local c = availCache[id]
	if c and now - c.t < 0.5 then return c.ok, c.why, c.level end
	local ok, why, level = true, nil, nil
	local s, known = pcall(db.QueryQuestSingle, id, "name")
	if s and known then
		local can, reason = QuestieWhy(db, id)
		if can == false then
			ok, why = false, reason
		else
			local s3, need = pcall(db.QueryQuestSingle, id, "requiredLevel")
			if s3 and type(need) == "number" and need > (UnitLevel("player") or 1) then
				ok, why, level = false, "level", need
			end
		end
	end
	availCache[id] = { t = now, ok = ok, why = why, level = level }
	return ok, why, level
end

-- Player data ----------------------------------------------------------------------

local _, playerClass = UnitClass("player")
local _, playerRace = UnitRace("player")
local playerFaction = UnitFactionGroup("player")
local locale = GetLocale and GetLocale() or "enUS"
FR.game = "FOREVER"

-- Is this a hardcore server? (the game's own flag; "#hardcoreserver" steps follow it)
function FR.IsHardcore()
	return C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() or false
end

-- Which variant of the "#hardcore" / "#softcore" steps to show: the deathless
-- one when the player plays that way. The setting is "auto" (the server decides),
-- "on" or "off". RestedXP only offers this on Classic; on Forever it is ours.
function FR.HardcoreMode()
	local mode = ForeverRouteDB and ForeverRouteDB.hardcoreMode or "auto"
	if mode == "on" then return true end
	if mode == "off" then return false end
	return FR.IsHardcore()
end

-- RestedXP's rule: a "#hardcore" guide cannot be switched to softcore and a
-- "#softcore" guide cannot be switched to hardcore.
function FR.HardcoreToggleDisabled(g)
	if not (g and g.header) then return false end
	local hc = FR.HardcoreMode()
	return (g.header.hardcore ~= nil and hc) or (g.header.softcore ~= nil and not hc)
end

-- Skill rank by name (English or client language), nil if unknown.
function FR.SkillRank(name)
	if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
	name = tostring(name):lower()
	for i = 1, GetNumSkillLines() or 0 do
		local skillName, isHeader, _, rank = GetSkillLineInfo(i)
		if not isHeader and skillName and skillName:lower() == name then return rank or 0 end
	end
	return 0
end

-- Tag rules ---------------------------------------------------------------------------
-- "Warrior/Mage" = either, "Orc Warrior" = both, "!Undead" = not, numbers are
-- a minimum level, "(...)" groups. Same rules as RestedXP.

local cache = {}

local function Parse(text)
	text = text:gsub("(!?)%(%s*(.-)%s*%)", function(op, inner)
		if Parse(inner) ~= (op == "!") then return playerClass else return "NULL" end
	end)
	local level = UnitLevel("player") or 1
	for alt in text:gmatch("[^/]+") do
		local ok = true
		for entry in alt:gmatch("!?[%w%d]+") do
			local negate = false
			if entry:sub(1, 1) == "!" then entry, negate = entry:sub(2), true end
			local upper = entry:upper()
			if entry == "Undead" then entry = "Scourge" end
			if upper == "DK" then upper = "DEATHKNIGHT" end
			local gender = (upper == "MALE" and UnitSex and UnitSex("player") == 2)
				or (upper == "FEMALE" and UnitSex and UnitSex("player") == 3)
			local num = tonumber(entry)
			local match = gender or upper == playerClass or entry == playerRace or entry == playerFaction
				or (num ~= nil and level >= num) or upper == FR.game or entry == locale
			if match == negate then ok = false break end
		end
		if ok then return true end
	end
	return false
end

function FR.Applies(tag)
	if not tag or tag == "" then return true end
	local r = cache[tag]
	if r == nil then
		r = Parse(tag)
		cache[tag] = r
	end
	return r
end

-- Level tags depend on the level, so the cache is reset when it changes.
local lastLevel
function FR:RefreshConditionEnv()
	local level = UnitLevel("player")
	if level ~= lastLevel then
		lastLevel = level
		for k in pairs(cache) do cache[k] = nil end
	end
end
