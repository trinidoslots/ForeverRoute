-- Tracks the current guide and step, checks elements, advances automatically.
--
-- Steps tagged #completewith or #sticky are not "current" steps of their own:
-- they stay on screen above the current step until they are done or the step
-- they refer to has been passed (like RestedXP).
local _, ns = ...
local FR = ns.FR

-- Marks: manual ticks, interactions and reached waypoints -----------------------------
-- Stored per character as marks[guideTitle][stepKey][elementIndex] = true. The
-- step key (Parser.lua, FR.StepKey) follows the step, not its number, so the
-- ticks stay when a setting hides other steps, the language changes or a new
-- guide version adds steps.

local function MarkTable(step, create)
	local g = FR.current
	if not (g and step and step.sig) then return nil end
	local marks = ForeverRouteCharDB and ForeverRouteCharDB.marks
	if not marks then return nil end
	local gm = marks[g.title]
	if not gm then
		if not create then return nil end
		gm = {}; marks[g.title] = gm
	end
	local key = FR.StepKey(step)
	local sm = gm[key]
	if not sm and create then sm = {}; gm[key] = sm end
	return sm
end

function FR:IsMarked(step, e)
	local sm = MarkTable(step, false)
	return sm and sm[e.idx] or false
end

function FR:SetMarked(step, e, value)
	local sm = MarkTable(step, true)
	if not sm then return end
	local was = sm[e.idx]
	sm[e.idx] = value and true or nil
	-- ".timer": a countdown starts when the line before it is done.
	if value and not was and e.timer and self.StartTimer then self:StartTimer(e.timer, e.timerText) end
end

-- Unticked by hand: the line counts as not done even when the game says it
-- is (finished quest, item in the bags) until it is ticked again.
function FR:IsUnticked(step, e)
	local sm = MarkTable(step, false)
	return sm ~= nil and sm[e.idx] == false
end

function FR:SetUnticked(step, e)
	local sm = MarkTable(step, true)
	if sm then sm[e.idx] = false end
end

function FR:ClearUntick(step, e)
	local sm = MarkTable(step, false)
	if sm and sm[e.idx] == false then sm[e.idx] = nil end
end

-- Skipped by hand ("Skip step"): the step counts as finished for the guide,
-- and shows as skipped in the list. Stored next to the element marks.
function FR:IsManuallySkipped(step)
	local sm = MarkTable(step, false)
	return sm ~= nil and sm.skipped == true
end

function FR:SetManuallySkipped(step, value)
	local sm = MarkTable(step, value and true or false)
	if sm then sm.skipped = value and true or nil end
end

function FR:ClearMarks(title)
	local marks = ForeverRouteCharDB and ForeverRouteCharDB.marks
	if marks and title then marks[title] = nil end
end

-- Element state ----------------------------------------------------------------------------

local function CurrentMap()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
	return ok and FR.Plain(id) or nil
end

-- Is the player in zone/map `mapID`? Not only "the best map is exactly this one": a client whose
-- map IDs differ from the guide's still names the zone the same (RestedXP checks the ID only).
-- (Not the parent maps: Undercity must not count as Tirisfal Glades.)
local zoneNames = {}
local function InZone(mapID)
	if not mapID then return false end
	local cur = FR.Plain(CurrentMap())   -- nil / secret inside instances: then only the zone name can match
	if cur ~= nil and cur == mapID then return true end
	if C_Map and C_Map.GetMapInfo then
		-- same zone name (any client language: the name comes from the game itself)
		local name = zoneNames[mapID]
		if name == nil then
			local ok, info = pcall(C_Map.GetMapInfo, mapID)
			name = ok and info and FR.Plain(info.name) or false
			zoneNames[mapID] = name
		end
		if name then
			local real = FR.SafeText(GetRealZoneText)
			local zone = FR.SafeText(GetZoneText)
			if real == name or zone == name then return true end
		end
	end
	return false
end

FR.InZone = InZone

local function AreaName(id)
	if C_Map and C_Map.GetAreaInfo then
		local ok, name = pcall(C_Map.GetAreaInfo, id)
		if ok then return FR.Plain(name) end
	end
end

local function LevelReached(e)
	local level = UnitLevel("player") or 1
	local xp = e.xp or 0
	if xp == 0 then return level >= e.level end
	local cur, max = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
	if xp < 0 then
		return level >= e.level or (level == e.level - 1 and cur >= max + xp)
	elseif xp >= 1 then
		return level > e.level or (level == e.level and cur >= xp)
	end
	return level > e.level or (level == e.level and cur >= max * xp)
end
FR.LevelReached = LevelReached

local function AnySpellKnown(spells)
	for _, id in ipairs(spells or {}) do
		if FR.SpellKnown(id) then return true end
	end
	return false
end

-- Reputation (".reputation faction,standing[,value]") --------------------------------------
-- Same rules as RestedXP: a negative value means "that far below the end of the
-- standing before", 1 and up is a number of reputation points into the standing,
-- below 1 a fraction of it.

local function FactionInfo(id)
	if GetFactionInfoByID then
		local ok, name, _, standing, bottom, top, earned = pcall(GetFactionInfoByID, id)
		if ok and standing then return name, standing, bottom, top, earned end
	end
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local ok, d = pcall(C_Reputation.GetFactionDataByID, id)
		if ok and d then return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding end
	end
end
FR.FactionInfo = FactionInfo

-- Has the player reached what the line asks for? (reverse for "<"); nil when unknown.
local function ReputationMet(e)
	local _, standing, bottom, top, earned = FactionInfo(e.faction)
	if not standing then return nil end
	local length = top - bottom
	local relative = earned < 0 and (length + earned) or (earned - bottom)
	local v = e.value or 0
	local reached = (v < 0 and (standing >= e.standing or (standing == e.standing - 1 and earned >= top + v)))
		or (v >= 1 and (standing > e.standing or (e.standing == standing and earned >= bottom + v)))
		or (v >= 0 and v < 1 and (standing > e.standing or (e.standing == standing and relative >= length * v)))
	return (reached and true or false) == (not e.reverse)
end
FR.ReputationMet = ReputationMet

-- Blasted Lands collection quests (".blastedLands") ------------------------------------
-- Items per quest: vulture gizzard, basilisk brain, blasted boar lung, scorpok
-- pincer, snickerfang jowl.
FR.BLASTED_ITEMS = { 8396, 8394, 8392, 8393, 8391 }
local BL_QUESTS = {
	[2583] = { 0, 1, 3, 2, 0 },
	[2601] = { 2, 10, 0, 0, 0 },
	[2585] = { 2, 0, 1, 3, 0 },
	[2581] = { 0, 0, 2, 1, 3 },
	[2603] = { 10, 0, 0, 0, 2 },
}

-- Totals still needed per item, and whether everything is collected.
function FR.BlastedNeeds()
	local total = { 0, 0, 0, 0, 0 }
	for quest, items in pairs(BL_QUESTS) do
		if not FR.IsQuestCompleted(quest) then
			for i, n in ipairs(items) do total[i] = total[i] + n end
		end
	end
	local done = true
	for i, goal in ipairs(total) do
		if FR.ItemCount(FR.BLASTED_ITEMS[i]) < goal then done = false end
	end
	return total, done
end

local MARK_KINDS = {
	manual = true, gossipoption = true, fp = true, fly = true, hs = true, home = true, vendor = true,
	trainer = true, stable = true, bank = true, deathskip = true, cast = true,
}

-- Kinds whose state can be read or ticked (see ElementState).
local COMPLETABLE = {
	accept = true, turnin = true, complete = true, collect = true, xp = true, train = true,
	equip = true, destroy = true, abandon = true, zone = true, subzone = true, skill = true,
	aura = true, blasted = true, reputation = true, gossipoption = true, manual = true, fp = true, fly = true, hs = true, home = true, vendor = true,
	trainer = true, stable = true, bank = true, deathskip = true, cast = true,
}

