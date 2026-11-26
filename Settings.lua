-- Settings: a list of sections on the left and scrolling pages on the right, inside the game's
-- options window (Options > AddOns > ForeverRoute), like RestedXP. Falls back to a standalone
-- window on clients without that options API.
--
-- Every page is a column of rows laid out by Page:Layout (no hand-placed offsets): a header, a
-- check box, a slider, a row of choices, a row of buttons or a note. The widgets are flat and take
-- their colours from the chosen theme (FR.Theme), like the guide window.
local _, ns = ...
local FR = ns.FR

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE = "Interface\\Buttons\\WHITE8X8"
local C = FR.colors
local Text = FR.MakeText

local PAD = 16    -- inside a page, left and right
local GAP = 8     -- between two rows
local EDGE = { 1, 1, 1, 0.10 }

local panel = CreateFrame("Frame", "ForeverRouteSettings", UIParent)
FR.settingsFrame = panel
panel.name = "ForeverRoute"
panel:SetSize(640, 560)   -- the game's options window resizes it when it is shown there
panel:Hide()

-- Styling ------------------------------------------------------------------------------

local styled = {}
local function Styled(fn)
	styled[#styled + 1] = fn
	fn(FR.Theme())
end
local function Restyle()
	local th = FR.Theme()
	for _, fn in ipairs(styled) do fn(th) end
end

local function Frame(parent, kind) return CreateFrame(kind or "Frame", nil, parent, BACKDROP) end

local function Flat(f, fill, edge)
	if not f.SetBackdrop then return end
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
	f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local function Scaled(c, k, a) return { c[1] * k, c[2] * k, c[3] * k, a or 1 } end

-- Header of the panel ------------------------------------------------------------------

local logo = panel:CreateTexture(nil, "ARTWORK")
logo:SetTexture("Interface\\AddOns\\ForeverRoute\\Textures\\Logo")
logo:SetSize(32, 32)
logo:SetPoint("TOPLEFT", 16, -12)

local title = Text(panel, FR.fontUITitle)
title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
title:SetText("ForeverRoute")
local version = Text(panel, FR.fontUISmall)
version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 0)
version:SetText("v" .. tostring(FR.version))
version:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
local desc = Text(panel, FR.fontUISmall)
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
desc:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
FR:Loc(desc, "Step-by-step leveling guide. Type /fr help for chat commands.")
Styled(function(th) title:SetTextColor(th.accent[1], th.accent[2], th.accent[3]) end)

-- Sidebar and scrolling content ----------------------------------------------------------

local sidebar = Frame(panel)
sidebar:SetPoint("TOPLEFT", 12, -56)
sidebar:SetPoint("BOTTOMLEFT", 12, 12)
sidebar:SetWidth(172)
Styled(function() Flat(sidebar, { 0, 0, 0, 0.30 }, EDGE) end)

local content = Frame(panel)
content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
content:SetPoint("BOTTOMRIGHT", -12, 12)
Styled(function() Flat(content, { 0, 0, 0, 0.30 }, EDGE) end)

local scroll = CreateFrame("ScrollFrame", nil, content)
scroll:SetPoint("TOPLEFT", 1, -1)
scroll:SetPoint("BOTTOMRIGHT", -12, 1)

-- A thin scroll bar: track and a thumb that can be dragged.
local bar = CreateFrame("Frame", nil, content)
bar:SetWidth(6)
bar:SetPoint("TOPRIGHT", -3, -3)
bar:SetPoint("BOTTOMRIGHT", -3, 3)
bar.track = bar:CreateTexture(nil, "BACKGROUND")
bar.track:SetTexture(WHITE)
bar.track:SetAllPoints()
local thumb = CreateFrame("Button", nil, bar)
thumb:SetWidth(6)
thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
thumb.tex:SetTexture(WHITE)
thumb.tex:SetAllPoints()
Styled(function(th)
	bar.track:SetVertexColor(1, 1, 1, 0.05)
	thumb.tex:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 0.55)
end)

local function UpdateBar()
	local range = scroll:GetVerticalScrollRange() or 0
	local h = bar:GetHeight() or 0
	if range < 1 or h < 10 then bar:Hide() return end
	bar:Show()
	local view = scroll:GetHeight() or h
	local size = math.max(28, h * view / (view + range))
	thumb:SetHeight(size)
	thumb:ClearAllPoints()
	thumb:SetPoint("TOP", bar, "TOP", 0, -((scroll:GetVerticalScroll() or 0) / range) * (h - size))
end

scroll:EnableMouseWheel(true)
scroll:SetScript("OnMouseWheel", function(self, delta)
	local range = self:GetVerticalScrollRange() or 0
	self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 48)))
end)
scroll:SetScript("OnVerticalScroll", UpdateBar)
scroll:SetScript("OnScrollRangeChanged", UpdateBar)

local dragFrom
thumb:SetScript("OnMouseDown", function(self)
	local _, y = GetCursorPosition()
	dragFrom = { y = y / (self:GetEffectiveScale() or 1), scroll = scroll:GetVerticalScroll() or 0 }
	self:SetScript("OnUpdate", function(s)
		if not dragFrom then return end
		local _, cy = GetCursorPosition()
		cy = cy / (s:GetEffectiveScale() or 1)
		local range = scroll:GetVerticalScrollRange() or 0
		local travel = (bar:GetHeight() or 1) - (s:GetHeight() or 0)
		if travel < 1 then return end
		local value = dragFrom.scroll + (dragFrom.y - cy) / travel * range
		scroll:SetVerticalScroll(math.max(0, math.min(range, value)))
	end)
end)
thumb:SetScript("OnMouseUp", function(self)
	dragFrom = nil
	self:SetScript("OnUpdate", nil)
end)

-- Pages ----------------------------------------------------------------------------------

local pages, controls = {}, {}
local selected
local category, standalone   -- how the panel was registered (see FR:RegisterOptions)

local Page = {}
Page.__index = Page

