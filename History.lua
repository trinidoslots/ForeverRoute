-- Step history: which steps were finished, passed on their own or left open, and why, per character.
--
-- The guide passes steps that are already done in the game without showing them (Engine.lua,
-- SkipForward). Those used to vanish: nothing said that they had been passed or why. Now
--   * every step that is left is written down (ForeverRouteCharDB.history, newest last),
--   * steps passed without being on screen that you may have missed are announced in a notice
--     box above the current step, with a click to go back to the first of them,
--   * right-click menu > History and /fr history list them, a click opens that step,
--   * the step list colours the numbers of past steps by what happened (UI.lua, FR:StepStatus).
--
-- entry = { t = server time, guide = guide title, short = short name, key = FR.StepKey, idx = step number,
--           text = first line of the step, how = "done" | "auto" | "skipped" | "left" | "guide",
--           why = reason (English), minor = true for routine skips (travel, cooldown ...) }
local _, ns = ...
local FR = ns.FR

local MAX = 400          -- entries kept
local NOTICE_SECONDS = 45

FR.historyVersion = 0

local HOW_LABEL = { done = "done", auto = "passed", skipped = "skipped", left = "left open", guide = "guide" }
-- Colours of the step numbers in the list and of the menu entries.
FR.HISTORY_COLORS = {
	done = { 0.35, 0.85, 0.45 }, auto = { 0.45, 0.7, 1.0 }, skipped = { 0.95, 0.7, 0.25 }, left = { 0.9, 0.4, 0.4 },
}

local function Hex(c)
	return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function List()
	if not ForeverRouteCharDB then return nil end
	local list = ForeverRouteCharDB.history
	if type(list) ~= "table" then
		list = {}
		ForeverRouteCharDB.history = list
	end
	return list
end

-- A cut that does not leave half a multi-byte character at the end.
local function Cut(s, n)
	if #s <= n then return s end
	local cut = s:sub(1, n)
	local nextByte = s:byte(n + 1)
	if nextByte and nextByte >= 128 and nextByte < 192 then
		cut = cut:gsub("[\192-\255][\128-\191]*$", "")
	end
	return cut .. "..."
end

local function Clean(s)
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
	s = s:gsub("[\r\n]+", " "):gsub("%s+", " ")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- First readable line of a step, for the history and the notice.
function FR.StepSummary(step)
	for _, e in ipairs(step.elements or {}) do
		if not e.hidden then
			local ok, text = pcall(FR.ElementText, FR, e)
			if ok and text then
				text = Clean(text)
				if text ~= "" then return Cut(text, 80) end
			end
		end
	end
	return string.format(FR.L["Step %d"], step.idx or 0)
end

-- Recording --------------------------------------------------------------------------------------

