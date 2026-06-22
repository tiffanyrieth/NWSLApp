#!/usr/bin/env node
// Bracket Battle — load a STATS edition recipe into Supabase.
//
//   node scripts/load_stats_edition.mjs path/to/stats-edition.json
//
// A stats edition is a RECIPE, not a roster: it says which position to pull and which
// stat to seed by, and the Worker builds the player pool live from ESPN at generation
// time (see bracket-engine.ts buildStatsPool). So — unlike a creative edition — there
// are no per-player entries to curate here. Validates the recipe and prints an INSERT
// you paste into the Supabase SQL editor (no service-role key needed on your laptop).
// The Worker picks the new `ready` row on the next rotation.
//
// See Reference/Bracket Battle/stats-edition-template.json for the shape, and
// supabase/seed_bracket_stats_editions.sql for the launch set already authored.

import { readFileSync } from "node:fs";

const POSITIONS = new Set(["F", "M", "D", "G"]); // null = all positions

const file = process.argv[2];
if (!file) {
  console.error("usage: node scripts/load_stats_edition.mjs <stats-edition>.json");
  process.exit(1);
}

let raw;
try {
  raw = JSON.parse(readFileSync(file, "utf8"));
} catch (e) {
  console.error(`Could not read/parse ${file}: ${e.message}`);
  process.exit(1);
}

// Drop documentation keys (anything starting with "_").
const ed = Object.fromEntries(Object.entries(raw).filter(([k]) => !k.startsWith("_")));

const errs = [];
for (const f of ["id", "theme_label", "title", "description", "seeding_stat", "season"]) {
  if (ed[f] === undefined || ed[f] === null || ed[f] === "") errs.push(`missing "${f}"`);
}
// position_filter is optional (null = all positions) but, when present, must be valid.
if (ed.position_filter !== undefined && ed.position_filter !== null && !POSITIONS.has(ed.position_filter)) {
  errs.push(`"position_filter" must be one of F, M, D, G, or null (got "${ed.position_filter}")`);
}
if (ed.season !== undefined && !Number.isInteger(Number(ed.season))) {
  errs.push(`"season" must be an integer year`);
}

if (errs.length) {
  console.error(`✗ ${file} is not ready:\n  - ${errs.join("\n  - ")}`);
  process.exit(1);
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;            // SQL string literal
const pos = ed.position_filter == null ? "null" : q(ed.position_filter);

const sql = `-- stats recipe · ${ed.position_filter ?? "ALL"} · seed by ${ed.seeding_stat} · season ${ed.season}
insert into public.bracket_stats_editions
  (id, theme_label, title, description, position_filter, seeding_stat, status, season)
values
  (${q(ed.id)}, ${q(ed.theme_label)}, ${q(ed.title)}, ${q(ed.description)}, ${pos}, ${q(ed.seeding_stat)}, 'ready', ${Number(ed.season)})
on conflict (id) do update set
  theme_label = excluded.theme_label, title = excluded.title, description = excluded.description,
  position_filter = excluded.position_filter, seeding_stat = excluded.seeding_stat,
  season = excluded.season, status = 'ready';
`;

console.error(`✓ ${ed.title}: valid stats recipe. SQL below — paste into Supabase:\n`);
console.log(sql);
