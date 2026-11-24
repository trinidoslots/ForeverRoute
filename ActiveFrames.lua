-- "Active Items" and "Active Targets": a small flat box with its title as
-- the first line and a grid of square buttons.
--   items   - click to use a quest item the current steps need
--   targets - enemies in the top rows, NPCs to talk to in the bottom rows;
--             click to target. As soon as the creature has been seen (target,
--             mouseover or name plate) its face replaces the placeholder.
-- The buttons are secure action buttons, so they can only change out of
-- combat; changes during combat are applied when combat ends.
local _, ns = ...
local FR = ns.FR

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE = "Interface\\Buttons\\WHITE8X8"
-- The bars are drawn pixel-perfect: one unit of their scale is one screen
-- pixel, so SIZE etc. are real pixels. SIZE comes from the "Button size"
-- setting (see Metrics).
local SIZE, STEP, PER_ROW, MAX = 28, 31, 10, 20
local SIDE, TOP, BOTTOM, GROUP_GAP = 10, 22, 8, 4

local function Metrics()
	SIZE = math.max(18, math.min(56, FR:Get("barSize") or 28))
	STEP = SIZE + 3
end

local TALK_ICON = 2056011                         -- speech bubble (RestedXP's placeholder)
local TALK_FALLBACK = "Interface\\GossipFrame\\GossipGossipIcon"
local KILL_ICON = "Interface\\Icons\\INV_Sword_04"

-- Creature name in the game's language (guides use English names).
-- Spelling mistakes in the guides' creature names (the macros need the exact in-game name).
FR.NPC_FIXES = {
	["Breton Samuels"] = "Brenton Samuels",
}

function FR.NpcName(name)
	-- 1) learned from the game (a creature the mouse touched that is spelled differently)
	local alias = ForeverRouteDB and ForeverRouteDB.npcAlias and ForeverRouteDB.npcAlias[name]
	if alias then return alias end
	return (FR.npcNames and FR.npcNames[name]) or FR.NPC_FIXES[name] or name
end

-- Number of edits between two strings (for names that differ by a typo).
local function EditDistance(a, b)
	local la, lb = #a, #b
	if math.abs(la - lb) > 3 then return 99 end
	local prev = {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		local cur = { [0] = i }
		for j = 1, lb do
			local cost = (a:byte(i) == b:byte(j)) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev = cur
	end
	return prev[lb]
end
FR.EditDistance = EditDistance

local function ItemIcon(id)
	local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
	if not f then return nil end
	local ok, tex = pcall(f, id)
	return ok and tex or nil
end

local function ItemCooldown(id)
	local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if not f then return 0, 0 end
	local ok, start, duration = pcall(f, id)
	if not ok then return 0, 0 end
	return start or 0, duration or 0
end

-- Quest item shown on the quest's tracker line (later clients only).
local function QuestSpecialItem(qid)
	if not (GetQuestLogSpecialItemInfo and GetQuestLogIndexByID) then return nil end
	local index = GetQuestLogIndexByID(qid)
	if not index or index == 0 then return nil end
	local ok, link = pcall(GetQuestLogSpecialItemInfo, index)
	if not ok or type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

-- Thin, sharp frame (1 px border) used for the bars and their title tabs.
-- Same flat panel with hairline border as the guide window.
local function Crisp(f)
	if not f.SetBackdrop then return end
	f.pixelUnit = 1
	FR.Skin(f, "bg")
	local c = FR.Theme().bg
	f:SetBackdropColor(c[1], c[2], c[3], math.max(0.75, FR:Get("alpha") or 0.9))
end

-- Bars -----------------------------------------------------------------------------------

local function MakeBar(key, titleKey, defaultY)
	local f = CreateFrame("Frame", "ForeverRoute" .. key, UIParent, BACKDROP)
	f:SetSize(60, SIZE + TOP + BOTTOM)
	f:SetScale(FR.PixelScale(1))
	local k = FR.UIPixels()
	f:SetPoint("LEFT", UIParent, "LEFT", math.floor(330 * k + 0.5), math.floor(defaultY * k + 0.5))
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	local function Start() if not FR:Get("locked") then f:StartMoving() end end
	local function Stop()
		f:StopMovingOrSizing()
		-- Re-anchor on whole pixels so the buttons stay sharp.
		local p, _, rp, x, y = f:GetPoint()
		if not p then return end
		x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
		f:ClearAllPoints()
		f:SetPoint(p, UIParent, rp, x, y)
		if ForeverRouteDB then ForeverRouteDB["pos" .. key] = { p, rp, x, y } end
	end
	f:SetScript("OnDragStart", Start)
	f:SetScript("OnDragStop", Stop)
	f.key = key

	-- Title as the first line inside the box. Anchored to a whole pixel at the
	-- left edge: text centred on a fractional width is drawn with uneven
	-- letter spacing.
	f.title = FR.MakeText(f, FR.fontBar)
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -7)
	f.title:SetJustifyH("LEFT")
	f.title:SetWordWrap(false)
	FR.Accent(f.title)
	FR:Loc(f.title, titleKey, function(text) return string.upper(text) end)
	-- Accent bar on the left edge, the same as on the step cards.
	f.bar = f:CreateTexture(nil, "ARTWORK")
	f.bar:SetTexture(WHITE)
	f.bar:SetPoint("TOPLEFT", 1, -1)
	f.bar:SetPoint("BOTTOMLEFT", 1, 1)
	f.bar:SetWidth(2)
	FR.Accent(f.bar)

	f.buttons = {}
	f:Hide()
	return f
