ForeverRoute.loadingLocale = "frFR"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-10_NightElf"
local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 1-6 Sombrevallon
#version 1
#group Guide de donjon Forever RestedXP (A)
#subgroup Guide de donjon 1-20
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 6-11 Teldrassil
step
#include RestedXP Guide Forever (A)\1-6 Sombrevallon
]])

ForeverRoute.RegisterGuide([[
#forever
#season 0,1
<< Alliance
#name 6-11 Teldrassil
#version 1
#group Guide de donjon Forever RestedXP (A)
#subgroup Guide de donjon 1-20
--#groupid RXP-SRGCE-A1
#defaultfor NightElf
#next 11-16 Sombrivage/Loch Modan

step
#include RestedXP Guide Forever (A)\6-11 Teldrassil
]])
