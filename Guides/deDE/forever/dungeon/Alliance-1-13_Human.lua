ForeverRoute.loadingLocale = "deDE"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-13_Human"
local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Alliance
#name 1-6 Nordhain
#version 1
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#defaultfor Human
#next 6-11 Wald von Elwynn


step
#include RestedXP Forever Route (A)\1-6 Nordhain
]])


ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 6-11 Wald von Elwynn
#next 11-13 Loch Modan
#defaultfor Human

step
#include RestedXP Forever Route (A)\6-11 Wald von Elwynn
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 11-13 Loch Modan
#next 13-15 Westfall
#defaultfor Human

step
    #include RestedXP Forever Route (A)\11-13 Loch Modan@NormalRouteStart-NormalRouteEnd
]])