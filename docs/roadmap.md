# Roadmap / What's Next

> ### ✅ DONE + DEPLOYED 2026-07-30 — WATCHER: "suspended" is not full time
> **Fixed and deployed** (`isUnfinishedPost` → `Match.unfinishedPost`, consulted at all three sites;
> 87 watcher tests + `test/suspension.test.ts`). The Live Activity path RETURNS EARLY on a suspension
> rather than broadcasting — the content state derives its phase from `state`, so an update would render
> a full-time card mid-match, and the teardown can't be undone. Fail-open polarity throughout: only
> positive evidence of non-completion counts, so a payload missing `completed` behaves exactly as before.
> ⚠️ NOT done (deliberate, owner call): un-marking `ended` when a fixture is seen `in` again. With the
> cause fixed, the 6h discovery sweep already covers recovery, and un-ending on `post→in` risks a
> duplicate full-time push on ESPN's frequent status flapping. Revisit only if a fixture is ever wrongly
> ended by some other route. **The original diagnosis is kept below — it's the reference for the failure
> mode, and the fabricated-kickoff variant in the next item is still unguarded.**
>
> #### Original diagnosis (2026-07-29)
> ESPN reports a suspended/abandoned match as **`state == "post"` with `completed == false` and
> `name == "STATUS_SUSPENDED"`.** The app now guards this (`Event.isFinalResult`, `SuspendedMatchTests`);
> **the watcher does not**, and it trusts bare `post` at THREE sites. Real consequences, all observed on
> UTA v WAS (wind hold at 27', resumed ~70 min later):
> - **`fixtures.ts:105,:126` marks the fixture `ended` → `isActive` (`:82`) drops it → POLLING STOPS.**
>   ⚠️ The worst one, and the least obvious. It was MASKED for 2½h because BAY v GFC was live on the same
>   ESPN feed (one scoreboard response covers every NWSL match, so the Spirit match kept being diffed as a
>   side effect — that's why the resumed-half goal + halftime pushes fired). When BAY finished at 00:10
>   the feed went quiet, and the Spirit's real full time at ~00:27 was **never observed** — KV proved it:
>   `match:401853954` still read `state:"in"`, fixture `ended:true`. **No full-time push was ever sent.**
>   Visibility depends on the schedule, which is the worst property a bug can have.
> - **`events.ts` FT detection** (`prev.state==="in" && state==="post"`) → fires a FALSE full-time push.
> - **`index.ts` ~:781 Live Activity teardown** → `broadcastEnd` + `deleteChannel` + KV deletes. IRREVERSIBLE:
>   push-to-start is gated on `ko >= now`, so an already-kicked-off match can never restart its Activity.
>   The guard must sit BEFORE the delete and bias toward "not ended" when signals conflict.
>
> Fix = the same `isFinalResult` concept at all three. Belt: **un-mark `ended` if a supposedly-ended
> fixture is ever seen `in` again** (see the backwards-transition rule below). Needs a deploy.

> ### 🕐 LIVE STATE — trust the SEQUENCE, never a single snapshot (three variants, one lesson)
> Live match state has broken three times, each a different mechanism, each from trusting ONE field:
> | Variant | ESPN says | Reality | Status |
> |---|---|---|---|
> | **Stale cache** (2026-07-11) | old-but-valid | clock stuck all game; read `pre` 47min after KO | ✅ fixed build 26 (windowed query + upstream cache-bust) |
> | **Suspension** (2026-07-29) | `state=post` | in progress | ✅ app fixed; ⛈️ watcher open (above) |
> | **Fabricated kickoff** (Orlando, ~2026-07-10) | `state=in` at 1' | **never kicked off** | ❌ **NO GUARD EXISTS** |
>
> **Fabricated kickoff:** a pre-KO lightning delay; ESPN auto-starts after ~30 min regardless and shows a
> STATIC placeholder minute. `TickAnchor` keeps the anchor when the clock doesn't advance (correct for
> stoppage, where ESPN freezes at 2700) — so a permanently static feed clock produced a **climbing display
> that reached 120'**. Self-healed only when ESPN keyed in a corrected start time.
> - ⚠️ **Do NOT tighten on status NAMES.** Verified 2026-07-29: a legitimate kickoff arrived as
>   `STATUS_IN_PROGRESS` (not `STATUS_FIRST_HALF`), and ESPN flapped between the two ~8× in one match.
>   Name-matching would MISS real kickoffs.
> - ✅ **Tighten on behaviour instead:** require the feed clock to have been OBSERVED ADVANCING before
>   ticking locally; until then render ESPN's string verbatim and diag if it never advances. Generalises
>   the `freshAtCap` rule already in `TickAnchor` ("first sighting at the cap is UNKNOWABLE — don't
>   fabricate"). Costs ~1 poll cycle; immune to labels and placeholders.
> - ✅ **Backwards transitions are proof the PRIOR state was wrong** — `post→in` (suspension recovery) and
>   `in→pre` (fake kickoff correction) are both impossible in a real match. Cheapest in the watcher, which
>   already persists `prev`.

> ### 🪪 DISPLAY NAMES ARE NOT UNIQUE — decide BEFORE launch (owner 2026-07-29)
> **Today anyone can take a name someone else already has.** `profiles.display_name` is a plain `text`
> column with **no unique constraint** (`supabase/schema.sql:34`), `DisplayNameRules` only trims and
> checks 2–20 characters, and **nothing anywhere queries whether a name is taken** — not on first
> choice, not on rename. Every board row carries a denormalized copy of the name, and nothing joins by it.
>
> **⚠️ It already happens.** Audited 2026-07-29 across the 2026 Predict boards: of 108 distinct names,
> **10 are held by more than one account** — "devontouchline" and "skyoffside" by THREE each. Those are
> seeded fans and purge before launch, but the demonstration stands: a *random name generator* collided
> ten times in ~120 accounts. Real users deliberately choosing desirable names will collide far more.
>
> **Why it matters beyond tidiness.** Club boards are small (a few hundred), so a collision is visible
> and confusing rather than lost in a crowd. Your own row is accent-highlighted, so YOU can find
> yourself — but the board is ambiguous to everyone else, and it directly undermines the recognition
> the Fan Zone is chasing ("why is nwslnoob always two spots above me?" only works if a name is a
> stable identity). It also leaves impersonation wide open: nothing stops a user picking a real
> player's name, or yours.
>
> **⚠️ THE TIMING IS THE WHOLE POINT.** Adding uniqueness before launch costs one index + one lookup.
> Adding it after means forcing existing users to rename — the kind of change that reads as the app
> taking something away. This is a pre-launch decision, not a someday one.
>
> **Recommended: case-insensitive GLOBAL uniqueness, first-come-first-served.**
> - `create unique index on public.profiles (lower(display_name))` — case-insensitive, so "Tiffany" and
>   "tiffany" can't coexist. ⚠️ Check for existing duplicates first; the index creation fails if any
>   remain (the seed purge clears today's).
> - An availability check in `DisplayNameEntry` before submit, plus honest "that name's taken" copy.
> - ⚠️ The UI check is ADVISORY ONLY — two people can submit the same name in the same instant. The
>   unique index is the real guard, so `AuthStore.updateDisplayName` must catch the `23505` unique
>   violation and surface it, not swallow it (NO SILENT FAILURES: a rename that appears to work and
>   didn't is exactly the banned shape).
> - Renaming must free the old name — it does automatically with a single-column index.
> - Load: one indexed lookup per name entry. Passes 1k/100k by construction; no new load path worth a
>   stress-test entry.
>
> **Considered:** per-club uniqueness (messy — users follow several clubs); a Discord-style `#1234`
> discriminator (kills collisions but also kills recognition, which is the thing the names are FOR);
> leaving it and relying on the you-row highlight (fails for everyone reading the board except you).
>
> **Separate but adjacent, worth deciding at the same time:** a reserved/blocked-name list. Nothing
> currently stops impersonating an NWSL player, a club, or the app itself.

> ### 📏 PHONE-SIZED, NOT PREVIEW-SIZED — community bars + small type (owner, 2026-07-28)
> Caught reviewing Predict's fan-picks bars: they shipped as a **4pt-tall bar in a fixed 70pt slot
> with an 11pt fixed-size percentage**. That reads fine in a design tool on a desktop and is squinty
> in a hand. Fixed for Predict (10pt bar, flexible width, `.dsFont` percentages that scale with
> Dynamic Type).
>
> **✅ KNOW HER GAME + NWSL TRIVIA — DONE 2026-07-29.** `CommunityResultsView` went further than a
> resize: options now STACK (full label on its own line, bar beneath), which killed the truncation AND
> roughly doubled the bar width since it no longer competes with a label column. Same pass added the
> "your pick" marking and cut two duplicate header lines. Both community games share the component, so
> Trivia got it for free as expected.
>
> **The general lesson worth keeping:** an 11pt font and a 4pt bar are a *tool* default, not a
> phone-reading size. When sizing anything a user has to read or compare at arm's length, size it
> for the device — and prefer `.dsFont` over `.font(.system(size:))` so Dynamic Type can rescue it.
>
> **✅ DONE 2026-07-28 — the DATA-BAR sweep.** Every bar the reader is meant to COMPARE is now 10pt
> (7pt in the compact Fan Zone carousel card, where a full-size bar would dominate): Predict's
> fan-picks + locked-XI bars, `CommunityResultsView` (fixes Know Her Game AND NWSL Trivia in one —
> was 60×6 with an 11pt fixed percentage while the LABEL took all the flexible width), Match Detail's
> `StatComparisonBar`, both Superfan bars, the Bracket leaderboard's accuracy bar and its
> picks-made progress. Bars in Predict + the community panel are now `Grid`-aligned so they share a
> common left edge — ragged edges make lengths incomparable, which is the entire job of a bar.
> Deliberately NOT touched: status dots (5–7pt live/bullet indicators), tab underlines (2pt), and the
> `ThumbnailContentCard` team-colour stripe (3pt) — none are data the reader compares.
>
> **⚠️ STILL OPEN — the broader TYPE audit.** 151 uses of `.dsFont(10/10.5/11)` remain app-wide.
> **26 are the deliberate tracked-caps eyebrow motif** (`trackedCaps(size: 11)` — small caps with
> tracking read larger than their point size, and it's a consistent DS motif) and should stay. The
> other ~125 are mostly legitimately-secondary captions, but some are certainly too small. That is a
> screen-by-screen judgement pass across ~40 files, not a find-and-replace — doing it blind would
> risk breaking layouts that were tuned around the current sizes. Worth its own session with the
> AX1-cap revisit in the accessibility workstream.

> ### 🎬 PREDICT STAGE 1 — results at LINEUP DROP (deferred by owner decision 2026-07-28)
> The redesigned results screen ships against FULL TIME only. The handoff also specified a two-stage
> timeline: 75 of the 88 points (players, positions, formation, perfect XI) resolve when the real
> lineup drops ~90 minutes before kickoff, and only the last 13 (exact score, result) wait for full
> time. Opening the screen at lineup drop is the moment the game is *named* for.
>
> Deferred as one pass, not dropped — the current build is structured so it drops in:
> - Per-pick detail is already derived TRANSIENTLY (`PredictResultDerivation`), not persisted, so a
>   pre-full-time render needs no new storage.
> - `PredictionScore` is untouched and still only written at full time.
>
> ⚠️ **THE TRAP TO RESPECT WHEN BUILDING IT.** A partial score must NEVER reach
> `PredictionStore.recordScore`: that increments `scoredMatchCount`, which is the denominator of
> `avg_points`, which is what the season board ranks on. Writing a stage-1 score would silently
> corrupt every user's rank. Stage 1 must be display-only, computed in the VM.
>
> Still to decide (both were open in the handoff):
> - **What triggers it.** Fetch-on-open is simplest and matches the existing on-demand `/summary`
>   pattern; anything more eager costs Cloudflare requests, the metered resource. ⚠️ Whatever fetches
>   inside the pre-kickoff window MUST send `w=near` (the cache-key window bucket), or a stale empty
>   pre-lineup shell can mask a posted XI. The current results fetch deliberately does NOT send it —
>   it only ever reads a finished match, where `w=near` would just cost cache hits.
> - **Whether to push at lineup drop.** The moment with the most pull; the app has matchday push
>   limits to respect, and it would need its own opt-in.
> - `PredictionScore`'s four Bools can't express "pending" (false is indistinguishable from unresolved),
>   so the pending rows need a separate transient type.

> ### 🐞 THE BRACKET — "top 94%" reads as praise and means near-last (found 2026-07-28)
> `resultsRankLine` computes `topPercent = rank / total * 100`, so rank 30 of 32 renders
> **"You're in the top 94%"** in the accent colour, as if it were an achievement. Three problems:
> the wording is inverted (Overwatch never said "top 94%" — it said *Bronze*), and the `max(1, …)`
> guard only protects the good end.
>
> ⚠️ **Four call sites, not one** — fix together or the inconsistency spreads:
> `BracketBattleView.swift:411`, `:527`, `:699`, and `BracketLeaderboardView.swift:163`.
>
> Predict adopted the replacement on 2026-07-28: state the POPULATION ("#8 of 20") and, where a
> neighbouring row is actually in hand, the next rung ("0.4 behind CapitalKick at #7"). Found while
> building that; out of scope for the Predict handoff, logged here rather than silently widened.

> ### 🔐 MULTI-DEVICE INTEGRITY (owner 2026-07-27; diagnosed further 2026-07-29)
> Trigger: the owner runs the app in THREE places under the same Apple ID — TestFlight, an Xcode USB
> build, and the Simulator — each with its own LOCAL stores but all syncing to one server row. She
> reports that after signing into the sim, her phone's Superfan total **doubled** (e.g. 30 → 60) on the
> next refresh. This matters far beyond the sim: it's the same shape as a user getting a new phone.
>
> **✅ FIXED 2026-07-29 (#195, reaches testers in build 31) — the duplicate rows were a RENDER bug, not two accounts.**
> The 2026-07-27 entry concluded "two rows = two distinct `user_id`s". **That was wrong.** Direct query
> of `prediction_scores` (WAS/2026, display_name=Tiffany) returns **exactly ONE row**, while the sim
> renders **two** (confirmed via the accessibility tree, 2026-07-29). One row, drawn twice.
>
> Root cause — `PredictXIViewModel.swift:475`:
> ```swift
> let myID = auth.userID?.uuidString              // Swift UUID → UPPERCASE
> let rivals = standings.filter { $0.userID != myID }   // Postgres uuid → lowercase
> ```
> The compare can never match, so the user's own server row is never removed from `rivals` — and then
> her live "You" row is spliced in beside it. `BracketService.swift:178` already guards exactly this
> (`myUserID?.uuidString.lowercased()`, commented "never double the user"); Predict is the only board
> that forgot. **Fixed by lowercasing both sides**, matching Bracket. Verified in-sim: two rows before,
> one after.
>
> ⚠️ **The seed `--purge` does NOT fix this** (owner asked, 2026-07-29). Purge deletes
> `@seed.nwslapp.test` accounts and cascades their rows; there is no second account here to delete. It
> would remove the seeded rivals and leave both "Tiffany" rows exactly as they are.
>
> **⚠️ STILL OPEN — correlated pairs are max-merged INDEPENDENTLY.** `prediction_scores` maxes `points`
> and `matches` as separate scalars, and `SuperfanCounts.merged` maxes each game's `correct` and `total`
> separately. Device A at 100 pts / 5 matches and device B at 80 / 6 merge to 100 / 6 → avg 16.7, a
> number **neither device produced**. Fix: merge each pair ATOMICALLY — take the side with more progress
> (the greater denominator) whole, never a numerator from one and a denominator from the other.
>
> **⚠️ STILL OPEN + UNREPRODUCED — the Superfan doubling itself.** Ruled out so far: `max()` cannot sum;
> Trivia's restore deliberately skips the season accuracy pair (`TriviaStore.swift:233-239`, guarding the
> earlier "0/10 shows 100%" bug); KHG's baseline is excluded from the accuracy numerator; the Home card
> and Game Center both max-merge. The owner's current row is internally CONSISTENT
> (6/11 + 15/126 + 8/10 + 10/10 → 62 ✓), so nothing is doubled right now. **The mechanism is not yet
> found — do not "fix" it by guessing.** Owner will reproduce deliberately (delete account → play on
> phone → sign into sim → refresh phone). The decisive evidence is the `superfan_scores` row captured
> IMMEDIATELY BEFORE and AFTER the sim signs in — that pins which field moves:
> `select * from superfan_scores where user_id = '<id>' and season = '2026';`
>
> **Also worth deciding:** whether display names should be unique per season.

> ### 🧪 SIM IDENTITY ISOLATION — stop the simulator writing to the owner's real data (owner 2026-07-27)
> Signing the simulator in with the owner's Apple ID makes it write to her real Superfan / Predict rows.
> **The mechanism to avoid this already exists and is wired correctly** — it has just never been switched
> on. `-signInAsTestFan <n>` (DEBUG-only, `AuthStore.debugSignInAsTestFan`) signs in as a seeded Fan Zone
> account instead. Verified 2026-07-27:
> - address format matches exactly on both sides (`seed+%04d@seed.nwslapp.test`)
> - every gate keys on `auth.isSignedIn` (= `currentUser != nil`), which the path sets — so Fan Zone entry,
>   Tier-2 alert toggles, NT bells and Profile all unlock
> - the Fan Zone gate additionally needs `hasChosenName`; the seeder writes
>   `profiles.display_name` + `name_is_custom = true`, so a seeded fan arrives already named
>
> **The one prerequisite: enable the Supabase Email provider with signups DISABLED** (so the only
> email/password accounts that can exist are the admin-created seed ones). Then:
> `xcrun simctl launch <SIM> com.tiffanyrieth.nwslapp.NWSLApp -signInAsTestFan 1`
>
> ⚠️ Push DELIVERY still can't be tested in a simulator at all (hardware, not auth) — device + the
> watcher's `/test-push` with `sandbox:true` remains the only real path. And this is the cheap 80% fix for
> Fan Zone contamination only; the broader 3-install cross-talk still wants a test Apple ID + `.debug`
> bundle id (see the signOut/global-scope finding).

> ### 🩹 SMALL PREDICT FOLLOW-UPS (from the reset-button incident, 2026-07-27)
> **✅ CONFIRMED IN THE WILD 2026-07-29.** The owner hit that button on TestFlight (build 29, which
> predates its removal in #188) to see what it did — and it wiped her local Predict history exactly as
> described, leaving the server's `prediction_scores` intact. That is why her season card read
> "Predict Washington's XI to join the board" all through the 2026-07-28/29 session while the
> leaderboard directly beneath it ranked her 3rd at 54.0 avg. **Build 30 is the first TestFlight build
> without the button.** The underlying follow-up below still stands: the season card reads LOCAL-only
> state, so any future local wipe (or a fresh device) reproduces the same contradiction.
> - **The season card reads LOCAL-only state** (`store.points(forTeam:)` / `scoredMatchCount`) even though
>   `prediction_scores` holds the authoritative numbers. So a local wipe makes the card say "Predict …'s XI
>   to join the board" while the leaderboard directly below still ranks the user. Reading the server row
>   would make the card honest and self-healing. (This also means `docs/fan-zone.md` §3's local-vs-server
>   table is right about *storage* but doesn't flag that a local-only READ can contradict the server.)
> - **Account delete does not clear local Predict state.** `PredictionStore.reset()` now has no caller;
>   `AuthStore.deleteAccount` tears down the session and identity but leaves predictions/scores in
>   UserDefaults on the device. Probably wants wiring up — a deleted account shouldn't leave game history
>   behind locally.

> ### 🛡️ ESPN ROSTER RELIABILITY — reduce the single-source risk (owner 2026-07-27; RESEARCHED + reframed 2026-07-30)
>
> **⭐ 2026-07-30 REFRAME — TWO ERROR CLASSES, and they need DIFFERENT tools. Read before designing.**
> - **LAGGING FACT** — the value WAS true, reality moved, nobody keyed it in. **Bounded** (one transfer's
>   worth) and self-correcting. Croix Bethune wore 7 her whole career, moved to KC where 7 was taken, took
>   8; the official feed still says 7. Understandable and finite.
> - **FABRICATION** — the value was NEVER true. **Unbounded.** ACFC → 1 player · Orlando ceasing to exist ·
>   Rodman FWD→MID (nothing stops GK next week) · players who don't exist (Bethi, Ngock on the Spirit) ·
>   **Spirit showing 5 goalkeepers last month, correctly 3 now.**
>   Owner's frame: a rename you haven't heard yet is a lagging fact; deciding to call someone "Cats" is
>   fabrication. ESPN tracks a million sports, mostly men's, and has no incentive to fix NWSL data.
>
> **⇒ INVARIANTS catch FABRICATION (one payload, pure logic, unit-testable, NO second source needed):**
> unique shirt number per squad (this caught Bethune — SDP listed TWO #7s) · **position-group counts**
> (5 keepers implausible, 0 impossible, 15 defenders impossible) · plausible squad size · a player on
> exactly one club. **CROSS-SOURCING catches STALENESS** — a lagging value is internally consistent, so
> only a second opinion reveals it. **Build the invariants FIRST**: cheaper, and it's the half where ESPN
> actually hurts.
>
> **⚠️ "The official feed always wins" is WRONG — jersey correctness goes BOTH ways** (verified live):
> | Case | ESPN | NWSL SDP | Right | Detectable how |
> |---|---|---|---|---|
> | Rodman position | Midfielder ❌ | Forward ✅ | SDP | cross-check |
> | Bethune jersey | #8 ✅ | #7 ❌ | **ESPN** | invariant (duplicate #7) |
> | Sentnor jersey | *missing* ❌ | #21 ✅ | **SDP** | missing value |
> | Bethi/Ngock membership | present ❌ | absent ✅ | SDP | cross-check |
>
> **Correction policy:** auto-correct ONLY on a missing value or a violated invariant. When both sources
> are self-consistent but disagree, **emit a diag and change nothing** — adjudicate via an overrides KV
> (which the planned admin portal would front). Never guess.
>
> **Source research (all verified by direct fetch 2026-07-29, not schema-reading):** NWSL's own public
> keyless Opta-backed API `https://api-sdp.nwslsoccer.com/v1/nwsl/football` — already used by the proxy in
> `src/headshots.ts`, whose weekly normalized-name SDP↔ESPN join (~98%) is a ready-made id bridge.
> `/seasons/{s}/stats/players?teamId=` returns a full squad in one page with `bibNumber` + `roleLabel`.
> **HAS:** correct squads · 171 season stats vs ESPN's 106 (xG, big chances, progressive carries, duels) ·
> tactical formation coords · standings `form`/`movement`/`qualification` · assists · paired subs · 2013+.
> **DOES NOT HAVE (checked, not assumed):** heat maps / average positions (**0 of 78 players populated**) ·
> distance/sprint/speed (all `0`) · per-match team box score · play-by-play · `/transfers` (returns `[]`) ·
> national teams + Concacaf W (in the catalog but **WAFCON `/matches` → HTTP 500**; licence is NWSL-scoped,
> so **ESPN stays for NT permanently**). xG is season-per-player only — NOT per match, so the natural
> home (home-vs-away comparison bars) is unreachable.
> **Live games: settled — do NOT migrate.** Latency is a wash (every event within one 30s cycle, no
> systematic winner across 3 kickoffs / 4 goals / HT / FT / suspension). SDP models state better in one
> place (`FINISHED` vs `SUSPENDED` where ESPN overloads `post`) and worse in another (`phase` went
> `PRE_MATCH` for a match at 27'), and degraded harder on the abnormal match (closed it ~10–15 min late).
>
> **Legal posture:** both ToS forbid automated access; Disney's says "whether or not for profit", so
> non-commercial is not a carve-out either way. Switching does NOT improve the position — owner has
> assessed and accepted this. Only asymmetry: NWSL's terms contemplate written permission, so *asking* is
> possible there and never with Disney.

> ESPN is the app's most vulnerable dependency. For a solo indie app that's an accepted trade — but the
> **roster** specifically has been flaky enough to warrant a better guard. Not aiming for perfect; aiming
> for *better than one unverified source*.
>
> **The failure mode is WRONG-BUT-PLAUSIBLE DATA, served confidently, then self-healing** — not outages.
> Three observed cases:
> - **ACFC roster collapsed to 1 player for ~a week** after a KC Current transfer; self-healed at the next
>   match. Bandaid shipped: `/roster` keeps a last-known-good KV copy and serves it with a
>   `proxyCachedAsOf` marker when live looks implausibly small.
> - **Orlando silently dropped from KHG edition 2026-W31** (`knowherTodoEmpty`, 06:02:44Z) — ESPN returned
>   an empty/stat-less roster for ~seconds. The assembler is fail-open, so it logged a GAP and shipped a
>   15-team pool. Pride fans opened the game to nothing.
> - **Trinity Rodman listed as MIDFIELDER instead of FORWARD for ~3 weeks**; self-healed 2026-07-27
>   (owner-confirmed in-app; all ESPN surfaces — site roster, athlete endpoint, proxy `/roster`, and the KV
>   last-known-good — now agree on Forward).
>
> **The gap:** every existing bandaid catches *missing* or *implausibly small* data. Nothing catches data
> that is wrong but well-formed — a flipped position passes every plausibility check we have, which is why
> it survived three weeks.
>
> **Scope (owner):** ESPN is FINE for minutes, stats, fixtures, scores. The problem is **roster identity** —
> who is on the squad, their position, their number.
>
> ### ✅ SHIPPED 2026-07-30 (proxy #63) — the two live bug fixes
> - **`fetchRosterResilient`** — the bracket engine + Know Her Game read ESPN RAW with no fallback.
>   Live-proven the same day: ESPN served **Portland as 1 athlete** and `/knowher/eligible?team=POR`
>   returned **0**, so an edition generated that day ships 15 teams (exactly the W31 Orlando failure).
>   Both paths now fall back to `/roster`'s `roster:{id}` last-known-good. Verified live: POR 0 → 17.
> - **Continuity guard** — a plausibly-sized payload may only REPLACE the last-known-good copy if it
>   still shares ≥50% of its players. Before this, a contaminated-but-plausible roster overwrote the
>   good copy on the first request: the fallback destroyed itself at the exact moment it was needed.
> - **KHG club-completeness gate** — a published edition must cover all 16 clubs. Both validators
>   checked for DUPLICATE clubs and never for MISSING ones, which is why W31 shipped short and silent.
> - **Paging** on `rosterContinuityRefused` + `knowherTodoEmpty` (the latter fired for real at W31 and
>   reached nobody).
>
> ### ✅ SHIPPED 2026-07-31 — nightly verification + owner overrides + one admin portal
> Design settled by the 16-club sweep (**`docs/roster-source-research.md` §10 — read it first**):
> ESPN stays the membership base, SDP verifies and never replaces. Guards run at BUILD time (nightly
> `0 8 * * *`), never at serve time. Mechanism + the two join traps: **`docs/backend.md`** roster §.
> - **Observe-mode verifier** (`src/roster-truth.ts`), gates A–D. Changes NOTHING users see.
> - **Owner overrides**, 90-day TTL, applied in `/roster`. Can only correct position/jersey on a
>   player ESPN already lists — never adds or removes, so a stale pin can't hide a real player.
> - **`GET /admin`** — one URL, one password, three tabs. Bracket + KHG are iframed (both work; one
>   drives a live game), so the shell is additive and reversible.
>
> **⚠️ First-run lesson, worth keeping:** run one flagged **66** players as "missing from ESPN" —
> mostly false. Two join bugs, both found by reproducing against live data: a player collided with
> HERSELF when two of her own name forms normalized alike, and one person spelled differently on each
> side was counted twice (as an addition AND an erasure). Now 8 paired variances + 29 erasures (22 =
> Portland's real collapse) + 4 real signings. **This is the case for observe-mode-before-serving:**
> wired to `/roster`, run one would have been noise rather than a bug report.
>
> ### 🕐 NEXT — tweak 2: serve from the verified snapshot
> Overrides already reach users; the SNAPSHOT does not. Decide after ~a week of nightly reports shows
> what normal drift looks like, then set enforcement thresholds from measurements instead of judgement.
> **Still open, and only the owner can close them:** ESPN has erased real players league-wide (Fuller,
> Heaps — a USWNT captain — Spaanstra) and carries **12 position mismatches**; none are size-detectable.
> The verifier now SURFACES them nightly; each still needs a ruling in the portal to reach users.

> ### 📊 TEAM-PAGE STATS BURST — ~27 direct ESPN calls per team-page open (found 2026-07-30, DEFERRED by owner)
> `TeamDetailViewModel.load` fans out **one ESPN Core-API call per athlete, in parallel, from the
> device** — bypassing the proxy entirely (no edge cache, no last-known-good, no cross-user dedupe;
> `AthleteStatsCache` is session-scoped so a relaunch refetches everything).
> ⚠️ **The trigger is opening a TEAM page, not tapping a player** — the team-leaders board needs every
> squad member's stat line, so the ordinary "who's wearing #7" gameday glance pays the whole burst.
> **This rules out app-side lazy-loading as a fix.**
> At 1k users: ~21.6k direct ESPN calls/day. Realistic failure = per-device burst throttling → a stats
> card with players silently missing rows. **Fix = a bundled `/team-stats?team={id}` proxy route**
> (27 requests → 1, edge-cached, shared) built on Queues (450 calls > the 50-subrequest budget).
> Owner deferred 2026-07-30: rosters are the correctness problem, this is a scaling one. Full sizing in
> **`docs/stress-testing.md` §6**.

> ### 🎮 FAN ZONE — a long-horizon iteration loop, NOT a one-session build (owner 2026-07-27)
> Four mini-games plus a Superfan point economy tying them together. The owner's framing, worth holding
> onto: **designing games is far harder than it looks and takes many revisions and trial-and-error.** The
> 2026-07-24 competitive redesign was a big improvement, but a few things still don't feel right — the
> target is that it feels **instantly big and connected**, and getting there is a matter of several more
> passes, not one more change.
>
> **Expected working rhythm:** change → TestFlight → live with it for a few weeks → adjust from real use →
> TestFlight again → repeat. Over months.
>
> **How to work on this (for future sessions):** don't treat a Fan Zone ask as a single-session build, and
> don't propose sweeping rewrites between passes — small, reversible tweaks that can be felt in real use
> beat big swings. Expect the owner to sit with a change before judging it. Instrument what's cheap to
> measure, but weight her lived impression above metrics at this scale. Read `docs/fan-zone.md` and
> `.claude/rules/fan-zone.md` (LOGIC GATE, incl. invariant #7) before touching any of it.

> ### 🎚️ STILL OPEN — halve Predict per-match scoring (flag only; verified NOT yet applied 2026-07-27)
> ⚠️ Not to be confused with the **Superfan 0–100 accuracy economy**, which WAS redesigned 2026-07-24 —
> this is a different knob and is still untouched (`XIPrediction.swift` today: formation 5, exact score 10,
> result 3, perfect XI 15 → max 88).
> The Predict-the-XI per-match max is **88** (+3/starter ×11, +2/position ×11, +5 formation, +10 exact
> score, +3 result, +15 perfect XI). The owner flagged this as oversized for a low-scoring sport — consider
> **halving every value → max 44** pre-launch (relative weights unchanged, so rankings don't move). The
> Batch-3 switch to an **average-per-match** leaderboard (users never see cumulative totals) made this
> non-urgent. `+5 formation` is the specific worry (near-free for attentive fans — most clubs run a stable
> shape). **No code change yet** — this is a deliberate pre-launch decision. Values live in
> `Models/XIPrediction.swift` (`PredictionScore.*Points`); if halved, the `predictPointRow` rules text +
> the season card's `/88` ring denominator + `RECENT_RESULTS` breakdown must move to `/44` in lockstep.


> ### ✅ DONE 2026-07-24 — Predict average-leaderboard migration (Batch 3)
> APPLIED by the owner (confirmed 2026-07-27). `supabase/migration_predict_avg_leaderboard.sql` (idempotent,
> additive: `prediction_scores` gains `matches` + `avg_points` + an index). Until it's applied, the Predict
> SEASON board's rivals degrade to empty (honest — the season CARD, recent results, and round board all use
> other data and keep working); after it's applied + a client sync, the board ranks by average per match.
> The seeder (`nwslapp-proxy/scripts/seed_test_fans.mjs`) now writes the two columns, so `--purge` +
> re-seed makes the seeded average board realistic for the visual pass.

> ### ✅ DONE 2026-07-24 — Fan Zone v3 migrations
> ALL FOUR APPLIED by the owner, and the proxy deploy is done (confirmed 2026-07-27). For the record:
> `migration_fanzone_progress.sql` (game-progress restore), `migration_predict_round_scores.sql`
> (Predict round boards), `migration_bracket_final_rank.sql` (final ranks + the bracket_votes
> service_role DELETE grant), `migration_retention_cron.sql` (pg_cron prunes; needs the pg_cron
> extension toggle on the free tier — Database → Extensions if the CREATE EXTENSION errs).
> Plus one proxy deploy (`wrangler deploy` in ~/Projects/nwslapp-proxy — quiz-results reveal rule +
> bracket rank stamping ride together).

> ### 🎡 NWSL Trivia — content pipeline ONLY (structure SHIPPED 2026-07-23)
> The biweekly-round STRUCTURE (rounds, landing page, retention, community model) is built — the app
> already treats Trivia as biweekly 10-Q rounds alternating with KHG. What remains is CONTENT: the
> annual ~530-question generation (tuned prompt + evergreen/season-bound tagging + difficulty
> stratification per `docs/nwsl-trivia-weekly-redesign.md` content rules) and its Claude-Routine
> loader. Until then the current stocked pool serves rounds with a deterministic slice (repeats
> after ~4 rounds — acceptable interim, owner-approved).

> ### 🏆 The Bracket → offseason-first, semi-automatic (decision LOCKED; the one code change is NOT done)
> **Decision (locked, owner):** stop running The Bracket year-round on a fixed cadence. Make it primarily
> an **offseason** feature, with maybe **1–2 editions during the season**. You stock a library of themes;
> the engine only advances rounds. ("Tentpole" just meant *the anchor feature that carries the offseason* —
> the thing that gives people a reason to open the app when the other three games are quiet.)
>
> ⚠️ **Verified 2026-07-27: the one required code change is still OUTSTANDING.** `handleAuto` in
> `bracket-engine.ts` still calls `generateNext()` once `break_days` elapses, i.e. auto still STARTS
> editions by itself. Until that becomes advance-only, the locked decision isn't actually in force.
>
> **Why — the content-calendar gap.** In season the Fan Zone is already full: KHG and Trivia alternate
> biweekly (a new round every Monday, each playable for two weeks) and Predict the XI runs any week
> with fixtures. That's plenty. But **both KHG and Predict are in-season ONLY** — KHG's featured
> players are picked from season stats, and Predict needs a fixture inside its 28-day window (it hides
> in a true offseason). So the offseason falls back to **Trivia alone**. Bracket is the natural filler:
> it's the one game that needs no live fixtures, no season stats, and no new editorial content per
> round — the engine generates it from the league pool. Offseason is exactly when the app most needs a
> reason to open, and when Bracket has the least competition for attention.
>
> **The model (owner, 2026-07-23) — "semi-automatic":** the operator curates a LIBRARY of themes (jot
> ideas down during the season, drop 3–4 in when the offseason arrives); **auto mode's only job is to
> advance rounds when the timer runs down.** Editions are STARTED by hand from the library, not
> generated on a break timer. Run it ~3–4 times a year, ~3 weeks each.
>
> **⚠️ Most of this already exists — don't rebuild it.** `bracket_creative_editions` /
> `bracket_stats_editions` ARE the library: per-theme `status` (`ready` | `parked` | `used`) + a
> `season` column that gates no-repeats, plus `used_themes_this_season` in `bracket_config` which
> `generateNext` skips against. The admin portal already has Add creative theme, Edit title,
> Park / Set ready, Delete, **Start specific**, Start next (rotation), and Clear used themes.
>
> **So the actual remaining work is a REDUCTION, not a build:**
> - **Stop auto from auto-STARTING editions.** `handleAuto` currently generates a new edition once
>   `break_days` elapses with none active. The wanted behaviour is advance-only: tally + advance while
>   an edition is live, then STOP when it completes and wait for the operator. That also removes the
>   need for any "is it the offseason?" signal — the operator's start IS the signal, which is far
>   cheaper than teaching `FanZoneCadence` an offseason concept it doesn't have.
> - **Re-pick the pacing** for a 3-week offseason edition (today `early_round_days=2`,
>   `late_round_days=3`, `break_days=10` → ~3–4 weeks + a ~10-day break); `break_days` becomes
>   irrelevant once editions are operator-started.
> - **Admin-portal controls** adjusted to match (the start/advance emphasis, less mode-toggling).
> - **💡 Fan-submitted theme ideas** (owner's "maybe have a way for people to recommend things") — a
>   genuinely new piece, and a nice ALIVE/community hook: suggestions land in the library as `parked`
>   for the operator to promote to `ready`. Needs a moderation path before it ships.
>
> **Already fixed (2026-07-23), don't re-diagnose:** the admin portal's AUTO/MANUAL switch wrote only
> the global `bracket_config` key while each edition carries its OWN `mode`, so switching an in-flight
> edition to AUTO silently did nothing (`handleAuto` skips a manual-mode edition). `setMode` now
> carries the mode onto the active edition and stamps `round_opened_at`/`round_closes_at` so the
> countdown starts. The ROUND SCHEDULE itself was never broken and is unit-tested (`bracket.spec.ts`).

> ### ✅ DONE — analytics + alerting go-live (owner-confirmed 2026-07-27)
> All arms are LIVE: analytics migration, Resend error-spike email, healthchecks.io dead-cron watchdog,
> and UptimeRobot route monitors.
>
> ⚠️ **Scope gap worth knowing (verified 2026-07-27): the email pager does NOT cover APP CRASHES.**
> `checkErrorSpike` scans **only** `sdiag:` (proxy server-origin diagnostics) and deliberately skips the
> client `/telemetry` stream, because that endpoint is unauthenticated and spoofable — counting it would
> let anyone trip the alert. So an iOS crash (e.g. the Predict picker crash) can never page; Apple's own
> "report this crash" prompt is currently the only signal. This is by design, NOT a threshold being tuned
> too low. The one deliberate softening is narrow: `apiFailure` events whose detail starts with
> `image fetch ` are excluded from the PAGING count (expired IG/YouTube thumbnail URLs — the false alarm
> you remember); they still land in telemetry and the in-app Diagnostics screen. Thresholds are ≥8 error
> events in 15 min, max one email per hour. For app-crash visibility the cheap path is Apple's own App
> Store Connect / TestFlight crash notifications + Xcode Organizer, not building a second pager.
>
> Historical setup steps, all now complete:
> 1. ✅ **Supabase migration — DONE (2026-07-22):** `supabase/migration_analytics_counters.sql` applied,
>    so counters now record. (No more `analyticsRpcFail: increment_counters 404` in /telemetry/recent.)
> 2. **Resend** (error-spike email): create a free account at resend.com → API key →
>    `wrangler secret put RESEND_API_KEY` + `wrangler secret put ALERT_EMAIL` (your address) in
>    ~/Projects/nwslapp-proxy. Threshold ≥8 error events/15min, max 1 email/hour.
> 3. **healthchecks.io** (dead-cron watchdog): free account → new check, period 2 min / grace
>    3 min → copy the ping URL → `wrangler secret put HEALTHCHECK_URL` in
>    ~/Projects/nwslapp-match-watcher. If the watcher cron ever stops, THEY email you.
> 4. **UptimeRobot** (route uptime): free account → HTTP monitors on the proxy `/config` and the
>    watcher `/` root. No code involved.

> ### 📋 PRE-PUBLISH — privacy package (needed BEFORE App Store submission; target mid-Aug)
> Lower priority than ALIVE work but MUST exist at submission (owner 2026-07-16 — track it here so
> it isn't lost):
> - **App Store privacy label** (filled in App Store Connect): Data Linked to You = Contact Info
>   (Sign in with Apple email/account). Data Not Linked to You = Diagnostics + Usage Data (the
>   anonymous telemetry + counters). Data Used to Track You = **None** (no ATT prompt).
> - **Privacy policy page** (Apple requires a URL at submission): write from the 2026-07-16
>   honest-language work — values as promises (no ads; no data sold; no third-party/cross-app
>   tracking), what IS collected (account basics; anonymous aggregate diagnostics/usage, never
>   linked), retention, delete-account. Host it (GitHub Pages is $0) + paste the URL in ASC.
> - README/showcase copy already reframed to match (PR #152); CLAUDE.md carries the
>   values-vs-mechanics stance so future copy stays consistent.

> ### ♿ PRE-RELEASE GATE — accessibility (owner 2026-07-21; must ship BEFORE launch)
> Accessibility is a release gate, not a nice-to-have — in an inclusive space like NWSL it must not be
> overlooked. NOT yet built; this is a scoped workstream to audit + complete before launch. Two parts:
> - **Blind / low-vision (VoiceOver + Dynamic Type):** systematic pass. Custom-DRAWN elements need
>   explicit `.accessibilityLabel` (formation-pitch dots, `StatComparisonBar`, score header, live clock,
>   image-only crests/headshots); GROUP compound units so a match card reads as one element ("Chicago 0,
>   Angel City 2, Full Time") not fragments; revisit the Dynamic Type **AX1 cap** per-screen (density vs
>   larger AX sizes — trade-off).
> - **Color-blind:** never rely on color ALONE — redundant encoding (letter/shape/icon) + respond to
>   `@Environment(\.accessibilityDifferentiateWithoutColor)`, usually better than a custom mode.
>
> #### ✅ Dynamic Type / AX1 — SETTLED 2026-07-29 (the cap question above is now ANSWERED)
> **The cap STAYS at AX1** (owner decision, after testing MLS / NWSL / MLB / Reddit / Swift Alert on
> device). Consequences, and the standing rule:
> - **AX1 is the largest size the app promises, so it must lose NO data.** AX2–AX5 all resolve to AX1
>   (verified: the maximum system setting renders pixel-identically), so AX1 IS the worst case — there's
>   nothing above it to test.
> - **Don't lift the cap.** At AX5 body text is 53pt on a 402pt screen ≈ 7 characters per line; no
>   layout survives it, which is why every app that permits it breaks (MLB shatters; MLS's club pages
>   overlap; Swift Alert breaks too). A predictable cap is a more honest contract than an uncapped
>   layout that collapses. Users who need >AX1 are served by **VoiceOver + iOS Zoom**, which work
>   regardless of the cap — that's where the remaining effort belongs, not here.
> - **The bar** is *same layout, same information, nothing hidden, nothing overlapping* — NOT "looks
>   identical" (bigger text legitimately means fewer cards per screen).
> - **Severity ladder:** **overlap = always broken** > truncating a value available nowhere else = bug >
>   truncation where the full value is one tap away (a fixed-size carousel card) = fine, leave it.
> - ⚠️ **A fixed-HEIGHT container must CLAMP its text** (`lineLimit`), or the text escapes its bounds
>   and collides — that's exactly how the MLS roster cards break. Clamped truncation is the SAFE
>   failure mode; unclamped overlap is not.
> - ⚠️ **MEASURE before redesigning.** Standings was assumed to need a graduated fix from ~xLarge up;
>   stepping through every size showed it clean across the ENTIRE standard range (xSmall…xxxLarge) and
>   broken only at AX1 — which shrank the work to one threshold. The reflex to redesign for "large text"
>   generally overshoots.
> - **Swept 2026-07-29** (five tabs, both quiz results panels, Bracket, Teams, Schedule, Social,
>   Superfan, Match Detail): PASS everywhere after fixing Superfan tier blurbs, Bracket edition titles,
>   Standings, and the Match Detail tiles + kickoff date. Colour-blind pass (deuter/protan/tritan
>   simulation, `cvd.py` method) found **no failures** — existing rules carry it: ✓/✗ glyph shapes, the
>   crest+abbreviation naming rule, "your pick"/"YOUR PICK" text labels, positional bars. Thinnest
>   margin = Standings form chips (W and L are the same colour under deuteranopia; only the W/L/D
>   letters distinguish them, so never swap those letters for coloured dots).
> - NOT done, deliberately: the Teams grid's uneven tile borders when club names wrap (cosmetic).
> Current state = PARTIAL, not zero (FormBadge shows W/D/L letter+color = color-blind safe; text uses
> `.dsFont`/@ScaledMetric; scattered labels exist) → the work is systematic completion + an audit, then a
> punch-list. First step when picked up: run the audit (read + VoiceOver in sim). Detail in the
> accessibility-pre-release-gate memory. (Dark-only is NOT an a11y issue — the app's color balances it.)
> Also still pending here: profanity-filter the editable leaderboard display name before public launch.

> ### ✅ SHIPPED + PROVEN — Know Her Game weekly automation (built 2026-07-13, proven through 2026-07-27)
> The full no-human weekly loop is BUILT (proxy branch `feature/knowher-weekly-automation`): deterministic
> prompt assembly (`assemble_knowher_prompt.mjs` fills the Rodman-faithful `knowher-weekly-TEMPLATE.md`
> from `/knowher/todo`, which now serves age/country + keeper stats), a dedicated-key
> **`POST /knowher/ingest`** (validate → KV → markFeatured, diag on every outcome), a `knowherStaleWeek`
> serving watchdog (in-season, 1/day), and the committed cloud-routine runbook
> (`knowher-weekly-routine.md`). Proxy DEPLOYED + prod-probed; `node --test` 14/14. The scheduled Claude
> Routine runs Mon 06:00 UTC (2am ET) on **Opus 4.6** — GitHub connected, four editions published
> (W27/W29/W30/W31). Monday user nudge = the existing local 10 AM notification (unchanged).
> ⚠️ **Three durable gotchas learned 2026-07-27 — see `docs/know-her-game.md` before touching this:**
> the routine's MODEL lives in the trigger's `job_config`, which the claude.ai UI does NOT write (set it
> via the RemoteTrigger API or every run silently reverts); `scripts/load_knowher.mjs` bypasses the
> featured ledger and is now guarded; and a one-second ESPN blip can silently drop a club from an edition
> (the assembler is fail-open — it logs a GAP and ships short). Engine question CLOSED (owner): the Rodman-WORKING prompt is final;
> `knowher-generation-prompt.md` (untested self-audit variant) deleted. Detail: `docs/know-her-game.md` §5d.

> ### 🧹 CLEANUP — remove the DEBUG postseason simulator's baked-in 2025 data (owner-parked)
> **Kept ON PURPOSE (owner, 2026-07-07):** `PostseasonSimulator.swift` carries real 2025 bracket +
> clinch data so the owner can exercise the Playoffs feature in-sim over the next few days before the
> real Nov postseason. It is 100% `#if DEBUG` + launch-arg-gated (`-simulatePostseason2025…`) → compiles
> out of Release/TestFlight and shows NOTHING in normal builds (scheme flag is off), so it is harmless to
> ship as-is. **When the owner says they're satisfied:** strip the fake 2025 seeding data from
> `PostseasonSimulator.swift` (or delete the sim harness) so no hard-coded 2025 bracket lingers in the
> app source. The unit tests that reference `PostseasonSimulator.clinchTable` (`PlayoffClinchTests`) move
> to inline fixtures at that point. Nothing auto-reminds — this note is the reminder.

> ### 🧹 PRE-LAUNCH GATE — purge the Fan Zone seed test population (owner 2026-07-23)
> The pre-launch seeder (`nwslapp-proxy/scripts/seed_test_fans.mjs`) creates real `@seed.nwslapp.test`
> `auth.users` so the crowd-shaped surfaces (leaderboards, community splits, Superfan ladder) can be
> designed against before there are real players. **Retention does NOT clean these up** — the cron only
> prunes `quiz_answers` (>35d) and `predict_round_scores` (>28d); the record book it writes
> (`prediction_scores`, `superfan_scores`, `profiles`) is kept FOREVER by design, and the `auth.users`
> rows never expire. So the seed fans would rank on real leaderboards and count in real aggregates
> permanently until explicitly torn down. **Before launch:**
> - `node scripts/seed_test_fans.mjs --purge` — deletes the `@seed.nwslapp.test` accounts; `on delete
>   cascade` sweeps all six seeded tables clean.
> - Then run the **REVOKE block** at the bottom of `supabase/migration_seed_grants.sql` — returns the
>   service_role key to exactly the reach it had before seeding.
> Enforced, not remembered: `health_check_seed_accounts.mjs` FAILS the `npm run healthcheck` chain while
> any seed account exists — that gate is why seeding against the prod project is safe at all.

> ### ✅ SHIPPED — Fan Zone v2 (2026-07-22, merged to main)
> The Fan Zone v2 batch is DONE + on main (detail in git + `.claude/rules/fan-zone.md`):
> - **Superfan Zone:** the trailing "Superfan" carousel card is now TAPPABLE → `SuperfanDetailView`, a
>   cross-game season stats hub (season total, competitive tier + percentile, per-game breakdown, "Your
>   best moments"). New backing: `superfan_scores` Supabase table + `SuperfanService`/`SuperfanStats`;
>   season-scoped, passes the 1k stress gate. ✅ **`migration_superfan_scores.sql` applied.**
> - **Know Her Game → BIWEEKLY + landing page:** KHG now alternates the Fan Zone quiz slot with NWSL
>   Trivia (Week 1 = KHG), editions numbered "Round N"; the old `KnowHerPickerView` is now the richer
>   `KnowHerLandingView` (This round · Last round · How players are chosen + "all caught up" state).
> - **NWSL Trivia FACELIFT:** the play screens were rebuilt onto the Know Her Game community-family
>   pattern (intro, progress dots, tap-to-answer, shared `ScoreRing` + `CommunityResultsView`). ⚠️ That
>   pass was PLAY-SCREENS ONLY and left the front door diverged — **superseded 2026-07-23** by the full
>   round rebuild (`TriviaLandingView` + `TriviaRoundView`, biweekly rounds), which closed the remaining
>   community-family drift. Only the question-generation pipeline is still parked (see Pending, below).
> - **Team-color vibrancy (Predict + Player Detail):** new shared `TeamWashBackground`
>   (`Components/TeamColorWash.swift`) on the Predict fixture/result + "Predictors" leaderboard cards,
>   `MatchCard` migrated onto it; "Playing as" now a consistent below-nav strip across all games.

> ### ✅ CLOSED 2026-07-13/16 (kept as one-liners; detail in git/memories)
> - **Live-clock / staleness / Match-Detail (build 26):** DEVICE-VERIFIED 2026-07-13 — count-up past
>   60', stoppage `45+7`/`90+6`, HT/FT, no pan; two display-only wording follow-ups remain (Match
>   Detail live-label form + V2 HT dedupe — see the wording-followups memory/session notes).
> - **Lineup-crest wrong-team:** resolved + device-verified 2026-07-10 (crest only on GOAL/RED CARD).
> - **Follows restore:** closed 2026-07-13 (owner) — restore-on-reinstall behaving across real uses.
> - **Polling efficiency (2026-07-16):** watcher fixture-window + app confederation scoping + 60s
>   in-app cadence + push-triggered refresh — merged (app #152/#153, watcher #27) + deployed; watch
>   the Cloudflare graph fall from ~23-28k/day as the visible proof. `docs/national-teams.md`.
> - **Involuntary sign-out fix (2026-07-16):** merged (app #152). On-device check on the next
>   TestFlight: exact toggles restore on re-sign-in; Notifications rows read OFF signed-out.
> **TEMP instrumentation stays on purpose:** the `Diagnostics.debugTrace` case + the reconcile trace in
> `FollowSyncCoordinator` remain in the code until this test passes — then remove them (Step C) and mark
> this done.

Pending work only (ALIVE > core > hardening); shipped work lives in git history + the File Map.
- **The Bracket v2 — built, awaiting owner deploy:** run the 4 SQL files (`migration_bracket_v2`
  → `migration_bracket_qualifying` → `seed_bracket_stats_editions` → `seed_bracket_creative_editions`)
  + `npm run deploy` (proxy) + the first-launch flow (`Reference/Bracket Battle/first-launch-checklist.md`).
  Optional later: more stat/creative themes; full bracket-TREE graphic.
- **First-launch perf** — Tier 1+2 shipped; onboarding quick-tips screen DEFERRED (build only if wanted).
- **YouTube Shorts thumbnail pillarbox** — DEFERRED; fix is proxy-side.
- **Pull-to-refresh polish** — keep the list visible during refresh (spinner only on first load).
- **Home follow-ups:** spotlight no-repeat-per-season + opt-in weekly notif.
- **Player headshots Phase B2 banners** — DEFERRED (licensing).
- **Accessibility** — now a PRE-RELEASE GATE (see the ♿ callout above): VoiceOver + color-blind pass before launch.
- **NWSL Trivia — question-generation pipeline (PARKED; STRUCTURE SHIPPED 2026-07-23)** — the biweekly
  ROUND model, landing page, retention and cadence are all built and live; the app already asks for
  "round N's 10 questions" and doesn't care where they come from. What remains is CONTENT ONLY: the
  annual ~530-question generation (tuned prompt, evergreen vs season-bound tagging, per-round difficulty
  stratification, fact-check pass) + its loader/routine. Until it lands the stocked 41-question pool
  serves rounds with a deterministic slice — 4 unique rounds, then it repeats (accepted interim).
  📄 The design doc is on the parked branch: `git show docs/nwsl-trivia-weekly-redesign:docs/nwsl-trivia-weekly-redesign.md`.
  ⚠️ Read it for the CONTENT rules only (530-pool → 53 slots, evergreen tagging, difficulty mix,
  annual regen). Its UI/cadence half is SUPERSEDED — it says "weekly / not yet built"; the app shipped
  BIWEEKLY rounds + the landing page on 2026-07-23. Current truth: `docs/fan-zone.md`.
  (community family), but the engine rebuild (`docs/nwsl-trivia-weekly-redesign.md`: weekly cadence,
  10 questions/wk, 530-pool → 53 weeks, annual regen, stat-questions-in-code) is the next Fan Zone build.
- **More team-color vibrancy (owner interested 2026-07-21)** — Predict cards + schedule `MatchCard` +
  player detail now carry the wash (via `TeamWashBackground` / `accentHex`, shipped in Fan Zone v2). STILL
  pending: extend it to more surfaces so club color carries further (candidate surfaces: Home header, Team
  detail, Standings followed-team rows, the Squad grid). Keeps the neutral-canvas philosophy — color comes
  from the TEAMS, not the chrome; the crest/abbreviation identity rules still hold. Design pass, scope
  per-surface with the owner (don't recolor chrome globally). Reference: MatchDetail header wash.

**Hardening (after ALIVE work):**
- `Fixtures/scoreboard.json` + decode-only test for `Scoreboard`/Event helpers (date parsing, `dayKey` TZ).
- `MatchStore.matches(for:)` joins club↔game by `abbreviation` (no ESPN id) — a rename silently empties a schedule. Fix: a normalized id map.
- Team social links — verify a few subreddit handles (KC `r/KCCurrent`; CHI `r/redstars` vs `r/ChicagoStars`).
- **Club-page links data pass** — Website · Shop · Tickets (OFFICIAL) + Discord (Fan) → `SocialPlatform` + `TeamSocialLinksProvider`, per-club.

**Longer-term:**
- **Push — Tier 2 (SERVER push) — SHIPPED** (Stage A–D done: watcher cron + KV diff + APNs JWT, per-team
  targeting, `APNS_HOST=production`, lineups-posted, red-card/VAR; NT alerts by FIFA code). Delivery now
  rides **Cloudflare Queues (V1) + APNs Broadcast Channels (V2)** — `docs/push-fanout-scaling.md`. Still
  open on the CLUB-competition axis: **Champions Cup / Challenge Cup (`usa.nwsl.cup`) push** — the watcher
  polls the NWSL + NT scoreboards but not these club-comp slugs; needs their slugs + a competition-aware
  card footer/title (carry the comp label through the pipeline). (The old "self-hosted crest primary is
  dead" item is RESOLVED — that was CF error 1042 from fetching the proxy over its public URL; `card.ts`
  now uses the PROXY service binding, so self-hosted `/crest` is the working primary, ESPN the fallback.)
- **Competitions follow-ups:** Challenge Cup (`usa.nwsl.cup`, single annual match) + Champions Cup + followed NTs fold into Schedule "My teams" (NT coverage now 16 feeds, shipped). WWC/Olympics whole-tournament UI DEFERRED; foreign-club color DB grows as Champions Cup opponents appear (`DesignTeamColors.international`).
- **Feed** — user-added sources; richer filtering. **Weather** — kickoff-temp header slot.
