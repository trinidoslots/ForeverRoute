-- ForeverRoute's own name plates. The game's plate is hidden and a frame of ours is drawn instead:
--   enemy  every attackable creature: a health bar with name, health % and level, a small cast bar.
--          The enemies of the current step are highlighted: a teal bar, a marker (the quest "!" and/or
--          the raid-style icon, Settings > Name Plates) and how many are still needed ("2/8").
--   npc    every friendly creature. By default ONLY THE NAME, drawn the way the game draws its floating
--          names (its font, colour by reaction, a thin shadow, the <title> under it): the plate exists so
--          the step's icon can sit beside the name, but it looks as if friendly plates were off. As an
--          option (Settings > Name Plates) the Classic plate: the name above a flat bar, a beveled frame,
--          a round level badge, a dragon for elite / rare, a cast bar with the spell icon.
-- Players, pets and everything else keep the game's plate. Nothing is drawn in instances (the names there
-- are secret values and friendly plates are forbidden frames). With "Custom plates" off Nameplates.lua
-- only hangs its small icon on the game's plate.
local _, ns = ...
local FR = ns.FR
local Plain = FR.Plain

local WHITE = "Interface\\Buttons\\WHITE8X8"
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local GOLD = { 1, 0.82, 0 }
local TEAL = { 0.12, 0.55, 0.60 }   -- fill of the bar of a step enemy
local BAR_W = 180       -- enemy bar
local CLASSIC_W = 110   -- Classic NPC plate
local ENEMY_H, NPC_H, CAST_H = 22, 10, 12
local NAME_SIZE = 18

local function PlateFor(unit)
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
	if not ok or not plate then return nil end
	if plate.IsForbidden and plate:IsForbidden() then return nil end
	return plate
end

local function Flag(func, ...)
	local ok, v = pcall(func, ...)
	if not ok then return nil end
	return Plain(v)
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- Size of a friendly NPC's name against the camera ------------------------------------------------------
-- The names the game draws get smaller the farther the camera is from the creature (perspective); a plate frame
-- has a constant size. So the size is computed: factor = (REF / cameraDistance) ^ strength, the camera distance
-- being about sqrt(distance to the creature ^ 2 + camera zoom ^ 2). Calibrated against the game's own names:
-- they shrink roughly with the camera distance to the power 1.4.

local REF_DIST = 15   -- yards of camera distance at which the factor is 1

local function CameraZoom()
	if not GetCameraZoom then return nil end
	local ok, zoom = pcall(GetCameraZoom)
	zoom = ok and Plain(zoom) or nil
	return type(zoom) == "number" and zoom or nil
end

-- Distance in yards between you and the unit, or nil when this client does not give positions of that unit.
local function UnitDistance(unit)
	if not UnitPosition then return nil end
	local ok1, py, px = pcall(UnitPosition, "player")
	local ok2, uy, ux = pcall(UnitPosition, unit)
	if not (ok1 and ok2) then return nil end
	py, px, uy, ux = Plain(py), Plain(px), Plain(uy), Plain(ux)
	if type(py) ~= "number" or type(px) ~= "number" or type(uy) ~= "number" or type(ux) ~= "number" then return nil end
	return math.sqrt((uy - py) ^ 2 + (ux - px) ^ 2)
end

-- UnitPosition is the expensive part and a creature does not move far in a quarter of a second: remembered per
-- name plate unit token, refreshed every 0.25 s.
local distCache = {}   -- [unit token] = { distance or false, time }

local function CachedDistance(unit)
	local now = GetTime()
	local c = distCache[unit]
	if not c or now - c[2] > 0.25 then
		c = c or {}
		c[1], c[2] = UnitDistance(unit) or false, now
		distCache[unit] = c
	end
	return c[1] or nil
end

-- The zoom the factor uses: the real zoom followed by a critically damped filter (time constant about 100 ms,
-- see the driver at the end), so that a stepwise reading (the value jumping per mouse wheel tick) glides.
local zoomPos, zoomVel
local function LiveZoom() return zoomPos or CameraZoom() end

-- The factor the name is scaled with. `zoom`: LiveZoom().
local function DistanceFactor(unit, zoom)
	local strength = FR:Get("plateNameDistance")
	if type(strength) ~= "number" or strength <= 0 then return 1 end
	local d = CachedDistance(unit) or 0
	local cam = math.sqrt(d * d + (zoom or 0) ^ 2)
	if cam < 1 then return 1 end
	return math.max(0.2, math.min(2.0, (REF_DIST / cam) ^ strength))
end
-- The game's own name-only mode for a plate (the one Plater switches on for friendly NPCs): the health bar
-- and the cast bar are taken out through texture groups and the game draws the name itself.
local function NativeAvailable()
	return TextureLoadingGroupMixin ~= nil and TextureLoadingGroupMixin.AddTexture ~= nil
		and TextureLoadingGroupMixin.RemoveTexture ~= nil and NamePlateUnitFrameMixin ~= nil
end

-- How friendly NPCs are drawn: "game" (the game draws the name itself, like friendly players), "own" (our
-- text in the game's font) or "classic" (the Classic plate). "game" needs nothing special: the bar is
-- hidden by hiding its container, the texture groups of NameOnly only help the game lay the name out.
local function NpcMode()
	local mode = FR:Get("plateNpc")
	if mode == "classic" or mode == "own" then return mode end
	return "game"
end

local function NameOnly(uf, on)
	if not NativeAvailable() or type(uf) ~= "table" then return end
	local container = uf.HealthBarsContainer
	local bar = container and container.healthBar or uf.healthBar
	local cast = uf.castBar or uf.CastBar
	local fn = on and TextureLoadingGroupMixin.AddTexture or TextureLoadingGroupMixin.RemoveTexture
	if bar then pcall(fn, { textures = bar }, "showOnlyName") end
	if cast then
		pcall(fn, { textures = cast }, "showOnlyName")
		pcall(fn, { textures = cast }, "widgetsOnly")
	end
end

-- The game's own floating NPC names ------------------------------------------------------------------------
-- A friendly NPC has a plate only within the plate range (45 yards here). Beyond it the game draws its own
-- floating name, inside it ours: two looks that differ in size, weight and height, so the swap is visible. While
-- our plates draw the names, the game's floating NPC names are switched off ("Show NPC names", CVar
-- UnitNameNPC): then there is one look only. The player's own value is saved and put back when this stops.

local function CVarValue(name)
	local get = (C_CVar and C_CVar.GetCVar) or GetCVar
	if not get then return nil end
	local ok, v = pcall(get, name)
	return ok and Plain(v) or nil
end

local function SetCVarSafe(name, value)
	local set = (C_CVar and C_CVar.SetCVar) or SetCVar
	if not set then return false end
	return (pcall(set, name, value))
end

-- Hide them only when we draw the names ourselves ("Own text", "Classic plate"): in "Game text" the name is the
-- game's own plate text, which may depend on the setting.
local function WantHideNames()
	return FR:Get("customPlates") and FR:Get("plateHideGameNames") ~= false and NpcMode() ~= "game"
end

local npcNamesPending = false

function FR:ApplyNpcNames()
	local db = ForeverRouteDB
	if not db then return end
	if InCombat() then npcNamesPending = true return end   -- a CVar cannot be changed in combat: later
	npcNamesPending = false
	local current = CVarValue("UnitNameNPC")
	if WantHideNames() then
		if current == nil then return end
		if db.npcNamesBackup == nil and current ~= "0" then db.npcNamesBackup = current end
		if current ~= "0" then SetCVarSafe("UnitNameNPC", "0") end
	elseif db.npcNamesBackup ~= nil then
		SetCVarSafe("UnitNameNPC", db.npcNamesBackup)
		db.npcNamesBackup = nil
	end
end

-- The plate range is the largest the game allows (its default, read from the CVar): a smaller value would put
-- the swap closer than necessary.
local function EnsureRange()
	if InCombat() or not FR:Get("customPlates") then return end
	local cur = tonumber(CVarValue("nameplateMaxDistance"))
	local info = C_CVar and C_CVar.GetCVarInfo
	if not (cur and info) then return end
	local ok, _, default = pcall(info, "nameplateMaxDistance")
	default = ok and tonumber(Plain(default)) or nil
	if default and default > 0 and cur < default - 0.5 then SetCVarSafe("nameplateMaxDistance", default) end
end

