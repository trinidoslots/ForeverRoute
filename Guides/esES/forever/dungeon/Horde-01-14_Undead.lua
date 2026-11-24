ForeverRoute.loadingLocale = "esES"
ForeverRoute.guideFile = "forever/dungeon/Horde-01-14_Undead"
local faction = UnitFactionGroup("player")
if faction == "Alliance" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#version 11
#group RestedXP Forever Guía de Mazmorras (H)
#subgroup Guía de mazmorras 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Undead
#name 1-6 Claros de Tirisfal
#next 6-12 Claros de Tirisfal

step
.enabledungeon RFC
#include RestedXP Guía Forever (H)\1-6 Claros de Tirisfal
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 6-12 Claros de Tirisfal
#displayname 6-13 Claros de Tirisfal << Paladin
#version 11
#group RestedXP Forever Guía de Mazmorras (H)
#subgroup Guía de mazmorras 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Undead
#next 12-14 Bosque de Argénteos; 12-17 Los Baldíos

step
.enabledungeon ROL
.enabledungeon RFC
#include RestedXP Guía Forever (H)\6-12 Claros de Tirisfal
]])


ForeverRoute.RegisterGuide([[
#group RestedXP Forever Guía de Mazmorras (H)
#subgroup Guía de mazmorras 1-22
--#groupid RXP-SRGCE-H1
<< Horde
#version 11
#defaultfor !Hunter !Shaman !Tauren
#forever
#era/som--h
#name 12-14 Bosque de Argénteos
#displayname 13-15 Bosque de Argénteos << Paladin
#next 12-16 Los Baldíos


step
.enabledungeon RFC
.enabledungeon ROL
#include RestedXP Guía Forever (H)\12-14 Bosque de Argénteos
]])
