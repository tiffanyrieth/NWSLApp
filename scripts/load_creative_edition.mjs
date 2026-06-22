#!/usr/bin/env node
// Bracket Battle — load a CREATIVE edition (theme-only) into Supabase.
//
//   node scripts/load_creative_edition.mjs path/to/creative-edition.json
//
// A creative edition is now just a THEME: a label, a title, and a one-line description.
// The Worker pulls the whole-league player pool from ESPN automatically (all positions,
// seeded by the same visibility heuristic as stats editions) — there are no per-player
// entries or content lines to curate. Matchup cards show name/jersey/team; the theme is
// all the context fans need. Validates the theme and prints an INSERT you paste into the
// Supabase SQL editor (no service-role key needed locally). The Worker picks the new
// `ready` row on the next rotation.
//
// (The launch set is already authored in supabase/seed_bracket_creative_editions.sql;
// use this loader to add a one-off theme later — the only manual input is the theme.)

import { readFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("usage: node scripts/load_creative_edition.mjs <creative-edition>.json");
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
for (const f of ["id", "theme_label", "title", "description", "season"]) {
  if (ed[f] === undefined || ed[f] === null || ed[f] === "") errs.push(`missing "${f}"`);
}
if (ed.season !== undefined && !Number.isInteger(Number(ed.season))) {
  errs.push(`"season" must be an integer year`);
}
if (ed.entries !== undefined) {
  errs.push(`"entries" is no longer used — creative editions are theme-only (the Worker builds the pool). Remove it.`);
}

if (errs.length) {
  console.error(`✗ ${file} is not ready:\n  - ${errs.join("\n  - ")}`);
  process.exit(1);
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`; // SQL string literal

const sql = `-- creative theme · season ${ed.season} · run in the Supabase SQL editor
insert into public.bracket_creative_editions
  (id, theme_label, title, description, status, season)
values
  (${q(ed.id)}, ${q(ed.theme_label)}, ${q(ed.title)}, ${q(ed.description)}, 'ready', ${Number(ed.season)})
on conflict (id) do update set
  theme_label = excluded.theme_label, title = excluded.title,
  description = excluded.description, season = excluded.season, status = 'ready';
`;

console.error(`✓ ${ed.title}: valid creative theme. SQL below — paste into Supabase:\n`);
console.log(sql);
