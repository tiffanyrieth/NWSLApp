# File Map

_Update after every feature. 🔧 = intentional "coming soon" placeholder. Online-only — no runtime seed; fixtures live only in previews + tests. Design specs in `Reference/Design/*-spec.md`._

```
NWSLApp/
├── NWSLAppApp.swift                   — app entry; launches RootTabView; forces dark; DEBUG `-resetOnboarding`; AppDelegate (APNs token + foreground/tap → PushBridge)
├── NWSLApp.entitlements               — Sign in with Apple + aps-environment (push) + usernotifications.time-sensitive (live-match rich alerts) + game-center (Game Center)
├── Config/
│   ├── AppConfig.swift                — base URLs; scoreboard/summary/roster → proxy; DEBUG `-useESPNDirect`; content route URLs (teamVideos/feed/spotlight/trivia)
│   ├── Secrets.swift                  — 🔒 GITIGNORED Supabase URL + anon key
│   └── Secrets.example                — checked-in template (non-.swift so it never compiles)
├── DesignSystem/
│   ├── DSColor.swift                  — `Color.ds*` tokens (dark-only hex)
│   ├── DSMetrics.swift                — `enum DS` spacing/radii/avatar/crest/game-card dims
│   └── DSText.swift                   — text modifiers: `.dsFont(...)` (@ScaledMetric Dynamic Type — use instead of raw `.font(.system)`) + `.dsScoreFont()`/`.trackedCaps()`/`.sectionTitle()`; `.nativeBackButton(title:)` (bare ‹ chevron + centered title; nil = identity-header screens)
├── Models/
│   ├── BracketEdition.swift           — Bracket Battle: BracketRound (main 64→2 + qualifying q1–q4 negative codes) / Entrant / Matchup / Edition (flat Codable)
│   ├── Club.swift                     — flat Club + ESPN /teams decode (brand/alternate color → crests)
│   ├── Competition.swift              — `ScheduledMatch` (Event + `CompetitionType`: nwsl/concacafChampionsCup/challengeCup/international) + `ChampionsCupFeed`/`ChallengeCupFeed` (`usa.nwsl.cup`)/`NationalTeamFeed.all` (7 women's NT feeds; sync with proxy `WOMENS_NT_FEEDS`) — folds non-NWSL feeds into Schedule. `CompetitionType.primaryBroadcastOverride` = curated US English-rights map (CC→Paramount+) for comps ESPN carries only in Spanish
│   ├── ContentCard.swift              — unified ALIVE-content model: 7 layouts + `sourceType` (club·reporter·player·league·news). NO time window — representation is count-based + age-agnostic (see ContentRoundRobin)
│   ├── NationalTeam.swift             — followable women's NT: FIFA code + name + flag + brand color. Curated `featured(8)`/`all(16)` + a `discovered` init for data-driven Browse-all (ESPN flag by FIFA; color via DesignTeamColors.displayHex else neutral)
│   ├── AthleteStatistics.swift        — ESPN Core API /statistics → PlayerSeasonStats
│   ├── MatchSummary.swift             — ESPN /summary: lineups+formation, boxscore, key-events timeline
│   ├── PlayerSpotlight.swift          — (legacy) player-of-week model; the Home Spotlight section was retired for Know Her Game; model retained for the `/spotlight` decode path
│   ├── KnowHerGame.swift              — Know Her Game content: `KnowHerPool`/`KnowHerPlayer`/`KnowHerQuestion` (Codable, mirrors proxy `src/knowher.ts`); category labels; `editionKey(weekKey:)`
│   ├── PlayerStats.swift              — per-player season stats + team-leaders (real ESPN data)
│   ├── Roster.swift                   — squad + team profile from one roster fetch; `ClubSquad.cachedAsOf` from the proxy's `proxyCachedAsOf` marker (last-known-good fallback)
│   ├── Scoreboard.swift               — ESPN scoreboard structs + Event helpers
│   ├── Standings.swift                — table rows (rank + Club + GP/W/D/L/PTS + GF/GA/GD from ESPN pointsfor/against/differential)
│   ├── TeamSocialLinks.swift          — per-team social links for TeamDetail (reference data, no live API); `iconAssetName` → bundled brand glyph in `Assets.xcassets/Social/`
│   ├── TriviaQuestion.swift           — one Daily-Trivia question (4 options)
│   └── XIPrediction.swift             — Predict the XI: PositionGroup · Formation · PredictionFixture · XIPrediction (draft→submitted) · ActualResult · PredictionScore
├── Services/
│   ├── BracketScoring.swift           — pure Bracket scorer (tiered per-round points). Unit-tested
│   ├── ContentRoundRobin.swift        — pure COUNT-BASED fair-share (Home M1 + Social): `balanced` = EQUAL per-club slots, volume-blind + age-agnostic, strict recency within a club (round-robin across CLUBS, no type-interleave) + `home/feedSlotsPerClub` + `advancedOffsets` (pull-refresh rotation) + optional `ArticlePriority` (Home FIRST-LOAD only: prefer ≤quota=3 club-site articles TOTAL across clubs (global cap, round-robined) + float to top, then normal recency mix; staleness-gated 4×/14d relative — no time window). Unit-tested
│   ├── BracketService.swift           — Bracket Supabase client: currentEdition/results/leaderboard/submit + standings/myEditionStats (Leaderboard screen); throw or honest-empty (online-only)
│   ├── AthleteStatsCache.swift        — actor; session cache of PlayerSeasonStats
│   ├── ContentService.swift           — ALIVE content client: homeCards→/team-videos · feedCards→/feed · spotlightCards→/spotlight; all `throws` (online-only; no seed)
│   ├── ESPNService.swift              — async fetch: scoreboard + summary + roster (proxy)/teams/standings + seasonStats (Core API)
│   ├── FollowSyncService.swift        — Supabase `follows` client (fetch/push/add/remove); RLS-scoped
│   ├── CompetitionFollowSyncService.swift — Supabase `competition_follows` client (NT + Champions Cup keys: "nt:USA"/"concacaf"); competition twin of FollowSyncService; RLS-scoped
│   ├── DeviceTokenService.swift       — Supabase `device_tokens` client (APNs token); RLS-scoped
│   ├── NotificationPrefsSyncService.swift — Supabase `notification_preferences` upsert
│   ├── NotificationScheduler.swift    — @MainActor; LOCAL (Tier 1) scheduling: day-before reminder (global type ∩ teams with alerts on) + weekly spotlight (global)
│   ├── PushBridge.swift               — @MainActor @Observable `.shared`; UIKit AppDelegate (APNs/tap) → observable world
│   ├── LiveActivityManager.swift      — @MainActor @Observable `.shared`; V2 Live Activity app side: registers this device's push-to-start token (`live_activity_start_tokens`) + each running Activity's update token (`live_activities`, keyed by matchId), prunes on end; mirrors to Supabase (RLS-scoped). Token uploads run under a background-task assertion (`withBackgroundTime`) so a push-to-start COLD BACKGROUND launch can finish the session-refresh + write; every step emits a `liveActivityTrace` breadcrumb (no silent drops). DEBUG `-driveLiveActivity` drives a local pre→live→goal→HT→FT lifecycle
│   ├── SupabaseManager.swift          — the one shared SupabaseClient (built from Secrets)
│   ├── HeadshotStore.swift            — @MainActor @Observable `.shared`; fetches the `/headshots` map (espnAthleteId→NWSL GUID) once per launch; `guid(forAthleteID:)`; best-effort (failure → monograms)
│   ├── AssetRefreshService.swift      — @MainActor; cadenced (>30d/March) best-effort refresh of bundled crests/flags: diff `/crest/manifest` vs BundledAssetManifest, download only a rebranded asset to Caches; NEVER downgrades vector→raster; never gates cold start
│   ├── BundledAssetManifest.swift     — source-master hashes (sha256[:16]) of every shipped crest + FEATURED flag; matches the proxy manifest so a fresh install re-downloads nothing. GENERATED — regen when bundled art changes
│   ├── Diagnostics.swift              — @MainActor @Observable `.shared` NO-SILENT-FAILURES spine: os_log + capped event ring (assetBundleMiss/apiFailure/parseError/staleServe/…), surfaced in dev/TestFlight + flushed to proxy `POST /telemetry` (non-PII)
│   ├── GameCenterIDs.swift            — GameKit ID constants (4 leaderboards + 6 achievements) + pure cross-game score helpers (GameKit-free, unit-tested)
│   ├── GameCenterManager.swift        — @MainActor @Observable `.shared`; LAZY idempotent `authenticate()` (on-appear from game screens; Profile triggers via `openLeaderboards()` ON TAP, so the banner never overlays Profile) + best-effort submit/report/syncAll/showDashboard; `leaderboardsUnavailable` honest-fail. Only file importing GameKit
│   ├── TeamAlertPrefsSyncService.swift— Supabase `team_alert_preferences` client (per-team on/off upsert/fetchAll/fetchAllTeamIDs/delete, composite key); RLS-scoped; fetchAllTeamIDs+delete back the mirror prune
│   ├── CompetitionAlertPrefsSyncService.swift — NT twin of the above against `competition_alert_preferences` (keyed by follow_key "nt:USA"); push/fetchAll/fetchAllKeys/delete; the watcher reads it for NT push fan-out
│   ├── AccountDeletionService.swift   — calls the proxy `POST /account/delete` (sends the session JWT); throws on any non-2xx so deletion never silently "succeeds". The client can't delete an auth user (service-role only)
│   ├── AppleTokenExchangeService.swift — fire-and-forget `POST /auth/apple-token-exchange` (Apple authorizationCode + session JWT) so the proxy stores a SIWA refresh_token for revoke-on-delete (guideline 5.1.1(v)); never blocks sign-in
│   ├── ForceUpdateService.swift       — launch-time forced-update check: `GET /config` → compares `minBuild` (int) vs this build's CFBundleVersion; FAILS OPEN (timeout/error/unreachable → allow). See `AppGateView`
│   ├── SupportStore.swift             — @MainActor @Observable StoreKit 2: 4 tip tiers (one-time + monthly), load/purchase/restore; `errorMessage` honest-failure (unverified/pending/failed → message + telemetry, never a fake success)
│   ├── PredictLeaderboardService.swift— Supabase per-team Predict board: upsertScore + standings(team); a read failure shows only your real local score (no fabricated rivals)
│   ├── TriviaLeaderboardService.swift — Supabase league-wide Trivia best-streak board: upsertScore + standings; read failure shows only your real local streak
│   ├── PredictionScoring.swift        — pure Predict-the-XI scorer (Mastermind partial, max 88). Unit-tested
│   ├── RecentForm.swift               — pure last-5 W/D/L per club from the season; feeds Standings "Last 5"; `result(scored:conceded:)` = the shared W/D/L rule (reused by MatchDetailViewModel.form). Unit-tested
│   ├── TeamSocialLinksProvider.swift  — static per-team social-account URLs (reference data, no live API)
│   ├── TriviaService.swift            — Daily-Trivia client: triviaQuestions→/trivia; `throws` on failure OR empty pool (online-only; no seed)
│   ├── KnowHerService.swift           — Know Her Game client: pool(teams:)→/knowher; `throws` on failure OR empty pool (online-only; no seed)
│   └── QuizResultsService.swift       — SHARED community-results client (NWSL Trivia + Know Her): upserts per-question answers to Supabase `quiz_answers`; reads the aggregate distribution from the proxy `/quiz-results` edge cache (never a live DB aggregation)
├── Stores/                            — @Observable shared state → UserDefaults, injected
│   ├── AppRouter.swift                — tab selection (AppTab); `openMatch(eventID:)` live-push tap; `reselectNonce` (re-tap-active-tab → Schedule snaps to boundary); DEBUG `-startTab`
│   ├── AuthStore.swift                — @MainActor; Sign in with Apple → Supabase user; profile upsert + `hydrateProfile()` (reads display_name + name_is_custom on restore AND sign-in → survives reinstall); `displayName`/`displayNameIsCustom`/`profileHydrated`; `hasChosenName` (Fan Zone gate condition); deleteAccount
│   ├── BracketStore.swift             — Bracket per-edition/round draft + one-way submit (only after server ack) + banked points + edition-summary gate (`bracket.v2.*`)
│   ├── ClubStore.swift                — shared club directory; one fetch, many readers
│   ├── FeedPreferencesStore.swift     — Feed content-type toggles + muted sources + `defaultFeedFilter` (the chip the Feed opens to, raw string)
│   ├── FeedStore.swift                — @Observable shared Feed cards + load state (one fetch, many readers); PREWARMED low-pri from RootTabView (first switch instant); SCOPE-AWARE loadIfNeeded (refetch when follows arrive after the prewarm, not just on empty) like HomeContentStore; honest loading (never a fake-empty)
│   ├── HomeContentStore.swift         — @MainActor @Observable shared Home M1+M2 content (HomeViewModel derives off it). SCOPE-AWARE loadIfNeeded (no-op when scope matches, refetch when changed) + debounced `warm()` from onboarding + launch prewarm (Home populated on arrival, no flash); honest loading flags
│   ├── FollowSyncCoordinator.swift    — @MainActor; the ONLY follows↔Supabase bridge — clubs (`follows`) AND competition follows (`competition_follows`). RESTORE-ONLY launch reconcile (un-onboarded device restores full server set; never prunes on launch); unfollows propagate only via the per-toggle `removeFollow`; `restoreResolved` gates the root "Restoring…" state
│   ├── NotificationSyncCoordinator.swift — @MainActor; device-token + notif-prefs↔Supabase bridge
│   ├── TeamAlertStore.swift           — @Observable; per-team match-alert ON/OFF (`Set<String>`, clubs by ESPN id + NT by FIFA code) → UserDefaults; `migrateFromGlobalIfNeeded`; `replaceEnabled` (mirror reconcile); `onAlertChanged` sync seam
│   ├── MatchAlertPresenter.swift      — @Observable per-screen; the shared bell flow: turning ON cascades the default alert bundle first-time (`applyMatchAlertDefaultsIfFirstTime`) + Tier-2 sign-in intercept (defer behind SIWA when signed out) + confirmation toast; drives every bell (Teams/Competitions/hub)
│   ├── TeamAlertSyncCoordinator.swift — @MainActor; per-team on/off↔Supabase **device-authoritative mirror** reconcile, SPLIT BY REALM: clubs→`team_alert_preferences`, national teams (FIFA code)→`competition_alert_preferences` (key "nt:CODE"); authoritative set = followedIDs ∪ followedNationalTeams (NT no longer pruned); converges both tables + auto-cleans legacy NT rows; unfollow-clears for both; pure `authoritativeOnSet` (unit-tested)
│   ├── FollowingStore.swift           — followed clubs + national teams + Champions Cup toggle + onboarding gate; offline-first; `replace`/`replaceCompetitionFollowKeys` (mirror reconcile); `competitionFollowKeys` for sync; one-time legacy-competition migration; DEBUG `debugResetState`
│   ├── NationalTeamDirectoryStore.swift — @Observable; loads `/national-teams` once (data-driven Browse-all directory); idle/loading/loaded/failed
│   ├── MatchStore.swift               — shared season store; one fetch, many readers
│   ├── NotificationPreferencesStore.swift — Profile's notification toggles (PURE OPT-IN: all default OFF, no auto-enable); → NotificationScheduler / NotificationSyncCoordinator
│   ├── PredictionStore.swift          — Predict-the-XI durable state: predictions+scores by fixtureID (`predict.v2.*`); `seasonPoints` + `points(forTeam:)` + `scoredTeams`
│   ├── TriviaStore.swift              — Daily-Trivia streak/bestStreak/accuracy + one-play/day gate
│   ├── KnowHerGameStore.swift         — Know Her Game durable state (`knowher.v1.*`): per-edition scores keyed `{weekKey}-{team}-{athleteId}` + weekly streak; in-memory weekly pool (via KnowHerService); `hasContent`/`totalPoints`/`unplayedPlayers`
│   └── FanZoneSeenStore.swift         — Fan Zone new/unseen state (docs §10): per-game last-opened cycle key (`fanzone.seen.v1`); `isUnseen`/`markSeen`; drives the `dsUnseen` "new" dot that clears on open
├── ViewModels/                        — @Observable; one per screen (idle/loading/loaded/error)
│   ├── BracketViewModel.swift         — Bracket session: round phase, progress, results, leaderboard, settled-round scoring (+ Game Center submit)
│   ├── FeedViewModel.swift            — Social-tab source-class chips (All·Reporters·Players·Clubs by `resolvedSourceType`; Reporters = reporter Bluesky + news articles; `league` has no chip → All only) + 30-day recency cut on reporter/league/news (`isFresh`; club/player age-agnostic) + `arranged` = per-club `ContentRoundRobin.balanced` over all team-tagged cards (volume-blind); `itemsError` on fetch failure
│   ├── HomeViewModel.swift            — @MainActor; derives Home modules from MatchStore+ClubStore+Following; M1/M2 read from shared HomeContentStore (passthrough errors/loading + `retryContent`/`refresh`). M1 "All" capped at 7 (overflow → "See more"); per-team chip = full single-club lens; `hasRefreshed` gates first-load `ArticlePriority` (off after pull-to-refresh)
│   ├── MatchDetailViewModel.swift     — one match: temporalState (past/live/future) + /summary + live refresh + preview
│   ├── PredictXIViewModel.swift       — Predict slate (open fixtures per followed team) + scoring via /summary + per-team leaderboards (+ GC submit)
│   ├── XIPickerViewModel.swift        — in-flight XI picker: formation + slot→athlete + scoreline; read-only once submitted
│   ├── ScheduleViewModel.swift        — day-grouped sections + filters from MatchStore
│   ├── StandingsViewModel.swift       — one-shot fetchStandings
│   ├── TeamsViewModel.swift           — thin reader over the shared ClubStore
│   ├── TeamDetailViewModel.swift      — roster + social links + real season stats/leaders
│   └── TriviaViewModel.swift          — one Daily-Trivia session; questions ← TriviaService (throws→error state); non-repeating daily-5 (unit-tested); best-streak leaderboard (+ GC submit)
├── Views/                             — one screen per file
│   ├── AppGateView.swift              — launch gate wrapping RootTabView: runs the forced-update check BEFORE tab bar/data/follows; dark splash while checking, then content or the wall. DEBUG `-forceUpdateWall` previews the wall
│   ├── ForceUpdateView.swift          — the non-dismissible "Update Required" wall (no tab bar, nothing behind, only an "Update" button → `AppConfig.updateURL`, TestFlight)
│   ├── RootTabView.swift              — app root; gates the 5-tab TabView behind `hasOnboarded` (full-screen OnboardingView until done); injects stores; restores session + coordinators; PREWARMS matches + Feed + Home content (incl. during onboarding, so post-onboarding Home arrives populated); GC syncAll; routes live-push tap
│   ├── HomeView.swift                 — your-teams hub (32pt header + avatar), Fan Zone LEADS: Fan Zone = single horizontal row of compact `FanZoneCarouselCard`s (fixed order Predict→Bracket→Trivia, per-game FanZoneCardModel built here) + trailing `SuperfanCard` (gated ≥2 games played); Club News round-robin as a PINNED Section (title+chips split into clubNewsHeader/clubNewsBody, logic untouched) + per-team chips + "See more →" (per-module error+retry); Spotlight carousel; Coming up. refetch on pull + follows-change
│   ├── HomeContentListView.swift      — "Club News" ("See more →") firehose: ALL followed-team content, no cap, reverse-chron, respects the active team chip (+ `HomeTeamChips` bar: [All] + per-team)
│   ├── ProfileView.swift              — account & settings sheet: identity · Fan Zone stats (🏆 → Game Center) · Settings (discoverable Display-name row → shared `DisplayNameEntry` sheet, signed-in only + Notifications) · My Teams · Account (Sign out + REAL Delete account: server delete via AccountDeletionService → wipes all local stores; spinner + honest error on failure + explicit "Account deleted" confirmation on success, never a silent no-op)
│   ├── NotificationsView.swift        — the ONE notifications hub: §Match alerts (per-team) · §Alert types (global, dimmed when no team on) · §Activity. INVARIANT: Tier-2 ON ⟹ signed in (default OFF, sign-out resets); unfollow clears alerts
│   ├── SupportView.swift              — "Support NWSLApp" (StoreKit tips): hero · one-time/monthly toggle · 4 tip tiers · CTA · Restore · "Where it goes" · thank-you state
│   ├── DailyTriviaView.swift          — NWSL Trivia game (indigo); 5/day; results screen w/ `CommunityResultsView` (streak leaderboard retired, docs §11); writes per-question answers to the shared community aggregate
│   ├── KnowHerGameView.swift          — Know Her Game (amber `dsGameSpotlight`): intro→question→result for one featured player; tap-to-answer + ~1.2s auto-advance; result = feel-good score + missed-fact + `CommunityResultsView`, no leaderboard CTA; `KnowHerPlayerAvatar` (team-ring headshot)
│   ├── KnowHerPickerView.swift        — Know Her multi-team picker (2+ followed teams): one row per team's featured player, Play/done badge, sign-in gated; opens the game in a sheet with "Next player ›" swap
│   ├── BracketBattleView.swift        — Bracket Battle (teal): 5 screens — Edition Intro (ranked banner · titled How-it-works steps · 3-tier points · "See the full bracket" sheet · Good-to-know) · Voting · Save/Submit · Results · Bracket Overview; matchup cards show player headshots (PlayerDot, monogram fallback); play gated via `.fanZoneGate`
│   ├── BracketLeaderboardView.swift   — Bracket Leaderboard (pushed from Results/Overview): Rankings (your-position + podium + table) + Your Stats (totals/accuracy/streaks/edition history); real data only
│   ├── PredictXIView.swift            — Predict the XI (pink): open fixtures + Results breakdown + per-team leaderboard cards
│   ├── XIPickerView.swift             — Predict picker sheet: formation chips → pitch-grid slots → scoreline → Save/Submit (+ Game Center first-prediction)
│   ├── OnboardingView.swift           — first-open club picker, FULL-SCREEN until onboarded (un-skippable). Per-row alert bell (OFF default — teaches follow-vs-alerts) + Teams/competitions pointer + "Follow players" COMING SOON teaser. Continue → ThesisView
│   ├── ThesisView.swift               — one-screen "You're all set" framing between team picker and Home: brand-color crest row + adaptive thesis sentence + optional alerts line; "Let's go →" completes onboarding
│   ├── NotificationAuthPromptView.swift — contextual "sign in for live alerts" half-sheet (Tier 2)
│   ├── ScheduleView.swift             — full-season cards; filter chips (NWSL · My teams = clubs + NT + Champions Cup); date headers + TODAY chip; opens at the past/upcoming boundary (no flash); re-tap + filter animate back
│   ├── TeamsView.swift                — all-16 directory: ONE list (followed floated up); follow-competitions row; per-row 🔔 toggles (+ toast → hub) + nav-bar 🔔 → NotificationsView; first-visit coach mark
│   ├── CompetitionsView.swift         — follow international comps: Champions Cup card+toggle + National Teams scoped search → SUGGESTED (8 curated, USA-first) over the full data-driven A-Z list; honest loading/error/empty; NT get no detail page
│   ├── TeamDetailView.swift           — club page: header (⭐ follow) + social row + Squad·Stats tabs
│   ├── MatchDetailView.swift          — state-aware match: full-bleed Card-C header (72pt crests, team-color abbr + score) + bare ‹ chevron over a transparent bar (`nativeBackButton()`); past=Play-by-Play/Lineups/Stats (formation pitch + bench), live=poll & LIVE pill, future=info + How-to-Watch + comparison + form
│   ├── CombinedPitchView.swift        — BOTH teams' XIs on ONE pitch; Lineups default
│   ├── FormationPitchView.swift       — single-team XI on a pitch; per-team list fallback
│   ├── PlayerDetailView.swift         — roster bio + season stat block
│   ├── StandingsView.swift            — color-block table (# · TEAM · PTS · GP · W · D · L · GD · LAST 5); signed GD; crest + color-coded abbr; cyan PLAYOFF LINE; team-color spine/tint/accent rank = FOLLOW indicator; Last-5 via RecentForm
│   ├── FeedView.swift                 — **Social** tab ("The world talking about your teams"): header + 4 left-aligned source-class chips (h-scroll HStack, same as Home's `HomeTeamChips`) + per-club-balanced ContentCardViews; opens to `defaultFeedFilter`; full-screen error+retry on fetch failure
│   ├── FeedSourcesView.swift          — Feed content preferences: Default-view picker + content-type toggles + mute sources
│   ├── _ColorAuditView.swift          — 🔧 DEBUG-only 16-club color audit (`-colorAudit`); remove once verified
│   └── _AssetAuditView.swift          — 🔧 DEBUG-only bundled-crest/flag fidelity audit (`-assetAudit`); remove once verified
├── Components/
│   ├── BroadcastInfo.swift / BroadcastLink.swift — "How to Watch" DB + broadcast→watch-URL
│   ├── Chip.swift                     — pill filter chip (Schedule + Social chip bars); optional `compact` (13pt) + `horizontalPadding` override (Social packs 4 on one no-scroll row)
│   ├── CategoryPill.swift             — the card's "what kind of voice" pill (NEWS·LEAGUE·REPORTER·PLAYER·CLUB by `resolvedSourceType`); NEWS + REPORTER both ride the Reporters chip (article vs social format), LEAGUE has no chip
│   ├── BroadcastChip.swift            — color-coded broadcast pill (handoff palette, substring-matched); schedule cards + match detail (separate from BroadcastInfo's color DB)
│   ├── ContentCardView.swift          — single entry point; routes a ContentCard by layout → the 3 card views; 3px team-color left-edge bar (color-block motif) on all layouts
│   ├── ThumbnailContentCard.swift / AvatarContentCard.swift / ArticleContentCard.swift — ContentCard layouts, PER-TAB via `unified` (ContentCardView). NO source/club NAME line on any card — it's redundant with the badge + color bar + abbr chip + CTA link. Article header = NEWS badge + timestamp only (Home NEWS pill / Social CategoryPill), headline first below it. Social cards (Avatar/Thumbnail) drop the source line ONLY for `.club` (reporter/player/creator handles kept — they have no color bar/team pill to fall back on). Team abbr chip ALWAYS bottom-left (Shared `MediaTeamBadge` on media, else on the CTA footer row), gated 2+ clubs. Avatar cards Social-only. Home (`!unified`, ADDENDUM v2) densifies: 152pt top-center media crop, 15pt/2-line headline, tighter footer; Social keeps 16:9/200/180pt + 16pt/3-line
│   ├── MediaTeamBadge.swift (in ThumbnailContentCard.swift) — the single bottom-left media "which club" label: team ABBREVIATION only (team-color text on translucent-dark chip), NO crest
│   ├── SettingsToggleRow.swift        — shared settings primitives: `SettingsToggleRow` + `SettingsGroup` (optional subtitle + `note` line) + `SettingsRowDivider`
│   ├── PlatformBadge.swift            — platform glyph (YT/Bluesky/TikTok/IG/article/reddit)
│   ├── FormBadge.swift                — W/D/L form badge (optional `size`/`fontSize`, default 22; `MatchResult` convenience init)
│   ├── MatchAlertToast.swift          — reusable `.matchAlertToast(_:onCustomize:)` bell-confirmation toast (extracted from TeamsView so Teams + Competitions both show it); auto-dismiss, "Customize alerts" routes to the hub
│   ├── FanZoneGate.swift              — MANDATORY-to-play Fan Zone gate: `.fanZoneGate(isRequested:gameName:onAuthorized:)` → no-skip "Sign in to play" + REQUIRED display-name steps (`FanZoneGateSheet`), runs the action once signed-in+named (instant if already). `DisplayNameEntry` = the shared name field (gate + Profile editor). Replaced FanZoneIntroView + SignInPromptView (both deleted)
│   ├── FanZoneCard.swift              — Home Fan Zone horizontal-row cards: `FanZoneCarouselCard` (~152pt, accent-wash + GameIcon SF Symbol + name + context + one accent `compactStatus` line) driven by a flat `FanZoneCardModel` (games: predict/bracket/trivia/knowHer); `SuperfanCard` (trailing cross-game total incl. Know Her, display-only); `GameIcon`; pure `compactCountdown(to:from:)`
│   ├── CommunityResultsView.swift     — SHARED "how everyone did" panel (NWSL Trivia + Know Her): community avg + per-question "% got it right" (or honest counts at low N) + what-everyone-picked bars; reveal server-decided; fetches `/quiz-results` via QuizResultsService
│   ├── HowToWatchCard.swift / MDInfoCard.swift / StatComparisonBar.swift — match-detail tiles (HowToWatch = FREE/SUB badge + BroadcastChip + per-device "Find it" steps; MDInfoCard = label/value)
│   ├── PitchDot.swift / PlayerDot.swift / PlayerCard.swift — player markers/cards (team-color monogram, no headshots)
│   ├── ComingUpRow.swift / EventTimelineRow.swift / FlowLayout.swift — Home/match rows + wrapping layout (ComingUpRow upcoming rows carry a `● Platform · FREE/SUB` broadcast line)
│   ├── CoachMarkTriangle.swift        — shared upward arrow for one-time coach marks (Teams bell + Social gear nudges)
│   ├── ImageCache.swift / TeamLogo.swift / CachedThumbnail.swift — cached crests + thumbnails; TeamLogo: cached-override → BUNDLED crest/flag (zero-network) → proxy `/crest`/ESPN; CachedThumbnail sync-seeds from ImageCache (no flash)
│   ├── MatchCard.swift                — schedule card (`ScheduledMatch`) → MatchDetailView: team wash, 60pt crests + team-color abbr (non-NWSL via `displayHex`), scores, temporal center, broadcast+venue rail, competition label
│   ├── NationalTeamCard.swift         — shared NT grid card (Competitions + Browse-all): bundled flag → override → URL + halo, FIFA code in country color, Follow pill + bell; followed → wash + border. Reads FollowingStore + TeamAlertStore
│   ├── PlayerHeadshot.swift           — circular player headshot via HeadshotStore→Cloudinary (ImageCache); jersey-monogram fallback on all 6 avatar surfaces (404/unmapped keeps the monogram)
│   ├── PlayerSpotlightCard.swift      — Module-2 hero (~400pt): team-gradient card, headshot fade-masked into the gradient, text in a left zone; ghost# + crest fallback on no-GUID/404 (never empty)
│   └── SocialLinkButton.swift         — circular team-tinted social icon (brand glyph; currently unused — TeamDetail renders its own capsule pills)
├── Extensions/
│   ├── Color+Hex.swift                — Color(hex:); teamAccent/teamFillOnDark; resolveMatchColors
│   ├── Date+RelativeAgo.swift         — shared "2h ago" formatter
│   ├── Club+BrandColor.swift          — Club → brandHex/accentColor (design palette → id-override → ESPN)
│   ├── DesignTeamColors.swift         — curated 16-team NWSL palette by abbreviation (authoritative; `hex(for:)` = NWSL-membership test). `displayHex(for:)` = COLOR-only resolver adding NT + foreign CC clubs (separate, never affects membership)
│   └── TeamBrandColors.swift          — per-team-id brand-color overrides for clubs ESPN gets wrong
└── Assets.xcassets/                   — app icons, accent; `Crests/` (16 NWSL: 11 vector SVG + 5 raster PNG), `Flags/` (8 FEATURED NT flags, vector SVG; browse-all = download+cache) — bundled for zero-network first launch; `Social/` (5 brand glyphs — bluesky/instagram/reddit/tiktok/youtube — vector SVG, template-rendered for tinting)

NotificationServiceExtension/          — rich-notification target (the .appex embedded in the app). Wakes on `mutable-content:1`, downloads the payload's `imageUrl` (server-rendered match card), attaches it; always delivers text-only on failure/timeout (os_log spine — separate process can't reach Diagnostics)
├── NotificationService.swift          — UNNotificationServiceExtension: didReceive (download → UNNotificationAttachment) + serviceExtensionTimeWillExpire fallback
├── Info.plist                         — NSExtension (usernotifications.service) + CFBundle keys via build vars (GENERATE_INFOPLIST_FILE=NO)
└── NotificationServiceExtension.entitlements — aps-environment (mirrors app; auto-prod on archive)

NWSLLiveActivity/                      — V2 Live Activity target (WidgetKit extension .appex; min iOS 17.2 for push-to-start). The silent "glance" layer (lock screen + Dynamic Island) complementing V1 rich push; never buzzes
├── NWSLLiveActivityBundle.swift       — `@main` WidgetBundle → MatchLiveActivity()
├── MatchLiveActivity.swift            — ActivityConfiguration for MatchActivityAttributes: lock-screen banner + Dynamic Island compact/expanded/minimal; temporal pill colors (Live/HT/FT/pre); bundled crests (no ring); local advancing minute via `Text(timerInterval:)` from clockStartEpoch
├── Info.plist                         — NSExtension (widgetkit-extension) + CFBundle keys via build vars (GENERATE_INFOPLIST_FILE=NO; full key set incl. CFBundleExecutable/version — appex install fails without them)
└── Assets.xcassets/Crests/            — copy of the 16 NWSL crests (separate bundle; widget can't read the app's catalog)

Shared/MatchActivityAttributes.swift   — the ActivityAttributes type compiled into BOTH app + widget (explicit build-file membership, not a synced group). ContentState uses `clockStartEpoch: Double?` (Unix seconds) so the remote (watcher) decode is unambiguous; Phase enum pre/live/halftime/extraTime/penalties/fulltime

supabase/schema.sql                    — Postgres: profiles, follows, competition_follows, device_tokens, notification_preferences, team_alert_preferences, bracket_* (editions/entrants/matchups/votes/scores + v2: config/stats_editions/creative_editions/user_edition_stats), prediction_scores, trivia_scores, live_activity_start_tokens + live_activities (V2 Live Activity tokens) (+ RLS + GRANTs; all per-user FKs `on delete cascade` so account deletion cascades). v2 deltas in `migration_bracket_*.sql`; `migration_account_deletion_cascade.sql` adds cascade to the 5 FKs that lacked it; `migration_profile_name_is_custom.sql` adds `profiles.name_is_custom` (no backfill); `migration_live_activity_tokens.sql` adds the two V2 token tables; `migration_apple_refresh_token.sql` adds `profiles.apple_refresh_token` + `grant … to service_role` (SIWA revoke-on-delete); `migration_live_activities_pref.sql` + `migration_notif_opt_in.sql` add `notification_preferences.live_activities_enabled` (V2 opt-in) and flip all notification defaults to false (pure opt-in); `seed_bracket_*.sql` (run in the SQL editor)
docs/silent-failure-audit.md           — 2026-06 NO-SILENT-FAILURES sweep: method + the 15 read-path catches that now emit Diagnostics + the reviewed-OK `try?` sites
NWSLApp.storekit                       — local StoreKit 2 config (4 tip consumables + monthly subs) for in-sim Support testing; referenced by the shared scheme. ASC products owner-gated
```