-- Scales the text of the game's own name (Game text): the game keeps it at its small nameplate size, the
-- names it draws for players are larger. SetTextScale where the client has it, else the font size.
local function ScaleName(uf, k)
	local fs = type(uf) == "table" and (uf.name or uf.Name) or nil
	if type(fs) ~= "table" or not fs.GetFont then return end
	if fs.SetTextScale then
		if k == 1 and not fs.FRScaled then return end
		-- Nothing to do when the text already has this scale (no needless re-rendering of the text).
		if fs.GetTextScale then
			local okc, cur = pcall(fs.GetTextScale, fs)
			if okc and type(cur) == "number" and math.abs(cur - k) < 0.0005 then return end
		end
		pcall(fs.SetTextScale, fs, k)
		fs.FRScaled = k ~= 1
		return
	end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if not ok or type(path) ~= "string" or type(size) ~= "number" then return end
	-- A size that is not the one set last was set by the game: that is the base.
	local base = (fs.FRSetSize and math.abs(size - fs.FRSetSize) < 0.01 and fs.FRBase) or size
	fs.FRBase = base
	-- Changing the font is expensive: in steps of 0.05 only (SetTextScale above takes the exact value).
	local want = base * (math.floor(k * 20 + 0.5) / 20)
	if math.abs(size - want) > 0.01 then pcall(fs.SetFont, fs, path, want, flags) end
	fs.FRSetSize = want
	fs.FRScaled = k ~= 1
end

-- The game puts a plate back to its normal look at every update of the unit's name colour: switch the
-- name-only mode on again there, for friendly non-player units, while "Game text" is chosen.
local nativeHooked = false
local function HookNative()
	if nativeHooked or not NativeAvailable() or not hooksecurefunc then return end
	nativeHooked = true
	pcall(hooksecurefunc, NamePlateUnitFrameMixin, "UpdateNameClassColor", function(self)
		if NpcMode() ~= "game" or not FR:Get("customPlates") or FR.InInstance() then return end
		local unit = self.unit
		if type(unit) ~= "string" then return end
		if Flag(UnitIsPlayer, unit) ~= false or Flag(UnitCanAttack, "player", unit) ~= false then return end
		NameOnly(self, true)
		ScaleName(self, (FR:Get("plateNameScale") or 1.0) * DistanceFactor(unit, LiveZoom()))
	end)
end

-- Which unit gets which plate ------------------------------------------------------------------------

-- "enemy", "npc" or "dead" for a name plate unit of ours, plus its step entry (Nameplates.lua), or nil:
-- the game's plate stays.
local function Category(unit)
	if not FR:Get("customPlates") then return nil end
	if type(unit) ~= "string" or FR.InInstance() then return nil end
	if Flag(UnitIsPlayer, unit) ~= false then return nil end          -- players (or unknown) keep the game's plate
	if Flag(UnitPlayerControlled, unit) ~= false then return nil end  -- pets, guardians
	local canAttack = Flag(UnitCanAttack, "player", unit)
	if canAttack == nil then return nil end
	local info = FR.NameplateEntry and FR.NameplateEntry(unit) or nil
	if canAttack then
		if Flag(UnitIsDead, unit) == true then return "dead" end
		return "enemy", info
	end
	return "npc", info
end

-- Nameplates.lua asks: does the plate of this unit draw the step icon itself?
function FR.PlateDrawsIcon(unit)
	local cat = Category(unit)
	-- With "Game text" the game draws the name and Nameplates.lua hangs the icon on it.
	return cat == "enemy" or (cat == "npc" and NpcMode() ~= "game")
end

-- Quest progress of a step enemy ----------------------------------------------------------------------

