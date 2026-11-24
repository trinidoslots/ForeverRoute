local faction = UnitFactionGroup("player")
if faction == "Alliance" then return end

ForeverRoute.loadingLocale = "enUS"
ForeverRoute.guideFile = "forever/dungeon/Horde-01-14_Undead"
ForeverRoute.RegisterGuide([[
#forever
<< Horde
#version 11
#group RestedXP Forever Dungeon Guide (H)
#subgroup Dungeon Guide 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Undead
#name 1-6 Tirisfal Glades
#next 6-12 Tirisfal Glades

step
.enabledungeon RFC
#include RestedXP Forever Guide (H)\1-6 Tirisfal Glades
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 6-12 Tirisfal Glades
#displayname 6-13 Tirisfal Glades << Paladin
#version 11
#group RestedXP Forever Dungeon Guide (H)
#subgroup Dungeon Guide 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Undead
#next 12-14 Silverpine Forest; 12-17 The Barrens

step
.enabledungeon ROL
.enabledungeon RFC
#include RestedXP Forever Guide (H)\6-12 Tirisfal Glades
]])


ForeverRoute.RegisterGuide([[
#group RestedXP Forever Dungeon Guide (H)
#subgroup Dungeon Guide 1-22
--#groupid RXP-SRGCE-H1
<< Horde
#version 11
#defaultfor !Hunter !Shaman !Tauren
#forever
#era/som--h
#name 12-14 Silverpine Forest
#displayname 13-15 Silverpine Forest << Paladin
#next 12-16 The Barrens


step
.enabledungeon RFC
.enabledungeon ROL
#include RestedXP Forever Guide (H)\12-14 Silverpine Forest
]])
