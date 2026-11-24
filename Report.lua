-- Problem report: a text with everything that is needed to see what went wrong
-- with a step (guide, step, what the guide expects and the game reports, settings,
-- client), to copy out of a window and send to the author. RestedXP has the same
-- (its feedback form). The character's name is not part of it.
local _, ns = ...
local FR = ns.FR

local function Strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end

-- Settings that change what a step shows or does.
local SETTINGS = {
	"autoAdvance", "autoArrive", "autoAccept", "autoTurnin", "autoGossip", "language",
	"showArrow", "mapPins", "markTargets", "targetMacro", "nameplateIcons",
}

function FR:BuildReport(stepIndex)
	local L = FR.L
	local g = self.current
	local out = {}
	local function Add(text, ...)
		out[#out + 1] = select("#", ...) > 0 and string.format(text, ...) or text
	end

	Add(L["Describe the problem:"])
	Add("")
	Add("")
	Add("")
	Add(L["Do not change anything below this line."])
	Add("```")

	local version, build = "?", "?"
	if GetBuildInfo then version, build = GetBuildInfo() end
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	Add("ForeverRoute %s", tostring(FR.version))
	Add("Client %s (build %s), game language %s, addon language %s",
		tostring(version), tostring(build), tostring(GetLocale()), tostring(self:Language()))
	Add("Character: %s %s, level %s, %s%s", tostring(race), tostring(class), tostring(UnitLevel("player")),
		tostring(UnitFactionGroup("player")), FR.IsHardcore() and ", hardcore" or "")

	-- Where the player is.
	local zone = FR.SafeText(GetRealZoneText)
	if zone == "" then zone = "?" end
	local sub = FR.SafeText(GetSubZoneText)
	local mapID, x, y
	if C_Map and C_Map.GetBestMapForUnit then
		local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
		if ok then mapID = FR.Plain(id) end
		if mapID and C_Map.GetPlayerMapPosition then
			local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
			if okPos and pos and pos.GetXY then x, y = pos:GetXY() end
			x, y = FR.Plain(x), FR.Plain(y)
		end
	end
	if FR.InInstance() then sub = (sub ~= "" and (sub .. " ") or "") .. "[instance]" end
	Add("Zone: %s%s (map %s)%s", tostring(zone), sub ~= "" and (" / " .. sub) or "", tostring(mapID),
		x and string.format(", %.1f / %.1f", x * 100, (y or 0) * 100) or "")

	if g and g.steps then
		Add("")
		Add("Guide: %s", Strip(g.title))
		Add("Group: %s, language %s, #version %s, file %s#%s", tostring(g.group), tostring(g.lang),
			tostring(g.header and g.header.version), tostring(g.file), tostring(g.fileIndex))
		if g.pair then
			Add("Translated guide completed from the English one: %d of %d steps are English",
				g.englishSteps or 0, g.mergedSteps or 0)
		end
		local current = self.stepIndex
		local idx = stepIndex or current
		local s = g.steps[idx]
		Add("Current step: %s of %d", tostring(current), #g.steps)
		if s then
			Add("")
			Add("Reported step: %d of %d (order %s, key %s)", idx, #g.steps, tostring(s.order), tostring(FR.StepKey(s)))
			Add("Signature: %s", tostring(s.sig):sub(1, 400))
			for _, line in ipairs(self:DescribeStep(s)) do Add(line) end
			Add("Lines:")
			for _, e in ipairs(s.elements) do
				local text = Strip(e.text)
				Add("   %s%s%s", e.cmd and ("." .. e.cmd .. " ") or "", text:sub(1, 120), e.hidden and "  (hidden)" or "")
			end
		end
		local active = {}
		for _, a in ipairs(self:GetActiveSteps()) do active[#active + 1] = tostring(a.idx) end
		Add("Steps on screen: %s", table.concat(active, ", "))

		local on = {}
		for _, d in ipairs(FR.DUNGEONS) do
			if FR.DungeonEnabled(d[1], g) then
				local byGuide = not (ForeverRouteDB and ForeverRouteDB.dungeons and ForeverRouteDB.dungeons[d[1]] ~= nil)
				on[#on + 1] = d[1] .. (byGuide and "*" or "")
			end
		end
		Add("Dungeons on (* = the guide's default, not your choice): %s; phase %d", #on > 0 and table.concat(on, " ") or "none", FR.PHASE)
	else
		Add("No guide selected")
	end

	-- What the guide passed, finished or left open lately, and why ("a step was skipped" reports).
	if self.HistoryText then
		Add("")
		Add("Recent steps (newest first):")
		Add("%s", self:HistoryText(15))
	end

	local settings = {}
	for _, key in ipairs(SETTINGS) do settings[#settings + 1] = key .. "=" .. tostring(self:Get(key)) end
	Add("")
	Add("Settings: %s", table.concat(settings, ", "))
	Add("```")
	return table.concat(out, "\n")
end

-- Opens the report window (for step `stepIndex`, the current one by default).
function FR:OpenReport(stepIndex)
	local text = self:BuildReport(stepIndex)
	local w = FR.TextWindow({
		name = "Report",
		title = FR.L["Report a problem"],
		hint = FR.L["Copy this text (Ctrl+C) and send it to the author of ForeverRoute."],
		text = text,
		focus = true,
	})
	-- The cursor goes to the first empty line under "Describe the problem:".
	if w and w.edit then w.edit:SetCursorPosition(#FR.L["Describe the problem:"] + 1) end
end
