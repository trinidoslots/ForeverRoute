-- Waypoints: resolves zone names to map IDs, sets a map pin, drives the
-- arrow and completes travel goals when the player arrives.
local _, ns = ...
local FR = ns.FR

-- Guides use English zone names. This table works on every client language;
-- the map API fills in anything missing (custom Forever zones).
local ZONES = {
	["Durotar"] = 1411, ["Mulgore"] = 1412, ["The Barrens"] = 1413, ["Kalimdor"] = 1414,
	["Eastern Kingdoms"] = 1415, ["Alterac Mountains"] = 1416, ["Arathi Highlands"] = 1417,
	["Badlands"] = 1418, ["Blasted Lands"] = 1419, ["Tirisfal Glades"] = 1420,
	["Silverpine Forest"] = 1421, ["Western Plaguelands"] = 1422, ["Eastern Plaguelands"] = 1423,
	["Hillsbrad Foothills"] = 1424, ["The Hinterlands"] = 1425, ["Dun Morogh"] = 1426,
	["Searing Gorge"] = 1427, ["Burning Steppes"] = 1428, ["Elwynn Forest"] = 1429,
	["Deadwind Pass"] = 1430, ["Duskwood"] = 1431, ["Loch Modan"] = 1432,
	["Redridge Mountains"] = 1433, ["Stranglethorn Vale"] = 1434, ["Swamp of Sorrows"] = 1435,
	["Westfall"] = 1436, ["Wetlands"] = 1437, ["Teldrassil"] = 1438, ["Darkshore"] = 1439,
	["Ashenvale"] = 1440, ["Thousand Needles"] = 1441, ["Stonetalon Mountains"] = 1442,
	["Desolace"] = 1443, ["Feralas"] = 1444, ["Dustwallow Marsh"] = 1445, ["Tanaris"] = 1446,
	["Azshara"] = 1447, ["Felwood"] = 1448, ["Un'Goro Crater"] = 1449, ["Moonglade"] = 1450,
	["Silithus"] = 1451, ["Winterspring"] = 1452, ["Stormwind City"] = 1453, ["Orgrimmar"] = 1454,
	["Ironforge"] = 1455, ["Thunder Bluff"] = 1456, ["Darnassus"] = 1457, ["Undercity"] = 1458,
	["Alterac Valley"] = 1459, ["Warsong Gulch"] = 1460, ["Arathi Basin"] = 1461,
}

local apiZones

local function BuildZoneTable()
	apiZones = {}
	if not (C_Map and C_Map.GetMapChildrenInfo) then return end
	-- 947 = Azeroth, 1414 = Kalimdor, 1415 = Eastern Kingdoms.
	for _, root in ipairs({ 947, 1414, 1415 }) do
		local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
		if ok and children then
			for _, info in ipairs(children) do
				if info.name and not apiZones[info.name] then
					apiZones[info.name] = info.mapID
				end
			end
		end
	end
end

function FR:GetZoneID(name)
	if not name then return nil end
	if ZONES[name] then return ZONES[name] end
	if not apiZones then BuildZoneTable() end
	return apiZones[name]
end

-- Active waypoint with world coordinates. The map and minimap show the
-- guide's own step numbers (MapPins.lua); no TomTom or game waypoint is set.
local current

function FR:ClearWaypoint()
	current = nil
	if FR.arrow then FR.arrow:Hide() end
end

-- Fills in map coordinates (0-100) and world position of a guide waypoint.
-- RestedXP world coordinates are written "west, north"; the client's
-- UnitPosition and map vectors use "north, west".
function FR:ResolveWaypoint(wp)
	if wp.resolved then return wp.ok end
	wp.resolved = true
	local vec = CreateVector2D
	if wp.world then
		wp.north, wp.west, wp.instance = wp.worldY, wp.worldX, wp.cont
		if C_Map and C_Map.GetMapPosFromWorldPos and vec then
			local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, wp.cont, vec(wp.north, wp.west), wp.mapID)
			if ok and pos then
				local x, y = pos:GetXY()
				wp.x, wp.y = x * 100, y * 100
			end
		end
	elseif C_Map and C_Map.GetWorldPosFromMapPos and vec then
		local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, wp.mapID, vec(wp.x / 100, wp.y / 100))
		if ok and pos then
			wp.instance = cont
			wp.north, wp.west = pos:GetXY()
		end
	end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(wp.mapID)
	wp.zone = info and info.name or ("Map " .. tostring(wp.mapID))
	wp.ok = (wp.north ~= nil) or (wp.x ~= nil)
	return wp.ok
