-- The creatures the current step is about, and their small icons hung on the game's name plate.
--
-- RestedXP puts real raid icons on these creatures (SetRaidTarget). WoW Forever
-- does not let addons do that, so this draws the same icons itself (and on the
-- target frame while the plate is off). Nothing here touches the creature or the
-- game's raid icons. With "Custom plates" on, Plates.lua draws the icons on its
-- own plates (FR.PlateDrawsIcon) and this is only the fallback for the game's plate.
--   friendly NPC (.target)    star, circle, diamond, triangle
--   enemy (.mob)              skull, cross, square
--   rare / scan (.unitscan)   moon
-- The creatures come from FR:UpdateActiveFrames (ActiveFrames.lua), which hands
-- over the same lists the target buttons use.
--
-- Names and GUIDs of units can be "secret values" on this client: reading them
-- is allowed but comparing or indexing with them raises an error. So every unit
-- value goes through Plain() first, inside pcall, and a unit whose values are
-- secret simply gets no icon.
local _, ns = ...
local FR = ns.FR

local ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"   -- 4 x 4 atlas, icons 1-8 in the top rows
local BASE_SIZE = 20
local MAX_ICONS = 40

local byName, byId = {}, {}   -- lower-case name / NPC id -> { marker, enemy, ... } of the step's creatures
local shown = {}              -- [unit token] = icon frame
local pool = {}               -- icon frames that are free
local targetIcon              -- the icon on the target frame
local count = 0

-- Unit values --------------------------------------------------------------------------------

local Plain = FR.Plain   -- nil for a secret value (Core.lua)

-- The step entry (from the lists above) that this unit is, or nil. The NPC id in
-- the GUID is exact; the name is the fallback for guides that only give a name.
local function Entry(unit)
	local kind, id = FR.UnitNpcId(unit)
	if kind then
		if kind ~= "Creature" and kind ~= "Vehicle" then return nil end   -- players, pets, objects
		local info = byId[id or 0]
		if info then return info end
	end
	local name = FR.SafeUnitName(unit)
	if name then return byName[name:lower()] end
	return nil
end
FR.NameplateEntry = Entry

local function IsDead(unit)
	local ok, dead = pcall(UnitIsDead, unit)
	return ok and Plain(dead) == true
end

local function Skip()
	if not FR:Get("nameplateIcons") then return true end
	-- Questie draws nothing in instances on Forever either: names are restricted there.
	return FR.InInstance()
end

-- Texture rectangle of a raid icon (1-8) in the atlas, for Plates.lua.
function FR.MarkerTexCoord(marker)
	local col, row = (marker - 1) % 4, math.floor((marker - 1) / 4)
	return col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25
end
FR.MARKER_ATLAS = ICONS

-- Icon frames ----------------------------------------------------------------------------------

local function Cut(texture, marker)
	local col, row = (marker - 1) % 4, math.floor((marker - 1) / 4)
	texture:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
end

local function NewFrame()
	local f = table.remove(pool)
	if f then return f end
	if count >= MAX_ICONS then return nil end
	count = count + 1
	f = CreateFrame("Frame", nil, UIParent)
	f:SetFrameStrata("HIGH")
	f:SetFrameLevel(10)
	f:EnableMouse(false)
	f.icon = f:CreateTexture(nil, "ARTWORK")   -- made once, the frame is reused
	f.icon:SetAllPoints()
	f.icon:SetTexture(ICONS)
	return f
end

