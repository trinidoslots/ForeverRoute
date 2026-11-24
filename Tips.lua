-- Tips, two things as in RestedXP:
--
-- 1. The tip window. A step marked "#tip" is not a step of the route: it is advice
--    and shows in a small movable window while you are at or after it (until a
--    later tip replaces it). None of the bundled guides has tips; imported guides
--    can. (Parser.lua puts them in guide.tips, with tipAfter = main steps before it.)
--
-- 2. Warnings: you are drowning (breath running out) and low health: the action
--    button of a healing potion, bandage or an emergency spell is outlined, so
--    the right button is easy to find in a hurry.
--
-- Values the game may hand out as "secret values" (health) are checked before
-- they are compared; a unit with such values simply gives no warning.
local _, ns = ...
local FR = ns.FR

local C = FR.colors

-- Decisions (no game state, so they can be tested) -------------------------------------

-- Health as a fraction, or nil when the values are not readable.
function FR.HealthFraction(health, max)
	if issecretvalue and (issecretvalue(health) or issecretvalue(max)) then return nil end
	if type(health) ~= "number" or type(max) ~= "number" or max <= 0 then return nil end
	return health / max
end

-- Low health: alive, some health left, below the threshold.
function FR.IsLowHealth(fraction, threshold, dead)
	return not dead and fraction ~= nil and fraction > 0 and fraction < threshold
end

-- Breath: used up, or below the threshold of the whole bar.
function FR.IsDrowning(value, max, threshold)
	if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then return false end
	return value <= 0 or (value / max) < threshold
end

-- The tip that applies at step `stepIndex` of guide g: the last one before it.
function FR.TipFor(g, stepIndex)
	local tip
	for _, t in ipairs(g and g.tips or {}) do
		if (t.tipAfter or 0) < stepIndex then tip = t else break end
	end
	return tip
end

function FR:CurrentTip()
	return FR.TipFor(self.current, self.stepIndex or 1)
end

