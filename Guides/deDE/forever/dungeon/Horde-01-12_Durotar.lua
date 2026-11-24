ForeverRoute.loadingLocale = "deDE"
ForeverRoute.guideFile = "forever/dungeon/Horde-01-12_Durotar"
local faction = UnitFactionGroup("player")
if faction == "Alliance" then return end

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 1-6 Durotar
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Troll/Orc
#next 6-10 Durotar


step
.enabledungeon RFC
#include RestedXP Forever Route (H)\1-6 Durotar
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 6-10 Durotar
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Troll/Orc
#next 10-12 Durotar

step
.enabledungeon RFC
#include RestedXP Forever Route (H)\6-10 Durotar
]])

ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 10-12 Durotar
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor Troll/Orc
#next 10-12 Tirisfal (Orc/Troll) << !Hunter !Shaman !Tauren !Skyborne
#next 14-18 Das Brachland << Orc Hunter/Troll Hunter/Orc Shaman/Troll Shaman


step
.enabledungeon ROL
.enabledungeon RFC
#include RestedXP Forever Route (H)\10-12 Durotar
]])


ForeverRoute.RegisterGuide([[
#forever
<< Horde
#name 10-12 Tirisfal (Orc/Troll)
#version 11
#group RestedXP Forever Dungeonführer (H)
#subgroup Dungeonführer 1-22
--#groupid RXP-SRGCE-H1
#defaultfor !Hunter !Shaman !Tauren !Skyborne !Undead
#next 12-14 Silberwald << !Hunter !Shaman !Tauren !Skyborne !Undead

step
.enabledungeon RFC
#include RestedXP Forever Route (H)\10-12 Tirisfal (Orc/Troll)
]])
