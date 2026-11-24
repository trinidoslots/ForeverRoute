-- Active party steps: the steps your group members are on, in a window next to
-- the guide window (RestedXP: "Active Party Steps").
--
-- ForeverRoute players in a party tell each other what they are doing with
-- addon messages (prefix "FRRoute"; RestedXP's own protocol is a different
-- one, so the two addons do not see each other). Each player sends the text
-- of the lines of his current steps, not a step number: class and race steps are
-- filtered when a guide is read, so the other player's copy of the guide may
-- not even contain them.
--
--   "H<version>"                         hello: "I am here, who else?"
--   "S<id>.<part>.<parts>:<text>"        one piece of a snapshot (an addon message is at most 255 bytes)
--
-- A snapshot is "version~guide~step~steps~class~level" followed by one "^"-led
-- record per line: a state character (1 done, 0 to do, - nothing to tick) and
-- the text. "~" and "^" cannot occur in a text: they are replaced when sending.
--
-- Everything that arrives passes issecretvalue and pcall before it is used.
local _, ns = ...
local FR = ns.FR

local P = {}
FR.Party = P

local PREFIX = "FRRoute"
local VERSION = 1
local CHUNK = 200          -- text bytes per message
local MAX_LINES = 12
local MAX_TEXT = 120
local EXPIRE = 90          -- seconds after which a member's data is dropped
local SEND_EVERY = 1       -- seconds between two snapshots
local DEBOUNCE = 0.5

-- Encoding (pure) --------------------------------------------------------------------------------

