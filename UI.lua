-- Guide window, top to bottom:
--   step cards             - floating above, the current step at the bottom
--   guide bar              - guide name, progress, click = guide menu
--   step list              - every step of the guide, scrollable
--   footer                 - settings, step counter, resize grip
-- Flat, modern look: solid panels, one-pixel borders, one accent colour.
local _, ns = ...
local FR = ns.FR

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Themes ------------------------------------------------------------------------------

local function RGB(r, g, b) return { r / 255, g / 255, b / 255 } end
local THEMES = {
	default = { name = "Navy", bg = RGB(16, 18, 26), row = RGB(25, 28, 39), hl = RGB(36, 41, 57), accent = { 0.36, 0.64, 1.0 } },
	horde   = { name = "Red",  bg = RGB(24, 14, 16), row = RGB(36, 21, 24), hl = RGB(56, 31, 35), accent = { 1.0, 0.38, 0.36 } },
	gold    = { name = "Gold", bg = RGB(24, 20, 13), row = RGB(36, 30, 19), hl = RGB(56, 46, 28), accent = { 1.0, 0.74, 0.28 } },
	dark    = { name = "Dark", bg = RGB(16, 16, 17), row = RGB(26, 26, 28), hl = RGB(40, 40, 43), accent = { 0.82, 0.82, 0.86 } },
}
FR.THEMES = THEMES
FR.THEME_ORDER = { "default", "horde", "gold", "dark" }

local C = {
	text = { 0.93, 0.94, 0.96 },
	dim  = { 0.55, 0.58, 0.65 },
	tip  = { 0.85, 0.80, 0.60 },
	edge = { 1, 1, 1, 0.08 },
}
FR.colors = C

-- Gold Assistant mode always wears the gold theme (RestedXP does the same).
local function Theme()
	if FR.IsGoldMode and FR:IsGoldMode() then return THEMES.gold end
	return THEMES[FR:Get("theme")] or THEMES.default
end
FR.Theme = Theme

-- Fonts ------------------------------------------------------------------------
-- Bundled screen fonts (SIL Open Font License, see Fonts\OFL-*.txt) plus the
-- game's own. Each has a regular and a bold file; the bold one is used for
-- headings, labels and map numbers.

local GAME_FALLBACK = "Fonts\\ARIALN.TTF"
local FONT_DIR = FR.DIR .. "\\Fonts\\"
FR.FONT_ORDER = { "opensans", "fira", "inter", "arialn", "friz" }
FR.FONTS = {
	opensans = { name = "Open Sans", FONT_DIR .. "OpenSans-Medium.ttf", FONT_DIR .. "OpenSans-SemiBold.ttf" },
	fira     = { name = "Fira Sans", FONT_DIR .. "FiraSans-Medium.ttf", FONT_DIR .. "FiraSans-SemiBold.ttf" },
	inter    = { name = "Inter", FONT_DIR .. "Inter-Medium.ttf", FONT_DIR .. "Inter-SemiBold.ttf" },
	arialn   = { name = "Arial Narrow", "Fonts\\ARIALN.TTF", "Fonts\\ARIALN.TTF" },
	friz     = { name = "Friz Quadrata", "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF" },
}

-- File of the chosen font (or of the given key).
function FR.FontFile(bold, key)
	-- A Chinese client: the bundled fonts have no Chinese characters, the game's own font has.
	if FR.ClientLanguage and FR.ClientLanguage() == "zhCN" and STANDARD_TEXT_FONT then return STANDARD_TEXT_FONT end
	local f = FR.FONTS[key or FR:Get("font")] or FR.FONTS.opensans
	return bold and f[2] or f[1]
end

-- Pixel-perfect drawing ------------------------------------------------------------
-- The guide window (and the arrow) get a scale at which one UI unit is exactly
-- one screen pixel times the "Scale" setting. With the game's own UI scale
-- most positions would otherwise fall between pixels and small text blurs.

-- Screen pixels per UI unit of frames on UIParent.
local function UIPixels()
	local physH = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 768
	local eff = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	local k = (eff or 1) * (physH or 768) / 768
	if not k or k <= 0 then k = 1 end
	return k
end
FR.UIPixels = UIPixels

-- SetScale value for a pixel-perfect frame on UIParent.
function FR.PixelScale(extra) return (extra or 1) / UIPixels() end

-- Screen pixels per UI unit inside the guide window.
local function PixelFactor() return FR:Get("scale") or 1 end
FR.PixelFactor = PixelFactor

-- Rounds a size or offset to whole screen pixels.
local function Snap(v)
	local k = PixelFactor()
	return math.floor(v * k + 0.5) / k
end
FR.Snap = Snap

-- Font objects by where they are used:
--   window - guide window, follows font size and font choice
--   bar    - same, on frames without the pixel scale (active targets / items)
--   arrow  - waypoint bar: fixed size (the bar has its own size setting)
--   ui     - settings window: fixed font and size
local fonts = {}
local function MakeFont(name, delta, space, bold)
	local f = CreateFont(name)
	fonts[#fonts + 1] = { obj = f, delta = delta, space = space or "window", bold = bold }
	return f
end
FR.fontTitle = MakeFont("ForeverRouteFontTitle", 1, nil, true)
FR.fontBody = MakeFont("ForeverRouteFontBody", 0)
FR.fontSmall = MakeFont("ForeverRouteFontSmall", -1)
FR.fontLabel = MakeFont("ForeverRouteFontLabel", -1, nil, true)
FR.fontBar = MakeFont("ForeverRouteFontBar", -1, "bar", true)
FR.fontArrow = MakeFont("ForeverRouteFontArrow", 0, "arrow")
FR.fontArrowBold = MakeFont("ForeverRouteFontArrowBold", 0, "arrow", true)
FR.fontArrowSmall = MakeFont("ForeverRouteFontArrowSmall", -1, "arrow", true)
FR.fontUITitle = MakeFont("ForeverRouteFontUITitle", 14, "ui", true)
FR.fontUIBody = MakeFont("ForeverRouteFontUIBody", 13, "ui")
FR.fontUISmall = MakeFont("ForeverRouteFontUISmall", 11, "ui")

local warnedFont = false

-- Sizes in whole screen pixels. No shadow: on the solid panels it only
-- makes the letters look washed out.
function FR:ApplyFonts()
	local base = self:Get("fontSize") or 11
	for _, f in ipairs(fonts) do
		local k, px
		if f.space == "window" then
			k, px = PixelFactor(), base + f.delta
			px = px * k
		elseif f.space == "arrow" then
			k = self:Get("arrowScale") or 1
			px = (base + f.delta) * k   -- same pixel size as the guide window text
		elseif f.space == "bar" then
			-- Active items / targets: one unit is one screen pixel.
			k, px = 1, base + f.delta
		else
			k = UIPixels()
			px = (f.space == "ui") and f.delta or base + f.delta
		end
		px = math.max(8, math.floor(px + 0.5))
		local file = FR.FontFile(f.bold, f.space == "ui" and "opensans" or nil)
		-- Only an explicit false means failure (some clients return nothing).
		if f.obj:SetFont(file, px / k, "") == false then
			-- New files are only found after restarting the game.
			f.obj:SetFont(GAME_FALLBACK, px / k, "")
			if not warnedFont and ForeverRouteDB and file ~= GAME_FALLBACK then
				warnedFont = true
				C_Timer.After(3, function() FR:Print(FR.L["The font could not be loaded. Please restart the game once (new files are only found after a restart)."]) end)
			end
		end
		f.obj:SetShadowOffset(0, 0)
		f.obj:SetShadowColor(0, 0, 0, 0)
	end
	if self.RefreshMapFonts then self:RefreshMapFonts() end
end
FR:ApplyFonts()

-- Skin helpers ------------------------------------------------------------------

local skinned = {}   -- frame -> colour key, re-coloured when the theme changes
local accents = {}   -- texture -> alpha, tinted with the theme's accent colour

-- Flat panel with a one-pixel hairline border (true = no border).
local function Skin(f, key, noBorder)
	if not f.SetBackdrop then return end
	local px = 1 / (type(f.pixelUnit) == "number" and f.pixelUnit or PixelFactor())
	if noBorder then
		f:SetBackdrop({ bgFile = WHITE })
	else
		f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = px,
			insets = { left = px, right = px, top = px, bottom = px } })
		f:SetBackdropBorderColor(C.edge[1], C.edge[2], C.edge[3], C.edge[4])
	end
	skinned[f] = key or "bg"
	local c = Theme()[key or "bg"]
	f:SetBackdropColor(c[1], c[2], c[3], FR:Get("alpha"))
end
FR.Skin = Skin

-- A texture in the accent colour (accent bars, progress, step label).
local function Accent(tex, alpha)
	accents[tex] = alpha or 1
	local a = Theme().accent
	if tex.SetVertexColor then tex:SetVertexColor(a[1], a[2], a[3], alpha or 1)
	else tex:SetTextColor(a[1], a[2], a[3], alpha or 1) end