-- Same decision as ElementState's second value, without any game state.
function FR.IsCompletableElement(e)
	if e.cond then return false end
	if e.manualCheck then return true end
	if e.kind == "goto" then return e.arrive and true or false end
	if e.textOnly then return false end
	return COMPLETABLE[e.kind or ""] == true
end

-- Is the item that a "manual" line tells you to use already equipped?
local function UsedItemEquipped(step)
	for _, x in ipairs(step.elements) do
		if x.kind == "use" and x.items then
			for _, id in ipairs(x.items) do
				if FR.ItemEquipped(id) then return true end
			end
		end
	end
	return false
end

-- done, completable
function FR:ElementState(step, e)
	if e.cond then return false, false end
	if e.manualCheck then
		if self:IsUnticked(step, e) then return false, true end
		return self:IsMarked(step, e), true
	end
	local k = e.kind
	if k == "goto" then
		if not e.arrive then return false, false end
		return self:IsMarked(step, e), true
	end
	if e.textOnly then return false, false end
	if self:IsUnticked(step, e) then
		-- Unticked by hand only holds while the game says the line is done. Once the game says it is
		-- open, the untick is outdated and goes away, so the line ticks itself when it is done for real.
		if self:GameState(step, e) then return false, true end
		self:ClearUntick(step, e)
	end
	if self:IsMarked(step, e) then return true, true end
	return self:GameState(step, e)
end

-- What the game says about a line (quest log, bags, level ...), without ticks or unticks made by hand.
-- done, completable
function FR:GameState(step, e)
	local k = e.kind
	-- A quest skipped from the "missing quest" card (MissingQuest.lua): its lines count as done.
	if e.qid and (k == "accept" or k == "turnin" or k == "complete") and FR.IsGivenUp and FR.IsGivenUp(e.qid) then
		return true, true
	end
	-- ".bankdeposit / .bankwithdraw <items>": done when the items are out of the bags / out of the bank
	-- (Bank.lua). Without a known state (the bank was never opened) it stays open for a manual tick.
	if k == "bank" and e.items and #e.items > 0 and FR.BankLineDone then
		return FR.BankLineDone(e) and true or false, true
	end
	if k == "accept" then return FR.IsOnQuest(e.qid) or FR.IsQuestCompleted(e.qid), true end
	if k == "turnin" then
		if FR.IsQuestCompleted(e.qid) then return true, true end
		-- ".turnin -id": nothing to hand in when the quest is not in the log.
		if e.skipIfMissing and not FR.IsOnQuest(e.qid) then return true, true end
		return false, true
	end
	if k == "complete" then
		if FR.IsQuestCompleted(e.qid) or FR.IsQuestReady(e.qid) then return true, true end
		local done = FR.ObjectiveDone(e.qid, e.obj, e.hint)
		if done ~= nil then return done, true end
		if e.skipIfMissing and not FR.IsOnQuest(e.qid) then return true, true end
		return false, true
	end
	if k == "collect" then
		if e.qid and not e.ignoreTurnIn and (FR.IsQuestCompleted(e.qid) or FR.IsQuestReady(e.qid)) then
			return true, true
		end
		-- With RestedXP flag 4: done once the tracked objectives are done.
		if e.objs then
			local all = true
			for _, o in ipairs(e.objs) do
				if FR.ObjectiveDone(e.qid, o) ~= true then all = false break end
			end
			if all then return true, true end
		end
		return FR.ItemCount(e.item) >= (e.count or 1), true
	end
	if k == "manual" and UsedItemEquipped(step) then return true, true end
	if k == "blasted" then local _, done = FR.BlastedNeeds(); return done, true end
	if k == "reputation" then return ReputationMet(e) == true, true end
	if k == "aura" then return FR.HasAura(e.aura, e.unit) ~= e.reverse, true end
	if k == "xp" then return LevelReached(e), true end
	if k == "train" then return AnySpellKnown(e.spells), true end
	if k == "equip" then
		local eq = FR.ItemEquipped(e.item)
		if eq == nil then return false, false end
		return eq, true
	end
	if k == "destroy" then return FR.ItemCount(e.item) == 0, true end
	if k == "abandon" then return not FR.IsOnQuest(e.qid), true end
	if k == "zone" then return InZone(e.mapID), true end
	if k == "subzone" then
		local name = AreaName(e.area)
		return name ~= nil and FR.SafeText(GetSubZoneText) == name, true
	end
	if k == "skill" then
		local rank = FR.SkillRank(e.skill)
		if rank == nil then return false, false end
		return (rank >= e.level) ~= e.reverse, true
	end
	if MARK_KINDS[k] then return false, true end
	return false, false
end

-- true / false, or nil when the element cannot be checked.
function FR:IsGoalDone(e, step)
	local done, completable = self:ElementState(step or self:GetStep(), e)
	if not completable then return nil end
	return done
end

-- Step conditions -------------------------------------------------------------------------

local function CondFails(e)
	local c = e.cond
	if c == "onquest" then
		local any = false
		for _, id in ipairs(e.qids) do if FR.IsOnQuest(id) then any = true end end
		return any == e.reverse
	elseif c == "turnedin" then
		if e.reverse then
			-- isQuestAvailable: skip once every listed quest is turned in.
			for _, id in ipairs(e.qids) do if not FR.IsQuestCompleted(id) then return false end end
			return true
		end
		for _, id in ipairs(e.qids) do if FR.IsQuestCompleted(id) then return false end end
		return true
	elseif c == "ready" then
		local id = e.qids[1]
		local ready = (id and FR.IsOnQuest(id) and FR.IsQuestReady(id)) or false
		return ready == e.reverse
	elseif c == "xp" then
		return LevelReached(e) ~= e.reverse
	elseif c == "maxlevel" then
		return (UnitLevel("player") or 1) > e.level
	elseif c == "istrained" then
		return AnySpellKnown(e.spells)
	elseif c == "skill" then
		local rank = FR.SkillRank(e.skill)
		if rank == nil then return false end
		return (rank >= e.level) ~= e.reverse
	elseif c == "itemcount" then
		local n = 0
		for _, id in ipairs(e.items) do n = n + FR.ItemCount(id) end
		local ok
		if e.op == "<" then ok = (e.eq and n <= e.total) or (not e.eq and n < e.total)
		elseif e.op == ">" then ok = (e.eq and n >= e.total) or (not e.eq and n > e.total)
		else ok = n >= e.total end
		return not ok
	elseif c == "showwhiledead" then
		return not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
	elseif c == "bronzetube" then
		local total = FR.IsQuestCompleted(174) and 0 or 1
		return (FR.ItemCount(4371) >= total) == (not e.rev)
	elseif c == "reputation" then
		return ReputationMet(e) == true
	elseif c == "itemstat" then
			local stat = FR.ItemStat(e.slot, e.stat)
			if stat == nil then return false end
			local ok
			if type(stat) == "number" and type(e.total) == "number" then
				stat = math.floor(stat * 10 + 0.5) / 10
				if e.op == ">" then ok = e.total < stat
				elseif e.op == "<" then ok = e.total > stat
				else ok = e.total == stat end
			else
				ok = tostring(e.total) == tostring(stat)
			end
			return not ok
	elseif c == "cooldown" then
		local start, duration = FR.Cooldown(e.ctype, e.id)
		if not (start and duration) then return false end
		local left = (start + duration) - GetTime()
		if left < 0 then left = 0 end
		if e.less then return left < e.seconds end
		return left > e.seconds
	elseif c == "bindlocation" then
			local name = AreaName(e.area)
			if not (name and GetBindLocation) then return false end
			return (GetBindLocation() == name) ~= e.reverse
	elseif c == "aura" then
			return FR.HasAura(e.aura, e.unit) ~= e.reverse
	elseif c == "zoneskip" then
		local hit = false
		for _, id in ipairs(e.ids) do if InZone(id) then hit = true end end
		return hit ~= e.reverse
	elseif c == "money" then
		local m = GetMoney and GetMoney() or 0
		return (m >= e.copper) == e.above
	elseif c == "subzoneskip" then
		local sub, hit = FR.SafeText(GetSubZoneText), false
		for _, id in ipairs(e.ids) do if sub ~= "" and AreaName(id) == sub then hit = true end end
		return hit ~= e.reverse
	end
	return false
