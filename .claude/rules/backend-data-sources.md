---
paths:
  - "**/ESPNService.swift"
  - "**/AppConfig.swift"
  - "**/Scoreboard.swift"
  - "**/Standings.swift"
  - "**/MatchSummary.swift"
  - "**/Competition.swift"
  - "**/Roster.swift"
  - "**/MatchWeather.swift"
---

# ⚠️ Data sources (ESPN / proxy / roster / weather) — decode DEFENSIVELY (read the doc first)

**STOP. Read `docs/backend.md` before you change how any of this fetches, decodes, or caches.** These are
the seams where the app meets ESPN's *unofficial* endpoints and the `nwslapp-proxy` Worker. The quirks below
are live-proven and NOT reconstructable from general knowledge — reasoning from first principles here has
repeatedly shipped bugs (a fake FT on a suspended match, a stuck clock, a wiped roster). Don't guess what a
data source is or does — **`docs/backend.md` is the map of every source the app uses** (that's why it exists,
and it's the thing that stops a wrong-direction rabbit hole).

## Source-of-truth docs (read the relevant one BEFORE editing):

- **`docs/backend.md`** — every ESPN endpoint + quirk, the proxy routes (`/scoreboard`, `/roster`,
  `/summary`, `/weather`, `/predict/community`, headshots/crests, bracket engine), the pass-through cache +
  the parsed-vs-**unparsed** feed inventory, and the Supabase schema/migrations/grants.
- **`docs/roster-source-research.md`** — read BEFORE any roster-source / cross-check work (ESPN vs the NWSL
  SDP API; two error classes; why the app stays on ESPN).

## The quirks that bite (all paid for — never "simplify" them away):

- **Scores are `String`, not `Int`.** `/scoreboard` needs `&limit=500` for a full season.
- **`state=="post"` does NOT mean FINISHED** (a wind hold at 27' reported `post`+`completed:false`+
  `STATUS_SUSPENDED`). Anything meaning "the result is settled" uses **`Event.isFinalResult` /
  `isUnfinishedPost`** (in `Scoreboard.swift`) — **fail-OPEN**: only `completed:false` or an explicit
  non-final status blocks; a sparse payload scores as before.
- **The full-season `dates=` query serves live state 25–47 min STALE** (ESPN-side cache); windowed/default
  queries stay fresh. `_cb` forces ESPN to recompute (proxy busts upstream on a `/scoreboard` MISS).
- **`status.clock` FREEZES at 45:00 / 90:00** through stoppage, and ESPN keeps `state=="in"` through
  halftime + advances `period`→2 at the START of the break. The live-clock ANCHORING logic is owned by
  `MatchClockKit` / `docs/live-activity-v2.md` — do not re-derive it here.
- **Roster = a VERIFIED pipeline, not a raw fetch:** last-known-good KV (`proxyCachedAsOf` + "Roster as of…"),
  a <50% continuity guard, nightly 08:00 UTC ESPN×NWSL verification, 90-day owner overrides. **Neither feed
  auto-wins** (ESPN erases real players; the NWSL feed lags transfers + dupes numbers). Detail: backend.md.
- **Weather** (`MatchWeather`) = PAST-only kickoff-hour temp/sky from **Open-Meteo** via the proxy `/weather`,
  keyed by a static ESPN-venue-id table, cached write-once. Not a forecast.
- **IG / social content is scraped via Bright Data** (proxy side) — the app doesn't hit Instagram directly.
- **Feeds carry MORE than we parse** — check `docs/backend.md`'s parsed-vs-unparsed inventory FIRST before
  proposing any new data source (`/summary` already carries `commentary`/`leaders`/`videos`, etc.).

Most traffic routes through the **`nwslapp-proxy`** Worker (`~/Projects/nwslapp-proxy`); DEBUG
`-useESPNDirect` bypasses it. Teams/standings hit ESPN direct. State which doc you read when you touch this.
