# Know Her Game — merged implementation plan

> Merges the Design→Code handoff (`design_handoff_fanzone_home/HANDOFF-know-her-game.md`,
> `Player Spotlight Game.html` 5-frame mockup, `…/Player Spotlight Game - Design Notes.md`) with the
> Owner↔Claude discussion memo. **Legend:** 🔒 locked (handoff, confirmed) · ✅ resolved in discussion
> (supersedes a handoff "open") · ⚠️ correction (handoff assumption vs. verified code reality) · ⏳ open.

## Context — why

Rework the passive **Player Spotlight** (AI-written article) into **Know Her Game**, a weekly
interactive "how well do you know this player?" quiz inside Fan Zone. Same soul — get to know a
player — but scored, and feeding Superfan. This is a FANDOM feature (Olympics-style get-to-know-her
emotional bond), not a stats quiz; stats support the bond, they aren't the substance.

## 1. Concept & placement 🔒

- Weekly quiz in the **Fan Zone row**. Name **"Know Her Game"** — locked.
- When it ships, the standalone Player Spotlight Home section **retires**. Home becomes:
  **Fan Zone row → Club News → Coming Up** (3 modules).
- ⚠️ "Keep the data pipeline, only presentation changes" is only partly true — see §5/§6.

## 2. Core rules 🔒 (+ discussion refinements ✅)

- **Per followed team:** one player/team/week; never a team you don't follow.
- **1 team → skip picker → intro (Frame 2). 2+ → picker (Frame 4).**
- **Points 1:1** (1/correct; max = question count) → same unified **Superfan** total as Predict/
  Bracket/Trivia.
- **Cadence:** weekly, new player Monday, available Mon–Sun.
- **One attempt, no partial saves** (quitting mid-game discards; restart from Q1) — same as Trivia.
- **Question count: ~10 total (owner 2026-07-02 — NYT model, REDUCED from 10–25).** ~8 stat/career/
  identity (code-generated from ESPN — free, unambiguous, safe) + **1–2 genuinely-good fun facts** that
  clear guardrail + sourcing. If a player has zero clean fun facts, 10 stat/career is fine. This
  **removes the "force-find fun facts" pressure** that caused low-effort filler. "Engaging" also includes
  cool career MILESTONES (first 2000s-born USWNT cap, an Iron-Woman consecutive-starts record, an
  almost-quit origin story), not only personal quirks. Points = 1/correct.

## 3. Multi-team card on Home — ✅ RESOLVED (was the handoff's deferred item)

Single **cluster launcher card** in the Fan Zone row (152pt, amber):
- **1 team** → single big-face card (Frame 1 look: player photo + name + team abbr + "Play now ›") →
  straight to intro.
- **2+ teams** → **cluster of all followed players' headshots** (team-color rings) + "your players" +
  progress ("1 of 3 played") → tap opens picker (Frame 4). No team favored at a single glance.
- Overflow → first N faces + "+N". Done (all played) → dimmed "✓ Done this week".
- **Rejected:** dedicated shelf (pushes Club News down; owner objected) and full abstraction (kills the
  face). Cluster is the only option satisfying equal-representation + faces + one compact card.

## 4. Player selection — roster-learning — ✅ RESOLVED + ⚠️ CORRECTION

⚠️ **Do NOT reuse the existing selection.** Today the proxy picks from each team's *most recent
matchday squad* + a weekly hash → over-features regular starters, no coverage guarantee. It's a "who
played last weekend" pick, not "learn the roster." Must be rewritten.

Rewrite (proxy-side, no UI impact):
- **Eligible pool** = players who **started ≥1 match this season** AND **not yet featured this season**.
  (No separate "≥10 questions" gate — 10 is always reachable via stat backfill, see §2.)
- ✅ **Season-only:** runs during the active NWSL season; in the offseason the game + its card **hide**
  (like Predict with no fixtures) — too much roster churn + tuned-out fans to serve roster-learning then.
- **Once per season, hard** (removed from pool after featuring).
- **Season-tail / static-XI fallback:** when unfeatured starters run out, expand to **highest-minutes
  not-yet-featured** players (pulls in supersubs before the ~30-min fringe). Never repeat.
- **Ordering:** core-starters-first (a season = a learning curriculum), weekly-deterministic, fair
  (NOT A–Z — that permanently buries late-alphabet clubs). Reuse the week-of-year seed idea.
- Coverage/once-per-season needs a little **KV state per team+season**.
- ✅ **ESPN data verified live:** the season-stats endpoint `general` category returns `starts`,
  `minutes`, `appearances` per athlete in one call. `starts >= 1` is the gate; `minutes` is the
  fallback tier. Pure subs (0 starts) and unplayed players (404 "No stats found") auto-exclude.
  `fetchAthleteSeasonStats` already hits this endpoint — add `starts`+`minutes` (~2-line parse change).

## 5. Content pipeline — ⚠️ CORRECTION (handoff overstates reuse; this is the critical path)

Handoff says "reuse, don't rebuild — same sourcing + fact-check, just reshape prose → Q&A." Verified
reality in the proxy: the existing pipeline does **curated source allow-lists + single-pass Haiku
*relevance* gating + a stats-based blurb**. It does **NOT** extract personal facts from the web, and
has **no corroboration / confidence pass**.
- **Reusable:** the stats feed; the Haiku-batch + KV-cache + forced-JSON-schema scaffolding; the
  "control-the-input-facts" structural guardrail; the curated source-quality philosophy.
- **NEW (must build — the real lift):**
  1. **Acquire** candidate personal facts from curated reliable sources (NWSL.com, The Athletic via
     Bluesky, Wikipedia, People, Girls Soccer Network, etc.).
  2. **Corroborate** — keep a fact only if multiple reliable sources agree (the owner's trust bar;
     mirrors the Social-tab source-quality philosophy but adds a genuinely new multi-source pass).
  3. **Generate Q&A** (stats + facts, MC/T-F) with the five-layer guardrail (§6) in the prompt.
