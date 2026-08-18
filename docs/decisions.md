# Decisions ledger — SETTLED rulings & owner-iterating calls

This file is the **durable, append-mostly record of decisions a future session must NOT quietly reverse.**
It exists because AI sessions repeatedly reopen settled product rulings (the restore line was re-litigated
~7×) or "fix" work the owner deliberately deferred. Kept OUT of CLAUDE.md's size budget so it can never be
trimmed to fit.

**How to use it:** before you change behavior, delete a fact, or "improve" something that matches an entry
below, you must **argue against the entry in the open** — cite it, state why it no longer holds, and get the
owner's explicit agreement. Silence is not consent to reverse.

**What belongs here (two kinds only):**
1. **SETTLED** — shipped product rulings + hard reasoning-error guardrails the owner has decided. Protect hard.
2. **PROVISIONALLY DONE / owner-iterating** — the owner marked something done *on purpose* while planning to
   tune it over weeks. Do NOT "fix," revert, or re-litigate it; treat the current state as intentional.

**What does NOT belong here:** design *preferences* that stay legitimately re-examinable (dark-only theme,
card density, team-naming, specific layouts). Those live in CLAUDE.md's UI rules and remain open to revisit on
their merits (`feedback_rules_are_reexaminable`). This ledger locks *rulings*, not *tastes*. When in doubt
whether something is a locked ruling or an open preference, ASK — don't assume either way.

---

## SETTLED

### THE RESTORE LINE — a reinstall is a clean slate (re-litigated ~7× — treat as closed)
Detailed PREFERENCES may restore on sign-in; the generic "who do I follow" and per-team/NT alert BELLS may
NOT. Concretely: follows sync **UPWARD-ONLY** (device is source of truth; no restore-down); the nine alert
TYPES (`notification_preferences`) restore verbatim but land INERT (apply to nothing until a bell is tapped);
per-team/NT bells do NOT restore; game PROGRESS (`fanzone_progress`) DOES restore. **Why:** not re-selecting a
team after a reinstall is a real signal, not data loss — a reinstall is often someone resetting a broken
state; restoring saved ~2 taps of 16. **Failed alternative:** a restore-down hijacked the onboarding picker
when the alert-bell intercept let a user sign in mid-onboarding, and "only the oldest follow survives" was a
data-loss bug. Full mechanism: `docs/data-sync.md`; owner ruling 2026-08-03.

