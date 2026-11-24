-- Step numbers on the world map and the minimap: the current step and the
-- next five, drawn as small outlined numbers without a background. Steps at the
-- same spot share one number: the first step and a plus ("111+"). Hovering a
-- number lists those steps.
local _, ns = ...
local FR = ns.FR

local AHEAD = 5             -- steps with a location after the current one
local MERGE_WORLD = 45      -- yards: closer points share a number (world map)
local MERGE_MINIMAP = 20    -- yards: the same on the minimap
local FONT = "Fonts\\ARIALN.TTF"   -- fallback; the chosen font comes from FR.FontFile

-- Position of a guide waypoint on the given map (0-1), or nil.
function FR:WaypointOnMap(wp, mapID)
	if not self:ResolveWaypoint(wp) then return nil end
	if wp.mapID == mapID and wp.x then return wp.x / 100, wp.y / 100 end
	if wp.north and C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
		local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, wp.instance, CreateVector2D(wp.north, wp.west), mapID)
		if ok and pos then return pos:GetXY() end
	end
	return nil
end

-- Pin data ----------------------------------------------------------------------------

-- Waypoints of a step that get a number: every shown point that has not been
-- reached yet. Steps that only have path points show their first point.
local function StepPoints(step, active)
	local list, first = {}, nil
	for _, e in ipairs(step.elements) do
		if (e.kind == "goto" or e.kind == "pin") and FR:ResolveWaypoint(e.wp) and e.wp.north then
			first = first or e
			-- A pin whose objective line is done (Mankrik's quests handed in) leaves the map.
			if not e.hidePin and not (active and e.wp.radius and FR:IsMarked(step, e))
				and not (active and not e.wp.radius and e.parent and not FR:PinWanted(step, e)) then
				list[#list + 1] = e
			end
		end
	end
	if #list == 0 and first then list[1] = first end
	return list
end

-- Number of a pin: its first step, with a plus when more steps share the spot.
local function Label(indexes)
	table.sort(indexes)
	return (#indexes > 1) and (indexes[1] .. "+") or tostring(indexes[1])
end

-- Every numbered point of the active steps and the next steps:
-- { step, wp, current }.
local function CollectPoints()
	local g = FR.current
	local out = {}
	if not (g and g.steps) then return out end
	local seen = {}
	local function Add(step, active)
		if seen[step] then return false end
		seen[step] = true
		local pts = StepPoints(step, active)
		for _, e in ipairs(pts) do
			out[#out + 1] = { step = step, wp = e.wp, current = (step.idx == FR.stepIndex) }
		end
		return #pts > 0
	end
	for _, s in ipairs(FR:GetActiveSteps()) do Add(s, true) end
	local i, count = FR.stepIndex + 1, 0
	while g.steps[i] and count < AHEAD do
		local s = g.steps[i]
		if not FR.IsSideStep(s) and not FR:IsStepFinished(s) and Add(s, false) then count = count + 1 end
		i = i + 1
	end
	return out
end

-- Groups points closer than `yards` into pins.
local function Merge(points, yards)
	local pins = {}
	for _, p in ipairs(points) do
		local wp, hit = p.wp, nil
		for _, pin in ipairs(pins) do
			if pin.instance == wp.instance then
				local dn, dw = pin.north - wp.north, pin.west - wp.west
				if dn * dn + dw * dw < yards * yards then hit = pin break end
			end
		end
		if not hit then
			hit = { instance = wp.instance, north = wp.north, west = wp.west, wp = wp, steps = {}, indexes = {}, has = {} }
			pins[#pins + 1] = hit
		end
		if not hit.has[p.step] then
			hit.has[p.step] = true
			hit.steps[#hit.steps + 1] = p.step
			hit.indexes[#hit.indexes + 1] = p.step.idx
		end
		hit.current = hit.current or p.current
	end
	for n, pin in ipairs(pins) do
		pin.label = Label(pin.indexes)
		pin.order = n
		table.sort(pin.steps, function(a, b) return a.idx < b.idx end)
	end
	return pins
end

local worldPins, minimapPins = {}, {}

-- Tooltip listing every step of a pin.
local function ShowPinTooltip(owner, pin)
	if not pin then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	for n, step in ipairs(pin.steps) do
		if n > 1 then GameTooltip:AddLine(" ") end
		GameTooltip:AddLine(string.format(FR.L["Step %d"], step.idx), 1, 0.82, 0.2)
		local text = FR.StepLines and FR.StepLines(step) or ""
		for line in (text .. "\n"):gmatch("(.-)\n") do
			if line ~= "" then GameTooltip:AddLine(line, 1, 1, 1, true) end
		end
	end
	GameTooltip:Show()
end

-- Shared look: just the outlined number, no background, in the purple of
-- RestedXP's map numbers. The current step is larger and fully opaque,
-- later steps fade a little.
local PURPLE = { 206 / 210, 123 / 210, 1 }

local function Style(f, pin, small)
	local size = pin.current and (small and 10 or 14) or (small and 8 or 11)
	local file = FR.FontFile and FR.FontFile(true) or FONT
	if f.num:SetFont(file, size, "OUTLINE") == false then f.num:SetFont(FONT, size, "OUTLINE") end
	f.num:SetText(pin.label)
	f.num:SetTextColor(PURPLE[1], PURPLE[2], PURPLE[3])
	local w = math.max(f.num:GetStringWidth() or 8, f.num:GetStringHeight() or 8) + 2
	f:SetSize(w, (f.num:GetStringHeight() or 8) + 2)
	f:SetAlpha(pin.current and 1 or math.max(0.6, 0.9 - (pin.order - 1) * 0.06))
end

local function Decorate(f)
	f.num = f:CreateFontString(nil, "OVERLAY")
	f.num:SetFont(FONT, 10, "OUTLINE")
	f.num:SetPoint("CENTER", 0, 0)
	f.num:SetShadowOffset(0, 0)
end

-- Placing the numbers -------------------------------------------------------------------
-- World map and minimap use HereBeDragons-Pins, the library RestedXP uses for
-- its step markers (a copy lives in Libs\). It places the icons, follows the
-- zoom of both maps, rotates with the minimap and floats icons on its edge.

local HBDPins = LibStub and LibStub("ForeverRoute-HBD-Pins-2.0", true)
local REF = "ForeverRoute"
local worldIcons, miniIcons = {}, {}
local lastSignature

local function Icon(list, i, small)
	local f = list[i]
	if f then return f end
	f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(22, 22)
	Decorate(f)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self) ShowPinTooltip(self, self.pin) end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.pin, f.small = false, small
	f:Hide()
	list[i] = f
	return f
end

local function Signature()
	local parts = { tostring(FR:Get("mapPins")), tostring(FR:Get("minimapPins")), tostring(FR:Get("font")),
		tostring(FR:Get("fontSize")) }
	for _, list in ipairs({ worldPins, minimapPins }) do
		for _, pin in ipairs(list) do
			parts[#parts + 1] = pin.label .. (pin.current and "*" or "") .. "@" .. tostring(pin.wp.mapID)
				.. ":" .. tostring(pin.wp.x) .. ":" .. tostring(pin.wp.y)
		end
		parts[#parts + 1] = "|"
	end
	return table.concat(parts, ";")
end

local function Rebuild()
	if not HBDPins then return end
	local sig = Signature()
	if sig == lastSignature then return end
	lastSignature = sig

	HBDPins:RemoveAllWorldMapIcons(REF)
	HBDPins:RemoveAllMinimapIcons(REF)
	for _, f in ipairs(worldIcons) do f.pin = false; f:Hide() end
	for _, f in ipairs(miniIcons) do f.pin = false; f:Hide() end
	if not (ForeverRouteDB and FR.current) then return end

	-- Later steps first, so the current step ends up on top.
	if FR:Get("mapPins") then
		for n = #worldPins, 1, -1 do
			local pin = worldPins[n]
			local wp = pin.wp
			if wp.mapID and wp.x and wp.y then
				local f = Icon(worldIcons, n, false)
				f.pin = pin
				Style(f, pin, false)
				pcall(HBDPins.AddWorldMapIconMap, HBDPins, REF, f, wp.mapID, wp.x / 100, wp.y / 100,
					HBD_PINS_WORLDMAP_SHOW_CONTINENT)
			end
		end
	end
	if FR:Get("minimapPins") and not (IsInInstance and IsInInstance()) then
		for n = #minimapPins, 1, -1 do
			local pin = minimapPins[n]
			local wp = pin.wp
			if wp.mapID and wp.x and wp.y then
				local f = Icon(miniIcons, n, true)
				f.pin = pin
				Style(f, pin, true)
				-- Only the current step floats on the edge of the minimap.
				pcall(HBDPins.AddMinimapIconMap, HBDPins, REF, f, wp.mapID, wp.x / 100, wp.y / 100, true,
					pin.current and true or false)
			end
		end
	end
end

-- Route lines on the world map --------------------------------------------------------
-- Like RestedXP: steps tagged "#loop" draw their route points as a closed line,
-- ".line" draws a given path. The lines are Line regions on a frame laid over the
-- map's canvas (the numbers themselves come from the pins library).

local routeLines = {}          -- { wps = { waypoint... }, closed = bool }
local lineFrame, lineObjs = nil, {}
local lastLineScale, lastLineMap

-- Route lines of the steps on screen and the next two.
local function CollectLines()
	local out = {}
	local g = FR.current
	if not (g and g.steps) then return out end
	local steps = {}
	for _, s in ipairs(FR:GetActiveSteps()) do steps[#steps + 1] = s end
	local i, count = (FR.stepIndex or 1) + 1, 0
	while g.steps[i] and count < 2 do
		local s = g.steps[i]
		if not FR.IsSideStep(s) and not FR:IsStepFinished(s) then steps[#steps + 1] = s; count = count + 1 end
		i = i + 1
	end
	for _, s in ipairs(steps) do
		if not FR:IsStepSkipped(s) then
			local loop = {}
			for _, e in ipairs(s.elements) do
				if e.kind == "goto" and s.loop and FR:ResolveWaypoint(e.wp) and e.wp.north then loop[#loop + 1] = e.wp end
				local L = e.line
				if L and not L.world then
					if not L.wps then
						L.wps = {}
						for _, p in ipairs(L.points) do
							local wp = { mapID = L.map, x = p[1], y = p[2] }
							if FR:ResolveWaypoint(wp) and wp.north then L.wps[#L.wps + 1] = wp end
						end
					end
					if #L.wps > 1 then out[#out + 1] = { wps = L.wps } end
				end
			end
			if #loop > 1 then out[#out + 1] = { wps = loop, closed = true } end
		end
	end
	return out
end

local function LineLevel(canvas)
	local level
	local mgr = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	if mgr and mgr.GetValidFrameLevel then
		local ok, l = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_AREA_POI")
		if ok and type(l) == "number" then level = l end
	end
	return level or ((canvas:GetFrameLevel() or 1) + 150)
end

local function DrawLines()
	if not (WorldMapFrame and WorldMapFrame.GetCanvas) then return end
	local okc, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
	if not (okc and canvas) then return end
	if not lineFrame then
		lineFrame = CreateFrame("Frame", nil, canvas)
		lineFrame:SetAllPoints(canvas)
		lineFrame:EnableMouse(false)
	end
	lineFrame:SetFrameLevel(LineLevel(canvas))
	local used = 0
	if WorldMapFrame:IsShown() and ForeverRouteDB and FR:Get("mapPins") and #routeLines > 0 then
		local okm, mapID = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
		local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
		if okm and mapID and w > 0 and h > 0 then
			local cs, ws = canvas:GetEffectiveScale() or 1, WorldMapFrame:GetEffectiveScale() or 1
			local scale = (cs > 0) and (ws / cs) or 1
			lastLineScale, lastLineMap = scale, mapID
			for _, pl in ipairs(routeLines) do
				local pts = {}
				for i, wp in ipairs(pl.wps) do
					local x, y = FR:WaypointOnMap(wp, mapID)
					pts[i] = (x and y) and { x * w, -y * h } or false
				end
				local count = #pl.wps
				for i = 1, pl.closed and count or count - 1 do
					local a, b = pts[i], pts[i % count + 1]
					if a and b then
						used = used + 1
						local ln = lineObjs[used]
						if not ln then
							ln = lineFrame:CreateLine(nil, "ARTWORK")
							lineObjs[used] = ln
						end
						ln:SetThickness(2 * scale)
						ln:SetColorTexture(206 / 210, 123 / 210, 1, 0.7)
						ln:SetStartPoint("TOPLEFT", lineFrame, a[1], a[2])
						ln:SetEndPoint("TOPLEFT", lineFrame, b[1], b[2])
						ln:Show()
					end
				end
			end
		end
	end
	for i = used + 1, #lineObjs do lineObjs[i]:Hide() end
end

-- While the map is open: redraw when the map changes or is zoomed.
local lineWatch, lineAcc = CreateFrame("Frame"), 0
lineWatch:SetScript("OnUpdate", function(_, elapsed)
	if not (WorldMapFrame and WorldMapFrame:IsShown()) or #routeLines == 0 then return end
	lineAcc = lineAcc + elapsed
	if lineAcc < 0.15 then return end
	lineAcc = 0
	local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
	if not (ok and canvas) then return end
	local cs, ws = canvas:GetEffectiveScale() or 1, WorldMapFrame:GetEffectiveScale() or 1
	local scale = (cs > 0) and (ws / cs) or 1
	local okm, mapID = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
	if not lastLineScale or math.abs(scale - lastLineScale) > 0.001 or (okm and mapID ~= lastLineMap) then
		pcall(DrawLines)
	end
end)
if WorldMapFrame and WorldMapFrame.HookScript then
	pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", function() lastLineScale = nil; pcall(DrawLines) end)
	pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", function() pcall(DrawLines) end)
end

-- Old versions placed a game waypoint; remove it once.
local cleaner = CreateFrame("Frame")
cleaner:RegisterEvent("PLAYER_ENTERING_WORLD")
cleaner:SetScript("OnEvent", function()
	if ForeverRouteDB and not ForeverRouteDB.userWaypointCleared then
		ForeverRouteDB.userWaypointCleared = true
		if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
	end
end)

-- Update ---------------------------------------------------------------------------------

-- After a font change: style the numbers again.
function FR:RefreshMapFonts()
	lastSignature = nil
end

-- Called after every guide window update.
function FR:RefreshMapPins()
	local points = (ForeverRouteDB and self.current) and CollectPoints() or {}
	worldPins = Merge(points, MERGE_WORLD)
	minimapPins = Merge(points, MERGE_MINIMAP)
	pcall(Rebuild)
	routeLines = (ForeverRouteDB and self.current) and CollectLines() or {}
	lastLineScale = nil
	pcall(DrawLines)
end

-- For tests: the world map pins as { label, current, steps }.
function FR:GetMapPinData()
	return worldPins
end

-- For tests: the icon frames handed to the library.
function FR:GetMapIcons()
	return worldIcons, miniIcons
end

-- For tests: the route lines of the steps on screen.
function FR:GetRouteLines()
	return routeLines
end
