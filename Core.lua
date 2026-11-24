-- ForeverRoute: core API that guide files register against.
local addonName, ns = ...

local FR = {}
_G.ForeverRoute = FR
ns.FR = FR

FR.addonName = addonName
FR.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "?"
FR.DIR = "Interface\\AddOns\\" .. addonName

-- API compatibility: newer clients moved many globals into C_* namespaces.
-- Always call these instead of the globals.
local function Pick(...)
	for i = 1, select("#", ...) do
		local f = select(i, ...)
		if type(f) == "function" then return f end
	end
end
FR.API = {
	GetItemCount = Pick(C_Item and C_Item.GetItemCount, GetItemCount) or function() return 0 end,
	IsEquippedItem = Pick(C_Item and C_Item.IsEquippedItem, IsEquippedItem),
	IsSpellKnown = Pick(C_SpellBook and C_SpellBook.IsSpellKnown, IsSpellKnown, IsPlayerSpell),
}
function FR.ItemCount(id)
	if not id then return 0 end
	local ok, n = pcall(FR.API.GetItemCount, id)
	return ok and tonumber(n) or 0
end
function FR.SpellKnown(id)
	local f = FR.API.IsSpellKnown
	if not (f and id) then return nil end
	local ok, r = pcall(f, id)
	if not ok then return nil end
	return r and true or false
end
function FR.ItemEquipped(id)
	local f = FR.API.IsEquippedItem
	if not (f and id) then return nil end
	local ok, r = pcall(f, id)
	if not ok then return nil end
	return r and true or false
end

-- Stat of the item worn in an equipment slot ("QUALITY", "LEVEL" or an
-- item stat such as ITEM_MOD_DAMAGE_PER_SECOND_SHORT); nil when unknown.
function FR.ItemStat(slot, stat)
	local id = GetInventoryItemID and GetInventoryItemID("player", slot)
	if not id then return nil end
	if stat == "QUALITY" then
		local q = GetInventoryItemQuality and GetInventoryItemQuality("player", slot)
		if q then return q end
		local _, _, quality = GetItemInfo(id)
		return quality
	elseif stat == "LEVEL" then
		local _, _, _, level = GetItemInfo(id)
		return level
	end
	local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
	if not (link and GetItemStats) then return nil end
	local ok, stats = pcall(GetItemStats, link)
	return ok and stats and stats[stat] or nil
end

-- Start and duration of an item or spell cooldown (nil when unknown).
function FR.Cooldown(kind, id)
	local ok, start, duration
	if kind == "item" then
		local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
		if not f then return nil end
		ok, start, duration = pcall(f, id)
	elseif kind == "spell" then
		if C_Spell and C_Spell.GetSpellCooldown then
			local okc, info = pcall(C_Spell.GetSpellCooldown, id)
			if okc and type(info) == "table" then return info.startTime, info.duration end
		end
		if not GetSpellCooldown then return nil end
		ok, start, duration = pcall(GetSpellCooldown, id)
	else
		return nil
	end
	if not ok then return nil end
	return start, duration
end

-- Is the unit under the aura (buff or debuff) with this spell id?
function FR.HasAura(id, unit)
	unit = unit or "player"
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and unit == "player" then
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if ok then return aura ~= nil end
	end
	for _, f in ipairs({ UnitBuff or false, UnitDebuff or false }) do
		if f then
			for i = 1, 40 do
				local ok, name, _, _, _, _, _, _, _, spellId = pcall(f, unit, i)
				if not ok or not name then break end
				if spellId == id then return true end
			end
		end
	end
	return false
end

FR.guides = {}        -- ordered list of guide records
FR.guidesByTitle = {}
FR.farmGuides = 0     -- guides whose group starts with "+" (farming guides, shown in gold mode)

-- The English guide files skip themselves when this is set. Like RestedXP,
-- ForeverRoute always loads them: the German translations (loaded on German
-- clients) only cover levels 1-22, the English route goes on to 60.
FR.localeGuides = false

function FR:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffForeverRoute:|r " .. tostring(msg))
end

-- Safe unit / zone reads ---------------------------------------------------------------------
-- In instances (and in some other places) this client hands out "secret values": reading them is
-- allowed, but comparing them, indexing with them or string functions on them raise an error. So
-- every value that comes from a unit or from the zone texts goes through these first. They return
-- nil for a value that is secret or missing.

-- nil when the value is secret.
function FR.Plain(value)
	if value == nil then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end
local Plain = FR.Plain

