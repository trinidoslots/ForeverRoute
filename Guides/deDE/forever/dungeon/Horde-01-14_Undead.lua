ForeverRoute.loadingLocale = "deDE"
ForeverRoute.guideFile = "forever/dungeon/Horde-01-14_Undead"
local faction = UnitFactionGroup("player")
if faction == "Alliance" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Undead
#name 1-6 Tirisfal
#next 6-12 Tirisfal

step
.enabledungeon RFC
#include RestedXP Forever Route (H)\1-6 Tirisfal
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 6-12 Tirisfal
#displayname 6-13 Tirisfal << Paladin
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Undead
#next 12-14 Silberwald; 12-17 Das Brachland

step
.enabledungeon ROL
.enabledungeon RFC
#include RestedXP Forever Route (H)\6-12 Tirisfal
]])


ForeverRoute.RegisterGuide([[
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
<< Horde
#version 11
#defaultfor !Hunter !Shaman !Tauren
#forever
#era/som--h
#name 12-14 Silberwald
#displayname 13-15 Silberwald << Paladin
#next 14-18 Das Brachland


step
.enabledungeon RFC
.enabledungeon ROL
#include RestedXP Forever Route (H)\12-14 Silberwald
]])
