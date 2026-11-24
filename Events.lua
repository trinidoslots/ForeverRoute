-- Startup, game events and slash commands.
local addonName, ns = ...
local FR = ns.FR

-- NPC id of the unit the player is interacting with.
local function InteractNpcID()
	-- Unit values can be secret in instances: FR.UnitNpcId reads them safely.
	local kind, id = FR.UnitNpcId("npc")
	if not kind then kind, id = FR.UnitNpcId("target") end
	if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then return id end
	return nil
end

local INTERACT = {
	GOSSIP_SHOW = "gossip", QUEST_GREETING = "gossip", QUEST_DETAIL = "gossip",
	QUEST_PROGRESS = "gossip", QUEST_COMPLETE = "gossip", CONFIRM_BINDER = "gossip",
	TAXIMAP_OPENED = "taxi",
	BANKFRAME_OPENED = "bank", PET_STABLE_SHOW = "stablemaster", HEARTHSTONE_BOUND = "home",
}

local PROGRESS = {
	"QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE",
	"UNIT_QUEST_LOG_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
	"SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_FACTION",
	"PLAYER_XP_UPDATE", "PLAYER_MONEY", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
	"BAG_UPDATE_COOLDOWN",
}

local HEARTHSTONE = { [8690] = true }

-- Flights ------------------------------------------------------------------------------
-- The game does not always tell that a flight started the moment control is lost (UnitOnTaxi is
-- still false then), so the flight is also recognised by TakeTaxiNode having been called a moment
-- before (like RestedXP does).
local FLIGHT_WINDOW = 1.5
local function FlightJustStarted()
	return FR.flightStart ~= nil and GetTime() - FR.flightStart < FLIGHT_WINDOW
end

-- The first "Fly to <place>" line of the steps on screen that is not done yet.
local function OpenFlyElement()
	for _, step in ipairs(FR:GetActiveSteps()) do
		for _, e in ipairs(step.elements) do
			if e.kind == "fly" and e.dest and not FR:IsMarked(step, e) then return e end
		end
	end
end

-- The flight map of a flight master is open: with "auto fly" on, take the flight the open step asks
-- for. The flight masters are found by node id and their English name (FlightData.lua), so this does
-- not depend on the language of the game. Holding Shift flies nowhere.
local function AutoFly()
	if not FR:Get("autoFly") or IsShiftKeyDown() then return end
	if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_Map and C_Map.GetBestMapForUnit and TakeTaxiNode) then return end
	local e = OpenFlyElement()
	if not e then return end
	local map = C_Map.GetBestMapForUnit("player")
	local list = map and C_TaxiMap.GetAllTaxiNodes(map)
	if not list then return end
	local state = Enum and Enum.FlightPathState
	local names = FR.FLIGHT_NODES and FR.FLIGHT_NODES[UnitFactionGroup("player") or ""]
	local want = e.dest:upper()
	for _, node in ipairs(list) do
		local usable = not state or (node.state ~= state.Unreachable and node.state ~= state.Current)
		local name = (names and names[node.nodeID]) or (GetLocale() == "enUS" and node.name) or nil
		if usable and node.slotIndex and name and name:upper():find(want, 1, true) then
			TakeTaxiNode(node.slotIndex)
			return
		end
	end
end

local ev = CreateFrame("Frame")

-- Unknown events raise an error on some clients, so register defensively.
local function Register(event) pcall(ev.RegisterEvent, ev, event) end

-- Vendors and trainers count as visited when their window is closed again (like
-- RestedXP): note whom the window was opened for, finish the line on closing.
local WINDOWS = {
	MERCHANT_SHOW = { open = true, kind = "merchant" }, MERCHANT_CLOSED = { kind = "merchant" },
	TRAINER_SHOW = { open = true, kind = "trainer" }, TRAINER_CLOSED = { kind = "trainer" },
}
local windowNpc = {}