-- Writes one step down. Side steps (#completewith / #sticky) and steps with nothing to show are not
-- steps you are told about. `why` defaults to FR:FinishReason(step).
function FR:RecordStep(step, how, why, minor)
	local g = self.current
	local list = List()
	if not (g and list and step) or step.empty or step.blank or FR.IsSideStep(step) then return end
	if g.detour then return end   -- a detour (MissingQuest.lua) is not part of the history
	local key = FR.StepKey(step)
	-- The same event reported again (Refresh runs often): refresh the last entries instead of adding.
	for i = #list, math.max(1, #list - 4), -1 do
		local e = list[i]
		if e.guide == g.title and e.key == key and e.how == how then
			e.t = time()
			return
		end
	end
	list[#list + 1] = {
		t = time(), guide = g.title, short = g.short, key = key, idx = step.idx,
		text = FR.StepSummary(step), how = how, why = why or self:FinishReason(step), minor = minor or nil,
	}
	while #list > MAX do table.remove(list, 1) end
	FR.historyVersion = FR.historyVersion + 1
end

-- The guide ended and the next one is loaded.
function FR:RecordGuideChange(from, to)
	local list = List()
	if not list then return end
	list[#list + 1] = {
		t = time(), guide = from.title, short = from.short, key = "", idx = 0,
		text = string.format(FR.L["Guide finished. Loading: %s"], to.short), how = "guide",
	}
	while #list > MAX do table.remove(list, 1) end
	FR.historyVersion = FR.historyVersion + 1
end

-- What happened to a step of the open guide (the newest entry), or nil. Cached until the history changes.
local cacheGuide, cacheVersion, cacheMap = nil, -1, {}

function FR:StepStatus(step)
	local g = self.current
	local list = List()
	if not (g and list and step) then return nil end
	if cacheGuide ~= g.title or cacheVersion ~= FR.historyVersion then
		cacheGuide, cacheVersion, cacheMap = g.title, FR.historyVersion, {}
		for _, e in ipairs(list) do
			if e.guide == g.title and e.key and e.key ~= "" then cacheMap[e.key] = e end
		end
	end
	return cacheMap[FR.StepKey(step)]
end

-- The "N steps were passed" notice -------------------------------------------------------------

function FR:AddPassNotice(g, steps)
	if #steps == 0 or not self:Get("autoPassNotice") then return end
	local n = self.passNotice
	if not (n and n.guide == g.title and GetTime() < n.untilT) then
		n = { guide = g.title, short = g.short, steps = {} }
		self.passNotice = n
	end
	for _, s in ipairs(steps) do
		n.steps[#n.steps + 1] = { idx = s.idx, key = FR.StepKey(s), text = FR.StepSummary(s), why = self:FinishReason(s) }
	end
	n.untilT = GetTime() + NOTICE_SECONDS
	if C_Timer and C_Timer.After then C_Timer.After(NOTICE_SECONDS + 1, function() FR:UpdateUI() end) end
end

-- The notice to show now, or nil (expired, dismissed, switched off).
function FR:ActivePassNotice()
	local n = self.passNotice
	if not n then return nil end
	if GetTime() > n.untilT or not self:Get("autoPassNotice") or #n.steps == 0 then
		self.passNotice = nil
		return nil
	end
	return n
end

function FR:PassNoticeText(n)
	local count = #n.steps
	local first
	if self.current and self.current.title ~= n.guide then
		first = string.format(FR.L["\"%s\" is finished: %d steps were passed automatically."], n.short or "?", count)
		if count == 1 then first = string.format(FR.L["\"%s\" is finished: 1 step was passed automatically."], n.short or "?") end
	elseif count == 1 then
		first = FR.L["1 step was passed automatically."]
	else
		first = string.format(FR.L["%d steps were passed automatically."], count)
	end
	return first .. "\n|cff9aa0aa" .. FR.L["Click: go back to it. Right-click: hide."] .. "|r"
end

function FR:PassNoticeTooltip(owner, n)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:AddLine(FR.L["Passed steps"], 1, 1, 1)
	for i, s in ipairs(n.steps) do
		if i > 12 then
			GameTooltip:AddLine(string.format(FR.L["... and %d more"], #n.steps - 12), 0.7, 0.7, 0.7)
			break
		end
		GameTooltip:AddLine(string.format("%d  %s", s.idx or 0, s.text or ""), 0.9, 0.9, 0.9)
		GameTooltip:AddLine("   " .. tostring(s.why or ""), 0.6, 0.62, 0.68, true)
	end
	GameTooltip:Show()
end

function FR:PassNoticeClick(n, button)
	GameTooltip:Hide()
	self.passNotice = nil
	if button ~= "RightButton" then
		local first = n.steps[1]
		if first then self:OpenStep(n.guide, first.key, first.idx) return end
	end
	self:UpdateUI()
end

-- Lists --------------------------------------------------------------------------------------------

local function Entries(limit, withMinor)
	local list = List() or {}
	local out = {}
	for i = #list, 1, -1 do
		local e = list[i]
		if withMinor or not e.minor then
			out[#out + 1] = e
			if limit and #out >= limit then break end
		end
	end
	return out
end

-- Items for the right-click menu (UI.lua, AddItems): the last steps, newest first.
function FR:BuildHistoryMenu()
	local items = {}
	for _, e in ipairs(Entries(40, false)) do
		if e.how == "guide" then
			items[#items + 1] = { text = Cut(Clean(e.text), 60) }
		else
			local c = FR.HISTORY_COLORS[e.how] or { 0.8, 0.8, 0.8 }
			local tag = e.how == "done" and "" or (" (" .. FR.L[HOW_LABEL[e.how] or e.how] .. ")")
			items[#items + 1] = {
				text = string.format("%s%d  %s%s|r  |cff888888%s|r", Hex(c), e.idx or 0, Cut(Clean(e.text), 44), tag,
					Cut(tostring(e.short or "?"), 22)),
				onClick = function() FR:OpenStep(e.guide, e.key, e.idx) end,
			}
		end
	end
	if #items == 0 then items[1] = { text = FR.L["No steps recorded yet."] } end
	return items
end

-- Plain text of the newest entries (all of them, quiet ones too), for /fr history and the problem report.
function FR:HistoryText(limit)
	local out = {}
	for _, e in ipairs(Entries(limit, true)) do
		out[#out + 1] = string.format("%s  %-9s %s%s  [%s]%s", date("%Y-%m-%d %H:%M", e.t or 0),
			HOW_LABEL[e.how] or tostring(e.how), (e.idx or 0) > 0 and (e.idx .. " ") or "", tostring(e.text or ""),
			tostring(e.short or "?"), e.why and (" - " .. e.why) or "")
	end
	if #out == 0 then return "(none)" end
	return table.concat(out, "\n")
end

function FR:OpenHistory()
	FR.TextWindow({
		name = "History",
		title = FR.L["Step history"],
		hint = FR.L["Newest first. Copy with Ctrl+C. Right-click menu > History opens a step."],
		text = self:HistoryText(200),
		selectAll = false,
	})
end

-- Text and colour for the tooltip of a row of the step list.
function FR:StepStatusLines(step)
	local e = self:StepStatus(step)
	if not e then return nil end
	return string.format("%s (%s)", FR.L[HOW_LABEL[e.how] or e.how], date("%H:%M", e.t or 0)), e.why, FR.HISTORY_COLORS[e.how]
end