local function Release(unit)
	local f = shown[unit]
	if not f then return end
	shown[unit] = nil
	f:Hide()
	f:ClearAllPoints()
	f:SetParent(UIParent)
	pool[#pool + 1] = f
end

local function PlateFor(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate then return nil end
	if plate.IsForbidden and plate:IsForbidden() then return nil end
	return plate
end

-- A text of a plate that is really there to anchor to.
local function ValidText(fs)
	return fs ~= nil and fs.IsShown ~= nil and fs:IsShown() and fs.GetObjectType ~= nil and fs:GetObjectType() == "FontString"
end

-- Shows, moves or removes the icon of one name plate unit.
local function Update(unit)
	if type(unit) ~= "string" then return end
	local info = not Skip() and Entry(unit) or nil
	if info and info.enemy and IsDead(unit) then info = nil end
	-- ForeverRoute's own plate (Plates.lua) draws the icon itself: no second one.
	if info and FR.PlateDrawsIcon and FR.PlateDrawsIcon(unit) then info = nil end
	local plate = info and PlateFor(unit)
	if not plate then Release(unit) return end

	-- Beside the game's name text, else beside the plate. The icon hangs on the game's UnitFrame, so it
	-- scales and fades together with the name (the game scales its plates with the distance).
	local uf = plate.UnitFrame
	local nameText = uf and (uf.name or uf.Name)
	local anchor = ValidText(nameText) and nameText or plate

	local f = shown[unit] or NewFrame()
	if not f then return end
	shown[unit] = f
	local size = math.floor(BASE_SIZE * (FR:Get("nameplateScale") or 1) + 0.5)
	f:SetParent((uf and uf.GetFrameLevel and not uf.FRHide) and uf or plate)
	f:SetFrameStrata("HIGH")
	f:SetFrameLevel(10)
	f:SetSize(size, size)
	f:ClearAllPoints()
	f:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
	Cut(f.icon, info.marker)
	f:Show()
end

local function UpdateAll()
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		if ok and type(plates) == "table" then
			for _, plate in ipairs(plates) do
				local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
				if type(unit) == "string" then Update(unit) end
			end
		end
	end
	-- Icons whose plate is gone (a plate unit can disappear without an event while loading).
	for unit in pairs(shown) do
		if not PlateFor(unit) then Release(unit) end
	end
end

-- Target frame (while the target has no name plate) -------------------------------------------

local function UpdateTarget()
	local info
	if not Skip() and UnitExists("target") and not PlateFor("target") then
		info = Entry("target")
		if info and info.enemy and IsDead("target") then info = nil end
	end
	if not info then
		if targetIcon then targetIcon:Hide() end
		return
	end
	if not targetIcon then
		targetIcon = CreateFrame("Frame", nil, TargetFrame or UIParent)
		targetIcon:SetFrameStrata("MEDIUM")
		targetIcon:SetFrameLevel(11)
		targetIcon:EnableMouse(false)
		targetIcon.icon = targetIcon:CreateTexture(nil, "ARTWORK")
		targetIcon.icon:SetAllPoints()
		targetIcon.icon:SetTexture(ICONS)
	end
	local size = math.floor(BASE_SIZE * 1.4 * (FR:Get("nameplateScale") or 1) + 0.5)
	targetIcon:SetSize(size, size)
	targetIcon:ClearAllPoints()
	if TargetFrame then
		-- Where Questie puts its target icon: beside the portrait, top right.
		targetIcon:SetParent(TargetFrame)
		targetIcon:SetPoint("RIGHT", TargetFrame, "RIGHT", -30, 25)
	else
		targetIcon:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	end
	Cut(targetIcon.icon, info.marker)
	targetIcon:Show()
end

-- Interface for ActiveFrames.lua and the settings ---------------------------------------------

-- Name plate switches of the game ---------------------------------------------------------------
-- The icons hang on the game's name plates, and those are off by default (V: enemies, Shift+V:
-- friendly ones). Which setting is needed depends on whether the step has enemies or NPCs.

local function GetCVarValue(name)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	if not get then return nil end
	local ok, v = pcall(get, name)
	if not ok then return nil end
	return Plain(v)
end

-- The settings that show friendly plates (Shift+V). Which of them this client has, and which one
-- decides for NPCs, differs between game versions, so all that exist are looked at and switched.
local FRIEND_CVARS = { "nameplateShowFriends", "nameplateShowFriendlyNPCs", "nameplateShowFriendlyNpcs" }

local function IsOn(v) return v == "1" or v == 1 or v == true end

local function FriendlyCVars()
	local list = {}
	for _, name in ipairs(FRIEND_CVARS) do
		if GetCVarValue(name) ~= nil then list[#list + 1] = name end
	end
	return list
end

local function PlatesOn(enemy)
	if enemy then return IsOn(GetCVarValue("nameplateShowEnemies")) end
	local list = FriendlyCVars()
	if #list == 0 then return true end   -- no such setting: nothing to switch
	for _, name in ipairs(list) do
		if not IsOn(GetCVarValue(name)) then return false end
	end
	return true
end

local function CountStep()
	local enemies, friends, seen = 0, 0, {}
	for _, info in pairs(byName) do
		if not seen[info] then
			seen[info] = true
			if info.enemy then enemies = enemies + 1 else friends = friends + 1 end
		end
	end
	return enemies, friends
end

-- Turns the game's name plates on (not in combat): enemies and friendly NPCs. ForeverRoute draws both
-- (Plates.lua), but only for plates the game creates. Used by the settings and by /fr plates on.
function FR:EnableNameplates()
	if InCombatLockdown and InCombatLockdown() then
		self:Print(FR.L["Not in combat."])
		return
	end
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if not set then return end
	local changed = {}
	local names = { "nameplateShowEnemies" }
	for _, name in ipairs(FriendlyCVars()) do names[#names + 1] = name end
	for _, name in ipairs(names) do
		if not IsOn(GetCVarValue(name)) and pcall(set, name, "1") then changed[#changed + 1] = name end
	end
	self:Print(#changed > 0 and (FR.L["Name plates turned on:"] .. " " .. table.concat(changed, ", "))
		or FR.L["The name plates for enemies and friendly NPCs were already on."])
	self:RefreshNameplateIcons()
end

-- Once per session, when the plates are off: say what to do. (The game's plates are never switched on
-- behind your back: a plate switch you turn off yourself stays off.)
local hinted = false
local function HintPlates()
	if hinted or not (FR:Get("customPlates") or FR:Get("nameplateIcons")) then return end
	if not PlatesOn(true) or not PlatesOn(false) then
		hinted = true
		FR:Print(FR.L["ForeverRoute's name plates need the game's name plates (V: enemies, Shift+V: friendly NPCs). Type /fr plates on to turn them on. Without them the step icon shows on the target frame."])
	end
end

-- /fr plates: what the icons see (for when no icon shows up).
function FR:PrintNameplateStatus()
	local function yn(v) return v and FR.L["yes"] or FR.L["no"] end
	local enemies, friends = CountStep()
	self:Print(FR.L["Name plate icons:"] .. " " .. (FR:Get("nameplateIcons") and FR.L["on"] or FR.L["off"])
		.. " | " .. FR.L["guide window shown:"] .. " " .. yn(self.frame and self.frame:IsShown())
		.. " | " .. FR.L["in an instance:"] .. " " .. yn(FR.InInstance()))
	if self.PlatesStatus then self:Print(self:PlatesStatus()) end
	self:Print(string.format(FR.L["Creatures of this step: %d enemies, %d friendly."], enemies, friends))
	self:Print(string.format(FR.L["Game name plates: enemies %s, friendly NPCs %s."],
		yn(PlatesOn(true)), yn(PlatesOn(false))))
	local values = { "nameplateShowEnemies=" .. tostring(GetCVarValue("nameplateShowEnemies")) }
	for _, name in ipairs(FriendlyCVars()) do values[#values + 1] = name .. "=" .. tostring(GetCVarValue(name)) end
	self:Print("  " .. table.concat(values, ", "))
	if (friends > 0 and not PlatesOn(false)) or (enemies > 0 and not PlatesOn(true)) then
		self:Print(FR.L["The plates this step needs are off. Type /fr plates on to turn them on."])
	end
	local plates = {}
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local okp, list = pcall(C_NamePlate.GetNamePlates)
		if okp and type(list) == "table" then plates = list end
	end
	local nShown = 0
	for _ in pairs(shown) do nShown = nShown + 1 end
	self:Print(string.format(FR.L["Name plates in view: %d, icons shown: %d."], #plates, nShown))
	for i, plate in ipairs(plates) do
		if i > 8 then break end
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		local okg, guid = pcall(UnitGUID, unit or "none")
		local okn, name = pcall(UnitName, unit or "none")
		local gs = okg and guid ~= nil and issecretvalue and issecretvalue(guid)
		local ns = okn and name ~= nil and issecretvalue and issecretvalue(name)
		local info = type(unit) == "string" and Entry(unit) or nil
		local own = type(unit) == "string" and FR.PlateDrawsIcon and FR.PlateDrawsIcon(unit)
		self:Print(string.format("  %s: %s%s -> %s%s | ForeverRoute plate: %s", tostring(unit),
			ns and FR.L["(name hidden by the game)"] or tostring(okn and name or "?"),
			gs and (" " .. FR.L["(GUID hidden by the game)"]) or "",
			info and (FR.L["in the step"] .. " (" .. info.marker .. ")") or FR.L["not in the step"],
			(type(unit) == "string" and shown[unit]) and (", " .. FR.L["icon shown"]) or "",
			own and FR.L["yes"] or FR.L["no"]))
	end
end

-- The creatures of the current step: markerByName[name:lower()] and markerById[npcId].
function FR:SetNameplateTargets(names, ids)
	byName, byId = names or {}, ids or {}
	if self.RefreshPlates then self:RefreshPlates() end   -- first: it decides who draws the icons
	UpdateAll()
	UpdateTarget()
	HintPlates()
end

-- Setting changed (on / off, size): draw everything again.
function FR:RefreshNameplateIcons()
	if self.RefreshPlates then self:RefreshPlates() end
	for unit in pairs(shown) do Release(unit) end
	UpdateAll()
	UpdateTarget()
end

-- Events ------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_ADDED")
pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_REMOVED")
pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED")
pcall(ev.RegisterEvent, ev, "UNIT_FLAGS")             -- a creature died
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")  -- instance in / out
-- A creature that died keeps its name plate for a while and no event says so reliably:
-- look at the shown icons once a second.
if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(1, function()
		for unit in pairs(shown) do Update(unit) end
	end)
end

ev:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		Update(unit)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		-- By the token: the creature's own values may be unreadable by now.
		if type(unit) == "string" then Release(unit) end
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateTarget()
	elseif event == "UNIT_FLAGS" then
		if type(unit) == "string" and shown[unit] then Update(unit) end
	elseif event == "PLAYER_ENTERING_WORLD" then
		FR:RefreshNameplateIcons()
	end
end)
