ForeverRoute.loadingLocale = "zhCN"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-13_Human"
local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Alliance
#name 1-6级 北郡
#version 1
#group RestedXP 无限 地下城指南 (联盟)
#subgroup 地下城指南 1-20级
--#groupid RXP-SRGCE-A1
#defaultfor Human
#next 6-11级 艾尔文森林


step
#include RestedXP无限服指南（联盟）\1-6级 北郡
]])


ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP 无限 地下城指南 (联盟)
#subgroup 地下城指南 1-20级
--#groupid RXP-SRGCE-A1
#name 6-11级 艾尔文森林
#next 11-13级 洛克莫丹
#defaultfor Human

step
#include RestedXP无限服指南（联盟）\6-11级 艾尔文森林
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP 无限 地下城指南 (联盟)
#subgroup 地下城指南 1-20级
--#groupid RXP-SRGCE-A1
#name 11-13级 洛克莫丹
#next 13-15级 西部荒野
#defaultfor Human

step
    #include RestedXP无限服指南（联盟）\11-13级 洛克莫丹@NormalRouteStart-NormalRouteEnd
]])