-- Name of a unit as a plain string, or nil.
function FR.SafeUnitName(unit)
	if type(unit) ~= "string" then return nil end
	local ok, name = pcall(UnitName, unit)
	name = ok and Plain(name) or nil
	if type(name) == "string" and name ~= "" then return name end
	return nil
end

-- Kind ("Creature", "Vehicle", "GameObject", "Player" ...) and NPC id of a unit, or nil.
function FR.UnitNpcId(unit)
	if type(unit) ~= "string" then return nil end
	local ok, guid = pcall(UnitGUID, unit)
	guid = ok and Plain(guid) or nil
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

-- Plain text from a zone / sub zone function ("" when unknown or secret).
function FR.SafeText(func, ...)
	if type(func) ~= "function" then return "" end
	local ok, text = pcall(func, ...)
	text = ok and Plain(text) or nil
	return type(text) == "string" and text or ""
end

function FR.InInstance()
	if not IsInInstance then return false end
	local ok, inInstance = pcall(IsInInstance)
	return ok and Plain(inInstance) == true
end

-- Error log ------------------------------------------------------------------------------------
-- Errors that come from ForeverRoute are kept in ForeverRouteDB.errors (last 25, equal ones are
-- counted), so they can be copied with /fr errors even when the game's error window is off.
local MAX_ERRORS = 25
local lastHandler

local function LogError(msg)
	local db = ForeverRouteDB
	if not db then return end
	msg = tostring(msg)
	local stack = ""
	if debugstack then
		local ok, s = pcall(debugstack, 3, 8, 0)
		if ok and type(s) == "string" then stack = s end
	end
	-- Only errors that have to do with this addon.
	if not (msg:find("ForeverRoute", 1, true) or stack:find("ForeverRoute", 1, true)) then return end
	db.errors = db.errors or {}
	for _, e in ipairs(db.errors) do
		if e.msg == msg then
			e.count = (e.count or 1) + 1
			e.time = time and time() or 0
			return
		end
	end
	local zone = FR.SafeText(GetRealZoneText)
	db.errors[#db.errors + 1] = {
		msg = msg, stack = stack, count = 1, time = time and time() or 0,
		zone = zone, instance = FR.InInstance(), version = FR.version,
	}
	while #db.errors > MAX_ERRORS do table.remove(db.errors, 1) end
end

-- Puts the logging handler in front of whatever handler is set. Called at login and again after
-- loading, because other addons replace the handler too.
function FR.InstallErrorLog()
	if not (geterrorhandler and seterrorhandler) then return end
	local current = geterrorhandler()
	if current == lastHandler then return end
	local previous = current
	lastHandler = function(msg, ...)
		pcall(LogError, msg)
		if previous then return previous(msg, ...) end
	end
	seterrorhandler(lastHandler)
end