function Page:Add(item)
	self.items[#self.items + 1] = item
	return item
end

-- Puts one row at x, y with the given width and returns its height. The row's frame needs a height
-- of its own (a frame without one gets no clicks and its bottom-anchored parts sit at its top).
local function Place(page, item, x, y, width)
	local f = item.frame
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", page.frame, "TOPLEFT", x, y)
	f:SetWidth(width)
	if item.place then item.place(width) end
	local h = item.height(width)
	f:SetHeight(math.max(1, h))
	return h
end

-- Puts the rows one under the other. Rows marked `half` share a line two by two.
function Page:Layout()
	local total = self.width or 520
	local w = math.max(220, total - 2 * PAD)
	self.frame:SetWidth(total)
	local items = self.items
	self.laid = 0
	local y, i, shown = -PAD, 1, false
	while i <= #items do
		local it = items[i]
		if it.hidden then
			it.frame:Hide()
			i = i + 1
		else
			it.frame:Show()
			if shown then y = y - (it.before or 0) end
			shown = true
			local nx = items[i + 1]
			local hw = math.floor((w - GAP) / 2)
			local h
			if it.half and nx and nx.half and not nx.hidden then
				nx.frame:Show()
				h = math.max(Place(self, it, PAD, y, hw), Place(self, nx, PAD + hw + GAP, y, hw))
				i = i + 2
			else
				h = Place(self, it, PAD, y, it.half and hw or w)
				i = i + 1
			end
			self.laid = (self.laid or 0) + 1
			y = y - h - GAP
		end
	end
	self.frame:SetHeight(math.max(10, -y + PAD - GAP))
	if selected == self.index then UpdateBar() end
end

local function Control(c) controls[#controls + 1] = c end

local function Tip(owner, label, tip, extra)
	local lines = { FR.L[label] }
	if tip then lines[#lines + 1] = FR.L[tip] end
	if extra then lines[#lines + 1] = extra end
	FR.ShowTooltip(owner, lines)
end

-- A title for the rows that follow.
function Page:Header(label)
	local f = CreateFrame("Frame", nil, self.frame)
	f.text = Text(f, FR.fontUITitle)
	f.text:SetPoint("TOPLEFT", 0, -3)
	FR:Loc(f.text, label)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetTexture(WHITE)
	f.line:SetPoint("BOTTOMLEFT")
	f.line:SetPoint("BOTTOMRIGHT")
	f.line:SetHeight(1)
	Styled(function(th)
		f.text:SetTextColor(th.accent[1], th.accent[2], th.accent[3])
		f.line:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 0.35)
	end)
	return self:Add({ frame = f, height = function() return 24 end, before = #self.items > 0 and 14 or 0 })
end

-- A box with a label. opts: { get = fn, set = fn(value), locked = fn -> true/false/nil, half = true }
-- `locked` returning a value fixes the box to it.
function Page:Check(key, label, tip, opts)
	opts = opts or {}
	local f = Frame(self.frame, "Button")
	f.box = Frame(f)
	f.box:SetSize(18, 18)
	f.box:SetPoint("LEFT", 0, 0)
	f.mark = f.box:CreateTexture(nil, "OVERLAY")
	f.mark:SetTexture(WHITE)
	f.mark:SetPoint("TOPLEFT", 4, -4)
	f.mark:SetPoint("BOTTOMRIGHT", -4, 4)
	f.label = Text(f, FR.fontUIBody)
	f.label:SetPoint("LEFT", f.box, "RIGHT", 8, 0)
	f.label:SetPoint("RIGHT", f, "RIGHT", -2, 0)
	f.label:SetJustifyH("LEFT")
	f.label:SetWordWrap(false)
	FR:Loc(f.label, label)

	local function paint()
		local th = FR.Theme()
		local on = f.checked
		Flat(f.box, th.row, (on or f.hover) and th.accent or EDGE)
		f.mark:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 1)
		f.mark:SetShown(on and true or false)
		local a = f.locked and 0.5 or 1
		f.label:SetTextColor(C.text[1] * a, C.text[2] * a, C.text[3] * a)
	end
	Styled(paint)

	f:SetScript("OnClick", function()
		if f.locked then return end
		local value = not f.checked
		if opts.set then opts.set(value) else FR:Set(key, value) end
		f.checked = value
		paint()
	end)
	f:SetScript("OnEnter", function() f.hover = true; paint(); Tip(f, label, tip) end)
	f:SetScript("OnLeave", function() f.hover = false; paint(); GameTooltip:Hide() end)
	function f:Refresh()
		local locked = opts.locked and opts.locked()
		if locked ~= nil then
			self.checked, self.locked = locked and true or false, true
		else
			self.locked = false
			local value
			if opts.get then value = opts.get() else value = FR:Get(key) end
			self.checked = value and true or false
		end
		paint()
	end
	Control(f)
	return self:Add({ frame = f, height = function() return 24 end, half = opts.half })
end

-- A value between minV and maxV. opts: { get = fn -> number, set = fn(number) }
function Page:Slider(key, label, minV, maxV, step, fmt, tip, opts)
	opts = opts or {}
	local function get()
		if opts.get then return opts.get() end
		return FR:Get(key)
	end
	local f = CreateFrame("Frame", nil, self.frame)
	f.label = Text(f, FR.fontUIBody)
	f.label:SetPoint("TOPLEFT", 0, -1)
	f.label:SetPoint("RIGHT", f, "RIGHT", -70, 0)
	f.label:SetJustifyH("LEFT")
	f.label:SetWordWrap(false)
	FR:Loc(f.label, label)
	f.value = Text(f, FR.fontUIBody)
	f.value:SetPoint("TOPRIGHT", 0, -1)
	f.value:SetJustifyH("RIGHT")

	local s = CreateFrame("Slider", nil, f)
	s:SetPoint("TOPLEFT", 0, -22)
	s:SetPoint("TOPRIGHT", 0, -22)
	s:SetHeight(16)
	s:SetOrientation("HORIZONTAL")
	s:SetThumbTexture(WHITE)
	local knob = s:GetThumbTexture()
	knob:SetSize(8, 16)
	s.track = s:CreateTexture(nil, "BACKGROUND")
	s.track:SetTexture(WHITE)
	s.track:SetPoint("LEFT")
	s.track:SetPoint("RIGHT")
	s.track:SetHeight(4)
	s.fill = s:CreateTexture(nil, "ARTWORK")
	s.fill:SetTexture(WHITE)
	s.fill:SetPoint("LEFT")
	s.fill:SetPoint("RIGHT", knob, "CENTER")
	s.fill:SetHeight(4)
	Styled(function(th)
		f.label:SetTextColor(C.text[1], C.text[2], C.text[3])
		f.value:SetTextColor(th.accent[1], th.accent[2], th.accent[3])
		s.track:SetVertexColor(th.hl[1], th.hl[2], th.hl[3], 1)
		s.fill:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 0.9)
		knob:SetVertexColor(C.text[1], C.text[2], C.text[3], 1)
	end)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

	local updating = false
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		f.value:SetText(string.format(fmt, v))
		if not updating and math.abs((get() or 0) - v) > 1e-6 then
			if opts.set then opts.set(v) else FR:Set(key, v) end
		end
	end)
	local function tooltip()
		Tip(f, label, tip, string.format("%s: %s - %s", FR.L["Range"], string.format(fmt, minV), string.format(fmt, maxV)))
	end
	s:SetScript("OnEnter", tooltip)
	s:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:EnableMouse(true)
	f:SetScript("OnEnter", tooltip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function f:Refresh()
		updating = true
		s:SetValue(get() or minV)
		f.value:SetText(string.format(fmt, get() or minV))
		updating = false
	end
	Control(f)
	return self:Add({ frame = f, height = function() return 42 end })
end

-- A row of choices, four to a line. options = { { value, label [, raw = true] [, font = key] }, ... };
-- the label is a translated key (or plain text with raw = true). opts: { get = fn, set = fn(value) }.
function Page:Choice(key, label, tip, options, opts)
	opts = opts or {}
	local function get()
		if opts.get then return opts.get() end
		return FR:Get(key)
	end
	local f = CreateFrame("Frame", nil, self.frame)
	f.label = Text(f, FR.fontUIBody)
	f.label:SetPoint("TOPLEFT", 0, -1)
	f.label:SetJustifyH("LEFT")
	FR:Loc(f.label, label)
	f:EnableMouse(true)
	f:SetScript("OnEnter", function() if tip then Tip(f, label, tip) end end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local cols = math.min(#options, 4)
	local rows = math.ceil(#options / cols)
	f.buttons = {}
	for i, opt in ipairs(options) do
		local b = Frame(f, "Button")
		b:SetHeight(22)
		b.text = Text(b, FR.fontUISmall)
		b.text:SetPoint("CENTER")
		b.text:SetJustifyH("CENTER")
		if opt.font then
			if b.text:SetFont(FR.FontFile(false, opt.font), 12, "") == false then b.text:SetFont("Fonts\\ARIALN.TTF", 12, "") end
		end
		if opt.raw then b.text:SetText(opt[2]) else FR:Loc(b.text, opt[2]) end
		b.value = opt[1]
		b:SetScript("OnClick", function()
			if opts.set then opts.set(opt[1]) else FR:Set(key, opt[1]) end
			f:Refresh()
		end)
		b:SetScript("OnEnter", function() b.hover = true; f:Paint() end)
		b:SetScript("OnLeave", function() b.hover = false; f:Paint() end)
		f.buttons[i] = b
	end
	function f:Paint()
		local th = FR.Theme()
		local value = get()
		for _, b in ipairs(self.buttons) do
			if value == b.value then
				Flat(b, Scaled(th.accent, 0.45), th.accent)
				b.text:SetTextColor(1, 1, 1)
			else
				Flat(b, b.hover and th.hl or th.row, b.hover and th.accent or EDGE)
				b.text:SetTextColor(C.text[1], C.text[2], C.text[3])
			end
		end
	end
	Styled(function() f:Paint() end)
	f.Refresh = f.Paint
	Control(f)
	return self:Add({
		frame = f,
		height = function() return 22 + rows * 26 end,
		place = function(w)
			local gap = 4
			local bw = math.floor((w - gap * (cols - 1)) / cols)
			for i, b in ipairs(f.buttons) do
				b:SetWidth(bw)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", f, "TOPLEFT", ((i - 1) % cols) * (bw + gap), -20 - math.floor((i - 1) / cols) * 26)
			end
		end,
	})
end

-- Buttons side by side, wrapping to the next line. list = { { label, tip, onClick }, ... }
-- Returns the page item and the buttons.
function Page:Buttons(list)
	local f = CreateFrame("Frame", nil, self.frame)
	f.buttons = {}
	for i, def in ipairs(list) do
		local b = Frame(f, "Button")
		b:SetHeight(26)
		b.text = Text(b, FR.fontUIBody)
		b.text:SetPoint("CENTER")
		FR:Loc(b.text, def[1])
		b.label, b.tip = def[1], def[2]
		b:SetScript("OnClick", def[3])
		b:SetScript("OnEnter", function() b.hover = true; b:Paint(); if b.tip then Tip(b, b.label, b.tip) end end)
		b:SetScript("OnLeave", function() b.hover = false; b:Paint(); GameTooltip:Hide() end)
		function b:Paint()
			local th = FR.Theme()
			Flat(self, self.hover and th.hl or th.row, self.hover and th.accent or EDGE)
			self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		end
		Styled(function() b:Paint() end)
		f.buttons[i] = b
	end
	local rows = 1
	local item = self:Add({
		frame = f,
		height = function() return rows * 32 - 6 end,
		place = function(w)
			local x, y = 0, 0
			rows = 1
			for _, b in ipairs(f.buttons) do
				local bw = math.max(120, math.ceil((b.text:GetStringWidth() or 90) + 28))
				if x > 0 and x + bw > w then x, y, rows = 0, y + 32, rows + 1 end
				b:SetWidth(bw)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
				x = x + bw + 8
			end
		end,
	})
	return item, f.buttons
end

-- A paragraph of small, dim text. Returns the item: item.fs:SetText(...) changes it (then call page:Layout()).
function Page:Note(key, bright)
	local f = CreateFrame("Frame", nil, self.frame)
	local fs = Text(f, bright and FR.fontUIBody or FR.fontUISmall)
	fs:SetPoint("TOPLEFT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	if key then FR:Loc(fs, key) end
	Styled(function()
		if bright then fs:SetTextColor(C.text[1], C.text[2], C.text[3])
		else fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
	end)
	return self:Add({
		frame = f, fs = fs,
		place = function(w) fs:SetWidth(w) end,
		height = function() return math.max(4, (fs:GetStringHeight() or 12) + 2) end,
	})
end

-- A row that fails to build must not blank the page: the page gets a red line with the error instead
-- (and /fr settings debug counts them).
local NOOP = { SetText = function() end, SetShown = function() end }
local function BuildFailed(page, name, err)
	local f = CreateFrame("Frame", nil, page.frame)
	local fs = Text(f, FR.fontUISmall)
	fs:SetPoint("TOPLEFT", 0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:SetTextColor(1, 0.35, 0.35)
	fs:SetText(name .. " failed: " .. (tostring(err):match("^[^\n]*") or "?"))
	page:Add({
		frame = f, fs = fs,
		place = function(w) fs:SetWidth(w) end,
		height = function() return math.max(14, (fs:GetStringHeight() or 12) + 2) end,
	})
	FR.settingsErrors = (FR.settingsErrors or 0) + 1
end
for _, name in ipairs({ "Header", "Check", "Slider", "Choice", "Buttons", "Note" }) do
	local build = Page[name]
	Page[name] = function(self, ...)
		local args, n = { ... }, select("#", ...)
		local res = { xpcall(function() return build(self, unpack(args, 1, n)) end, function(e) return tostring(e) end) }
		if res[1] then return unpack(res, 2, 3) end
		BuildFailed(self, name, res[2])
		return { frame = CreateFrame("Frame"), hidden = true, fs = NOOP, height = function() return 0 end }, { { text = NOOP } }
	end
end

local function NewPage(label)
	local p = setmetatable({ label = label, items = {} }, Page)
	p.frame = CreateFrame("Frame", nil, scroll)
	p.frame:SetSize(400, 100)
	p.frame:Hide()
	pages[#pages + 1] = p
	p.index = #pages

	local b = Frame(sidebar, "Button")
	b:SetHeight(30)
	b:SetPoint("TOPLEFT", 6, -6 - (p.index - 1) * 32)
	b:SetPoint("TOPRIGHT", -6, -6 - (p.index - 1) * 32)
	b.mark = b:CreateTexture(nil, "OVERLAY")
	b.mark:SetTexture(WHITE)
	b.mark:SetPoint("TOPLEFT")
	b.mark:SetPoint("BOTTOMLEFT")
	b.mark:SetWidth(3)
	b.text = Text(b, FR.fontUIBody)
	b.text:SetPoint("LEFT", 14, 0)
	b.text:SetPoint("RIGHT", -6, 0)
	b.text:SetJustifyH("LEFT")
	b.text:SetWordWrap(false)
	FR:Loc(b.text, label)
	function b:Paint()
		local th = FR.Theme()
		local on = selected == p.index
		Flat(self, on and th.hl or (self.hover and th.row or { 0, 0, 0, 0 }), { 0, 0, 0, 0 })
		self.mark:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 1)
		self.mark:SetShown(on)
		if on then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end
	end
	b:SetScript("OnClick", function() panel:Select(p.index) end)
	b:SetScript("OnEnter", function() b.hover = true; b:Paint() end)
	b:SetScript("OnLeave", function() b.hover = false; b:Paint() end)
	Styled(function() b:Paint() end)
	p.nav = b
	return p
end

function panel:Select(i)
	local p = pages[i]
	if not p then return end
	selected = i
	for n, q in ipairs(pages) do
		if n == i then q.frame:Show() else q.frame:Hide() end
		q.nav:Paint()
	end
	scroll:SetScrollChild(p.frame)
	p.width = math.max(300, scroll:GetWidth() or 520)
	p:Layout()
	scroll:SetVerticalScroll(0)
	self.tab = i
	UpdateBar()
end

-- The window got another size (the game's options window is resized, or the panel shows for the first time).
scroll:SetScript("OnSizeChanged", function(self, width)
	local p = pages[selected or 0]
	if p and width and width > 50 and math.abs((p.width or 0) - width) > 0.5 then
		p.width = width
		p:Layout()
	end
	UpdateBar()
end)

-- The texts changed (another language): the rows may have another height.
local baseApplyLocale = FR.ApplyLocale
function FR:ApplyLocale()
	baseApplyLocale(self)
	if panel:IsShown() then self:RefreshSettings() end
end

-- Contents -------------------------------------------------------------------------------

-- RestedXP 4.11.36: loot sparkles. The game's outline mode hides the sparkle of lootable objects;
-- this puts the CVars the way RestedXP does (on) or back to their defaults (off).
local SPARKLE_CVARS = { "graphicsOutlineMode", "OutlineEngineMode", "raidGraphicsOutlineMode", "RAIDOutlineEngineMode" }
local function CVarOn(name)
	local get = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
	if not get then return false end
	local ok, v = pcall(get, name)
	return ok and v and true or false
end

local LANGUAGE_OPTIONS = { { "auto", "Automatic" } }
for _, l in ipairs(FR.OfferedLanguages()) do LANGUAGE_OPTIONS[#LANGUAGE_OPTIONS + 1] = { l[1], l[2], raw = true } end

-- General ----------------------------------------------------------------------------------
local general = NewPage("General")
general:Header("Progress")
general:Check("autoAdvance", "Auto-advance finished steps",
	"Moves to the next step as soon as the current one is done.")
general:Check("autoArrive", "Complete travel steps on arrival",
	"\"Go to\" steps tick themselves off when you reach the spot.")
general:Check("autoAccept", "Accept quests automatically",
	"Accepts the quests of the current step. Hold Shift to do it by hand.")
general:Check("autoTurnin", "Turn in quests automatically",
	"Turns in the quests of the current step when there is at most one reward. Hold Shift to do it by hand.")
general:Check("autoGossip", "Pick talk options automatically",
	"Selects the options of an NPC's talk window that the current step asks for (e.g. to set your hearthstone or train). Hold Shift to do it by hand.")
general:Check("autoBank", "Deposit and withdraw at the bank",
	"A step with \"Deposit\" or \"Withdraw\" items moves them between your bags and the bank as soon as you open the bank window (whole stacks, only the items the step lists). Hold Shift to do it by hand.")
general:Check("autoFly", "Fly automatically",
	"A \"Fly to ...\" step takes the flight as soon as you open the map of a flight master. Hold Shift to choose by hand.")
general:Check("skipUnavailable", "Skip quests I cannot accept",
	"Passes a step whose quest you cannot take (a quest before it is missing, you are too low a level, the quest excludes one you have, or it is not for your race or class). Needs the Questie addon. Going back to the step shows it again.")
general:Check("missingQuestPrompt", "Offer a route for missing quests",
	"When a step needs a quest that is not in your quest log (or cannot be accepted because a quest before it is missing), a card offers to create a route that gets it, or to skip it, and lists the later quests you may miss. Uses the Questie addon when it is installed.")
general:Check("hearthFallback", "Travel step when the hearthstone does not fit",
	"A \"Hearth to ...\" step is hidden while your hearthstone is bound somewhere else or cooling down, and a step that sends you there by flight path or on foot is shown instead. /fr bind shows how the guide reads your hearthstone.")
general:Check("autoPassNotice", "Tell me when steps are passed",
	"When the guide passes steps that were already done in the game (or that need a quest you do not have), a note above the steps says so. Click it to go back to the first of them. Right-click menu > History lists them all.")
general:Check("versionChannel", "Check for new versions",
	"Joins a hidden chat channel where ForeverRoute users share their version number (nothing else), so you hear when a newer version is out. Guild and group members are always checked.")
general:Slider("arriveRadius", "Arrival radius", 3, 40, 1, "%d yd",
	"How close you have to get to a spot for a travel step to count as reached.")
general:Choice("hardcoreMode", "Hardcore mode",
	"Shows the deathless variant of the steps that differ between hardcore and softcore. Automatic follows the server.",
	{ { "auto", "Automatic" }, { "on", "On" }, { "off", "Off" } })

general:Choice("language", "Language",
	"The language of the guides and the menus. Automatic follows the game. A guide that has no translation stays in English.",
	LANGUAGE_OPTIONS, {
		get = function() return FR:Get("language") end,
		set = function(v)
			FR:Set("language", v)
			FR:SwitchGuideLanguage()
		end,
	})

general:Header("Guide")
general:Buttons({
	{ "Choose a guide", "Opens the guide menu.", function() FR:ToggleGuideMenu() end },
	{ "Restart guide", "Back to step 1, clears manual ticks of this guide.", function() FR:ConfirmRestart() end },
	{ "Report a problem", "Opens a text with the details of the current step to copy and send to the author.", function() FR:OpenReport() end },
	{ "Import guide", "Adds a guide from its text (RestedXP's text format).", function() FR:OpenImport() end },
})

general:Header("Reset")
general:Buttons({
	{ "Reset positions", "Moves the window and arrow back to their default spots.", function() FR:ResetPositions() end },
	{ "Restore defaults", "Resets every setting.", function()
		FR:Confirm(FR.L["Reset every setting to its default?"], function()
			for k, v in pairs(FR.defaults) do
				if k ~= "minimapAngle" and k ~= "hidden" then ForeverRouteDB[k] = v end
			end
			FR.listDirty = true
			FR:ApplySettings()
			FR:RefreshSettings()
			Restyle()
		end)
	end },
})

-- Interface --------------------------------------------------------------------------------
local interface = NewPage("Interface")
interface:Header("Interface")
interface:Check("showMinimap", "Show minimap button", "Shows the ForeverRoute button at the minimap.")
interface:Check("locked", "Lock window and arrow", "Prevents dragging and resizing.")
interface:Check("showActiveItems", "Show active items",
	"Buttons for quest items the current step needs. Click to use.")
interface:Check("showActiveTargets", "Show active targets",
	"Buttons that target the NPCs and enemies of the current step.")
interface:Check("markTargets", "Mark targets with raid icons",
	"Clicking a target button also puts a raid icon on the creature: skull, cross and square for enemies, star, circle, diamond and triangle for NPCs.")
interface:Check("targetMacro", "Create the targeting macro",
	"Keeps a game macro called FRTarget up to date with the creatures of the current step. Put it on an action bar: one press targets the nearest of them and marks it with a raid icon.")
interface:Check("lootSparkle", "Show object sparkles",
	"Shows the sparkle on lootable objects and quest objects by turning the game's outline mode off. Switching it back restores the game's defaults. Needs a /reload to take full effect.", {
		get = function()
			if not CVarOn("outlineModeShowLootEffectWhenDisabled") then return false end
			for _, name in ipairs(SPARKLE_CVARS) do if CVarOn(name) then return false end end
			return true
		end,
		set = function(value)
			local set = (C_CVar and C_CVar.SetCVar) or SetCVar
			local default = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
			if not set then return end
			local all = { "outlineModeShowLootEffectWhenDisabled", unpack(SPARKLE_CVARS) }
			for _, name in ipairs(all) do
				local v
				if value then
					v = (name == "outlineModeShowLootEffectWhenDisabled") and 1 or 0
				elseif default then
					local ok, d = pcall(default, name)
					if ok then v = d end
				end
				if v ~= nil then pcall(set, name, v) end
			end
			FR:Print(FR.L["Object sparkles changed. Type /reload to apply it fully."])
		end,
	})
interface:Slider("barSize", "Button size of active items / targets", 18, 56, 1, "%d px",
	"Size of the buttons for the active items and targets.")

-- Guide window -----------------------------------------------------------------------------
local window = NewPage("Guide Window")
window:Header("Layout")
window:Check("showList", "Show step list", "The scrollable list of all steps under the guide bar.")
window:Check("hideCompleted", "Hide finished steps in the list", "Finished steps leave the step list.")
window:Slider("width", "Window width", 200, 1000, 5, "%d px", "Width of the guide window.")
window:Slider("height", "Step list height", 60, 1200, 5, "%d px", "Height of the step list under the guide bar.")
window:Slider("scale", "Scale", 0.6, 1.6, 0.05, "%.2f", "Size of the whole guide window.")
window:Header("Look")
local themeOptions = {}
for _, key in ipairs(FR.THEME_ORDER) do themeOptions[#themeOptions + 1] = { key, FR.THEMES[key].name } end
window:Choice("theme", "Colour theme", "The colours of the guide window and of these settings.", themeOptions, {
	set = function(v)
		FR:Set("theme", v)
		Restyle()
	end,
})
window:Slider("alpha", "Background opacity", 0.2, 1, 0.05, "%.2f", "How solid the background of the guide window is.")
window:Slider("fontSize", "Font size", 8, 16, 1, "%d", "Text size in the guide window.")
local fontOptions = {}
for _, key in ipairs(FR.FONT_ORDER) do fontOptions[#fontOptions + 1] = { key, FR.FONTS[key].name, raw = true, font = key } end
window:Choice("font", "Font", "The font of the guide window. Each name is written in its own font.", fontOptions)

-- Navigation -------------------------------------------------------------------------------
local nav = NewPage("Navigation")
nav:Header("Waypoint arrow")
nav:Check("showArrow", "Show waypoint arrow", "Points to the next location.")
nav:Slider("arrowScale", "Arrow size", 0.5, 2.0, 0.05, "%.2f", "Size of the waypoint arrow.")
nav:Buttons({
	{ "Center navigation bar", "Puts the bar at the top of the screen, centred, 20 pixels from the edge.", function() FR:CenterArrow() end },
})
nav:Header("Map")
nav:Check("mapPins", "Show step numbers on the world map",
	"Numbers for the current step and the next five. Hover a number to see the step.")
nav:Check("minimapPins", "Show step numbers on the minimap", "The same numbers on the minimap.")

-- Dungeons: the steps for a dungeon show only while its box is ticked.
-- A dungeon the open guide's group asks for is fixed on (RestedXP ".enabledungeon").
local dungeons = NewPage("Dungeons")
dungeons:Header("Optional dungeons")
dungeons:Note("Steps for a dungeon only show while it is ticked. Ticking one in a route without dungeons moves you to the matching route with dungeons. The route's own choice is only the starting point.")
for _, d in ipairs(FR.DUNGEONS) do
	local tag = d[1]
	dungeons:Check("dungeon:" .. tag, FR.DungeonName(tag), "Shows the steps of this dungeon in your route.", {
		half = true,
		get = function() return FR.DungeonShown(tag, FR.current) end,
		set = function(value) FR:SetDungeon(tag, value) end,
	})
end
dungeons:Buttons({
	{ "Recommended dungeons", "Turns on the dungeons that pay off most for your class and faction (RestedXP's rating of travel time, quests and class) and the others off.", function() FR:SetRecommendedDungeons() end },
	{ "Enable all dungeons", "Ticks every dungeon.", function() FR:SetAllDungeons(true) end },
	{ "Disable all dungeons", "Unticks every dungeon.", function() FR:SetAllDungeons(false) end },
})
dungeons:Header("Route")
local routeNote = dungeons:Note(nil, true)
local routeItem, routeButtons = dungeons:Buttons({
	{ "Switch route", "Changes between the route with dungeon steps and the one without.", function()
		local g = FR.current
		if g then FR:SwitchDungeonRoute(not FR.IsDungeonRoute(g)) end
	end },
})
local requiredNote = dungeons:Note()
Control({
	Refresh = function()
		local g = FR.current
		local L2 = FR.L
		local required = FR.SplitDungeons(g)
		if #required > 0 then
			local names = {}
			for _, tag in ipairs(required) do names[#names + 1] = FR.DungeonName(tag) end
			requiredNote.fs:SetText(L2["Required Dungeons"] .. ": " .. table.concat(names, ", ") .. "\n"
				.. L2["Optional Dungeons"] .. ": " .. L2["These dungeons are less efficient for your class, but you can select them if you'd like to include them in your route."])
		else
			requiredNote.fs:SetText("")
		end
		routeItem.hidden = false
		if not g then
			routeNote.fs:SetText("")
			routeItem.hidden = true
		elseif FR.IsDungeonRoute(g) then
			routeNote.fs:SetText(L2["Open guide: route with dungeons."])
			if FR.DungeonRouteGroup(g, false) then
				routeButtons[1].text:SetText(L2["Switch to the route without dungeons"])
			else
				routeItem.hidden = true
			end
		elseif FR.DungeonRouteGroup(g, true) then
			routeNote.fs:SetText(L2["Open guide: route without dungeons."])
			routeButtons[1].text:SetText(L2["Switch to the route with dungeons"])
		else
			routeNote.fs:SetText(L2["This guide has no dungeon steps."])
			routeItem.hidden = true
		end
		dungeons:Layout()
	end,
})

-- Inventory: the Inventory Manager (Inventory.lua), like RestedXP's.
local inventory = NewPage("Inventory")
inventory:Header("Inventory Manager")
inventory:Check("enableInventoryManager", "Enable Inventory Manager",
	"The switch for everything on this page: it finds the junk in your bags (grey items and the ones you mark yourself). Off: nothing below does anything.")
inventory:Check("showJunkIcon", "Show junk item indicator",
	"Puts a gold coin on the junk items in your bags (the game's bags and Baganator). In Baganator, choose ForeverRoute as the junk plugin (Settings > Icon); your choice there is never changed.")
inventory:Check("rightClickJunk", "Toggle junk with modified right click",
	"Right click on an item in your bags while holding the key below marks it as junk, or as useful if it was junk. /fr junk lists what you marked.")
inventory:Choice("rightClickMod", "Right Click Modifier", "The key to hold for the right click above.",
	{ { "CTRL", "CTRL", raw = true }, { "ALT", "ALT", raw = true }, { "CTRL+ALT", "CTRL+ALT", raw = true } })
inventory:Check("autoSellJunk", "Auto Sell Junk", "Sells the junk as soon as you open a vendor window.")
inventory:Check("autoDiscardItems", "Discard junk items if bag is full",
	"When every bag is full, deletes the cheapest piece of junk to make room. Deleted items cannot be recovered.")
inventory:Slider("maxSoulShards", "Soul Shard Maximum", 0, 100, 1, "%d",
	"Warlocks: soul shards beyond this number count as junk (not in a soul bag).")
inventory:Buttons({
	{ "Reset Junk List", "Forgets everything you marked as junk or as useful.", function()
		FR:Confirm(FR.L["Forget everything you marked as junk or as useful?"], function() FR:ResetJunk() end)
	end },
})

-- Tips: the tip window and the two warnings (Tips.lua).
local tipsPage = NewPage("Tips")
tipsPage:Header("Tip window")
tipsPage:Check("showTips", "Display tips",
	"Advice that a guide marks as a tip (#tip) shows in a small window you can move. The bundled guides have none, imported guides can.")
tipsPage:Header("Low health")
tipsPage:Check("enableEmergency", "Outline the emergency buttons",
	"When your health is low, the action buttons with a healing potion, a bandage or an emergency ability get a red outline.")
tipsPage:Check("emergencyAnimation", "Pulse the outline", "Makes the red outline pulse.")
tipsPage:Slider("emergencyThreshold", "Low health below", 0.1, 0.5, 0.05, "%.2f",
	"The buttons are outlined while your health is below this part of the maximum.")
tipsPage:Header("Drowning")
tipsPage:Check("enableDrowningWarning", "Warn when drowning", "A message and a sound when your breath is running out.")
tipsPage:Check("drowningSound", "Play a sound", "Plays a warning sound when your breath is running out.")
tipsPage:Check("drowningFlash", "Flash the screen red", "Flashes the screen red while you are drowning.")
tipsPage:Slider("drowningThreshold", "Warn below", 0.1, 0.6, 0.05, "%.2f",
	"The warning starts when the breath bar is below this part of the maximum.")

-- Group & Report: the leveling report and (PartySteps.lua) the party steps.
local groupPage = NewPage("Group & Report")
groupPage:Header("Leveling report")
groupPage:Check("enableTracker", "Record the leveling data",
	"Writes down, for each level, the time it took and where its experience came from (quests or kills, solo or group, zones, deaths) for the leveling report.")
groupPage:Check("showLevelETA", "Show the pace and time to level",
	"The footer of the guide window shows the experience per hour and the time left to the next level, from the last half hour of play (needs the leveling data above).")
groupPage:Buttons({
	{ "Open leveling report", "Shows the report of your levels.", function() FR:OpenLevelReport() end },
})
groupPage:Header("Active party steps")
groupPage:Check("partySteps", "Share and show party steps",
	"Tells the ForeverRoute players in your party which steps you are on and shows theirs in a window next to the guide. Not in raids. RestedXP players cannot take part: it is a different protocol.")
groupPage:Check("partyStepsBackground", "Show the window background", "Draws a dark background behind the party steps window.")
groupPage:Slider("partyStepsScale", "Window scale", 0.7, 1.5, 0.05, "%.2f", "Size of the party steps window.")

-- Name plates: ForeverRoute draws a bar for every enemy and only the name for friendly NPCs (Plates.lua);
-- the creatures of the current step are marked.
local platesPage = NewPage("Name Plates")
platesPage:Header("Step creatures")
platesPage:Check("nameplateIcons", "Mark the creatures of the step",
	"Marks the enemies and NPCs of the current step on their plates and on the target frame.")
platesPage:Choice("plateMarker", "Marker",
	"The mark on a step enemy: the yellow quest ! (like a quest giver), the raid icon (skull, cross, square, as on the target buttons), or both. Friendly NPCs always get their raid icon.",
	{ { "quest", "Quest !" }, { "raid", "Raid icon" }, { "both", "Both" } })
platesPage:Check("plateProgress", "Show the count (2/8)",
	"Under the marker of a step enemy: how many of it you have killed so far and how many the quest asks for, e.g. 2/8.")
platesPage:Slider("nameplateScale", "Marker size", 0.5, 2.0, 0.1, "%.1f", "Size of the marker on the creatures of the step.")

platesPage:Header("Plates")
platesPage:Check("customPlates", "Use ForeverRoute's own name plates",
	"Off (default): the game draws its own name plates and ForeverRoute only adds the step icon beside the name (see \"Mark the creatures of the step\"). On: enemies get a bar with name, health, level and cast bar. Friendly NPCs show only their name, like the game's floating names, without a bar (or the Classic plate, see below). Players and pets keep the game's plate. Not in instances.")
platesPage:Buttons({
	{ "Turn on the game's name plates", "Switches the game's name plates on (V: enemies, Shift+V: friendly NPCs). ForeverRoute can only draw plates the game creates.", function() FR:EnableNameplates() end },
})
platesPage:Note("Plater and other name plate addons draw their own plates as well: switch their enemy plates off, or both show on top of each other.")
platesPage:Note("The settings below only apply while ForeverRoute's own name plates are on. The step icons above work either way.")
platesPage:Slider("plateScale", "Plate size", 0.5, 2.0, 0.05, "%.2f", "Size of ForeverRoute's own plates.")
platesPage:Check("plateBorder", "Plate border",
	"Draws the beveled frame around the Classic NPC plate and the thin edge around enemy bars. Off: the bar without a frame. A step enemy has a teal bar.")

platesPage:Header("Friendly NPC names")
platesPage:Choice("plateNpc", "Friendly NPC plates",
	"Game text (recommended): the game draws the name itself, like the names of friendly players, without a bar; ForeverRoute only adds the icon. Own text: ForeverRoute draws the name in the game's font. Classic plate: the name above a flat bar with a level badge and a cast bar.",
	{ { "game", "Game text" }, { "own", "Own text" }, { "classic", "Classic plate" } })
platesPage:Slider("plateNameScale", "Name size", 0.5, 3.0, 0.1, "%.1f", "Size of the names of friendly NPCs.")
platesPage:Slider("plateNameY", "Name height", -80, 40, 1, "%d", "Height of the name above the middle of the plate.")
platesPage:Slider("plateNameWeight", "Name weight", 0, 1, 0.05, "%.2f", "How heavy the strokes of the names are.", {
	get = function()
		local w = FR:Get("plateNameWeight")
		if type(w) == "string" then w = ({ light = 0, medium = 0.5, bold = 1 })[w] end   -- older versions
		return type(w) == "number" and w or 0.5
	end,
})
platesPage:Slider("plateNameDistance", "Distance scaling", 0, 2.0, 0.1, "%.1f",
	"How strongly the names of friendly NPCs shrink when the camera or the creature is farther away, like the names of the game. 0 = always the same size.")
platesPage:Check("plateHideGameNames", "Hide the game's own NPC names",
	"Friendly NPCs have a name plate only within the plate range (45 yards); farther away the game draws its own name, which looks different, so you see the name change when you walk closer. This switches the game's own NPC names off while ForeverRoute draws the names (Own text, Classic plate): no change of look, but NPC names are only shown within the plate range. Your own setting is restored when you switch this off.")

function FR:RefreshSettings()
	for _, c in ipairs(controls) do pcall(c.Refresh, c) end
	local p = pages[selected or 0]
	if p then FR.Safe("settings layout", p.Layout, p) end
end

-- The page is laid out with the size the scroll frame has right now and again a frame later, when
-- the game's options window has given the panel its real size.
local function ShowSettings()
	FR.Safe("settings style", Restyle)
	FR:RefreshSettings()
	FR.Safe("settings page", panel.Select, panel, panel.tab or 1)
	C_Timer.After(0, function()
		if not panel:IsShown() then return end
		local p = pages[selected or 0]
		local width = scroll:GetWidth()
		if p and width and width > 50 then
			p.width = width
			FR.Safe("settings layout", p.Layout, p)
		end
		UpdateBar()
	end)
	C_Timer.After(1, function()
		local p = pages[selected or 0]
		if panel:IsShown() and p and (p.laid or 0) == 0 then
			FR:Print("The settings page is empty. Please type /fr settings debug and send the lines it prints.")
		end
	end)
end
panel:SetScript("OnShow", ShowSettings)
panel:SetScript("OnSizeChanged", function()
	local p = pages[selected or 0]
	local width = scroll:GetWidth()
	if p and panel:IsShown() and width and width > 50 and math.abs((p.width or 0) - width) > 0.5 then
		p.width = width
		FR.Safe("settings layout", p.Layout, p)
	end
end)

-- /fr settings debug: sizes and what was laid out, for a bug report when a page looks empty.
function FR:SettingsDebug()
	local function size(f) return string.format("%.0fx%.0f%s", f:GetWidth() or 0, f:GetHeight() or 0, f:IsShown() and "" or " hidden") end
	self:Print(string.format("settings: panel %s, sidebar %s, content %s, scroll %s, registered as %s",
		size(panel), size(sidebar), size(content), size(scroll),
		standalone and "own window" or (category and "game options" or "nothing")))
	for _, p in ipairs(pages) do
		self:Print(string.format("  page %d %s: frame %s, %d rows, %d laid out%s", p.index, tostring(p.label), size(p.frame),
			#p.items, p.laid or 0, selected == p.index and "  <- shown" or ""))
	end
	self:Print(string.format("  rows that failed to build: %d, controls: %d", FR.settingsErrors or 0, #controls))
end

-- Registration --------------------------------------------------------------------

local function MakeStandalone()
	standalone = true
	panel:SetParent(UIParent)
	panel:ClearAllPoints()
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	if not panel.SetBackdrop and BackdropTemplateMixin and Mixin then Mixin(panel, BackdropTemplateMixin) end
	Styled(function(th)
		if panel.SetBackdrop then
			panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
			panel:SetBackdropColor(th.bg[1], th.bg[2], th.bg[3], 0.97)
			panel:SetBackdropBorderColor(0, 0, 0, 1)
		end
	end)
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	tinsert(UISpecialFrames, "ForeverRouteSettings")
end

function FR:RegisterOptions()
	local ok = pcall(function()
		if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
			category = Settings.RegisterCanvasLayoutCategory(panel, "ForeverRoute")
			Settings.RegisterAddOnCategory(category)
		elseif InterfaceOptions_AddCategory then
			InterfaceOptions_AddCategory(panel)
			category = panel
		end
	end)
	if not ok or not category then MakeStandalone() end
end

local function ToggleSettingsRaw(self)
	-- RegisterOptions did not run (or failed): the settings get their own window, not an unplaced panel.
	if not standalone and not category then MakeStandalone() end
	if standalone or not category then
		if panel:IsShown() then panel:Hide() else panel:Show() end
		return
	end
	if Settings and Settings.OpenToCategory and type(category) == "table" and category ~= panel then
		if SettingsPanel and SettingsPanel:IsShown() then
			if not pcall(HideUIPanel, SettingsPanel) then SettingsPanel:Hide() end
			return
		end
		local id = category.GetID and category:GetID() or category.ID
		local ok, err = pcall(Settings.OpenToCategory, id)
		if ok then return end
		-- The game's options window refused (a blocked action). The old
		-- InterfaceOptions call below is what raises "Interface action failed
		-- because of an addon", so show ForeverRoute's own window instead.
		self:Print(FR.L["The game's options window could not be opened. Showing the ForeverRoute settings in their own window."]
			.. " (" .. tostring(err) .. ")")
		if not standalone then MakeStandalone() end
		panel:Show()
		return
	end
	if InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
		return
	end
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

-- An error opening the settings shows in the chat instead of nothing happening.
function FR:ToggleSettings()
	return FR.Safe("settings", ToggleSettingsRaw, self)
end