end

-- step / element are passed so arrival can complete the element.
function FR:SetWaypoint(wp, title, step, element)
	if not wp then self:ClearWaypoint() return end
	if current and current.wp == wp then
		current.step, current.goal, current.title = step, element, title
		return
	end
	self:ClearWaypoint()
	if not self:ResolveWaypoint(wp) then return end
	current = { wp = wp, zone = wp.zone, x = wp.x or 0, y = wp.y or 0, mapID = wp.mapID, title = title,
		radius = wp.radius, step = step, goal = element, cont = wp.instance, wx = wp.north, wy = wp.west }
	self:UpdateArrowVisibility()
end

-- Is this plain pin (a ".goto" without radius) still worth pointing at? It is tied to the last
-- objective line before it (Parser.lua, `parent`): once that line is done - the quest handed in or
-- accepted, the item collected - the pin is not needed any more (RestedXP does the same). A pin with
-- no parent, or one whose parent cannot be ticked, stays until the step is done.
function FR:PinWanted(step, e)
	local parent = e.parent and step.elements[e.parent]
	if not parent then return true end
	local done, completable = self:ElementState(step, parent)
	return not (completable and done)
end

-- Picks the waypoint of the active steps (side steps first, the current step last):
--   1. one the player chose by hand (wpOverride),
--   2. the first path point / arrival with a radius that has not been reached,
--   3. the first plain pin that is still wanted, in the order the guide lists them,
--   4. when every pin is done: the last plain pin of the current step.
-- Returns the element and its step.
function FR:ChooseWaypoint(active)
	local override = self.wpOverride
	if override then
		for _, s in ipairs(active) do
			for _, e in ipairs(s.elements) do
				if e == override then return e, s end
			end
		end
		self.wpOverride = nil
	end
	for _, s in ipairs(active) do
		for _, e in ipairs(s.elements) do
			if e.kind == "goto" and e.wp.radius and not self:IsMarked(s, e) then return e, s end
		end
	end
	for _, s in ipairs(active) do
		for _, e in ipairs(s.elements) do
			if e.kind == "goto" and not e.wp.radius and self:PinWanted(s, e) then return e, s end
		end
	end
	for n = #active, 1, -1 do
		local s, pin = active[n], nil
		for _, e in ipairs(s.elements) do
			if e.kind == "goto" and not e.wp.radius then pin = e end
		end
		if pin then return pin, s end
	end
end

