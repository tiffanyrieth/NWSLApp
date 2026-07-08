# Navigation Identity

_Each tab's lens. Read when adding or redesigning a screen/tab._

Each tab has a distinct lens. When adding/redesigning, check the lens matches and neighbors
stay consistent. Full rationale in `Reference/navigation-architecture.md`.
- **Home** — your teams, right now. Personal + temporal. The engagement hub (live content,
  Player Spotlight, Fan Zone games, "Coming up").
- **Schedule** — when do they play / what happened? Full-season calendar — INCLUDING the
  postseason: playoff games render as round-grouped sections (QUARTERFINALS/SEMIFINALS/
  CHAMPIONSHIP, status-colored headers + left bar) at the chronological end, with a year-round
  TBD "road to the championship" tail (ESPN's published season windows) and a clinch-gated
  "Playoffs" chip (my-path status → the bracket road once seeded). The playoffs live HERE and
  only here — a Standings-tab bracket was removed as duplication (playoff games ARE schedule
  data). The completed season stays browsable through the offseason until the next season's
  schedule publishes (MatchStore rollover).
- **Standings** — where does your team sit? Pure table, all season (no playoff surface).
- **Teams** — the club directory + deep dives.
- **Feed** — the conversation around your teams (reporter/journalist/social voices).

**Adjacency rule:** Home Module 1 (team content) and Feed (reporter/social voices) are
distinct — don't blur them. Schedule cards and MatchDetailView share visual language.