end

-- Quests that cannot be accepted ----------------------------------------------------
-- A step whose only open lines are "accept" lines of quests that Questie says cannot be taken
-- (pre-quest missing, exclusive quest done, wrong race / class, level too low) is passed, with
-- the reason in the step history. Only the step that is about to become the current one is
-- looked at, and only after it has stayed that way for UNAVAIL_DELAY seconds: Questie notes a
-- turn-in a moment after the game does, and a step further down may still become possible.
-- A step with anything else to do (a turn-in, an objective) is never passed, since that may be
-- what makes the quest available.
local UNAVAIL_DELAY = 1.5
FR.unavail = setmetatable({}, { __mode = "k" })   -- [step] = { since = time, why = "prereq" | "level", level = n }
local candidate   -- the step SkipForward is looking at right now

function FR:UnavailableReason(step)
	if not self:Get("skipUnavailable") then return nil end
	local why, level
	for _, e in ipairs(step.elements) do
		local done, completable = self:ElementState(step, e)
		if completable and not done and e.kind ~= "goto" then
			if e.kind ~= "accept" then return nil end
			local ok, w, l = FR.QuestAvailable(e.qid)
			if ok then return nil end
			why, level = why or w, level or l
		end
	end
	return why, level
end

function FR:IsStepUnavailable(step)
	local why, level = self:UnavailableReason(step)
	local rec = self.unavail[step]
	if not why then
		if rec then self.unavail[step] = nil end
		return false
	end
	local now = GetTime()
	if not rec then
		self.unavail[step] = { since = now, why = why, level = level }
		C_Timer.After(UNAVAIL_DELAY + 0.1, function() FR:QueueRefresh() end)
		return false
	end
	rec.why, rec.level = why, level
	return now - rec.since >= UNAVAIL_DELAY
end

function FR:IsStepSkipped(step, depth)
	if step.empty or step.blank then return true end
	if self:IsManuallySkipped(step) then return true end
	-- "#level N": the step is only for players of level N and up.
	local need = tonumber(step.level)
	if need and (UnitLevel("player") or 1) < need then return true end
	for _, e in ipairs(step.elements) do
		if e.cond and CondFails(e) then return true end
	end
	if (step == candidate or (self.current and self.current.steps[self.stepIndex] == step))
		and self:IsStepUnavailable(step)
		-- A quest whose pre-quest is missing gets the "missing quest" card instead of a silent skip.
		and not (FR.MissingQuestHolds and FR.MissingQuestHolds(step)) then
		return true
	end
	return false
end

-- All completable elements done (a step without any never completes itself).
-- Arrival points only count when the step has nothing else to do: once the
-- quests of a step are done, the step is done wherever you stand.
function FR:IsStepDone(step)
	local any, others, othersDone, arrivalsDone = false, false, true, true
	for _, e in ipairs(step.elements) do
		local done, completable = self:ElementState(step, e)
		if completable then
			any = true
			if done and e.completesStep then return true end
			if e.kind == "goto" then
				if not done then arrivalsDone = false end
			else
				others = true
				if not done then othersDone = false end
			end
		end
	end
	if not any then return false end
	if others then return othersDone end
	return arrivalsDone
end

function FR:IsStepFinished(step)
	return self:IsStepSkipped(step) or self:IsStepDone(step)
end

-- Why a step counts as finished, as a short English text for the step history (never shown as
-- a translated interface text, it is stored). Order: your skip, a level gate, a failed condition,
-- then what the game reports for each line that is done.
local COND_TEXT = {
	onquest = function(e) return (e.reverse and "already on quest " or "not on quest ") .. table.concat(e.qids, ",") end,
	turnedin = function(e) return "quest " .. table.concat(e.qids, ",") .. (e.reverse and " already turned in" or " not turned in") end,
	ready = function(e) return "quest " .. table.concat(e.qids, ",") .. (e.reverse and " is complete" or " is not complete") end,
	maxlevel = function(e) return "you are above level " .. tostring(e.level) end,
	xp = function(e) return e.reverse and "level not reached yet" or "level already reached" end,
	istrained = function() return "spell already learned" end,
	skill = function(e) return e.reverse and "skill level too low" or "skill level already reached" end,
	itemcount = function() return "item count does not fit" end,
	money = function() return "money does not fit" end,
	cooldown = function() return "cooldown does not fit" end,
	showwhiledead = function() return "you are not dead" end,
	bindlocation = function() return "hearthstone bound elsewhere" end,
	aura = function(e) return e.reverse and "aura is missing" or "aura is active" end,
	zoneskip = function() return "zone does not fit" end,
	subzoneskip = function() return "area does not fit" end,
}

local function DoneSource(self, step, e)
	local k = e.kind or "line"
	if self:IsMarked(step, e) then
		return k .. (e.qid and (" " .. e.qid) or "") .. ": ticked / reached"
	end
	if k == "accept" then
		return "accept " .. tostring(e.qid) .. (FR.IsOnQuest(e.qid) and ": in the quest log" or ": already turned in")
	elseif k == "turnin" then
		return "turn in " .. tostring(e.qid) .. ": turned in"
	elseif k == "complete" then
		return "objective " .. tostring(e.qid) .. "," .. tostring(e.obj) .. ": done"
	elseif k == "collect" then
		return "collect " .. tostring(e.item) .. ": you have it"
	elseif k == "zone" or k == "subzone" then
		return k .. ": reached"
	elseif k == "xp" then
		return "level reached"
	end
	return k .. ": done"
end