-- Distance in yards and bearing (radians, counter-clockwise from north) to
-- the waypoint, or nil when it is on another continent / unknown.
-- The player's world position as RestedXP gets it: through HereBeDragons, which matches the
-- instance ID UnitPosition reports with the one of the map (it learns the difference at run time,
-- e.g. for cities whose instance ID is not the continent's). Returns north, west, instance.
local function PlayerWorld()
	-- Inside instances the position is nil or secret: then there is no position (the arrow hides).
	local Plain = FR.Plain
	local HBD = LibStub and LibStub("ForeverRoute-HBD-2.0", true)
	if HBD and HBD.GetPlayerWorldPosition then
		local ok, x, y, instance = pcall(HBD.GetPlayerWorldPosition, HBD)
		if ok then
			x, y, instance = Plain(x), Plain(y), Plain(instance)
			if x and y then return y, x, instance end
			return nil, nil, instance
		end
	end
	local ok, py, px, _, instance = pcall(UnitPosition, "player")
	if not ok then return nil, nil, nil end
	py, px, instance = Plain(py), Plain(px), Plain(instance)
	if not (py and px) then return nil, nil, instance end
	return py, px, instance
end
FR.PlayerWorld = PlayerWorld

function FR:GetWaypointVector(info)
	info = info or current
	if not info or not info.wx then return nil end
	local py, px, instance = PlayerWorld()
	-- RestedXP: wrong continent only when the instance is known (-1 = unknown) and differs.
	if not py or (info.cont and instance and instance ~= -1 and instance ~= info.cont) then return nil end
	-- World axes: first value = north, second = west (same order for both APIs).
	local dNorth, dWest = info.wx - py, info.wy - px
	return math.sqrt(dNorth * dNorth + dWest * dWest), math.atan2(dWest, dNorth)
end

function FR:GetWaypointInfo() return current end

-- /fr where: everything the arrival and zone checks look at (for steps that do not complete).
function FR:PrintWhere()
	local okPos, ry, rx, _, rinst = pcall(UnitPosition, "player")
	if not okPos then ry, rx, rinst = nil, nil, nil end
	local py, px, inst = PlayerWorld()
	ry, rx = FR.Plain(ry), FR.Plain(rx)
	self:Print(string.format("UnitPosition north=%s west=%s instance=%s (HereBeDragons: instance %s)",
		tostring(ry and math.floor(ry * 10) / 10), tostring(rx and math.floor(rx * 10) / 10), tostring(FR.Plain(rinst)), tostring(inst)))
	local map = FR.Plain(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	local okInfo, info = false, nil
	if map and C_Map.GetMapInfo then okInfo, info = pcall(C_Map.GetMapInfo, map) end
	if not okInfo then info = nil end
	self:Print(string.format("position north=%s west=%s instance=%s", tostring(py and math.floor(py * 10) / 10),
		tostring(px and math.floor(px * 10) / 10), tostring(inst)))
	self:Print(string.format("map=%s (%s) parent=%s zone=%s / %s subzone=%s", tostring(map),
		tostring(info and FR.Plain(info.name)), tostring(info and FR.Plain(info.parentMapID)),
		FR.SafeText(GetRealZoneText), FR.SafeText(GetZoneText), FR.SafeText(GetSubZoneText)))
	local c = current
	if not c then self:Print("no waypoint active") else
		local dist = self:GetWaypointVector()
		self:Print(string.format("waypoint: %s | north=%s west=%s continent=%s radius=%s distance=%s goal=%s arrive=%s autoArrive=%s",
			tostring(c.title), tostring(c.wx and math.floor(c.wx * 10) / 10), tostring(c.wy and math.floor(c.wy * 10) / 10),
			tostring(c.cont), tostring(c.radius), tostring(dist and math.floor(dist)), tostring(c.goal and c.goal.kind),
			tostring(c.goal and c.goal.arrive), tostring(self:Get("autoArrive"))))
	end
	local step = self:GetStep()
	if step and self.InZone then
		for _, e in ipairs(step.elements) do
			if e.kind == "zone" then
				self:Print(string.format("zone goal: map %s -> in zone: %s", tostring(e.mapID), tostring(self.InZone(e.mapID))))
			end
		end
	end
end

-- Waypoint bar -------------------------------------------------------------------
-- A small box instead of a big arrow:  [24] Novice Elreth   ^ 120 yd  x
-- step number, who or what to go to, a turning chevron for the direction,
-- the distance and a button to hide it until the next waypoint.

-- Waypoint.lua loads before UI.lua: the labels start with the game font and
-- get the addon's font objects (FR.fontArrow*) on the first layout.
local FONT = "Fonts\\ARIALN.TTF"
local BAR_H, PAD, TITLE_MAX = 24, 6, 240
local dismissed   -- waypoint hidden with the x button
local view, lastView   -- what the bar shows right now: the corpse or the guide waypoint

local arrow = CreateFrame("Frame", "ForeverRouteArrow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
FR.arrow = arrow
arrow:SetSize(160, BAR_H)
arrow:SetPoint("TOP", UIParent, "TOP", 0, -120)
arrow:SetMovable(true)
arrow:SetClampedToScreen(true)
arrow:EnableMouse(true)
arrow:RegisterForDrag("LeftButton")
arrow:SetScript("OnDragStart", function(self) if not FR:Get("locked") then self:StartMoving() end end)
arrow:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint()
	if not p then return end
	x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
	self:ClearAllPoints()
	self:SetPoint(p, UIParent, rp, x, y)
	if ForeverRouteDB then ForeverRouteDB.arrowPos = { p, rp, x, y } end
end)
arrow:Hide()
arrow.shownDist, arrow.shownAngle, arrow.skinned = false, false, false

local function Label(size, r, g, b, bold)
	local fs = arrow:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, size, "")
	fs.fontKey = (size < 12 and "fontArrowSmall") or (bold and "fontArrowBold") or "fontArrow"
	fs:SetShadowOffset(0, 0)
	fs:SetTextColor(r, g, b)
	fs:SetWordWrap(false)
	return fs
end

-- Step number on a tinted badge.
arrow.badge = arrow:CreateTexture(nil, "ARTWORK")
arrow.badge:SetTexture("Interface\\Buttons\\WHITE8X8")
arrow.badge:SetPoint("LEFT", PAD - 1, 0)
arrow.badge:SetHeight(16)
arrow.step = Label(11, 1, 1, 1, true)
arrow.step:SetPoint("CENTER", arrow.badge, "CENTER", 0, 0)

arrow.title = Label(12, 0.93, 0.94, 0.96)
arrow.title:SetPoint("LEFT", arrow.badge, "RIGHT", 7, 0)
arrow.title:SetJustifyH("LEFT")

-- Hide button.
arrow.close = CreateFrame("Button", nil, arrow)
arrow.close:SetSize(16, BAR_H)
arrow.close:SetPoint("RIGHT", -3, 0)
arrow.close.text = arrow.close:CreateFontString(nil, "OVERLAY")
arrow.close.text:SetFont(FONT, 13, "")
arrow.close.text:SetPoint("CENTER", 0, 1)
arrow.close.text:SetText("\195\151")   -- multiplication sign
arrow.close.text:SetTextColor(0.55, 0.58, 0.65)
arrow.close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
arrow.close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.55, 0.58, 0.65) end)
arrow.close:SetScript("OnClick", function()
	dismissed = view and view.wp or (current and current.wp)
	arrow:Hide()
end)

