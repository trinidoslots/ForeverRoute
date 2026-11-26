// Audits the bundled guides for mismatches (read-only).
//
//   node tools/Audit-Guides.js                    all enUS guides, report on stdout
//   node tools/Audit-Guides.js --rule A1,A2       only these rules
//   node tools/Audit-Guides.js --file Skyborne    only files whose name contains this
//   node tools/Audit-Guides.js --langs            also check the translations (rule A5)
//   node tools/Audit-Guides.js --quest 97332      show where the route accepts / completes / turns in that quest (with --rule A3)
//   node tools/Audit-Guides.js --strict           exit code 1 when a finding is not in tools/audit-allow.json
//   node tools/Audit-Guides.js --json out.json    write the findings as JSON as well
//
// Rules
//   A1  hearthstone steps: unguarded ".hs", conflicting bind areas, no travel fallback after a guarded ".hs"
//   A2  dangling references: #completewith / #requires labels, #include ranges, #next targets
//   A3  quests along the #next route: never turned in, turned in before accepted
//   A3h (only with --rule A3h) quests held for several guides without objective steps (informational)
//   A4  unknown ".commands" and "#directives" (typos in the upstream guides)
//   A5  translations: step / command parity with the English guide
//
// The tag rules ("<< Horde Shaman/Mage", "!Undead", "(A/B)") mirror FR.Applies in Conditions.lua; #include
// is expanded like Expand() in Parser.lua. A finding that was reviewed and is fine goes into
// tools/audit-allow.json as { "rule": "A3", "key": "...", "reason": "..." }.
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf("--" + name); return i < 0 ? null : (args[i + 1] && !args[i + 1].startsWith("--") ? args[i + 1] : true); };
const RULES = (opt("rule") || "A1,A2,A3,A4" + (opt("langs") ? ",A5" : "")).toString().split(",");
const FILE_FILTER = opt("file");

// ---- tags ------------------------------------------------------------------------------------------
const CLASSES = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];
const RACES = { Horde: ["Orc", "Tauren", "Troll", "Scourge"], Alliance: ["Human", "Dwarf", "NightElf", "Gnome"] };

