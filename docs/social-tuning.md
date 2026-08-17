# Social Self-Tuning — players (IG) + reporters (Bluesky) + analytics discovery

**The system that keeps the Social tab's default sources current WITHOUT manual curation.**
Built 2026-08-16/17. Both sides are FULLY AUTOMATED with server-enforced guardrails; the owner
reviews run reports and tunes the routine prompts from real outcomes (the same operating model
as the KHG content routines). All state lives proxy-side (`nwslapp-proxy`); the app consumes it.

## 0. The laws (owner rulings — do not relax without an explicit new ruling)

1. **Identity is a MUST, not a nice-to-have.** The app is a publisher: a card under a player's
   name asserts "this is her." Every featured IG account requires `athleteClass: true` in the
   research memory — identity CONFIDENCE that it's the professional player's own account. Best
   evidence = the profile's athlete-class professional-category label ("Athlete" / localized
   equivalents like "Futbolista"); when direct profile reads are rate-limited (~6/run from
   datacenter IPs), web corroboration substitutes (club/federation page linking the exact
   handle, bio naming her club/NT, verified badge). Nothing solid ⇒ not featured. The SERVER
   enforces this in `/apply` — the routine cannot bypass it. Verified (blue check) is an
   accuracy ACCELERATOR (less corroboration needed), never the gate itself.
2. **Player eligibility = NWSL ∧ NT, EARNED FOREVER.** On an NWSL roster AND has represented a
   national team (any federation — all equal). Once earned, never lost to a missed camp: the
   ledger is append-only. The ONLY drops: leaving the NWSL (verified — beware ESPN name
   variants) or a dead handle. Fox / Girma / A. Thompson are grandfathered (Europe-based,
   tagged to last NWSL club) — the server refuses to drop them.
3. **Ceilings are CEILINGS, never targets.** Carry exactly who qualifies. Players: 160 total
   (2 pools × 80/run — the per-run Apify budget). Reporters: 24 (`MAX_FEED_HANDLES`, the
   classification-cost budget). Never pad toward either.
4. **Players are IG-only for defaults.** A live sweep found essentially no genuine player
   Bluesky accounts (name-matches were impersonation squats), so default player-Bluesky
   discovery AND serving were removed. Users may still add a player's Bluesky themselves
   (`/feed?playerBsky=` — their explicit choice, unfiltered).
5. **Player content NEVER passes through the Haiku classifier** — not IG, not user Bluesky
   adds. Haiku's scope is exactly the default reporter/league list.
6. **Analytics are anonymous** — `reporter_added` carries `"TEAM|handle"`: which club FANBASE
   added which voice, never which fan. No IDs, no IPs, ever.

## 1. Player pipeline (fully automated)

**Data:** live list = KV `social:player-list` (`{name, abbr, ig, addedAt?, source?, pool}`;
source constant `PLAYER_SOCIAL_SEED` in `index.ts` serves only until the first apply).
Eligibility ledger = KV `social:nt-ledger` (`{normName: {name, firstSeen, source-slug, nation,
research?}}`) — append-only, earned-forever; `research` = the once-ever web-research memory
(`status, ig, category, athleteClass, verified, checkedAt`), so no candidate is re-researched.

**Endpoints** (auth: owner `x-admin-key` OR the routine's scoped `x-audit-key`,
`SOCIAL_AUDIT_KEY` secret):
- `GET /social/player-audit?nt=<slug>` — fetch one NT competition's squads from ESPN (grouped
  roster decode), intersect with live NWSL rosters by `normalizeName`, append matches to the
  ledger. Feeds = `WOMENS_NT_FEEDS` minus two >50-team qualifying feeds (subrequest cap;
  excluded by design — a miss only delays an earned-forever append).
- `GET /social/player-audit?section=nwsl` — the decision report: capacity/pools, per-club
  coverage, `featured[]` (with gate records), `candidates.needsResearch` / `.researched`
  (delta-oriented — the routine researches ONLY needsResearch), advisory `drops`. Decision
  paths build the roster map LIVE (a stale cache once hid a marquee transfer — cached map is
  for `?nt=` only).
- `POST .../research` — writes research memory; malformed entries come back in `skipped[]`
  with reasons (never silently ignored).
- `POST .../apply` — auto-apply with server guards: identity gate, club-code validation,
  dedupe, the 160 ceiling, grandfather refusal; new adds auto-join the LIGHTER pool. Diag
  `socialPlayerApply` on every call.
- `GET .../scrape-meta` — reads the most recent ALREADY-RUN Apify dataset (free API GET, never
  runs the actor): per-handle `is_verified`/full-name from IG's own data. ⚠️ Field trap: each
  item's `user` is the POST AUTHOR — collab posts carry the co-poster, so identity fields come
  only from self-authored items.

