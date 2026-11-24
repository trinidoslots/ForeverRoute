-- Tells other ForeverRoute users which version this client runs, and tells this client when
-- somebody runs a newer one. An addon can not download its own code: the files have to be copied
-- outside the game (tools\Update.cmd), so all this does is notice and remind.
--
-- Messages (addon prefix FRVer): "V<version>", e.g. "V2.10.0".
--   * sent to the guild after login and to the group when it changes (party, instance, raid);
--   * sent to a hidden shared channel (FRVersion, setting "versionChannel"), so players who share no
--     guild or group with anybody on a newer version still learn about it;
--   * somebody who runs an OLDER version than the one we get is answered once with a whisper,
--     so an outdated client learns about the new version even if it was not the one talking.
--     On the channel the answer waits a few random seconds and is dropped if somebody else
--     already told the sender a version that is not older than ours (no whisper storm);
--   * a NEWER version is saved in ForeverRouteDB.newerVersion and shown again on every login
--     until this client has been updated.
local _, ns = ...
local FR = ns.FR

local V = {}
FR.Version = V

local PREFIX = "FRVer"
local GROUP_COOLDOWN = 60      -- seconds between two announcements to the group
local CHANNEL = "FRVersion"    -- the hidden channel every client with the setting on joins
local JOIN_DELAY = 20          -- seconds after login: after General/Trade, so /1-/4 keep their numbers
local REPLY_MIN, REPLY_MAX = 1, 6   -- seconds an answer on the channel waits (random)

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

-- The hidden channel -------------------------------------------------------------------------------

local channelId = 0   -- > 0 once joined

-- The join / leave lines of our channel stay out of the chat. A chat filter gets (frame, event, text,
-- sender, language, channelString, target, flags, zoneChannelId, channelIndex, channelBaseName).
local function HideNotice(_, _, _, _, _, channelString, _, _, _, _, baseName)
	if (channelString and tostring(channelString):find(CHANNEL, 1, true))
		or (baseName and tostring(baseName):find(CHANNEL, 1, true)) then
		return true
	end
end
local filtered = false

local function HideChannel()
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, frame, CHANNEL) end
	end
end

local function AnnounceChannel()
	if FR.version == "?" or channelId <= 0 then return end
	Send(Mine(), "CHANNEL", channelId)
end

local function Enabled() return FR:Get("versionChannel") ~= false end

-- Joins the channel, hides it and announces our version. The server confirms the join a moment
-- later, so the channel number is asked for a few times (3 s apart) before giving up.
local function JoinChannel(tries)
	if not Enabled() or channelId > 0 then return end
	tries = type(tries) == "number" and tries or 0
	if tries == 0 then
		if not filtered and ChatFrame_AddMessageEventFilter then
			filtered = true
			pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_NOTICE", HideNotice)
			pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_NOTICE_USER", HideNotice)
		end
		local join = JoinTemporaryChannel or JoinChannelByName
		if join then pcall(join, CHANNEL) end
	end
	HideChannel()
	local id = GetChannelName and GetChannelName(CHANNEL) or 0
	if type(id) == "number" and id > 0 then
		channelId = id
		AnnounceChannel()
		if C_Timer and C_Timer.After then C_Timer.After(2, HideChannel) end   -- the chat adds new channels itself
	elseif tries < 4 and C_Timer and C_Timer.After then
		C_Timer.After(3, function() JoinChannel(tries + 1) end)
	end
end

-- Takes our channel back out when the setting is switched off.
function V.Apply()
	if Enabled() then
		if channelId <= 0 and C_Timer and C_Timer.After then C_Timer.After(1, JoinChannel) end
	elseif channelId > 0 then
		if LeaveChannelByName then pcall(LeaveChannelByName, CHANNEL) end
		channelId = 0
	end
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
	AnnounceChannel()
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
local pending = nil  -- an answer on the channel that waits for its random delay: { floor = version }

-- Somebody on the channel runs an older version: say ours on the channel after a short random wait,
-- unless somebody else says a newer version than theirs first (then they know already).
local function AnswerOutdated(floor)
	if pending or not (C_Timer and C_Timer.After) then return end
	local mine = { floor = floor }
	pending = mine
	C_Timer.After(REPLY_MIN + math.random() * (REPLY_MAX - REPLY_MIN), function()
		if pending == mine then
			pending = nil
			if not mine.cancel then AnnounceChannel() end
		end
	end)
end

ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
		elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
		if C_Timer and C_Timer.After then
			C_Timer.After(JOIN_DELAY, JoinChannel)
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
		local prefix, message, distribution, sender = ...
		if prefix ~= PREFIX then return end
		if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return end
		if type(message) ~= "string" or type(sender) ~= "string" then return end
		local me = UnitName and UnitName("player")
		if sender == me or ShortName(sender) == me then return end
		local version = message:match("^V(%d[%d%.]*)$")
		if not version or #version > 20 then return end
		local order = V.Compare(version, FR.version)
		local onChannel = distribution == "CHANNEL"
		-- Somebody else has already told the outdated one about a newer version: no need to answer.
		if onChannel and pending and V.Compare(version, pending.floor) > 0 then pending.cancel = true end
		if order > 0 then
			Remember(version, ShortName(sender))
			Notify(version, ShortName(sender))
		elseif order < 0 and FR.version ~= "?" then
			if onChannel then
				-- Everybody on the channel hears the answer, so one is enough: wait a moment.
				AnswerOutdated(version)
			elseif not replied[sender] then
				-- The other one is outdated: tell it which version we run.
				replied[sender] = true
				Send(Mine(), "WHISPER", sender)
			end
		end
	end
end)