function evalTag(text, c) {
	if (!text) return true;
	// "(Warrior/Mage)" and "!(...)" groups first
	let guard = 0;
	while (/\(/.test(text) && guard++ < 10) {
		text = text.replace(/(!?)\(\s*([^()]*?)\s*\)/g, (_, op, inner) => (evalTag(inner, c) !== (op === "!") ? "TRUE" : "FALSE"));
	}
	for (const alt of text.split("/")) {
		let ok = true;
		for (const m of alt.matchAll(/!?[\w]+/g)) {
			let e = m[0], neg = false;
			if (e[0] === "!") { neg = true; e = e.slice(1); }
			if (e === "Undead") e = "Scourge";
			let match;
			if (e === "TRUE") match = true;
			else if (e === "FALSE") match = false;
			else if (/^\d+$/.test(e)) match = true;                       // level: assume the player has it
			else if (e === "skip") match = false;                         // disabled upstream
			else if (e === "Male" || e === "Female") match = true;
			else match = e.toUpperCase() === c.cls.toUpperCase() || e === c.race || e === c.faction || e === "FOREVER" || e === "enUS";
			if (match === neg) { ok = false; break; }
		}
		if (ok) return true;
	}
	return false;
}

// ---- reading ---------------------------------------------------------------------------------------
function splitTag(line) {
	let tag = null;
	const m = line.match(/\s*<<\s*(.+)$/);
	if (m) { tag = m[1].replace(/\s+--.*$/, "").trim(); line = line.slice(0, m.index); }
	return [line.trim(), tag];
}

function readFile(file, lang) {
	const text = fs.readFileSync(file, "utf8").replace(/\r/g, "");
	const out = [];
	const re = /RegisterGuide\(\[\[([\s\S]*?)\]\]\)/g;
	let m, index = 0;
	while ((m = re.exec(text))) {
		const startLine = text.slice(0, m.index).split("\n").length;
		const g = { file, lang, index: ++index, startLine, header: {}, headerTags: {}, steps: [], enabledFor: null, raw: m[1] };
		let cur = null, inHeader = true;
		m[1].split("\n").forEach((raw, i) => {
			const ln = startLine + i;
			const trimmed = raw.trim();
			if (!trimmed || trimmed.startsWith("--")) return;
			const [line, tag] = splitTag(trimmed);
			if (/^step$/.test(line) || /^step\s/.test(line)) {
				cur = { ln, tag, lines: [] };
				g.steps.push(cur);
				inHeader = false;
				return;
			}
			if (inHeader) {
				if (line === "" && tag) { g.enabledFor = tag; return; }
				const k = line.match(/^#(\S+)\s*(.*)$/);
				if (k) { (g.hdrAll = g.hdrAll || []).push({ k: k[1], v: k[2].trim(), tag }); if (g.header[k[1]] === undefined) { g.header[k[1]] = k[2].trim(); g.headerTags[k[1]] = tag; } }
				return;
			}
			if (!cur) return;
			const e = { ln, tag, raw: line };
			let body = line, text2 = null;
			const gt = body.match(/\s*>>\s*(.*)$/);
			if (gt) { text2 = gt[1]; body = body.slice(0, gt.index); }
			e.text = text2;
			let k;
			if ((k = body.match(/^#(\S+)\s*(.*)$/))) {
				e.dir = k[1]; e.val = k[2].replace(/\s+--.*$/, "").trim();
			} else if ((k = body.match(/^\.(\S+)\s*(.*)$/))) {
				e.cmd = k[1]; e.args = k[2].replace(/\s+--.*$/, "").replace(/\s*,\s*/g, ",").trim();
			}
			cur.lines.push(e);
		});
		g.name = g.header.name;
		g.groups = [...new Set((g.hdrAll || []).filter((h) => h.k === "group").map((h) => h.v))];
		g.group = g.header.group || "Guides";
		g.title = g.group + "\\" + g.name;
		out.push(g);
	}
	return out;
}

function listGuideFiles(lang) {
	const base = path.join(ROOT, "Guides", lang);
	const files = [];
	for (const d of ["forever", "forever/dungeon", "survival"]) {
		const dir = path.join(base, d);
		if (!fs.existsSync(dir)) continue;
		for (const f of fs.readdirSync(dir)) if (f.endsWith(".lua")) files.push(path.join(dir, f));
	}
	return files;
}

// ---- registry --------------------------------------------------------------------------------------
const guides = [];
const byTitle = new Map();
for (const f of listGuideFiles("enUS")) {
	for (const g of readFile(f, "enUS")) {
		g.fileShort = path.relative(path.join(ROOT, "Guides", "enUS"), f).replace(/\\/g, "/");
		guides.push(g);
		if (!byTitle.has(g.title)) byTitle.set(g.title, g);
		for (const gr of g.groups) if (!byTitle.has(gr + "\\" + g.name)) byTitle.set(gr + "\\" + g.name, g);
	}
}
function findGuide(ref, group, strict) {
	ref = ref.trim();
	return byTitle.get(ref) || (group && byTitle.get(group + "\\" + ref)) || (strict ? null : guides.find((g) => g.name === ref)) || null;
}

// A header value as the engine reads it for this player: the first line whose "<< tag" applies.
function hdr(g, key, c) {
	for (const h of g.hdrAll || []) if (h.k === key && evalTag(h.tag, c)) return h.v;
	return undefined;
}

// ---- flattening (one guide, one player) ------------------------------------------------------------
// Returns steps with only the lines that apply to the player. Steps keep their guide and line of origin.
function flatten(g, c, from, to, seen) {
	seen = seen || new Set([g]);
	const out = [];
	let started = !from;
	for (const s of g.steps) {
		if (!evalTag(s.tag, c)) continue;
		const lines = s.lines.filter((e) => evalTag(e.tag, c));
		const inc = lines.find((e) => e.dir === "include");
		if (inc) {
			if (started) {
				let ref = inc.val, f = null, t = null;
				const r = ref.match(/^(.*?)@([^@\-]+)-?([^@\-]*)$/);
				if (r) { ref = r[1]; f = r[2] || null; t = r[3] || null; }
				const target = findGuide(ref, hdr(g, "group", c) || g.group);
				if (target && !seen.has(target)) {
					seen.add(target);
					out.push(...flatten(target, c, f, t, seen));
					seen.delete(target);
				}
			}
			continue;
		}
		const step = { guide: g, ln: s.ln, lines, dirs: {} };
		for (const e of lines) if (e.dir) step.dirs[e.dir] = e.val === "" ? true : e.val;
		if (!started && step.dirs.label === from) started = true;
		if (!started) continue;
		out.push(step);
		if (to && step.dirs.label === to) break;
	}
	return out;
}

// ---- players ---------------------------------------------------------------------------------------
function combosFor(g) {
	const list = [];
	const raceTags = new Set();
	for (const m of g.raw.matchAll(/<<[^\n]*/g)) for (const r of Object.values(RACES).flat().concat(["Undead"])) if (new RegExp("\\b" + r + "\\b").test(m[0])) raceTags.add(r === "Undead" ? "Scourge" : r);
	for (const faction of ["Horde", "Alliance"]) {
		const races = RACES[faction].filter((r) => raceTags.has(r));
		if (!races.length) races.push(RACES[faction][0]);
		for (const race of races) for (const cls of CLASSES) {
			const c = { faction, race, cls };
			if (g.enabledFor && !evalTag(g.enabledFor, c)) continue;
			const grp = hdr(g, "group", c);
			if (grp === undefined) continue;                               // every #group line is tagged for someone else
			if (/(A)/.test(grp) && faction !== "Alliance") continue;
			if (/(H)/.test(grp) && faction !== "Horde") continue;
			list.push(c);
		}
	}
	return list;
}
const who = (c) => c.cls + "/" + c.race;
function summarize(set) {
	const arr = [...set];
	if (arr.length >= 14) return "all";
	return arr.join(",");
}

// ---- findings --------------------------------------------------------------------------------------
const findings = new Map();   // key -> { rule, msg, where: Set }
function report(rule, key, msg, who_, loc) {
	if (!RULES.includes(rule)) return;
	const id = rule + "|" + key;
	let f = findings.get(id);
	if (!f) { f = { rule, key, msg, who: new Set(), loc }; findings.set(id, f); }
	if (who_) f.who.add(who_);
}
const locOf = (step, e) => (step.guide.fileShort + ":" + (e ? e.ln : step.ln) + " (" + step.guide.name + ")");

const wanted = (g) => !FILE_FILTER || g.fileShort.includes(FILE_FILTER);

// ---- A4: unknown commands / directives -------------------------------------------------------------
const parserSrc = fs.readFileSync(path.join(ROOT, "Parser.lua"), "utf8");
const HANDLED = new Set();
for (const m of parserSrc.matchAll(/^H\.([A-Za-z_]+)\s*=/gm)) HANDLED.add(m[1]);
for (const m of parserSrc.matchAll(/^H\["([^"]+)"\]\s*=/gm)) HANDLED.add(m[1]);
const KNOWN_DIRS = new Set(("completewith label requires sticky optional loop softcore hardcore hardcoreserver softcoreserver hidewindow " +
	"ah phase era som ssf season xprate tbc classic wotlk cata mop df retail forever version group subgroup name displayname next " +
	"defaultfor include internal map disabledungeons ignorecorpse icon level qremove tip nocheck dungeon dungeonskip enabledungeon " +
	"hidden nodeath").split(" "));

if (RULES.includes("A4")) {
	for (const g of guides) {
		if (!wanted(g)) continue;
		for (const s of g.steps) for (const e of s.lines) {
			if (e.cmd && !HANDLED.has(e.cmd)) report("A4", "cmd " + e.cmd, "no handler for .%s".replace("%s", e.cmd) + " (the line is only shown as text, or dropped)", null, g.fileShort + ":" + e.ln);
			if (e.dir && !KNOWN_DIRS.has(e.dir)) report("A4", "dir " + e.dir, "unknown directive #" + e.dir + " (typo?)", null, g.fileShort + ":" + e.ln);
		}
		for (const k of Object.keys(g.header)) if (!KNOWN_DIRS.has(k) && !/^(step)$/.test(k)) report("A4", "hdr " + k, "unknown guide header #" + k, null, g.fileShort + ":" + g.startLine);
	}
}

// ---- A1 / A2 per player ----------------------------------------------------------------------------
const FALLBACK_TEXT = /\b(fly|flight|run|travel|take the|boat|zeppelin|ship|portal|teleport|walk|ride|go to|head to|swim|cross)\b/i;
const placeOf = (t) => ((t || "").match(/(?:Hearth|Astral Recall)(?: or Astral Recall)?\s+to\s+(.+?)(?:\.|$| if | and |,)/i) || [])[1];
// same as Norm() in Hearth.lua: lower case, no ASCII punctuation, no leading "the ", single spaces
const normPlace = (s) => s.toLowerCase().replace(/[!-\/:-@\[-`{-~]/g, "").replace(/^the /, "").replace(/\s+/g, " ").trim();
const bindNames = new Map();   // area id -> Map(name -> count)
const pendingUnguarded = [];

for (const g of guides) {
	if (!wanted(g)) continue;
	if (!RULES.some((r) => r === "A1" || r === "A2")) break;
	for (const c of combosFor(g)) {
		const steps = flatten(g, c);
		const labels = new Set();
		steps.forEach((s) => { if (typeof s.dirs.label === "string") labels.add(s.dirs.label); });
		steps.forEach((s, i) => {
			// A2: labels
			for (const k of ["completewith", "requires"]) {
				const v = s.dirs[k];
				if (typeof v === "string" && v !== "next" && !labels.has(v)) {
					report("A2", g.title + "|" + k + " " + v, "#" + k + " " + v + ": no step with that label (the side step never ends by itself)", who(c), locOf(s));
				}
			}
			// A1
			// ".home >> Set your Hearthstone to X" + ".bindlocation id": X is the place of area id
			const home = s.lines.find((e) => e.cmd === "home"), homeBind = s.lines.find((e) => e.cmd === "bindlocation");
			if (home && homeBind && home.text) {
				const hp = (home.text.match(/[Hh]earth(?:stone)?\s+to\s+(.+?)(?:\.|$|,| if )/) || [])[1];
				if (hp) {
					const id = homeBind.args.split(",")[0];
					const m = bindNames.get(id) || new Map();
					const n = normPlace(hp);
					m.set(n, (m.get(n) || 0) + 1);
					bindNames.set(id, m);
				}
			}
			const hs = s.lines.find((e) => e.cmd === "hs");
			if (hs) {
				const place = placeOf(hs.text);
				const bind = s.lines.find((e) => e.cmd === "bindlocation");
				const guard = s.lines.some((e) => ["bindlocation", "subzoneskip", "zoneskip"].includes(e.cmd));
				// The engine adds a ".bindlocation" to an unguarded step whose place is in HearthAreas.lua; judged after the loop.
				if (!bind) pendingUnguarded.push({ key: g.title + "|hs-unguarded|" + s.ln, place, guard, text: hs.text || "", who: who(c), loc: locOf(s, hs) });
				if (bind && place) {
					const id = bind.args.split(",")[0];
					const m = bindNames.get(id) || new Map();
					const n = normPlace(place);
					m.set(n, (m.get(n) || 0) + 1);
					bindNames.set(id, m);
				}
				// A1c: when the hearthstone cannot be used there must be a way to the same place: a step of the
				// guide's own (a flight, a zone to travel to ...) or a place to point at, for the travel step the
				// engine adds (Parser.lua, FR.AddHearthFallbacks: the first .goto of the next 8 steps).
				if (bind || place) {
					let own = false, looked = 0;
					for (let j = i + 1; j < steps.length && looked < 3 && !own; j++) {
						const t = steps[j];
						if (t.lines.some((e) => e.cmd === "hs")) continue;
						looked++;
						if (t.lines.some((e) => ["fly", "zone", "subzone"].includes(e.cmd) || (e.cmd === "cast" && /teleport|portal|astral/i.test(e.text || "")) || (e.text && FALLBACK_TEXT.test(e.text)))) own = true;
					}
					let dest = false;
					for (let j = i + 1; j < Math.min(steps.length, i + 9) && !dest; j++) {
						if (steps[j].lines.some((e) => e.cmd === "hs")) continue;
						if (steps[j].lines.some((e) => e.cmd === "goto")) dest = true;
					}
					if (!own && !dest) report("A1", g.title + "|hs-nofallback|" + s.ln, "hearth step: no way to \"" + (place || "?") + "\" of the guide's own and no .goto in the next 8 steps to point at (the engine cannot add a travel step)", who(c), locOf(s, hs));
				}
			}
		});
		// #include ranges and #next
		if (RULES.includes("A2")) {
			steps.forEach(() => {});
		}
	}
	if (RULES.includes("A2")) {
		for (const s of g.steps) for (const e of s.lines) {
			if (e.dir !== "include") continue;
			let ref = e.val;
			const r = ref.match(/^(.*?)@([^@\-]+)-?([^@\-]*)$/);
			let f = null, t = null;
			if (r) { ref = r[1]; f = r[2] || null; t = r[3] || null; }
			const target = findGuide(ref, g.group);
			if (!target) { report("A2", g.title + "|include " + ref, "#include target not found: " + ref, null, g.fileShort + ":" + e.ln); continue; }
			const labelsOf = new Set(target.steps.flatMap((x) => x.lines.filter((l) => l.dir === "label").map((l) => l.val)));
			for (const l of [f, t]) if (l && !labelsOf.has(l)) report("A2", g.title + "|include-label " + ref + "@" + l, "#include range label \"" + l + "\" not found in " + target.title, null, g.fileShort + ":" + e.ln);
		}
		const next = g.header.next;
		if (next) {
			for (const part of next.split(";")) {
				const [ref] = splitTag(part);
				if (!ref) continue;
				if (!findGuide(ref, g.group)) report("A2", g.title + "|next " + ref, "#next target not found: " + ref, null, g.fileShort + ":" + g.startLine);
			}
		}
	}
}
// A1a: unguarded hearth steps the engine cannot guard either (place unknown)
if (RULES.includes("A1")) {
	const places = new Map();
	for (const [id, m] of bindNames) for (const n of m.keys()) { const s = places.get(n) || new Set(); s.add(id); places.set(n, s); }
	for (const u of pendingUnguarded) {
		const ids = u.place && places.get(normPlace(u.place));
		if (ids && ids.size === 1) continue;   // Parser.lua adds the guard
		report("A1", u.key, "hearth step without .bindlocation and the place is not known (" + (u.place ? "\"" + u.place + "\"" : "no place in the text") + "): \"" + u.text + "\"" + (u.guard ? " (only a zone guard)" : ""), u.who, u.loc);
	}
}
// A1b: one bind area with several place names
if (RULES.includes("A1")) {
	for (const [id, m] of bindNames) {
		if (m.size > 1) report("A1", "bind-area " + id, ".bindlocation " + id + " is used with different place names: " + [...m.keys()].join(" | "), null, "");
	}
}

// --emit-hearth-areas: place name -> area id of the guarded hearthstone steps, for Hearth.lua / HearthAreas.lua
if (opt("emit-hearth-areas")) {
	const byName = new Map();
	for (const [id, m] of bindNames) for (const n of m.keys()) { const s = byName.get(n) || new Set(); s.add(id); byName.set(n, s); }
	const lines = [];
	for (const [n, ids] of [...byName].sort((x, y) => x[0].localeCompare(y[0]))) {
		if (ids.size === 1) lines.push("\t[" + JSON.stringify(n) + "] = " + [...ids][0] + ",");
		else console.log("hearth place " + n + " has several areas (" + [...ids].join(", ") + ") and is left out");
	}
	fs.writeFileSync(path.join(ROOT, "HearthAreas.lua"), [
		"-- Generated by tools/Audit-Guides.js --emit-hearth-areas. Do not edit.",
		"-- Place a \"Hearth to <place>\" step names (lower case, no punctuation) -> the area id the guides' own",
		"-- \".bindlocation\" lines use for it. Parser.lua uses it to guard hearthstone steps that have no such line.",
		"local _, ns = ...",
		"local FR = ns.FR",
		"",
		"FR.HEARTH_AREAS = {",
		...lines,
		"}",
		"",
	].join("\n"));
	console.log("HearthAreas.lua: " + lines.length + " places");
}

// ---- A3: quests along the route --------------------------------------------------------------------
if (RULES.includes("A3") || RULES.includes("A3h")) {
	const headed = new Set(guides.map((g) => g.title));
	const referenced = new Set();
	for (const g of guides) for (const part of (g.header.next || "").split(";")) { const [ref] = splitTag(part); const t = ref && findGuide(ref, g.group, true); if (t) referenced.add(t); }
	const heads = guides.filter((g) => !referenced.has(g) && g.header.next);
	for (const head of heads) {
		if (!wanted(head)) continue;
		for (const c of combosFor(head)) {
			// follow #next (first alternative that applies)
			const chain = [];
			const seen = new Set();
			let cur = head;
			while (cur && !seen.has(cur)) {
				seen.add(cur);
				chain.push(cur);
				let nxt = null;
				for (const part of (hdr(cur, "next", c) || "").split(";")) {
					const [ref, tag] = splitTag(part);
					if (!ref || !evalTag(tag, c)) continue;
					nxt = findGuide(ref, hdr(cur, "group", c) || cur.group, true) || findGuide(ref, cur.group);
					if (nxt) break;
				}
				cur = nxt;
			}
			if (chain.length < 2) continue;
			const ev = [];
			chain.forEach((g, gi) => flatten(g, c).forEach((s, si) => {
				for (const e of s.lines) {
					if (!e.cmd || !["accept", "turnin", "complete", "abandon"].includes(e.cmd)) continue;
					const id = (e.args.match(/\d+/) || [])[0];
					if (id) ev.push({ k: e.cmd, id, gi, si, pos: ev.length, g, ln: e.ln, t: e.text, step: s });
				}
			}));
			const by = {};
			ev.forEach((x) => (by[x.id] = by[x.id] || []).push(x));
			const label = chain[0].group + " / " + head.name;
			if (opt("quest") && c.cls === "Warrior" && by[opt("quest")]) console.log("[quest " + opt("quest") + "] " + label + " (" + c.faction + ") chain of " + chain.length + ": " + by[opt("quest")].map((x) => x.k + "@" + x.g.name + ":" + x.ln + "#" + x.gi).join(", "));
			for (const id in by) {
				const L = by[id];
				const acc = L.find((x) => x.k === "accept");
				const tin = L.filter((x) => x.k === "turnin");
				const gone = L.some((x) => x.k === "abandon");
				// The last guides of a chain hand their quests on to a chain this audit cannot follow (another race / group).
				if (acc && !tin.length && !gone && acc.gi < chain.length - 3) {
					report("A3", label + "|noturnin " + id, "quest " + id + " (" + (acc.t || "").replace(/^Accept /, "") + ") is accepted but never turned in or abandoned on the route", who(c), acc.g.fileShort + ":" + acc.ln);
				}
				if (acc && tin.length && tin.every((x) => x.gi < acc.gi || (x.gi === acc.gi && x.si < acc.si))) {
					report("A3", label + "|tinbefore " + id, "quest " + id + " (" + (acc.t || "") + ") is turned in before it is accepted", who(c), tin[0].g.fileShort + ":" + tin[0].ln);
				}
				if (RULES.includes("A3h") && acc && tin.length && !L.some((x) => x.k === "complete")) {
					const after = tin.find((x) => x.gi > acc.gi + 1);
					if (after) report("A3h", label + "|held " + id, "quest " + id + " (" + (acc.t || "") + ") is held for " + (after.gi - acc.gi) + " guides and no step has its objectives", who(c), acc.g.fileShort + ":" + acc.ln);
				}
			}
		}
	}
}

// ---- A5: translations ------------------------------------------------------------------------------
if (RULES.includes("A5")) {
	const sig = (g) => g.steps.map((s) => s.lines.filter((e) => e.cmd && !["target", "mob", "unitscan", "link", "macro", "timer"].includes(e.cmd)).map((e) => e.cmd).join(" ")).join("\n");
	for (const lang of ["deDE", "esES", "frFR", "ptBR", "zhCN"]) {
		for (const f of listGuideFiles(lang)) {
			const rel = path.relative(path.join(ROOT, "Guides", lang), f).replace(/\\/g, "/");
			if (FILE_FILTER && !rel.includes(FILE_FILTER)) continue;
			const en = path.join(ROOT, "Guides", "enUS", rel);
			if (!fs.existsSync(en)) { report("A5", lang + "|" + rel, "no English file for " + rel, null, rel); continue; }
			const tr = readFile(f, lang), base = readFile(en, "enUS");
			const baseBy = new Map(base.map((g) => [g.title, g]));
			for (const g of tr) {
				const b = baseBy.get(g.title);
				if (!b) { report("A5", lang + "|" + rel + "|" + g.name, "translated guide \"" + g.name + "\" has no English twin", null, rel + ":" + g.startLine); continue; }
				if (g.steps.length !== b.steps.length) report("A5", lang + "|" + rel + "|" + g.name, "step count " + g.steps.length + " vs English " + b.steps.length + " in \"" + g.name + "\"", null, rel + ":" + g.startLine);
				else if (sig(g) !== sig(b)) report("A5", lang + "|" + rel + "|" + g.name + "|sig", "commands differ from English in \"" + g.name + "\" (steps are out of sync)", null, rel + ":" + g.startLine);
			}
			for (const b of base) if (!tr.some((g) => g.title === b.title)) report("A5", lang + "|" + rel + "|missing " + b.name, "\"" + b.name + "\" is not translated (the English guide is used)", null, rel);
		}
	}
}

// ---- output ----------------------------------------------------------------------------------------
let allow = [];
const allowFile = path.join(__dirname, "audit-allow.json");
if (fs.existsSync(allowFile)) allow = JSON.parse(fs.readFileSync(allowFile, "utf8"));
const allowed = (f) => allow.some((a) => a.rule === f.rule && f.key.includes(a.key));

const out = [...findings.values()].sort((a, b) => a.rule.localeCompare(b.rule) || a.key.localeCompare(b.key));
const counts = {};
let open = 0;
for (const f of out) {
	counts[f.rule] = (counts[f.rule] || 0) + 1;
	if (!allowed(f)) open++;
}
const names = { A3h: "quests held for long (info)", A1: "hearthstone", A2: "references", A3: "quests", A4: "commands", A5: "translations" };
for (const rule of RULES) {
	const list = out.filter((f) => f.rule === rule);
	console.log("\n== " + rule + " " + (names[rule] || "") + ": " + list.length + " finding(s)");
	for (const f of list) {
		console.log((allowed(f) ? "  [allowed] " : "  ") + f.msg + (f.who.size ? "  <" + summarize(f.who) + ">" : "") + (f.loc ? "\n      " + f.loc : ""));
	}
}
console.log("\nTotal: " + out.length + " finding(s), " + open + " not in audit-allow.json");
const jsonOut = opt("json");
if (typeof jsonOut === "string") {
	fs.writeFileSync(jsonOut, JSON.stringify(out.map((f) => ({ rule: f.rule, key: f.key, msg: f.msg, who: [...f.who], loc: f.loc })), null, 1));
}
if (opt("strict") && open > 0) process.exit(1);