function FR:FinishReason(step)
	if step.empty or step.blank then return "nothing to do in this step" end
	if self:IsManuallySkipped(step) then return "skipped by you" end
	local need = tonumber(step.level)
	if need and (UnitLevel("player") or 1) < need then return "needs level " .. need end
	for _, e in ipairs(step.elements) do
		if e.cond and CondFails(e) then
			local text = COND_TEXT[e.cond]
			return "condition: " .. (text and text(e) or tostring(e.cond))
		end
	end
	local u = self.unavail[step]
	-- Only while the quests are still unavailable now: a step finished by accepting the quest keeps
	-- its normal reason (the stored record may be left over from before the accept).
	if u and self:Get("skipUnavailable") and GetTime() - u.since >= UNAVAIL_DELAY and self:UnavailableReason(step) then
		if u.why == "level" then return "missing pre-requisites: needs level " .. tostring(u.level) end
		if u.why == "other" then return "the quest cannot be accepted (Questie says it is unavailable)" end
		return "missing pre-requisites: a quest before it is missing"
	end
	local parts = {}
	for _, e in ipairs(step.elements) do
		local done, completable = self:ElementState(step, e)
		if completable and done then parts[#parts + 1] = DoneSource(self, step, e) end
	end
	return #parts > 0 and table.concat(parts, "; ") or "done"
end

-- Area lines (".zone" / ".subzone") are read from where you stand, so they went back to open when
-- you left the area. Once reached they are saved as a mark like a travel point: they stay ticked.
-- Only the steps on screen are looked at, so an area further down the guide does not tick early,
-- and a line you unticked by hand stays unticked.
local function LatchAreas(self)
	for _, step in ipairs(self:GetActiveSteps()) do
		for _, e in ipairs(step.elements) do
			if (e.kind == "zone" or e.kind == "subzone") and not e.cond
				and not self:IsMarked(step, e) and not self:IsUnticked(step, e) then
				local here
				if e.kind == "zone" then
					here = InZone(e.mapID)
				else
					local name = AreaName(e.area)
					here = name ~= nil and FR.SafeText(GetSubZoneText) == name
				end
				if here then self:SetMarked(step, e, true) end
			end
		end
	end
end

-- A step that is passed without having been on screen: how to record it and whether the player
-- should be told. Travel and cooldown conditions are routine (recorded quietly); a step passed
-- because of the quest log or because the game says it is done is something you may have missed.
local QUEST_CONDS = { onquest = true, turnedin = true, ready = true }

local function PassKind(self, s)
	if self:IsStepSkipped(s) then
		if self:IsManuallySkipped(s) then return "skipped", false, false end
		for _, e in ipairs(s.elements) do
			if e.cond and CondFails(e) and QUEST_CONDS[e.cond] then return "skipped", false, true end
		end
		-- Passed because Questie says its quests cannot be accepted: worth telling.
		if self.unavail[s] then return "skipped", false, true end
		return "skipped", true, false
	end
	return "auto", false, true
end

local function IsSideStep(step)
	return step.completewith ~= nil or step.sticky ~= nil
end
FR.IsSideStep = IsSideStep

-- Index of the step a #completewith refers to.
local function TargetIndex(g, j)
	local t = g.steps[j].completewith
	if t == true or t == "next" then return j + 1 end
	if type(t) == "string" then return g.labels and g.labels[t] end
end

function FR:IsStepVisible() return true end

local HOLD = 0.7   -- seconds a finished step stays so the tick can be seen

-- A side step with "#requires X" waits until step X is done: it is not shown
-- while X is the current step, or a side step that is not finished yet (or
-- itself waits for something). Like RestedXP.
local function Blocked(self, g, s, cur, depth)
	if type(s.requires) ~= "string" or depth > 6 then return false end
	local r = g.labels and g.labels[s.requires]
	if not r then return false end
	if r == cur then return true end
	local rs = g.steps[r]
	if IsSideStep(rs) and not self:IsStepFinished(rs) then return true end
	return Blocked(self, g, rs, cur, depth + 1)
end

-- Has the step that "#completewith" refers to been reached? When that step is
-- a side step itself it counts as reached once it is finished, otherwise once
-- the current step is past it.
local function CompletewithReached(self, g, j, cur)
	local t = TargetIndex(g, j)
	if not t then return false end
	local ts = g.steps[t]
	if ts and IsSideStep(ts) then return self:IsStepFinished(ts) end
	return cur > t
end

-- The steps on screen: unfinished side steps before the current one, then
-- the current step. A side step that has just been completed stays for a
-- moment (with its tick) before it goes away.
function FR:GetActiveSteps()
	local g = self.current
	if not (g and g.steps) then return {} end
	local list, cur = {}, self.stepIndex or 1
	local side = self.sideSeen
	if not side or side.guide ~= g then
		side = { guide = g, seen = {}, untilT = {} }
		self.sideSeen = side
	end
	local now = GetTime()
	for j = 1, cur - 1 do
		local s = g.steps[j]
		if IsSideStep(s) then
			if not CompletewithReached(self, g, j, cur) then
				if Blocked(self, g, s, cur, 0) then
					side.seen[s], side.untilT[s] = nil, nil
				elseif not self:IsStepFinished(s) then
					list[#list + 1] = s
					side.seen[s], side.untilT[s] = true, nil
				elseif side.seen[s] and self:IsStepDone(s) and not self:IsStepSkipped(s) then
					local u = side.untilT[s]
					if not u then
						u = now + HOLD
						side.untilT[s] = u
						C_Timer.After(HOLD + 0.05, function() FR:UpdateUI() end)
					end
					if now < u then
						list[#list + 1] = s
					else
						side.seen[s], side.untilT[s] = nil, nil
					end
				else
					side.seen[s], side.untilT[s] = nil, nil
				end
			end
		end
	end
	local s = g.steps[cur]
	if s then list[#list + 1] = s end
	return list
end

-- Navigation -----------------------------------------------------------------------------

function FR:GetStep()
	local g = self.current
	return g and g.steps and g.steps[self.stepIndex]
end

-- Key of the current step (nil without a guide); see FR.StepKey.
function FR:CurrentStepKey()
	local s = self:GetStep()
	return s and FR.StepKey(s) or nil
end

-- Number of the step with this key in guide `g`, or nil.
local function IndexOfKey(g, key)
	if not (g and g.steps and key) then return nil end
	for i, s in ipairs(g.steps) do
		if FR.StepKey(s) == key then return i end
	end
	return nil
end

function FR:SaveState()
	ForeverRouteCharDB = ForeverRouteCharDB or {}
	-- A detour (MissingQuest.lua) is never saved: after a reload the guide it started from opens.
	local d = self.current and self.current.detour
	if d then
		ForeverRouteCharDB.guide, ForeverRouteCharDB.step, ForeverRouteCharDB.stepKey = d.originTitle, d.originStep, d.originKey
		return
	end
	ForeverRouteCharDB.guide = self.current and self.current.title
	ForeverRouteCharDB.step = self.stepIndex
	ForeverRouteCharDB.stepKey = self:CurrentStepKey()
end

-- `step` is a step number, `stepKey` (optional) the key of the step to open: the
-- key wins when that step is still in the guide (steps move when a guide is updated).
function FR:SetGuide(title, step, stepKey, noSkip)
	local g = self.guidesByTitle[title]
	if not g then return false end
	-- Opening another guide ends a detour.
	if self.current and self.current.detour and self.current ~= g then self:DropDetour(self.current) end
	-- Never a guide in a language that is not chosen (a German guide with English chosen): its English twin.
	if g.lang ~= "enUS" and g.lang ~= self:Language() then
		FR.LangWarn("opened " .. tostring(g.title) .. " (" .. tostring(g.lang) .. ")")
		if g.pair then g = g.pair end
	end
	self:ParseGuide(g)
	if #g.steps == 0 then return false end
	self.current = g
	step = IndexOfKey(g, stepKey) or step
	self.stepIndex = math.max(1, math.min(step or 1, #g.steps))
	self.wpOverride = nil
	self.returnTo, self.pinnedStep, self.replaying = nil, nil, false
	if not noSkip then self:SkipForward(true) end   -- noSkip: open exactly this step (the step history)
	self:SaveState()
	self:UpdateUI()
	return true
end

function FR:RestartGuide()
	local g = self.current
	if not g then return end
	self:ClearMarks(g.title)
	self.returnTo, self.pinnedStep, self.replaying = nil, nil, false
	self.stepIndex = 1
	self:SkipForward(true)
	self:SaveState()
	self:UpdateUI()
end

-- Is the step on its way to becoming the current one finished? (IsStepSkipped looks at the
-- quests it cannot be accepted of for this one step only.)
local function FinishedCandidate(self, s)
	candidate = s
	local finished = self:IsStepFinished(s)
	candidate = nil
	return finished
end

-- Moves to the next step that still needs doing. Side steps are passed over
-- (they show up above the current step instead).
function FR:SkipForward(includeCurrent)
	local g = self.current
	if not g then return end
	local auto = self:Get("autoAdvance")
	local i = includeCurrent and self.stepIndex or self.stepIndex + 1
	-- Steps passed here without ever being on screen: written to the step history, and the ones you
	-- may have missed are announced with a way back (FR.passNotice, shown by UI.lua). Not when a guide
	-- is opened (includeCurrent): then every finished step in front of you would count.
	local told = {}
	while g.steps[i] do
		local s = g.steps[i]
		if IsSideStep(s) then
			-- shown above the current step instead
		elseif auto and FinishedCandidate(self, s) then
			if not includeCurrent and self.RecordStep then
				local how, minor, notable = PassKind(self, s)
				self:RecordStep(s, how, nil, minor)
				if notable then told[#told + 1] = s end
			end
		else
			break
		end
		i = i + 1
	end
	if #told > 0 and self.AddPassNotice then self:AddPassNotice(g, told) end
	if g.steps[i] then
		self.stepIndex = i
	else
		self.stepIndex = #g.steps
		self:OnGuideFinished()
	end
end

-- Moving by hand: going back remembers where you were (the guide returns
-- there once the step you went back to is done again), and a finished step
-- you moved to stays until you tick something in it or leave it.
function FR:MoveTo(i)
	local g = self.current
	if not (g and g.steps[i]) then return end
	-- Going to a step you skipped takes it back: it is a step to do again.
	self:SetManuallySkipped(g.steps[i], false)
	-- Moving forward by hand past steps that are not finished: they are noted as left open.
	if i > self.stepIndex and self.RecordStep and not self.replaying then
		local n = 0
		for j = self.stepIndex, i - 1 do
			local s = g.steps[j]
			if s and not IsSideStep(s) and not self:IsStepFinished(s) then
				self:RecordStep(s, "left", "left without finishing")
				n = n + 1
				if n >= 25 then break end
			end
		end
	end
	if i < self.stepIndex then
		self.returnTo = math.max(self.returnTo or 0, self.stepIndex)
	elseif self.returnTo and i >= self.returnTo then
		self.returnTo = nil
	end
	self.replaying, self.replayCount = false, 0
	self.stepIndex = i
	self.pinnedStep = self:IsStepFinished(g.steps[i]) and i or nil
	self.wpOverride = nil
	self:SaveState()
	self:UpdateUI()
end

-- Moves on to the next step without marking anything ("/fr next"). After the
-- last step the next guide only loads when the player agrees.
function FR:NextStep()
	if not self.current then return end
	local i = self:NextVisibleIndex(self.stepIndex)
	if i then self:MoveTo(i) else self:ConfirmFinish() end
end

function FR:ConfirmFinish()
	local g = self.current
	if not g then return end
	self:Confirm(FR.L["This is the last step. Load the next guide?"], function() FR:OnGuideFinished() end)
end

-- "Skip step": marks step `i` (the current one by default) as skipped. Skipping
-- the current step moves on; a step further down is just marked and passed
-- when it comes up. Side steps (#completewith / #sticky) simply go away.
function FR:SkipStep(i)
	local g = self.current
	local step = g and g.steps[i or self.stepIndex]
	if not step then return end
	if step.idx ~= self.stepIndex or IsSideStep(step) then
		self:SetManuallySkipped(step, true)
		if self.RecordStep then self:RecordStep(step, "skipped") end
		self:SaveState()
		self:QueueRefresh()
		return
	end
	local nextI = self:NextVisibleIndex(step.idx)
	if not nextI then
		self:Confirm(FR.L["This is the last step. Load the next guide?"], function()
			FR:SetManuallySkipped(step, true)
			if FR.RecordStep then FR:RecordStep(step, "skipped") end
			FR:OnGuideFinished()
		end)
		return
	end
	self:SetManuallySkipped(step, true)
	if self.RecordStep then self:RecordStep(step, "skipped") end
	self:MoveTo(nextI)
end

function FR:PrevStep()
	if not self.current then return end
	local g = self.current
	local i = self.stepIndex - 1
	while i > 1 and IsSideStep(g.steps[i]) do i = i - 1 end
	self:MoveTo(math.max(1, i))
end

function FR:NextVisibleIndex(i)
	local g = self.current
	if not g then return nil end
	i = i + 1
	while g.steps[i] and IsSideStep(g.steps[i]) do i = i + 1 end
	return g.steps[i] and i or nil
end

-- Opens a step of the step history: that guide (the one now open stays when it is the same), exactly
-- at that step. It is not passed on at once even if it counts as finished; finishing it carries
-- on from where you were (the same way as after going back with "previous step").
function FR:OpenStep(title, key, idx)
	local g = self.guidesByTitle[title]
	if not g then return false end
	if self.current ~= g then
		if not self:SetGuide(title, idx, key, true) then return false end
		g = self.current
	end
	local at = IndexOfKey(g, key) or math.max(1, math.min(tonumber(idx) or 1, #g.steps))
	self:MoveTo(at)
	return true
end

function FR:GoToStep(i)
	local g = self.current
	-- A side step is not a place to stand on (it would be passed at once):
	-- go to the step it belongs to.
	if g and g.steps[i] and IsSideStep(g.steps[i]) then i = self:NextVisibleIndex(i) or i end
	self:MoveTo(i)
end

-- A setting changed which steps show (a dungeon was turned on or off, the
-- hardcore mode changed). The step numbers move but the ticks follow their
-- steps (step keys), and the guide opens at the step you were on, or - if that
-- one is gone - at the step that comes first at or after it.
function FR:OnRouteSettingsChanged()
	local g = self.current
	local cur = g and g.steps and g.steps[self.stepIndex]
	local order = cur and cur.order
	local key = cur and FR.StepKey(cur)
	self:InvalidateParsed()
	if not g then return end
	local steps = self:ParseGuide(g)
	local at = IndexOfKey(g, key)
	if not at then
		at = #steps
		if order then
			for n, s in ipairs(steps) do
				if (s.order or 0) >= order then at = n break end
			end
		end
	end
	self.sideSeen, self.doneSeen = nil, nil
	self.returnTo, self.pinnedStep, self.replaying = nil, nil, false
	self.stepIndex = math.max(1, at)
	self.wpOverride = nil
	self.listDirty = true
	self:SkipForward(true)
	self:SaveState()
	self:UpdateUI()
	if self.RefreshSettings then self:RefreshSettings() end
end

FR.OnDungeonsChanged = FR.OnRouteSettingsChanged   -- the old name

-- Hardcore mode on <-> off (the menu entry). Not for a guide that is made for one
-- kind (FR.HardcoreToggleDisabled).
function FR:ToggleHardcore()
	if FR.HardcoreToggleDisabled(self.current) then
		self:Print(FR.L["This guide is made for the other mode, so the mode cannot be changed here."])
		return
	end
	self:Set("hardcoreMode", FR.HardcoreMode() and "off" or "on")
end

function FR:OnGuideFinished()
	local g = self.current
	if not g or self.finishing then return end
	-- The last step of a detour: back to the step it started from.
	if g.detour then self:EndDetour() return end
	local ref = g.next and g.next:match("^([^;]+)")
	local nextGuide = ref and self:FindGuide(ref, g.group, g.lang)
	-- A guide the dungeon choices left without steps (a dungeon-only guide whose dungeon is
	-- off) is passed over: on to its own "next".
	local hops = 0
	while nextGuide and nextGuide ~= g and hops < 6 and self:IsGuideEmpty(nextGuide) do
		local r = nextGuide.next and nextGuide.next:match("^([^;]+)")
		nextGuide = r and self:FindGuide(r, nextGuide.group, nextGuide.lang) or nil
		hops = hops + 1
	end
	if nextGuide and self:IsGuideEmpty(nextGuide) then nextGuide = nil end
	if not nextGuide or nextGuide == g then
		-- End of a route (e.g. the German guides stop at 22): continue with
		-- the best guide for the current level.
		local title = self:FindSuggestedGuide(g)
		nextGuide = title and self.guidesByTitle[title]
	end
	if nextGuide and nextGuide ~= g then
		self.finishing = true
		if self.RecordGuideChange then self:RecordGuideChange(g, nextGuide) end
		self:Print(string.format(FR.L["Guide finished. Loading: %s"], nextGuide.short))
		self:SetGuide(nextGuide.title, 1)
		self.finishing = false
	end
end

local REPLAY_MAX = 14   -- finished steps shown one by one on the way back

-- How long a replayed step stays: its ticks pop one after the other.
local function ReplayHold(step)
	local n = 0
	for _, e in ipairs(step.elements) do
		if not e.hidden and select(2, FR:ElementState(step, e)) then n = n + 1 end
	end
	return math.min(0.9, 0.3 + 0.07 * n)
end

-- Leaves the finished current step. After going back, the guide runs forward
-- again step by step, like RestedXP: every finished step is shown for a moment
-- with its ticks until the step you came from is reached. Otherwise it goes
-- to the next step that still needs doing.
local function Advance(self)
	local g = self.current
	-- The step being left was on screen: it goes into the step history. (A replay on the way back and
	-- side steps are not recorded.) Finishing a step yourself also ends an "N steps passed" notice.
	local leaving = g.steps[self.stepIndex]
	if leaving and not self.replaying and not IsSideStep(leaving) and self.RecordStep then
		if self:IsStepSkipped(leaving) then
			local _, minor = PassKind(self, leaving)
			self:RecordStep(leaving, "skipped", nil, minor)
			local u = self.unavail[leaving]
			if u and not self:IsManuallySkipped(leaving) and FR.StepSummary then
				local what = FR.StepSummary(leaving)
				if u.why == "level" then
					self:Print(string.format(FR.L["Skipped: %s - needs level %d."], what, u.level or 0))
				else
					self:Print(string.format(FR.L["Skipped: %s - missing pre-requisites."], what))
				end
			end
		else
			self:RecordStep(leaving, "done")
			self.passNotice = nil
		end
	end
	local back = self.returnTo
	if back and back > self.stepIndex and g.steps[back] then
		local i = self.stepIndex + 1
		while i < back do
			local s = g.steps[i]
			-- Side steps, skipped steps and steps you never finished are passed.
			if not IsSideStep(s) and not self:IsStepSkipped(s) and self:IsStepDone(s) then break end
			i = i + 1
		end
		self.replayCount = (self.replayCount or 0) + 1
		if i < back and self.replayCount <= REPLAY_MAX then
			self.replaying = true
			self.replayToken = (self.replayToken or 0) + 1
			self.stepIndex = i
			self:SaveState()
			return
		end
		-- Arrived (or far too long a way): carry on from the step you came from.
		self.returnTo, self.replaying, self.replayCount = nil, false, 0
		self.stepIndex = back
		self:SkipForward(true)
	else
		self.returnTo, self.replaying, self.replayCount = nil, false, 0
		self:SkipForward(false)
	end
	self:SaveState()
end

-- Called after any event that can change progress.
function FR:Refresh()
	if self.current then LatchAreas(self) end
	if self.UpdateMissingQuest then self:UpdateMissingQuest() end
	if self.current and self:Get("autoAdvance") then
		local step = self:GetStep()
		local finished = step and self:IsStepFinished(step)
		local pinned = self.pinnedStep == self.stepIndex
		if pinned and step and not finished then
			self.pinnedStep, pinned = nil, false
		end
		if step and not finished and self.doneSeen then self.doneSeen[step] = nil end
		if step and not pinned then
			if IsSideStep(step) then
				Advance(self)
			elseif finished then
				-- Done in the game (or ticked by hand): show the tick for a
				-- moment before the next step comes.
				if self:IsStepDone(step) and not self:IsStepSkipped(step) then
					self.doneSeen = self.doneSeen or {}
					local t = self.doneSeen[step]
					if not t then
						local hold = self.replaying and ReplayHold(step) or HOLD
						self.doneSeen[step] = GetTime() + hold
						self:UpdateUI()
						C_Timer.After(hold + 0.05, function() FR:Refresh() end)
						return
					elseif GetTime() < t then
						self:UpdateUI()
						return
					end
					self.doneSeen[step] = nil
				end
				Advance(self)
			end
		end
	end
	self:UpdateUI()
end

local pending = false
function FR:QueueRefresh()
	if pending then return end
	pending = true
	C_Timer.After(0.2, function()
		pending = false
		FR:InvalidateQuestLog()
		FR:RefreshConditionEnv()
		FR:Refresh()
	end)
end

-- Events from the game -------------------------------------------------------------------

local INTERACT_KINDS = {
	merchant = { vendor = true }, trainer = { trainer = true }, taxi = { fp = true },
	home = { home = true }, stablemaster = { stable = true },   -- (bank lines are done by Bank.lua: items, not the window)
}

-- The player opened a service window (vendor, trainer, flight master, ...).
function FR:OnInteract(npcID, kind)
	local wanted = INTERACT_KINDS[kind]
	if not wanted then return end
	local changed = false
	for _, step in ipairs(self:GetActiveSteps()) do
		for _, e in ipairs(step.elements) do
			if wanted[e.kind] and (not e.npc or e.npc == npcID) and not self:IsMarked(step, e) then
				self:SetMarked(step, e, true)
				changed = true
			end
		end
	end
	if changed then self:QueueRefresh() end
end

-- Marks every active element of one kind (hearthstone used, flight taken, ...).
function FR:MarkKind(kind, spellID)
	local changed = false
	for _, step in ipairs(self:GetActiveSteps()) do
		for _, e in ipairs(step.elements) do
			local hit = e.kind == kind
			if hit and kind == "cast" then
				hit = false
				for _, id in ipairs(e.spells or {}) do if id == spellID then hit = true end end
			end
			if hit and not self:IsMarked(step, e) then
				self:SetMarked(step, e, true)
				changed = true
			end
		end
	end
	if changed then self:QueueRefresh() end
end

-- Reached a waypoint. Path points only move the arrow on; arrival elements
-- also count towards the step.
function FR:OnArrive(step, e)
	if self:IsMarked(step, e) then return end
	self:SetMarked(step, e, true)
	if step.loop then
		-- Looping paths start over once every point was reached.
		local all = true
		for _, x in ipairs(step.elements) do
			if x.kind == "goto" and x.wp.radius and not self:IsMarked(step, x) then all = false end
		end
		if all then
			for _, x in ipairs(step.elements) do
				if x.kind == "goto" and not x.arrive then self:SetMarked(step, x, false) end
			end
		end
	end
	self:QueueRefresh()
end

-- Click on a line's checkbox: a done line (ticked by hand or done in the
-- game) is unticked, an open line is ticked off.
function FR:ToggleGoal(e, step)
	step = step or self:GetStep()
	if not step then return end
	-- Ticking something is an explicit action: a finished step you had moved
	-- back to no longer stays put.
	self.pinnedStep = nil
	self.replaying = false   -- a click ends a running replay
	if self:ElementState(step, e) then
		-- Only the game saying "done" needs an untick that holds. A line that is done just because it was
		-- ticked by hand simply loses its tick (an untick there would keep it open for good).
		if e.manualCheck or e.kind == "goto" or not self:GameState(step, e) then
			self:SetMarked(step, e, false)
		else
			self:SetUnticked(step, e)
		end
	else
		self:SetMarked(step, e, true)
	end
	-- ".clicknext": the line takes you to the next guide.
	if e.nextGuide and self:IsMarked(step, e) then
		local g = self:FindGuide(e.nextGuide, self.current and self.current.group, self.current and self.current.lang)
		if g and g ~= self.current then self:SetGuide(g.title, 1) return end
	end
	-- Show the tick (with its little animation) first, move on afterwards.
	self.doneSeen = self.doneSeen or {}
	local finished = self:IsStepDone(step) and not self:IsStepSkipped(step)
	self.doneSeen[step] = finished and (GetTime() + HOLD) or nil
	self:UpdateUI()
	C_Timer.After(HOLD + 0.05, function() FR:Refresh() end)
end

-- Guide choice ---------------------------------------------------------------------------

-- Level range from a guide name like "6-12 Tirisfal Glades". Levels are one or two digits: a typo in
-- the data such as "37-380_38-38 Swamp of Sorrows" (a range of 37-380) is not taken as a range; the
-- #displayname ("37-38 Swamp of Sorrows") is used instead when the name has no valid one.
local function RangeOf(text)
	-- At the start or after a space only: not the "38-38" tail of "37-380_38-38".
	text = " " .. tostring(text or "")
	local lo, hi = text:match("%s(%d%d?)%-(%d%d?)%f[%D]")
	lo, hi = tonumber(lo), tonumber(hi)
	if lo and hi and hi >= lo then return lo, hi end
end

local function LevelRange(g)
	local lo, hi = RangeOf(g.name)
	if not lo then lo, hi = RangeOf(g.short or (g.header and g.header.displayname)) end
	return lo, hi
end
FR.GuideLevelRange = LevelRange

local function GroupRank(group)
	group = group or ""
	if group == FR.IMPORT_GROUP then return 4 end   -- imported guides come last
	if group:find("Forever") and not group:find("Dungeon") then return 1 end
	if group:find("Forever") then return 2 end
	return 3
end

FR.GroupRank = GroupRank

-- "#defaultfor none Human Mage": a guide the player picks by hand; it is never
-- the suggested one and not a starter zone of some other race either.
local function NoDefault(g)
	local d = g.defaultfor
	return d ~= nil and d:lower():find("%f[%w]none%f[%W]") ~= nil
end
FR.NoDefault = NoDefault

-- A starter guide made for another race ("#defaultfor Orc,Troll").
function FR:IsOtherRaceGuide(g)
	if g.defaultfor == nil or g.defaultfor == "" or NoDefault(g) then return false end
	return not FR.Applies((g.defaultfor:gsub(",", "/")))
end

-- Is the guide offered in the chosen language? That language first, the English
-- guides (which go up to 60) behind it; English alone shows English only.
function FR:IsGuideAllowed(g)
	-- Gold mode shows the farming guides, the normal mode the leveling guides.
	if (g.farm == true) ~= self:IsGoldMode() then return false end
	-- "#internal" guides (RestedXP's helper guides such as RXP-Hyjal) are only #included by other guides.
	if g.header and g.header.internal ~= nil then return false end
	-- The chosen language and English (the fallback: it goes up to level 60); never a third one.
	return g.lang == self:Language() or g.lang == "enUS"
end

-- Gold Assistant mode (RestedXP): only farming guides are offered. Per character.
function FR:IsGoldMode()
	return ForeverRouteCharDB ~= nil and ForeverRouteCharDB.goldMode == true
end

-- At login: no farming guide any more (an import was deleted): back to normal.
function FR:CheckGoldMode()
	if self:IsGoldMode() and (FR.farmGuides or 0) == 0 then ForeverRouteCharDB.goldMode = false end
end

-- Switches between the leveling guides and the farming guides. The guide and
-- step you were on are remembered for each kind.
function FR:ToggleGoldMode()
	local want = not self:IsGoldMode()
	if want and (FR.farmGuides or 0) == 0 then
		self:Print(FR.L["There is no farming guide yet. Import one (a guide whose group starts with +)."])
		return
	end
	ForeverRouteCharDB.modeGuide = ForeverRouteCharDB.modeGuide or {}
	local kind = self:IsGoldMode() and "gold" or "normal"
	if self.current then
		ForeverRouteCharDB.modeGuide[kind] = { title = self.current.title, step = self.stepIndex, key = self:CurrentStepKey() }
	end
	ForeverRouteCharDB.goldMode = want
	local saved = ForeverRouteCharDB.modeGuide[want and "gold" or "normal"]
	local g = saved and self.guidesByTitle[saved.title]
	if g and (g.farm == true) == want then
		self:SetGuide(g.title, saved.step, saved.key)
	else
		local title = self:FindSuggestedGuide()
		if title then self:SetGuide(title, 1) end
	end
	if self.ApplySettings then self:ApplySettings("theme") end   -- gold theme on / off
	self:UpdateUI()
end

-- Guides in the chosen language; English ones when no translation exists.
function FR:IsGuideInLanguage(g)
	return g.lang == self:Language()
end

-- The same guide in the chosen language, when there is one: an English guide has a German twin
-- (same file, same number in the file, same level range: FR.PairGuides sets `pair`). nil otherwise.
function FR:LanguageTwin(g)
	local lang = self:Language()
	if not (g and g.file and g.fileIndex) or g.lang == lang or lang == "enUS" then return nil end
	local twin = FR.guideSlots[lang .. "|" .. g.file .. "#" .. g.fileIndex]
	if twin and twin.pair == g and self:IsGuideAllowed(twin) then return twin end
	return nil
end

-- After the language was changed: an open English guide that has a twin in the new language
-- carries on there, at the same step.
function FR:SwitchGuideLanguage()
	local twin = self:LanguageTwin(self.current)
	if twin then self:SetGuide(twin.title, self.stepIndex, self:CurrentStepKey()) end
end

-- The race's starter guide, otherwise the guide that matches the level.
-- Prefers the chosen language and never picks another race's starter zone.
function FR:FindSuggestedGuide(exclude, skipped)
	local level = UnitLevel("player") or 1
	local best, bestRank
	for _, g in ipairs(self.guides) do
		if g ~= exclude and not (skipped and skipped[g]) and self:IsGuideAllowed(g) and not self:IsOtherRaceGuide(g) then
			local lo, hi = LevelRange(g)
			local mine = g.defaultfor ~= nil and not NoDefault(g)
			local rank
			if mine and lo and level >= lo and level < hi then rank = 0
			elseif lo and level >= lo and level < hi then rank = 2
			elseif mine and (not lo or level < lo) then rank = 4 end
			if rank then
				-- The language counts more than the kind of guide: a German player
				-- gets the German route as long as there is one.
				rank = rank + GroupRank(FR.CanonGroup(g)) * 10 + (self:IsGuideInLanguage(g) and 0 or 50)
				if not bestRank or rank < bestRank then best, bestRank = g, rank end
			end
		end
	end
	if not best and self:IsGoldMode() then
		-- Farming guides have no level range: the first one is the suggestion.
		for _, g in ipairs(self.guides) do
			if g ~= exclude and self:IsGuideAllowed(g) then return g.title end
		end
	end
	-- Not a guide the dungeon choices left empty: the next best one then.
	if best and self:IsGuideEmpty(best) then
		skipped = skipped or {}
		skipped[best] = true
		return self:FindSuggestedGuide(exclude, skipped)
	end
	return best and best.title
end

-- Dungeon routes ---------------------------------------------------------------------------------
-- The game has every Forever route twice: "Leveling Route" (group "... Forever Guide ...", no
-- dungeon steps) and "Leveling Route with Dungeons" ("... Forever Dungeon Guide ...", which
-- includes the same steps and adds the dungeon ones). The dungeon choices only mean something in
-- the second kind, so choosing a dungeon in the first moves you over.

-- Has the guide no step at all with the current settings? Also a guide that is only one dungeon's run
-- while that dungeon is switched off (its steps are not tagged, so none of them would be hidden).
-- Used to pass over guides on the way to the next one; a guide you pick by hand still opens.
function FR:IsGuideEmpty(g)
	if g == nil then return false end
	local tag = FR.DungeonOnlyTag(g)
	if tag and not FR.DungeonShown(tag, g) then return true end
	return #self:ParseGuide(g) == 0
end

-- The group of the other kind of route ("with" = the one with dungeons), or nil when there is
-- none (the guide is already of that kind, or no such group exists: mage, imported guides).
-- Takes a guide. The group is judged by the English name of the guide's group (FR.CanonGroup:
-- the group of its English twin), so this works in every language: the translated files call
-- their groups "Forever Route", "Guía Forever", ... The group returned is such an English name.
function FR.DungeonRouteGroup(g, with)
	local group = FR.CanonGroup(g)
	if type(group) ~= "string" then return nil end
	local to
	if with then
		if group:find("Forever Dungeon Guide", 1, true) or not group:find("Forever Guide", 1, true) then return nil end
		to = (group:gsub("Forever Guide", "Forever Dungeon Guide"))
	else
		if not group:find("Forever Dungeon Guide", 1, true) then return nil end
		to = (group:gsub("Forever Dungeon Guide", "Forever Guide"))
	end
	for _, c in ipairs(FR.guides) do
		if FR.CanonGroup(c) == to then return to end
	end
	return nil
end

-- Does this guide belong to a route with dungeons?
function FR.IsDungeonRoute(g)
	local group = FR.CanonGroup(g)
	return type(group) == "string" and group:find("Forever Dungeon Guide", 1, true) ~= nil
end

-- The guide of the other kind of route to carry on with, and the step number in it: the guide
-- that has the step with `key` (the steps are the same, only the splits into guides differ,
-- e.g. "12-17 The Barrens" and "12-16 The Barrens" + "16-17 Ragefire Chasm"), otherwise the
-- one for the player's level.
function FR:FindRouteGuide(g, with, key)
	local to = g and FR.DungeonRouteGroup(g, with)
	if not to then return nil end
	local level = UnitLevel("player") or 1
	local lo, hi = LevelRange(g)
	local same, other = {}, {}
	for _, c in ipairs(self.guides) do
		if FR.CanonGroup(c) == to and self:IsGuideAllowed(c) and not self:IsOtherRaceGuide(c) then
			local clo, chi = LevelRange(c)
			local near = not clo or (level >= clo and level <= chi) or (lo and hi and clo <= hi and chi >= lo)
			if near then table.insert(c.lang == g.lang and same or other, c) end
		end
	end
	for _, list in ipairs({ same, other }) do
		if key then
			for _, c in ipairs(list) do
				self:ParseGuide(c)
				local at = IndexOfKey(c, key)
				if at then return c, at end
			end
		end
	end
	for _, list in ipairs({ same, other }) do
		for _, c in ipairs(list) do
			local clo, chi = LevelRange(c)
			if clo and level >= clo and level < chi and not self:IsGuideEmpty(c) then return c, 1 end
		end
	end
	return nil
end

-- Ticks and skips of the steps two guides share (same step key) carry over.
function FR:CopyMarks(fromTitle, toTitle)
	local marks = ForeverRouteCharDB and ForeverRouteCharDB.marks
	local from = marks and marks[fromTitle]
	if not from or fromTitle == toTitle then return end
	marks[toTitle] = marks[toTitle] or {}
	for key, sm in pairs(from) do
		if marks[toTitle][key] == nil then
			local copy = {}
			for k, v in pairs(sm) do copy[k] = v end
			marks[toTitle][key] = copy
		end
	end
end

-- Moves to the same place in the other kind of route. `key` = the current step's key (taken
-- from the open guide when not given).
function FR:SwitchDungeonRoute(with, key)
	local g = self.current
	if not g then return false end
	key = key or self:CurrentStepKey()
	local c, at = self:FindRouteGuide(g, with, key)
	if not c then
		self:Print(FR.L[with and "There is no route with dungeons for this guide." or "There is no route without dungeons for this guide."])
		return false
	end
	self:CopyMarks(g.title, c.title)
	if not self:SetGuide(c.title, at or 1, key) then return false end
	self:Print(string.format(FR.L[with and "Route with dungeons: %s" or "Route without dungeons: %s"], c.short))
	if self.RefreshSettings then self:RefreshSettings() end
	return true
end

-- Called after a dungeon choice changed which steps show. Turning a dungeon on in a guide
-- without dungeon steps moves you to the matching route with dungeons.
function FR:DungeonsChanged(turnedOn)
	local g = self.current
	if turnedOn and g and not FR.HasDungeonSteps(g) and FR.DungeonRouteGroup(g, true) then
		local key = self:CurrentStepKey()
		local steps, labels, tips = g.steps, g.labels, g.tips
		self:InvalidateParsed()   -- the candidates must be read with the new choices
		if self:SwitchDungeonRoute(true, key) then return end
		g.steps, g.labels, g.tips = steps, labels, tips   -- stay: OnRouteSettingsChanged needs the place
	end
	self:OnRouteSettingsChanged()
end

function FR:IsGuideVisible() return true end

-- /fr dungeons: for each dungeon whether it is on for the open guide and where
-- that comes from (your choice, the guide group's default, or "#disabledungeons").
function FR:PrintDungeons()
	local g = self.current
	if not g then self:Print(FR.L["No guide selected"]) return end
	self:Print(string.format("%s  (group: %s%s)  phase %d", g.title, tostring(g.group),
		g.header.disabledungeons and ", #disabledungeons" or "", FR.PHASE))
	local mine = ForeverRouteDB and ForeverRouteDB.dungeons or {}
	for _, d in ipairs(FR.DUNGEONS) do
		local tag = d[1]
		local why
		if g.header.disabledungeons then why = "this guide has no dungeon steps"
		elseif mine[tag] ~= nil then why = "your choice"
		elseif FR.DungeonDefault(tag, g.group) ~= nil then why = "default of the guide group (.enabledungeon)"
		else why = "default (off)" end
		self:Print(string.format("   %-7s %-3s  %s", tag, FR.DungeonEnabled(tag, g) and "ON" or "off", why))
	end
end

-- /fr dump: what the guide expects and what the game reports, line by line
-- of the current steps. Meant for bug reports ("this line did not tick").
-- A step as lines of text: whether it is done or skipped, and for each line
-- what the guide expects and what the game reports. Used by /fr dump and by the
-- problem report.
function FR:DescribeStep(s)
	local lines = {}
	lines[#lines + 1] = string.format("Step %d  done=%s skipped=%s", s.idx, tostring(self:IsStepDone(s)), tostring(self:IsStepSkipped(s)))
	for _, e in ipairs(s.elements) do
		if e.cond then
			lines[#lines + 1] = string.format("   cond %s -> %s", tostring(e.cond), tostring(CondFails(e) and "skips the step" or "ok"))
		elseif e.kind == "complete" or (e.kind == "collect" and e.obj) then
			local list = {}
			local c = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(e.qid) or {}
			for i, o in ipairs(c) do list[#list + 1] = string.format("%d=[%s%s]", i, tostring(o.text), o.finished and " done" or "") end
			local text, finished = FR.GetObjective(e.qid, e.obj, e.hint)
			lines[#lines + 1] = string.format("   %s quest %s obj %s hint=%s -> picked '%s' finished=%s | game: %s",
				e.kind, tostring(e.qid), tostring(e.obj), tostring(e.hint), tostring(text), tostring(finished),
				#list > 0 and table.concat(list, ", ") or "quest not in the log")
		elseif not e.hidden then
			local done, completable = self:ElementState(s, e)
			lines[#lines + 1] = string.format("   %s done=%s tickable=%s", tostring(e.kind or "text"), tostring(done), tostring(completable))
		end
	end
	return lines
end

function FR:DumpStep()
	local g = self.current
	if not g then self:Print(FR.L["No guide selected"]) return end
	if g.pair then
		self:Print(string.format("%s: %d of %d steps are still English (the translation is behind)",
			g.title, g.englishSteps or 0, g.mergedSteps or 0))
	end
	for _, s in ipairs(self:GetActiveSteps()) do
		for _, line in ipairs(self:DescribeStep(s)) do self:Print(line) end
	end
end
