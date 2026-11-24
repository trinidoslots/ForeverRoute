-- A window with a title, a line of help and a large text box you can copy from or
-- paste into: the problem report and the guide import use it.
--
--   FR.TextWindow{
--     name = "Report",            -- one window per name (reused)
--     title = "Report a problem",
--     hint = "Copy this text ...",
--     text = "...",
--     selectAll = true,           -- select the whole text when it opens
--     acceptLabel = "Import",     -- optional second button ...
--     onAccept = function(text) return true end,   -- ... true closes the window
--   }
local _, ns = ...
local FR = ns.FR

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE = "Interface\\Buttons\\WHITE8X8"
local Text = FR.MakeText
local C = FR.colors

local windows = {}

local function Build(name)
	local frameName = "ForeverRoute" .. name .. "Window"
	local f = CreateFrame("Frame", frameName, UIParent, BACKDROP)
	f:SetSize(580, 460)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	FR.Skin(f, "bg")
	f:Hide()

	f.title = Text(f, FR.fontUITitle)
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetTextColor(1, 0.82, 0.2)

	f.hint = Text(f, FR.fontUISmall)
	f.hint:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.hint:SetWidth(550)
	f.hint:SetWordWrap(true)
	f.hint:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

	-- The text box: a scroll frame with a multi-line edit box in it.
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", frameName .. "Scroll", f, "UIPanelScrollFrameTemplate")
	if not ok then
		scroll = CreateFrame("ScrollFrame", nil, f)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local max = math.max(0, (self:GetVerticalScrollRange() or 0))
			self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	scroll:SetPoint("TOPLEFT", 16, -92)
	scroll:SetPoint("BOTTOMRIGHT", -36, 52)
	f.scroll = scroll

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(WHITE)
	bg:SetVertexColor(0, 0, 0, 0.35)
	bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
	bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, -4)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(FR.fontUIBody)
	edit:SetTextColor(C.text[1], C.text[2], C.text[3])
	edit:SetMaxLetters(0)
	if edit.SetMaxBytes then edit:SetMaxBytes(0) end
	edit:SetWidth(500)
	scroll:SetScrollChild(edit)
	scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 0 then edit:SetWidth(w) end end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	edit:SetScript("OnTextChanged", function() scroll:UpdateScrollChildRect() end)
	-- Keeps the line you are typing in view.
	edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
		y = -(y or 0)
		local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
		if y < offset then scroll:SetVerticalScroll(y)
		elseif y + (h or 0) > offset + height then scroll:SetVerticalScroll(y + (h or 0) - height) end
	end)
	-- A click anywhere in the box puts the cursor in it.
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	f.edit = edit

	local function Button(label, anchor, x, width, onClick)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(width, 24)
		b:SetPoint(anchor, x, 16)
		b:SetScript("OnClick", onClick)
		return b
	end
	f.selectButton = Button("Select all", "BOTTOMLEFT", 16, 120, function()
		edit:SetFocus()
		edit:HighlightText()
	end)
	f.acceptButton = Button("Accept", "BOTTOMRIGHT", -150, 120, function()
		local opts = f.opts
		if opts and opts.onAccept and opts.onAccept(edit:GetText()) then f:Hide() end
	end)
	f.closeButton = Button("Close", "BOTTOMRIGHT", -16, 120, function() f:Hide() end)
	-- An extra button in the middle (opts.extra = { label, onClick(button) }), e.g. a level picker.
	f.extraButton = Button("", "BOTTOM", 0, 190, function()
		local opts = f.opts
		if opts and opts.extra and opts.extra.onClick then opts.extra.onClick(f.extraButton) end
	end)

	tinsert(UISpecialFrames, frameName)
	return f
end

function FR.TextWindow(opts)
	local name = opts.name or "Text"
	local f = windows[name]
	if not f then
		f = Build(name)
		windows[name] = f
	end
	f.opts = opts
	f.title:SetText(opts.title or "")
	f.hint:SetText(opts.hint or "")
	f.selectButton:SetText(FR.L["Select all"])
	f.closeButton:SetText(FR.L["Close"])
	if opts.onAccept then
		f.acceptButton:SetText(opts.acceptLabel or FR.L["Accept"])
		f.acceptButton:Show()
	else
		f.acceptButton:Hide()
	end
	if opts.extra then
		f.extraButton:SetText(opts.extra.label or "")
		f.extraButton:Show()
	else
		f.extraButton:Hide()
	end
	f.edit:SetText(opts.text or "")
	f.scroll:SetVerticalScroll(0)
	f:Show()
	f:Raise()
	if opts.selectAll then
		f.edit:SetFocus()
		f.edit:HighlightText()
	elseif opts.focus then
		f.edit:SetFocus()
	end
	return f
end
