-- Reads RestedXP-format guide text into steps and elements.
--
--   step << Warrior/Mage          step only for these players
--       #completewith next        shown alongside later steps until "next" is done
--       #sticky / #label X / #requires X / #hardcore / #softcore ...
--       .goto 1420/0,1667.77,1679.04,10 >> Run up out of the crypt
--       >>Talk to |cRXP_FRIENDLY_Mordo|r
--       .accept 363 >> Accept Rude Awakening
--       .complete 376,1 --Damaged Necrotic Etching (5)
--       .target Undertaker Mordo
--       +Manual note with a checkbox
local _, ns = ...
local FR = ns.FR

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Text formatting ------------------------------------------------------------------

local COLORS = {
	RXP_FRIENDLY_ = "ff00ff25", RXP_ENEMY_ = "ffff5722", RXP_LOOT_ = "ff00bcd4",
	RXP_WARN_ = "fffcdc00", RXP_PICK_ = "ffdb2eef", RXP_BUY_ = "ff3fd147",
}

-- Inline textures get the line height so icons line up with the text.
local function FixTexture(spec)
	local path, rest = spec:match("^([^:]+)(.*)$")
	if not path then return "|T" .. spec .. "|t" end
	local parts = {}
	for p in rest:gmatch(":([^:]*)") do parts[#parts + 1] = p end
	parts[1] = "0"
	parts[2] = "0"
	parts[3] = parts[3] or "0"
	-- Icons sit 1-2 px too high on the text line; lower them.
	if not parts[4] or parts[4] == "0" then parts[4] = "-2" end
	return "|T" .. path .. ":" .. table.concat(parts, ":") .. "|t"
end

function FR.FormatText(text)
	if not text then return nil end
	-- "|cRXP_FRIENDLY_Ailee Farheart::251362|r": the number is an NPC id for the
	-- guide's own bookkeeping, not part of the name.
	text = text:gsub("::%d+", "")
	text = text:gsub("|c(RXP_%u+_)", function(k) return "|c" .. (COLORS[k] or "ffffffff") end)
	text = text:gsub("|T(.-)|t", FixTexture)
	text = text:gsub("\\n", "\n")
	-- Guide credits live in Guides\LICENSE.txt; the window shows our name.
	text = text:gsub("RestedXP", "ForeverRoute")
	return text
end

-- Waypoints --------------------------------------------------------------------------

-- "1420/0" = map 1420 with world coordinates on continent 0,
-- "Tirisfal Glades" or "1420" = map with 0-100 coordinates.
local function MakeWaypoint(zone, x, y)
	if not (zone and x and y) then return nil end
	local mapStr, cont = tostring(zone):match("^(%d+)/(%d+)$")
	if mapStr then
		return { mapID = tonumber(mapStr), cont = tonumber(cont), worldX = x, worldY = y, world = true }
	end
	local mapID = tonumber(zone) or FR:GetZoneID(Trim(zone))
	if not mapID then return nil end
	return { mapID = mapID, x = x, y = y }
end

-- Element handlers -----------------------------------------------------------------------
-- Each gets (args, text, ctx, step) and returns an element table or nil.
--   textOnly = true  -> shown without a checkbox, never blocks the step
--   cond     = name  -> condition that can skip the whole step
--   hidden   = true  -> not shown in the window

local H = {}

local function Num(v) return tonumber(v) end
local function Ids(args)
	local t = {}
	for _, v in ipairs(args) do
		for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
	end
	return t
end
-- ".target Name", ".mob +Name::1234", ".unitscan A;B": names are separated by ";",
-- a leading "+" only marks the line as the parent of the list, and "::1234"
-- is the NPC id (kept apart so names match the game's text).
-- Returns the names and a { [name] = npcId } table (nil when there are no ids).
local function Names(args)
	local t, ids = {}, nil
	for _, v in ipairs(args) do
		for part in tostring(v):gmatch("[^;]+") do
			part = Trim((part:gsub("^%s*%+", "")))
			local name, id = part:match("^(.-)%s*::(%d+)$")
			if name then
				part = name
				ids = ids or {}
				ids[name] = tonumber(id)
			end
			if part ~= "" then t[#t + 1] = part end
		end
	end
	return t, ids
end

H["goto"] = function(a, text, ctx)
	local zone, x, y, radius, low = a[1], Num(a[2]), Num(a[3]), Num(a[4]), a[5]
	if tonumber(a[1]) and not Num(a[3]) then
		-- ".goto x,y" continues in the last zone.
		zone, x, y, radius, low = ctx.lastZone, Num(a[1]), Num(a[2]), Num(a[3]), a[4]
	end
	if zone then ctx.lastZone = zone end
	local wp = MakeWaypoint(zone, x, y)
	if not wp then return text and { text = text, textOnly = true } or nil end
	local e = { kind = "goto", wp = wp, text = text }
	if radius and radius ~= 0 then wp.radius = math.abs(radius) end
	-- With a radius and no low-priority flag, arriving completes the element.
	-- With the flag it is a point on a path; without radius just a pin.
	e.lowPrio = (low ~= nil) or not wp.radius
	e.arrive = wp.radius ~= nil and not e.lowPrio
	e.textOnly = not e.arrive
	e.hidden = not text
	-- Path points (radius plus the optional flag) only steer the arrow; they
	-- get no number on the map, like in RestedXP.
	e.hidePin = (low ~= nil) and (wp.radius ~= nil) or nil
	return e
end
H.waypoint = H["goto"]
H.groundgoto = H["goto"]
H.flygoto = H["goto"]

local function Quest(kind)
	return function(a, text)
		local qid = Num(a[1])
		if not qid then return nil end
		-- ".turnin -1234" (RestedXP): the line is optional, it counts as done when the quest is
		-- not in the log. The id itself is the positive one (auto turn-in, quest title, flags).
		local e = { kind = kind, qid = math.abs(qid), text = text }
		if qid < 0 and kind == "turnin" then e.skipIfMissing = true end
		return e
	end
end
H.accept = Quest("accept")
H.daily = Quest("accept")
H.turnin = Quest("turnin")
H.dailyturnin = Quest("turnin")
-- ".convertquest a,b" only tells RestedXP that one quest id replaces another: nothing to show.
H.convertquest = function() return nil end

H.complete = function(a, text)
	local qid, obj = Num(a[1]), Num(a[2])
	if not (qid and obj) then return nil end
	local e = { kind = "complete", qid = math.abs(qid), obj = obj, need = Num(a[3]), text = text }
	if qid < 0 then e.skipIfMissing = true end
	return e
end

-- .collect item,count,questID,objFlags,flags (RestedXP): the line is done
-- when the items are in the bags or the quest has been turned in. objFlags
-- is a bit mask of quest objectives and only counts with flag 4 ("done when
-- these objectives are done"). Flag 1 = no checkbox, 16 = turn-in does not
-- count; a negative flag means "subtract quest progress" (and no checkbox).
local function HasBit(v, b) return math.floor(v / b) % 2 == 1 end

H.collect = function(a, text)
	local item = Num(a[1])
	if not item then return nil end
	local e = { kind = "collect", item = item, count = Num(a[2]) or 1, qid = Num(a[3]), text = text }
	local objFlags, flags = Num(a[4]) or 0, Num(a[5]) or 0
	if flags < 0 then flags = 3 end
	e.textOnly = HasBit(flags, 1) or nil
	e.ignoreTurnIn = HasBit(flags, 16) or nil
	if e.qid and HasBit(flags, 4) and objFlags > 0 then
		e.objs = {}
		for n = 1, 12 do
			if HasBit(objFlags, 2 ^ (n - 1)) then e.objs[#e.objs + 1] = n end
		end
		e.obj = e.objs[1]   -- live text of the first tracked objective
	end
	return e
end

-- ".xp 5" reach level 5; ".xp 5,1" skip this step from level 5;
-- ".xp <5,1" skip this step below level 5; "5+1200" / "5.5" partial levels.
H.xp = function(a, text)
	local op, level, extra = tostring(a[1] or ""):gsub(" ", ""):match("(<?)(%d+)([%+%.%-]?%d*)")
	level = Num(level)
	if not level then return nil end
	local e = { kind = "xp", level = level, xp = tonumber(extra) or 0, reverse = (op == "<") }
	local skipstep = Num(a[2])
	if skipstep then
		e.cond, e.textOnly, e.hidden, e.text = "xp", true, not text, text
		if skipstep < 0 then e.reverse = true end
	else
		e.text = text or string.format(FR.L["Grind to level %d"], level)
	end
	return e
end

H.maxlevel = function(a)
	local level = Num(tostring(a[1] or ""):match("%d+"))
	if not level then return nil end
	return { cond = "maxlevel", level = level, textOnly = true, hidden = true }
end

H.train = function(a, text)
	local spells = Ids(a)
	if #spells == 0 then return text and { text = text, textOnly = true } or nil end
	return { kind = "train", spells = spells, text = text or FR.L["Train new spells"] }
end
H.istrained = function(a)
	return { cond = "istrained", spells = Ids(a), textOnly = true, hidden = true }
end

local function Simple(kind, default)
	return function(a, text)
		return { kind = kind, text = text or FR.L[default], npc = Num(a[1]) }
	end
end
H.fp = function(a, text) return { kind = "fp", text = text or (FR.L["Get the flight path"] .. (a[1] and (": " .. a[1]) or "")) } end
-- "dest" = the place as the guide writes it (".fly Tanaris"), matched against the flight masters' names
-- when the flight map opens (Events.lua, auto fly).
H.fly = function(a, text)
	local dest = a[1] and Trim(a[1]) or nil
	if dest == "" then dest = nil end
	return { kind = "fly", dest = dest, text = text or string.format(FR.L["Fly to %s"], a[1] or "") }
end
H.hs = Simple("hs", "Use your Hearthstone")
H.home = Simple("home", "Set your Hearthstone")
H.vendor = Simple("vendor", "Visit the vendor")
H.trainer = Simple("trainer", "Visit the trainer")
H.stable = Simple("stable", "Visit the stable master")
-- ".bankdeposit 5996,1468 >> text" / ".bankwithdraw ...": the item ids the step moves. Bank.lua moves them
-- when the bank window opens; the line is done when none of them is left in the bags (deposit) or in
-- the bank (withdraw), see FR.BankLineDone.
local function Bank(mode, default)
	return function(a, text)
		return { kind = "bank", mode = mode, items = Ids(a), text = text or FR.L[default] }
	end
end
H.bankdeposit = Bank("deposit", "Deposit items in the bank")
H.bankwithdraw = Bank("withdraw", "Withdraw items from the bank")
H.deathskip = Simple("deathskip", "Die and respawn at the Spirit Healer")

H.cast = function(a, text) return { kind = "cast", spells = Ids(a), text = text } end
H.usespell = H.cast

H.use = function(a, text)
	return { kind = "use", items = Ids(a), text = text, textOnly = true, hidden = not text }
end
H.addquestitem = function(a)
	return { kind = "use", items = { Num(a[1]) }, textOnly = true, hidden = true }
end

H.equip = function(a, text)
	local item = Num(a[2]) or Num(a[1])
	return item and { kind = "equip", item = item, text = text } or nil
end
H.destroy = function(a, text)
	local item = Num(a[1])
	return item and { kind = "destroy", item = item, text = text } or nil
end
H.abandon = function(a, text)
	local qid = Num(a[1])
	return qid and { kind = "abandon", qid = qid, text = text or string.format(FR.L["Abandon quest %d"], qid) } or nil
end

H.zone = function(a, text)
	local mapID = Num(a[1]) or FR:GetZoneID(a[1] or "")
	-- Entering the zone completes the whole step (RestedXP behaviour).
	return mapID and { kind = "zone", mapID = mapID, text = text, completesStep = true } or nil
end
H.subzone = function(a, text)
	local area = Num(a[1])
	return area and { kind = "subzone", area = area, text = text } or nil
end

H.skill = function(a, text)
	local op, level = tostring(a[2] or ""):gsub(" ", ""):match("(<?)(%d+)")
	level = Num(level)
	if not (a[1] and level) then return nil end
	local e = { kind = "skill", skill = a[1], level = level, reverse = (op == "<"), text = text }
	if Num(a[3]) then e.cond, e.textOnly, e.hidden = "skill", true, not text end
	return e
end

H.money = function(a, text)
	local s = tostring(a[1] or "")
	local amount = Num(s:match("(%d+%.?%d*)"))
	if not amount then return nil end
	-- ".money >0.1": the step counts as done once you have more than 10 silver
	-- (RestedXP uses it to skip vendor / training steps).
	return { cond = "money", above = s:sub(1, 1) == ">", copper = amount * 10000, text = text,
		textOnly = true, hidden = not text }
end

H.itemcount = function(a)
	local op, eq, total = tostring(a[2] or ""):gsub(" ", ""):match("([<>]?)(=?)(%d+)")
	return { cond = "itemcount", items = Ids({ a[1] }), op = op, eq = eq == "=", total = Num(total) or 1,
		textOnly = true, hidden = true }
end

local function QuestCond(name, reverse)
	return function(a)
		return { cond = name, qids = Ids(a), reverse = reverse, textOnly = true, hidden = true }
	end
end
H.isOnQuest = QuestCond("onquest", false)
H.isNotOnQuest = QuestCond("onquest", true)
H.isQuestTurnedIn = QuestCond("turnedin", false)
H.isQuestAvailable = QuestCond("turnedin", true)
H.isQuestComplete = QuestCond("ready", false)
H.isQuestNotComplete = QuestCond("ready", true)

local function ZoneCond(name)
	return function(a)
		local ids = {}
		for z in tostring(a[1] or ""):gmatch("[^%+/]+") do
			ids[#ids + 1] = Num(z) or FR:GetZoneID(Trim(z))
		end
		local flags = Num(a[2]) or 0
		return { cond = name, ids = ids, reverse = (flags % 2) == 1, textOnly = true, hidden = true }
	end
end
H.zoneskip = ZoneCond("zoneskip")
H.subzoneskip = ZoneCond("subzoneskip")

local function Targets(kind)
	return function(a, text)
		local names, ids = Names(a)
		return { kind = kind, targets = names, npcIds = ids, text = text, textOnly = true, hidden = not text }
	end
end
H.target = Targets("target")
H.targetnpc = Targets("target")
H.mob = Targets("mob")
H.unitscan = Targets("unitscan")

H.link = function(a, text) return text and { kind = "link", text = text, textOnly = true } or nil end

-- ".dungeon WC": the step is for players who run Wailing Caverns (setting or
-- ".enabledungeon" of the guide group). ".dungeon !WC": the step is the way
-- without that dungeon and goes away when it is on (RestedXP DungeonCheck).
H.dungeon = function(a, text, _, step)
	local tag = Trim(tostring(a[1] or ""))
	local skip = tag:sub(1, 1) == "!"
	if skip then tag = tag:sub(2) end
	tag = FR.DungeonTag(tag)
	if tag then
		if skip then step.dungeonskip = tag else step.dungeon = tag end
	end
	return text and { text = text, textOnly = true } or nil
end
H.disablecheckbox = function(_, _, _, step)
	step.nocheck = true
	-- The line before it loses its checkbox and no longer holds the step back.
	local prev = step.elements[#step.elements]
	if prev and prev.kind ~= "goto" then prev.textOnly = true end
end

-- .itemStat slot,stat,<value (RestedXP): the step only stays while the item
-- in that equipment slot meets the condition, e.g. "<4.9" damage per second
-- keeps "equip the Wooden Mallet" until a better weapon is worn.
H.itemStat = function(a)
	local slot, stat = Num(a[1]), a[2]
	local op, total = tostring(a[3] or ""):gsub(" ", ""):match("^([<>]?)(.+)$")
	if not (slot and stat and total) then return nil end
	return { cond = "itemstat", slot = slot, stat = stat, op = op, total = Num(total) or total,
		textOnly = true, hidden = true }
end

-- Remaining RestedXP commands -----------------------------------------------------------

-- .solo / .enabledungeon: only a line of text (the rest is guide bookkeeping).
H.solo = function(_, text) return text and { text = text, textOnly = true } or nil end
H.enabledungeon = H.solo

-- .showwhiledead: the step is only for dead players (skipped while alive).
H.showwhiledead = function() return { cond = "showwhiledead", textOnly = true, hidden = true } end

-- .bronzetube [rev]: skipped once you carry the Bronze Tube(s) the step needs.
H.bronzetube = function(a)
	return { cond = "bronzetube", rev = a[1] ~= nil and a[1] ~= "", textOnly = true, hidden = true }
end

-- .blastedLands: the five Blasted Lands collection quests as one line.
H.blastedLands = function() return { kind = "blasted", text = "" } end

-- .gossipoption id: picks that option of the NPC's talk window and is done then.
H.gossipoption = function(a, text)
	local id = Num(a[1])
	if not id then return nil end
	return { kind = "gossipoption", gossipId = id, text = text, textOnly = not text, hidden = not text }
end

-- .clicknext text,guide: a line that takes you to the next guide.
H.clicknext = function(a, text)
	text = text or a[1]
	local ref = a[2] or a[1]
	if not (text and ref) then return nil end
	return { kind = "manual", text = text, nextGuide = ref }
end

-- .timer seconds[,text]: starts a countdown bar when the line before it is
-- done (a flight, a boat, a talk option). Shown text is optional.
H.timer = function(a, text, _, step)
	local seconds = Num(a[1])
	local prev = step.elements[#step.elements]
	if seconds and prev and not a[3] then
		prev.timer, prev.timerText = seconds, a[2] or text
	end
	return (text and not prev) and { text = text, textOnly = true } or nil
end

-- .macro name,icon >> body: a macro button in the Active Items box.
H.macro = function(a, text)
	local name, icon = a[1], Num(a[2]) or 134400
	if not (name and text) then return nil end
	return { macro = { name = name, icon = icon, body = (text:gsub("\\n", "\n")) }, textOnly = true, hidden = true }
end

-- .reputation faction,standing[,value]: "grind to Honored with ..." line, or a
-- condition ("<" reverses it, a fifth argument skips the step instead).
local STANDINGS = { hated = 1, hostile = 2, unfriendly = 3, neutral = 4, friendly = 5, honored = 6, revered = 7, exalted = 8 }
H.reputation = function(a, text)
	local faction = Num(a[1])
	local str = tostring(a[2] or ""):gsub(" ", "")
	local op, standing, rep = str:match("(<?)([%d%w]+)([%+%.%-]?%d*)")
	standing = STANDINGS[(standing or ""):lower()] or Num(standing)
	if a[3] then op, rep = tostring(a[3]):match("(<?)%s*(%-?%d+%.?%d*)") end
	if not (faction and standing) then return nil end
	local e = { kind = "reputation", faction = faction, standing = standing, value = Num(rep) or 0,
		reverse = (op == "<"), text = text }
	if a[4] then e.kind, e.cond, e.textOnly, e.hidden = nil, "reputation", true, true end
	return e
end

-- .pin zone,x,y[,tooltip]: a map pin without arrow or checkbox.
H.pin = function(a, text, ctx)
	local tip = a[4]
	local args = { a[1], a[2], a[3] }
	local e = H["goto"](args, text, ctx)
	if not e or e.kind ~= "goto" then return e end
	e.kind, e.arrive, e.textOnly, e.hidden, e.mapTooltip = "pin", false, true, true, tip
	e.hidePin = nil
	return e
end

-- .line zone,x1,y1,x2,y2,...: a line on the world map (map percent, or world
-- coordinates with "zone/instance"). Drawn by MapPins.lua.
H.line = function(a, text, ctx)
	local zone = tostring(a[1] or ""):gsub("^%+", "")
	local mapID, instance = zone:match("^(%d+)/(%d+)$")
	local points = {}
	for i = 2, #a, 2 do
		local x, y = Num(a[i]), Num(a[i + 1])
		if not (x and y) then return nil end
		points[#points + 1] = { x, y }
	end
	if #points < 2 then return nil end
	local last = tostring(ctx.lastZone or "")
	local map = Num(mapID or zone) or FR:GetZoneID(zone) or Num(last:match("^(%d+)")) or FR:GetZoneID(last)
	if not map then return nil end
	return { line = { map = map, world = instance ~= nil, points = points }, textOnly = true, hidden = true }
end

-- .group [number]: a warning line for steps meant for a group (RestedXP).
H.group = function(a, text)
	local n = Num(a[1])
	if not text and n and n > 0 then
		text = string.format(FR.L["Do NOT attempt this quest unless you are in a group of at least %d"], n)
	elseif not text then
		text = FR.L["This step is meant to be completed as a group, be careful"]
	end
	return { text = text, textOnly = true, warn = true }
end

-- Gossip automation (RestedXP): ".skipgossip [npcID,options...]" picks options of
-- an NPC's talk window, ".skipgossipid id,..." picks the option with that
-- gossip id. Handled in QuestAuto.lua while the step is on screen.
H.skipgossip = function(a, text)
	local args = {}
	for _, v in ipairs(a) do args[#args + 1] = Num(v) end
	return { gossip = { args = args }, textOnly = true, hidden = not text, text = text }
end
H.skipgossipid = function(a, text)
	local ids = {}
	for _, v in ipairs(a) do
		local id = Num((tostring(v):gsub("^%+", "")))
		if id then ids[#ids + 1] = id end
	end
	if #ids == 0 then return nil end
	return { gossipIds = ids, textOnly = true, hidden = not text, text = text }
end

-- .cooldown item|spell,id,>N|<N: the step ends while the cooldown has more
-- (">") or less ("<") than N seconds left. The guides use it for the
-- Hearthstone: no "hearth to ..." step while it is on cooldown.
H.cooldown = function(a)
	local ctype, id = a[1], Num(a[2])
	local op, n, unit = tostring(a[3] or ""):gsub(" ", ""):match("([<>]?)(%d+%.?%d*)([ms]?)")
	if not (ctype and id and n) then return nil end
	local seconds = tonumber(n) * (unit == "m" and 60 or 1)
	return { cond = "cooldown", ctype = ctype, id = id, less = (op == "<"), seconds = math.max(2, seconds),
		textOnly = true, hidden = true }
end

-- .bindlocation areaID[,flags]: done once the hearthstone is set to that inn.
H.bindlocation = function(a)
	local area = Num(a[1])
	if not area then return nil end
	return { cond = "bindlocation", area = area, reverse = (Num(a[2]) or 0) % 2 == 1,
		textOnly = true, hidden = true }
end

-- .aura spellID[,duration][,unit]: with text a checkbox line, without text a
-- condition that ends the step while the aura is there ("-" or a negative id
-- = while it is missing).
H.aura = function(a, text)
	local id = Num(a[1])
	if not id then return nil end
	local reverse = id < 0
	if tostring(a[2] or ""):find("<") or tostring(a[2] or ""):find("%-$") then reverse = not reverse end
	local e = { aura = math.abs(id), reverse = reverse, unit = a[3] or "player", text = text }
	if text then e.kind = "aura" else e.cond, e.textOnly, e.hidden = "aura", true, true end
	return e
end

-- Line parsing ------------------------------------------------------------------------------

-- Step signature (see StepKey): lines that hold translated names or text do not
-- go into it, so a guide has the same signatures in every language.
local SIG_MASKED = { target = true, targetnpc = true, mob = true, unitscan = true, link = true, macro = true, timer = true }

local function ParseLine(line, step, ctx)
	local tag
	line = line:gsub("%s*<<%s*(.+)$", function(t) tag = t return "" end)
	if tag and not FR.Applies(tag) then return end
	local sig = step.sigParts

	local key, value = line:match("^#(%S+)%s*(.*)$")
	if key then
		-- "#label End --hidden step for #include": the comment is not part of the value.
		value = Trim((value:gsub("%s+%-%-.*$", "")))
		if step[key] == nil then step[key] = (value ~= "" and value) or true end
		if sig then sig[#sig + 1] = "#" .. key .. " " .. value end
		return
	end

	local text
	line = line:gsub("%s*>>%s*(.*)$", function(t)
		if t ~= "" then text = t end
		return ""
	end)

	local e
	local cmd, args = line:match("^%.(%S+)%s*(.*)$")
	if cmd then
		local comment
		args = args:gsub("%s*%-%-%s*(.*)$", function(c) comment = c return "" end)
		args = args:gsub("%s*,%s*", ",")
		if sig and not SIG_MASKED[cmd] then sig[#sig + 1] = "." .. cmd .. " " .. args end
		local list = {}
		for v in args:gmatch("[^,]+") do list[#list + 1] = v end
		local handler = H[cmd]
		if handler then
			e = handler(list, text, ctx, step)
		elseif text then
			e = { text = text, textOnly = true }
		end
		if e then
			e.cmd = cmd
			e.comment = comment
			-- ".complete 370,1 --Captain Perrine (1)": the name finds the objective
			-- even if the game lists the objectives in a different order.
			if comment and (e.kind == "complete" or (e.kind == "collect" and e.obj)) then
				local name = comment:match("^(.-)%s*%(%d+%)%s*$")
				if name and name ~= "" then e.hint = name end
			end
		end
	elseif text then
		e = { text = text, textOnly = true }
	elseif line:sub(1, 1) == "+" then
		e = { kind = "manual", text = line:sub(2) }
		-- "#hidewindow" steps only steer the arrow along a loop; RestedXP never shows
		-- their lines, and the bare "+1" they end with is a placeholder, not an
		-- instruction. Hidden, it gets no checkbox and never blocks the step.
		if step.hidewindow then e.hidden, e.textOnly = true, true end
		if sig then sig[#sig + 1] = "+" end
	elseif line:sub(1, 1) == "*" then
		e = { text = line:sub(2), textOnly = true }
		if sig then sig[#sig + 1] = "*" end
	end

	if e then
		e.text = FR.FormatText(e.text)
		e.comment = e.comment and FR.FormatText(e.comment)
		table.insert(step.elements, e)
		e.idx = #step.elements
		-- RestedXP ties a plain ".goto" (a pin without radius) to the last objective line before it
		-- in the same step (a line with a checkbox). The arrow and the map pin stay on the pin until
		-- that objective is done, so a step that lists several NPCs walks from one to the next.
		-- `parent` is the index of that element; a pin before any objective has none.
		if ctx.objStep ~= step then ctx.objStep, ctx.lastObjective = step, nil end
		if e.kind == "goto" and not e.arrive then
			e.parent = ctx.lastObjective
		elseif e.kind and e.kind ~= "goto" and e.kind ~= "pin" and not e.textOnly and not e.cond then
			ctx.lastObjective = e.idx
		elseif e.kind == "goto" and e.arrive and e.text then
			ctx.lastObjective = e.idx   -- an arrival point with its own text is a line to tick
		end
	end
end

-- Step filters ---------------------------------------------------------------------------
-- Which steps belong in a guide is decided per guide, not per step text: a
-- dungeon guide #includes the steps of a zone guide, and the dungeon, phase
-- and server tags have to be judged for the guide that is being built.

-- Forever runs on the pre-Naxxramas patch (RestedXP forces phase 5 there too).
FR.PHASE = 5

-- "#phase 4-6", "#phase 3" (from phase 3 on).
local function PhaseMatches(phase)
	if type(phase) ~= "string" then return true end
	local lo, hi = phase:match("(%d+)%-(%d+)")
	if lo then
		lo, hi = tonumber(lo), tonumber(hi)
	else
		lo, hi = tonumber(phase:match("%d+")), 0xffff
	end
	if not lo then return true end
	return FR.PHASE >= lo and FR.PHASE <= hi
end

-- Does `step` show in guide `g`? Pure: no state is changed.
local function StepShown(step, g)
	local server = FR.IsHardcore()
	local hc = FR.HardcoreMode() or g.header.hardcore ~= nil   -- a "#hardcore" guide counts too
	if step.hardcore and not hc then return false end
	if step.softcore and hc then return false end
	if step.hardcoreserver and not server then return false end
	if step.softcoreserver and server then return false end
	if type(step.season) == "string" and not step.season:find("[01]") then return false end
	if step.som or step.ssf then return false end
	if not PhaseMatches(step.phase) then return false end

	-- RestedXP DungeonCheck: ".dungeon X" needs X on, ".dungeon !X" needs it off.
	local dungeon, skip = step.dungeon, step.dungeonskip
	if skip and FR.DungeonEnabled(skip, g) then return false end
	if dungeon then
		if dungeon == skip or not FR.DungeonEnabled(dungeon, g) then return false end
	end

	if type(step.xprate) == "string" then
		-- Forever uses normal experience rates.
		local op, v = step.xprate:match("^([<>]?)%s*([%d%.]+)")
		v = tonumber(v)
		if v and op == "<" and not (1 < v) then return false end
		if v and op == ">" and not (1 > v) then return false end
	end
	return true
end

-- A step none of whose lines can be ticked (e.g. just "Talk to the innkeeper"
-- when the lines for the player's class were filtered out) gets a checkbox on
-- every visible line, so it can always be skipped by hand.
local function MarkManual(step)
	if step.empty then return end
	local visible, located = false, false
	for _, e in ipairs(step.elements) do
		if FR.IsCompletableElement(e) then return end
		if not e.hidden and not e.cond and (e.text or e.comment) then visible = true end
		if e.kind == "goto" then located = true end
	end
	-- Nothing to read, nothing to tick and no place to go to (only conditions
	-- such as ".maxlevel"): there is nothing to show, so the step is skipped.
	if not visible and not located then step.blank = true end
	for _, e in ipairs(step.elements) do
		if not e.cond and not e.hidden and e.textOnly and (e.text or e.comment) and e.kind ~= "manual" then
			e.manualCheck = true
		end
	end
end

local function CopyStep(s)
	local c = {}
	for k, v in pairs(s) do c[k] = v end
	return c
end

-- Reading ----------------------------------------------------------------------------------

-- German merge -----------------------------------------------------------------------------
-- The German files are translated copies of the English guides and come later:
-- after a guide update they still hold the old steps. The signature of a step
-- (Parser step signature, see ParseLine) is the same in both languages, so the
-- two lists can be lined up step by step:
--   * the English list gives the steps and their order (it is the current one),
--   * where the German guide has the step (same signature, same time it comes
--     up) the German step is used, with its German text,
--   * otherwise the English step is used (not translated yet),
--   * German steps the English guide no longer has are dropped.
-- Raw steps are never changed (guides get copies), so sharing them is safe.
local function MergeWithEnglish(g, own, english)
	local mine, seen = {}, {}
	for _, s in ipairs(own) do
		local sig = s.sig or ""
		local n = (seen[sig] or 0) + 1
		seen[sig] = n
		mine[sig .. "#" .. n] = s
	end
	local out, count = {}, {}
	local fallback = 0
	for _, s in ipairs(english) do
		local sig = s.sig or ""
		local n = (count[sig] or 0) + 1
		count[sig] = n
		local own = mine[sig .. "#" .. n]
		if own then
			out[#out + 1] = own
		else
			out[#out + 1] = s
			if not s.include then fallback = fallback + 1 end
		end
	end
	g.englishSteps, g.mergedSteps = fallback, #out
	return out
end

-- Reads the guide text once into raw steps. Raw steps keep every tag (phase,
-- dungeon, server ...) and are never handed out: guides get copies, because
-- the same steps are used by the guide itself and by dungeon guides that
-- #include it. An "#include" line becomes a { include = {...} } entry.
--   #include Group\Guide               every step of that guide
--   #include Group\Guide@a-b           the steps from "#label a" to "#label b"
local function ReadSteps(g)
	if g.rawSteps then return g.rawSteps end
	local steps, step, skip = {}, nil, false
	local ctx = {}

	for raw in g.raw:gmatch("[^\r\n]+") do
		local line = Trim(raw)
		if line:match("^step$") or line:match("^step[%s<]") then
			local tag = line:match("<<%s*(.+)$")
			if tag and not FR.Applies(tag) then
				skip, step = true, nil
			else
				skip = false
				step = { elements = {}, sigParts = { tag and ("step<<" .. tag) or "step" } }
				table.insert(steps, step)
			end
		elseif line:match("^#include%s") then
			local ref = Trim(line:match("^#include%s+(.-)%s*$"))
			local tag
			ref = ref:gsub("%s*<<%s*(.+)$", function(t) tag = t return "" end)
			if not skip and (not tag or FR.Applies(tag)) then
				local name, from, to = ref:match("^(.-)@([^@%-]+)%-?([^@%-]*)$")
				if not name then name, from, to = ref, nil, nil end
				if from == "" then from = nil end
				if to == "" then to = nil end
				-- A step that only held the #include (and ".enabledungeon" lines) is
				-- not a step of its own (RestedXP leaves it out as well).
				if step and #step.elements == 0 and not step.label and not step.requires then
					table.remove(steps)
				end
				-- Group and guide names are translated, the level range and the labels are not.
				local range = name:match("(%d+%-%d+)") or name
				table.insert(steps, {
					include = { ref = name, from = from, to = to },
					sig = "include:" .. range .. "@" .. (from or "") .. "-" .. (to or ""),
				})
				step = nil
			end
		elseif step and not skip and line ~= "" and line:sub(1, 2) ~= "--" then
			ParseLine(line, step, ctx)
		end
	end
	for _, s in ipairs(steps) do
		if s.sigParts then
			s.sig = table.concat(s.sigParts, "|")
			s.sigParts = nil
		end
	end
	-- A German guide whose translation is behind: the English guide decides which
	-- steps there are, the German text is used where the step is translated.
	if g.pair and g.pair ~= g then steps = MergeWithEnglish(g, steps, ReadSteps(g.pair)) end
	g.rawSteps = steps
	return steps
end

-- Key of a step in the saved progress: the signature of its lines (the same in
-- every language and when other steps appear or go away) and which time that
-- signature has come up in the guide (many steps repeat, e.g. "use the
-- Hearthstone"). Computed on first use.
-- Two 24-bit hashes side by side (48 bits): every product stays below 2^31, so
-- the result is the same on any Lua number type.
local function Hash(s)
	local a, b = 5381, 52711
	for i = 1, #s do
		local c = s:byte(i)
		a = (a * 33 + c) % 16777216
		b = (b * 31 + c) % 16777216
	end
	return string.format("%06x%06x", a, b)
end

function FR.StepKey(step)
	local key = step.key
	if not key then
		key = Hash(step.sig or "") .. "#" .. (step.occ or 1)
		step.key = key
	end
	return key
end

-- Appends the steps of `src` that show in the guide being built to `out`,
-- #include lines expanded in place. `from` / `to` are the labels of an
-- "#include Guide@from-to" range (inclusive, as in RestedXP). `ctx.n` counts
-- every step met, shown or not, so a step keeps its place (`order`) when a
-- setting such as a dungeon changes which steps show.
local function Expand(self, src, out, shown, ctx, depth, from, to, seen)
	local started = from == nil
	for _, s in ipairs(ReadSteps(src)) do
		if s.include then
			if started and depth < 4 then
				local inc = self:FindGuide(s.include.ref, src.group, src.lang)
				if inc and not seen[inc] then
					seen[inc] = true
					Expand(self, inc, out, shown, ctx, depth + 1, s.include.from, s.include.to, seen)
					seen[inc] = nil
				end
			end
		else
			local visible = shown(s)
			if not started and visible and s.label == from then started = true end
			if started then
				ctx.n = ctx.n + 1
				-- Which time this signature comes up, counted over the steps that are
				-- hidden too, so a setting that hides a repeated step moves no key.
				local occ = (ctx.seen[s.sig or ""] or 0) + 1
				ctx.seen[s.sig or ""] = occ
				if visible then
					local c = CopyStep(s)
					c.order = ctx.n
					c.occ = occ
					table.insert(out, c)
					if to and s.label == to then return end
				end
			end
		end
	end
end

function FR:ParseGuide(g)
	if g.steps then return g.steps end
	local flat = {}
	Expand(self, g, flat, function(s) return StepShown(s, g) end, { n = 0, seen = {} }, 0, nil, nil, { [g] = true })

	local out, labels, tips = {}, {}, {}
	for _, s in ipairs(flat) do
		if s.tip then
			-- A tip ("#tip") is advice, not a step of the route: it goes to the tip
			-- window and is not counted, ticked or listed. tipAfter = how many route
			-- steps come before it.
			s.tipAfter = #out
			table.insert(tips, s)
		else
			-- Steps whose lines were all filtered out still count, so step numbers
			-- match RestedXP; they are skipped automatically.
			s.empty = (#s.elements == 0) or nil
			table.insert(out, s)
			s.idx = #out
			if type(s.label) == "string" then labels[s.label] = s.idx end
			if s.nocheck then
				for _, e in ipairs(s.elements) do
					if e.kind == "manual" then e.textOnly = true end
				end
			end
			MarkManual(s)
		end
	end
	g.tips = tips
	-- A step that "#requires" a sticky step ends that sticky step once it is
	-- reached (RestedXP: the sticky step gets "completewith" this step).
	for _, s in ipairs(out) do
		if type(s.requires) == "string" and not s.sticky and not s.completewith then
			local ri = labels[s.requires]
			local req = ri and out[ri]
			if req and req.sticky and not req.completewith then
				if type(s.label) ~= "string" then
					s.label = "__req" .. s.idx
					labels[s.label] = s.idx
				end
				req.completewith = s.label
			end
		end
	end
	g.labels = labels
	g.steps = out
	return out
end

-- Forgets the parsed steps of every guide (after a setting such as a dungeon
-- changed which steps show). The text is read again from the raw steps only.
function FR:InvalidateParsed()
	for _, g in ipairs(self.guides) do g.steps, g.labels, g.tips = nil, nil, nil end
end