-- Every step of the start runs through FR.Safe: a step that fails is reported in the chat and the
-- log, and the steps after it still run (so a failing step can never leave the options, the guide
-- window or the events dead).
local function Step(name, func, ...) return FR.Safe("start: " .. name, func, ...) end

local function OnLogin()
	FR:InitDB()
	Step("error log", FR.InstallErrorLog)
	Step("guide pairs", FR.PairGuides)   -- German guides with their English twins (before any guide is read)
	Step("imports", function() FR:LoadImports() end)  -- the guides the player imported
	Step("gold mode", function() FR:CheckGoldMode() end)
	if FR.Tracker then Step("tracker", FR.Tracker.Refresh) end   -- leveling tracker (events, /played)
	Step("positions", function() FR:RestorePositions() end)
	Step("active frames", function() FR:RestoreActivePositions() end)
	Step("settings", function() FR:ApplySettings() end)
	Step("options", function() FR:RegisterOptions() end)
	Step("conditions", function() FR:RefreshConditionEnv() end)

	Step("guide", function()
		local saved = ForeverRouteCharDB.guide
		-- A saved guide of the other kind (leveling / farming) is not opened.
		local savedGuide = saved and FR.guidesByTitle[saved]
		if savedGuide and (savedGuide.farm == true) ~= FR:IsGoldMode() then saved = nil end
		-- An English guide that exists in the player's language (German) opens in that language.
		local twin = saved and savedGuide and FR:LanguageTwin(savedGuide)
		if twin then saved = twin.title end
		if not (saved and FR:SetGuide(saved, ForeverRouteCharDB.step, ForeverRouteCharDB.stepKey)) then
			local suggested = FR:FindSuggestedGuide()
			if suggested then FR:SetGuide(suggested, 1) else FR:UpdateUI() end
		end
		if FR:Get("hidden") then FR.frame:Hide() end
	end)
	Step("minimap button", function() FR:UpdateMinimapButton() end)

	for _, e in ipairs(PROGRESS) do Register(e) end
	Register("PLAYER_ENTERING_WORLD")   -- the error log goes in front of handlers other addons set
	for e in pairs(INTERACT) do Register(e) end
	for e in pairs(WINDOWS) do Register(e) end
	-- Own spell casts only (hearthstone, spells a step asks for).
	if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
	else Register("UNIT_SPELLCAST_SUCCEEDED") end

	-- Flights: remember when one was ordered; a moment later the flight is on (or control was lost).
	if hooksecurefunc and TakeTaxiNode then
		hooksecurefunc("TakeTaxiNode", function()
			FR.flightStart = GetTime()
			C_Timer.After(FLIGHT_WINDOW, function()
				if UnitOnTaxi and UnitOnTaxi("player") then FR:MarkKind("fly") end
			end)
		end)
	end

	-- Turn-ins on clients without QUEST_TURNED_IN.
	if hooksecurefunc and GetQuestReward then
		hooksecurefunc("GetQuestReward", function()
			local id = GetQuestID and GetQuestID()
			if id and id > 0 then FR.turnedIn[id] = true end
			FR:QueueRefresh()
		end)
	end

	FR:Print(string.format(FR.L["v%s loaded, %d guides. Type %s for commands."], FR.version, #FR.guides, "|cffffd100/fr help|r"))
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, ...)
	local arg1 = ...
	if event == "PLAYER_LOGIN" then
		OnLogin()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		FR.InstallErrorLog()
		FR:QueueRefresh()   -- zone / instance changed
		return
	end
	local window = WINDOWS[event]
	if window then
		if window.open then
			windowNpc[window.kind] = InteractNpcID() or false
		else
			local npc = windowNpc[window.kind]
			windowNpc[window.kind] = nil
			if npc ~= nil then FR:OnInteract(npc or nil, window.kind) end
		end
		return
	end
	if INTERACT[event] then
		FR:OnInteract(InteractNpcID(), INTERACT[event])
		if event == "TAXIMAP_OPENED" then FR.Safe("auto fly", AutoFly) end
		if event ~= "HEARTHSTONE_BOUND" then return end
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if arg1 ~= "player" then return end
		local spellID = select(3, ...)
		if HEARTHSTONE[spellID] then FR:MarkKind("hs") end
		if spellID then FR:MarkKind("cast", spellID) end
		return
	end
	if event == "PLAYER_CONTROL_LOST" and ((UnitOnTaxi and UnitOnTaxi("player")) or FlightJustStarted()) then
		FR:MarkKind("fly")
	end
	if event == "PLAYER_DEAD" then FR:MarkKind("deathskip") end
	if event == "QUEST_TURNED_IN" and arg1 then FR.turnedIn[arg1] = true end
	if event == "UNIT_QUEST_LOG_CHANGED" and arg1 ~= "player" then return end
	if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
		FR:InvalidateQuestLog()
	end
	FR:QueueRefresh()
end)