### Predict graded results are SERVER-DURABLE (supersedes part of the 2026-08-03 storage line)
Owner ruling 2026-08-10. The 2026-08-03 data-sync audit filed Predict's per-match score breakdowns
(`predict.v2.scores`) as Category-3 local-only ("per-match detail × every user = real DB growth").
A real reinstall that same week showed the cost: the owner lost her Recent Results + round board,
and — combined with the board-rendering bug fixed the same day — appeared to lose her leaderboard
standing, exactly the "starting over" the Category-2 acceptance bar promises can't happen. **Ruling:**
graded results (breakdown + the submitted XI, needed to re-render predicted-vs-actual) upload
POST-GRADING to `predict_match_results` (own-row RLS) and restore at sign-in. ~26 rows × ~300B per
user per season is inside the cost rule; the storage line was drawn for unbounded per-round detail,
not for this. **Unchanged and still binding:** pre-deadline lineups are NEVER uploaded (the
community-consensus protections); the plain-upsert merge is deliberate (a regrade must rewrite —
don't "fix" it into a GREATEST). Mechanism: `docs/data-sync.md` Category 2.

### Multi-device integrity — atomic-pair merge + cross-device dedup (owner 2026-08-13, closes roadmap #10)
Investigation (three explorers) of the CURRENT code found the old score-DOUBLING (20→40 on a 2nd device)
was already fixed — every local↔server reconcile is max-or-skip, never additive — but four real gaps
remained. Owner: close all four now (not for cheating, but so edge cases don't become mystery bug
reports). **Rulings:**
- **Atomic-pair merge (#10 proper).** The persisted leaderboard merges maxed numerator and denominator
  as SEPARATE scalars, so a two-device user could store an average nobody scored (100pts/5 + 80/6 →
  100/6). Fixed at all THREE sites via one shared `LeaderboardRanking.fullerPair` (take the side with the
  greater denominator WHOLE — the rule the display-side `effectiveStanding` already used): `SuperfanCounts.merged`,
  `PredictLeaderboardService.upsertScore`, `ProgressSnapshot.merge` (trivia lifetime). Denominator stays
  monotonic → reinstall-safety preserved; momentum stays `max` (standalone, not a ratio partner).
- **Predict double-submit = lock, NOT lineup upload.** A 2nd device reads its own
  `predict_submission_marks` (an own-row SELECT policy — the ONE narrow exception to that table's sealed
  design; marks carry no picks) and locks an already-predicted fixture (`.submittedElsewhere`). The
  pre-deadline no-upload rule STANDS — we never upload the XI, so the 2nd device can't show the picks
  until the match grades. Uploading lineups for full cross-device view was rejected: it reintroduces the
  per-user-per-round storage growth the design deliberately avoids (efficiency-is-the-target).
- **KHG/Trivia cross-device play = FULL review (owner's Option 2).** The played-set + score + exact
  per-question picks are DERIVED from the `quiz_answers` the server already stores (`selected_index` is
  there) — no new table, same bounded own-row read either way, so Option 2 costs nothing extra on the
  stress tests. A 2nd device shows a played round as played + the identical review, and can't replay.
- **Username staleness.** A foreground `hydrateProfile()` propagates a rename across devices without a
  cold relaunch. (Usernames were already one-per-Apple-ID, server-authoritative, globally unique.)
All new reads are own-row, index-served, bounded — pass 1k with 100k headroom. Family Sharing gives each
person (incl. under-13 child accounts) their own Apple ID, so per-account dedup never cross-blocks
siblings. Mechanism: `docs/data-sync.md`; the four commits on `feature/multi-device-integrity`.

### Notifications are OPT-IN — no dark patterns
Nothing auto-enables at onboarding/launch; the user turns on exactly what they want. The single nuance: an
EXPLICIT match-alert bell tap IS the opt-in, so it cascades the full default bundle the FIRST time
(`applyMatchAlertDefaultsIfFirstTime`) — a complete feature makes the best first impression, and a
bell-on-nothing-fires state is a banned silent-success. NEVER auto-enable a notification without an explicit
user action. Full model: `docs/notifications.md` §1.

### Know Her Game — each player featured once per season, no repeats (a PRINTED contract)
The no-repeats rule is printed in-app (`KnowHerLandingView`), so it's a promise; the enforcing KV ledger IS
the feature, not bookkeeping to adjust for a "better" outcome. **Why:** KHG is a season-long curriculum —
no-repeats is the ENGINE that moves it past the stars to the squad players the back half exists to surface.
**Rejected 2026-07-27:** reclaiming 32 already-featured players because their content was regenerated with a
better model — a player who PLAYED an edition experienced it; deleting the artifact doesn't undo that. The
ONLY legitimate reclaim is a same-`weekKey` content correction. Full reasoning: `docs/know-her-game.md` +
`.claude/rules/fan-zone.md` gate #7.

### Know Her Game verify gate — WEEKEND/MONDAY split + Lever 1, NOT hold-the-whole-run (owner 2026-08-12)
The verify gate (generate→verify→publish, so the publisher isn't the writer) was split across the week:
HUMAN questions **generate + verify on the WEEKEND** (human-only, tiered re-search — heavy on fun facts, light
source-check on career), and **stats inject + the pool publishes MONDAY** (fresh ESPN, so Sunday-night games
count). **Why:** the owner needs a weekend correction window (a future office schedule leaves no Monday-morning
window before the 10am nudge), and stat questions are season-cumulative so they must be Monday-fresh. **This
SUPERSEDES the 2026-08-11 "if any player can't reach 8 confirmed human questions, HOLD THE WHOLE RUN" rule** —
holding let the (device-local, fixed) Monday nudge fire on stale content. Replaced by **Lever 1**: a short
player is topped to the 10-floor with deterministic ESPN stats (cap 5) rather than held; only a <5-human player
holds, and that surfaces at the weekend verify-stage where it's fixable. **Do NOT "restore" hold-the-whole-run**
— it was reversed on purpose. Full design + reasoning: `docs/know-her-game.md §5c`.

### The proxy pass-through has ONE allowed body mutation — attendance enrichment (owner 2026-08-11)
The ESPN pass-through's contract is bytes-unchanged (app decoders never see proxy-authored JSON). The single
exception: the `/summary` enrich hook may fill `gameInfo.attendance` when it is 0/absent on a SETTLED match,
with a league-verified figure from the attendance-backstop ledger (`src/attendance.ts`; sources: late ESPN
ingest or NWSL's own matchfacts feed). Nothing else in any body may ever be touched. **Why the exception:**
ESPN's attendance ingestion went spotty for weeks in Aug 2026 and the figure is display-final data with no
app-side interpretation — the alternative (a separate endpoint + app merge) would strand every shipped build.
**Why it stays narrow:** casual payload editing would silently break the defensive-decode assumptions every
app decoder makes; do not use this as precedent — a second mutation needs its own owner ruling. Mechanism +
the six-source research: `docs/backend.md` (Attendance backstop).

### Contrast floor — readable text is primary/secondary ONLY; tertiary/quaternary are decoration (owner 2026-08-11)
Dark-mode gray-on-gray text shipped below WCAG AA — invisible dark-on-dark (the weather footer at 1.5–2.3:1
was the caught exemplar; ~230 sites across Fan Zone/Profile/Match Detail). **Ruling:** readable text uses
`dsFgPrimary` or `dsFgSecondary` ONLY; `dsFgTertiary`/`dsFgQuaternary` are DECORATION-ONLY (they fail AA as
text) and hierarchy below primary is expressed by WEIGHT/SIZE, not a darker gray. `dsFgSecondary` was
lightened #8E8E93 → #AEAEB2 (AA-clean on every surface). Every readable fg×bg must clear WCAG AA 4.5:1
(3:1 large/bold); `DSColorContrastTests` enforces it (the color peer of the 12pt font floor). Same exemptions
as the font floor (dividers, dots, disabled, TBD/VS placeholders, icons beside a label). **Why it's locked:**
a future session (or a Design handoff) will want to re-dim text to a "prettier" darker gray for aesthetics —
that's exactly the regression; the floor test catches it, and this entry says don't. Full rule: CLAUDE.md UI
rules; the recurring-mistake lesson: `feedback_invisible_dark_on_dark_text` memory.

### Efficiency is the TARGET, not the floor; judge load at the MACRO level (owner 2026-08-11)
Two standing design rules, the positive twin of the BANNED LENS. **(1)** Build the most efficient feasible
implementation, then verify 1k — not "it passes 1k, ship it." If a capped/metered resource can be AVOIDED
(edge cache vs. KV writes; cache-once-serve-many vs. a per-user rate-limited API hit; a computed value vs. a
stored row), avoid it from day one. Free-tier headroom is preserved for growth, never spent because it's
currently available; the aim is staying free to the highest user count physically possible. Passing 1k is
necessary, not sufficient. **(2)** Judge new load against the COMBINED draw on each shared budget (Cloudflare
requests, KV writes/day, Supabase) and the headroom left for future features — never a feature's own
service cap in isolation. **Why:** the model kept reading "1k passes with headroom" as license to build the
naive/wasteful version. Worked example: the game-time weather forecast — edge cache not KV, 8h TTL matched to
model-update cadence → user-count-independent, never a paid tier. Full method: `docs/stress-testing.md` §3a.

### THE BANNED LENS — never size from CURRENT usage
Every load/reliability/scaling question is asked **as if the app ships tomorrow** (hundreds of one-club fans
from one subreddit post), never "only N users today → plenty of headroom / defer to launch." **Why:** that
lens produced the APNs 50-device near-miss and two wrong calls on 2026-07-16. Defer only when the 1k stress
test PASSES or the lever is a flip-anytime config. Full method: `docs/stress-testing.md` §0.

### Privacy / monetization — VALUES are promises, MECHANICS stay flexible
VALUES (promises, never walk back): no ads, no data sold, no third-party/cross-app tracking, no dark patterns.
MECHANICS (stay flexible): say "free, tip-supported," never vow "free forever"/"no paywalls ever"; anonymous
FIRST-PARTY aggregate usage/diagnostics counters ARE allowed (App Store label target: Data Not Linked to
You). Don't write absolutist product vows into public copy; don't read the old "no tracking" line as banning
anonymous counters. Owner, 2026-07-16.

### Recurring-AI-mistake directives (the call keeps drifting — hold it)
These are design/product calls a future session keeps unconsciously violating; hold them unless the owner
reopens them explicitly:
- **Crests are PROMINENT — render LARGE, never shrunk toward an icon/spec size.** The crest is the team's
  identity and outranks the abbreviation/name. AI keeps shrinking them; err larger (à la The Athletic).
- **Tab navigation = The Athletic model.** Each tab keeps its OWN nav stack across switches; do NOT reset on
  every tab tap (ESPN's model, owner-rejected). `.id()` on a TabView child desyncs selection from content
  (tried, reverted — don't re-try it).
- **Online-only — no demo/seed/fake data in the running app.** Every surface shows live data or an honest
  "Couldn't load — tap to retry." Never propose a demo/placeholder mode.

### CONCACAF is core league content — always in the Schedule overview; the toggle is RETIRED (owner 2026-08-18)
A CONCACAF W Champions Cup match involving any of the 16 NWSL clubs is **core schedule content, shown in the
Schedule overview (the "All" chip) for EVERY user regardless of who they follow** — a Thorns fan sees Bay FC's
CONCACAF final. It is NOT opt-in: the old `isConcacafFollowed` toggle (onboarding + Competitions) was
**retired** and the feed is now fetched unconditionally alongside the NWSL spine. **Boundary:** only matches
with an NWSL club splice in (the fetch filters to the 16 by abbreviation) — a Liga-MX-vs-Liga-MX scouting tie
stays out ("for that level of CONCACAF coverage there are other apps"). **National teams stay per-follow**
(personal, opt-in) — they appear in the overview too, but only the ones you follow; that asymmetry is
intentional (clubs = the league, always shown; NTs = who fans are, opt-in). **Rationale:** the brand is
everything about your 16 teams — a club in a continental match is a *product of* NWSL (owner's Anthropic→Claude
analogy); NWSL's own site treating CONCACAF as separate (no note that Spirit reached the March final) is the
mistake being corrected. Do NOT re-add the toggle or re-gate the fetch. My teams still narrows clubs to your
follows. The default chip was renamed **"NWSL" → "All"** (adjustable — a taste, not a locked ruling).

---

## PROVISIONALLY DONE / owner-iterating (do not "fix," revert, or re-litigate)

### Superfan v1.0 economy + experience (2026-08-05)
The 20+5 economy (`SuperfanScoring`/`SuperfanMomentum`, all-tunable code constants) and the rebuilt
`SuperfanDetailView` shipped as a deliberate FIRST CUT. The owner is playing with the Superfan card over the
following weeks and will tune what needs tuning. **This is a recognized, protected state — NOT a partial-credit
violation.** Do not "correct" the economy, revert the rebuild, or re-litigate the tier math; if something
looks off, surface it as an observation, don't unilaterally change it. Deliberately deferred (not bugs):
offseason-freeze for momentum, extra "noticed-you" spotlight counters, the stale-Trivia self-heal. Design law:
`feedback_superfan_points_philosophy`.

### Fan Zone = long-horizon iteration (standing)
Designing the games takes many revisions. The rhythm is **change → TestFlight → live for weeks → adjust**;
favor small reversible passes over sweeping rewrites. A game surface that the owner said "consider done for
now, I'll revisit" is intentionally parked, not incomplete. Owner, 2026-07-27 (`project_fan_zone_elevate`).

---

*Add an entry when the owner settles a ruling that AI is likely to reopen, or marks something provisionally
done. Keep entries short — link the full reasoning in a doc/memory rather than re-dumping it. Never delete an
entry to "resolve" it; if a ruling genuinely changes, edit it in place with the new decision + date and keep
the history of what it replaced.*