arrow.dist = Label(12, 1, 1, 1, true)
arrow.dist:SetPoint("RIGHT", arrow.close, "LEFT", -3, 0)
arrow.dist:SetJustifyH("RIGHT")

arrow.chev = arrow:CreateTexture(nil, "ARTWORK")
arrow.chev:SetSize(12, 12)
arrow.chev:SetTexture(FR.DIR .. "\\Textures\\Chevron")
arrow.chev:SetPoint("RIGHT", arrow.dist, "LEFT", -4, 0)

-- Width reserved for the distance so the box does not twitch while walking.
local distReserve

local function Accent()
	return FR.Theme and FR.Theme().accent or { 0.36, 0.64, 1.0 }
end

-- Who or what the step is about: the first target / enemy name, else the
-- step's text.
local function Who(info)
	if info.corpse then return FR.L["Your corpse"] end
	local step = info.step
	if step then
		for _, e in ipairs(step.elements) do
			if (e.kind == "target" or e.kind == "mob" or e.kind == "unitscan") and e.targets and e.targets[1] then
				local n = tostring(e.targets[1]):gsub("^%+", "")
				return FR.NpcName and FR.NpcName(n) or n
			end
		end
	end
	return info.title or FR.L["Waypoint"]
end

-- Corpse ----------------------------------------------------------------------------------
-- As a ghost the bar points to the body instead of the guide step.

