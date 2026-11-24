// Copies RestedXP's data tables into ForeverRoute, unchanged.
//
//   node tools/Update-RxpData.js "C:/Users/Me/Downloads/RXPGuides/RXPGuides"
//
// Reads DB/forever/db.lua (and flightData.lua) of an unpacked RXPGuides release and writes
//   DungeonStats.lua   addon.dungeonStats                  -> FR.DUNGEON_STATS
//   EmergencyData.lua  addon.emergencyItems / ...Spells    -> FR.EMERGENCY_ITEMS / FR.EMERGENCY_SPELLS
//   NpcNames.lua       locale/NPCnames.lua                 -> FR.npcNames (English name -> the client's name)
const fs = require("fs");
const path = require("path");

const source = process.argv[2];
if (!source) {
	console.error("Usage: node tools/Update-RxpData.js <unpacked RXPGuides folder>");
	process.exit(1);
}

const db = path.join(source, "DB", "forever", "db.lua");
const lines = fs.readFileSync(db, "utf8").replace(/\r/g, "").split("\n");

const version = (() => {
	try {
		const toc = fs.readFileSync(path.join(source, "RXPGuides.toc"), "utf8");
		return (toc.match(/## Version: (\S+)/) || [])[1] || "unknown";
	} catch (e) { return "unknown"; }
})();

// The table that starts with "<name> = {" and ends at the next line that is just "}".
function table(name, newName) {
	const start = lines.findIndex(l => l.startsWith(name + " = {"));
	if (start < 0) {
		console.error(name + " not found in " + db);
		process.exit(1);
	}
	let end = start + 1;
	while (end < lines.length && lines[end] !== "}") end++;
	const block = lines.slice(start, end + 1);
	block[0] = newName + " = {";
	// Tabs for indentation, like the rest of ForeverRoute.
	return block.map(l => l.replace(/^( {4})+/, m => "\t".repeat(m.length / 4))).join("\n");
}

function header(what, from, by, file) {
	return [
		"-- " + what,
		"-- RestedXP's data for Forever (" + (file || "DB/forever/db.lua") + ", " + from + ", RestedXP Guides " + version + "),",
		"-- copied unchanged. RestedXP Guides is licensed under CC BY-NC-SA 4.0",
		"-- (https://creativecommons.org/licenses/by-nc-sa/4.0/), as is this file.",
		"-- Used by " + by + ". Regenerate with:",
		"--   node tools/Update-RxpData.js <unpacked RXPGuides folder>",
		"local _, ns = ...",
		"local FR = ns.FR",
		"",
	].join("\n");
}

const root = path.join(__dirname, "..");

fs.writeFileSync(path.join(root, "DungeonStats.lua"), [
	header("How much each dungeon is worth for a route, per faction: travel time saved,\n-- quest value and the value for each class (0-3).", "addon.dungeonStats", "FR.RecommendedDungeons (Core.lua)"),
	table("addon.dungeonStats", "FR.DUNGEON_STATS"),
	"",
].join("\n"));

fs.writeFileSync(path.join(root, "EmergencyData.lua"), [
	header("Items (potions, bandages ...) and spells (racial and class abilities) that help when\n-- health runs low. Item id -> name, spell id -> name per race or class.", "addon.emergencyItems / addon.emergencySpells", "Tips.lua (emergency action highlight)"),
	table("addon.emergencyItems", "FR.EMERGENCY_ITEMS"),
	"",
	table("addon.emergencySpells", "FR.EMERGENCY_SPELLS"),
	"",
].join("\n"));

// Flight masters: node id -> English name per faction, from DB/forever/flightData.lua (addon.FPDB). The
// distances between the nodes are left out. The "Fly to <place>" steps are matched against these names
// by node id, so the match does not depend on the language of the game client.
{
	const fp = fs.readFileSync(path.join(source, "DB", "forever", "flightData.lua"), "utf8").replace(/\r/g, "").split("\n");
	const nodes = { Horde: {}, Alliance: {} };
	let faction = null, node = null, count = 0;
	for (const l of fp) {
		let m;
		if ((m = l.match(/^    \["(Horde|Alliance)"\] = \{/))) { faction = m[1]; node = null; continue; }
		if (!faction) continue;
		if ((m = l.match(/^        \[(\d+)\] = \{/))) { node = m[1]; continue; }
		if (node && (m = l.match(/^\s+\["name"\]\s*=\s*"((?:[^"\\]|\\.)*)"/))) { nodes[faction][node] = m[1]; count++; }
	}
	if (count < 50) { console.error("flightData.lua: only " + count + " flight masters found"); process.exit(1); }
	const out = [header("The flight masters of Forever: node id -> English name, per faction (the guides' \"Fly to <place>\" steps\n-- are matched against these names).", "addon.FPDB (names only)", "Events.lua (auto fly)", "DB/forever/flightData.lua")];
	out.push("FR.FLIGHT_NODES = {");
	for (const f of ["Horde", "Alliance"]) {
		out.push("\t" + f + " = {");
		for (const id of Object.keys(nodes[f]).map(Number).sort((a, b) => a - b))
			out.push("\t\t[" + id + "] = \"" + nodes[f][id] + "\",");
		out.push("\t},");
	}
	out.push("}", "");
	fs.writeFileSync(path.join(root, "FlightData.lua"), out.join("\n"));
	console.log("Wrote FlightData.lua (" + count + " flight masters)");
}

// Creature names in the language of the game client (one table per locale in RestedXP's file; the
// macros that target a creature need the name the game shows).
const npc = fs.readFileSync(path.join(source, "locale", "NPCnames.lua"), "utf8").split(/\r?\n/);
const starts = [];
npc.forEach((l, i) => { const m = l.match(/^(?:else)?if locale == (.+) then$/); if (m && !/enUS/.test(l)) starts.push({ i, cond: m[1] }); });
const endLine = npc.lastIndexOf("end");
if (starts.length === 0 || endLine < 0) { console.error("NPCnames.lua: no locale blocks found"); process.exit(1); }
const out = [
	"-- Names of the creatures the guides mention, English name -> name in the game's language,",
	"-- one table for the language of the game client (the target macros need the exact name).",
	"-- From RestedXP Guides " + version + " (locale/NPCnames.lua), copied unchanged. RestedXP Guides is licensed",
	"-- under CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/), as is this file.",
	"-- Regenerate with: node tools/Update-RxpData.js <unpacked RXPGuides folder>",
	"local _, ns = ...",
	"local locale = GetLocale and GetLocale() or \"enUS\"",
];
starts.forEach((s, n) => {
	const to = n + 1 < starts.length ? starts[n + 1].i : endLine;
	out.push((n === 0 ? "if" : "elseif") + " locale == " + s.cond + " then");
	for (let k = s.i + 1; k < to; k++) out.push(npc[k].replace("addon.npcNames = {", "ns.FR.npcNames = {"));
});
out.push("end", "");
fs.writeFileSync(path.join(root, "NpcNames.lua"), out.join("\n"));

console.log("Wrote DungeonStats.lua, EmergencyData.lua and NpcNames.lua (RXP " + version + ")");
