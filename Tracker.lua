-- Leveling tracker: what each level took and where its experience came from, for
-- the leveling report (LevelReport.lua). Like RestedXP's tracker, but
--   * the experience is measured from the XP bar (UnitXP), not read from the
--     chat text, so it works in every game language, and
--   * the "time played" chat line is hidden by switching that event off on the
--     chat windows for the moment of our request; no game function is replaced.
--
-- Per character, ForeverRouteCharDB.levels[level] =
--   quests = { [zone] = { [questId] = xp } }, mobs = { [zone] = { xp, count } },
--   groupXP, deaths, started / finished (played seconds), dateStarted / dateFinished (server time)
local _, ns = ...
local FR = ns.FR

local T = {}
FR.Tracker = T

local state = {
	level = nil,                 -- the level we think the player has
	-- lastXP, lastMax, lastLevel: the XP bar at the last change (set on the first look)
	questXP = 0,                 -- experience of quests turned in, not matched to an XP gain yet
	unattributed = nil,          -- { level, zone, amount, group } gained, waiting for the quest turn-ins that go with it
	base = nil,                  -- { clock, total, thisLevel } from the last /played
	waiting = nil,               -- what the next TIME_PLAYED_MSG is for
}
T.state = state

-- Data ------------------------------------------------------------------------------------------

function T.Levels()
	ForeverRouteCharDB = ForeverRouteCharDB or {}
	ForeverRouteCharDB.levels = ForeverRouteCharDB.levels or {}
	return ForeverRouteCharDB.levels
end

function T.Entry(level)
	local db = T.Levels()
	local e = db[level]
	if not e then
		e = { quests = {}, mobs = {}, groupXP = 0, deaths = 0 }
		db[level] = e
		if level == 1 then e.started = 0 end   -- a new character starts with 0 seconds played
	end
	return e
end

-- Experience --------------------------------------------------------------------------------------

-- Experience `gain` earned at `level` in `zone`; `questXP` of it came from quests
-- turned in just now, the rest is killing (and anything else, e.g. discoveries).
-- Returns the part that was quest experience.
function T.Attribute(level, zone, gain, questXP, inGroup)
	local e = T.Entry(level)
	local fromQuest = math.min(gain, questXP or 0)
	local rest = gain - fromQuest
	if rest > 0 then
		local m = e.mobs[zone]
		if not m then m = { xp = 0, count = 0 }; e.mobs[zone] = m end
		m.xp = m.xp + rest
		m.count = m.count + 1
		if inGroup then e.groupXP = (e.groupXP or 0) + rest end
	end
	return fromQuest
end

-- A quest was turned in: record it under its zone. (As in RestedXP, a quest
-- turned in while in a group counts as group experience.)
function T.QuestTurnedIn(level, zone, questId, xp, inGroup)
	if type(xp) ~= "number" or xp <= 0 then return end
	local e = T.Entry(level)
	local q = e.quests[zone]
	if not q then q = {}; e.quests[zone] = q end
	q[questId] = xp
	if inGroup then e.groupXP = (e.groupXP or 0) + xp end
	state.questXP = state.questXP + xp
end

-- Puts the waiting experience into the books. Done a moment after the XP changed,
-- because the quest turn-in and the XP change can come in either order.
function T.Flush()
	local u = state.unattributed
	state.unattributed = nil
	if not u then return end
	T.Attribute(u.level, u.zone, u.amount, state.questXP, u.group)
	state.questXP = 0   -- a turn-in without experience change must not leak into the next gain
end

-- The XP bar changed: cur / max experience at `level`. Returns the gain.
function T.XPChanged(cur, max, level, zone, inGroup)
	local gain = 0
	local earnedAt = state.lastLevel
	if state.lastXP and earnedAt then
		if level == earnedAt then
			gain = cur - state.lastXP
		elseif level > earnedAt then
			gain = (state.lastMax - state.lastXP) + cur   -- through a level up
		end
	end
	state.lastXP, state.lastMax, state.lastLevel = cur, max, level
	if gain <= 0 or not earnedAt then return 0 end
	local u = state.unattributed
	if u and u.level ~= earnedAt then T.Flush(); u = nil end
	if not u then
		u = { level = earnedAt, zone = zone, amount = 0, group = inGroup }
		state.unattributed = u
	end
	u.amount = u.amount + gain
	return gain