local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:12|t"
local corpse, corpseChecked = nil, 0
local function CorpseMapPosition()
	local Plain = FR.Plain
	local mapID = Plain(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
	-- The body is also on every parent map of the map it lies on.
	local tries = 0
	while mapID and tries < 5 do
		local x, y
		if C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
			local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, mapID)
			if ok and pos then
				if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
				x, y = Plain(x), Plain(y)
			end
		end
		if x and y and (x > 0 or y > 0) then return mapID, x, y end
		local okInfo, info = pcall(C_Map.GetMapInfo, mapID)
		mapID = okInfo and info and Plain(info.parentMapID) or nil
		tries = tries + 1
	end
	-- Older clients: position on the map that is open.
	if GetCorpseMapPosition then
		local ok, x, y = pcall(GetCorpseMapPosition)
		local map = Plain(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
		x, y = Plain(x), Plain(y)
		if ok and map and x and y and (x > 0 or y > 0) then return map, x, y end
	end
end

local function CorpseTarget()
	if not (UnitIsGhost and UnitIsGhost("player")) then corpse = nil return nil end
	local now = GetTime()
	if corpse and now - corpseChecked < 0.5 then return corpse end
	corpseChecked = now
	local mapID, x, y = CorpseMapPosition()
	if not mapID then return corpse end   -- keep the last known position
	if corpse and corpse.mapID == mapID and corpse.x == x * 100 and corpse.y == y * 100 then return corpse end
	local wp = { mapID = mapID, x = x * 100, y = y * 100 }
	if not FR:ResolveWaypoint(wp) or not wp.north then return nil end
	corpse = { wp = wp, zone = wp.zone, x = wp.x, y = wp.y, mapID = mapID, title = FR.L["Your corpse"],
		radius = 35, cont = wp.instance, wx = wp.north, wy = wp.west, corpse = true }
	return corpse
end

-- The waypoint the bar shows: the corpse while you are a ghost, else the step's.
local function PickView()
	return CorpseTarget() or current
end

-- Lays the box out for a waypoint (text and width).
local function Layout(info)
	info = info or view
	if not info then return end
	if not arrow.skinned and FR.Skin then
		arrow.skinned = true
		FR.Skin(arrow, "bg")
		-- The addon's fonts exist now (UI.lua); they follow the font choice.
		for _, fs in ipairs({ arrow.step, arrow.title, arrow.dist }) do
			if FR[fs.fontKey] then fs:SetFontObject(FR[fs.fontKey]) end
		end
		if FR.fontArrow then arrow.close.text:SetFontObject(FR.fontArrow) end
	end
	-- Text boxes of an even height in a bar of an even height: the text is then
	-- centred on a whole pixel (a half pixel makes small text blurry).
	local fh = 2 * math.ceil(((FR:Get("fontSize") or 11) + 4) / 2)
	for _, fs in ipairs({ arrow.step, arrow.title, arrow.dist }) do fs:SetHeight(fh) end
	arrow.badge:SetHeight(fh + 2)
	arrow:SetHeight(fh + 10)
	arrow.close:SetSize(16, fh + 10)
	local a = info.corpse and { 1, 0.4, 0.35 } or Accent()
	arrow.badge:SetVertexColor(a[1], a[2], a[3], 0.22)
	arrow.step:SetTextColor(a[1], a[2], a[3])
	arrow.step:SetText(info.corpse and SKULL or tostring(FR.stepIndex or 0))
	arrow.badge:SetWidth(math.max(16, math.ceil(arrow.step:GetStringWidth() or 10) + 10))
	arrow.title:SetWidth(0)
	arrow.title:SetText(Who(info))
	local titleW = math.min(TITLE_MAX, math.ceil(arrow.title:GetStringWidth() or 60))
	arrow.title:SetWidth(titleW)
	if not distReserve then
		arrow.dist:SetText("9999 yd")
		distReserve = math.ceil(arrow.dist:GetStringWidth() or 40)
		arrow.dist:SetText("")
	end
	local w = PAD + arrow.badge:GetWidth() + 7 + titleW + 12 + 12 + 4 + distReserve + 3 + 16 + 3
	arrow:SetWidth(math.ceil(w))
	arrow.shownDist, arrow.shownAngle = false, false
end

-- Puts the bar in the middle of the screen, 20 pixels below the top edge.
function FR:CenterArrow()
	local s = self:Get("arrowScale") or 1
	local y = -math.floor(20 / s + 0.5)   -- offsets count in the bar's own units
	arrow:ClearAllPoints()
	arrow:SetPoint("TOP", UIParent, "TOP", 0, y)
	if ForeverRouteDB then ForeverRouteDB.arrowPos = { "TOP", "TOP", 0, y } end
end

-- After a font change: measure the texts again.
function FR:LayoutArrow()
	distReserve = nil
	if arrow:IsShown() then Layout(view) end
end

function FR:UpdateArrowVisibility()
	view = PickView()
	if view and view.wx and self:Get("showArrow") and dismissed ~= view.wp then
		Layout(view)
		lastView = view
		arrow:Show()
	else
		arrow:Hide()
	end
	-- Pixel-perfect like the guide window (see UI.lua).
	local s = self:Get("arrowScale") or 1
	arrow:SetScale(FR.PixelScale and FR.PixelScale(s) or s)
end

local acc, lastStep, lastTitle = 0, nil, nil
arrow:SetScript("OnUpdate", function(self, elapsed)
	acc = acc + elapsed
	if acc < 0.02 then return end
	acc = 0
	view = PickView()
	if not view then self:Hide() return end
	-- Ghost <-> alive, a new waypoint, or the step / its text changed.
	if view ~= lastView or lastStep ~= FR.stepIndex or lastTitle ~= view.title then
		if view ~= lastView and (dismissed == view.wp or not FR:Get("showArrow")) then
			lastView = view
			self:Hide()
			return
		end
		lastView, lastStep, lastTitle = view, FR.stepIndex, view.title
		Layout(view)
		if not self:IsShown() and FR:Get("showArrow") and dismissed ~= view.wp then self:Show() end
	end
	local a = view.corpse and { 1, 0.4, 0.35 } or Accent()
	local dist, bearing = FR:GetWaypointVector(view)
	if not dist then
		-- Other continent / instance: no direction, the zone name instead.
		self.chev:Hide()
		if self.shownDist ~= view.zone then
			self.shownDist = view.zone
			self.dist:SetText(view.zone)
			self.dist:SetTextColor(0.55, 0.58, 0.65)
		end
		return
	end
	self.chev:Show()
	-- Green inside the arrival radius, else the theme colour.
	local r, g, b = a[1], a[2], a[3]
	if dist <= (view.radius or FR:Get("arriveRadius") or 0) then r, g, b = 0.4, 0.95, 0.5 end
	self.chev:SetVertexColor(r, g, b)
	self.dist:SetTextColor(r, g, b)
	local angle = bearing - (GetPlayerFacing() or 0)
	if not self.shownAngle or math.abs(angle - self.shownAngle) > 0.01 then
		self.shownAngle = angle
		self.chev:SetRotation(angle)
	end
	local t = string.format("%d yd", math.floor(dist))
	if t ~= self.shownDist then self.shownDist = t; self.dist:SetText(t) end
end)

-- Arrival ticker (runs even when the arrow is hidden) ---------------------------

local ticker = CreateFrame("Frame")
local tacc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	tacc = tacc + elapsed
	if tacc < 0.25 then return end
	tacc = 0
	if not current or not current.goal or not current.wx then return end
	if UnitIsGhost and UnitIsGhost("player") then return end
	local goal = current.goal
	-- Only waypoints with a radius are "reached" (path points and arrivals).
	if not current.radius then return end
	if goal.arrive and not FR:Get("autoArrive") then return end
	local dist = FR:GetWaypointVector()
	if dist and dist <= current.radius then
		FR:OnArrive(current.step, goal)
	end
end)
