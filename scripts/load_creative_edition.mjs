#!/usr/bin/env node
// Bracket Battle — load a curated creative edition into Supabase.
//
//   node scripts/load_creative_edition.mjs path/to/edition.json
//
// Validates a creative-edition JSON (see Reference/Bracket Battle/creative-edition-
// template.json) and prints an INSERT statement you paste into the Supabase SQL editor.
// No secrets, no app changes — adding a future edition is pure data. The Worker picks
// the new `ready` row on the next rotation.
//
// (We emit SQL rather than calling Supabase directly so you never need the service-role
// key on your laptop — you run the statement in the dashboard, same as the schema.)

import { readFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("usage: node scripts/load_creative_edition.mjs <edition>.json");
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
for (const f of ["id", "theme_label", "title", "description", "season", "entries"]) {
  if (ed[f] === undefined || ed[f] === null || ed[f] === "") errs.push(`missing top-level "${f}"`);
}
if (!Array.isArray(ed.entries) || ed.entries.length < 4) {
  errs.push(`"entries" must be an array of at least 4 contenders`);
}

const seeds = new Set();
const ids = new Set();
(ed.entries || []).forEach((e, i) => {
  for (const f of ["player_id", "player_name", "team_abbreviation", "seed", "content", "source"]) {
    if (e[f] === undefined || e[f] === null || e[f] === "") errs.push(`entry ${i}: missing "${f}"`);
  }
  if (ids.has(e.player_id)) errs.push(`entry ${i}: duplicate player_id "${e.player_id}"`);
  ids.add(e.player_id);
  if (seeds.has(e.seed)) errs.push(`entry ${i}: duplicate seed ${e.seed}`);
  seeds.add(e.seed);
  if (/EXAMPLE|REPLACE/i.test(`${e.content} ${e.source}`)) {
    errs.push(`entry ${i} ("${e.player_name}"): still has placeholder EXAMPLE/REPLACE content — fill it in`);
  }
});

if (errs.length) {
  console.error(`✗ ${file} is not ready:\n  - ${errs.join("\n  - ")}`);
  process.exit(1);
}

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;             // SQL string literal
const jsonb = q(JSON.stringify(ed.entries));                        // entries as jsonb text

const sql = `-- ${ed.entries.length} entries · season ${ed.season} · run in the Supabase SQL editor
insert into public.bracket_creative_editions
  (id, theme_label, title, description, status, season, entries)
values
  (${q(ed.id)}, ${q(ed.theme_label)}, ${q(ed.title)}, ${q(ed.description)}, 'ready', ${Number(ed.season)}, ${jsonb}::jsonb)
on conflict (id) do update set
  theme_label = excluded.theme_label, title = excluded.title,
  description = excluded.description, season = excluded.season,
  entries = excluded.entries, status = 'ready';
`;

console.error(`✓ ${ed.title}: ${ed.entries.length} entries, valid. SQL below — paste into Supabase:\n`);
console.log(sql);