end

local itemsBar = MakeBar("ActiveItems", "Active Items", 120)
local targetsBar = MakeBar("ActiveTargets", "Active Targets", 60)
FR.itemsBar, FR.targetsBar = itemsBar, targetsBar

local styled
local function Restyle()
	local key = tostring(FR:Get("theme")) .. tostring(FR:Get("alpha"))
	if styled == key then return end
	styled = key
	for _, bar in ipairs({ itemsBar, targetsBar }) do Crisp(bar) end
end

local function GetButton(bar, i)
	local b = bar.buttons[i]
	if b then return b end
	b = CreateFrame("Button", "ForeverRoute" .. bar.key .. "Button" .. i, bar, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b.face, b.targetName, b.itemID, b.macroName = false, false, false, false
	b:RegisterForClicks("AnyUp", "AnyDown")
	-- Hairline border like the panels (one pixel, faint white).
	b.edge = b:CreateTexture(nil, "BACKGROUND")
	b.edge:SetTexture(WHITE)
	b.edge:SetVertexColor(1, 1, 1, 0.16)
	b.edge:SetPoint("TOPLEFT", -1, 1)
	b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
	b.back = b:CreateTexture(nil, "BACKGROUND", nil, 1)
	b.back:SetTexture(WHITE)
	b.back:SetVertexColor(0.05, 0.06, 0.09, 1)
	b.back:SetAllPoints()
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(WHITE)
	FR.Accent(hl, 0.28)
	-- Raid icon this button sets on the creature (see SetupTarget).
	b.marker = b:CreateTexture(nil, "OVERLAY")
	b.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	b.marker:SetPoint("TOPRIGHT", 2, 2)
	b.marker:Hide()
	b.count = b:CreateFontString(nil, "OVERLAY")
	b.count:SetFontObject(FR.fontBar)
	b.count:SetPoint("BOTTOMRIGHT", 0, 1)
	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.itemID then
			GameTooltip:SetItemByID(self.itemID)
		elseif self.targetName then
			GameTooltip:AddLine(self.targetName, 1, 1, 1)
		elseif self.macroName then
			GameTooltip:AddLine(self.macroName, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bar.buttons[i] = b
	return b
end

-- Faces ------------------------------------------------------------------------------------
-- A portrait can only be drawn while the unit exists, so each creature's face
-- is kept in its own texture and moved onto whichever button shows it.

local faces = {}            -- creature name (game language) -> texture
local holder = CreateFrame("Frame")
holder:Hide()

local function AttachFace(b)
	local face = b.targetName and faces[b.targetName]
	if b.face and b.face ~= face then
		b.face:SetParent(holder); b.face:Hide(); b.face.button = false
		b.face = false
	end
	if face then
		if face.button and face.button ~= b then face.button.face = false; face.button.icon:Show() end
		face:SetParent(b)
		face:ClearAllPoints()
		face:SetAllPoints(b)
		face:SetDrawLayer("ARTWORK", 1)
		face:Show()
		face.button = b
		b.face = face
		b.icon:Hide()
	else
		b.icon:Show()
	end
end

-- Names currently wanted on the targets bar.
local wantedNames = {}

local function Remember(unit)
	if type(unit) ~= "string" or not SetPortraitTexture then return end
	local okExists, exists = pcall(UnitExists, unit)
	if not (okExists and FR.Plain(exists)) then return end
	local okPlayer, isPlayer = pcall(UnitIsPlayer, unit)
	if okPlayer and FR.Plain(isPlayer) then return end
	local name = FR.SafeUnitName(unit)   -- nil when the game hides it (instances)
	if not (name and wantedNames[name]) then return end
	local face = faces[name]
	if not face then
		face = holder:CreateTexture(nil, "ARTWORK")
		face:SetTexCoord(0.12, 0.88, 0.12, 0.88)
		face.button = false
		faces[name] = face
	end
	pcall(SetPortraitTexture, face, unit)
	for _, b in ipairs(targetsBar.buttons) do
		if b:IsShown() and b.targetName == name then AttachFace(b) end
	end
end

local function ScanNamePlates()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or not plates then return end
	for _, plate in ipairs(plates) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then Remember(unit) end
	end
end

-- Layout ---------------------------------------------------------------------------------

-- A ".macro" button: runs the macro text (spell:ID becomes the spell's name).
local function SetupMacro(b, macro)
	b.itemID, b.targetName, b.macroName = false, false, macro.name
	local body = macro.body:gsub("spell:(%d+)", function(id)
		local name = GetSpellInfo and GetSpellInfo(tonumber(id))
		return name or ("spell:" .. id)
	end)
	b:SetAttribute("type", "macro")
	b:SetAttribute("item", nil)
	b:SetAttribute("macrotext", body)
	b.marker:Hide()
	AttachFace(b)
	b.icon:SetTexture(macro.icon)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count:SetText("")
	b.cooldown:Hide()
end

local function SetupItem(b, id)
	if type(id) == "table" then return SetupMacro(b, id) end
	b.macroName = false
	b.itemID, b.targetName = id, false
	b:SetAttribute("type", "item")
	b:SetAttribute("item", "item:" .. id)
	b:SetAttribute("macrotext", nil)
	b.marker:Hide()
	AttachFace(b)
	b.icon:SetTexture(ItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local n = FR.ItemCount(id)
	b.count:SetText(n > 1 and n or "")
	local start, duration = ItemCooldown(id)
	if duration and duration > 0 then b.cooldown:SetCooldown(start, duration) else b.cooldown:Hide() end
end

local function SetupTarget(b, entry)
	b.itemID, b.targetName = false, entry.name
	b:SetAttribute("type", "macro")
	b:SetAttribute("item", nil)
	-- Like RestedXP: the click also puts a raid icon on the creature (skull,
	-- cross, square for enemies; star, circle, diamond, triangle for NPCs).
	-- "!" sets the icon even when it is already used, without it the icon of
	-- an NPC toggles. The game does not let addons set icons by themselves.
	local marker = FR:Get("markTargets") and entry.marker or nil
	local macro = "/cleartarget\n/targetexact " .. entry.name
	if marker then macro = macro .. "\n/tm " .. (entry.enemy and "!" or "") .. marker end
	b:SetAttribute("macrotext", macro)
	if marker then
		local col, row = (marker - 1) % 4, math.floor((marker - 1) / 4)
		b.marker:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
		b.marker:SetSize(math.max(10, math.floor(SIZE * 0.42)), math.max(10, math.floor(SIZE * 0.42)))
		b.marker:Show()
	else
		b.marker:Hide()
	end
	if entry.enemy then
		b.icon:SetTexture(KILL_ICON)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	else
		b.icon:SetTexture(TALK_ICON)
		if not b.icon:GetTexture() then b.icon:SetTexture(TALK_FALLBACK) end
		b.icon:SetTexCoord(0, 1, 0, 1)
	end
	b.count:SetText("")
	b.cooldown:Hide()
	AttachFace(b)
end

-- Targeting macro (like RestedXP's RXPTargeting) --------------------------------------------
-- A game macro that targets the creatures of the current step and marks the
-- one it finds with a raid icon, so a single key press is enough. The buttons in
-- the box do the same for one creature each.
local MACRO_NAME, MACRO_ICON, MACRO_MAX = "FRTarget", "Ability_EyeOfTheOwl", 223
local macroBody

local function UpdateMacro(enemies, friends)
	if not (GetMacroInfo and CreateMacro and EditMacro) then return end
	if not FR:Get("targetMacro") then
		if macroBody ~= false then
			if GetMacroInfo(MACRO_NAME) and DeleteMacro then pcall(DeleteMacro, MACRO_NAME) end
			macroBody = false
		end
		return
	end
	local names, seen = {}, {}
	for _, list in ipairs({ enemies, friends }) do
		for _, entry in ipairs(list) do
			if not seen[entry.name] then seen[entry.name] = true; names[#names + 1] = entry.name end
		end
	end
	-- The first creature must be targeted last (the last /targetexact that finds
	-- its creature wins), so the lines run from the end of the list to the start.
	local body
	for n = #names, 1, -1 do
		local line = "/targetexact " .. names[n]
		body = body and (body .. "\n" .. line) or line
	end
	if body then
		-- Macros hold 255 characters: drop the lowest priority lines (at the top).
		-- Exactly RestedXP's text: its "/tm !7" is only part of the macro on clients where that is
		-- known to work (WOW_PROJECT_CAMELOT/MAINLINE). Icons come from the buttons and FRMark.
		local marker = ""
		if (WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
			or (WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) then
			marker = "\n/tm !7"
		else
			MACRO_MAX = 230
		end
		while #body > MACRO_MAX do body = (body:gsub("^\n?[^\n]*[\n]*", "", 1)) end
		body = body .. marker .. "\n/targetlasttarget [dead]"
	else
		body = "//ForeverRoute - " .. FR.L["current step has no targets"]
	end
	local exists = GetMacroInfo(MACRO_NAME)
	if exists and body == macroBody then return end
	if exists then
		pcall(EditMacro, MACRO_NAME, MACRO_NAME, nil, body)
	else
		if (GetNumMacros() or 0) >= 119 then return end
		if not pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body) then return end
		if ForeverRouteDB and not ForeverRouteDB.macroAnnounced and #names > 0 then
			ForeverRouteDB.macroAnnounced = true
			C_Timer.After(1, function()
				FR:Print(string.format(FR.L["A targeting macro (%s) has been created. Put it on an action bar: one press targets and marks the creatures of the current step."], MACRO_NAME))
			end)
		end
	end
	macroBody = body
end

-- Mouseover marking ----------------------------------------------------------------------------
-- In TBC RestedXP put a raid icon on every creature of the step as soon as the mouse touched it.
-- The game of this client does not let addons set raid icons, only a key press / click on a secure
-- button can (macro "/tm"). So: while the mouse is on a creature of the step, a secure button and
-- a game macro (FRMark) are loaded with "target the mouseover unit, put ITS icon on it". One press of
-- the bound key (Key Bindings > AddOns > ForeverRoute) or of the macro does the rest.
local MARK_MACRO, MARK_ICON = "FRMark", "Ability_Hunter_SniperShot"
local markerByName, markBody, markName, lastHover, markHinted = {}, nil, nil, nil, false
local markButton

_G.BINDING_HEADER_FOREVERROUTE = "ForeverRoute"
_G["BINDING_NAME_CLICK ForeverRouteMarkButton:LeftButton"] = FR.L["Mark the creature under the cursor"]

local function MarkText(info)
	if not info then return "//ForeverRoute - " .. FR.L["no creature of the step under the cursor"] end
	-- First the creature by its name (works for a click on an action bar too, where the mouse is not
	-- on the creature any more), then the one under the cursor if there is one, then its icon.
	-- "!" sets the icon even when it is already in use, so a second press can not remove it again.
	return "/cleartarget\n/targetexact " .. info.name
		.. "\n/target [@mouseover,exists] mouseover\n/tm !" .. info.marker
end

local function SetMarkBody(body)
	if body == markBody then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if not markButton then
		markButton = CreateFrame("Button", "ForeverRouteMarkButton", UIParent, "SecureActionButtonTemplate")
		markButton:RegisterForClicks("AnyUp", "AnyDown")
		markButton:SetAttribute("type", "macro")
		markButton:SetSize(1, 1)
		markButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
		-- Feedback after each press (what got targeted, which icon it has): shows in the chat
		-- whether the key / click did anything and where it stopped.
		markButton:HookScript("PostClick", function(_, btn, down)
			local useDown = GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")
			if down ~= nil and (down and true or false) ~= (useDown and true or false) then return end
			C_Timer.After(0.25, function()
				local hasTarget = UnitExists("target")
				local name = hasTarget and (FR.SafeUnitName("target") or "?") or FR.L["nothing"]
				local icon = hasTarget and GetRaidTargetIndex and FR.Plain(GetRaidTargetIndex("target"))
				local over = UnitExists("mouseover") and (FR.SafeUnitName("mouseover") or "?") or "-"
				FR:Print(string.format(FR.L["Mark key pressed: target %s, icon %s, mouseover %s"],
					tostring(name), tostring(icon or "-"), tostring(over)))
			end)
		end)
		markButton:EnableMouse(false)
		markButton:SetAlpha(0)
		markButton:Show()
	end
	markBody = body
	markButton:SetAttribute("macrotext", body)
	if GetMacroInfo and EditMacro and FR:Get("targetMacro") and GetMacroInfo(MARK_MACRO) then
		pcall(EditMacro, MARK_MACRO, MARK_MACRO, nil, body)
	end
end

local function CreateMarkMacro()
	if not (GetMacroInfo and CreateMacro) or GetMacroInfo(MARK_MACRO) then return end
	if (GetNumMacros() or 0) >= 119 then return end
	pcall(CreateMacro, MARK_MACRO, MARK_ICON, markBody or MarkText(nil))
end

-- Called on every change of the mouseover unit: remembers which icon belongs to the creature.

function FR:OnMouseoverMark()
	local okExists, exists = pcall(UnitExists, "mouseover")
	local okPlayer, isPlayer = pcall(UnitIsPlayer, "mouseover")
	local hovering = okExists and FR.Plain(exists) and not (okPlayer and FR.Plain(isPlayer))
	local name = hovering and FR.SafeUnitName("mouseover") or nil   -- nil when hidden (instances)
	lastHover = name
	if not name then
		-- The mouse left the creature (to an action bar, say): keep what is loaded, as long as
		-- the creature still belongs to the step.
		if markName and not markerByName[markName:lower()] then markName = nil; SetMarkBody(MarkText(nil)) end
		return
	end
	local info = markerByName[name:lower()]
	if not info then
		-- The guides have typos in creature names ("Breton" for "Brenton"): a creature of the step
		-- under the cursor whose name differs by one or two letters is the one meant. Remember it.
		local low, best, bestD = name:lower(), nil, 99
		if #low >= 6 then
			for _, cand in pairs(markerByName) do
				local c = cand.name:lower()
				if c:sub(1, 1) == low:sub(1, 1) then
					local d = EditDistance(low, c)
					if d < bestD then best, bestD = cand, d end
				end
			end
		end
		if best and bestD <= math.max(1, math.floor(#low * 0.12)) and ForeverRouteDB and best.raw
			and not (InCombatLockdown and InCombatLockdown()) then
			ForeverRouteDB.npcAlias = ForeverRouteDB.npcAlias or {}
			ForeverRouteDB.npcAlias[best.raw] = name
			FR:Print(string.format(FR.L["Creature name corrected: %s is called %s in the game."], best.name, name))
			if C_Timer and C_Timer.After then C_Timer.After(0, function() FR:UpdateActiveFrames() end) end
			info = best
		end
	end
	if info and info.enemy then
		local okDead, dead = pcall(UnitIsDead, "mouseover")
		if okDead and FR.Plain(dead) == true then info = nil end
	end
	markName = info and name:lower() or nil
	SetMarkBody(MarkText(info))
	if info and not markHinted and FR:Get("markTargets") then
		markHinted = true
		if GetBindingKey and not GetBindingKey("CLICK ForeverRouteMarkButton:LeftButton") then
			FR:Print(FR.L["To mark creatures of the step, bind a key (Key Bindings > AddOns > ForeverRoute) or put the macro FRMark on an action bar. Details: /fr macro"])
		end
	end
end

-- /fr macro: what the macros contain (for when they do not do what they should).
function FR:PrintMacroInfo()
	local function show(name)
		local exists = GetMacroInfo and GetMacroInfo(name)
		self:Print(name .. ": " .. (exists and (select(3, GetMacroInfo(name)) or "?") or FR.L["does not exist"]))
	end
	self:Print(string.format(FR.L["Macros in use: %d of 120"], (GetNumMacros and GetNumMacros() or 0)))
	show(MACRO_NAME)
	show(MARK_MACRO)
	self:Print("FRMarkButton: " .. tostring(markBody or "-"):gsub("\n", " | "))
	-- Language check: the names the macros use must be exactly the ones the game shows.
	local names = {}
	for k, info in pairs(markerByName) do
		if not names[info.name] then names[info.name] = true end
	end
	local list = {}
	for n in pairs(names) do list[#list + 1] = n end
	table.sort(list)
	self:Print(FR.L["Creatures of this step (as the macros call them):"] .. " " .. (#list > 0 and table.concat(list, ", ") or "-"))
	self:Print(FR.L["Creature last under the cursor:"] .. " " .. tostring(lastHover or "-"))
	self:Print("Client: " .. tostring(GetLocale and GetLocale()) .. ", " .. FR.L["Creature names known:"] .. " "
		.. tostring(FR.npcNames ~= nil))
end

local function Rows(n) return math.ceil(n / PER_ROW) end
local function RowWidth(n) return n == 0 and 0 or (math.min(n, PER_ROW) * STEP - (STEP - SIZE)) end

-- groups = { list1, list2 }: drawn as separate row blocks, top to bottom.
local function Fill(bar, groups, setup)
	local used, y, width = 0, -TOP, 0
	for g, list in ipairs(groups) do
		if #list > 0 then
			if used > 0 then y = y - GROUP_GAP end
			for n, entry in ipairs(list) do
				used = used + 1
				local b = GetButton(bar, used)
				b:SetSize(SIZE, SIZE)
				local col, row = (n - 1) % PER_ROW, math.floor((n - 1) / PER_ROW)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", bar, "TOPLEFT", SIDE + col * STEP, y - row * STEP)
				setup(b, entry)
				b:Show()
			end
			y = y - Rows(#list) * STEP + (STEP - SIZE)
			width = math.max(width, RowWidth(#list))
		end
	end
	for i = used + 1, #bar.buttons do
		local b = bar.buttons[i]
		b.targetName = false
		AttachFace(b)
		b:Hide()
	end
	if used == 0 then bar:Hide() return end
	local titleW = math.ceil(bar.title:GetStringWidth() or 40) + 2
	bar:SetWidth(math.max(SIDE * 2 + titleW, SIDE * 2 + width))
	bar:SetHeight(-y + BOTTOM)
	bar:Show()
end

local pending = false

function FR:UpdateActiveFrames()
	if InCombatLockdown and InCombatLockdown() then pending = true return end
	pending = false
	Metrics()
	Restyle()
	local items, friends, enemies, seenItem, seenName = {}, {}, {}, {}, {}
	local macros, seenMacro = {}, {}
	if self.current and self.frame and self.frame:IsShown() then
		for _, step in ipairs(self:GetActiveSteps()) do
			-- A finished step you went back to (step history, "previous step") shows its creatures too.
			if not self:IsStepFinished(step) or self.pinnedStep == step.idx then
				-- The quest objectives of the step: the name plates read "2/8" from them (Plates.lua).
				local stepObjs = {}
				for _, e in ipairs(step.elements) do
					if e.qid and e.obj and (e.kind == "complete" or e.kind == "collect") then
						stepObjs[#stepObjs + 1] = { qid = e.qid, obj = e.obj, hint = e.hint }
					end
				end
				for _, e in ipairs(step.elements) do
					-- ".macro": a button that runs the macro text.
					if e.macro and not seenMacro[e.macro.name] then
						seenMacro[e.macro.name] = true
						macros[#macros + 1] = e.macro
					end
					local list = {}
					if e.kind == "use" and e.items then
						for _, id in ipairs(e.items) do list[#list + 1] = id end
					end
					if e.qid and (e.kind == "complete" or e.kind == "collect") and not self:ElementState(step, e) then
						list[#list + 1] = QuestSpecialItem(e.qid)
					end
					for _, id in ipairs(list) do
						if id and not seenItem[id] and FR.ItemCount(id) > 0 then
							seenItem[id] = true
							items[#items + 1] = id
						end
					end
					for _, raw in ipairs(e.targets or {}) do
						local name = FR.NpcName(raw)
						if not seenName[name] then
							seenName[name] = true
							-- ".unitscan" creatures are enemies too, but get the moon (RestedXP).
							local entry = {
								name = name, raw = raw, enemy = (e.kind == "mob" or e.kind == "unitscan"),
								unitscan = (e.kind == "unitscan") or nil,
								npcId = e.npcIds and e.npcIds[raw] or nil,
								objs = stepObjs,
							}
							if entry.enemy then enemies[#enemies + 1] = entry else friends[#friends + 1] = entry end
						end
					end
				end
			end
		end
	end
	-- The name plate icons (Nameplates.lua) do not depend on the target buttons being shown or on
	-- how many fit on the bar: they get every creature of the step, with the same icons.
	do
		local plateNames, plateIds, mobs = {}, {}, 0
		for n, entry in ipairs(friends) do entry.marker = ((n - 1) % 4) + 1 end
		for _, entry in ipairs(enemies) do
			if entry.unitscan then
				entry.marker = 5
			else
				mobs = mobs + 1
				entry.marker = 8 - ((mobs - 1) % 3)
			end
		end
		for _, list in ipairs({ friends, enemies }) do
			for _, entry in ipairs(list) do
				local info = { name = entry.name, raw = entry.raw, marker = entry.marker, enemy = entry.enemy, npcId = entry.npcId,
					objs = entry.objs }
				plateNames[entry.name:lower()] = info
				if entry.raw then plateNames[entry.raw:lower()] = plateNames[entry.raw:lower()] or info end
				if entry.npcId then plateIds[entry.npcId] = info end
			end
		end
		if self.SetNameplateTargets then self:SetNameplateTargets(plateNames, plateIds) end
	end
	if not self:Get("showActiveItems") then items, macros = {}, {} end
	while #macros > 6 do table.remove(macros) end
	if not self:Get("showActiveTargets") then friends, enemies = {}, {} end
	while #items > MAX do table.remove(items) end
	while #enemies + #friends > MAX do
		if #enemies > #friends then table.remove(enemies) else table.remove(friends) end
	end
	-- Icons as RestedXP hands them out: enemies skull, cross, square (8, 7, 6),
	-- NPCs star, circle, diamond, triangle (1 to 4).
	-- ".unitscan" creatures get the moon (5).
	local mobs = 0
	for _, entry in ipairs(enemies) do
		if entry.unitscan then
			entry.marker = 5
		else
			mobs = mobs + 1
			entry.marker = 8 - ((mobs - 1) % 3)
		end
	end
	for n, entry in ipairs(friends) do entry.marker = ((n - 1) % 4) + 1 end
	UpdateMacro(enemies, friends)
	markerByName = {}
	local markerById = {}
	for _, list in ipairs({ friends, enemies }) do
		for _, entry in ipairs(list) do
			local info = { name = entry.name, raw = entry.raw, marker = entry.marker, enemy = entry.enemy, npcId = entry.npcId }
			markerByName[entry.name:lower()] = info
			if entry.raw then markerByName[entry.raw:lower()] = markerByName[entry.raw:lower()] or info end
			if entry.npcId then markerById[entry.npcId] = info end
		end
	end
	if self:Get("markTargets") then
		if self:Get("targetMacro") then CreateMarkMacro() end
		self:OnMouseoverMark()
	else
		markerByName = {}
		SetMarkBody(MarkText(nil))
	end
	wantedNames = seenName
	Fill(itemsBar, { items, macros }, SetupItem)
	-- Enemies on top, NPCs to talk to below (RestedXP's order).
	Fill(targetsBar, { enemies, friends }, SetupTarget)
	Remember("target")
	Remember("mouseover")
	ScanNamePlates()
end

-- Pixel scale of the bars (again after a change of the game's UI scale).
-- (The bars hold secure buttons: they must not be changed during combat.)
function FR:ApplyActiveScale()
	if InCombatLockdown and InCombatLockdown() then self.scalePending = true return end
	self.scalePending = false
	for _, bar in ipairs({ itemsBar, targetsBar }) do bar:SetScale(FR.PixelScale(1)) end
end

function FR:RestoreActivePositions()
	local db = ForeverRouteDB
	if not db then return end
	-- Until 2.3 the bars used the game's UI units, now they use screen pixels:
	-- convert saved positions once, and start with a smaller button size
	-- (they were a bit large).
	if not db.barUnits then
		db.barUnits = true
		local k = FR.UIPixels()
		for _, bar in ipairs({ itemsBar, targetsBar }) do
			local pos = db["pos" .. bar.key]
			if pos then pos[3], pos[4] = math.floor((pos[3] or 0) * k + 0.5), math.floor((pos[4] or 0) * k + 0.5) end
		end
		db.barSize = math.max(22, math.min(48, math.floor(25 * k * 0.85 + 0.5)))
	end
	self:ApplyActiveScale()
	for _, bar in ipairs({ itemsBar, targetsBar }) do
		local pos = db["pos" .. bar.key]
		if pos then
			bar:ClearAllPoints()
			bar:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
		end
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED")
pcall(ev.RegisterEvent, ev, "UPDATE_MOUSEOVER_UNIT")
pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_ADDED")
ev:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_REGEN_ENABLED" then
		if FR.scalePending then FR:ApplyActiveScale() end
		if pending then FR:UpdateActiveFrames() end
	elseif event == "PLAYER_TARGET_CHANGED" then
		Remember("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Remember("mouseover")
		FR:OnMouseoverMark()
	elseif event == "NAME_PLATE_UNIT_ADDED" and unit then
		Remember(unit)
	end
end)