end
FR.Accent = Accent

local function ReSkin()
	local a = FR:Get("alpha")
	for f, key in pairs(skinned) do
		local c = Theme()[key]
		if c then f:SetBackdropColor(c[1], c[2], c[3], a) end
	end
	for t, alpha in pairs(accents) do Accent(t, alpha) end
end

-- Coloured strip (accent bar, progress fill, separators).
local function Bar(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(WHITE)
	return t
end

local function Text(parent, font, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(font or FR.fontBody)
	fs:SetJustifyH("LEFT")
	return fs
end
FR.MakeText = Text

local function Tooltip(owner, lines, anchor)
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	for i, l in ipairs(lines) do
		if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1, true) end
	end
	GameTooltip:Show()
end
FR.ShowTooltip = Tooltip

local function Strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end

local function IconButton(parent, tex, size, tip, crop)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(tex)
	if crop then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
	b.icon:SetVertexColor(0.85, 0.85, 0.85)
	b:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		if tip then
			local lines = {}
			for i, key in ipairs(tip) do lines[i] = FR.L[key] end
			Tooltip(self, lines)
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(0.85, 0.85, 0.85)
		GameTooltip:Hide()
	end)
	return b
end

-- Element icons and text ---------------------------------------------------------------
-- Blizzard icons, the same ones RestedXP uses for each kind of instruction.

local POI = "Interface\\MINIMAP\\POIICONS"
local KIND_ICONS = {
	accept = "|TInterface\\GossipFrame\\AvailableQuestIcon:0:0:0:-2|t",
	turnin = "|TInterface\\GossipFrame\\ActiveQuestIcon:0:0:0:-2|t",
	complete = "|TInterface\\GossipFrame\\HealerGossipIcon:0:0:0:-2|t",
	collect = "|TInterface\\GossipFrame\\VendorGossipIcon:0:0:0:-2|t",
	equip = "|TInterface\\GossipFrame\\VendorGossipIcon:0:0:0:-2|t",
	vendor = "|TInterface\\GossipFrame\\BankerGossipIcon:0:0:0:-2|t",
	bank = "|TInterface\\GossipFrame\\BankerGossipIcon:0:0:0:-2|t",
	fly = "|TInterface\\GossipFrame\\TaxiGossipIcon:0:0:0:-2|t",
	fp = "|TInterface\\GossipFrame\\TaxiGossipIcon:0:0:0:-2|t",
	hs = "|TInterface\\MINIMAP\\TRACKING\\Innkeeper:0:0:0:-2|t",
	trainer = "|TInterface\\GossipFrame\\TrainerGossipIcon:0:0:0:-2|t",
	train = "|TInterface\\GossipFrame\\TrainerGossipIcon:0:0:0:-2|t",
	xp = "|TInterface\\PETBATTLES\\BattleBar-AbilityBadge-Strong-Small:0:0:0:-2|t",
	stable = "|TInterface\\MINIMAP\\TRACKING\\StableMaster:0:0:0:-2|t",
	abandon = "|TInterface\\GossipFrame\\IncompleteQuestIcon:0:0:0:-2|t",
	link = "|TInterface\\FriendsFrame\\UI-FriendsFrame-Link:0:0:0:-2|t",
	["goto"] = "|T" .. POI .. ":0:0:0:-2:128:128:63:72:0:4|t",
	home = "|T" .. POI .. ":0:0:0:-2:128:128:45:54:0:4|t",
	deathskip = "|T" .. POI .. ":0:0:0:-2:128:128:72:81:0:4|t",
	-- The same flag RestedXP puts in front of zone and subzone lines ("Travel back to Brill").
	zone = "|T" .. POI .. ":0:0:0:-2:128:128:63:72:0:4|t",
	subzone = "|T" .. POI .. ":0:0:0:-2:128:128:63:72:0:4|t",
	gossipoption = "|TInterface\\GossipFrame\\GossipGossipIcon:0:0:0:-2|t",
	reputation = "|TInterface\\GossipFrame\\WorkOrderGossipIcon:0:0:0:-2|t",
	blasted = "|TInterface\\GossipFrame\\VendorGossipIcon:0:0:0:-2|t",
	combat = "|TInterface\\GossipFrame\\BattleMasterGossipIcon:0:0:0:-2|t",
	clicknext = "|TInterface\\Tooltips\\ReforgeGreenArrow:0:0:0:-2|t",
}

local function ItemName(id)
	local f = (C_Item and C_Item.GetItemNameByID) or (GetItemInfo and function(i) return (GetItemInfo(i)) end)
	if not (f and id) then return nil end
	local ok, name = pcall(f, id)
	return ok and name or nil
end

-- Display text of an element, with live quest / item progress.
function FR:ElementText(e)
	local k = e.kind
	if k == "complete" then
		local live = FR.GetObjective(e.qid, e.obj, e.hint)
		if live and live ~= "" then return live end
		if e.text then return e.text end
		if e.comment then return e.comment end
		return (FR.QuestTitle(e.qid) or string.format(FR.L["Quest %d"], e.qid)) .. " (" .. e.obj .. ")"
	elseif k == "collect" then
		if e.qid and e.obj and not e.text then
			local live = FR.GetObjective(e.qid, e.obj, e.hint)
			if live and live ~= "" then return live end
		end
		if e.text then return e.text end
		local name = ItemName(e.item) or (e.comment and e.comment:gsub("^Collect%s+", ""):gsub("%s*%(%d+%)$", "")) or ("Item " .. e.item)
		return string.format("%s: %d/%d", name, math.min(FR.ItemCount(e.item), e.count or 1), e.count or 1)
	elseif k == "xp" then
		local text = e.text or string.format(FR.L["Grind to level %d"], e.level)
		-- Partial-level goals ("level 3 + 980 xp") show the current XP.
		if (e.xp or 0) ~= 0 and UnitLevel("player") == e.level and UnitXP then
			text = text .. string.format("  |cffaaaaaa(%d / %d xp)|r", UnitXP("player") or 0, UnitXPMax("player") or 0)
		end
		return text
	elseif k == "accept" or k == "turnin" then
		if e.text then return e.text end
		local title = FR.QuestTitle(e.qid) or string.format(FR.L["Quest %d"], e.qid)
		return string.format(FR.L[k == "accept" and "Accept %s" or "Turn in %s"], title)
	elseif k == "blasted" then
		-- The five Blasted Lands collection quests as one list with counts.
		local total, done = FR.BlastedNeeds()
		if done then return FR.L["Do the Blasted Lands collection quests"] end
		local lines = { FR.L["Collect the following items:"] }
		for i, goal in ipairs(total) do
			if goal > 0 then
				local id = FR.BLASTED_ITEMS[i]
				local name = ItemName(id) or ("Item " .. id)
				lines[#lines + 1] = string.format("- %s: %d/%d", name, math.min(FR.ItemCount(id), goal), goal)
			end
		end
		return table.concat(lines, "\n")
	elseif k == "reputation" and not e.text then
		local name = FR.FactionInfo and FR.FactionInfo(e.faction) or ""
		local standing = _G["FACTION_STANDING_LABEL" .. tostring(e.standing)] or tostring(e.standing)
		local v = e.value or 0
		if v < 0 then
			return string.format(FR.L["Grind until you are %d away from %s with %s"], -v, standing, name or "")
		elseif v >= 1 then
			return string.format(FR.L["Grind until you are %s into %s with %s"], tostring(v), standing, name or "")
		elseif v > 0 then
			return string.format(FR.L["Grind until you are %.0f%% into %s with %s"], v * 100, standing, name or "")
		end
		return string.format(FR.L["Grind to %s with %s"], standing, name or "")
	end
	return e.text or e.comment
end

-- Icon in front of a line: by kind, and for quest objectives by what has to be
-- done (items, creatures, other), like RestedXP.
local function LineIcon(e)
	if e.kind == "complete" then
		local t = FR.ObjectiveType and FR.ObjectiveType(e.qid, e.obj, e.hint)
		if t == "item" then return KIND_ICONS.collect end
		if t == "monster" then return KIND_ICONS.combat end
		return KIND_ICONS.complete
	end
	if e.nextGuide then return KIND_ICONS.clicknext end
	return KIND_ICONS[e.kind or ""]
end

-- Text with the kind icon in front (unless the guide already put one there).
local function ElementLabel(e)
	local text = FR:ElementText(e)
	if not text then return nil end
	local icon = LineIcon(e)
	if icon and text:sub(1, 2) ~= "|T" then text = icon .. " " .. text end
	return text
end
FR.ElementLabel = ElementLabel
-- Frames ---------------------------------------------------------------------------

local NAME_H, FOOTER_H, OVERLAP = 34, 20, 1

local main = CreateFrame("Frame", "ForeverRouteFrame", UIParent)
FR.frame = main
main:SetSize(FR.defaults.width, FR.defaults.height)
main:SetPoint("LEFT", UIParent, "LEFT", 30, -60)
main:SetMovable(true)
main:SetResizable(true)
main:SetClampedToScreen(true)
main:SetFrameStrata("MEDIUM")
if main.SetResizeBounds then main:SetResizeBounds(200, FOOTER_H, 1200, 1400)
elseif main.SetMinResize then main:SetMinResize(200, FOOTER_H); main:SetMaxResize(1200, 1400) end

local function StartMove() if not FR:Get("locked") then main:StartMoving() end end
local function StopMove()
	main:StopMovingOrSizing()
	-- Re-anchor on whole pixels so the text stays sharp after dragging.
	local p, _, rp, x, y = main:GetPoint()
	if not p then return end
	x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
	main:ClearAllPoints()
	main:SetPoint(p, UIParent, rp, x, y)
	if ForeverRouteDB then ForeverRouteDB.pos = { p, rp, x, y } end
end

-- Footer -----------------------------------------------------------------------------
local footer = CreateFrame("Frame", nil, main, BACKDROP)
main.footer = footer
footer:SetPoint("BOTTOMLEFT")
footer:SetPoint("BOTTOMRIGHT")
footer:SetHeight(FOOTER_H)
Skin(footer, "bg")
footer:EnableMouse(true)
footer:RegisterForDrag("LeftButton")
footer:SetScript("OnDragStart", StartMove)
footer:SetScript("OnDragStop", StopMove)
footer:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" then FR:ShowOptionsMenu(footer) end
end)
-- The footer is narrow: the pace and the time to the next level are written out in full here.
footer:SetScript("OnEnter", function(self)
	local T = FR.Tracker
	local full = FR:Get("showLevelETA") and FR:Get("enableTracker") and T and T.ETAFull and T.ETAFull()
	if not full then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine(full, 1, 1, 1, true)
	GameTooltip:Show()
end)
footer:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Gear = settings. No tooltips on the window's buttons.
main.cog = CreateFrame("Button", nil, footer)
main.cog:SetSize(14, 14)
main.cog:SetPoint("LEFT", 5, 0)
main.cog.icon = main.cog:CreateTexture(nil, "ARTWORK")
main.cog.icon:SetAllPoints()
main.cog.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
main.cog.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
main.cog:SetScript("OnEnter", function(self) self.icon:SetVertexColor(1, 1, 1) end)
main.cog:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) end)
main.cog:RegisterForClicks("LeftButtonUp", "RightButtonUp")
main.cog:SetScript("OnClick", function(_, button)
	if button == "RightButton" then FR:ShowOptionsMenu(footer) else FR:ToggleSettings() end
end)

