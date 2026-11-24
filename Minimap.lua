-- Minimap button. Sits on the minimap's edge (round or square minimaps)
-- and can be dragged around it.
local _, ns = ...
local FR = ns.FR

-- Which quadrants of each minimap shape are rounded
-- (1 = bottom-right, 2 = bottom-left, 3 = top-right, 4 = top-left).
local SHAPES = {
	["ROUND"] = { true, true, true, true },
	["SQUARE"] = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

-- Distance of the button centre outside the minimap's edge.
local EDGE_OFFSET = 10

local btn = CreateFrame("Button", "ForeverRouteMinimapButton", Minimap)
FR.minimapButton = btn
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetClampedToScreen(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetPoint("TOPLEFT", 7, -5)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(21, 21)
icon:SetPoint("TOPLEFT", 5, -5)
icon:SetTexture(FR.DIR .. "\\Textures\\Logo")
icon:SetTexCoord(0, 1, 0, 1)
btn.icon = icon

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 6, -6) end)
btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 5, -5) end)

local function Place()
	local angle = math.rad(FR:Get("minimapAngle") or 200)
	local x, y = math.cos(angle), math.sin(angle)
	local q = 1
	if x < 0 then q = q + 1 end
	if y > 0 then q = q + 2 end
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	local rounded = (SHAPES[shape] or SHAPES.ROUND)[q]
	local w = (Minimap:GetWidth() or 140) / 2 + EDGE_OFFSET
	local h = (Minimap:GetHeight() or 140) / 2 + EDGE_OFFSET
	if rounded then
		x, y = x * w, y * h
	else
		-- Square corner: push out to the corner, then clamp to the edge.
		local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
		x = math.max(-w, math.min(x * dw, w))
		y = math.max(-h, math.min(y * dh, h))
	end
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local s = Minimap:GetEffectiveScale()
	if not (mx and cx and s) then return end
	ForeverRouteDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx)) % 360
	Place()
end

btn:SetScript("OnDragStart", function(self)
	if FR:Get("locked") then return end
	self:LockHighlight()
	self:SetScript("OnUpdate", OnDragUpdate)
	GameTooltip:Hide()
end)
btn:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
	self:UnlockHighlight()
end)

btn:SetScript("OnClick", function(_, button)
	if button == "RightButton" then FR:ShowOptionsMenu(btn)
	elseif button == "MiddleButton" or IsShiftKeyDown() then FR:ToggleSettings()
	else FR:Toggle() end
end)

btn:SetScript("OnEnter", function(self)
	local L = FR.L
	local function Hint(key, what) return "|cff66bbff" .. L[key] .. "|r " .. L[what] end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("ForeverRoute")
	if FR.current then
		GameTooltip:AddLine(FR.current.short, 1, 0.82, 0.2)
		GameTooltip:AddLine(string.format(L["Step %d of %d"], FR.stepIndex or 1, #FR.current.steps), 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(Hint("Left-click:", "show / hide guide"), 1, 1, 1)
	GameTooltip:AddLine(Hint("Right-click:", "options"), 1, 1, 1)
	GameTooltip:AddLine(Hint("Shift-click:", "settings"), 1, 1, 1)
	GameTooltip:AddLine(Hint("Drag:", "move around the minimap"), 1, 1, 1)
	GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function FR:UpdateMinimapButton()
	if self:Get("showMinimap") then btn:Show(); Place() else btn:Hide() end
end

-- Minimap size can change after login (other addons, edit mode).
pcall(Minimap.HookScript, Minimap, "OnSizeChanged", function() if ForeverRouteDB then Place() end end)

-- Addon compartment (dropdown on the minimap in newer clients).
function ForeverRoute_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then FR:ShowPicker() else FR:Toggle() end
end