-- Which emergency spells does this player have? Spell ids by race, class and profession.
function FR.EmergencySpellIds(race, class, known)
	local ids = {}
	local data = FR.EMERGENCY_SPELLS or {}
	local function Add(list)
		for id in pairs(list or {}) do
			if known(id) then ids[#ids + 1] = id end
		end
	end
	Add(data.professions)
	Add(data[race])
	-- The table uses names with spaces ('Night Elf'), the game's token has none.
	if race then Add(data[(tostring(race):gsub("(%l)(%u)", "%1 %2"))]) end
	Add(data[class])
	return ids
end

-- The tip window ---------------------------------------------------------------------------

local tipWindow

local function BuildTipWindow()
	local f = CreateFrame("Frame", "ForeverRouteTipWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(230, 60)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	FR.Skin(f, "bg")
	local pos = ForeverRouteDB and ForeverRouteDB.posTip
	if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 220) end

	f.title = FR.MakeText(f, FR.fontUISmall)
	f.title:SetPoint("TOPLEFT", 10, -8)
	f.title:SetTextColor(1, 0.82, 0.2)

	f.body = FR.MakeText(f, FR.fontUIBody)
	f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.body:SetWidth(210)
	f.body:SetWordWrap(true)
	f.body:SetTextColor(C.text[1], C.text[2], C.text[3])

	f:SetScript("OnDragStart", function(self) if not FR:Get("locked") then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		if point and ForeverRouteDB then ForeverRouteDB.posTip = { point, rel, math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	f:SetScript("OnMouseUp", function(_, button)
		if button ~= "RightButton" or not ns.FlatMenu then return end
		ns.FlatMenu.OpenAtCursor(f, function(_, root)
			root:CreateButton(FR.L["Hide tips"], function() FR:Set("showTips", false) end)
		end, { avoid = f })   -- no room on the right: open at the left side of the window
	end)
	f:Hide()
	return f
end

-- Shows the tip that belongs to the step you are on (or hides the window).
function FR:UpdateTipWindow()
	local tip = self:Get("showTips") and not self:Get("hidden") and self:CurrentTip() or nil
	if not tip then
		if tipWindow then tipWindow:Hide() end
		return
	end
	tipWindow = tipWindow or BuildTipWindow()
	local lines = {}
	for _, e in ipairs(tip.elements) do
		if not e.hidden then
			local text = self:ElementText(e)
			if text and text ~= "" then lines[#lines + 1] = text end
		end
	end
	if #lines == 0 then tipWindow:Hide() return end
	tipWindow.title:SetText(FR.L["Tip"])
	tipWindow.body:SetText(table.concat(lines, "\n"))
	tipWindow:SetHeight(math.max(40, (tipWindow.body:GetStringHeight() or 20) + 34))
	tipWindow:Show()
end

-- The window follows every update of the guide window.
local rawUpdateUI = FR.UpdateUI
function FR:UpdateUI(...)
	rawUpdateUI(self, ...)
	self:UpdateTipWindow()
end

-- Warnings -------------------------------------------------------------------------------------

local state = {
	breath = nil,          -- { value, max } while the breath bar drains
	lastAlert = 0,
	items = {},            -- emergency item ids in the bags
	spells = {},           -- emergency spell ids the player has
	barMap = {},           -- ["item:123"] / ["spell:123"] = action button name
	highlights = {},       -- button name -> outline texture
}

local ALERT_EVERY = 1      -- seconds between drowning alerts
local CHECK_EVERY = 0.5

-- Full-screen red pulse (the game's own low health texture, as RestedXP does).
local flashFrame
local function ShowFlash(loops)
	if not flashFrame then
		local f = CreateFrame("Frame", "ForeverRouteDangerFrame", UIParent)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:SetAllPoints(UIParent)
		f:EnableMouse(false)
		f.bg = f:CreateTexture(nil, "BACKGROUND")
		f.bg:SetTexture("Interface\\FullScreenTextures\\LowHealth")
		f.bg:SetBlendMode("ADD")
		f.bg:SetAllPoints(f)
		f.animation = f:CreateAnimationGroup()
		f.animation:SetLooping("BOUNCE")
		local pulse = f.animation:CreateAnimation("Alpha")
		pulse:SetDuration(0.5236)
		pulse:SetFromAlpha(0.75)
		pulse:SetToAlpha(0.2)
		f.animation:HookScript("OnLoop", function()
			f.loops = (f.loops or 0) - 1
			if f.loops < 0 then f.animation:Stop(); f:Hide() end
		end)
		f:Hide()
		flashFrame = f
	end
	flashFrame.loops = loops
	flashFrame:Show()
	if not flashFrame.animation:IsPlaying() then flashFrame.animation:Play() end
end

local function CheckDrowning(now)
	local b = state.breath
	if not b or not FR:Get("enableDrowningWarning") then return end
	local value = b.value
	if GetMirrorTimerProgress then
		local ok, progress = pcall(GetMirrorTimerProgress, "BREATH")
		if ok and not (issecretvalue and issecretvalue(progress)) and type(progress) == "number" then value = progress end
	end
	if not FR.IsDrowning(value, b.max, FR:Get("drowningThreshold") or 0.2) then return end
	if now - state.lastAlert < ALERT_EVERY then return end
	state.lastAlert = now
	if FR:Get("drowningFlash") then ShowFlash(2) end
	if FlashClientIcon then pcall(FlashClientIcon) end
	if UIErrorsFrame and UIErrorsFrame.AddMessage then
		UIErrorsFrame:AddMessage(STRING_ENVIRONMENTAL_DAMAGE_DROWNING or FR.L["You are drowning!"], 1, 0.1, 0.1, ALERT_EVERY)
	end
	if FR:Get("drowningSound") and PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end

-- Bags -> emergency items ----------------------------------------------------------------------

local function ScanBags()
	state.items = {}
	local data = FR.EMERGENCY_ITEMS
	if not data then return end
	local slots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
	local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
	if not (slots and itemID) then return end
	for bag = 0, 4 do
		local ok, n = pcall(slots, bag)
		if ok and type(n) == "number" then
			for slot = 1, n do
				local okId, id = pcall(itemID, bag, slot)
				if okId and type(id) == "number" and data[id] then state.items[id] = true end
			end
		end
	end
end

local function ScanSpells()
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	state.spells = FR.EmergencySpellIds(race, class, function(id) return FR.SpellKnown(id) == true end)
end

-- Action bars -> which button holds what ------------------------------------------------------

local BARS = { "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }

local function ScanActionBars()
	state.barMap = {}
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			local name = bar .. "Button" .. i
			local button = _G[name]
			if button then
				local ok, slot = pcall(function()
					if type(button.action) == "number" then return button.action end
					if ActionButton_GetPagedID then return ActionButton_GetPagedID(button) end
					return button:GetAttribute("action")
				end)
				if ok and type(slot) == "number" and HasAction and HasAction(slot) then
					local okInfo, kind, id = pcall(GetActionInfo, slot)
					if okInfo and not (issecretvalue and (issecretvalue(kind) or issecretvalue(id))) then
						local key
						if kind == "macro" and GetMacroSpell then
							local _, _, spellId = GetMacroSpell(id)
							if spellId then key = "spell:" .. spellId end
						elseif kind == "item" and id then
							key = "item:" .. id
						elseif kind == "spell" and id then
							key = "spell:" .. id
						end
						if key then state.barMap[key] = name end
					end
				end
			end
		end
	end
end

local function Highlight(name)
	local parent = _G[name]
	if not parent then return nil end
	local border = state.highlights[name]
	if not border then
		border = parent:CreateTexture(nil, "OVERLAY")
		border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		border:SetBlendMode("ADD")
		border:SetVertexColor(1, 0.25, 0.2, 0.9)
		local size = (parent:GetWidth() or 36) * 1.9
		border:SetSize(size, size)
		border:SetPoint("CENTER", parent, "CENTER", 0, 0)
		border.animation = border:CreateAnimationGroup()
		border.animation:SetLooping("BOUNCE")
		local fade = border.animation:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.3)
		fade:SetDuration(0.4)
		border:Hide()
		state.highlights[name] = border
	end
	return border
end

local function HideHighlights()
	for _, border in pairs(state.highlights) do
		if border:IsShown() then
			border.animation:Stop()
			border:Hide()
		end
	end
end

local function CheckEmergency()
	if not FR:Get("enableEmergency") then HideHighlights() return end
	local okHealth, health, max = pcall(function() return UnitHealth("player"), UnitHealthMax("player") end)
	local fraction = okHealth and FR.HealthFraction(health, max) or nil
	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
	if not FR.IsLowHealth(fraction, FR:Get("emergencyThreshold") or 0.2, dead) then
		HideHighlights()
		return
	end
	local animate = FR:Get("emergencyAnimation")
	local function Show(key)
		local name = state.barMap[key]
		local border = name and Highlight(name)
		if border then
			border:Show()
			if animate and not border.animation:IsPlaying() then border.animation:Play() end
		end
	end
	for id in pairs(state.items) do Show("item:" .. id) end
	for _, id in ipairs(state.spells) do Show("spell:" .. id) end
end

-- Events --------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "BAG_UPDATE_DELAYED", "ACTIONBAR_SLOT_CHANGED",
	"SPELLS_CHANGED", "PLAYER_LOGIN" }) do
	pcall(ev.RegisterEvent, ev, e)
end

local rescanBags, rescanBars = false, false
ev:SetScript("OnEvent", function(_, event, ...)
	if event == "MIRROR_TIMER_START" then
		local timer, value, max, scale = ...
		if timer ~= "BREATH" then return end
		if issecretvalue and (issecretvalue(value) or issecretvalue(max) or issecretvalue(scale)) then return end
		-- A scale above 0 means the breath is coming back.
		if type(scale) == "number" and scale > 0 then state.breath = nil return end
		state.breath = { value = value, max = max }
	elseif event == "MIRROR_TIMER_STOP" then
		if (...) == "BREATH" then state.breath = nil end
	elseif event == "BAG_UPDATE_DELAYED" then
		rescanBags = true
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		rescanBars = true
	elseif event == "SPELLS_CHANGED" or event == "PLAYER_LOGIN" then
		rescanBags, rescanBars = true, true
		ScanSpells()
	end
end)

local elapsed = 0
ev:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < CHECK_EVERY then return end
	elapsed = 0
	if rescanBags then rescanBags = false; ScanBags() end
	if rescanBars then rescanBars = false; ScanActionBars() end
	CheckDrowning(GetTime())
	CheckEmergency()
end)

-- A setting changed (on / off): outlines go away at once.
function FR:RefreshTips()
	if not self:Get("enableEmergency") then HideHighlights() end
	self:UpdateTipWindow()
end

-- Exposed for tests.
FR.TipsState = state
