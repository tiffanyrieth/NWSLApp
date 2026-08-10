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