-- How many of this creature the step's quest objectives ask for: (killed, needed), or nil. The objective
-- text ("Murloc Oracle slain: 2/8") has to name the creature.
local function Progress(info)
	if not (info and info.objs and FR.GetObjective) then return nil end
	local names = {}
	if info.name then names[#names + 1] = info.name:lower() end
	if info.raw then names[#names + 1] = info.raw:lower() end
	for _, o in ipairs(info.objs) do
		local text = FR.GetObjective(o.qid, o.obj, o.hint)
		if type(text) == "string" then
			local cur, total = text:match("(%d+)%s*/%s*(%d+)")
			if cur then
				local low, hit = text:lower(), false
				for _, n in ipairs(names) do
					if low:find(n, 1, true) then hit = true break end
				end
				if not hit and o.hint and info.raw and o.hint:lower() == info.raw:lower() then hit = true end
				if hit then return tonumber(cur), tonumber(total) end
			end
		end
	end
	return nil
end

-- Colours --------------------------------------------------------------------------------------------

-- The colour the game gives the unit's name: green friendly, yellow neutral, red hostile.
local function ReactionColor(unit, dr, dg, db)
	local ok, r, g, b = pcall(UnitSelectionColor, unit)
	r, g, b = Plain(r), Plain(g), Plain(b)
	if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
	return dr, dg, db
end

-- Colour of a creature's level against yours (grey, green, yellow, orange, red), the same the game's target frame
-- uses (GetCreatureDifficultyColor: the XP difficulty of a creature, not the quest one).
local function LevelColor(level)
	if level < 0 then return 1, 0.1, 0.1 end   -- skull
	if GetCreatureDifficultyColor then
		local ok, c = pcall(GetCreatureDifficultyColor, level)
		if ok and type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
	end
	-- Fallback: the classic rules. Grey at or below the player's grey level.
	local mine = UnitLevel("player") or level
	local diff = level - mine
	local grey
	if mine <= 5 then grey = 0
	elseif mine <= 39 then grey = mine - math.floor(mine / 10) - 5
	elseif mine <= 59 then grey = mine - math.floor(mine / 5) - 1
	else grey = mine - 9 end
	if diff >= 5 then return 1, 0.1, 0.1 end
	if diff >= 3 then return 1, 0.5, 0.25 end
	if diff >= -2 then return 1, 1, 0 end
	if level > grey then return 0.25, 0.75, 0.25 end
	return 0.5, 0.5, 0.5
end

-- Fill colour of an enemy bar: teal for a step enemy, else muted tones by reaction (not the game's pure red).
local function BarColor(unit, info)
	if info then return TEAL[1], TEAL[2], TEAL[3] end
	local reaction = Flag(UnitReaction, unit, "player")
	if type(reaction) == "number" then
		if reaction <= 2 then return 0.72, 0.17, 0.15 end
		if reaction == 3 then return 0.80, 0.40, 0.14 end
		if reaction == 4 then return 0.82, 0.68, 0.18 end
		return 0.24, 0.58, 0.26
	end
	local r, g, b = ReactionColor(unit, 0.9, 0.22, 0.2)
	return r * 0.78, g * 0.78, b * 0.78
end

-- A vertical alpha gradient on a texture (from `a1` at the bottom to `a2` at the top) in the given colour.
local function Gradient(tex, a1, a2, r, g, b)
	if tex.SetGradient and CreateColor then
		pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
	elseif tex.SetGradientAlpha then
		pcall(tex.SetGradientAlpha, tex, "VERTICAL", r, g, b, a1, r, g, b, a2)
	else
		tex:SetVertexColor(r, g, b, (a1 + a2) / 2)
	end
end

-- The line under an NPC's name ("<Wind Rider Master>"), or nil. Read from the unit's tooltip: line 2,
-- which is the level line for creatures without a title. Remembered per creature; a miss is tried again
-- after 3 seconds (the tooltip data can arrive late).
local subCache, subCount, scanTip = {}, 0, nil

function FR.UnitSubtitle(unit)
	local guid = Flag(UnitGUID, unit)
	if type(guid) ~= "string" then return nil end
	local now = GetTime()
	local hit = subCache[guid]
	if hit and (hit[1] ~= false or now - hit[2] < 3) then return hit[1] or nil end
	if not scanTip then scanTip = CreateFrame("GameTooltip", "ForeverRouteScanTooltip", nil, "GameTooltipTemplate") end
	scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
	local text
	if pcall(scanTip.SetHyperlink, scanTip, "unit:" .. guid) then
		local okc, mode = pcall(GetCVar, "colorblindMode")
		local line = _G["ForeverRouteScanTooltipTextLeft" .. (2 + (okc and tonumber(mode) or 0))]
		text = line and line:GetText()
	end
	if type(text) ~= "string" or text == "" or (issecretvalue and issecretvalue(text)) then
		text = nil
	else
		local levelLine = ((UNIT_LEVEL_TEMPLATE or "Level %d"):lower():gsub("%%d", "(.*)"))
		if text:lower():match(levelLine) then text = nil end
	end
	if text and text:sub(1, 1) ~= "<" then text = "<" .. text .. ">" end
	if subCount > 300 then subCache, subCount = {}, 0 end
	if not hit then subCount = subCount + 1 end
	subCache[guid] = { text or false, now }
	return text
end

-- Fonts ----------------------------------------------------------------------------------------------

-- `key`: a key of FR.FONTS, else the addon's font. For the enemy bar.
-- `flags` "SHADOW": no outline, the soft black drop shadow instead (readable and not heavy at small sizes).
local function SetFontSafe(fs, size, flags, key)
	if not FR.FONTS[key or ""] then key = nil end
	local path = FR.FontFile(true, key)
	local shadow = flags == "SHADOW"
	if shadow then flags = "" end
	if fs:SetFont(path, size, flags) == false then fs:SetFont("Fonts\\ARIALN.TTF", size, flags) end
	if shadow then
		fs:SetShadowColor(0, 0, 0, 0.9)
		fs:SetShadowOffset(1, -1)
	else
		fs:SetShadowOffset(0, 0)   -- these texts have an outline, not the thin shadow of the names
	end
end

-- The font the game draws unit names in (an addon may have replaced it), with the thin drop shadow of
-- the game's names instead of an outline.
local function SetGameFont(fs, size, flags)
	flags = flags or ""
	local path = type(UNIT_NAME_FONT) == "string" and UNIT_NAME_FONT ~= "" and UNIT_NAME_FONT or "Fonts\\FRIZQT__.TTF"
	if fs:SetFont(path, size, flags) == false then fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags) end
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
end

-- The style of the game's own names: font, size, flags and shadow, read from the name text of a friendly
-- player's plate (the reference: the game draws it), else from the game's nameplate font object, else
-- constants. "Own text" copies it, so it never has an outline or shadow of ours.
local playerStyle, lastSample = nil, 0

local function ReadFont(fs)
	if type(fs) ~= "table" or not fs.GetFont then return nil end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if not ok or type(path) ~= "string" or type(size) ~= "number" or size <= 0 then return nil end
	local st = { path = path, size = size, flags = type(flags) == "string" and flags or "" }
	local okx, ox, oy = pcall(fs.GetShadowOffset, fs)
	if okx and type(ox) == "number" and type(oy) == "number" then st.ox, st.oy = ox, oy end
	local okc, sr, sg, sb, sa = pcall(fs.GetShadowColor, fs)
	if okc and type(sr) == "number" then st.sr, st.sg, st.sb, st.sa = sr, sg, sb, sa end
	st.key = string.format("%s,%s,%s,%s,%s", path, tostring(size), st.flags, tostring(st.ox), tostring(st.oy))
	return st
end

local function GameNameStyle()
	local now = GetTime()
	if now - lastSample > 2 and C_NamePlate and C_NamePlate.GetNamePlates then
		lastSample = now
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		if ok and type(plates) == "table" then
			for _, plate in ipairs(plates) do
				local uf = plate.UnitFrame
				local unit = uf and uf.unit
				if type(unit) == "string" and not uf.FRHide and Flag(UnitIsPlayer, unit) == true
					and Flag(UnitCanAttack, "player", unit) == false then
					local st = ReadFont(uf.name or uf.Name)
					if st then playerStyle = st break end
				end
			end
		end
	end
	if playerStyle then return playerStyle end
	local st = ReadFont(_G.SystemFont_NamePlate)
	if st then
		-- The size of the nameplate font, but the file the game draws unit names in (Friz Quadrata), so the
		-- letters have the shape of the names of players.
		if type(UNIT_NAME_FONT) == "string" and UNIT_NAME_FONT ~= "" then
			st.path = UNIT_NAME_FONT
			st.key = string.format("%s,%s,%s,%s,%s", st.path, tostring(st.size), st.flags, tostring(st.ox), tostring(st.oy))
		end
		return st
	end
	local path = type(UNIT_NAME_FONT) == "string" and UNIT_NAME_FONT ~= "" and UNIT_NAME_FONT or "Fonts\\FRIZQT__.TTF"
	return { path = path, size = 12, flags = "", ox = 1, oy = -1, key = "fallback" }
end

-- The weight of the text ("Name weight"): the text gets a shadow in its own colour half a pixel to the right, which
-- thickens the strokes without the thick border of an outline. `weight` (0..1) is the opacity of that shadow, so
-- every value in between works (the offset is a whole screen pixel anyway: text is pixel-snapped). It needs no
-- second text object, which matters: the size of the names is changed every frame while the camera moves.
local FAUX_OFFSET = 0.7

local function WeightShadow(fs, r, g, b, weight)
	if weight <= 0 then return end   -- the copied shadow of the game's style stays
	fs:SetShadowColor(r, g, b, weight)
	fs:SetShadowOffset(FAUX_OFFSET, 0)
end
-- The setting "Name weight" as a number 0..1 (older versions saved "light", "medium" or "bold").
local WEIGHT_OF = { light = 0, medium = 0.5, bold = 1 }
local function NameWeight()
	local w = FR:Get("plateNameWeight")
	if type(w) == "string" then w = WEIGHT_OF[w] end
	if type(w) ~= "number" then w = 0.5 end
	return math.max(0, math.min(1, w))
end

local function ApplyStyle(fs, st, size)
	size = size or st.size
	if fs:SetFont(st.path, size, st.flags) == false then fs:SetFont("Fonts\\FRIZQT__.TTF", size, st.flags) end
	fs:SetShadowOffset(st.ox or 1, st.oy or -1)
	fs:SetShadowColor(st.sr or 0, st.sg or 0, st.sb or 0, st.sa or 1)
end

-- The skin ---------------------------------------------------------------------------------------------

local styled = {}       -- [unit token] = plate
local cfgVersion = 0     -- raised by every change of a setting: skins are laid out again

-- A FontString that has no font raises "Font not set" on SetText: every one gets a font at once.
-- Text and textures are snapped to the pixel grid by default; the names of the game are projected at sub-pixel
-- positions, so while the camera moves ours would jump by up to a pixel per frame. Switched off where the client
-- has the call.
local function NoSnap(region)
	if region.SetSnapToPixelGrid then pcall(region.SetSnapToPixelGrid, region, false) end
	if region.SetTexelSnappingBias then pcall(region.SetTexelSnappingBias, region, 0) end
end

local function NewText(parent, size)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	SetGameFont(fs, size or 9)
	NoSnap(fs)
	return fs
end

local function BuildSkin(plate)
	local s = CreateFrame("Frame", nil, plate)
	s:SetSize(BAR_W, ENEMY_H)
	s:EnableMouse(false)
	s:SetFrameLevel((plate:GetFrameLevel() or 0) + 10)

	-- Enemy and Classic plate: the bar with a 1 px edge (enemy: the colour says step enemy / target).
	s.edge = s:CreateTexture(nil, "BACKGROUND", nil, -1)
	s.edge:SetTexture(WHITE)
	s.edge:SetPoint("TOPLEFT", -1, 1)
	s.edge:SetPoint("BOTTOMRIGHT", 1, -1)

	s.bar = CreateFrame("StatusBar", nil, s)
	s.bar:EnableMouse(false)
	s.bar:SetAllPoints(s)
	s.bar:SetStatusBarTexture(WHITE)
	s.bar.bg = s.bar:CreateTexture(nil, "BACKGROUND")
	s.bar.bg:SetAllPoints()
	s.bar.bg:SetTexture(WHITE)
	s.bar.bg:SetVertexColor(0.08, 0.08, 0.09, 0.9)

	-- Depth of the enemy bar: a soft sheen over the upper half (white, fading out downwards) and a shade over the
	-- lower third (black, fading out upwards), so it looks rounded and not like a flat rectangle.
	s.shine = s.bar:CreateTexture(nil, "OVERLAY")
	s.shine:SetTexture(WHITE)
	s.shine:SetPoint("TOPLEFT", s.bar, "TOPLEFT", 0, 0)
	s.shine:SetPoint("TOPRIGHT", s.bar, "TOPRIGHT", 0, 0)
	s.shine:SetHeight(ENEMY_H / 2)
	Gradient(s.shine, 0, 0.18, 1, 1, 1)
	s.shade = s.bar:CreateTexture(nil, "OVERLAY")
	s.shade:SetTexture(WHITE)
	s.shade:SetPoint("BOTTOMLEFT", s.bar, "BOTTOMLEFT", 0, 0)
	s.shade:SetPoint("BOTTOMRIGHT", s.bar, "BOTTOMRIGHT", 0, 0)
	s.shade:SetHeight(ENEMY_H / 3)
	Gradient(s.shade, 0.25, 0, 0, 0, 0)

	-- The target: a soft halo behind the bar (instead of a hard white edge).
	s.glow = s:CreateTexture(nil, "BACKGROUND", nil, -2)
	s.glow:SetTexture(WHITE)
	s.glow:SetPoint("TOPLEFT", -4, 4)
	s.glow:SetPoint("BOTTOMRIGHT", 4, -4)
	s.glow:SetVertexColor(1, 1, 1, 0.22)

	-- Enemy: name and health % inside the bar, level above its right end.
	s.name = NewText(s.bar)
	s.pct = NewText(s.bar)
	s.level = NewText(s)

	-- Friendly NPC: the name (and <title>); with the Classic plate also a beveled frame, a level badge
	-- and a dragon.
	s.nname = NewText(s, NAME_SIZE)
	s.sub = NewText(s, NAME_SIZE)
	s.frame = CreateFrame("Frame", nil, s, BACKDROP)
	s.frame:EnableMouse(false)
	s.frame:SetFrameLevel(s:GetFrameLevel() + 2)
	s.frame:SetPoint("TOPLEFT", s, "TOPLEFT", -3, 3)
	s.frame:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 3, -3)
	if s.frame.SetBackdrop then s.frame:SetBackdrop({ edgeFile = BORDER, edgeSize = 10 }) end
	s.badge = CreateFrame("Frame", nil, s)
	s.badge:EnableMouse(false)
	s.badge:SetSize(18, 18)
	s.badge:SetFrameLevel(s:GetFrameLevel() + 4)
	s.badge.circle = s.badge:CreateTexture(nil, "BACKGROUND")
	s.badge.circle:SetTexture(FR.DIR .. "\\Textures\\Circle")
	s.badge.circle:SetAllPoints()
	s.badge.circle:SetVertexColor(0.04, 0.04, 0.06, 0.95)
	s.badge.ring = s.badge:CreateTexture(nil, "BORDER")
	s.badge.ring:SetTexture(FR.DIR .. "\\Textures\\Ring")
	s.badge.ring:SetAllPoints()
	s.badge.ring:SetVertexColor(0.85, 0.7, 0.2, 1)
	s.badge.text = NewText(s.badge)
	s.badge.text:SetPoint("CENTER", 0, 0)
	s.badge.skull = s.badge:CreateTexture(nil, "OVERLAY")
	s.badge.skull:SetTexture(FR.MARKER_ATLAS)
	s.badge.skull:SetTexCoord(FR.MarkerTexCoord(8))
	s.badge.skull:SetSize(12, 12)
	s.badge.skull:SetPoint("CENTER", 0, 0)
	s.dragon = s:CreateTexture(nil, "OVERLAY")

	-- Enemy and Classic plate: the cast bar under the bar, the spell icon to its left.
	s.cast = CreateFrame("StatusBar", nil, s)
	s.cast:EnableMouse(false)
	s.cast:SetHeight(CAST_H)
	s.cast:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -3)
	s.cast:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -3)
	s.cast:SetStatusBarTexture(WHITE)
	s.cast:SetStatusBarColor(1, 0.7, 0.1)
	s.cast.bg = s.cast:CreateTexture(nil, "BACKGROUND")
	s.cast.bg:SetAllPoints()
	s.cast.bg:SetTexture(WHITE)
	s.cast.bg:SetVertexColor(0, 0, 0, 0.7)
	s.cast.icon = s.cast:CreateTexture(nil, "OVERLAY")
	s.cast.icon:SetSize(CAST_H + 2, CAST_H + 2)
	s.cast.icon:SetPoint("RIGHT", s.cast, "LEFT", -2, 0)
	s.cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	s.cast.text = NewText(s.cast, 8)
	s.cast.text:SetPoint("CENTER")
	s.cast:Hide()

	-- All: the step's marker and count.
	s.quest = s:CreateTexture(nil, "OVERLAY")
	s.quest:SetTexture(QUEST_ICON)
	s.raid = s:CreateTexture(nil, "OVERLAY")
	s.raid:SetTexture(FR.MARKER_ATLAS)
	s.progress = NewText(s, 10)
	for _, region in ipairs({ s.edge, s.glow, s.bar.bg, s.shine, s.shade, s.cast.bg, s.cast.icon, s.quest, s.raid, s.dragon,
		s.badge.circle, s.badge.ring, s.badge.skull }) do
		NoSnap(region)
	end
	return s