-- Slash commands ---------------------------------------------------------------------

local HELP = {
	{ "/fr", "show / hide the guide window" },
	{ "/fr guides", "choose a guide" },
	{ "/fr settings", "open the settings ('/fr settings debug' shows their sizes for a bug report)" },
	{ "/fr junk", "list the items marked as junk or useful, and the junk you carry (Inventory Manager)" },
	{ "/fr next, /fr prev", "change step" },
	{ "/fr restart", "restart the current guide" },
	{ "/fr arrow", "toggle the waypoint arrow" },
	{ "/fr lock", "lock / unlock the window" },
	{ "/fr reset", "reset window and arrow positions" },
	{ "/fr dump", "list the quest objectives of the current step (for bug reports)" },
	{ "/fr perf [reset]", "how long the window updates take (to find lags)" },
	{ "/fr macro","show what the macros FRTarget and FRMark contain" },
	{ "/fr dungeons", "which dungeons are on for the current guide and why (for bug reports)" },
	{ "/fr hardcore [on|off|auto]", "hardcore mode: show the deathless variant of the steps" },
	{ "/fr gold", "switch between the leveling guides and the farming guides (gold mode)" },
	{ "/fr levels", "the leveling report: time and experience of each level" },
	{ "/fr history", "the steps you finished, that were passed on their own or skipped, and why" },
	{ "/fr party", "show the steps of your party members (ForeverRoute users)" },
	{ "/fr plates [on|dump|zoomtest|perf]", "why an icon shows or not next to name plates; 'on' turns the game's name plates on, 'dump' lists the parts of the target's plate, 'zoomtest' measures the zoom, 'perf' shows the frame time per addon" },
	{ "/fr errors [clear]", "show the errors ForeverRoute caused (text to copy), or clear them" },
	{ "/fr report", "report a problem with the current step (text to copy)" },
	{ "/fr import", "add a guide from its text" },
	{ "/fr version", "your version and the newest one other ForeverRoute users run" },
	{ "/fr update", "how to get a newer version onto this PC" },
}