- **Real-data-only:** a "fun fact" must trace to a verified public source. **Prototype this first on
  one player** before any app-side work — it's where the effort and the reputational risk live.
- ⚠️ **COST CORRECTION (2026-07-02) — Sonnet + web_search is NOT viable.** A live prototype cost **~$2
  per player** and wiped a $5 credit in ~2 runs. Cause: the **`web_search` tool injects full page
  content into context**, re-read across an 18-search agentic loop → hundreds of thousands of input
  tokens, on Sonnet. At 16/week ≈ ~$130/mo. **Do NOT use the web_search tool for this pipeline.**
- ✅ **COST-VIABLE pipeline (replaces Sonnet+web_search) — separate cheap ACQUISITION from cheap
  GENERATION, exactly like the existing news/spotlight Haiku pipelines (which cost cents/day):**
  - **Acquire (no LLM, no web_search):** free fetches only — the player's **Wikipedia extract**
    (MediaWiki REST API, no key; a free source from the content playbook) for bio/personality + the
    **ESPN season stats already fetched** for stat facts. Bounded input (~a few k tokens).
  - **Stat/identity questions = code templates (ZERO LLM):** position/number/apps/goals/debut straight
    from ESPN data. Free. This is what makes the 10-floor stat-backfill free.
  - **Fun-fact questions = ONE small Haiku call** fed only the bounded Wikipedia text + the five-layer
    guardrail. **Haiku 4.5** = the tier the existing pipelines already run at cents/day. Corroboration
    = curated pre-vetted sources (Wikipedia is cited) + an optional tiny 2nd Haiku pass over the SAME
    provided text (no web search). A fact that can't be supported by the provided text is dropped.
  - **Generate ONCE per featured player, cache for the season** (each featured once); optionally via the
    **Batch API (50% off)**. Est. cost: ~a fraction of a cent to ~2¢/player one-time — back in range.
  - **Spend guard:** set a low monthly cap in the Anthropic console; never re-enable web_search here.
- **Trade-off (reverses the earlier "broad search + Sonnet" pick on cost grounds):** fun facts are
  limited to Wikipedia/curated sources — usually fine for notable players; thin players lean stat-heavy
  (the accepted 10-floor). Still fully automated (no human approval), unless owner opts into Batch+review.

## 5b. Acquisition/generation — options explored (2026-07-02, after the web_search cost blowup)

Researched to avoid API cost. Ranked:
1. ⭐ **Claude Routine on the OWNER'S SUBSCRIPTION (recommended, $0 marginal).** Claude Code *Routines*
   (claude.ai/code/routines) run on Anthropic cloud and **draw down your Max/Pro subscription quota —
   NOT the pay-per-token API** ("Routines draw down subscription usage the same way interactive sessions
   do"). Can web-search + WebFetch, run shell/git, `curl` — **headless, no permission prompts**, weekly
   cron (min 1h interval, daily run cap). One weekly routine: pick the week's eligible players → generate
   guardrailed Q&A from reputable sources → POST to a Worker ingest endpoint (→ KV). Within ToS for a
   personal app (migrate to API/Managed-Agents if it becomes a company). CAVEATS: (a) keep it LEAN —
   bounded Wikipedia + 1–2 searches/player, NOT 18 open searches (same balloon that cost $2/player on the
   API would eat the daily subscription cap; lean ~16/wk fits, esp. on Max); (b) monitor silent failures
   (run history/webhooks); (c) secrets in the routine env, not `.env`.
2. **Gemini free tier (~$0).** Gemini 2.5 Flash/Flash-Lite: free input+output tokens + **Google Search
   grounding free ≤500 req/day**. Best open-web breadth for fun facts at $0. Caveats: competitor/second
   dependency; free-tier inputs train Google (fine — public facts only); build+maintain a Gemini client.
3. **Wikipedia + ESPN → Haiku, in-stack (~cents).** Cheapest KNOWN in-stack path (§5). Fun facts limited
   to Wikipedia.
4. **Brave free search (covers our volume) → few snippets → Haiku (~cents).** Middle path — some open-web
   breadth, you control token volume (dodges the web_search balloon).
5. **Apify / residential-proxy scrapers ("A" service).** ACQUISITION-only (scrape bot-blocked sources like
   IG), bills per run. Defer unless a needed source blocks bots.
6. **Batch API (Haiku, 50% off) / manual seed + organic growth.** Control/fallback levers.

**ADOPTED (2026-07-02): Claude REMOTE Routine on the owner's subscription** (Method 1 — remote, cloud,
NOT local Auto Mode which needs the machine awake). $0, fully automated, stays in Claude. **Gemini free
API** = fallback. Owner-validated via independent research.
- **Division of work:** *I build* — the tight guardrailed generation PROMPT, a secret-gated Worker
  **`/ingest` endpoint → KV**, and the app/proxy pieces. *Owner sets up* — the Remote Routine in her
  Claude account (claude.ai/code/routines), pastes the prompt, points its output at `/ingest`.
- **Cost discipline lives in the prompt** (the whole reason for the redesign): **≤~3 searches/player**,
  ≥2-source corroboration, "skip failed fetches & continue" — so each run stays within the subscription
  daily cap. NOT open-ended search.
- Five-layer guardrail (§6) goes in the prompt verbatim. Output = the §8/schema JSON, `curl`-POSTed to
  `/ingest` (or git-committed). Monitor run history for silent failures.
- ✅ **Batch it: ONE weekly run for ALL the week's players, not per-player** (owner insight). The API
  blowup was *flailing* (18 unfocused searches hoarding raw page text on Sonnet), NOT "search is
  expensive" — a tight, fully-specified single prompt gets the whole fun-facts list in 1–3 searches
  (owner did exactly this by hand for Trin). Refined shape:
  - **Worker does selection + hands the routine each week's players WITH their ESPN stats already
    attached** (endpoint e.g. `/knowher/todo`). So the routine never searches for stats — only fun facts.
  - **Routine (one weekly run):** for the batch, search ONLY fun facts across the preferred sources,
    apply guardrail + ≥2-source rule, **distill each player to vetted facts and DROP raw page text before
    the next** (this is what keeps context bounded — the real cost lever, not batch-vs-per-player), emit
    ONE JSON doc → POST `/ingest`.
  - **Stat/identity questions = code-templated from the ESPN data (free).** The routine only does the
    fun-fact half + formatting. On the flat subscription, the sole limit is the daily token cap, which
    one tight batch run stays under (split into 2 runs if ever needed).