end

local function HideParts(s)
	s.edge:Hide(); s.glow:Hide(); s.bar:Hide(); s.shine:Hide(); s.shade:Hide(); s.level:Hide(); s.cast:Hide()
	s.nname:Hide(); s.sub:Hide(); s.frame:Hide(); s.badge:Hide(); s.dragon:Hide()
	s.quest:Hide(); s.raid:Hide(); s.progress:Hide()
end

-- The parts that change all the time: health and cast. Cheap, no unit classification.
-- The health of a creature can be a secret value: it cannot be compared or calculated with, but a status bar takes
-- it as it is. So the bar gets the raw values; only the percentage text needs a plain number (or the game's own
-- UnitHealthPercent, which SetFormattedText accepts even when it is secret).
local function UpdateHealth(s, unit)
	local okc, cur = pcall(UnitHealth, unit)
	local okm, max = pcall(UnitHealthMax, unit)
	local plainCur, plainMax = Plain(okc and cur or nil), Plain(okm and max or nil)
	local fed = false
	if okc and okm and cur ~= nil and max ~= nil then
		if type(plainMax) == "number" and plainMax <= 0 then
			-- no health known (0 max): leave it to the fallback below
		elseif pcall(s.bar.SetMinMaxValues, s.bar, 0, max) and pcall(s.bar.SetValue, s.bar, cur) then
			fed = true
		end
	end
	if not fed then
		s.bar:SetMinMaxValues(0, 1)
		s.bar:SetValue(1)
	end
	if s.kind ~= "enemy" then s.pct:SetText("") return end

	if type(plainCur) == "number" and type(plainMax) == "number" and plainMax > 0 then
		s.pct:SetText(string.format("%d%%", math.floor(plainCur / plainMax * 100 + 0.5)))
		return
	end
	-- Secret values: ask the game for the percentage.
	local percent = _G.UnitHealthPercent
	local scale = CurveConstants and CurveConstants.ScaleTo100
	if percent then
		local ok, v = pcall(percent, unit, false, scale)
		if ok and v ~= nil then
			local plain = Plain(v)
			if type(plain) == "number" then
				if not scale then plain = plain * 100 end
				s.pct:SetText(string.format("%d%%", math.floor(plain + 0.5)))
				return
			end
			if scale and pcall(s.pct.SetFormattedText, s.pct, "%.0f%%", v) then return end
		end
	end
	s.pct:SetText("")
end

local function UpdateCast(s, unit)
	local channel = false
	local ok, name, _, icon, startMs, endMs = pcall(UnitCastingInfo, unit)
	name, icon, startMs, endMs = Plain(name), Plain(icon), Plain(startMs), Plain(endMs)
	if not ok or type(name) ~= "string" then
		channel = true
		ok, name, _, icon, startMs, endMs = pcall(UnitChannelInfo, unit)
		name, icon, startMs, endMs = Plain(name), Plain(icon), Plain(startMs), Plain(endMs)
	end
	if ok and type(name) == "string" and type(startMs) == "number" and type(endMs) == "number" and endMs > startMs then
		local now = GetTime() * 1000
		local value = channel and (endMs - now) or (now - startMs)
		s.cast:SetMinMaxValues(0, endMs - startMs)
		s.cast:SetValue(math.max(0, math.min(endMs - startMs, value)))
		s.cast.text:SetText(name)
		if icon ~= nil then s.cast.icon:SetTexture(icon); s.cast.icon:Show() else s.cast.icon:Hide() end
		s.cast:Show()
	else
		s.cast:Hide()
	end
end

-- The step's marker left of the bar, the count under it. `mode`: "quest", "raid" or "both".
local function PlaceMarkers(s, info, cur, total, mode)
	if not info or FR:Get("nameplateIcons") == false then return end
	local size = math.floor(26 * (FR:Get("nameplateScale") or 1) + 0.5)
	local first   -- the icon next to the bar: the count goes under it
	if mode == "raid" or mode == "both" then
		s.raid:SetTexCoord(FR.MarkerTexCoord(info.marker))
		s.raid:SetSize(size, size)
		s.raid:ClearAllPoints()
		s.raid:SetPoint("RIGHT", s, "LEFT", -4, 0)
		s.raid:Show()
		first = s.raid
	end
	if mode == "quest" or mode == "both" then
		s.quest:SetSize(size, size)
		s.quest:ClearAllPoints()
		if first then s.quest:SetPoint("RIGHT", first, "LEFT", -1, 0) else s.quest:SetPoint("RIGHT", s, "LEFT", -4, 0) end
		s.quest:Show()
		first = first or s.quest
	end
	if cur and total and FR:Get("plateProgress") ~= false and first then
		SetFontSafe(s.progress, 12, "SHADOW")
		s.progress:ClearAllPoints()
		s.progress:SetPoint("TOP", first, "BOTTOM", 0, 0)
		if cur >= total then s.progress:SetTextColor(0.3, 1, 0.3) else s.progress:SetTextColor(1, 1, 1) end
		s.progress:SetText(cur .. "/" .. total)
		s.progress:Show()
	end