local grip = CreateFrame("Button", nil, footer)
grip:SetSize(12, 12)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetAlpha(0.6)

main.footText = Text(footer, FR.fontSmall)
main.footText:SetPoint("LEFT", main.cog, "RIGHT", 6, 0)
main.footText:SetPoint("RIGHT", grip, "LEFT", -4, 0)
main.footText:SetJustifyH("LEFT")
main.footText:SetWordWrap(false)
main.footText:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

-- List frame ------------------------------------------------------------------------------
local list = CreateFrame("Frame", nil, main, BACKDROP)
main.list = list
list:SetPoint("TOPLEFT")
list:SetPoint("BOTTOMRIGHT", 0, FOOTER_H - 1)
Skin(list, "bg")

local scroll = CreateFrame("ScrollFrame", "ForeverRouteListScroll", list)
scroll:SetPoint("TOPLEFT", 4, -4)
scroll:SetPoint("BOTTOMRIGHT", -10, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(200, 10)
scroll:SetScrollChild(content)

-- Thin scroll bar (3 px, no arrow buttons) on the right edge.
local scrollBar = CreateFrame("Slider", nil, list)
scrollBar:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -5)
scrollBar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 5)
scrollBar:SetWidth(3)
scrollBar:SetOrientation("VERTICAL")
scrollBar:SetMinMaxValues(0, 0)
scrollBar:SetValue(0)
scrollBar.track = scrollBar:CreateTexture(nil, "BACKGROUND")
scrollBar.track:SetAllPoints()
scrollBar.track:SetTexture(WHITE)
scrollBar.track:SetVertexColor(1, 1, 1, 0.04)
local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
thumb:SetTexture(WHITE)
thumb:SetSize(3, 30)
scrollBar:SetThumbTexture(thumb)
thumb:SetVertexColor(1, 1, 1, 0.22)
scrollBar:SetScript("OnEnter", function() thumb:SetVertexColor(1, 1, 1, 0.45) end)
scrollBar:SetScript("OnLeave", function() thumb:SetVertexColor(1, 1, 1, 0.22) end)
scrollBar:SetScript("OnValueChanged", function(_, v)
	if math.abs((scroll:GetVerticalScroll() or 0) - v) > 0.5 then scroll:SetVerticalScroll(v) end
end)

local function UpdateScrollBar()
	if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
	local range = scroll:GetVerticalScrollRange() or 0
	local view = scroll:GetHeight() or 1
	scrollBar:SetMinMaxValues(0, math.max(0, range))
	if range <= 1 then scrollBar:Hide() return end
	scrollBar:Show()
	local track = scrollBar:GetHeight() or view
	thumb:SetHeight(math.max(16, track * view / (view + range)))
	scrollBar:SetValue(scroll:GetVerticalScroll() or 0)
end

local function ScrollTo(y)
	UpdateScrollBar()
	local range = scroll:GetVerticalScrollRange() or 0
	y = math.max(0, math.min(y, range))
	scroll:SetVerticalScroll(y)
	scrollBar:SetValue(y)
end

scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(_, delta)
	ScrollTo((scroll:GetVerticalScroll() or 0) - delta * 40)
end)
scroll:SetScript("OnScrollRangeChanged", UpdateScrollBar)
scroll:SetScript("OnSizeChanged", UpdateScrollBar)

-- Guide bar --------------------------------------------------------------------------
-- Guide name and group on the left, progress in percent on the right and a
-- thin progress line along the bottom edge.
local nameBar = CreateFrame("Button", nil, main, BACKDROP)
main.nameBar = nameBar
nameBar:SetHeight(NAME_H)
Skin(nameBar, "row")
nameBar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
nameBar:RegisterForDrag("LeftButton")
nameBar:SetScript("OnDragStart", function(self) self.dragged = true; StartMove() end)
-- The click that ends a drag is not a menu click. Not every client sends that
-- click, so the flag is cleared shortly after the drag instead of in OnClick.
nameBar:SetScript("OnDragStop", function(self)
	StopMove()
	C_Timer.After(0.1, function() self.dragged = false end)
end)

main.percent = Text(nameBar, FR.fontTitle)
main.percent:SetPoint("RIGHT", -10, 1)
main.percent:SetJustifyH("RIGHT")
Accent(main.percent)

main.title = Text(nameBar, FR.fontTitle)
main.title:SetPoint("BOTTOMLEFT", nameBar, "LEFT", 10, 0)
main.title:SetPoint("RIGHT", main.percent, "LEFT", -8, 0)
main.title:SetWordWrap(false)
main.title:SetTextColor(C.text[1], C.text[2], C.text[3])
main.subtitle = Text(nameBar, FR.fontSmall)
main.subtitle:SetPoint("TOPLEFT", nameBar, "LEFT", 10, -1)
main.subtitle:SetPoint("RIGHT", main.percent, "LEFT", -8, 0)
main.subtitle:SetWordWrap(false)
main.subtitle:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

local progressTrack = Bar(nameBar, "ARTWORK")
progressTrack:SetPoint("BOTTOMLEFT", 1, 1)
progressTrack:SetPoint("BOTTOMRIGHT", -1, 1)
progressTrack:SetHeight(2)
progressTrack:SetVertexColor(1, 1, 1, 0.05)
local progressFill = Bar(nameBar, "OVERLAY")
progressFill:SetPoint("BOTTOMLEFT", 1, 1)
progressFill:SetHeight(2)
progressFill:SetWidth(1)
Accent(progressFill)

function FR:SetProgress(fraction)
	local w = math.max(0, (nameBar:GetWidth() or 200) - 2)
	progressFill:SetWidth(math.max(0.01, w * math.max(0, math.min(1, fraction or 0))))
	progressFill:SetShown((fraction or 0) > 0)
	main.percent:SetText(fraction and string.format("%d%%", math.floor(fraction * 100 + 0.5)) or "")
end

nameBar:SetScript("OnEnter", function(self)
	local c = Theme().hl
	self:SetBackdropColor(c[1], c[2], c[3], FR:Get("alpha"))
end)
nameBar:SetScript("OnLeave", function(self)
	local c = Theme().row
	self:SetBackdropColor(c[1], c[2], c[3], FR:Get("alpha"))
end)
nameBar:SetScript("OnClick", function(self, button)
	if self.dragged then self.dragged = false return end
	GameTooltip:Hide()
	if button == "RightButton" then FR:ShowOptionsMenu(self) else FR:ToggleGuideMenu() end
end)