SLASH_FOREVERROUTE1 = "/fr"
SLASH_FOREVERROUTE2 = "/foreverroute"
SlashCmdList.FOREVERROUTE = function(msg)
	local cmd = (msg or ""):lower():match("^(%S*)")
	if cmd == "" or cmd == "toggle" or cmd == "show" then FR:Toggle()
	elseif cmd == "next" then FR:NextStep()
	elseif cmd == "prev" or cmd == "back" then FR:PrevStep()
	elseif cmd == "guides" or cmd == "menu" or cmd == "list" then FR:ShowPicker()
	elseif cmd == "settings" or cmd == "config" or cmd == "options" then
		local arg = (msg or ""):lower():match("^%S+%s+(%S+)")
		if arg == "debug" then FR:SettingsDebug() else FR:ToggleSettings() end
	elseif cmd == "restart" then FR:RestartGuide()
	elseif cmd == "arrow" then
		FR:Set("showArrow", not FR:Get("showArrow"))
		FR:Print(FR.L[FR:Get("showArrow") and "Arrow on" or "Arrow off"])
	elseif cmd == "lock" or cmd == "unlock" then
		FR:Set("locked", not FR:Get("locked"))
		FR:Print(FR.L[FR:Get("locked") and "Window locked" or "Window unlocked"])
	elseif cmd == "junk" then
		FR:PrintJunk()
	elseif cmd == "dump" then
		FR:DumpStep()
	elseif cmd == "dungeons" then
		FR:PrintDungeons()
	elseif cmd == "plates" or cmd == "nameplates" then
		local arg = (msg or ""):lower():match("^%S+%s+(%S+)")
		if arg == "on" then FR:EnableNameplates()
		elseif arg == "dump" then FR:DumpPlate()
		elseif arg == "zoomtest" then FR:ZoomTest()
		elseif arg == "perf" then FR:PerfReport()
		else FR:PrintNameplateStatus() end
	elseif cmd == "errors" or cmd == "error" then
		local arg = (msg or ""):lower():match("^%S+%s+(%S+)")
		if arg == "clear" then
			if ForeverRouteDB then ForeverRouteDB.errors = nil end
			FR:Print(FR.L["Error log cleared."])
		else
			local text = FR.ErrorLogText()
			if text == "" then
				FR:Print(FR.L["No errors from ForeverRoute were recorded."])
			else
				FR.TextWindow{
					name = "Errors", title = FR.L["ForeverRoute errors"],
					hint = FR.L["Copy this text (Ctrl+C) and send it with your bug report. /fr errors clear deletes it."],
					text = text, selectAll = true,
				}
			end
		end
	elseif cmd == "party" then
		local count = #FR.Party.List()
		if FR.Party.CanShow() then
			FR.Party.Show()
		else
			FR:Print(string.format(FR.L["Party steps: %s, %d group member(s) with ForeverRoute sharing their steps."],
				FR:Get("partySteps") and FR.L["on"] or FR.L["off"], count))
		end
	elseif cmd == "levels" or cmd == "level" then
		FR:OpenLevelReport()
	elseif cmd == "history" then
		FR:OpenHistory()
	elseif cmd == "gold" then
		FR:ToggleGoldMode()
	elseif cmd == "hardcore" then
		local arg = (msg or ""):lower():match("^%S+%s+(%S+)")
		if arg == "on" or arg == "off" or arg == "auto" then
			FR:Set("hardcoreMode", arg)
		elseif arg then
			FR:Print("/fr hardcore [on|off|auto]")
			return
		else
			FR:ToggleHardcore()
		end
		FR:Print(string.format(FR.L["Hardcore mode: %s (setting: %s)"],
			FR.HardcoreMode() and FR.L["on"] or FR.L["off"], tostring(FR:Get("hardcoreMode"))))
	elseif cmd == "report" or cmd == "bug" or cmd == "feedback" then
		FR:OpenReport()
	elseif cmd == "import" then
		FR:OpenImport()
	elseif cmd == "version" or cmd == "ver" then
		FR.Version.Print()
	elseif cmd == "update" then
		FR.Version.ShowUpdate()
	elseif cmd == "where" then
		FR:PrintWhere()
	elseif cmd == "macro" or cmd == "macros" then
		FR:PrintMacroInfo()
	elseif cmd == "perf" then
		FR:PrintPerf((msg or ""):lower():find("reset") ~= nil)
	elseif cmd == "reset" then
		FR:ResetPositions()
		FR:Print(FR.L["Window and arrow positions reset."])
	else
		FR:Print(FR.L["Commands:"])
		for _, h in ipairs(HELP) do
			DEFAULT_CHAT_FRAME:AddMessage("   |cffffd100" .. h[1] .. "|r - " .. FR.L[h[2]])
		end
	end
end