end

-- Enemy: the bar, the marker and the count.
local function LayoutEnemy(s, plate, info, unit, name, isTarget, cur, total)
	s:ClearAllPoints()
	s:SetSize(BAR_W, ENEMY_H)
	s:SetPoint("CENTER", plate, "CENTER", 0, 0)
	s.baseScale = (FR:Get("plateScale") or 1) * (isTarget and 1.12 or 1)
	s.distScale = false   -- bars keep a constant size
	s:SetScale(s.baseScale)
	HideParts(s)
	s.hasBar = true

	-- A step enemy is teal, every other enemy has a muted colour by reaction.
	local r, g, b = BarColor(unit, info)
	s.bar:SetStatusBarColor(r, g, b)
	s.bar:Show()
	s.shine:Show()
	s.shade:Show()
	-- The thin dark edge ("Plate border"); the target also gets a soft halo, no white box.
	if FR:Get("plateBorder") ~= false then
		s.edge:SetVertexColor(0, 0, 0, 1)
		s.edge:Show()
	end
	if isTarget then s.glow:Show() end

	SetFontSafe(s.pct, 13, "SHADOW")
	s.pct:ClearAllPoints()
	s.pct:SetPoint("RIGHT", s.bar, "RIGHT", -5, 0)
	s.pct:SetTextColor(1, 1, 1)
	SetFontSafe(s.name, 13, "SHADOW")
	s.name:ClearAllPoints()
	s.name:SetPoint("LEFT", s.bar, "LEFT", 5, 0)
	s.name:SetWidth(BAR_W - 50)   -- leaves room for "100%"
	s.name:SetJustifyH("LEFT")
	s.name:SetWordWrap(false)
	s.name:SetTextColor(1, 1, 1)
	s.name:SetText(name or "")

	local level = Flag(UnitLevel, unit)
	if type(level) == "number" then
		local lr, lg, lb = LevelColor(level)
		SetFontSafe(s.level, 12, "SHADOW")
		s.level:ClearAllPoints()
		s.level:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)
		s.level:SetTextColor(lr, lg, lb)
		s.level:SetText(level > 0 and level or "??")
		s.level:Show()
	end
	SetFontSafe(s.cast.text, 10, "SHADOW")

	UpdateHealth(s, unit)
	PlaceMarkers(s, info, cur, total, FR:Get("plateMarker") or "quest")
end

-- Friendly NPC, default: only the name like the game's floating names, the <title> under it in the same
-- colour, the step icon beside the name block. No bar, no frame.
local function LayoutName(s, plate, info, unit, name, isTarget, r, g, b, sub, st)
	s:ClearAllPoints()
	local size = st.size * (FR:Get("plateNameScale") or 1.0)
	s:SetSize(200, math.ceil(size) + 2)
	-- Close above the head: the bottom of the name block at the middle of the plate, moved by the setting
	-- "Name height"; a <title> hangs under the name.
	s:SetPoint("BOTTOM", plate, "CENTER", 0, FR:Get("plateNameY") or -28)
	s.baseScale = isTarget and 1.1 or 1
	s.distScale = true    -- the name follows the camera distance (kept up to date by the 0.1 s ticker)
	plate.FRFactor = DistanceFactor(unit, LiveZoom())   -- starts at the right size; Drive eases it from here
	s:SetScale(s.baseScale * plate.FRFactor)
	HideParts(s)
	s.hasBar = false

	-- The weight: 0 = the copied style as it is, up to 1 = full faux bold (a second layer behind the text).
	local weight = NameWeight()

	ApplyStyle(s.nname, st, size)
	s.nname:ClearAllPoints()
	s.nname:SetPoint("TOP", s, "TOP", 0, 0)
	s.nname:SetTextColor(r, g, b)
	s.nname:SetText(name or "")
	s.nname:Show()
	WeightShadow(s.nname, r, g, b, weight)
	local width = s.nname:GetStringWidth() or 60
	if sub then
		ApplyStyle(s.sub, st, math.max(6, math.floor(size * 0.85 + 0.5)))
		s.sub:SetTextColor(r, g, b)
		s.sub:SetText(sub)
		s.sub:ClearAllPoints()
		s.sub:SetPoint("TOP", s.nname, "BOTTOM", 0, -1)   -- a small gap: name and <title> no longer touch
		s.sub:Show()
		WeightShadow(s.sub, r, g, b, weight)
		width = math.max(width, s.sub:GetStringWidth() or 0)
	end
	PlaceMarkers(s, info, nil, nil, "raid")   -- friendly NPCs always get their raid icon
	if s.raid:IsShown() then
		s.raid:ClearAllPoints()
		s.raid:SetPoint("RIGHT", s.nname, "CENTER", -(width / 2 + 4), 0)
	end
end

-- Friendly NPC, option: the Classic plate.
local function LayoutClassic(s, plate, info, unit, name, isTarget, r, g, b, level, class)
	s:ClearAllPoints()
	s:SetSize(CLASSIC_W, NPC_H)
	s:SetPoint("CENTER", plate, "CENTER", 0, 0)
	s.baseScale = (FR:Get("plateScale") or 1) * (isTarget and 1.1 or 1)
	s.distScale = false
	s:SetScale(s.baseScale)
	HideParts(s)
	s.hasBar = true

	s.bar:SetStatusBarColor(r, g, b)
	s.bar:Show()
	-- The beveled frame ("Plate border"); gold around a step NPC.
	if FR:Get("plateBorder") ~= false then
		if s.frame.SetBackdropBorderColor then
			if info then s.frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1) else s.frame:SetBackdropBorderColor(1, 1, 1, 1) end
		end
		s.frame:Show()
	end

	-- The name, centered above the bar.
	SetGameFont(s.nname, 12)
	s.nname:ClearAllPoints()
	s.nname:SetPoint("BOTTOM", s, "TOP", 0, 5)
	s.nname:SetTextColor(r, g, b)
	s.nname:SetText(name or "")
	s.nname:Show()

	-- Level badge at the right end of the bar (a skull for a boss level), a dragon for elite / rare.
	if type(level) == "number" then
		s.badge:ClearAllPoints()
		s.badge:SetPoint("CENTER", s, "RIGHT", 2, 0)
		if level < 0 then
			s.badge.skull:Show()
			s.badge.text:SetText("")
		else
			local lr, lg, lb = LevelColor(level)
			SetGameFont(s.badge.text, 9)
			s.badge.text:SetTextColor(lr, lg, lb)
			s.badge.text:SetText(level)
			s.badge.skull:Hide()
		end
		s.badge:Show()
		local atlas
		if class == "elite" or class == "worldboss" then atlas = "nameplates-icon-elite-gold"
		elseif class == "rare" or class == "rareelite" then atlas = "nameplates-icon-elite-silver" end
		if atlas and C_Texture and C_Texture.GetAtlasInfo then
			local ok, found = pcall(C_Texture.GetAtlasInfo, atlas)
			if ok and found then
				s.dragon:SetAtlas(atlas)
				s.dragon:SetSize(16, 16)
				s.dragon:ClearAllPoints()
				s.dragon:SetPoint("LEFT", s.badge, "RIGHT", 0, 0)
				s.dragon:Show()
			end
		end
	end
	SetGameFont(s.cast.text, 8)

	UpdateHealth(s, unit)
	PlaceMarkers(s, info, nil, nil, "raid")   -- friendly NPCs always get their raid icon
end

-- The game's own plate -----------------------------------------------------------------------------------

-- Hides a part of the game's plate. Alpha 0 alone does not hold: the game drives the alpha of a plate
-- through SetAlphaFromBoolean and shows the frame again when a plate is reused. So hooks put the hiding
-- back, and `hard` also calls Hide() (not in combat: the plate frame can be protected, then alpha 0 and the
-- next OnShow have to do).
local function ReHide(self)
	if not self.FRHide then return end
	pcall(self.SetAlpha, self, 0)
	if self.FRHard and self.Hide and not InCombat() then pcall(self.Hide, self) end