- ✅ **Live test (2026-07-02, Sonnet 5 vs Gemini, one player = Trin) — validated:**
  - **THE GUARDRAIL WORKS.** Both models dropped the Dennis-Rodman-dad trap; Claude's `dropped` list even
    caught "Triple Espresso" as defining her through more-famous co-stars (Layer 4). Biggest risk of the
    feature — proven enforceable live.
  - **Claude > Gemini on TRUST.** Claude showed its search/verify trace and dropped PS5 when a newer SI
    piece contradicted it. **Gemini was warmer but looser** — asserted the pre-wrap fact with
    "approved-source" citations Claude couldn't verify (likely loose attribution) + garbled a name. →
    reinforces the **Routine (Claude)** choice; STEAL only Gemini's warmer fan-friendly phrasing.
  - ⚠️ **Source allow-list was TOO NARROW — fix.** It was built for the crawler-limited API (~10 domains
    that block NBC Olympics/Time/Biography/Red Bull/People). On the SUBSCRIPTION routine/chat Claude CAN
    read those. The narrow list strangled the fun facts (dropped PS5/pre-wrap/makeup-artist/age-4/Trin-
    Spin) → the quiz came out STAT-HEAVY (not thin content — a too-tight whitelist). **Broaden to a wider
    curated "reputable" tier** (mainstream outlets + dedicated player-profile sites), keep ≥2-source
    corroboration + guardrail → recovers the human hook.
  - Small tunes: force **4 options for MC** (Gemini gave 3); on a contradiction prefer the most-recent
    reputable source (or include the nuance) instead of auto-dropping; warmer voice.
- ✅ **Haiku v2 test (2026-07-02):** broadened source list WORKED — fun facts came back (makeup-artist
  dream, basketball-as-kid, Colleen Hoover, pre-wrap, Vampire Diaries), good stat/human balance; Haiku
  HELD the person-guardrail (dropped dad/dating). **BUT looser corroboration** — included SINGLE-source
  fun facts (pre-wrap, Vampire Diaries, "shake her eyes") violating its own ≥2-source rule + a shaky
  "50 goal contributions" stat with mismatched URLs (same loose URL-attribution Gemini showed). Sonnet
  had correctly DROPPED those single-source facts.
- ✅ **CONCLUSION — run the routine on SONNET, not Haiku.** Guardrail holds on both, but CORROBORATION
  rigor degrades on the cheap models. The cost reason for Haiku existed only on the METERED API (15×
  cheaper) — abandoned. On the flat SUBSCRIPTION routine, Sonnet's rigor is ~free (just more daily-cap;
  fine for one weekly batch, esp. Max) → no upside to Haiku's looseness. **Use Sonnet.**
- ⚠️ **Tighten the prompt (all models leaked):** require **≥2 DISTINCT-DOMAIN** reputable sources for fun
  facts; **only cite URLs actually retrieved — else drop the fact** (anti-fabrication); drop trivial
  facts. Optional cheap **verification pass** enforcing ≥2 real sources per fun fact.
- The owner's key diagnosis (correct): the API blowup was **open-ended search** (18 autonomous searches
  ballooning context on Sonnet), NOT "using search." The fix is a **TIGHT single prompt per player with a
  hard search cap (≤~3)** + explicit ≥2-source corroboration + weighting rules → everything for a player
  in one bounded result. This discipline applies on ANY surface.
- The acquisition DESIGN is unchanged (bounded Wikipedia/ESPN fetches, **code-template stat Qs = free**,
  five-layer guardrail, ≥2-source corroboration, generate-once → cache in KV). Only the EXECUTOR moves
  from proxy-Haiku-**API** to the subscription **Routine** (Claude cloud, drawn from the Max/Pro plan).
- Routine flow: weekly cron → pick eligible players → per player run the tight guardrailed prompt →
  `curl` POST the JSON to a Worker ingest endpoint (secret-gated) → KV → app serves cached. Monitor runs.

## 5c. Latest sourcing tuning + STATUS (2026-07-02) — NOTHING RULED OUT (owner)

