ForeverRoute.loadingLocale = "zhCN"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-10_NightElf"
local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 1-6级 幽影谷
#version 1
#group RestedXP 无限 地下城指南 (联盟)
#subgroup 地下城指南 1-20级
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 6-11级 泰达希尔
step
#include RestedXP无限服指南（联盟）\1-6级 幽影谷
]])

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 6-11级 泰达希尔
#version 1
#group RestedXP 无限 地下城指南 (联盟)
#subgroup 地下城指南 1-20级
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 11-16级 黑海岸/洛克莫丹

step
#include RestedXP无限服指南（联盟）\6-11级 泰达希尔
]])