end

local function HideFrame(obj, hard)
	if type(obj) ~= "table" or not obj.SetAlpha then return end
	if not obj.FRHooked then
		obj.FRHooked = true
		pcall(hooksecurefunc, obj, "SetAlpha", function(self, alpha)
			if self.FRHide and alpha ~= 0 then pcall(self.SetAlpha, self, 0) end
		end)
		if obj.SetAlphaFromBoolean then
			pcall(hooksecurefunc, obj, "SetAlphaFromBoolean", function(self)
				if self.FRHide then pcall(self.SetAlpha, self, 0) end
			end)
		end
		if hard and obj.HookScript then pcall(obj.HookScript, obj, "OnShow", ReHide) end
	end
	obj.FRHide, obj.FRHard = true, hard and true or false
	pcall(obj.SetAlpha, obj, 0)
	if hard and obj.Hide and not InCombat() then pcall(obj.Hide, obj) end
end

local function RestoreFrame(obj)
	if type(obj) ~= "table" or not obj.FRHide then return end
	obj.FRHide = false
	pcall(obj.SetAlpha, obj, 1)
	if obj.FRHard and obj.Show and not InCombat() then pcall(obj.Show, obj) end
end

-- Parts that can ignore the alpha of their parent (a border or highlight would stay visible).
local PARTS = { "HealthBarsContainer", "castBar", "CastBar", "name", "Name", "selectedBorder", "border" }

-- Calls func on every part of the game's plate that may be drawn: the known parts, all child frames and all
-- regions (so a border or highlight with an unexpected name cannot stay).
local function EachPart(uf, func)
	for _, key in ipairs(PARTS) do func(uf[key]) end
	local okc, children = pcall(function() return { uf:GetChildren() } end)
	if okc then for _, child in ipairs(children) do func(child) end end
	local okr, regions = pcall(function() return { uf:GetRegions() } end)
	if okr then for _, region in ipairs(regions) do func(region) end end
end

-- mode: nil = the whole plate (enemy bar, Classic plate); "full" = the whole plate and every part of it
-- (our own text); "game" = only the health bar container: the game draws the name itself.
local function HideBlizzard(plate, mode)
	local uf = plate.UnitFrame
	if not uf then return end
	plate.FRTouched = true
	if mode == "game" then
		-- The bar with its border; the name text is not part of it and stays the game's.
		if uf.HealthBarsContainer then
			HideFrame(uf.HealthBarsContainer, false)
		else
			HideFrame(uf.healthBar, false)
			HideFrame(uf.border, false)
		end
		HideFrame(uf.selectedBorder, false)
		return
	end
	HideFrame(uf, true)
	if mode == "full" then
		EachPart(uf, function(part) HideFrame(part, false) end)
	else
		for _, key in ipairs(PARTS) do HideFrame(uf[key], false) end
	end
end

-- Names whose plate went away a moment ago (zooming moves creatures in and out of the plate range, which is
-- measured from the camera): when such a name comes back it appears at once and is not laid out again.
local recentGone = {}   -- [name] = time

-- Undoes whatever was done to the game's plate and hides our skin.
local function Restore(plate)
	local skin = plate.FRSkin
	if skin then
		local now = GetTime()
		if skin:IsShown() and skin.lastName then recentGone[skin.lastName] = now end
		skin:Hide()
		skin.fadeStart = nil
		skin:SetAlpha(1)
		skin.goneAt = now   -- see ApplyRaw: back within a second = the same look, nothing is redone
	end
	plate.FRMode = nil
	if not plate.FRTouched then return end
	plate.FRTouched = false
	local uf = plate.UnitFrame
	if not uf then return end
	if plate.FRNative then
		plate.FRNative = false
		NameOnly(uf, false)
		ScaleName(uf, 1)
	end
	RestoreFrame(uf)
	EachPart(uf, RestoreFrame)
end

local function Remove(unit)
	local plate = styled[unit]
	styled[unit] = nil
	distCache[unit] = nil   -- the token can belong to another creature next time
	if plate then Restore(plate) end
end