- **Google/Gemini = RECALL, our code = FILTER.** Google AI Overview / Gemini grounding surfaces rich
  candidate facts (found Sophia Wilson's exotic-pet zoo + gymnastics dream; Kaleigh Kurtz's almost-quit
  story) BUT won't filter — the same overviews surfaced guardrail violations (dad/sister; NFL fiancé) and
  cited junk (Girls Soccer Network/YouTube/soccer.com). Model: AI does broad recall; OUR code applies the
  guardrail + reputable-source allow-list + substance bar and keeps the best 1–2. (Google AI Overview
  isn't a callable API; its engine = the Gemini free-API grounding we tested.)
- **Disambiguation (owner catch — works):** the prompt confirms each fact is about the RIGHT NWSL player
  (discard same/similar-name namesakes) + her CURRENT club, and emits a `confirmedIdentity`. In the v3
  test it CORRECTLY corrected a stale team (Kaleigh Kurtz → Denver Summit FC, 2026 expansion, not NC
  Courage).
- **Gemini v3 verdict:** disambiguation ✓, guardrail ✓ (didn't define Sophia via her NFL husband),
  applied 2-domain to obvious single-source facts ✓ — BUT still counted JUNK domains as reputable
  (futbin = a video-game site!, clifbar/soccer.com = sponsor/retailer, nuzest = supplement brand) and
  asserted a likely-false milestone. ⇒ the safeguard MUST gate sources against an explicit APPROVED-DOMAIN
  ALLOW-LIST (not just "2 distinct domains") + require URLs resolve. Residual risk it can't catch: a wrong
  CLAIM on a real reputable page → why the rigorous model (Sonnet) + optional verify pass matter.
- ⚖️ **STATUS — nothing ruled out (this is a long-term fine-tuning effort, owner):** **Sonnet** = proven,
  rigorous, most surviving fun facts, but higher cost / uses subscription cap (dodge via an OVERNIGHT
  routine so it never hits the daytime 5-hr session window). **Gemini** = free + best recall, loose on
  source-quality (needs the allow-list safeguard + tuning) → more stat-heavy after filtering. **Haiku** =
  cheap, holds guardrail, looser corroboration. ALL THREE remain viable with fine-tuning; the ENGINE is
  deliberately LEFT OPEN and is the main thing to tune in future sessions. The code safeguard (allow-list
  + ≥2 distinct domains + resolves) makes PUBLISHED output trustworthy on ANY engine — we are ~90% there;
  the remainder is sourcing trial-and-error, not an app-build blocker.

## 5d. ✅ SETTLED + BUILT (2026-07-13) — the automated weekly pipeline (supersedes the open items above)

The engine question is CLOSED: **a weekly Claude Routine (owner's subscription, Sonnet, Monday 09:00 UTC
≈ 5am ET)** runs the **FULL fine-tuned Rodman-WORKING query** — the owner declared that prompt final
("generated the perfect questions"; the old MC-difficulty frontier is closed). This supersedes §5's
"code-templated stat questions + Haiku fun facts" sketch: the tuned prompt writes ALL questions,
including stat ones built from the verified numbers the proxy provides (no stat lookups, so the old
web_search cost balloon doesn't apply — and the routine draws subscription quota, not API dollars).

The built loop (proxy repo, branch → PR):
1. **Assemble (code, not model judgment):** `scripts/assemble_knowher_prompt.mjs` fetches each club's
   pick from `/knowher/todo` (now serving age/country + keeper cleanSheets/saves), computes the ISO
   weekKey, and fills `scripts/knowher-weekly-TEMPLATE.md` (the Rodman-faithful template; wording is
   owner-owned and immutable). Gaps warn loudly; offseason exits non-zero.
2. **Generate:** the routine executes the assembled prompt verbatim (web search per its own guardrails).
3. **Validate:** `load_knowher.mjs --dry-run` (server rules, no write).
4. **Publish:** `POST /knowher/ingest` — dedicated `KNOWHER_INGEST_KEY` (never the master admin key,
   never in the public repo), reusing the ONE validate→KV→markFeatured path so the once-per-season
   rotation always advances. Every accept/reject emits a diag.
5. **Watchdog:** `/knowher` serving emits `knowherStaleWeek` (throttled 1/day, in-season) whenever the
   served pool's weekKey lags the current ISO week — a silent missed Monday is impossible.
6. **Failure posture:** one retry per step then stop LOUD; last week's pool stays live (serving has no
   week gate). The user-facing Monday nudge stays the existing Tier-1 LOCAL notification (Mon 10:00 AM,
   `playerSpotlight` opt-in) — unchanged, works signed-out.
Runbook = `scripts/knowher-weekly-routine.md` (the routine's committed instruction set).

## 6. The five-layer guardrail 🔒 — enforced at generation level (bake into the prompt verbatim)

1. **Public** — not private life.
2. **About HER** — her own career/achievements/personality/story; never defined through, attributed
   to, or introduced via another person (esp. a more famous one).
3. **Sourced** — official/verified only; never fan theory as fact.
4. **Holds even when true** — canonical fail: "grew up around basketball → dad Dennis Rodman."
   Rejected because it makes her story about a man's fame.
5. **MECHANICAL RULE** — if the answer to a question is another person's name/identity/achievements,
   it's OUT.

**Framing test (Taylor Swift):** WOULD ask — how many cats, cats' names, a house referenced in a song,
did she play soccer, handed out demos at the NJ shore (T/F). WOULD NOT — which ex a song is about,
did an ex influence her writing, who she's dating. Rule ≠ "no personal life"; rule = "nothing that
defines her through someone else." **Why it matters:** AI reproduces training-data bias that frames
NWSL players through men; this guardrail actively fights that. It's a brand value, not just a filter.

## 7. Question design ✅ (REVISED 2026-07-02 after the first live playthrough)

- **Hybrid** stats + within-bounds personal; MC (4) + True/False. Categories shown as labels:
  `Her game` / `Her story` / `Her world` / `True or false`.
- **⚠️ FIRST-PLAYTHROUGH LEARNINGS (owner, Trin pool) — the generator produced the wrong mix:**
  1. **Too many gimme stats.** "What position?" / "What's her number?" / "How many games this year?" are
     trivial for a star (she starts every game → the answer is obvious). A few identity anchors are fine,
     but NOT 8 of them. Make stat questions actually think: MC options that are genuinely CLOSE (the
     minutes question — several 900-range options — was the only hard one, and it worked), or stats that
     aren't self-evident. Difficulty via *plausible-close options*, not obscurity.
  2. **Only 1 fun fact, dumped at the END.** That sets a "stat quiz" vibe and underwhelms — the emotional
     bond is the whole point. Target **2–3 fun-fact questions, INTERLEAVED** through the set (not all at
     the end). Stats are the FLOOR to reach ~10, not the bulk. Lead human-first.
  3. **The lone hyper-specific T/F is a DUD.** A single "True or false: she wrote a children's book called
     '<exact title>'" is un-challenging — the answer is obviously TRUE (you can't invent that specificity,
     so it's a free guess; the answer is never plausibly false). **Fix:** (a) for a SINGLE fun fact, use
     an **MC "which of these has she actually done?"** — one true option among 3–4 plausible-but-false
     ones (e.g. "produced a song / wrote a children's book / biked across several states / …"). This
     forces real knowledge. (b) Only use **True/False when there are ≥2 fun facts AND at least some T/F
     statements are plausibly FALSE** (a believable-but-untrue claim), so "true" isn't a free guess. A
     hyper-specific-and-always-true T/F is banned.
- **Hybrid is the goal for EVERY player** (the emotional bond is the point). A thin-content rookie
  skewing to "9 stats + 1 human" is an accepted *fallback FLOOR* — never the target; always reach for
  human details first, aim for 2–3, interleave them.
- **Target mix (the ratio, per the canonical prompt):** **≥6 HUMAN/story** questions
  (`herStory`/`herWorld`/`trueOrFalse`) and **≤4 stat/identity** (`herGame`); 2–3 of the human ones are the
  delightful "fun facts," interleaved. The `9 stats + 1 human` line above is the floor, not the aim.
- 📌 **Canonical generation prompt (single source of truth) — proxy repo
  `scripts/knowher-weekly-TEMPLATE.md`** (UPDATED 2026-07-13; §5d): the Rodman-faithful weekly template
  the automation fills via `scripts/assemble_knowher_prompt.mjs` and publishes via `/knowher/ingest`. It
  carries these §7 rules, the five-layer guardrail (§6), the GOLD-TIER source allow-list, and the output
  JSON schema — **keep it in sync with §6/§7, and never change its wording without an owner decision.**
  The proven single-player run it derives from is `scripts/knowher-prompt-rodman-WORKING.md` (+ its
  result JSON) — the untouched GOLD STANDARD, kept for comparison and future reuse. The §5 ~$2/player
  cost trap doesn't apply: the routine runs on the owner's subscription, not the metered web_search API.
- **✅ RODMAN PROMPT = FINAL (owner, 2026-07-13).** The biggest early worry — accurate, guardrailed,
  source-*discriminating*, genuinely-hard content — is SOLVED; the owner declared the Rodman run's
  questions "perfect" after multi-session tuning. The engine question is CLOSED. (The 2026-07-03
  experimental "MC self-audit" variant, `knowher-generation-prompt.md`, never proved out and was DELETED
  per the fallback discipline — the proven pre-self-audit wording is what the weekly template scales.)

## 8. Screen flow 🔒 (mockup `Player Spotlight Game.html`)

- **F1 Row card** — amber, player photo (team-tinted 44px), name/abbr, "Play now ›". (Multi-team → §3.)
- **F2 Intro** — `‹ Fan Zone`; big photo (108px), team tag, name, position/#, tagline, meta row
  (count | Weekly | max points), "Start the challenge", footer.
- **F3 Question** — `‹ Quit` (grey = discard); progress dots; "Question N of M · <category>"; 70px
  photo; question; 4 MC / 2 T-F; immediate correct(green)/wrong(red) reveal; auto-advance ~1.2s.
- **F4 Picker** — `‹ Fan Zone`; one row per followed team (team-tinted 52px photo + name + pos/team +
  Play / done badge). Completed → 72% opacity + score ("8/10 ✓").
- **F5 Result** — score circle; contextual **feel-good** title (90+/70–89/50–69/<50); subtitle surfaces
  one missed fact (the "learn" payoff); "＋N points" (to Superfan, if kept — §11); scrollable answer
  reveal. ✅ **No "See the leaderboard" CTA** (quiz = personal, not competitive) — replace with a
  contextual action: **"Next player ›"** when unplayed followed-team players remain this week, else
  **"Back to Fan Zone"**; footer.

## 9. State machine 🔒

`UNPLAYED → IN_PROGRESS → COMPLETED → (Monday reset) → UNPLAYED (new player)`. IN_PROGRESS quit =
discard. COMPLETED = points banked, no QUIZ replay — but the row stays **tappable → a read-only result
recap** (your score + the live community results); it is NOT a dead end. Weekly reset assigns new players
per team; the just-closed week is kept ONE week as a "Last week" section (final community results,
regardless of whether you played it). State keyed per `{week}-{team}-{player}` (mirror `PredictionStore`).

## 10. Fan Zone unseen/new indicator — ✅ discussion addition (Fan-Zone-WIDE; separable)

No unread/new/seen convention exists in the app today (only played→dim, and inconsistently — only
Trivia dims). Establish a unified **3-state per-card** model across all four games:
- **New/unseen** → small `dsUnseen` dot (NOT red — red = live/error). Fresh, unopened.
- **Seen/in-progress** → normal card + countdown/status; dot clears on open.
- **Done** → dim to 0.7 + "Done" (unify Predict/Bracket to also dim, matching Trivia).

"New" trigger per game: Trivia=new day; Predict=new fixture; Bracket=new round; **Know Her=new week /
newly-unplayed followed team**. Needs new persistence: per-game "seen cycle-key" set (UserDefaults).
✅ **APPROVED as a SEPARATE follow-up PR** (Fan-Zone-wide, not Know-Her-Game-specific) — not in this
feature's PR.

## 11. Leaderboards & Superfan ✅ (leaderboard scope NARROWED — owner)

**Principle (owner):** competitive leaderboards are only for the high-variation competitive games —
**Predict the XI** + **Bracket Battle**. Quiz-style games (Daily Trivia, **Know Her Game**) are about a
**personal feel-good result** ("10/12 — you really know her!" / "1/12 — we all start somewhere 🌱") and
learning the fact — NOT a competitive ranking (a leaderboard on "facts memorized" is hollow + less fun).

- ❌ **Know Her Game gets NO dedicated competitive leaderboard.** The Frame-5 "See the leaderboard" CTA
  is dropped (→ §8).
- Existing boards (verified in `GameCenterIDs.swift`): `predict.seasonpoints`, `bracket.totalpoints`
  (competitive — keep), `trivia.streak` (✅ owner decided to **REMOVE** — see §11b/§13), plus combined
  `superfan.total` (keep).
- ✅ **Superfan contribution — YES (adopted).** Know Her points feed the combined `superfan.total`
  aggregate (engagement/participation meta, NOT a skill board — like Trivia's lifetime-correct). Extend
  `GameCenterScores.superfanTotal` to a 4th arg (+ update `GameCenterIDsTests`) + add an amber
  "[N] spotlight" line to the `SuperfanCard` breakdown. The `superfan.total` board stays.
- `SuperfanCard` stays display-only. No new `knowher` per-game board is created.

## 11b. NWSL Trivia rename + community-results (quiz games) ✅ NEW SCOPE (owner)

The quiz-game *replacement* for a leaderboard — a NYT-style "how everyone did" screen — shared by
**NWSL Trivia + Know Her Game**:
- **Rename "Daily Trivia" → "NWSL Trivia"** — user-facing strings only (verified): `DailyTriviaView`
  nav title (:49), gate `gameName` (:54), card eyebrow "DAILY TRIVIA" (:110); `HomeView` card title
  (:619); `NotificationsView` subtitle (:156); the `#Preview` (`FanZoneCard.swift:262`). GC identifier
  strings (`…trivia.streak`, `game: .trivia`, `dsGameTrivia`) do NOT change (not user-facing; changing
  breaks GC records). Doc-comment renames optional.
- **Remove the `trivia.streak` leaderboard** (verified: 2 submit callsites — `DailyTriviaView.swift:206`
  + `GameCenterManager.swift:169`; drop both, plus remove the id from `Leaderboard.all` + the constant,
  and update `GameCenterIDsTests`). **Leave the `superfanTotal` submission untouched** (uses
  `trivia.totalCorrect`, independent of the streak board) and **keep the trivia achievements**
  (`triviaPerfectDay/Streak7/30`). Retire the App Store Connect leaderboard record out-of-code.
- **Community-results (shared component, BOTH quiz games):** your personal score shows on completion;
  the COMMUNITY breakdown reveals once the edition **CLOSES** (+ a past-editions archive — see "reveal
  timing" below).
  - Average score across players + per-question "% who got it right" (+ what everyone picked) — the
    interactive "alive" hook.
  - ✅ **Honest counts always, % at scale (revised — do NOT hide from early players):** show truthful
    **counts** at any N ("4 of 6 fans nailed this" — honest for player #2, no hiding, no wait-to-play
    incentive); layer in **percentages once N ≥ ~25**. Replaces the earlier "hide below N" idea, which
    punished early users.
- **Backend (NEW, shared — VERIFIED net-new) + COST-SAFE architecture (the Swifties lesson):** trivia
  today is local + a single Supabase `best_streak` scalar; NO per-question data exists, so this is fully
  new. The Eras-tour cost blowup = **live per-view DB aggregation** at spike — AVOID by decoupling
  aggregation from views:
  - **Write:** on completion the app upserts answers to Supabase `quiz_answers` (PK `(user_id, game,
    edition_key, question_id)` → idempotent, replay can't inflate; RLS owner-only insert/update, no
    per-user read). ~1 write/user/edition. `edition_key` = day-key (Trivia) / `{week}-{team}-{player}`.
  - **Aggregate + serve via the EDGE CACHE (Cache API, NOT KV writes):** a proxy endpoint computes the
    distribution from Supabase (as `service_role`; needs `grant … to service_role`, per the CLAUDE.md
    gotcha) on an edge-cache MISS and serves it via `caches.default` — exactly like the app's other hot
    endpoints (`proxyAndCache`) — with a **short TTL for live weekly counts (~15–30 min)** and a
    **long/immutable TTL for closed editions**. ⚠️ **Deliberately NOT KV writes:** the free tier's scarce
    limit is **1,000 KV writes/day** (the watcher already nears it on live-match Saturdays), so a
    per-edition-per-interval KV write would blow it — edge cache avoids that entirely. Only aggregate
    distributions leave the server; raw per-user answers never exposed (Bracket model).
  - **Read:** every result/archive view hits the edge cache (+ client local cache for closed editions),
    **NEVER** a live DB aggregation and **no KV write**. Supabase is touched only on a cache miss (bounded
    by editions × colos × TTL) + the tiny per-user answer upsert.
  - ✅ **Reveal timing — HYBRID BY CADENCE (owner):** **Know Her Game (weekly)** shows **live, growing
    honest counts DURING the week** (recompute on a timer → KV; % once N≥25) for in-week community energy;
    **NWSL Trivia (daily)** uses a **post-close (next-day) reveal** since its window is only 1 day. Both
    feed a **past-editions archive** ("your completed games", cached). **N=1 state — UPDATED 2026-07-13
    (owner):** the "you're the first / check back later" GATE is REMOVED — the live board shows from the
    first responder ("1 fan played" + honest counts). The honest count IS the live-stats hook, and the
    old gate perversely hid it from the 1st player AND from a 2nd player who fetched a pre-write count.
    Counts grow → percentages at N≥25.
  - **Cost at ~1k downloads ≈ $0 (verified tiers):** Supabase free = 500 MB DB / 5 GB egress-mo /
    unlimited API requests (answer rows ~hundreds of bytes → <<500 MB for ages); Cloudflare free = 100k
    Worker req/day + 100k KV reads/day (a few k views/day << that). A real spike (100k+ req/day) → CF paid
    **$5/mo**; Supabase Pro **$25/mo** only if DB>500 MB or egress>5 GB-mo — far off. The Swifties trap
    (per-view live aggregation) is simply not in this design.
- **Know Her Game's F5 result (§8) uses this same community-results component** (alongside the personal
  feel-good score) — so the leaderboard replacement is one build, two games.

## Sequencing (this effort is now multi-part)

- **A — Know Her Game** feature (the main build).
- **B — shared community-results infra** (Supabase aggregate + reusable UI component). Build alongside A
  (Know Her's result screen needs it).
- **C — NWSL Trivia** rename + `trivia.streak` leaderboard removal + retrofit the community-results
  component. Tight follow-up after A/B.
- **D — Fan-Zone unseen indicator** (§10) — separate PR, Fan-Zone-wide.

## Cost & scale (VERIFIED whole-app, not just this feature)

- **At 1–2k DAU: comfortably FREE** — ~28k (1k) to ~53k (2k) Worker requests/day vs the **100k/day** free
  ceiling; KV reads negligible (hot endpoints use the edge Cache API → ~flat vs users; standings/teams/
  stats go direct to ESPN = 0 Workers; crests bundled). Supabase nowhere near 500 MB / 5 GB-egress.
- **Free ceiling (~100k Worker req/day) crossed ~3,000–4,000 DAU** → Cloudflare **Workers Paid $5/mo**
  (owner: fine, donations cover it). Fixed ~3,200 req/day (every-min match-watcher + its proxy binding)
  is user-independent.
- **One free limit to watch: 1,000 KV writes/day** — the watcher's `MATCH_STATE`/Live-Activity writes near
  it on a heavy live-match Saturday (schedule-bound, not user-bound). ⇒ community-results MUST serve via
  edge cache, not KV writes (§11b), so it adds ~0 here.
- Biggest per-user driver: per-launch fixed proxy calls (`/config`+`/scoreboard`+`/team-videos`+
  `/spotlight`+`/headshots`); biggest episodic driver: live-match `/summary` 30 s polling
  (`MatchDetailView`), only while parked on a live match.
- **This feature's own load:** ~1 tiny Supabase write/user/edition + edge-cached reads = negligible; does
  NOT move the free-tier math at 1–2k DAU.
- ⚠️ **Anthropic content-generation cost (learned the hard way 2026-07-02):** the `web_search` tool +
  Sonnet cost **~$2/player** (context balloons with page content). BANNED for this pipeline. Cost-viable
  path (§5): free fetches (Wikipedia + ESPN) + code-template stat Qs + one small **Haiku** call for fun
  facts, generated once/player and cached → ~cents/player. Set a monthly spend cap in the console.

## 12. Color 🔒

`dsGameSpotlight` = `#F5A623` (amber). Player's **team color** tints the photo circle + team tag so
it still feels like *your* player while the game chrome stays amber. Add token to app `DSColor.swift`
and proxy `tokens/colors.css`.

## 13. Files to touch (grounded in code exploration)

**App (NWSLApp):**
- `Views/HomeView.swift` — remove `getToKnowYourPlayers` section; add cluster-card model builder +
  the 1-team-vs-2+ branch (mirror `predictCardModel`'s `count>=2` pattern) + destination routing.
- `Components/FanZoneCard.swift` — amber accent case; add `isUnseen` bool + dot; unify done-dim.
- New `Views/KnowHerGameView.swift` (intro/question/result) + `Views/KnowHerPickerView.swift` (mirror
  `PredictXIView` list → `.fanZoneGate` → `.sheet`); new `Stores/KnowHerGameStore.swift` (mirror
  `PredictionStore` keyed per week/team/player).
- `DesignSystem/DSColor.swift` — `dsGameSpotlight`, `dsUnseen`.
- `Services/GameCenterIDs.swift` — 4th game in `superfanTotal` + a leaderboard id.
- `Services/NotificationScheduler.swift` — recopy the existing Mon-10am `weeklySpotlightRequest` →
  "New Know Her Game" (still pure opt-in, default OFF); name a weekly-rotated player.
- Retire `Components/PlayerSpotlightCard.swift` + `Views/PlayerSpotlightView.swift`. Keep headshot
  resolution (`HeadshotStore`) and the season-stats data path (reused). `docs/FILEMAP.md` update.

**Trivia rename + leaderboard removal + community-results (parts B/C):**
- `Views/DailyTriviaView.swift` — rename strings (:49/:54/:110); drop the `:206` streak submit; submit
  per-question answers to the community aggregate; present the community-results screen.
- `Views/HomeView.swift:619` (card title), `Views/NotificationsView.swift:156` (copy),
  `Services/GameCenterManager.swift:169` (drop trivia-streak submit), `Services/GameCenterIDs.swift`
  (remove `triviaStreak` from `all` + constant), `NWSLAppTests/GameCenterIDsTests.swift` (update pins).
- `ViewModels/TriviaViewModel.swift` — emit per-question answers on completion.
- **New shared** `Components/CommunityResultsView.swift` (both quiz games) + `Services/QuizResultsService.swift`
  (upsert answers + fetch the cached aggregate; local-cache closed editions) + a **past-editions archive**
  screen ("your completed games").
- **Supabase:** new `quiz_answers` table (`supabase/schema.sql` + a migration), owner-only RLS +
  `grant … to service_role` for the proxy aggregation read.
- **Proxy:** an aggregation job (at-close / timer) reading `quiz_answers` as `service_role` → a small
  per-edition distribution blob in **Cloudflare KV**; a read endpoint serving that cached blob (views
  never trigger a live DB aggregation).

**Proxy (nwslapp-proxy `src/index.ts`):**
- `fetchAthleteSeasonStats` — parse `starts` + `minutes`.
- Rewrite spotlight **selection** → roster-learning pool + KV coverage/once-per-season (§4).
- NEW **Know Her Game content** endpoint (e.g. `/know-her-game?team=`): fact-acquisition +
  corroboration + guardrailed Q&A generation (§5/§6). `tokens/colors.css` add `dsGameSpotlight`.

## 14. Streak ✅ APPROVED

A **weekly streak** — counts if you complete **≥1 player** in the Mon–Sun window (not all followed
teams — following 5 teams shouldn't make streaks harder). Resets on a fully-skipped week. Kept
distinct from Daily Trivia's *daily* streak.

## 15. Verification (merges handoff checklist + discussion additions)

1. Amber card in the row shows current player + team. 2. 1 team (and no "Last week") → intro directly;
2+ teams OR a last-week section exists → picker. 3. Question count ≥10, varies per player, shown on
intro. 4. Every question passes all five guardrail layers (spot-check: no answer is another person's
identity). 5. Immediate correct/incorrect + ~1.2s auto-advance. 6. Result adds points to Superfan + the
community "how everyone did" (reveal facts fold into it; no separate answers list). 7. Picker done rows
stay tappable → read-only result recap (score + "Results ›"); a "Last week" section shows the prior
edition's final results. 8. Monday reset assigns new players. 9. Superfan breakdown includes spotlight.
10. Old Spotlight section gone (pipeline/headshots retained). 11. **Roster-learning holds over weeks:
different players surface, pure subs (0 starts) never appear, everyone with real minutes eventually
features.** 12. **Unseen dot appears on new content, clears on open, returns next cycle.**

## BUILD PLAN (2026-07-02) — build 100% today, MANUAL-mode start; ONLY the auto sourcing SCRIPT is deferred

Owner directive: build the entire feature + all rules + data plumbing now. Ship in **manual mode** (owner
pastes Sonnet-generated content for well-known players across the 16 teams; game is playable live). Auto
weekly is deferred until the sourcing script is tuned — but the pipe it plugs into is built now, so
nothing gets retrofitted. Every piece below maps to a verified existing pattern.

### 0. Design doc (do FIRST)
Materialize this plan into a durable repo doc **`docs/know-her-game.md`** — full decision/dead-end/options
record with all sourcing options + pros/cons (nothing ruled out) so future sessions resume instantly.
Add a `docs/FILEMAP.md` entry.

### A. Proxy (`nwslapp-proxy`) — manual pool + route + admin + eligibility (mirror the Trivia KV model)
- **`knowher-pool.json`** (owner content file) + **`scripts/load_knowher.mjs`** (validate shape →
  `wrangler kv key put knowher-pool-v1 --binding FEED_TAGS --remote`) + `load-knowher` npm script — clone
  `scripts/load_trivia.mjs`.
- **`handleKnowHer`** route `GET /knowher?teams=` → read KV `knowher-pool-v1`, filter to followed teams,
  edge-cache 6h, **never cache empty**; register in the router (~`index.ts:598`) + 404 list (~`:622`).
- **Eligibility (built now; used by auto later):** `computeEligiblePlayers(team, year)` reusing
  `bracket-engine.ts` primitives — `${ESPN_SITE}/teams` → `/teams/{id}/roster` → `fetchStatsForMany(ids)`
  → keep `general.starts ≥ 1` (confirm exact stat name from one live payload; minutes/appearances
  confirmed). Expose `/knowher/eligible?team=` for the admin to see who's pickable.
- **Admin (mirror `bracket-admin-page.ts` + `handleBracketAdmin` + `adminAuthed`):** `GET /knowher/admin`
  (HTML page) + `POST /knowher/admin/api` ops: `pasteContent` (validate + write KV pool), `setMode`
  (manual/auto), `state` (view pool + eligible players). Extract `adminAuthed` into shared `admin-auth.ts`;
  gate with `BRACKET_ADMIN_KEY` (or a new `ADMIN_KEY`).
- **Mode flag:** KV `knowher:mode` (manual|auto, default manual). Manual = serve the pasted pool. Auto =
  a `scheduled()` cron branch calling the tuned generator — STUBBED behind mode=auto, not wired to run.

### B. Supabase — community results (shared by NWSL Trivia + Know Her Game)
- **`quiz_answers`** table (`user_id, game, edition_key, question_id, selected_index, is_correct, season`),
  upsert PK, owner-only RLS + `grant … to service_role`; SECURITY DEFINER aggregate RPC/view returning
  distributions. Migration + schema. (Know Her CONTENT stays in KV; only community answers go to Supabase.)

### C. iOS app (`NWSLApp`) — the full feature
- Models `KnowHerGame.swift`; Service `KnowHerService.swift` (+ `AppConfig.knowHerURL()`, empty=failure);
  Store `KnowHerGameStore.swift` (`@Observable`; per-`{week}-{team}-{player}` played+score → UserDefaults;
  weekly streak).
- Views `KnowHerGameView.swift` (intro→question→result, mirror `DailyTriviaView`) + `KnowHerPickerView.swift`
  (multi-team, mirror `PredictXIView` list → `.fanZoneGate` → `.sheet`); result = personal score +
  community-results, NO leaderboard CTA.
- `Components/FanZoneCard.swift`: `.knowHer` case + amber `dsGameSpotlight` + **cluster launcher card**
  (1 team = big face; 2+ = headshot cluster + "N played" → picker).
- `Views/HomeView.swift`: add `.knowHer` to `FanGame` + `knowHerVisible` gate (pool non-empty) + cluster
  model builder + routing; **retire the standalone Player Spotlight `getToKnowYourPlayers` section**.
- `DSColor.swift` `dsGameSpotlight`; `GameCenterIDs.swift`/`GameCenterManager.swift`: Know Her feeds
  `superfanTotal` (4th arg + `GameCenterIDsTests`) + amber "[N] spotlight" breakdown; NO Know Her board;
  **REMOVE `trivia.streak`** (2 callsites). `NotificationScheduler.swift`: recopy Mon-10am notif → "New
  Know Her Game".
- **NWSL Trivia rename** (verified strings). **Community results:** `Components/CommunityResultsView.swift`
  + `Services/QuizResultsService.swift` (upsert + fetch aggregate; hybrid reveal; small-N honest counts).
- Retire `PlayerSpotlightCard.swift` + `PlayerSpotlightView.swift`; keep `HeadshotStore` + season-stats.
  Update `docs/FILEMAP.md`.

### D. Admin for all games (owner point 4)
Build the **Know Her Game admin** now (needed for manual content) + extract shared `adminAuthed`. Direction:
a unified `/admin` with per-game tabs (Know Her tab now; Bracket keeps its page; Predict/Trivia controls =
fast-follow, flagged not blocking).

### Deferred (ONLY these)
1. ~~The tuned AUTO content-generation script~~ ✅ **RESOLVED 2026-07-13 — the weekly automation is BUILT
   (§5d):** template + deterministic assembly + `/knowher/ingest` + the scheduled Claude Routine (Mon
   09:00 UTC). Flip `knowher:mode` to auto after the first successful automated publish.
2. Fan-Zone-wide unseen indicator (§10) — separable follow-up; build the core game first. (Shipped
   2026-07-02 per §10.)

### Sequencing / reality
Large multi-surface build. Order: 0 doc → A proxy → B Supabase → C app → D admin. Branch
`feature/know-her-game` (app repo too). Manual-verify in the sim. I'll work methodically with task
tracking; the AI sourcing script stays deferred.

## Deferred / not now

Superfan tap-through stats view (parked). Unseen indicator may split into its own PR (it's
Fan-Zone-wide, not Know-Her-Game-specific).