local function Clean(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cRXP_%u+_", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
	text = text:gsub("[%^~\r\n]", " "):gsub("%s+", " ")
	text = text:match("^%s*(.-)%s*$")
	if #text > MAX_TEXT then
		text = text:sub(1, MAX_TEXT)
		-- Do not cut a UTF-8 character in half.
		while #text > 0 and text:byte(#text) >= 0x80 and text:byte(#text) < 0xC0 do text = text:sub(1, #text - 1) end
		if #text > 0 and text:byte(#text) >= 0xC0 then text = text:sub(1, #text - 1) end
	end
	return text
end
P.Clean = Clean

-- snapshot = { guide, step, steps, class, level, lines = { { state = "1"|"0"|"-", text } } }
function P.Encode(s)
	local parts = { table.concat({ VERSION, Clean(s.guide), tonumber(s.step) or 0, tonumber(s.steps) or 0,
		Clean(s.class), tonumber(s.level) or 0 }, "~") }
	for i, line in ipairs(s.lines or {}) do
		if i > MAX_LINES then break end
		local text = Clean(line.text)
		if text ~= "" then parts[#parts + 1] = (line.state or "-") .. text end
	end
	return table.concat(parts, "^")
end

-- nil for anything that is not a well-formed snapshot of a version we know.
function P.Decode(text)
	if type(text) ~= "string" then return nil end
	local records = {}
	for piece in (text .. "^"):gmatch("(.-)%^") do records[#records + 1] = piece end
	local head = records[1]
	if not head then return nil end
	local f = {}
	for field in (head .. "~"):gmatch("(.-)~") do f[#f + 1] = field end
	if tonumber(f[1]) ~= VERSION or #f < 6 then return nil end
	local s = { guide = f[2], step = tonumber(f[3]), steps = tonumber(f[4]), class = f[5], level = tonumber(f[6]), lines = {} }
	if not (s.step and s.steps and s.level) then return nil end
	for i = 2, math.min(#records, MAX_LINES + 1) do
		local state, line = records[i]:sub(1, 1), records[i]:sub(2)
		if (state == "1" or state == "0" or state == "-") and line ~= "" then
			s.lines[#s.lines + 1] = { state = state, text = line }
		end
	end
	return s
end

-- The text in messages of at most CHUNK bytes: { "S12.1.2:...", "S12.2.2:..." }.
function P.Chunks(text, id)
	local out, n = {}, math.max(1, math.ceil(#text / CHUNK))
	for part = 1, n do
		out[part] = string.format("S%d.%d.%d:%s", id, part, n, text:sub((part - 1) * CHUNK + 1, part * CHUNK))
	end
	return out
end

-- Reassembling (pure) ----------------------------------------------------------------------------------

local assembling = {}   -- [sender] = { id, parts, got = {}, count }
P.members = {}          -- [sender] = { snapshot fields..., time }

-- One message from `sender` at time `now`. Returns the finished snapshot text or nil.
function P.Receive(sender, message, now)
	if type(message) ~= "string" then return nil end
	local id, part, parts, chunk = message:match("^S(%d+)%.(%d+)%.(%d+):(.*)$")
	id, part, parts = tonumber(id), tonumber(part), tonumber(parts)
	if not (id and part and parts and parts >= 1 and parts <= 40 and part >= 1 and part <= parts) then return nil end
	local a = assembling[sender]
	-- A newer snapshot replaces one that never got finished.
	if not a or a.id ~= id or a.parts ~= parts then
		a = { id = id, parts = parts, got = {}, count = 0 }
		assembling[sender] = a
	end
	if not a.got[part] then
		a.got[part] = chunk
		a.count = a.count + 1
	end
	if a.count < a.parts then return nil end
	assembling[sender] = nil
	local pieces = {}
	for i = 1, a.parts do pieces[i] = a.got[i] end
	return table.concat(pieces)
end

-- Stores what a member sent. Returns true when the data is new or changed.
function P.Store(sender, snapshot, now)
	if not snapshot then return false end
	snapshot.time = now
	P.members[sender] = snapshot
	return true
end

-- Drops data older than EXPIRE seconds. Returns true when something went.
function P.Expire(now)
	local removed = false
	for name, s in pairs(P.members) do
		if now - (s.time or 0) > EXPIRE then
			P.members[name] = nil
			assembling[name] = nil
			removed = true
		end
	end
	return removed
end

function P.Clear()
	P.members = {}
	assembling = {}
end

-- The members, sorted by name.
function P.List()
	local list = {}
	for name in pairs(P.members) do list[#list + 1] = name end
	table.sort(list)
	return list
end

-- "Name-Realm" -> "Name"
function P.ShortName(sender)
	return (tostring(sender):gsub("%-.*$", ""))
end

-- Sending ------------------------------------------------------------------------------------------

-- Where a message goes: never to a raid (RestedXP does not either).
local function Channel()
	if IsInRaid and IsInRaid() then return nil end
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if instance and IsInGroup and IsInGroup(instance) then return "INSTANCE_CHAT" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end

local function SendMessage(text)
	local channel = Channel()
	if not channel then return end
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel)
	elseif SendAddonMessage then
		pcall(SendAddonMessage, PREFIX, text, channel)
	end
end

-- What this player is doing now, as lines of text.
function P.BuildSnapshot()
	local g = FR.current
	if not (g and g.steps) then return nil end
	local lines = {}
	for _, step in ipairs(FR:GetActiveSteps()) do
		for _, e in ipairs(step.elements) do
			if not e.hidden and #lines < MAX_LINES then
				local text = FR:ElementText(e)
				if text and Clean(text) ~= "" then
					local done, completable = FR:ElementState(step, e)
					lines[#lines + 1] = { state = completable and (done and "1" or "0") or "-", text = text }
				end
			end
		end
	end
	local _, class = UnitClass("player")
	return { guide = g.short or g.name, step = FR.stepIndex or 1, steps = #g.steps, class = class or "", level = UnitLevel("player") or 0, lines = lines }
end

local lastText, lastSent, sequence, timerPending = nil, 0, 0, false

local function Broadcast(force)
	timerPending = false
	if not FR:Get("partySteps") or not Channel() then return end
	local now = GetTime()
	local snapshot = P.BuildSnapshot()
	if not snapshot then return end
	local text = P.Encode(snapshot)
	if text == lastText and not force then return end
	if now - lastSent < SEND_EVERY and not force then
		-- Too soon: try again a little later.
		if C_Timer and C_Timer.After and not timerPending then
			timerPending = true
			C_Timer.After(SEND_EVERY, function() Broadcast(false) end)
		end
		return
	end
	lastText, lastSent = text, now
	sequence = (sequence % 99999) + 1
	for _, message in ipairs(P.Chunks(text, sequence)) do SendMessage(message) end
end
P.Broadcast = Broadcast

-- Called after every update of the guide window: send what changed, a moment later.
function P.Queue()
	if timerPending or not FR:Get("partySteps") or not Channel() then return end
	timerPending = true
	if C_Timer and C_Timer.After then C_Timer.After(DEBOUNCE, function() Broadcast(false) end) else Broadcast(false) end
end

-- Window -----------------------------------------------------------------------------------------------

local window
local selected

local function ClassColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.9, 0.9, 0.9
end

local function Hidden() return P.hidden end

local function ShouldShow()
	return FR:Get("partySteps") and not Hidden() and #P.List() > 0 and not (IsInRaid and IsInRaid())
		and FR.frame and FR.frame:IsShown() and not FR:Get("hidden")
end

local function Build()
	local f = CreateFrame("Frame", "ForeverRoutePartyWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(260, 120)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	FR.Skin(f, "bg")
	f.tabs = {}
	f.header = FR.MakeText(f, FR.fontUISmall)
	f.header:SetPoint("TOPLEFT", 10, -30)
	f.header:SetWidth(240)
	f.header:SetWordWrap(false)
	f.header:SetTextColor(FR.colors.dim[1], FR.colors.dim[2], FR.colors.dim[3])
	f.body = FR.MakeText(f, FR.fontUIBody)
	f.body:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -6)
	f.body:SetWidth(240)
	f.body:SetWordWrap(true)
	f.body:SetTextColor(FR.colors.text[1], FR.colors.text[2], FR.colors.text[3])
	f:SetScript("OnDragStart", function(self) if not FR:Get("locked") then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		if point and ForeverRouteDB then ForeverRouteDB.posParty = { point, rel, math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then P.OpenMenu(f) end
	end)
	f:Hide()
	return f
end

local function Place(f)
	f:ClearAllPoints()
	local pos = ForeverRouteDB and ForeverRouteDB.posParty
	if pos then
		f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	elseif FR.frame then
		f:SetPoint("TOPLEFT", FR.frame, "TOPRIGHT", 6, 0)
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
	end
end

local function Tab(f, i)
	local b = f.tabs[i]
	if not b then
		b = CreateFrame("Button", nil, f)
		b:SetHeight(18)
		b.text = FR.MakeText(b, FR.fontUISmall)
		b.text:SetPoint("CENTER")
		b:SetScript("OnClick", function(self)
			selected = self.member
			P.Refresh()
		end)
		f.tabs[i] = b
	end
	return b
end

-- Draws the window for the data we have, or hides it.
function P.Refresh()
	P.Expire(GetTime())
	if not ShouldShow() then
		if window then window:Hide() end
		return
	end
	window = window or Build()
	Place(window)
	window:SetScale(FR:Get("partyStepsScale") or 1)
	if FR:Get("partyStepsBackground") then FR.Skin(window, "bg") else window:SetBackdrop(nil) end

	local list = P.List()
	if not (selected and P.members[selected]) then selected = list[1] end
	local x = 8
	for i, name in ipairs(list) do
		local b = Tab(window, i)
		b.member = name
		local r, g, bl = ClassColor(P.members[name].class)
		local label = P.ShortName(name)
		b.text:SetText(label)
		b.text:SetTextColor(r, g, bl, name == selected and 1 or 0.55)
		b:SetWidth((b.text:GetStringWidth() or 40) + 14)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", window, "TOPLEFT", x, -8)
		b:Show()
		x = x + b:GetWidth() + 2
	end
	for i = #list + 1, #window.tabs do window.tabs[i]:Hide() end

	local s = P.members[selected]
	window.header:SetText(string.format("%s  -  %s %d/%d  (%s %d)", s.guide or "?", FR.L["Step"], s.step or 0, s.steps or 0, FR.L["Level"], s.level or 0))
	local lines = {}
	for _, line in ipairs(s.lines or {}) do
		local mark = line.state == "1" and "|TInterface\\Buttons\\UI-CheckBox-Check:12|t " or (line.state == "0" and "- " or "")
		lines[#lines + 1] = mark .. FR.FormatText(line.text)
	end
	window.body:SetText(#lines > 0 and table.concat(lines, "\n") or "-")
	window:SetHeight(math.max(70, (window.body:GetStringHeight() or 20) + 66))
	window:Show()
end

function P.OpenMenu(owner)
	if not ns.FlatMenu then return end
	ns.FlatMenu.OpenAtCursor(owner, function(_, root)
		root:CreateButton(FR:Get("partyStepsBackground") and FR.L["Hide Background"] or FR.L["Show Background"], function()
			FR:Set("partyStepsBackground", not FR:Get("partyStepsBackground"))
		end)
		root:CreateButton(FR.L["Disable Active Party Steps"], function() FR:Set("partySteps", false) end)
		root:CreateButton(FR.L["Hide"], function() P.hidden = true; P.Refresh() end)
		root:CreateButton(FR.L["Close"], function() end)
	end, { avoid = owner })   -- no room on the right: open at the left side of the window
end

-- For the menu: members are there but the window is not.
function P.CanShow()
	return #P.List() > 0 and not (IsInRaid and IsInRaid()) and (not FR:Get("partySteps") or Hidden())
end

function P.Show()
	P.hidden = false
	FR:Set("partySteps", true)
	P.Refresh()
	-- Ask the others for their steps again.
	SendMessage("H" .. VERSION)
end

-- Events ------------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end

local function Hello()
	if Channel() and FR:Get("partySteps") then SendMessage("H" .. VERSION) end
end

ev:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
		elseif RegisterAddonMessagePrefix then pcall(RegisterAddonMessagePrefix, PREFIX) end
		if C_Timer and C_Timer.After then C_Timer.After(8, Hello) end
	elseif event == "GROUP_ROSTER_UPDATE" then
		if not (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) then P.Clear() end
		P.Refresh()
		if C_Timer and C_Timer.After then C_Timer.After(2, Hello) end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, _, sender = ...
		if prefix ~= PREFIX then return end
		if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return end
		if type(message) ~= "string" or type(sender) ~= "string" then return end
		local me = UnitName and UnitName("player")
		if sender == me or P.ShortName(sender) == me then return end
		if not FR:Get("partySteps") then return end
		pcall(function()
			if message:sub(1, 1) == "H" then
				-- Someone is new in the group: tell him what we are doing (after a short, random wait).
				local delay = 0.5 + math.random() * 1.5
				if C_Timer and C_Timer.After then C_Timer.After(delay, function() Broadcast(true) end) else Broadcast(true) end
				return
			end
			local text = P.Receive(sender, message, GetTime())
			if text and P.Store(sender, P.Decode(text), GetTime()) then P.Refresh() end
		end)
	end
end)

-- The window follows the guide window; our own steps go out with every update.
local rawUpdateUI = FR.UpdateUI
function FR:UpdateUI(...)
	rawUpdateUI(self, ...)
	P.Queue()
	-- (it also hides with the guide window)
	if (window and window:IsShown() or false) ~= (ShouldShow() and true or false) then P.Refresh() end
end

-- Members that stop sending drop out of the window.
if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(5, function()
		if P.Expire(GetTime()) then P.Refresh() end
	end)
end

function FR:RefreshPartySteps() P.Refresh() end
