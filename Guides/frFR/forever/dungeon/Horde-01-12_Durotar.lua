ForeverRoute.loadingLocale = "frFR"
ForeverRoute.guideFile = "forever/dungeon/Horde-01-12_Durotar"
local faction = UnitFactionGroup("player")
if faction == "Alliance" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 1-6 Durotar
#version 11
#group Guide de donjon Forever RestedXP (H)
#subgroup Guide de donjon 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Troll/Orc
#next 6-10 Durotar


step
.enabledungeon RFC
#include RestedXP Guide Forever (H)\1-6 Durotar
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 6-10 Durotar
#version 11
#group Guide de donjon Forever RestedXP (H)
#subgroup Guide de donjon 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Troll/Orc
#next 10-12 Durotar

step
.enabledungeon RFC
#include RestedXP Guide Forever (H)\6-10 Durotar
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 10-12 Durotar
#version 11
#group Guide de donjon Forever RestedXP (H)
#subgroup Guide de donjon 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Troll/Orc
#next 10-12 Tirisfal (Orc/Troll) << !Hunter !Shaman !Tauren !Skyborne
#next 12-16 Les Tarides << Orc Hunter/Troll Hunter/Orc Shaman/Troll Shaman


step
.enabledungeon ROL
.enabledungeon RFC
#include RestedXP Guide Forever (H)\10-12 Durotar
]])


ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 10-12 Tirisfal (Orc/Troll)
#version 11
#group Guide de donjon Forever RestedXP (H)
#subgroup Guide de donjon 1-22
--#groupid RXP-SRGCE-H1
#defaultfor !Hunter !Shaman !Tauren !Skyborne !Undead
#next 12-14 Forêt des Pins argentés << !Hunter !Shaman !Tauren !Skyborne !Undead

step
.enabledungeon RFC
#include RestedXP Guide Forever (H)\10-12 Tirisfal (Orc/Troll)
]])
