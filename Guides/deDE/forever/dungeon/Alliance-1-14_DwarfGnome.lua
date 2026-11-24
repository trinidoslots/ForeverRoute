ForeverRoute.loadingLocale = "deDE"
ForeverRoute.guideFile = "forever/dungeon/Alliance-1-14_DwarfGnome"
local faction = UnitFactionGroup("player")
if faction == "Horde" then return end

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 1-5 Das Eisklammtal
#next 5-11 Dun Morogh
#defaultfor Dwarf/Gnome

step
#include RestedXP Forever Route (A)\1-5 Das Eisklammtal
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 5-11 Dun Morogh
#next 11-12 Elwynn (Zwerge/Gnome);11-12 Leerwandler-Quest;12-14 Loch Modan (Zwerg/Gnom);11-13 Loch Modan (Jäger)
#defaultfor Dwarf/Gnome

step
#include RestedXP Forever Route (A)\5-11 Dun Morogh
]])

ForeverRoute.RegisterGuide([[
#forever
<< Alliance !Hunter
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 11-12 Elwynn (Zwerge/Gnome)
#version 1
#defaultfor Gnome/Dwarf
#next 12-14 Loch Modan (Zwerg/Gnom)

step
#include RestedXP Forever Route (A)\11-12 Elwynn (Zwerge/Gnome)
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance !Hunter
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 12-14 Loch Modan (Zwerg/Gnom)
#next 13-15 Westfall
#defaultfor Gnome/Dwarf

step
#include RestedXP Forever Route (A)\12-14 Loch Modan (Zwerg/Gnom)
]])

ForeverRoute.RegisterGuide([[
#forever
#version 1
<< Alliance Hunter
#group RestedXP Forever Dungeonführer (A)
#subgroup Dungeonführer 1-20
--#groupid RXP-SRGCE-A1
#name 11-13 Loch Modan (Jäger)
#next 13-15 Westfall
#defaultfor Dwarf

step
#include RestedXP Forever Route (A)\11-13 Loch Modan (Jäger)@NormalRouteStart-NormalRouteEnd
]])