**Pool rotation (the scale mechanism):** the every-2-day cron scrapes ONE pool per run
(alternating via the KV marker). Same monthly Apify volume as a single 80-handle list, double
the coverage; each player refreshes ~every 4 days; an outage costs one pool's freshness. Pools
are club-balanced (split within each club) and self-balance via lighter-pool adds.

**Routine:** "Social players — audit + auto-apply" (Claude Remote, Mar/Jul/Oct 15). Steps:
ledger top-up across all feeds → report → research ONLY new candidates (identity law; IG-only)
→ verify departures before drops → apply → transparency report. Mirror doc:
`nwslapp-proxy/scripts/social-player-audit-routine.md`.

## 2. Reporter pipeline (fully automated, guarded)

**Data:** live list = KV `social:reporter-list` (`{handle, kind: reporter|league}`; seed =
`FEED_HANDLES` const). Consumed by `/feed` (curated fetch + Haiku classification), the admin
Status tab, and the audit endpoint — all via `loadFeedHandles(env)`.

**Endpoints:**
- `GET /social/reporter-audit` — health tiers per handle on last ORIGINAL post (ok <14d /
  cooling 14–30d / dormant >30d / empty / dead; same logic as the Status tab via
  `bskySourceHealth`), a consecutive-flag streak (KV `social:reporter-dormant-streak`; TWO
  consecutive flagged audits = drop candidate, one = watch), an OUTAGE GUARD (majority flagged
  at once ⇒ platform outage: streaks frozen, zero candidates — live-proven during a real
  Bluesky outage), and `addSignals` (the anonymous fan add counters, aggregated from
  `analytics_counters`; requires `grant select … to service_role`, applied 2026-08-17).
- `POST /social/reporter-audit/apply` — auto-apply with server guards: **max 2 adds per call**,
  the 24 ceiling, handle validation, dedupe. Diag `socialReporterApply`.

**The quality bar (routine-enforced; the server can't judge content):** add only voices whose
NWSL coverage is distinctive and engaging — breaking news, transfers/rumors, player storylines
with insight or energy. NOT: bare article links with no text, generic recap/aggregation
accounts, or anything without an ORIGINAL post in ~30 days (hard recency check; reposts don't
count — an active-elsewhere reporter with a dead/repost-only Bluesky is still a drop: the list
serves what posts). Mixed beats are fine — Haiku filters per-post. Follow-graph discovery
(follows-of-follows) is REJECTED; discovery = fan add-signals (3+ adds of one handle among a
club's fans) + an unconditional per-club beat-coverage web sweep every run.

**Routine:** "Social reporters — monthly audit + discovery" (Claude Remote, 1st monthly).
Mirror doc: `nwslapp-proxy/scripts/social-reporter-audit-routine.md`.

## 3. Analytics discovery (Phase 3)

App fires `reporter_added` (`"TEAM|handle"`, once per followed team, on a reporter add in
Content Preferences) + `reporter_add_session` (once per session — the adders denominator),
through the existing anonymous Level-3 pipeline (`Analytics.swift` → `/analytics` →
`increment_counters` RPC → `analytics_counters`). `reporter_added` params get 64 chars (bsky
handles outrun the 32 default). The audit endpoint aggregates per handle/club; the threshold
(3+, tunable as the user base grows) lives in the routine prompt. Loop proven end-to-end with
a synthetic signal 2026-08-17.

## 4. User-added sources (unchanged by automation)

User adds are their explicit choice: reporters (`handles=`) and player Bluesky (`playerBsky=`)
serve UNFILTERED with `userAdded: true` (never Haiku — the cost firewall). Layering: an active
default supersedes a same-handle user add; a muted default (`muted=` param) lets the user add
resurface; user adds are removed via Remove, never by mutes. Persist forever app-side.

## 5. Cost model + tuning

- Apify: ~79 handles/run × ~12 items × ~15 runs/mo ≈ $4.3/mo — inside the $5 tier, bounded by
  `MAX_POOL_HANDLES`, independent of total player count.
- Haiku: bounded by the default reporter list only (user adds skip it). 18 handles ≈ tens of
  posts/day ≈ single-digit dollars/year; `MAX_FEED_HANDLES=24` is the budget ceiling.
- Tuning model: automate at ~90%, review the run reports (push notifications per run), adjust
  the routine prompts from real outcomes. Prompt edits: `RemoteTrigger update` on the trigger
  (keep the mirror docs in `scripts/` in sync — they are the source of truth for intent).

## 6. Diagnostics vocabulary (all in the sdiag spine)

`apifyHandleEmpty` / `apifyRunFail` (player scrape) · `bdHandleEmpty` (club scrape) ·
`socialPlayerApply` / `socialResearchSaved` / `socialNtLedgerRun` (player pipeline) ·
`socialReporterApply` / `reporterAuditOutage` / `reporterAuditSbFail` (reporter pipeline) ·
`feedUpstreamTimeout` (the /feed 8s hang bound + two-wave build — news first, Bluesky second,
so a Bluesky outage can't starve the rest) · `playerCapExceeded` (per-pool budget).
