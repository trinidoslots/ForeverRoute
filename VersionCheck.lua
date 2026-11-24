-- Tells other ForeverRoute users which version this client runs, and tells this client when
-- somebody runs a newer one. An addon can not download its own code: the files have to be copied
-- outside the game (tools\Update.cmd), so all this does is notice and remind.
--
-- Messages (addon prefix FRVer): "V<version>", e.g. "V2.10.0".
--   * sent to the guild after login and to the group when it changes (party, instance, raid);
--   * somebody who runs an OLDER version than the one we get is answered once with a whisper,
--     so an outdated client learns about the new version even if it was not the one talking;
--   * a NEWER version is saved in ForeverRouteDB.newerVersion and shown again on every login
--     until this client has been updated.
local _, ns = ...
local FR = ns.FR

local V = {}
FR.Version = V

local PREFIX = "FRVer"
local GROUP_COOLDOWN = 60      -- seconds between two announcements to the group

-- Versions ---------------------------------------------------------------------------------------

-- "2.10.0" -> { 2, 10, 0 }; nil when the text has no number in it.
local function Parse(text)
	if type(text) ~= "string" then return nil end
	local parts = {}
	for n in text:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
	if #parts == 0 then return nil end
	return parts
end

-- -1 when a is older than b, 0 when equal, 1 when a is newer. Unknown versions count as equal.
function V.Compare(a, b)
	local pa, pb = Parse(a), Parse(b)
	if not (pa and pb) then return 0 end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x < y then return -1 end
		if x > y then return 1 end
	end
	return 0
end

-- Sending ----------------------------------------------------------------------------------------

local function Send(text, channel, target)
	if not channel then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel, target)
	elseif SendAddonMessage then
		pcall(SendAddonMessage, PREFIX, text, channel, target)
	end
end

local function GroupChannel()
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup and IsInGroup(instance) then return "INSTANCE_CHAT" end
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end

local function Mine() return "V" .. tostring(FR.version) end

local lastGroup = 0

local function AnnounceGuild()
	if FR.version == "?" then return end
	if IsInGuild and IsInGuild() then Send(Mine(), "GUILD") end
end

local function AnnounceGroup()
	if FR.version == "?" then return end
	local channel = GroupChannel()
	if not channel then return end
	local now = GetTime()
	if now - lastGroup < GROUP_COOLDOWN then return end
	lastGroup = now
	Send(Mine(), channel)
end

-- Telling the player --------------------------------------------------------------------------------

local notified = {}   -- version -> true: each version is announced once per session

local function Notify(version, from)
	if notified[version] then return end
	notified[version] = true
	local text = string.format(
		FR.L["ForeverRoute %s is available (you have %s%s). Close WoW and update it in the CurseForge app, or type %s."],
		version, tostring(FR.version),
		from and (", " .. string.format(FR.L["seen from %s"], from)) or "",
		"/fr update")
	FR:Print("|cffffd100" .. text .. "|r")
end

local function Remember(version, from)
	local db = ForeverRouteDB
	if not db then return end
	local old = db.newerVersion
	if old and V.Compare(old.v, version) >= 0 then return end   -- we already know a newer or equal one
	db.newerVersion = { v = version, from = from, at = time and time() or 0 }
end

-- The newest version seen so far that is newer than this one, or nil.
function V.Newer()
	local old = ForeverRouteDB and ForeverRouteDB.newerVersion
	if old and V.Compare(old.v, FR.version) > 0 then return old end
	return nil
end

local function ShortName(sender)
	return (tostring(sender):gsub("%-.*$", ""))
end

-- Commands -----------------------------------------------------------------------------------------

function V.Print()
	FR:Print(string.format(FR.L["Your version: %s."], tostring(FR.version)))
	local newer = V.Newer()
	if newer then
		FR:Print("|cffffd100" .. string.format(FR.L["A newer version exists: %s (seen from %s). Type %s."],
			newer.v, newer.from or "?", "/fr update") .. "|r")
	else
		FR:Print(FR.L["No newer version has been seen."])
	end
	lastGroup = 0
	AnnounceGuild()
	AnnounceGroup()
end

function V.ShowUpdate()
	local newer = V.Newer()
	local lines = {}
	if newer then
		lines[#lines + 1] = string.format(FR.L["A newer version exists: %s (you have %s)."], newer.v, tostring(FR.version))
	else
		lines[#lines + 1] = string.format(FR.L["You have version %s. No newer one has been seen yet."], tostring(FR.version))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = FR.L["An addon can not update itself, the files have to be copied while the game is closed:"]
	lines[#lines + 1] = ""
	lines[#lines + 1] = FR.L["1. Close World of Warcraft completely."]
	lines[#lines + 1] = FR.L["2. Open the CurseForge app and update ForeverRoute there."]
	lines[#lines + 1] = FR.L["3. Start the game again."]
	FR.TextWindow{
		name = "Update", title = FR.L["Update ForeverRoute"],
		hint = FR.L["Copy this text (Ctrl+C) if you need it later."],
		text = table.concat(lines, "\n"),
	}
end

-- Events ------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end

local replied = {}   -- sender -> true: answered once per session

ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
		elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
		if C_Timer and C_Timer.After then
			C_Timer.After(10, function()
				-- The database is set up by now. Remind the player of a version seen earlier.
				local newer = V.Newer()
				if newer then
					Notify(newer.v, newer.from)
				elseif ForeverRouteDB then
					ForeverRouteDB.newerVersion = nil   -- updated since: forget it
				end
				AnnounceGuild()
			end)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		if C_Timer and C_Timer.After then C_Timer.After(3, AnnounceGroup) end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, _, sender = ...
		if prefix ~= PREFIX then return end
		if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return end
		if type(message) ~= "string" or type(sender) ~= "string" then return end
		local me = UnitName and UnitName("player")
		if sender == me or ShortName(sender) == me then return end
		local version = message:match("^V(%d[%d%.]*)$")
		if not version or #version > 20 then return end
		local order = V.Compare(version, FR.version)
		if order > 0 then
			Remember(version, ShortName(sender))
			Notify(version, ShortName(sender))
		elseif order < 0 and not replied[sender] and FR.version ~= "?" then
			-- The other one is outdated: tell it which version we run.
			replied[sender] = true
			Send(Mine(), "WHISPER", sender)
		end
	end
end)
