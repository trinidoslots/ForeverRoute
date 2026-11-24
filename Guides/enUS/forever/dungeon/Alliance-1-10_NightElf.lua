local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.loadingLocale = "enUS"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-10_NightElf"
ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 1-6 Shadowglen
#version 1
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 6-11 Teldrassil
step
#include RestedXP Forever Guide (A)\1-6 Shadowglen
]])

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 6-11 Teldrassil
#version 1
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 11-16 Darkshore/Loch Modan

step
#include RestedXP Forever Guide (A)\6-11 Teldrassil
]])
