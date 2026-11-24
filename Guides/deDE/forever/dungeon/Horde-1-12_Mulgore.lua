ForeverRoute.loadingLocale = "deDE"
ForeverRoute.guideFile = "forever/dungeon/Horde-1-12_Mulgore"
local faction = UnitFactionGroup("player")
if faction == "Alliance" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 1-6 Mulgore
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Tauren
#next 6-12 Mulgore;6-13 Mulgore

step
.enabledungeon RFC
#include RestedXP Forever Route (H)\1-6 Mulgore
]])


ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 6-12 Mulgore
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Tauren
#next 14-18 Das Brachland


step
.enabledungeon RFC
#include RestedXP Forever Route (H)\6-12 Mulgore
]])