-- Step box area (boxes stack upwards from here) ------------------------------------------
local stepArea = CreateFrame("Frame", nil, main)
main.stepArea = stepArea
stepArea:SetPoint("BOTTOMLEFT", nameBar, "TOPLEFT", 0, 6)
stepArea:SetPoint("BOTTOMRIGHT", nameBar, "TOPRIGHT", 0, 6)
stepArea:SetHeight(1)

-- Resizing: the content follows live while the grip is dragged.
local sizing = false

local function StoreSize()
	if not ForeverRouteDB then return end
	ForeverRouteDB.width = math.floor(main:GetWidth() + 0.5)
	if FR:Get("showList") then ForeverRouteDB.height = math.floor(main:GetHeight() + 0.5) end
end

grip:SetScript("OnMouseDown", function()
	if FR:Get("locked") then return end
	sizing = true
	main:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
	main:StopMovingOrSizing()
	sizing = false
	if not ForeverRouteDB then return end
	StoreSize()
	local p, _, rp, x, y = main:GetPoint()
	if p then
		x, y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
		main:ClearAllPoints()
		main:SetPoint(p, UIParent, rp, x, y)
		ForeverRouteDB.pos = { p, rp, x, y }
	end
	FR.listDirty = true
	FR:UpdateUI()
	if FR.RefreshSettings then FR:RefreshSettings() end
end)

-- While sizing, only what depends on the size is laid out again: the step
-- boxes every frame, the list (many rows to measure) a few times a second.
local liveW, liveH, listAcc, listPending = nil, nil, 0, false
main:SetScript("OnUpdate", function(_, elapsed)
	if not sizing then return end
	local w = math.floor(main:GetWidth() + 0.5)
	local h = math.floor(main:GetHeight() + 0.5)
	if w ~= liveW then
		liveW = w
		StoreSize()
		FR:LiveLayoutBoxes(w)
		listPending = true
	elseif h ~= liveH then
		StoreSize()
	end
	if h ~= liveH then liveH = h; UpdateScrollBar() end
	listAcc = listAcc + elapsed
	if listPending and listAcc >= 0.08 then
		listAcc, listPending = 0, false
		FR:LiveLayoutList()
	end
end)

-- Step cards ---------------------------------------------------------------------------------
-- One card per active step: side steps on top, the current step at the bottom.
-- The current card has an accent bar on the left and a "STEP N" label.
-- Only the round checkboxes react to the mouse.

local TICK = FR.DIR .. "\\Textures\\Tick"     -- ring with a check mark
local RING = FR.DIR .. "\\Textures\\Check"    -- empty ring
local CHECK_W, TEXT_X, PAD = 12, 19, 10
local boxes, boxUsed = {}, 0

local function PaintCheck(b, hover)
	-- "waiting" = a replayed tick that has not popped up yet: shown empty.
	if b.done and not b.waiting then
		b.ring:Hide()
		b.tick:Show()
		Accent(b.tick, hover and 1 or 0.9)
	else
		b.tick:Hide()
		b.ring:Show()
		if hover then b.ring:SetVertexColor(1, 1, 1, 1) else b.ring:SetVertexColor(0.6, 0.63, 0.7, 1) end
	end
end

-- Little pop when a line is ticked (grows past its size and settles) or a
-- soft shrink when it is unticked.
local function CheckAnim(self, elapsed)
	self.animT = self.animT + elapsed
	if self.animT < 0 then return end
	if self.waiting then
		self.waiting = false
		PaintCheck(self, false)
	end
	local p = math.min(1, self.animT / 0.22)
	local tex = self.done and self.tick or self.ring
	local scale
	if self.done then scale = 0.55 + 0.45 * p + 0.4 * math.sin(math.pi * p) * (1 - p * 0.4)
	else scale = 1.25 - 0.25 * p end
	tex:SetSize(CHECK_W * scale, CHECK_W * scale)
	tex:SetAlpha(0.3 + 0.7 * p)
	if p >= 1 then
		tex:SetSize(CHECK_W, CHECK_W)
		tex:SetAlpha(1)
		self:SetScript("OnUpdate", nil)
	end
end

local function CheckOnEnter(self)
	PaintCheck(self, true)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -6)
	GameTooltip:AddLine(FR.L["Tick off / untick"], 1, 1, 1)
	GameTooltip:Show()
end

local function CheckOnLeave(self)
	PaintCheck(self, false)
	GameTooltip:Hide()
end

-- Ticks the line off (or on again); a step whose lines are all ticked is done.
local function CheckOnClick(self)
	local line = self:GetParent()
	if line.element then FR:ToggleGoal(line.element, line.step) end
end

-- Moves each card towards its target height in whole pixels.
local function BoxOnUpdate(self, elapsed)
	local cur, target = self.curH or 0, self.targetH or 0
	if math.abs(target - cur) < 1 then
		cur = target
	else
		cur = cur + (target - cur) * math.min(1, elapsed * 16)
	end
	self.curH = cur
	self:SetHeight(math.max(1, Snap(cur)))
	local a = self:GetAlpha() or 1
	if a < 1 then self:SetAlpha(math.min(1, a + elapsed * 6)) end
	if cur == target and a >= 1 then self:SetScript("OnUpdate", nil) end
end

local function GetBox()
	boxUsed = boxUsed + 1
	local b = boxes[boxUsed]
	if not b then
		b = CreateFrame("Frame", nil, stepArea, BACKDROP)
		Skin(b, "bg")
		if b.SetClipsChildren then b:SetClipsChildren(true) end
		b.bar = Bar(b, "ARTWORK")
		b.bar:SetPoint("TOPLEFT", 1, -1)
		b.bar:SetPoint("BOTTOMLEFT", 1, 1)
		b.bar:SetWidth(2)
		Accent(b.bar)
		-- "STEP 24" label inside the card (kept as .tab for the layout code).
		b.tab = CreateFrame("Frame", nil, b)
		b.tab:SetPoint("TOPLEFT", PAD, -7)
		b.tab:SetSize(100, 12)
		b.tab.text = Text(b.tab, FR.fontLabel)
		b.tab.text:SetPoint("LEFT")
		Accent(b.tab.text)
		b.elements = {}
		b.curH = 0
		b:SetAlpha(0)
		-- Only the "steps were passed" notice reacts to the mouse (b.notice is set for it alone).
		b:SetScript("OnMouseUp", function(self, button)
			if self.notice then FR:PassNoticeClick(self.notice, button) end
		end)
		b:SetScript("OnEnter", function(self)
			if self.notice then FR:PassNoticeTooltip(self, self.notice) end
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		boxes[boxUsed] = b
	end
	b.notice = nil
	b:EnableMouse(false)
	if not b:IsShown() then
		-- Newly shown cards grow in and fade in.
		b.curH = 0
		b:SetAlpha(0)
	end
	b.used = 0
	b:Show()
	return b
end

-- kind: "check" (round checkbox), "plain"
local function AddElement(box, y, width, kind, text, done, element, step)
	box.used = box.used + 1
	local e = box.elements[box.used]
	if not e then
		e = CreateFrame("Frame", nil, box)
		e:EnableMouse(false)
		e.checkButton = CreateFrame("Button", nil, e)
		e.checkButton:SetSize(CHECK_W + 4, CHECK_W + 4)
		e.checkButton:SetPoint("TOPLEFT", -2, 1)
		-- React on press: a guide update between press and release can not
		-- swallow the click.
		e.checkButton:RegisterForClicks("LeftButtonDown")
		e.checkButton:SetScript("OnEnter", CheckOnEnter)
		e.checkButton:SetScript("OnLeave", CheckOnLeave)
		e.checkButton:SetScript("OnClick", CheckOnClick)
		e.checkButton.ring = e.checkButton:CreateTexture(nil, "ARTWORK")
		e.checkButton.ring:SetSize(CHECK_W, CHECK_W)
		e.checkButton.ring:SetPoint("CENTER")
		e.checkButton.ring:SetTexture(RING)
		e.checkButton.tick = e.checkButton:CreateTexture(nil, "ARTWORK")
		e.checkButton.tick:SetSize(CHECK_W, CHECK_W)
		e.checkButton.tick:SetPoint("CENTER")
		e.checkButton.tick:SetTexture(TICK)
		e.checkButton.animT, e.checkButton.waiting = 0, false
		e.text = Text(e, FR.fontBody)
		e.text:SetPoint("TOPLEFT", TEXT_X, 0)
		e.text:SetWordWrap(true)
		if e.text.SetSpacing then e.text:SetSpacing(2) end
		box.elements[box.used] = e
	end
	e.element, e.step = element, step
	e:ClearAllPoints()
	e:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, Snap(y))
	e:SetWidth(width)
	-- Every line starts its text at the same x, with or without checkbox.
	e.text:SetWidth(width - TEXT_X - 2)
	if kind == "check" then
		e.checkButton.done = done
		PaintCheck(e.checkButton, GetMouseFocus and GetMouseFocus() == e.checkButton)
		e.checkButton:Show()
		if element then
			-- A line that changes state while it is on screen (ticked by hand,
			-- finished in the game, unticked) gets the little animation.
			local was = element.shownDone
			element.shownDone = done and true or false
			if FR.replaying and done and step == FR:GetStep() and element.replayToken ~= FR.replayToken then
				-- Running forward again after going back (like RestedXP): the
				-- ticks of this finished step pop up one after the other.
				element.replayToken = FR.replayToken
				e.checkButton.animT = -0.07 * box.used
				e.checkButton.waiting = true
				PaintCheck(e.checkButton, false)
				e.checkButton:SetScript("OnUpdate", CheckAnim)
			elseif was ~= nil and was ~= element.shownDone then
				-- ".timer" lines start their countdown when the line before is done.
				if element.shownDone and element.timer and FR.StartTimer and not FR:IsMarked(step, element) then
					FR:StartTimer(element.timer, element.timerText)
				end
				e.checkButton.waiting = false
				e.checkButton.animT = 0
				e.checkButton:SetScript("OnUpdate", CheckAnim)
			end
		end
	else
		e.checkButton:Hide()
	end
	e.text:SetText(text)
	e.text:SetAlpha(done and 0.4 or 1)
	local h = math.ceil(math.max(CHECK_W, e.text:GetStringHeight() or 12))
	e:SetHeight(h)
	e:Show()
	return h
