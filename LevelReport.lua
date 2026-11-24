-- The leveling report window: pick a level, read what it took and where the
-- experience came from (data: Tracker.lua).
local _, ns = ...
local FR = ns.FR

local function MaxLevel()
	return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

-- The report text for one level, or nil when there is no data for it.
function FR:BuildLevelReport(level)
	local T = FR.Tracker
	local current = UnitLevel("player") or 1
	local r = T.Compile(level, current, T.CurrentSeconds(GetTime()))
	if not r then return nil end
	return T.Format(r, level >= MaxLevel())
end

function FR:OpenLevelReport(level)
	local L = FR.L
	local T = FR.Tracker
	local levels = T.LevelList()
	if #levels == 0 then
		self:Print(L["There is no leveling data yet. It is recorded from now on."])
		return
	end
	local current = UnitLevel("player") or 1
	if not level or not T.Levels()[level] then
		level = T.Levels()[current] and current or levels[#levels]
	end
	local label = level >= MaxLevel() and string.format(L["Level %d (maximum)"], level)
		or string.format(L["Level %d to %d"], level, level + 1)

	FR.TextWindow({
		name = "Levels",
		title = L["Leveling report"],
		hint = L["Pick another level with the button below. You can copy the text with Ctrl+C."],
		text = self:BuildLevelReport(level) or "",
		extra = {
			label = label,
			onClick = function(button)
				if not ns.FlatMenu then return end
				ns.FlatMenu.Open(button, function(_, root)
					if #levels > 22 and root.SetScrollMode then root:SetScrollMode(22 * 20) end
					for i = #levels, 1, -1 do
						local l = levels[i]
						local text = l >= MaxLevel() and string.format(L["Level %d (maximum)"], l)
							or string.format(L["Level %d to %d"], l, l + 1)
						if l == level then text = "|cff33ff33" .. text .. "|r" end
						root:CreateButton(text, function() FR:OpenLevelReport(l) end)
					end
				end)
			end,
		},
	})
end
