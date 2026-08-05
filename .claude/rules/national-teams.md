---
paths:
  - "**/NationalTeam*.swift"
  - "**/ConfederationMap.swift"
---

# ⚠️ National teams — a deliberately LIGHTER, live-fetched tier (read the doc first)

**STOP. Read `docs/national-teams.md` before you change NT display, alerts, or feeds.** NT is the deliberate
INVERSE of the club-roster stack: **all NT data is LIVE-FETCHED, ESPN-AS-IS — no storage, no proxy
last-known-good, no nightly verification, no owner overrides, no crons** (there's no second source to verify
against). Don't apply roster-pipeline reasoning here.

## Source-of-truth doc:

- **`docs/national-teams.md`** — the trust model, the feed/slug system, the browse surface, and the boundaries.

## The facts that bite:

- **NT team ids are per-WOMEN'S-program.** USWNT = **2765**, NOT 660. Using the men's id silently returns the
  wrong squad.
- **Schedule + alerts must stay aligned.** ESPN's `all/teams/{id}/schedule` is **HISTORY-only**, so UPCOMING
  NT fixtures come ONLY from the per-competition scoreboards (friendlies + confederation championships +
  WC/Olympic qualifying).
- **A new competition = add its slug to all THREE lists in sync** — app `NationalTeamFeed.all`, proxy
  `WOMENS_NT_FEEDS` (+ allowlist), watcher `NT_LEAGUES` — **AND** tag its `scope` in `ConfederationMap.swift`
  (untagged defaults to global/polled-for-everyone, fail-open).
- **Alerts:** bell keyed by FIFA code → `competition_alert_preferences` (separate from the club-id
  `team_alert_preferences`); **V1 push only** (no Live Activities for NT). Fan-out is confederation-scoped.

State that you read the doc when you touch this.