end

-- Lines are reused in place and only the unused ones are hidden: hiding a
-- line that is being clicked would cancel the click.
local function HideUnused(box)
	for i = box.used + 1, #box.elements do box.elements[i]:Hide() end
end

-- Fills a card with a step; returns its height.
local function FillBox(box, step, width, isCurrent)
	box.used = 0
	local y = -PAD + 1
	if isCurrent then
		box.tab.text:SetText(string.upper(string.format(FR.L["Step %d"], step.idx)))
		box.tab:Show()
		box.bar:Show()
		y = -24
	else
		box.tab:Hide()
		box.bar:Hide()
	end
	local inner = width - PAD * 2
	for _, e in ipairs(step.elements) do
		if not e.hidden then
			local text = ElementLabel(e)
			if text then
				local done, completable = FR:ElementState(step, e)
				y = y - AddElement(box, y, inner, completable and "check" or "plain", text, done, e, step) - 6
			end
		end
	end
	HideUnused(box)
	return math.ceil(-y + PAD - 6 + 1)
end

local function SetBoxHeight(box, h)
	box.targetH = h
	if box.curH == nil then box.curH = 0 end
	box:SetScript("OnUpdate", BoxOnUpdate)
end

local function FillMessage(box, text, width)
	box.used = 0
	box.tab:Hide()
	box.bar:Hide()
	local h = AddElement(box, -PAD, width - PAD * 2, "plain", text, false, nil, nil) + PAD * 2
	HideUnused(box)
	return math.ceil(h)
end

local function MessageBox(text)
	local box = GetBox()
	box.step, box.message = nil, text
	SetBoxHeight(box, FillMessage(box, text, FR:Get("width") or 280))
	return box
end

-- The "N steps were passed automatically" notice: a message card above the steps that goes back
-- to the first passed step when clicked (History.lua).
local function NoticeBox(notice)
	local box = MessageBox(FR:PassNoticeText(notice))
	box.notice = notice
	box:EnableMouse(true)
	return box
end

-- Title for the arrow: the pin's own text, else the line it belongs to ("Accept ..."), else the
-- text of the step's first visible element.
local function StepTitle(step, e)
	if e and e.text then return Strip(e.text) end
	local parent = e and e.parent and step.elements[e.parent]
	if parent then
		local t = FR:ElementText(parent)
		if t then return Strip(t) end
	end
	for _, x in ipairs(step.elements) do
		if not x.hidden then
			local t = FR:ElementText(x)
			if t then return Strip(t) end
		end
	end
	return string.format(FR.L["Step %d"], step.idx)
end

-- Step list -------------------------------------------------------------------------------

local rows, rowCount = {}, 0

local function RowOnEnter(self)
	local hl = Theme().hl
	self:SetBackdropColor(hl[1], hl[2], hl[3], 1)
	self:SetAlpha(1)
	-- What happened to a step that is behind you (done, passed on its own, skipped, left open) and why.
	local title, why, color = FR:StepStatusLines(self.step)
	if title then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, color and color[1] or 1, color and color[2] or 1, color and color[3] or 1)
		if why then GameTooltip:AddLine(why, 0.75, 0.77, 0.82, true) end
		GameTooltip:Show()
	end
end

local function RowOnLeave(self)
	if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	FR:StyleRow(self)
end

local function RowOnClick(self, button)
	if button == "RightButton" then
		-- Options menu: go to step, other guide, reload, options, close.
		FR:ShowOptionsMenu(self, self.index)
	elseif self.lastClick and GetTime() - self.lastClick < 0.4 then
		self.lastClick = nil
		FR:GoToStep(self.index)
	else
		self.lastClick = GetTime()
	end
end

local NUM_W = 22   -- step number column

local function GetListRow(i)
	local r = rows[i]
	if not r then
		r = CreateFrame("Button", nil, content, BACKDROP)
		Skin(r, "row", true)
		skinned[r] = nil   -- coloured by StyleRow
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r.bar = Bar(r, "ARTWORK")
		r.bar:SetPoint("TOPLEFT")
		r.bar:SetPoint("BOTTOMLEFT")
		r.bar:SetWidth(2)
		Accent(r.bar)
		-- Thin divider under every row.
		r.sep = Bar(r, "ARTWORK")
		r.sep:SetPoint("BOTTOMLEFT", 8, 0)
		r.sep:SetPoint("BOTTOMRIGHT", -8, 0)
		r.sep:SetHeight(1)
		r.sep:SetVertexColor(1, 1, 1, 0.09)
		r.num = Text(r, FR.fontSmall)
		r.num:SetPoint("TOPRIGHT", r, "TOPLEFT", NUM_W, -6)
		r.num:SetJustifyH("RIGHT")
		r.text = Text(r, FR.fontBody)
		r.text:SetPoint("TOPLEFT", NUM_W + 8, -5)
		r.text:SetWordWrap(true)
		if r.text.SetSpacing then r.text:SetSpacing(2) end
		r:SetScript("OnEnter", RowOnEnter)
		r:SetScript("OnLeave", RowOnLeave)
		r:SetScript("OnClick", RowOnClick)
		rows[i] = r
	end
	return r
end

-- Only the current step has a fill and the accent bar; finished steps fade.
function FR:StyleRow(r)
	local i, cur = r.index, self.stepIndex or 1
	local c = Theme().row
	r:SetBackdropColor(c[1], c[2], c[3], i == cur and FR:Get("alpha") or 0)
	r.bar:SetShown(i == cur)
	if i == cur then
		r:SetAlpha(1)
		Accent(r.num)
	else
		r:SetAlpha(i < cur and 0.4 or 0.85)
		accents[r.num] = nil
		-- Steps behind you: the number shows what happened to them (done, passed on its own, skipped, left open).
		local status = i < cur and r.step and FR:StepStatus(r.step)
		local sc = status and FR.HISTORY_COLORS[status.how]
		if sc then r.num:SetTextColor(sc[1], sc[2], sc[3]) else r.num:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
	end
end

local listGuide, listWidth

