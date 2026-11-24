local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.loadingLocale = "enUS"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-14_DwarfGnome"
ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 1-5 Coldridge Valley
#next 5-11 Dun Morogh
#defaultfor Dwarf/Gnome

step
#include RestedXP Forever Guide (A)\1-5 Coldridge Valley
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 5-11 Dun Morogh
#next 11-12 Elwynn (Dwarf/Gnome);11-12 Voidwalker Quest;12-14 Loch Modan (Dwarf/Gnome);11-13 Loch Modan (Hunter)
#defaultfor Dwarf/Gnome

step
#include RestedXP Forever Guide (A)\5-11 Dun Morogh
]])

ForeverRoute.RegisterGuide([[
#forever
<< Alliance !Hunter
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 11-12 Elwynn (Dwarf/Gnome)
#version 1
#defaultfor Gnome/Dwarf
#next 12-14 Loch Modan (Dwarf/Gnome)

step
#include RestedXP Forever Guide (A)\11-12 Elwynn (Dwarf/Gnome)
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance !Hunter
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 12-14 Loch Modan (Dwarf/Gnome)
#next 13-15 Westfall
#defaultfor Gnome/Dwarf

step
#include RestedXP Forever Guide (A)\12-14 Loch Modan (Dwarf/Gnome)
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance Hunter
#group RestedXP Forever Dungeon Guide (A)
#subgroup Dungeon Guide 1-20
--#groupid RXP-SRGCE-A1
#name 11-13 Loch Modan (Hunter)
#next 13-15 Westfall
#defaultfor Dwarf

step
#include RestedXP Forever Guide (A)\11-13 Loch Modan (Hunter)@NormalRouteStart-NormalRouteEnd
]])