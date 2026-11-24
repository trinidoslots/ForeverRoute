local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.loadingLocale = "enUS"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-13_Human"
ForeverRoute.RegisterGuide([[
#forever
<< Alliance
#name 1-6 Northshire
#version 1
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#defaultfor Human
#next 6-11 Elwynn Forest


step
#include RestedXP Forever Guide (A)\1-6 Northshire
]])


ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 6-11 Elwynn Forest
#next 11-13 Loch Modan
#defaultfor Human

step
#include RestedXP Forever Guide (A)\6-11 Elwynn Forest
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 11-13 Loch Modan
#next 13-15 Westfall
#defaultfor Human

step
    #include RestedXP Forever Guide (A)\11-13 Loch Modan@NormalRouteStart-NormalRouteEnd
]])