local function StepLines(step)
	local lines = {}
	for _, e in ipairs(step.elements) do
		if not e.hidden then
			local t = ElementLabel(e)
			if t then lines[#lines + 1] = t end
		end
	end
	return table.concat(lines, "\n")
end

FR.StepLines = StepLines

-- Lines whose text changes while playing (kill counts, items, xp, quest names).
local LIVE = { complete = true, collect = true, xp = true, accept = true, turnin = true }

local function IsLive(step)
	for _, e in ipairs(step.elements) do
		if LIVE[e.kind or ""] and not e.hidden then return true end
	end
	return false
end

local function MeasureRow(r, width)
	r:SetWidth(width)
	r.text:SetWidth(width - NUM_W - 14)
	r.h = math.ceil(math.max(22, (r.text:GetStringHeight() or 12) + 11))
	r:SetHeight(r.h)
end

local function BuildList(g, width)
	rowCount = 0
	for _, r in ipairs(rows) do r:Hide() end
	if not g then return end
	for i, s in ipairs(g.steps) do
		-- Like RestedXP's step list: steps tagged "#optional" are not listed
		-- (they still count in the numbering and show above the current step).
		local text = s.optional and "" or StepLines(s)
		if text ~= "" then
			rowCount = rowCount + 1
			local r = GetListRow(rowCount)
			r.index, r.step, r.live, r.shownText = i, s, IsLive(s), text
			r.text:SetText(text)
			r.num:SetText(tostring(i))
			MeasureRow(r, width)
		end
	end
end

-- Updates the rows with live text; true when a row changed its height.
-- Only rows around the current step are kept live: kill counts and item
-- counts only change for quests that are in the log, which are the steps near
-- the current one. Reading every row of a 150 step guide on each update was
-- the main cost of a window update (and so of every loot).
local LIVE_BEFORE, LIVE_AHEAD = 4, 16

local function RefreshLiveRows(width)
	local moved = false
	local cur = FR.stepIndex or 1
	for i = 1, rowCount do
		local r = rows[i]
		if r.live and r.index >= cur - LIVE_BEFORE and r.index <= cur + LIVE_AHEAD then
			local text = StepLines(r.step)
			if text ~= r.shownText then
				r.shownText = text
				r.text:SetText(text)
				local h = r.h
				MeasureRow(r, width)
				if r.h ~= h then moved = true end
			end
		end
	end
	return moved
end

-- Positions the rows; scrolls to the current step only when asked.
local function LayoutList(scrollToCurrent)
	local y, curTop = 0, nil
	local hide = FR:Get("hideCompleted")
	for i = 1, rowCount do
		local r = rows[i]
		if hide and r.index < FR.stepIndex then
			r:Hide()
		else
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			r:Show()
			FR:StyleRow(r)
			if r.index >= FR.stepIndex and not curTop then curTop = y end
			y = y + r.h + 1
		end
	end
	content:SetHeight(math.max(10, y))
	if scrollToCurrent then ScrollTo(curTop or 0) else UpdateScrollBar() end
end

local function ListWidth()
	local w = scroll:GetWidth() or 0
	if w < 50 then w = (FR:Get("width") or 280) - 21 end
	return w
end

-- Live resizing ------------------------------------------------------------------------------

function FR:LiveLayoutBoxes(width)
	for i = 1, boxUsed do
		local box = boxes[i]
		local h
		if box.step then h = FillBox(box, box.step, width, box.isCurrent)
		elseif box.message then h = FillMessage(box, box.message, width) end
		if h then
			box:SetScript("OnUpdate", nil)
			box.targetH, box.curH = h, h
			box:SetHeight(h)
			box:SetAlpha(1)
		end
	end
end

function FR:LiveLayoutList()
	if not (self.current and self:Get("showList")) then return end
	local w = ListWidth()
	for i = 1, rowCount do MeasureRow(rows[i], w) end
	listWidth = self:Get("width")
	LayoutList(false)
end

-- Window update ---------------------------------------------------------------------------

-- The footer: "Step 12 / 230" and, while the leveling tracker knows the pace, "18.4k XP/h, 37 min to level 31".
local function FooterText()
	local g = FR.current
	if not g then return "ForeverRoute v" .. tostring(FR.version) end
	local text = string.format(FR.L["Step %d"], FR.stepIndex or 1) .. " / " .. #g.steps
	local T = FR.Tracker
	if FR:Get("showLevelETA") and FR:Get("enableTracker") and T and T.ETAText then
		local eta = T.ETAText()
		if eta then text = text .. "  |  " .. eta end
	end
	return text
end

-- The pace changes while you play, not with steps: refresh the footer every half minute.
if C_Timer and C_Timer.NewTicker then
	C_Timer.NewTicker(30, function()
		if ForeverRouteDB then main.footText:SetText(FooterText()) end
	end)
end

function FR:UpdateUI()
	if not ForeverRouteDB then return end
	local W = self:Get("width")
	local showList = self:Get("showList")
	main:SetWidth(W)
	main:SetHeight(showList and self:Get("height") or FOOTER_H)
	if showList then list:Show() else list:Hide() end
	nameBar:ClearAllPoints()
	nameBar:SetPoint("BOTTOMLEFT", main, "TOPLEFT", 0, showList and -OVERLAP or -2)
	nameBar:SetPoint("BOTTOMRIGHT", main, "TOPRIGHT", 0, showList and -OVERLAP or -2)
	nameBar:SetFrameLevel((list:GetFrameLevel() or 1) + 5)


	boxUsed = 0
	local shown = {}
	local g = self.current
	main.footText:SetText(FooterText())

	if not g then
		main.title:SetText("ForeverRoute")
		main.subtitle:SetText(FR.L["No guide selected"])
		self:SetProgress(nil)
		shown[1] = MessageBox(FR.L["Click the guide bar below to choose a guide."])
		self:ClearWaypoint()
		BuildList(nil, 0)
		listGuide = nil
	else
		local total = #g.steps
		main.title:SetText(g.short)
		main.subtitle:SetText(FR.SubgroupName(g.subgroup) or FR.GroupName(FR.CanonGroup(g), g.lang))
		self:SetProgress((self.stepIndex - 1) / math.max(1, total - 1))

		-- Side steps on top, the current step at the bottom (next to the bar).
		local active = self:GetActiveSteps()
		local current = self:GetStep()
		for n = #active, 1, -1 do
			local s = active[n]
			local box = GetBox()
			box.step, box.isCurrent, box.message = s, (s == current), nil
			local h = FillBox(box, s, W, s == current)
			if box.used > 0 then
				SetBoxHeight(box, h)
				shown[#shown + 1] = box
			else
				box:Hide(); box.tab:Hide()
				boxUsed = boxUsed - 1
			end
		end

		-- Steps the guide passed on its own (already done in the game): said above the steps, with a way back.
		local notice = self.ActivePassNotice and self:ActivePassNotice()
		if notice then shown[#shown + 1] = NoticeBox(notice) end

		local wpElement, wpStep = self:ChooseWaypoint(active)
		if wpElement then
			self:SetWaypoint(wpElement.wp, StepTitle(wpStep, wpElement), wpStep, wpElement)
		else
			self:ClearWaypoint()
		end

		if showList then
			local listW = ListWidth()
			local rebuilt, moved = false, false
			if self.listDirty or listGuide ~= g or listWidth ~= W then
				BuildList(g, listW)
				listGuide, listWidth = g, W
				self.listDirty = false
				rebuilt = true
			else
				moved = RefreshLiveRows(listW)
			end
			-- Follow the current step only when it changed (keeps your own scrolling).
			local follow = rebuilt or self.listStep ~= self.stepIndex
			self.listStep = self.stepIndex
			-- Positioning ~180 rows is the biggest part of an update: do it only when
			-- something moved (new step, a row changed its height, resize).
			if follow or moved or self.listLayoutDirty then
				self.listLayoutDirty = false
				LayoutList(follow)
			end
		end
	end

	-- Stack the boxes upwards from the guide bar.
	for i = boxUsed + 1, #boxes do boxes[i]:Hide(); boxes[i].tab:Hide() end
	local below = stepArea
	for i, box in ipairs(shown) do
		box:ClearAllPoints()
		if i == 1 then
			box:SetPoint("BOTTOMLEFT", stepArea, "BOTTOMLEFT")
			box:SetPoint("BOTTOMRIGHT", stepArea, "BOTTOMRIGHT")
		else
			-- Leave room for the "Step N" tab of the box below.
			local gap = 4
			box:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, gap)
			box:SetPoint("BOTTOMRIGHT", below, "TOPRIGHT", 0, gap)
		end
		below = box
	end
	if self.UpdateActiveFrames then self:UpdateActiveFrames() end
	if self.RefreshMapPins then self:RefreshMapPins() end
end

function FR:SetShown(show)
	if show then main:Show() else main:Hide() end
	if ForeverRouteDB then ForeverRouteDB.hidden = not show end
	if show then self:Refresh() elseif self.UpdateActiveFrames then self:UpdateActiveFrames() end
end

function FR:Toggle()
	self:SetShown(not main:IsShown())
end

function FR:ResetPositions()
	if ForeverRouteDB then ForeverRouteDB.pos, ForeverRouteDB.arrowPos = nil, nil end
	-- Offsets are in screen pixels (the frames use the pixel scale).
	local k = UIPixels()
	local function Px(v) return math.floor(v * k + 0.5) end
	main:ClearAllPoints(); main:SetPoint("LEFT", UIParent, "LEFT", Px(30), Px(-60))
	FR.arrow:ClearAllPoints(); FR.arrow:SetPoint("TOP", UIParent, "TOP", 0, Px(-120))
	if ForeverRouteDB then ForeverRouteDB.posActiveItems, ForeverRouteDB.posActiveTargets = nil, nil end
	if FR.itemsBar and not (InCombatLockdown and InCombatLockdown()) then
		FR.itemsBar:ClearAllPoints(); FR.itemsBar:SetPoint("LEFT", UIParent, "LEFT", Px(330), Px(120))
		FR.targetsBar:ClearAllPoints(); FR.targetsBar:SetPoint("LEFT", UIParent, "LEFT", Px(330), Px(40))
	end
end

function FR:ApplySettings(key)
	if not ForeverRouteDB then return end
	self.listLayoutDirty = true
	if key == nil or key == "scale" then main:SetScale(FR.PixelScale(self:Get("scale"))) end
	if (key == nil or key == "barSize") and self.ApplyActiveScale then self:ApplyActiveScale() end
	if (key == "showTips" or key == "enableEmergency") and self.RefreshTips then self:RefreshTips() end
	if key == "enableTracker" and self.Tracker then self.Tracker.Refresh() end
	if key == "versionChannel" and self.Version and self.Version.Apply then self.Version.Apply() end
	if (key == "showJunkIcon" or key == "enableInventoryManager") and self.RefreshJunkIcons then self:RefreshJunkIcons() end
	if type(key) == "string" and key:find("^partySteps") and self.RefreshPartySteps then self:RefreshPartySteps() end
	-- Which "#hardcore" / "#softcore" steps show: the guide is read again.
	if key == "hardcoreMode" and self.OnRouteSettingsChanged then self:OnRouteSettingsChanged() end
	-- Ticking the box is also the wish to see them: turn the game's name plates on if they are off.
	if (key == "nameplateIcons" or key == "customPlates") and self:Get(key) and self.EnableNameplates then self:EnableNameplates() end
	local plateKey = type(key) == "string" and (key:find("^nameplate") or key:find("^plate") or key == "customPlates")
	if (key == nil or plateKey) and self.RefreshNameplateIcons then
		self:RefreshNameplateIcons()
	end
	-- The game's own floating NPC names go off while our plates draw the names (Plates.lua).
	if (key == nil or key == "customPlates" or key == "plateNpc" or key == "plateHideGameNames") and self.ApplyNpcNames then
		self:ApplyNpcNames()
	end
	if key == nil or key == "alpha" or key == "theme" then ReSkin() end
	if key == nil or key == "fontSize" or key == "scale" or key == "font" or key == "arrowScale" then
		self:ApplyFonts()
		self.listDirty = true
		if key == "font" and self.LayoutArrow then self:LayoutArrow() end
	end
	if key == nil or key == "language" then
		self:ApplyLocale()
		if key == "language" then
			-- Default step texts are translated when a guide is read: read again.
			local stepKey = self:CurrentStepKey()   -- before the steps are dropped
			for _, g in ipairs(self.guides) do g.steps, g.labels = nil, nil end
			if self.current then
				local title, idx = self.current.title, self.stepIndex
				self.current = nil
				self:SetGuide(title, idx, stepKey)
			end
			self.listDirty = true
		end
	end
	if key == "width" or key == "showList" then self.listDirty = true end
	if key == nil or key == "showArrow" or key == "arrowScale" then self:UpdateArrowVisibility() end
	if key == nil or key == "mapPins" or key == "minimapPins" then self.pinsDirty = true end
	if key == nil or key == "showMinimap" then if self.UpdateMinimapButton then self:UpdateMinimapButton() end end
	if key == "autoAdvance" or key == "autoArrive" then self:Refresh() return end
	self:UpdateUI()
end

-- Until 2.3 sizes and positions were stored in the game's UI units; now the
-- window uses screen pixels. Convert once so the window keeps its size/place.
local function MigratePixelUnits(db)
	if db.pixelUnits then return end
	db.pixelUnits = true
	local k = UIPixels()
	local function R(v) return v and math.floor(v * k + 0.5) end
	if db.width then db.width = R(db.width) end
	if db.height then db.height = R(db.height) end
	for _, key in ipairs({ "pos", "arrowPos" }) do
		local p = db[key]
		if p then p[3], p[4] = R(p[3]), R(p[4]) end
	end
end

-- 2.3: Inter replaces Arial Narrow; at the same pixel size it is larger, so
-- 11 matches what 12 looked like before (10 turned out too small).
local function MigrateFont(db)
	if db.fontInter then return end
	db.fontInter = true
	if db.fontSize == nil or db.fontSize <= 12 then db.fontSize = 11 end
end

-- Keep the pixel scale when the game's UI scale or resolution changes.
for _, event in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
	pcall(main.RegisterEvent, main, event)
end
main:SetScript("OnEvent", function()
	if not ForeverRouteDB then return end
	FR:ApplySettings("scale")
	FR:ApplySettings("arrowScale")
	if FR.ApplyActiveScale then FR:ApplyActiveScale() end
end)

function FR:RestorePositions()
	local db = ForeverRouteDB
	MigratePixelUnits(db)
	MigrateFont(db)
	if db.pos then
		local p, rp, x, y = unpack(db.pos)
		main:ClearAllPoints(); main:SetPoint(p, UIParent, rp, x, y)
	end
	if db.arrowPos then
		local p, rp, x, y = unpack(db.arrowPos)
		FR.arrow:ClearAllPoints(); FR.arrow:SetPoint(p, UIParent, rp, x, y)
	end
end

-- Menus (FlatMenu, the one look of the Forever addons) --------------------------------------
-- Guide menu: route -> level range -> guide. Starting zones of other races go
-- into an "Other starting zones" sub menu, like RestedXP. With German chosen,
-- German guides come first and the English ones (which go up to 60) follow.

local Flat = ns.FlatMenu

-- A yes/no question (restart, skipping the last step). `onAccept` runs on Yes.
StaticPopupDialogs["FOREVERROUTE_CONFIRM"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(_, data)
		if type(data) == "function" then data() end
	end,
}
function FR:Confirm(text, onAccept)
	StaticPopup_Show("FOREVERROUTE_CONFIRM", text, nil, onAccept)
end

function FR:ConfirmRestart()
	self:Confirm(FR.L["Restart the guide? Your manual ticks in it are cleared."], function() FR:RestartGuide() end)
end

local function GuideItem(g, suggestedTitle)
	local suggested = (g.title == suggestedTitle)
	local text = g.short
	if FR.current == g then text = "|cff33ff33" .. text .. "|r"
	elseif suggested then text = "|cffffd100" .. text .. "|r" end
	return {
		text = text,
		onClick = function()
			FR.wpOverride = nil
			-- Picking the guide you are in keeps your place.
			FR:SetGuide(g.title, FR.current == g and FR.stepIndex or 1)
			FR:SetShown(true)
		end,
	}, suggested
end

-- Group (Forever route, dungeon route, survival), then subgroup, then level, then file order.
local function GuideBefore(a, b)
	local ra, rb = FR.GroupRank(FR.CanonGroup(a)), FR.GroupRank(FR.CanonGroup(b))
	if ra ~= rb then return ra < rb end
	if a.group ~= b.group then return a.group < b.group end
	local sa, sb = a.subgroup or "", b.subgroup or ""
	if sa ~= sb then return sa < sb end
	local la, lb = (FR.GuideLevelRange(a)) or 0, (FR.GuideLevelRange(b)) or 0
	if la ~= lb then return la < lb end
	return a.order < b.order
end

function FR:BuildGuideMenu()
	local root = { children = {}, index = {} }
	local suggestedItems = {}
	local suggestedTitle = self:FindSuggestedGuide()
	local lang = self:Language()
	local list = {}
	for _, g in ipairs(self.guides) do
		-- An English guide that exists in the chosen language is not listed twice.
		if self:IsGuideAllowed(g) and not (g.lang ~= lang and self:LanguageTwin(g)) then list[#list + 1] = g end
	end
	table.sort(list, GuideBefore)
	for pass = 1, 2 do
		for _, g in ipairs(list) do
			local inLang = (g.lang == lang)
			if (pass == 1) == inLang then
				local node = root
				local segs = { FR.GroupName(FR.CanonGroup(g), g.lang) }
				if g.subgroup then segs[2] = FR.SubgroupName(g.subgroup) end
				for _, seg in ipairs(segs) do
					local child = node.index[seg]
					if not child then
						child = { text = seg, children = {}, index = {} }
						node.index[seg] = child
						table.insert(node.children, child)
					end
					node = child
				end
				local item, suggested = GuideItem(g, suggestedTitle)
				local target = node
				if self:IsOtherRaceGuide(g) then
					node.other = node.other or { text = "|cff8899aa" .. FR.L["Other starting zones"] .. "|r", children = {}, names = {} }
					target = node.other
				end
				-- Two guides with the same display name: add the full name.
				target.names = target.names or {}
				if target.names[g.short] then item.text = item.text .. " (" .. g.name .. ")" end
				target.names[g.short] = true
				table.insert(target.children, item)
				if suggested then table.insert(suggestedItems, (GuideItem(g, suggestedTitle))) end
			end
		end
	end
	local function Finish(node)
		for _, c in ipairs(node.children) do
			if c.children and c.index then Finish(c) end
		end
		if node.other then table.insert(node.children, node.other) end
	end
	Finish(root)
	local top = {}
	if #suggestedItems > 0 then
		table.insert(top, { text = "|cffffd100" .. FR.L["Suggested for you"] .. "|r", children = suggestedItems })
	end
	for _, c in ipairs(root.children) do table.insert(top, c) end
	return top
end

-- The dungeons: a tick box each, always usable. A tick in a route without dungeon steps moves
-- you to the matching route with dungeons (FR:DungeonsChanged). The first entry says which kind
-- of route is open and switches to the other one.
function FR:BuildDungeonMenu()
	local g = self.current
	local L = FR.L
	local list = {}
	if g then
		if FR.IsDungeonRoute(g) then
			if FR.DungeonRouteGroup(g, false) then
				list[#list + 1] = { text = L["Route with dungeons - switch to the route without"],
					onClick = function() FR:SwitchDungeonRoute(false) end }
			end
		elseif FR.DungeonRouteGroup(g, true) then
			list[#list + 1] = { text = L["Route without dungeons - switch to the route with"],
				onClick = function() FR:SwitchDungeonRoute(true) end }
		else
			list[#list + 1] = { text = L["This guide has no dungeon steps."], disabled = true }
		end
		if #list > 0 then list[#list + 1] = { divider = true } end
	end
	-- As RestedXP 4.11.36: the dungeons the open route needs ("Required"), then the rest ("Optional").
	-- Here both can be switched; the route's own choice is the starting point.
	local required, optional = FR.SplitDungeons(g)
	local function Add(tags)
		for _, tag in ipairs(tags) do
			list[#list + 1] = {
				text = FR.DungeonName(tag),
				check = function() return FR.DungeonShown(tag, FR.current) end,
				onClick = function() FR:SetDungeon(tag, not FR.DungeonShown(tag, FR.current)) end,
			}
		end
	end
	if #required > 0 then
		list[#list + 1] = { text = "|cffffd100" .. L["Required Dungeons"] .. "|r", disabled = true }
		Add(required)
		list[#list + 1] = { text = "|cffffd100" .. L["Optional Dungeons"] .. "|r", disabled = true }
	end
	Add(optional)
	list[#list + 1] = { divider = true }
	list[#list + 1] = { text = L["Recommended dungeons"], onClick = function() FR:SetRecommendedDungeons() end }
	list[#list + 1] = { text = L["Enable all dungeons"], onClick = function() FR:SetAllDungeons(true) end }
	list[#list + 1] = { text = L["Disable all dungeons"], onClick = function() FR:SetAllDungeons(false) end }
	return list
end

-- Items { text, onClick | children | check | divider, disabled } into a FlatMenu description.
local function AddItems(desc, items)
	for _, it in ipairs(items) do
		if it.divider then
			desc:CreateDivider()
		elseif it.children then
			local sub = desc:CreateButton(it.text)
			if #it.children > 22 then sub:SetScrollMode(22 * 20) end
			AddItems(sub, it.children)
		elseif it.check then
			local box = desc:CreateCheckbox(it.text, it.check, function() it.onClick() end)
			if it.disabled then box:SetEnabled(false) end
		elseif it.onClick then
			local button = desc:CreateButton(it.text, function() it.onClick() end)
			if it.disabled then button:SetEnabled(false) end
		else
			desc:CreateTitle(it.text)
		end
	end
end

-- Opens the menu at the cursor (right-click) or, with `below`, under `owner` (a
-- second click on the same owner closes it).
local function OpenMenu(owner, title, items, below)
	local function Generate(_, root)
		if title then root:CreateTitle(title) end
		AddItems(root, items)
	end
	-- A right-click menu that does not fit to the right of the cursor opens at the left side of the
	-- guide window instead of sliding over it (FlatMenu.lua, options.avoid).
	if below then Flat.Open(owner, Generate) else Flat.OpenAtCursor(owner, Generate, { avoid = main }) end
end
FR.OpenMenu = OpenMenu

function FR:ToggleGuideMenu()
	if not main:IsShown() then self:SetShown(true) end
	OpenMenu(nameBar, FR.L["Choose a guide"], self:BuildGuideMenu(), true)
end

-- Reads the current guide again (e.g. after changing the language).
function FR:ReloadGuide()
	local g = self.current
	if not g then return end
	local idx, stepKey = self.stepIndex, self:CurrentStepKey()
	g.steps, g.labels = nil, nil
	self.current = nil
	self.sideSeen, self.doneSeen = nil, nil   -- they hold the old step tables
	self.listDirty = true
	self:SetGuide(g.title, idx, stepKey)
end

-- Right-click menu on a step or on the guide bar (like RestedXP).
local function ShowOptionsMenuRaw(self, owner, stepIndex)
	local L = FR.L
	local items = {}
	local g = self.current
	if stepIndex and g then
		items[#items + 1] = { text = string.format(L["Go to step %d"], stepIndex), onClick = function() FR:GoToStep(stepIndex) end }
		if g.steps and g.steps[stepIndex] and not FR:IsManuallySkipped(g.steps[stepIndex]) then
			items[#items + 1] = { text = string.format(L["Skip step %d"], stepIndex), onClick = function() FR:SkipStep(stepIndex) end }
		end
		items[#items + 1] = { text = string.format(L["Report a problem with step %d"], stepIndex), onClick = function() FR:OpenReport(stepIndex) end }
	end
	items[#items + 1] = { text = L["Choose another guide"], children = self:BuildGuideMenu() }
	if self.BuildHistoryMenu then items[#items + 1] = { text = L["History"], children = self:BuildHistoryMenu() } end
	if g then
		-- Only for a guide that has tips (RestedXP: "Display Tips").
		if g.tips and #g.tips > 0 then
			items[#items + 1] = {
				text = L["Display Tips"],
				check = function() return FR:Get("showTips") end,
				onClick = function() FR:Set("showTips", not FR:Get("showTips")) end,
			}
		end
		items[#items + 1] = { text = L["Dungeons"], children = self:BuildDungeonMenu() }
		items[#items + 1] = {
			text = FR.HardcoreMode() and L["Deactivate Hardcore mode"] or L["Activate Hardcore mode"],
			disabled = FR.HardcoreToggleDisabled(g),
			onClick = function() FR:ToggleHardcore() end,
		}
		if not stepIndex then
			items[#items + 1] = { text = L["Skip step"], onClick = function() FR:SkipStep() end }
		end
		items[#items + 1] = { text = L["Reload guide"], onClick = function() FR:ReloadGuide() end }
		items[#items + 1] = { text = L["Restart guide"], onClick = function() FR:ConfirmRestart() end }
		if not stepIndex then
			items[#items + 1] = { text = L["Report a problem..."], onClick = function() FR:OpenReport() end }
		end
		if g.imported then
			items[#items + 1] = { text = L["Delete imported guide"], onClick = function() FR:ConfirmDeleteImport(g) end }
		end
	end
	-- Only when there is a farming guide to switch to (or the mode is on).
	if (FR.farmGuides or 0) > 0 or FR:IsGoldMode() then
		items[#items + 1] = {
			text = FR:IsGoldMode() and L["Activate the Quest Guide mode"] or L["Activate the Gold Assistant mode"],
			onClick = function() FR:ToggleGoldMode() end,
		}
	end
	items[#items + 1] = { text = L["Import guide..."], onClick = function() FR:OpenImport() end }
	-- Group members' steps, when the window is hidden or the feature is off (RestedXP: "Show Active Party Steps").
	if FR.Party and FR.Party.CanShow() then
		items[#items + 1] = { text = L["Show Active Party Steps"], onClick = function() FR.Party.Show() end }
	end
	-- RestedXP hides the report in gold mode.
	if FR:Get("enableTracker") and not FR:IsGoldMode() then
		items[#items + 1] = { text = L["Leveling report"], onClick = function() FR:OpenLevelReport() end }
	end
	items[#items + 1] = { divider = true }
	items[#items + 1] = { text = L["Options..."], onClick = function() FR:ToggleSettings() end }
	items[#items + 1] = { text = FR:Get("locked") and L["Unlock window"] or L["Lock window"],
		onClick = function() FR:Set("locked", not FR:Get("locked")) end }
	items[#items + 1] = { text = L["Hide window"], onClick = function() FR:SetShown(false) end }
	items[#items + 1] = { text = L["Close"], onClick = function() end }
	OpenMenu(owner or nameBar, "ForeverRoute", items)
end

-- An error while the menu is built shows in the chat instead of the menu just not opening.
function FR:ShowOptionsMenu(owner, stepIndex)
	return FR.Safe("right-click menu", ShowOptionsMenuRaw, self, owner, stepIndex)
end

-- Kept for slash command / minimap button callers.
function FR:ShowPicker() self:ToggleGuideMenu() end

-- Timing of the window update, for "/fr perf": how long one update takes,
-- so it can be told whether a lag comes from this addon.
FR.perf = { n = 0, total = 0, max = 0, last = 0 }
local rawUpdateUI = FR.UpdateUI
function FR:UpdateUI(...)
	local start = debugprofilestop and debugprofilestop()
	rawUpdateUI(self, ...)
	if start then
		local dt = debugprofilestop() - start
		local p = self.perf
		p.n, p.total, p.last = p.n + 1, p.total + dt, dt
		if dt > p.max then p.max = dt end
	end
end

function FR:PrintPerf(reset)
	local p = self.perf
	if reset then p.n, p.total, p.max, p.last = 0, 0, 0, 0 end
	if p.n == 0 then self:Print(FR.L["No window update measured yet."]) return end
	self:Print(string.format(FR.L["Window updates: %d, average %.2f ms, slowest %.2f ms, last %.2f ms"],
		p.n, p.total / p.n, p.max, p.last))
end