end

function T.Death(level)
	local e = T.Entry(level)
	e.deaths = (e.deaths or 0) + 1
end

-- Time played ---------------------------------------------------------------------------------------

-- A /played answer: `total` seconds played, `thisLevel` of them at the current level.
-- `ctx` says what we asked for: { kind = "levelup", level = n, date = t } or nothing (login).
function T.PlayedReceived(total, thisLevel, now, serverTime, ctx, currentLevel)
	state.base = { clock = now, total = total, thisLevel = thisLevel }
	if ctx and ctx.kind == "levelup" then
		local prev = T.Entry(ctx.level - 1)
		prev.finished = total - 1
		prev.dateFinished = ctx.date or serverTime
		local cur = T.Entry(ctx.level)
		cur.started = total
		cur.dateStarted = ctx.date or serverTime
	else
		-- Login: a level we never saw begin starts as far back as the game says.
		local cur = T.Entry(currentLevel)
		if cur.started == nil then
			cur.started = math.max(0, total - thisLevel)
			cur.dateStarted = cur.dateStarted or (serverTime - thisLevel)
		end
	end
end

-- Seconds played at the current level right now.
function T.CurrentSeconds(now)
	local b = state.base
	if not b then return nil end
	return b.thisLevel + (now - b.clock)
end

-- Report data ------------------------------------------------------------------------------------------

-- Everything the report shows for one level, or nil when the level is unknown.
function T.Compile(level, currentLevel, currentSeconds)
	local e = T.Levels()[level]
	if not e then return nil end
	local r = { level = level, questXP = 0, mobXP = 0, zones = {}, deaths = e.deaths or 0, groupXP = e.groupXP or 0,
		isCurrent = (level == currentLevel) }
	local zoneXP = {}
	for zone, quests in pairs(e.quests or {}) do
		for _, xp in pairs(quests) do
			r.questXP = r.questXP + xp
			zoneXP[zone] = (zoneXP[zone] or 0) + xp
		end
	end
	for zone, m in pairs(e.mobs or {}) do
		r.mobXP = r.mobXP + m.xp
		zoneXP[zone] = (zoneXP[zone] or 0) + m.xp
	end
	for zone, xp in pairs(zoneXP) do r.zones[#r.zones + 1] = { name = zone, xp = xp } end
	table.sort(r.zones, function(a, b)
		if a.xp ~= b.xp then return a.xp > b.xp end
		return a.name < b.name
	end)
	r.totalXP = r.questXP + r.mobXP
	r.soloXP = math.max(0, r.totalXP - r.groupXP)
	r.started, r.finished = e.started, e.finished
	r.dateStarted, r.dateFinished = e.dateStarted, e.dateFinished
	if e.started and e.finished then
		r.seconds = e.finished - e.started
	elseif r.isCurrent then
		r.seconds = currentSeconds
	end
	return r
end

-- Seconds as "1d 2h 03min 04s".
function T.PrettyTime(s)
	if type(s) ~= "number" or s < 0 then return nil end
	s = math.floor(s)
	local d, h, m, sec = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60), s % 60
	if d > 0 then return string.format("%dd %dh %02dmin %02ds", d, h, m, sec) end
	if h > 0 then return string.format("%dh %02dmin %02ds", h, m, sec) end
	if m > 0 then return string.format("%dmin %02ds", m, sec) end
	return string.format("%ds", sec)
end

