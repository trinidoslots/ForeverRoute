ForeverRoute.loadingLocale = "ptBR"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-10_NightElf"
local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 1-6 Umbravale
#version 1
#group Guia de Masmorras do RestedXP Forever (A)
#subgroup Guia da Masmorra 1-20
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 6-11 Teldrassil
step
#include Guia RestedXP Forever (A)\1-6 Umbravale
]])

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 6-11 Teldrassil
#version 1
#group Guia de Masmorras do RestedXP Forever (A)
#subgroup Guia da Masmorra 1-20
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 11-16 Costa Negra/Loch Modan

step
#include Guia RestedXP Forever (A)\6-11 Teldrassil
]])