local function ApplyRaw(unit)
	if type(unit) ~= "string" then return end
	local plate = PlateFor(unit)
	if not plate then Remove(unit) return end
	local cat, info = Category(unit)
	if not cat then
		Remove(unit)
		Restore(plate)   -- the plate may have been skinned for another unit before
		return
	end
	-- "enemy", "dead", or for a friendly NPC "own" (our text), "game" (the game's text), "classic".
	local mode = cat == "npc" and NpcMode() or cat
	if plate.FRMode ~= mode then
		if plate.FRMode ~= nil then Restore(plate) end   -- undo what the old mode did to the game's plate
		plate.FRMode = mode
	end

	-- "Game text": the game draws the name in its own name-only mode; we only keep the bar out of it.
	if mode == "game" then
		local uf = plate.UnitFrame
		if not uf then return end
		HookNative()
		plate.FRNative = true
		NameOnly(uf, true)
		ScaleName(uf, (FR:Get("plateNameScale") or 1.0) * DistanceFactor(unit, LiveZoom()))
		HideBlizzard(plate, "game")
		if plate.FRSkin then plate.FRSkin:Hide() end
		styled[unit] = plate
		return
	end

	local s = plate.FRSkin
	if not s then
		s = BuildSkin(plate)
		plate.FRSkin = s
	end

	-- What this unit looks like, and a key that changes when that changes.
	local name = FR.SafeUnitName(unit) or ""
	local isTarget = Flag(UnitIsUnit, unit, "target") == true
	local style = cat == "enemy" and "enemy" or (mode == "classic" and "classic" or "name")
	local cur, total, r, g, b, level, class, sub, nameStyle
	local extraKey = ""
	if cat == "dead" then
		style = "dead"
	elseif style == "enemy" then
		cur, total = Progress(info)
		extraKey = string.format("%s,%s,%s,%s,%s", tostring(cur), tostring(total), tostring(FR:Get("plateMarker")),
			tostring(FR:Get("plateProgress")), tostring(FR:Get("plateBorder")))
	else
		r, g, b = ReactionColor(unit, 0, 1, 0)
		if style == "classic" then
			level, class = Flag(UnitLevel, unit), Flag(UnitClassification, unit)
		else
			sub = FR.UnitSubtitle(unit)
			nameStyle = GameNameStyle()
		end
		extraKey = string.format("%.2f,%.2f,%.2f,%s,%s,%s,%s,%s,%s,%s", r, g, b, tostring(level), tostring(class), sub or "",
			tostring(FR:Get("plateBorder")), tostring(FR:Get("plateNameY")), nameStyle and nameStyle.key or "",
			tostring(FR:Get("plateNameScale")) .. "," .. string.format("%.2f", NameWeight()))
	end
	local signature = table.concat({ cfgVersion, style, name, info and info.marker or 0, isTarget and 1 or 0, extraKey }, "|")

	-- A layout that failed is not tried again for 5 s (and the game's plate stays); a changed key tries at once.
	if s.failed == signature and GetTime() - (s.failedAt or 0) < 5 then return end

	-- The plate was taken away and is back: after a second or more it is a new creature (laid out again),
	-- within a second it is the same name and nothing is redone.
	if s.goneAt then
		if GetTime() - s.goneAt > 1 then s.unit = nil end
		s.goneAt = nil
	end

	-- Hide the game's plate and note the unit first: whatever goes wrong below, the plate is never left
	-- half hidden and the unit is looked at again.
	HideBlizzard(plate, style == "name" and "full" or nil)
	styled[unit] = plate

	if style == "dead" then
		-- A corpse keeps its plate for a while: show nothing (and not the game's plate either).
		s:Hide()
		s.signature, s.unit, s.kind, s.hasBar = nil, unit, nil, false
		return
	end

	if s.signature ~= signature or s.unit ~= unit then
		local newUnit = s.unit ~= unit   -- a plate that appears fades in (not a redraw after a setting)
		s.kind = cat
		local ok, err
		if style == "enemy" then
			ok, err = pcall(LayoutEnemy, s, plate, info, unit, name, isTarget, cur, total)
		elseif style == "classic" then
			ok, err = pcall(LayoutClassic, s, plate, info, unit, name, isTarget, r, g, b, level, class)
		else
			ok, err = pcall(LayoutName, s, plate, info, unit, name, isTarget, r, g, b, sub, nameStyle)
		end
		if not ok then
			s.signature, s.failed, s.failedAt = nil, signature, GetTime()
			Restore(plate)   -- the game's plate instead of a blank one
			error(err, 0)    -- reported once by FR.Safe
		end
		s.signature, s.unit, s.failed = signature, unit, nil
		s.lastName = name
		-- Only a name that really appears for the first time fades in, not one that was just there.
		local gone = recentGone[name]
		if newUnit and not (gone and GetTime() - gone < 3) then
			s.fadeStart = GetTime()
			s:SetAlpha(0)
		end
	end
	if s.hasBar then
		UpdateHealth(s, unit)
		UpdateCast(s, unit)
	end
	s:Show()
end

-- An error on one plate shows once in the chat and never stops the other plates or the addon.
local function Apply(unit) return FR.Safe("name plate", ApplyRaw, unit) end

local function UnitOfPlate(plate)
	return plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
end

-- Every plate in view.
local function ForEachPlate(func)
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then return end
	for _, plate in ipairs(plates) do
		local unit = UnitOfPlate(plate)
		if type(unit) == "string" then func(unit) end
	end
end

-- Draws every plate in view again (a setting or the step changed).
function FR:RefreshPlates()
	cfgVersion = cfgVersion + 1
	local seen = {}
	ForEachPlate(function(unit)
		seen[unit] = true
		Apply(unit)
	end)
	for unit in pairs(styled) do
		if not seen[unit] then Remove(unit) end
	end
end

-- /fr plates: one line about the custom plates.
function FR:PlatesStatus()
	local count = 0
	for _ in pairs(styled) do count = count + 1 end
	return string.format("%s: %s | ForeverRoute plates: %d", FR.L["Custom name plates"],
		FR:Get("customPlates") and FR.L["on"] or FR.L["off"], count)
end

-- /fr plates dump: what the game's plate is made of (for when a part of it still shows). The game's own
-- plate code is not readable, so this lists the real structure of the plate of the target (else the first
-- plate in view).
function FR:DumpPlate()
	local plate = UnitExists("target") and PlateFor("target") or nil
	if not plate and C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, list = pcall(C_NamePlate.GetNamePlates)
		plate = ok and type(list) == "table" and list[1] or nil
	end
	local uf = plate and plate.UnitFrame
	if not uf then self:Print("No name plate in view: target a creature that has one."); return end
	local function out(text) self:Print("  " .. text) end
	local function kind(o)
		if type(o) ~= "table" then return type(o) end
		return o.GetObjectType and o:GetObjectType() or "table"
	end
	local function alpha(o)
		local ok, a = pcall(o.GetAlpha, o)
		local ig = o.IsIgnoringParentAlpha and select(2, pcall(o.IsIgnoringParentAlpha, o))
		return string.format("alpha %s%s", tostring(ok and a or "?"), ig and ", ignores parent alpha" or "")
	end
	self:Print("Plate of " .. tostring(plate.namePlateUnitToken or "?") .. ": UnitFrame " .. kind(uf) .. ", " .. alpha(uf)
		.. ", shown " .. tostring(uf:IsShown()) .. ", ForeverRoute hides it: " .. tostring(uf.FRHide == true))
	local keys = {}
	for _, key in ipairs({ "name", "Name", "healthBar", "HealthBarsContainer", "castBar", "CastBar", "border",
		"selectedBorder", "BuffFrame", "optionTable", "RaidTargetFrame", "softTargetFrame" }) do
		if uf[key] ~= nil then keys[#keys + 1] = key .. "=" .. kind(uf[key]) end
	end
	out("fields: " .. table.concat(keys, ", "))
	local function scales(frame, fs)
		local function sc(o, method)
			if type(o) ~= "table" or not o[method] then return "-" end
			local ok, v = pcall(o[method], o)
			return ok and type(v) == "number" and string.format("%.3f", v) or "?"
		end
		return string.format("scale plate %s, UnitFrame %s, name effective %s", sc(frame, "GetScale"),
			sc(frame.UnitFrame, "GetScale"), sc(fs, "GetEffectiveScale"))
	end
	out(scales(plate, uf.name or uf.Name))
	do
		-- What the size of friendly NPC names is computed from: the camera zoom and the distance to the creature.
		local punit = plate.namePlateUnitToken
		local dist = type(punit) == "string" and UnitDistance(punit) or nil
		local zoom = CameraZoom()
		out(string.format("camera zoom: %s | unit distance: %s | factor: %s | skin scale: %s",
			zoom and string.format("%.1f yd", zoom) or "not available",
			dist and string.format("%.1f yd", dist) or "not available (only the zoom counts)",
			type(punit) == "string" and string.format("%.2f", DistanceFactor(punit, LiveZoom())) or "?",
			plate.FRSkin and string.format("%.2f", plate.FRSkin:GetScale()) or "-"))
	end
	do
		local st = GameNameStyle()
		out("Own text copies: " .. tostring(st.key) .. (playerStyle and " (from a friendly player's plate)" or " (nameplate font object)"))
	end
	do
		local fs = uf.name or uf.Name
		if type(fs) == "table" and fs.GetTextScale then
			local okt, ts = pcall(fs.GetTextScale, fs)
			out("name text scale: " .. tostring(okt and ts or "?") .. " (ForeverRoute set: " .. tostring(fs.FRScaled == true) .. ")")
		end
	end
	-- The reference: a friendly player's plate in view, drawn by the game.
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local okp, list = pcall(C_NamePlate.GetNamePlates)
		for _, other in ipairs(okp and type(list) == "table" and list or {}) do
			local ouf = other.UnitFrame
			local ounit = ouf and ouf.unit
			if other ~= plate and type(ounit) == "string" and Flag(UnitIsPlayer, ounit) == true
				and Flag(UnitCanAttack, "player", ounit) == false then
				local st = ReadFont(ouf.name or ouf.Name)
				out("reference (friendly player): " .. (st and (st.key .. ", shadow colour "
					.. tostring(st.sr) .. "," .. tostring(st.sg) .. "," .. tostring(st.sb) .. "," .. tostring(st.sa)) or "no name text")
					.. " | " .. scales(other, ouf.name or ouf.Name))
				break
			end
		end
	end
	local nameFs = uf.name or uf.Name
	if type(nameFs) == "table" and nameFs.GetFont then
		local okf, path, size, flags = pcall(nameFs.GetFont, nameFs)
		out(string.format("name font: %s, size %s, flags '%s'; UNIT_NAME_FONT = %s", tostring(okf and path or "?"),
			tostring(size), tostring(flags), tostring(UNIT_NAME_FONT)))
	else
		out("UNIT_NAME_FONT = " .. tostring(UNIT_NAME_FONT))
	end
	local n = 0
	for i, child in ipairs({ uf:GetChildren() }) do
		n = n + 1
		if n > 14 then out("... more children"); break end
		local shown = child.IsShown and child:IsShown()
		out(string.format("child %d: %s '%s' shown=%s, %s", i, kind(child), tostring(child.GetName and child:GetName() or ""),
			tostring(shown), alpha(child)))
	end
	n = 0
	for i, region in ipairs({ uf:GetRegions() }) do
		n = n + 1
		if n > 14 then out("... more regions"); break end
		local shown = region.IsShown and region:IsShown()
		out(string.format("region %d: %s shown=%s, %s", i, kind(region), tostring(shown), alpha(region)))
	end
end

-- Events ---------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_ADDED")
pcall(ev.RegisterEvent, ev, "NAME_PLATE_UNIT_REMOVED")
pcall(ev.RegisterEvent, ev, "PLAYER_TARGET_CHANGED")
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "UNIT_FLAGS")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")

ev:SetScript("OnEvent", function(_, event, arg1)
	if event == "NAME_PLATE_UNIT_ADDED" then
		Apply(arg1)
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		if type(arg1) == "string" then Remove(arg1) end   -- by the token: the creature's values may be unreadable
	elseif event == "PLAYER_TARGET_CHANGED" then
		for unit in pairs(styled) do Apply(unit) end
	elseif event == "UNIT_FLAGS" then
		if type(arg1) == "string" and styled[arg1] then Apply(arg1) end
	elseif event == "PLAYER_ENTERING_WORLD" then
		HookNative()
		FR:RefreshPlates()
		-- The CVars are read once the world is up.
		if C_Timer and C_Timer.After then
			C_Timer.After(1, function() EnsureRange(); FR:ApplyNpcNames() end)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if npcNamesPending then FR:ApplyNpcNames() end
	end
end)

if C_Timer and C_Timer.NewTicker then
	-- Every plate in view, not only the ones we know: deaths, quest progress, a change of reaction, a plate
	-- that was missed after an error or a change of the game's name plate settings.
	C_Timer.NewTicker(0.5, function()
		ForEachPlate(Apply)
		local now = GetTime()
		for name, t in pairs(recentGone) do
			if now - t > 3 then recentGone[name] = nil end
		end
	end)
	-- Health and cast move fast; this only touches the bars.
	C_Timer.NewTicker(0.1, function()
		FR.Safe("name plate", function()
			for unit, plate in pairs(styled) do
				local s = plate.FRSkin
				if s and s:IsShown() and s.hasBar then
					UpdateHealth(s, unit)
					UpdateCast(s, unit)
				end
			end
		end)
	end)
end

-- The size of the names follows the camera (see DistanceFactor), which moves every frame: so it is updated every
-- frame (a ticker would make it jump ten times a second while the game's own names glide). The zoom is run
-- through a critically damped filter (about 100 ms) so a stepwise reading does not show as jumps; the distance
-- to the creature is read four times a second, so the factor is eased towards its target. When nothing changes
-- nothing is touched (no re-rendering of the text). The same loop fades in a plate that really appears for the
-- first time.

local zoomTest   -- set by /fr plates zoomtest: { start, frames = {...} }

-- Is the frame on the screen (with a margin)? Names behind or beside the camera need no scale update.
local function OnScreen(frame)
	local x, y = frame:GetCenter()
	if not x then return false end
	local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	x, y = x * k, y * k
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	return x > -150 and x < w + 150 and y > -150 and y < h + 150
end

local function Drive(dt)
	local t0 = debugprofilestop and debugprofilestop() or 0
	local slow = dt > 0.025       -- the frame is already slow: the far names wait for the next frame
	local scaled, skipped = 0, 0
	dt = math.min(dt, 0.1)
	local rawZoom = CameraZoom()
	if rawZoom then
		if not zoomPos then
			zoomPos, zoomVel = rawZoom, 0
		else
			-- Critically damped step response with omega = 20 (exact solution, stable for any dt).
			local w = 20
			local x = zoomPos - rawZoom
			local c = zoomVel + w * x
			local e = math.exp(-w * dt)
			zoomPos = rawZoom + (x + c * dt) * e
			zoomVel = (zoomVel - w * c * dt) * e
		end
	else
		zoomPos, zoomVel = nil, nil
	end
	local nameScale = FR:Get("plateNameScale") or 1.0
	local now = GetTime()
	local ease = math.min(1, dt * 8)
	local sample
	for unit, plate in pairs(styled) do
		local s = plate.FRSkin
		if s and s.fadeStart then   -- a new name fades in over a quarter of a second
			local t = (now - s.fadeStart) / 0.25
			if t >= 1 then
				s.fadeStart = nil
				s:SetAlpha(1)
			else
				s:SetAlpha(t)
			end
		end
		if plate.FRNative or (s and s.distScale and s:IsShown()) then
			local target = DistanceFactor(unit, zoomPos or rawZoom)
			local cur = plate.FRFactor or target
			if cur ~= target then
				cur = cur + (target - cur) * ease
				if math.abs(target - cur) < 0.002 * target then cur = target end
			end
			plate.FRFactor = cur
			sample = sample or cur
			local frame = plate.FRNative and plate or s
			if (slow and cur < 0.6) or not OnScreen(frame) then
				skipped = skipped + 1   -- not seen / not now: it gets its size when it is
			elseif plate.FRNative then
				scaled = scaled + 1
				ScaleName(plate.UnitFrame, nameScale * cur)
			else
				local want = (s.baseScale or 1) * cur
				if math.abs(s:GetScale() - want) > want * 0.005 then
					s:SetScale(want)
					scaled = scaled + 1
				end
			end
		end
	end
	if zoomTest then
		local n = #zoomTest.frames + 1
		zoomTest.frames[n] = { dt = dt, raw = rawZoom, smooth = zoomPos, factor = sample, scaled = scaled, skipped = skipped,
			cost = debugprofilestop and (debugprofilestop() - t0) or 0 }
		if now - zoomTest.start >= 4 then
			local frames = zoomTest.frames
			zoomTest = nil
			local count, total = #frames, 0
			local dmin, dmax, distinct, jumpRaw, jumpSmooth, jumpFactor = 1e9, 0, {}, 0, 0, 0
			local nDistinct, sumScaled, sumSkipped, sumCost, maxCost = 0, 0, 0, 0, 0
			for i, f in ipairs(frames) do
				total = total + f.dt
				sumScaled, sumSkipped, sumCost = sumScaled + f.scaled, sumSkipped + f.skipped, sumCost + f.cost
				maxCost = math.max(maxCost, f.cost)
				dmin, dmax = math.min(dmin, f.dt), math.max(dmax, f.dt)
				if f.raw then
					local key = string.format("%.4f", f.raw)
					if not distinct[key] then distinct[key] = true; nDistinct = nDistinct + 1 end
				end
				local prev = frames[i - 1]
				if prev then
					if f.raw and prev.raw then jumpRaw = math.max(jumpRaw, math.abs(f.raw - prev.raw)) end
					if f.smooth and prev.smooth then jumpSmooth = math.max(jumpSmooth, math.abs(f.smooth - prev.smooth)) end
					if f.factor and prev.factor then jumpFactor = math.max(jumpFactor, math.abs(f.factor - prev.factor)) end
				end
			end
			FR:Print(string.format("Zoom test: %d frames in %.1f s (%.0f FPS), frame time min/avg/max %.1f / %.1f / %.1f ms",
				count, total, count / math.max(total, 0.001), dmin * 1000, total / math.max(count, 1) * 1000, dmax * 1000))
			FR:Print(string.format("  zoom reading: %d different values in %d frames, largest jump between two frames %.3f yd; "
				.. "after the filter %.3f yd; largest factor jump %.4f", nDistinct, count, jumpRaw, jumpSmooth, jumpFactor))
			FR:Print(string.format("  our driver: %.2f ms per frame on average (max %.2f ms); names scaled per frame %.1f, skipped (off screen / slow frame) %.1f",
				sumCost / math.max(count, 1), maxCost, sumScaled / math.max(count, 1), sumSkipped / math.max(count, 1)))
		end
	end
end

function FR:ZoomTest()
	zoomTest = { start = GetTime(), frames = {} }
	self:Print("Zoom test: zoom the camera in and out with the mouse wheel for the next 4 seconds ...")
end

-- /fr plates perf: how much frame time each addon needs, from the game's own addon profiler (no CVar needed).
-- Shows whether ForeverRoute matters at all when the picture is choppy.
function FR:PerfReport()
	local P = C_AddOnProfiler
	if not (P and P.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then
		self:Print("This client has no addon profiler (C_AddOnProfiler).")
		return
	end
	local function metric(name, kind)
		local ok, v = pcall(P.GetAddOnMetric, name, kind)
		v = ok and Plain(v) or nil
		return type(v) == "number" and v or nil
	end
	local recent, peak = Enum.AddOnProfilerMetric.RecentAverageTime, Enum.AddOnProfilerMetric.PeakTime
	local count = (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns()) or (GetNumAddOns and GetNumAddOns()) or 0
	local list = {}
	for i = 1, count do
		local info = C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(i) or (GetAddOnInfo and GetAddOnInfo(i))
		local name = type(info) == "table" and info.name or info
		if type(name) == "string" then
			local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)) or (IsAddOnLoaded and IsAddOnLoaded(name))
			local avg = loaded and metric(name, recent) or nil
			if avg then list[#list + 1] = { name = name, avg = avg, peak = metric(name, peak) or 0 } end
		end
	end
	table.sort(list, function(a, b) return a.avg > b.avg end)
	local own
	for _, e in ipairs(list) do if e.name == "ForeverRoute" then own = e end end
	local fps = GetFramerate and GetFramerate() or 0
	self:Print(string.format("Frame time per addon (average of the last moments, %.0f FPS):", fps))
	if own then
		self:Print(string.format("  ForeverRoute: %.2f ms average, %.2f ms peak", own.avg, own.peak))
	else
		self:Print("  ForeverRoute: no value")
	end
	for i = 1, math.min(5, #list) do
		self:Print(string.format("  #%d %s: %.2f ms average, %.2f ms peak", i, list[i].name, list[i].avg, list[i].peak))
	end
end
local driver, driverFailed = CreateFrame("Frame"), false
driver:SetScript("OnUpdate", function(_, dt)
	if next(styled) == nil then return end
	if not pcall(Drive, dt) and not driverFailed then
		driverFailed = true
		FR.Safe("name plate", Drive, dt)   -- reports the error once
	end
end)