-- Runs func(...) so that an error in it can never stop what called it, and never goes unseen: the
-- error is written to the chat once (the game's error window may be off) and to the error log.
-- Returns true plus the results of func, or false.
local reportedErrors = {}
function FR.Safe(label, func, ...)
	local n, args = select("#", ...), { ... }
	local results = { xpcall(function() return func(unpack(args, 1, n)) end, function(err)
		local text = tostring(err)
		if debugstack then
			local ok, stack = pcall(debugstack, 2, 6, 0)
			if ok and type(stack) == "string" then text = text .. "\n" .. stack end
		end
		return text
	end) }
	if results[1] then return true, unpack(results, 2, table.maxn and table.maxn(results) or #results) end
	local text = tostring(results[2])
	pcall(LogError, "ForeverRoute " .. label .. ": " .. text)
	local first = text:match("^[^\n]*") or text
	if not reportedErrors[label .. first] then
		reportedErrors[label .. first] = true
		FR:Print("|cffff5555" .. label .. " failed:|r " .. first .. "  (/fr errors)")
	end
	return false
end

-- Text of the log (for /fr errors).
function FR.ErrorLogText()
	local errors = ForeverRouteDB and ForeverRouteDB.errors
	if not errors or #errors == 0 then return "" end
	local lines = { "ForeverRoute v" .. tostring(FR.version) }
	for i = #errors, 1, -1 do
		local e = errors[i]
		lines[#lines + 1] = string.format("[%d] %s x%d - %s%s", #errors - i + 1,
			date and date("%Y-%m-%d %H:%M", e.time or 0) or "?", e.count or 1, e.zone ~= "" and e.zone or "?",
			e.instance and " (instance)" or "")
		lines[#lines + 1] = tostring(e.msg)
		if e.stack and e.stack ~= "" then lines[#lines + 1] = e.stack end
		lines[#lines + 1] = ""
	end
	return table.concat(lines, "\n")
end

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Where a guide sits in its file. The German and the English file of a guide
-- hold the same guides in the same order, and every file starts with
-- ForeverRoute.guideFile = "<same id in both languages>" (tools\Update-Guides.ps1),
-- so (file, number in file) pairs a German guide with its English twin.
FR.guideCount = {}   -- ["lang|file"] = guides called so far
FR.guideSlots = {}   -- ["lang|file#n"] = guide

-- Title of a translated guide whose plain title is taken by the English one.
function FR.LangTitle(title, lang) return title .. " [" .. tostring(lang) .. "]" end

-- Guide files call ForeverRoute.RegisterGuide([[ ...guide text... ]]).
-- Only the header (lines before the first "step") is read here; steps are
-- parsed when the guide is opened. Returns the guide, or nil and the reason
-- (not for this player, no name, already there).
function FR.RegisterGuide(a, b)
	local text = type(a) == "string" and a or b
	if type(text) ~= "string" then return nil, "no text" end

	-- Counted before any early return: a guide that is not for this player still
	-- takes its number, so the numbers of both languages stay in line.
	local lang = FR.loadingLocale or "enUS"   -- set at the top of each guide file
	local file, index = FR.guideFile, nil
	if file then
		local slot = lang .. "|" .. file
		index = (FR.guideCount[slot] or 0) + 1
		FR.guideCount[slot] = index
	end

	local header = {}
	for line in text:gmatch("[^\r\n]+") do
		line = Trim(line)
		if line:sub(1, 4) == "step" then break end
		local code, tag = line:match("^(.-)%s*<<%s*(.+)$")
		if code then
			if code == "" then
				-- "<< Horde" on its own line: the whole guide is for those players.
				if not FR.Applies(tag) then return nil, "not for this player" end
				header.enabledFor = tag
				line = ""
			elseif FR.Applies(tag) then
				line = code
			else
				line = ""
			end
		end
		local k, v = line:match("^#(%S+)%s*(.*)$")
		if k and header[k] == nil then header[k] = Trim(v) end
	end
	if not header.name then return nil, "no #name line" end

	-- Game version tags: keep guides made for Forever or Classic.
	local tagged = header.classic or header.tbc or header.wotlk or header.cata or header.retail
		or header.df or header.forever or header.mop
	if tagged and not (header.forever or header.classic) then return nil, "for another game version" end
	if header.season and not header.season:find("[01]") then return nil, "for another season" end   -- Season of Discovery only
	if header.som then return nil, "for another season" end                                          -- Season of Mastery only

	local group = header.group or "Guides"
	local title = group .. "\\" .. header.name
	local taken = FR.guidesByTitle[title]
	if taken then
		-- The same group and name in the same language is a duplicate. In another language it is the
		-- translation of the same guide (the German guides keep the English names): English keeps the
		-- plain title (saved progress, #include and #next point at it), the translation is listed as
		-- "Group\Name [deDE]" and is found by FR.FindGuide for guides of its own language.
		if taken.lang == lang then return nil, "already there" end
		if lang == "enUS" then
			local moved = FR.LangTitle(title, taken.lang)
			if FR.guidesByTitle[moved] then return nil, "already there" end
			FR.guidesByTitle[title] = nil
			taken.title = moved
			FR.guidesByTitle[moved] = taken
		else
			title = FR.LangTitle(title, lang)
			if FR.guidesByTitle[title] then return nil, "already there" end
		end
	end
	local g = {
		title = title,
		name = header.name,
		short = header.displayname or header.name,
		group = group,
		subgroup = header.subgroup,
		next = header.next,
		defaultfor = header.defaultfor,
		header = header,
		raw = text,
		order = #FR.guides + 1,
		lang = lang,
		file = file,
		fileIndex = index,
		-- A group starting with "+" holds farming guides (RestedXP: Gold Assistant).
		farm = group:sub(1, 1) == "+" or nil,
	}
	if g.farm then FR.farmGuides = FR.farmGuides + 1 end
	table.insert(FR.guides, g)
	FR.guidesByTitle[title] = g
	if file then FR.guideSlots[lang .. "|" .. file .. "#" .. index] = g end

	-- ".enabledungeon RFC" / ".enabledungeon !RFC" lines sit inside steps, but
	-- they speak for the whole guide group: the guides of a dungeon group name
	-- the dungeons they need (RestedXP: addon.dungeonOverride).
	if text:find(".enabledungeon", 1, true) then
		for line in text:gmatch("[^\r\n]+") do
			local bang, name = line:match("^%s*%.enabledungeon%s+(!?)([^%s>]+)")
			if name then
				local cond = line:match("<<%s*(.+)$")
				local tag = FR.DungeonTag(name)
				if tag and (not cond or FR.Applies(cond)) then
					local o = FR.dungeonOverride[group]
					if not o then o = {}; FR.dungeonOverride[group] = o end
					o[tag] = (bang == "")
				end
			end
		end
	end
	return g
end

-- Takes a guide out of the lists again (a deleted import, or an import that did
-- not read). If it is the open guide, the suggested one opens instead.
function FR:UnregisterGuide(g)
	for i, x in ipairs(self.guides) do
		if x == g then table.remove(self.guides, i) break end
	end
	for i, x in ipairs(self.guides) do x.order = i end
	if self.guidesByTitle[g.title] == g then self.guidesByTitle[g.title] = nil end
	if g.farm then FR.farmGuides = math.max(0, FR.farmGuides - 1) end
	if g.file and g.fileIndex then
		self.guideSlots[(g.lang or "enUS") .. "|" .. g.file .. "#" .. g.fileIndex] = nil
	end
	if g.imported and ForeverRouteDB and ForeverRouteDB.imports then ForeverRouteDB.imports[g.title] = nil end
	self:ClearMarks(g.title)
	if self.current == g then
		self.current = nil
		local suggested = self:FindSuggestedGuide()
		if suggested then self:SetGuide(suggested, 1) elseif self.UpdateUI then self:UpdateUI() end
	end
end

-- The group of a guide under its English name. The translated files name their groups in their
-- own language ("Forever Route", "Guía Forever" ...): a guide with an English twin takes the twin's
-- group, and every translated group name met on such a pair is remembered (FR.groupCanon), so a
-- guide whose translation is older (no twin: other level range) still maps to the English group.
FR.groupCanon = {}
function FR.CanonGroup(g)
	if not g then return nil end
	return (g.pair and g.pair.group) or FR.groupCanon[g.group] or g.group
end

-- Pairs every translated guide with its English twin (same file, same number in the
-- file) so its steps can be completed from the English guide where the German
-- translation is behind (Parser.lua, MergeWithEnglish). Only guides whose names
-- start with the same level range are paired; a pair that does not look right
-- is left alone. Run once after all guide files have loaded.
function FR.PairGuides()
	local paired = 0
	FR.groupCanon = {}
	for _, g in ipairs(FR.guides) do
		g.pair = nil
		if g.lang ~= "enUS" and g.file then
			local en = FR.guideSlots["enUS|" .. g.file .. "#" .. g.fileIndex]
			if en then
				local a, b = tostring(g.name):match("^(%d+%-%d+)"), tostring(en.name):match("^(%d+%-%d+)")
				-- Same level range, or a translated name without any level range ("Lauft zum Dorf ...").
				-- Same level range, a translated name without any level range ("Lauft zum Dorf ..."), or guides
				-- without a level range whose names are the same ("01. Hall of Thanes", "Hyjal").
				if (a and a == b) or (not a and (b or g.name == en.name)) then
					g.pair = en
					paired = paired + 1
					if FR.groupCanon[g.group] == nil then FR.groupCanon[g.group] = en.group end
				end
			end
		end
	end
	return paired
end

-- Dungeons -----------------------------------------------------------------------
-- Tags as the guides write them (".dungeon WC"). The area id gives the name in
-- the client's language (same ids as RestedXP's DB\forever\db.lua); the English
-- name is the fallback. Order = level order, as shown in the settings.
FR.DUNGEONS = {
	{ "RFC", 2437, "Ragefire Chasm" },
	{ "WC", 718, "Wailing Caverns" },
	{ "SFK", 209, "Shadowfang Keep" },
	{ "DM", 1581, "The Deadmines" },
	{ "BFD", 719, "Blackfathom Deeps" },
	{ "STOCKS", 717, "The Stockade" },
	{ "GNOMER", 133, "Gnomeregan" },
	{ "RFK", 491, "Razorfen Kraul" },
	{ "SM", 796, "Scarlet Monastery" },
	{ "RFD", 722, "Razorfen Downs" },
	{ "ULDA", 1337, "Uldaman" },
	{ "ZF", 978, "Zul'Farrak" },
	{ "MARA", 2100, "Maraudon" },
	{ "ST", 1417, "Sunken Temple" },
	{ "BRD", 1584, "Blackrock Depths" },
	{ "HOT", 16919, "Hall of Thanes" },
	{ "ROL", 153, "Ruins of Lordaeron" },
}
local dungeonByTag = {}
for _, d in ipairs(FR.DUNGEONS) do dungeonByTag[d[1]] = d end
local DUNGEON_ALIAS = {
	DEADMINES = "DM", VC = "DM", STOCKADES = "STOCKS", ["TEMPLE OF ATAL'HAKKAR"] = "ST",
}

-- [group][tag] = true / false from ".enabledungeon" lines (see RegisterGuide).
FR.dungeonOverride = {}

-- "wc", "Mara", "Deadmines" -> "WC", "MARA", "DM"; nil for an empty name.
function FR.DungeonTag(name)
	name = Trim(tostring(name or "")):upper()
	if name == "" then return nil end
	return DUNGEON_ALIAS[name] or name
end

function FR.DungeonName(tag)
	local d = dungeonByTag[tag]
	if not d then return tag end
	if C_Map and C_Map.GetAreaInfo then
		local ok, name = pcall(C_Map.GetAreaInfo, d[2])
		if ok and type(name) == "string" and name ~= "" then return name end
	end
	return d[3]
end

-- The dungeon tag of a guide that is nothing but that dungeon's run ("31-31 Gnomeregan",
-- "30-31 Razorfen Kraul" ...), or nil. Such a guide has one ".enabledungeon TAG" line and its steps
-- carry no ".dungeon" tags, so turning the dungeon off hides none of them: the guide has to be passed
-- over as a whole (FR:IsGuideEmpty). Mixed guides ("30-32 Duskwood/Gnomeregan": zone steps plus the
-- dungeon) have the line too but are named differently and stay. Judged on the English twin of a
-- translated guide, so it is the same in every language. The result is kept in g.dungeonOnly.
function FR.DungeonOnlyTag(g)
	if g.dungeonOnly ~= nil then return g.dungeonOnly or nil end
	g.dungeonOnly = false
	local src = g.pair or g
	local text = src.raw
	if type(text) == "string" and text:find(".enabledungeon", 1, true) then
		local base = tostring(src.name or ""):gsub("^[%d%-%.]+%s*", ""):lower()
		for line in text:gmatch("[^\r\n]+") do
			local bang, name = line:match("^%s*%.enabledungeon%s+(!?)([^%s>]+)")
			if name and bang == "" then
				local cond = line:match("<<%s*(.+)$")
				local tag = FR.DungeonTag(name)
				local d = tag and dungeonByTag[tag]
				if d and (not cond or FR.Applies(cond)) and base == d[3]:lower() then
					g.dungeonOnly = tag
					break
				end
			end
		end
	end
	return g.dungeonOnly or nil
end

-- What the guide group itself wants for this dungeon (".enabledungeon" lines):
-- true / false, or nil when it says nothing. Only a default: the player's own
-- choice (ForeverRouteDB.dungeons[tag], true or false) wins over it.
function FR.DungeonDefault(tag, group)
	local o = group and FR.dungeonOverride[group]
	if o then return o[tag] end
end

-- Old name; nothing is fixed any more.
function FR.DungeonLocked() return nil end

-- Does this guide have dungeon steps at all? The normal "Leveling Route" guides are
-- marked "#disabledungeons": their dungeon variants are the "with Dungeons" guides.
function FR.HasDungeonSteps(g)
	return g ~= nil and not (g.header and g.header.disabledungeons)
end

-- The dungeons split as RestedXP 4.11.36 shows them: the ones the guide's group turns on
-- (".enabledungeon") are "required" for that route, the others "optional". Two lists of tags in
-- the order of FR.DUNGEONS. A guide without dungeon steps has no required ones.
function FR.SplitDungeons(g)
	local required, optional = {}, {}
	for _, d in ipairs(FR.DUNGEONS) do
		if FR.HasDungeonSteps(g) and FR.DungeonDefault(d[1], g.group) == true then
			required[#required + 1] = d[1]
		else
			optional[#optional + 1] = d[1]
		end
	end
	return required, optional
end

-- Is the dungeon on, as the lists show it? The player's choice; without one the
-- default of the open guide's group, and off in a guide without dungeon steps.
function FR.DungeonShown(tag, g)
	local d = ForeverRouteDB and ForeverRouteDB.dungeons
	local v = d and d[tag]
	if v ~= nil then return v and true or false end
	if FR.HasDungeonSteps(g) then return FR.DungeonDefault(tag, g.group) == true end
	return false
end

-- Is the dungeon on for guide `g` (which steps show)? A guide marked
-- "#disabledungeons" has none, otherwise the same as DungeonShown.
function FR.DungeonEnabled(tag, g)
	if g and g.header and g.header.disabledungeons then return false end
	return FR.DungeonShown(tag, g)
end

-- Turns a dungeon on or off. Which steps show changes, so the parsed steps of
-- every guide are dropped and the open guide is read again. Turning one on in a
-- guide without dungeon steps moves to the matching route with dungeons.
function FR:SetDungeon(tag, value)
	if not ForeverRouteDB then return end
	ForeverRouteDB.dungeons = ForeverRouteDB.dungeons or {}
	value = value and true or false
	local before = FR.DungeonShown(tag, self.current)
	ForeverRouteDB.dungeons[tag] = value
	if before == value then return end
	if self.DungeonsChanged then self:DungeonsChanged(value) end
end

-- Recommended dungeons, as RestedXP scores them (SettingsPanel.lua,
-- ScoreDungeons / SetRecommended; the numbers are in DungeonStats.lua):
-- score = travel * 0.7 + quest * 1.2 + value for the player's class * 1.4, and
-- a dungeon is recommended above 7. On the Alliance side STOCKS and ULDA always
-- score 9, and so does SM for Paladins and Warriors. nil: no figures for this dungeon.
function FR.DungeonScore(tag)
	local _, class = UnitClass("player")
	local faction = UnitFactionGroup("player")
	local stats = FR.DUNGEON_STATS and FR.DUNGEON_STATS[faction]
	local d = stats and stats[tag]
	if not d then return nil end
	if faction == "Alliance" then
		if tag == "STOCKS" or tag == "ULDA" then return 9 end
		if tag == "SM" and (class == "PALADIN" or class == "WARRIOR") then return 9 end
	end
	return (d.travel or 0) * 0.7 + (d.quest or 0) * 1.2 + (d[class] or 0) * 1.4
end

function FR.DungeonRecommended(tag)
	local score = FR.DungeonScore(tag)
	return score ~= nil and score > 7
end

-- Turns the recommended dungeons on and every other one with figures off.
-- Dungeons without figures (Hall of Thanes, Ruins of Lordaeron) are left as
-- they are.
function FR:SetRecommendedDungeons()
	if not ForeverRouteDB then return end
	ForeverRouteDB.dungeons = ForeverRouteDB.dungeons or {}
	local g = self.current
	local changed, turnedOn = false, false
	for _, d in ipairs(FR.DUNGEONS) do
		local tag = d[1]
		local score = FR.DungeonScore(tag)
		if score ~= nil then
			local on = score > 7
			if FR.DungeonShown(tag, g) ~= on then
				changed = true
				if on then turnedOn = true end
			end
			ForeverRouteDB.dungeons[tag] = on
		end
	end
	if changed and self.DungeonsChanged then self:DungeonsChanged(turnedOn) end
end

-- Every dungeon on or off at once (the guide is read again only once).
function FR:SetAllDungeons(value)
	if not ForeverRouteDB then return end
	ForeverRouteDB.dungeons = ForeverRouteDB.dungeons or {}
	value = value and true or false
	local g = self.current
	local changed = false
	for _, d in ipairs(FR.DUNGEONS) do
		if FR.DungeonShown(d[1], g) ~= value then changed = true end
		ForeverRouteDB.dungeons[d[1]] = value
	end
	if changed and self.DungeonsChanged then self:DungeonsChanged(value) end
end

-- Finds a guide by "Group\Name", or by name within a group. `lang` is the language of the guide
-- that asks (#include, #next): where the guide exists in that language, that one is meant.
function FR:FindGuide(ref, group, lang)
	if not ref then return nil end
	ref = Trim(ref)
	if lang and lang ~= "enUS" then
		local t = self.guidesByTitle[FR.LangTitle(ref, lang)]
			or (group and self.guidesByTitle[FR.LangTitle(group .. "\\" .. ref, lang)])
		if t then return t end
	end
	if self.guidesByTitle[ref] then return self.guidesByTitle[ref] end
	if group and self.guidesByTitle[group .. "\\" .. ref] then return self.guidesByTitle[group .. "\\" .. ref] end
	local first
	for _, g in ipairs(self.guides) do
		if g.name == ref then
			if not lang or g.lang == lang then return g end
			first = first or g
		end
	end
	return first
end

-- Settings -------------------------------------------------------------------

FR.defaults = {
	locked = false,        -- window and arrow cannot be dragged
	scale = 1.0,           -- window scale
	width = 280,           -- window width in pixels
	height = 180,          -- step list height in pixels
	alpha = 0.9,           -- background opacity
	fontSize = 11,         -- text size in the guide window, in screen pixels
	font = "opensans",     -- see FR.FONTS in UI.lua
	targetMacro = true,    -- keep the FRTarget macro up to date (like RestedXP's RXPTargeting)
	markTargets = true,    -- clicking a target button also sets a raid icon on the creature
	hardcoreMode = "auto", -- "auto" (the server decides), "on" or "off": which "#hardcore"/"#softcore" steps show
	enableTracker = true,         -- record the experience and time of each level (Tracker.lua)
	showLevelETA = true,          -- the guide window's footer shows the pace and the time to the next level
	autoPassNotice = true,        -- say when the guide passes steps that were already done (History.lua)
	skipUnavailable = true,       -- pass "accept" steps of quests Questie says cannot be taken (Engine.lua, needs the Questie addon)
	autoFly = false,              -- a "Fly to ..." step flies there as soon as the flight master's map opens (Events.lua; Shift = off)
	autoBank = true,              -- ".bankdeposit / .bankwithdraw" steps move their items when the bank is open (Bank.lua; Shift = off)
	enableInventoryManager = true, -- RestedXP's Inventory Manager (Inventory.lua): the master switch of the five below
	showJunkIcon = false,         -- a coin on junk items in the bags
	rightClickJunk = false,       -- modifier + right click on a bag item marks / unmarks it as junk
	rightClickMod = "CTRL",       -- "CTRL", "ALT" or "CTRL+ALT"
	autoSellJunk = false,         -- sell junk when a vendor window opens
	autoDiscardItems = false,     -- delete the cheapest junk when every bag is full
	maxSoulShards = 100,          -- Warlocks: soul shards above this many count as junk
	partySteps = true,            -- share your steps with ForeverRoute players in your party and show theirs
	partyStepsScale = 1.0,
	partyStepsBackground = true,
	enableEmergency = true,       -- outline the action buttons of healing items / spells when health is low
	emergencyAnimation = true,    -- the outline pulses
	emergencyThreshold = 0.2,     -- "low" = health below this fraction
	enableDrowningWarning = true, -- warn when the breath runs out
	drowningSound = true,
	drowningFlash = true,         -- red screen pulse
	drowningThreshold = 0.2,      -- warn below this fraction of the breath bar
	customPlates = false,  -- ForeverRoute draws its own name plates: bars for enemies, names only for friendly NPCs (Plates.lua). Off by default: the game's plates, only the step icon is added (Nameplates.lua)
	plateScale = 1.0,      -- size of the plates
	plateNpc = "game",     -- friendly NPC plates: "game" (the game's own name-only plate, like friendly players), "own" (only the name, drawn by us in the game's font) or "classic" (bar, frame, level badge)
	plateNameY = -28,      -- height of the name of "own" above the middle of the plate
	plateNameScale = 1.0,  -- size of friendly NPC names ("game" and "own") at a camera distance of 15 yards (they follow the camera, see plateNameDistance)
	plateNameWeight = 0.5, -- "own" text: how heavy the strokes are, 0 (as copied) to 1 (full faux bold)
	plateNameDistance = 1.4, -- how strongly friendly NPC names shrink with the camera distance (the game's names go roughly with distance^-1.4; 0 = constant size)
	plateHideGameNames = false, -- switch the game's own floating NPC names off while our plates draw the names (no visible swap at the plate range, but no names beyond it)
	plateBorder = true,    -- the beveled frame of the Classic NPC plate and the thin edge of enemy bars
	nameplateIcons = true, -- mark the creatures of the current step on the plates (Nameplates.lua, Plates.lua)
	nameplateScale = 1.0,  -- size of that marker
	plateMarker = "quest", -- "quest" (the yellow !), "raid" (skull, cross, ... as on the target buttons) or "both"
	plateProgress = true,  -- show how many of a step enemy are still needed ("2/8")
	barSize = 28,          -- size of the buttons of active items / targets, in pixels
	theme = "default",
	showList = true,       -- show the list of all steps under the guide name
	hideCompleted = false, -- hide finished steps in that list
	showTips = true,
	showActiveItems = true,   -- clickable quest items of the current step
	showActiveTargets = true, -- clickable target buttons for NPCs / enemies
	autoAdvance = true,    -- skip finished steps automatically
	autoArrive = true,     -- complete travel goals on arrival
	arriveRadius = 10,     -- yards, when the guide gives none
	showArrow = true,
	arrowScale = 1.0,
	mapPins = true,        -- numbered step pins on the world map
	minimapPins = true,    -- the same numbers on the minimap
	autoAccept = true,     -- accept the guide's quests automatically
	autoTurnin = true,
	autoGossip = true,     -- pick the gossip options the guide asks for (.skipgossip)     -- turn in the guide's quests automatically
	showMinimap = true,
	minimapAngle = 200,
	language = "auto",     -- "auto" (game language), "enUS" or "deDE"
	hidden = false,
}

function FR:InitDB()
	ForeverRouteDB = ForeverRouteDB or {}
	local db = ForeverRouteDB
	-- Older versions stored the arrow toggle as "arrow".
	if db.arrow == false and db.showArrow == nil then db.showArrow = false end
	db.arrow = nil
	-- Settings of the plate system before 2.9 (Plater support, per-category looks): gone.
	for _, k in ipairs({ "autoEnablePlates", "nameplateX", "nameplateY", "plateOwner", "plateFont",
		"iconsWithPlater", "plates", "platesNpcLook" }) do
		db[k] = nil
	end
	-- Since 2.9.1 friendly NPCs use the game's own name text by default (earlier choices were test versions).
	if (db.plateNpcVersion or 0) < 1 then
		db.plateNpc = "game"
		db.plateNpcVersion = 1
	end
	-- Calibration against the game's own names (2.9.2): the old defaults of the size and height of friendly NPC
	-- names were too big / too high once the size follows the camera. Values the player changed stay.
	if (db.plateNameCalib or 0) < 1 then
		if db.plateNameScale == 1.8 then db.plateNameScale = 1.1 end
		if db.plateNameY == -12 then db.plateNameY = -28 end
		db.plateNameCalib = 1
	end
	-- Calibration 2.9.6: the names follow the camera distance with the exponent 1.4 and the size 1.0 matches the
	-- game's names. The old defaults (size 1.1, distance 1.0 / 0.6) become the new ones; values the player set stay.
	if (db.plateNameDistCalib or 0) < 2 then
		if db.plateNameDistance == 1.0 or db.plateNameDistance == 0.6 then db.plateNameDistance = 1.4 end
		if db.plateNameScale == 1.1 then db.plateNameScale = 1.0 end
		db.plateNameDistCalib = 2
	end
	-- 2.9.7: the game's own NPC names stay on by default (with them off, friendly NPCs beyond the plate range had no
	-- name at all). The saved CVar value is put back by FR:ApplyNpcNames.
	if (db.plateHideGameNamesVersion or 0) < 1 then
		db.plateHideGameNames = false
		db.plateHideGameNamesVersion = 1
	end
	-- 2.9.9: ForeverRoute's own name plates are off by default (the game's plates plus the step icon). Once for existing
	-- profiles; whoever wants them switches them on in the settings.
	if (db.customPlatesVersion or 0) < 1 then
		db.customPlates = false
		db.customPlatesVersion = 1
	end
	-- 2.9.8: the enemy bars are bigger; a plate size below 1 was set when they were tiny. The slider stays.
	if (db.plateScaleVersion or 0) < 1 then
		if type(db.plateScale) == "number" and db.plateScale < 1 then db.plateScale = 1.0 end
		db.plateScaleVersion = 1
	end
	for k, v in pairs(self.defaults) do
		if db[k] == nil then db[k] = v end
	end
	db.dungeons = db.dungeons or {}   -- [tag] = true / false: the player's choice; no entry = the guide's default
	ForeverRouteCharDB = ForeverRouteCharDB or {}
	-- Until 2.5 the ticks were stored under step numbers. Steps are known by a key
	-- now (see FR.StepKey); the old ticks cannot be moved over reliably (the guides
	-- were updated in between), so they start again. What the game knows - quests,
	-- items, level - ticks itself again.
	if ForeverRouteCharDB.marksV ~= 2 then
		ForeverRouteCharDB.marks = {}
		ForeverRouteCharDB.marksV = 2
	end
	ForeverRouteCharDB.marks = ForeverRouteCharDB.marks or {}
	self.db = db
end

function FR:Get(key)
	local db = ForeverRouteDB
	local v = db and db[key]
	if v == nil then return self.defaults[key] end
	return v
end

function FR:Set(key, value)
	if not ForeverRouteDB then return end
	ForeverRouteDB[key] = value
	if self.ApplySettings then self:ApplySettings(key) end
end
