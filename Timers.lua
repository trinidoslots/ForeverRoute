-- Countdown bars for ".timer" (RestedXP): started when the line before the
-- timer is done (a talk option, a flight, an accepted quest with an NPC event).
-- Small flat bars under the waypoint bar; they remove themselves at zero.
local _, ns = ...
local FR = ns.FR

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local W, H, GAP, MAX = 220, 20, 4, 4
local bars = {}

local function Format(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function Place()
	local k = FR.UIPixels and FR.UIPixels() or 1
	local y = -math.floor(150 * k + 0.5)
	for _, bar in ipairs(bars) do
		if bar:IsShown() then
			bar:ClearAllPoints()
			bar:SetPoint("TOP", UIParent, "TOP", 0, y)
			y = y - H - GAP
		end
	end
end

local function Make(i)
	local f = CreateFrame("Frame", nil, UIParent, BACKDROP)
	f:SetSize(W, H)
	f:SetScale(FR.PixelScale and FR.PixelScale(1) or 1)
	f:SetFrameStrata("MEDIUM")
	f.pixelUnit = 1
	if FR.Skin then FR.Skin(f, "bg") end
	f.fill = f:CreateTexture(nil, "ARTWORK")
	f.fill:SetTexture(WHITE)
	f.fill:SetPoint("TOPLEFT", 1, -1)
	f.fill:SetPoint("BOTTOMLEFT", 1, 1)
	f.fill:SetWidth(1)
	if FR.Accent then FR.Accent(f.fill, 0.35) end
	f.label = FR.MakeText and FR.MakeText(f, FR.fontBar) or f:CreateFontString(nil, "OVERLAY")
	f.label:SetPoint("LEFT", 8, 0)
	f.label:SetPoint("RIGHT", -52, 0)
	f.label:SetJustifyH("LEFT")
	f.label:SetWordWrap(false)
	f.time = FR.MakeText and FR.MakeText(f, FR.fontBar) or f:CreateFontString(nil, "OVERLAY")
	f.time:SetPoint("RIGHT", -8, 0)
	f.time:SetJustifyH("RIGHT")
	f:Hide()
	f:SetScript("OnUpdate", function(self)
		local left = self.endTime - GetTime()
		if left <= 0 then self:Hide(); Place() return end
		local p = left / self.total
		self.fill:SetWidth(math.max(1, (W - 2) * p))
		self.time:SetText(Format(left))
	end)
	bars[i] = f
	return f
end

-- Starts (or restarts) a countdown with that label.
function FR:StartTimer(seconds, text)
	seconds = tonumber(seconds)
	if not seconds or seconds <= 0 then return end
	text = text or ""
	local bar
	for _, b in ipairs(bars) do
		if b:IsShown() and b.text == text then bar = b break end
	end
	if not bar then
		for _, b in ipairs(bars) do if not b:IsShown() then bar = b break end end
	end
	if not bar and #bars < MAX then bar = Make(#bars + 1) end
	if not bar then bar = bars[1] end
	bar.text, bar.total, bar.endTime = text, seconds, GetTime() + seconds
	bar.label:SetText(text)
	bar:Show()
	Place()
end

-- After the game's UI scale changed.
function FR:RescaleTimers()
	for _, b in ipairs(bars) do b:SetScale(FR.PixelScale(1)) end
	Place()
end