-- The report as plain text (RestedXP's report: speed, date, teamwork, sources,
-- zones, deaths, experience per hour; "N/A" where a share means nothing).
-- `isMax`: the level is the maximum one (nothing to share out).
function T.Format(r, isMax, dateFormat)
	local L = FR.L
	local out = {}
	local function Add(...) out[#out + 1] = string.format(...) end
	local missing = L["Missing data"]
	if isMax then
		Add("%s", string.format(L["Level %d (maximum)"], r.level))
	else
		Add("%s", string.format(L["Level %d to %d"], r.level, r.level + 1))
	end
	Add("")
	Add("%s: %s", L["Time spent"], T.PrettyTime(r.seconds) or missing)
	local reached = r.dateFinished
	local label = isMax and L["Reached the maximum level"] or string.format(L["Reached level %d"], r.level + 1)
	if not r.isCurrent or isMax then
		Add("%s: %s", label, reached and date(dateFormat or "%Y-%m-%d %H:%M", reached) or missing)
	end
	Add("%s: %s", string.format(L["Started level %d"], r.level), r.dateStarted and date(dateFormat or "%Y-%m-%d %H:%M", r.dateStarted) or missing)
	Add("")
	local na = isMax or r.totalXP == 0
	Add("%s", L["Teamwork"])
	if na then
		Add("   * %s: N/A", L["Solo"])
		Add("   * %s: N/A", L["Group"])
	else
		local group = 100 * math.min(r.groupXP, r.totalXP) / r.totalXP
		Add("   * %s: %.1f%%", L["Solo"], 100 - group)
		Add("   * %s: %.1f%%", L["Group"], group)
	end
	Add("%s", L["Experience sources"])
	if na then
		Add("   * %s: N/A", L["Quests"])
		Add("   * %s: N/A", L["Killing"])
	else
		local quests = 100 * r.questXP / r.totalXP
		Add("   * %s: %.1f%%", L["Quests"], quests)
		Add("   * %s: %.1f%%", L["Killing"], 100 - quests)
	end
	if not isMax and r.totalXP > 0 and #r.zones > 0 then
		Add("%s", L["Experience by zone"])
		for _, z in ipairs(r.zones) do Add("   * %s - %.1f%%", z.name, 100 * z.xp / r.totalXP) end
	end
	Add("")
	Add("%s: %d", L["Deaths"], r.deaths or 0)
	if not isMax and r.seconds and r.seconds > 0 and r.totalXP > 0 then
		Add("%s: %d", L["Experience per hour"], math.floor(r.totalXP / (r.seconds / 3600)))
	end
	return table.concat(out, "\n")
end

-- The highest level that has data, and the list of levels in order.
function T.LevelList()
	local list = {}
	for level in pairs(T.Levels()) do list[#list + 1] = level end
	table.sort(list)
	return list
end

-- Pace and time to the next level ----------------------------------------------------------------------
-- The pace is measured over the last half hour of play (the XP gains of this session). The first gain
-- of the window only starts the clock: it was earned before it. Without enough of a window the average
-- of the level so far is used (from the leveling data).

local samples = {}                 -- { time, gain }
local PACE_WINDOW, PACE_MIN = 1800, 300

function T.AddSample(gain, now)
	now = now or GetTime()
	samples[#samples + 1] = { now, gain }
	while samples[1] and now - samples[1][1] > PACE_WINDOW do table.remove(samples, 1) end
end

-- Experience per hour, or nil when there is nothing to base it on.
function T.XPPerHour(now)
	now = now or GetTime()
	while samples[1] and now - samples[1][1] > PACE_WINDOW do table.remove(samples, 1) end
	if #samples >= 3 then
		local span = now - samples[1][1]
		if span >= PACE_MIN then
			local sum = 0
			for i = 2, #samples do sum = sum + samples[i][2] end
			return sum / span * 3600
		end
	end
	local level = UnitLevel("player") or 1
	local seconds = T.CurrentSeconds(now)
	if seconds and seconds >= PACE_MIN then
		local r = T.Compile(level, level, seconds)
		if r and r.totalXP > 0 then return r.totalXP / seconds * 3600 end
	end
	return nil
end

-- Seconds until the next level at the current pace, or nil (unknown pace, maximum level).
function T.TimeToLevel(now)
	local level = UnitLevel("player") or 1
	if level >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then return nil end
	local rate = T.XPPerHour(now)
	if not rate or rate <= 0 then return nil end
	local remaining = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
	if remaining <= 0 then return nil end
	return remaining / rate * 3600, rate
end

local function ShortTime(s)
	local m = math.max(1, math.floor(s / 60 + 0.5))
	if m >= 60 then return string.format("%dh %02dm", math.floor(m / 60), m % 60) end
	return string.format("%dm", m)
end

local function XPText(rate)
	return rate >= 10000 and string.format("%.1fk", rate / 1000) or string.format("%d", math.floor(rate + 0.5))
end

-- "18.4k XP/h | 37m to 31" for the footer of the guide window (short: the footer is narrow), or nil.
function T.ETAText()
	local seconds, rate = T.TimeToLevel()
	if not seconds then return nil end
	return string.format(FR.L["%s XP/h | %s to %d"], XPText(rate), ShortTime(seconds), (UnitLevel("player") or 1) + 1)
end

-- The same as a sentence, for the tooltip of the footer.
function T.ETAFull()
	local seconds, rate = T.TimeToLevel()
	if not seconds then return nil end
	return string.format(FR.L["%s experience per hour, about %s to level %d"], XPText(rate), ShortTime(seconds),
		(UnitLevel("player") or 1) + 1)
end

-- Chat: no "time played" line for our own request ---------------------------------------------------

local silenced = {}

local function Silence()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local f = _G["ChatFrame" .. i]
		if f and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
			f:UnregisterEvent("TIME_PLAYED_MSG")
			silenced[#silenced + 1] = f
		end
	end
end

local function Unsilence()
	for _, f in ipairs(silenced) do f:RegisterEvent("TIME_PLAYED_MSG") end
	silenced = {}
end
T.Unsilence = Unsilence

-- Asks the game for /played without writing it into the chat.
function T.RequestPlayed()
	if not RequestTimePlayed then return end
	Silence()
	if C_Timer and C_Timer.After then C_Timer.After(5, Unsilence) end   -- never leave the chat silent
	RequestTimePlayed()
end

-- Events ------------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local registered = false
local EVENTS = { "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_DEAD", "TIME_PLAYED_MSG" }

local function MaxLevel()
	return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

local function Zone()
	local zone = GetRealZoneText and GetRealZoneText()
	if type(zone) ~= "string" or zone == "" or (issecretvalue and issecretvalue(zone)) then return "?" end
	return zone
end

-- Registers or drops the events by the setting and the level.
function T.Refresh()
	local want = FR:Get("enableTracker") and (UnitLevel("player") or 1) < MaxLevel()
	if want and not registered then
		for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
		registered = true
		state.level = UnitLevel("player")
		state.lastXP, state.lastMax, state.lastLevel = UnitXP and UnitXP("player"), UnitXPMax and UnitXPMax("player"), state.level
		T.Entry(state.level)
		state.waiting = nil
		T.RequestPlayed()
	elseif not want and registered then
		for _, e in ipairs(EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
		registered = false
	end
end

ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_XP_UPDATE" then
		local unit = ...
		if unit and unit ~= "player" then return end
		local level = UnitLevel("player")
		local gain = T.XPChanged(UnitXP("player"), UnitXPMax("player"), level, Zone(), IsInGroup and IsInGroup() or false)
		if gain > 0 then
			T.AddSample(gain)
			if C_Timer and C_Timer.After then C_Timer.After(0.3, T.Flush) else T.Flush() end
		end
	elseif event == "QUEST_TURNED_IN" then
		local questId, xp = ...
		if issecretvalue and (issecretvalue(questId) or issecretvalue(xp)) then return end
		T.QuestTurnedIn(state.level or UnitLevel("player"), Zone(), questId, tonumber(xp), IsInGroup and IsInGroup() or false)
	elseif event == "PLAYER_LEVEL_UP" then
		local level = ...
		level = tonumber(level) or UnitLevel("player")
		T.Flush()
		state.level = level
		T.Entry(level)
		state.waiting = { kind = "levelup", level = level, date = GetServerTime and GetServerTime() or time() }
		T.RequestPlayed()
		if level >= MaxLevel() then T.Refresh() end
	elseif event == "PLAYER_DEAD" then
		T.Death(state.level or UnitLevel("player"))
	elseif event == "TIME_PLAYED_MSG" then
		local total, thisLevel = ...
		if type(total) ~= "number" or type(thisLevel) ~= "number" then return end
		local ctx = state.waiting
		state.waiting = nil
		T.PlayedReceived(total, thisLevel, GetTime(), GetServerTime and GetServerTime() or time(), ctx, state.level or UnitLevel("player"))
		if C_Timer and C_Timer.After then C_Timer.After(0.1, Unsilence) else Unsilence() end
	end
end)
