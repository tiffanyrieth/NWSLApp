//
//  HomeView.swift
//  NWSLApp
//
//  The Home tab — the app's your-teams-first hub, "alive between matchdays."
//  Until the user has been through onboarding it renders the "Make it yours"
//  team picker in place (tab bar stays visible); afterwards it shows the hub.
//
//  Modules, top to bottom (Fan Zone promoted to the top per the
//  design_handoff_fanzone_home handoff):
//   1. Fan Zone                 — the games as a single horizontal row of compact cards
//                                 (Predict → Bracket → Trivia → trailing Superfan card).
//   2. Club News                — team-channel content (the hook); PINNED section header.
//   3. Weekly Player Spotlight  — one weekly player spotlight per followed team.
//   4. Coming up                — a compact next-match strip per followed club.
//  ("Around the league" was removed — it duplicated the Schedule tab.)
//
//  Home owns no season or directory data: it reads the shared MatchStore,
//  ClubStore, and FollowingStore from the environment and derives everything
//  through HomeViewModel. The only thing it loads of its own are two TEMP content
//  seeds (Modules 1 & 2), via HomeViewModel.loadContent().
//

import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    // Lets Home's empty state re-present the picker after onboarding is done.
    @State private var showTeamPicker = false
    // The profile avatar button's destination (a placeholder until the Profile
    // screen ships in its own phase).
    @State private var showProfile = false
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore
    @Environment(ClubStore.self) private var clubStore
    // The shared, warmable/prewarmable Home content store — its raw items feed the
    // view model's derivation. Warmed during onboarding + prewarmed at launch.
    @Environment(HomeContentStore.self) private var homeContent
    @Environment(TriviaStore.self) private var trivia
    @Environment(BracketStore.self) private var bracket
    @Environment(PredictionStore.self) private var predict
    @Environment(KnowHerGameStore.self) private var knowHer
    @Environment(FanZoneSeenStore.self) private var seen
    // Cross-tab navigation (Module 4's "Full schedule →" jumps to Schedule).
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            // Onboarding is gated above this view now (RootTabView shows OnboardingView
            // full-screen until `hasOnboarded`), so Home only ever renders the hub.
            hubContent
        }
        .task {
            // Hand the view model the shared stores, load the shared stores once
            // (guarding on .idle so re-selecting the tab — or another screen having
            // loaded them first — doesn't refetch), THEN load Module-1 content.
            // Content runs last because the live `/team-videos` route is scoped to
            // the followed clubs, which `loadContent` resolves from the now-loaded
            // ClubStore. The hub gates on clubs+matches being `.loaded` anyway, so
            // content loading after them costs nothing visible.
            viewModel.store = matchStore
            viewModel.clubStore = clubStore
            viewModel.contentStore = homeContent
            if case .idle = matchStore.state { await matchStore.load() }
            await clubStore.loadIfNeeded()   // dedupe-aware: never scope content before clubs are loaded
            // Scope-aware: an instant no-op if the onboarding warm (or the launch prewarm)
            // already loaded this exact followed set; otherwise it fetches.
            await homeContent.loadIfNeeded(following: following, clubStore: clubStore)
            await loadBracketSummary()
            // Warm the Know Her Game pool for the followed teams (drives the Fan Zone card +
            // its visibility gate). Online-only — a failure just hides the game.
            await knowHer.loadIfNeeded(teams: viewModel.followedTeamAbbreviations(following: following))
        }
        // A newly-followed (or unfollowed) team should change Module 1 without a
        // manual refresh — refetch the live content scoped to the new followed set
        // (the deferred "refetch-on-follows-change" item). Also reset the per-team
        // chip if the team it pointed at was just unfollowed.
        .onChange(of: following.followedIDs) {
            viewModel.reconcileSelectedTeam(following: following)
            // Scope-aware: a follow added/removed changes the abbr set → the store refetches;
            // unchanged set → no-op (e.g. onboarding already warmed the exact final scope).
            Task { await homeContent.loadIfNeeded(following: following, clubStore: clubStore) }
            Task { await knowHer.loadIfNeeded(teams: viewModel.followedTeamAbbreviations(following: following), force: true) }
        }
        .sheet(isPresented: $showTeamPicker) {
            NavigationStack { OnboardingView() }
        }
    }

    /// Cache the active Bracket edition summary so the Fan Zone card can show/hide
    /// (the visibility gate) and render its status without opening the game. The
    /// full edition + real votes load when the game is opened (BracketService).
    private func loadBracketSummary() async {
        let service = BracketService()
        do {
            if let edition = try await service.currentEdition() {
                bracket.adopt(summary: .init(
                    id: edition.id, title: edition.title,
                    currentRoundRaw: edition.currentRound.rawValue,
                    roundClosesAt: edition.roundClosesAt, isActive: true
                ))
            } else {
                // Genuinely no active edition → hide the Fan Zone card.
                bracket.clearActiveEdition()
            }
        } catch {
            // Online-only: a failed gate preload leaves the existing gate as-is —
            // opening the game surfaces the honest error. Don't fabricate or clear.
        }
    }

    // MARK: - Hub

    @ViewBuilder
    private var hubContent: some View {
        Group {
            if let message = errorMessage {
                errorView(message)
            } else if !isReady {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                hub
            }
        }
        // Custom large-title header (title + profile avatar) like the Schedule /
        // Standings facelift headers; the system nav bar is hidden so the header
        // owns the top edge.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { homeHeader }
        .sheet(isPresented: $showProfile) { ProfileView() }
        .refreshable { await reload() }
    }

    // Large "Home" title + the profile avatar button, drawn as one pinned header.
    private var homeHeader: some View {
        HStack(alignment: .center) {
            Text("Home")
                .dsFont(32, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            profileAvatarButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Tight (ADDENDUM v2): + the scroll's 8pt top inset ≈ an 8pt Home→Fan Zone gap.
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgGrouped)
    }

    // Avatar button → the Profile screen (account, notifications, follows).
    private var profileAvatarButton: some View {
        Button { showProfile = true } label: {
            ZStack {
                Circle().fill(Color.dsBgCard)
                Image(systemName: "person.fill")
                    .dsFont(14)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(Color.dsFgQuaternary, lineWidth: 1))
        }
        .accessibilityLabel("Profile")
    }

    private var hub: some View {
        ScrollViewReader { proxy in
        ScrollView {
            // Fan Zone leads the feed as a compact horizontal row; Club News follows
            // with a PINNED section header (the "you're in the feed" cue). LazyVStack +
            // pinnedViews gives native iOS header pinning — only Club News is a Section,
            // so only its header pins; Spotlight/Upcoming are plain modules below.
            // spacing: 0 — every gap is set by explicit per-module padding, NOT stack
            // spacing (ADDENDUM v2). A pinned Section's header→content gap would otherwise
            // inherit the stack spacing — that was the ~28pt chips→first-card void. Gaps
            // ABOVE a module are its own `.padding(.top)`, except the Club News section
            // break, which is the preceding Fan Zone module's `.padding(.bottom)` so it
            // scrolls away with the carousel (leaving the pinned header flush to the top).
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Zero-height top anchor — always present (Fan Zone hides in the offseason), so the
                // follow-change scroll-to-top below always has a target. See bug B.
                Color.clear.frame(height: 0).id(Self.topAnchor)
                playSection
                clubNewsSection
                comingUp
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color.dsBgGrouped)
        .onChange(of: following.followedIDs) {
            // Follows changed → the feed re-scopes to the new teams. Snap to top so a full-replacement
            // of the follow set doesn't strand the scroll offset past now-collapsed content (the "black
            // screen" that only fills in when you scroll back up). Bug B.
            proxy.scrollTo(Self.topAnchor, anchor: .top)
        }
        }
    }

    private static let topAnchor = "home-feed-top"

    // MARK: - Module 1: From your teams (the hook)

    // Club News is a PINNED Section now (the header + chips stick to the top as you
    // scroll past Fan Zone). The header (title + chips) and body (cards/states) are
    // split so the Section API can pin the header, but the body's branch logic is
    // otherwise untouched — same source scoping, caps, balancing, chip re-query, and
    // pool-cycling refresh (DO-NOT-TOUCH contract). teams/result are computed once here
    // and handed to both halves so `teamContent` isn't derived twice per render.
    @ViewBuilder
    private var clubNewsSection: some View {
        let teams = viewModel.followedTeamAbbreviations(following: following)
        let result = viewModel.teamContent(following: following)
        // Chips show under the SAME condition as before the split: only in the populated
        // branch (not error/empty/loading) and only when following 2+ teams.
        let showChips = viewModel.contentError == nil
            && !(result.cards.isEmpty && viewModel.selectedTeam == nil)
            && teams.count >= 2
        Section {
            // Club News always renders SOME body (cards/empty/loading), so its bottom
            // padding is a safe place for the Club News → Player Spotlight section break.
            clubNewsBody(teams: teams, result: result)
                .padding(.bottom, 24)
        } header: {
            clubNewsHeader(teams: teams, showChips: showChips)
        }
    }

    // The pinned header: "Club News" title + (when following 2+ teams) the per-team chip
    // bar. Opaque page-color background so scrolled cards don't show through when pinned.
    private func clubNewsHeader(teams: [String], showChips: Bool) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Club News").sectionTitle()
            // Per-team chips only when following 2+ teams — a fresh scoped re-query per
            // chip (NOT a client-side filter). HomeTeamChips owns that behavior unchanged.
            if showChips {
                HomeTeamChips(viewModel: viewModel, teams: teams)
            }
        }
        .padding(.top, 6)
        // 12pt bottom = the chips→first-card gap (ADDENDUM v2): with the LazyVStack at
        // spacing 0, the header's bottom padding IS that gap — the fix for the 28pt void.
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgGrouped)
    }

    // The Club News body — the same branch logic as before, minus the chip row (now in
    // the pinned header). Nothing about the feed's data/scoping/balancing changes here.
    @ViewBuilder
    private func clubNewsBody(teams: [String], result: ContentRoundRobin.Result) -> some View {
        // Online-only: a failed live fetch shows an honest tap-to-retry card for
        // THIS module only (the rest of Home stays usable) — never stale/seed.
        if let error = viewModel.contentError {
            moduleError(error) { await viewModel.retryContent(following: following) }
        }
        // Nothing to show on "All": distinguish genuinely-no-follows (invite to choose)
        // from has-follows-but-empty-content (honest "no fresh posts" + retry). The old
        // code showed "Follow your teams" for BOTH — misleading to someone who already
        // follows a team (the bug reproduced in-sim on the brother's exact state).
        else if result.cards.isEmpty && viewModel.selectedTeam == nil {
            if following.followedIDs.isEmpty {
                followPrompt
            } else if viewModel.hasCompletedContentLoad && !viewModel.isLoadingContent {
                // A load actually completed empty → honest "no fresh posts" + retry.
                emptyFollowedContent { await viewModel.retryContent(following: following) }
            } else {
                // Still loading (the directory-load → content-load gap, after the
                // hub's full-screen spinner clears): an honest loading state, NEVER
                // the empty/Retry card (a loading state must not look identical to an
                // empty result, #5). Mirrors FeedView's gate.
                contentLoadingPlaceholder
            }
        } else {
            VStack(spacing: 10) {
                if result.cards.isEmpty {
                    Text("No content from \(viewModel.selectedTeam ?? "") right now.")
                        .dsFont(13)
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(result.cards) { card in
                        ContentCardView(
                            card: card,
                            club: viewModel.club(forAbbreviation: card.teamAbbreviation ?? ""),
                            // Following one team → drop the redundant team badge +
                            // name on every card (chip redesign, adaptive labels).
                            hideTeamIdentity: teams.count <= 1
                        )
                    }
                }
                if result.overflowCount > 0 { seeMoreLink }
            }
        }
    }

    // Opens the full chronological list of all followed-team content (Change 1),
    // respecting the active chip. Appears only when the balanced module is capping
    // content off.
    private var seeMoreLink: some View {
        NavigationLink {
            HomeContentListView(viewModel: viewModel)
        } label: {
            HStack {
                Text("See more club news →")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsAccent)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
    }

    // Shown when the user follows nobody (so the lead module has nothing to show).
    private var followPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "star")
                .dsFont(32)
                .foregroundStyle(Color.dsFgSecondary)
            Text("Follow your teams to fill your home feed with their latest content.")
                .dsFont(15)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
            Button("Choose your teams") { showTeamPicker = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    /// Shown when the user HAS follows but their content came back empty — an honest, retryable
    /// state. Distinct from `followPrompt` (which is only for genuinely-zero follows) so we never
    /// tell someone who already follows a team to "follow your teams."
    private func emptyFollowedContent(retry: @escaping () async -> Void) -> some View {
        RetryStateView(message: "No fresh posts from your teams right now.",
                       retryLabel: "Retry", icon: "tray", style: .card) {
            await retry()
        }
    }

    /// Shown while Module-1 content is still fetching (after the hub's full-screen spinner
    /// clears but before the cards arrive) — an honest loading card, so the empty/Retry
    /// state never flashes during a normal load.
    private var contentLoadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // MARK: - Module 3: Fan Zone (the games)

    // Fan Zone visibility rule: each game has its own gate, and a game with nothing
    // active/upcoming is hidden EVERYWHERE (card + screen) — no dead links or stale
    // states. The module itself hides when no game is visible (offseason). Predict
    // the XI's gate is a followed-team fixture within 28 days; Bracket and Daily
    // Trivia are seed-backed so always have content for now (their real gates land
    // when they go live).
    private var predictXIVisible: Bool { predictXIActive }
    private var bracketVisible: Bool { bracket.hasActiveEdition }
    private var triviaVisible: Bool { true }

    /// The visible games, ordered most time-sensitive first. Predict the XI is
    /// matchday-driven AND personal (you predict YOUR team's lineup), so it leads
    /// when a followed team has a fixture within 28 days; Bracket Battle and Daily
    /// Trivia follow. The first entry becomes the featured lead card.
    private enum FanGame: Hashable { case predict, bracket, trivia, knowHer }
    /// Know Her Game shows when the weekly pool has a featured player for a followed team
    /// (hidden in the offseason / before content loads — online-only, docs §4).
    private var knowHerVisible: Bool { knowHer.hasContent }
    private var visibleGames: [FanGame] {
        var games: [FanGame] = []
        if predictXIVisible { games.append(.predict) }
        if bracketVisible { games.append(.bracket) }
        if knowHerVisible { games.append(.knowHer) }
        if triviaVisible { games.append(.trivia) }   // Trivia last (owner order)
        return games
    }

    @ViewBuilder
    private var playSection: some View {
        let games = visibleGames
        // The whole block hides when no game is active (offseason) → Club News rises to
        // the top. The Superfan card rides the row and never keeps the block alive alone.
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Bold white header — a peer of "Club News" (App Store shelf model, ADDENDUM
                // v2), not a muted eyebrow. dsFont so it still scales with Dynamic Type.
                Text("Fan Zone")
                    .dsFont(20, weight: .heavy)
                    .foregroundStyle(Color.dsFgPrimary)
                fanZoneRow(games: games)
            }
            // The one real section break on the page: carousel → Club News (≈20pt, split
            // with the Club News header's top pad). Bottom-padding the PRECEDING module keeps
            // the pinned Club News header flush to the top when it sticks.
            .padding(.bottom, 14)
        }
    }

    // The single horizontal row: uniform compact cards in FIXED order (Predict → Bracket
    // → Trivia → future), snapping, with the display-only Superfan summary as the trailing
    // card. Two cards + a peek show at rest so it's obvious the row scrolls. Order comes
    // from `visibleGames` (already fixed) — never sorted by deadline.
    private func fanZoneRow(games: [FanGame]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(games, id: \.self) { game in
                    NavigationLink { destination(for: game) } label: {
                        FanZoneCarouselCard(model: cardModel(for: game))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 152)
                    // Opening a game marks its current cycle SEEN → the "new" dot clears (docs §10)
                    // — and bumps the anonymous which-games-get-played counter (same stable key).
                    .simultaneousGesture(TapGesture().onEnded {
                        seen.markSeen(game: Self.seenKey(game), cycleKey: cycleKey(for: game))
                        Analytics.shared.log(.fanzoneGameOpened(Self.seenKey(game)))
                    })
                }
                // Trailing Superfan card — display-only (computed locally / synced to Game
                // Center as today), shown once the user has a cross-game score (≥2 games
                // played, total > 0). Stays even when a game is hidden, since it gates on
                // games PLAYED, not games currently visible.
                if superfanBannerVisible {
                    SuperfanCard(
                        predictPoints: predict.seasonPoints,
                        bracketPoints: bracket.points,
                        triviaCorrect: trivia.totalCorrect,
                        knowHerPoints: knowHer.totalPoints
                    )
                    .frame(width: 152)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    /// Show the Superfan banner only once the user has genuine scores in ≥2 games AND a
    /// non-zero total — never a meaningless "0" for a new user (handoff visibility rule).
    private var superfanBannerVisible: Bool {
        let played = [predict.hasPredicted, bracket.hasPlayed, trivia.totalAnswered > 0, knowHer.totalPoints > 0]
            .filter { $0 }.count
        let total = GameCenterScores.superfanTotal(
            triviaTotalCorrect: trivia.totalCorrect,
            predictSeasonPoints: predict.seasonPoints,
            bracketPoints: bracket.points,
            knowHerPoints: knowHer.totalPoints)
        return played >= 2 && total > 0
    }

    @ViewBuilder
    private func destination(for game: FanGame) -> some View {
        // Each game gates sign-in + display name at its first ranked action (FanZoneGate) —
        // no up-front invite needed (the old one-time, skippable .fanZoneIntro() was removed).
        switch game {
        case .predict: PredictXIView()
        case .bracket: BracketBattleView()
        case .trivia:  DailyTriviaView()
        case .knowHer: knowHerDestination
        }
    }

    /// One followed team with a player → straight to the intro (docs §3); 2+ → the picker.
    @ViewBuilder
    private var knowHerDestination: some View {
        let players = knowHer.players
        // Go straight to the game only for a single-team fan with NOTHING else to show. Route through
        // the picker when there are multiple players OR a "Last week" section exists — otherwise a
        // one-team fan would have no way to reach last week's results.
        if players.count == 1 && !knowHer.hasPreviousWeek {
            KnowHerGameView(player: players[0], weekKey: knowHer.weekKey ?? "")
        } else {
            KnowHerPickerView(teams: viewModel.followedTeamAbbreviations(following: following))
        }
    }

    // MARK: Fan Zone card models — HomeView owns the per-game state logic and hands
    // FanZoneGameCard a flat model to render.

    private func cardModel(for game: FanGame) -> FanZoneCardModel {
        var model: FanZoneCardModel
        switch game {
        case .predict: model = predictCardModel
        case .bracket: model = bracketCardModel
        case .trivia:  model = triviaCardModel
        case .knowHer: model = knowHerCardModel
        }
        // Unified 3-state (docs §10): done → dim (unify Predict/Bracket to match Trivia/Know Her);
        // else if there's fresh unopened content this cycle → the "new" dot.
        let isDone = model.doneLine != nil || model.dimmed
        if isDone { model.dimmed = true }
        model.isUnseen = seen.isUnseen(game: Self.seenKey(game), cycleKey: cycleKey(for: game), isDone: isDone)
        return model
    }

    // MARK: Unseen/new state (docs §10)

    private static func seenKey(_ game: FanGame) -> String {
        switch game {
        case .predict: return "predict"
        case .bracket: return "bracket"
        case .trivia:  return "trivia"
        case .knowHer: return "knowher"
        }
    }

    /// The current content-cycle key per game — changes when there's a genuinely new window
    /// (new day / round / fixture / week), which is what re-triggers the "new" dot.
    private func cycleKey(for game: FanGame) -> String? {
        switch game {
        case .predict:
            // The soonest open fixture = the current matchday; a NEW fixture opening rolls the key.
            return (openPredictFixtures.min { $0.deadline < $1.deadline }?.id) ?? nextPredictFixture?.id
        case .bracket:
            return bracket.summary.map { "\($0.id)-r\($0.currentRoundRaw)" }
        case .trivia:
            return Self.todayKey()
        case .knowHer:
            return knowHer.weekKey
        }
    }

    /// Local-day key ("yyyy-MM-dd") — Trivia's cycle (a fresh set each day).
    private static func todayKey() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// The Fan Zone "Know Her Game" card. One followed player → names her ("Trinity Rodman ·
    /// WAS"); 2+ → the cluster line ("N of M played"). All played → "Done this week".
    private var knowHerCardModel: FanZoneCardModel {
        let players = knowHer.players
        var model = FanZoneCardModel(game: .knowHer, title: "Know Her Game",
                                     contextLine: "This week's player")
        if players.count == 1, let p = players.first {
            model.contextLine = "\(p.playerName) · \(p.teamAbbreviation.uppercased())"
        } else if players.count > 1 {
            model.contextLine = "\(knowHer.playedCount) of \(players.count) played"
        }
        if knowHer.allPlayed {
            model.dimmed = true
            model.doneLine = "Done this week"
        }
        return model
    }

    private var predictCardModel: FanZoneCardModel {
        // Following 2+ predictable teams → the card is about the DEADLINE, not one team:
        // a generic "N predictions open" context + a countdown to the soonest deadline
        // across all your open predictions. (One predictable team → fall through to the
        // specific-matchup card below.) Tapping through lists every team's fixture.
        let fixtures = openPredictFixtures
        if fixtures.count >= 2 {
            var model = FanZoneCardModel(game: .predict, title: "Predict the XI",
                                         contextLine: "Pick your teams")
            let points = predict.seasonPoints
            if points > 0 { model.badge = "\(points)" }
            // "Open" = a prediction you haven't submitted yet; countdown to the soonest of those.
            let open = fixtures.filter { predict.prediction(for: $0.id)?.state != .submitted }
            guard let soonestDeadline = open.map(\.deadline).min() else {
                // Every followed team's prediction is already in.
                model.contextLine = "All predictions in"
                model.doneLine = "Picks locked in"
                return model
            }
            model.contextLine = open.count == 1 ? "1 prediction open" : "\(open.count) predictions open"
            model.statusLine = "Make your predictions"
            if let left = compactCountdown(to: soonestDeadline) { model.countdown = "\(left) left" }
            return model
        }

        // One predictable team (or none) → name the specific matchup, exactly as before.
        let context: String
        if let fixture = nextPredictFixture {
            context = "\(fixture.teamAbbreviation) vs \(fixture.opponentAbbreviation) · \(Self.kickoffLabel(fixture.kickoff))"
        } else {
            context = "Pick your team's XI"
        }
        var model = FanZoneCardModel(game: .predict, title: "Predict the XI", contextLine: context)
        let points = predict.seasonPoints
        if points > 0 { model.badge = "\(points)" }

        // Submitted for this fixture → the locked-in done line (no status/progress).
        let draft = nextPredictFixture.flatMap { predict.prediction(for: $0.id) }
        if draft?.state == .submitted {
            let drop = nextPredictFixture.flatMap { compactCountdown(to: $0.deadline) }
            model.doneLine = drop.map { "Picks locked in — results drop in \($0)" } ?? "Picks locked in"
            return model
        }

        let picked = draft?.slots.count ?? 0
        if points > 0 {
            model.statusLine = "\(points) season pts · \(picked)/11 drafted"
        } else if picked > 0 {
            model.statusLine = "\(picked)/11 drafted"
        } else {
            model.statusLine = "Make your prediction"
        }
        if let fixture = nextPredictFixture, let left = compactCountdown(to: fixture.deadline) {
            model.countdown = "\(left) left"
        }
        if picked > 0, picked < 11 {
            model.progress = .init(value: picked, max: 11,
                                   label: "\(picked) of 11 players picked — tap to finish")
        }
        return model
    }

    private var bracketCardModel: FanZoneCardModel {
        let summary = bracket.summary
        let round = summary.flatMap { BracketRound(rawValue: $0.currentRoundRaw) }
        let theme = summary?.title ?? "Bracket Battle"
        let context = round.map { "\(theme) · \($0.title)" } ?? theme
        var model = FanZoneCardModel(game: .bracket, title: "Bracket Battle", contextLine: context)

        let points = bracket.points
        if points > 0 { model.badge = "\(points)" }
        let closes = summary?.roundClosesAt.flatMap { compactCountdown(to: $0) }

        // The current round is submitted → locked-in done line.
        if let round, bracket.hasSubmitted(round) {
            model.doneLine = closes.map { "Picks locked in — results drop in \($0)" } ?? "Picks locked in"
            return model
        }

        let picks = round.map { bracket.picks(for: $0).count } ?? 0
        let total = round?.matchupCount ?? 0
        if points > 0 {
            model.statusLine = "\(points) pts · \(picks)/\(total) picks made"
        } else if bracket.hasPlayed {
            model.statusLine = "\(picks)/\(total) picks made"
        } else {
            model.statusLine = "Vote now"
        }
        if let closes { model.countdown = "\(closes) left" }
        if picks > 0, total > 0, picks < total {
            model.progress = .init(value: picks, max: total, label: "\(picks) of \(total) picks made")
        }
        return model
    }

    private var triviaCardModel: FanZoneCardModel {
        var model = FanZoneCardModel(game: .trivia, title: "NWSL Trivia",
                                     contextLine: "5 questions · refreshes daily")
        if trivia.streak > 0 { model.badge = "\(trivia.streak)🔥" }

        if trivia.hasPlayedToday {
            model.dimmed = true
            model.contextLine = "\(trivia.lastScore)/5 correct today"
            let fresh = compactCountdown(to: Self.nextLocalMidnight())
            model.doneLine = fresh.map { "Done today · new questions in \($0)" } ?? "Done today"
            return model
        }
        model.statusLine = trivia.streak > 0 ? "\(trivia.streak)-day streak" : "Play now"
        if let fresh = compactCountdown(to: Self.nextLocalMidnight()) {
            model.countdown = "New in \(fresh)"
        }
        return model
    }

    /// "Sat 7:30 PM" — the Predict context-line kickoff format (mirrors PredictXIView).
    private static func kickoffLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date)
    }

    /// The next local midnight — when Daily Trivia refreshes (TriviaStore's day-gate
    /// flips at local midnight).
    private static func nextLocalMidnight(from now: Date = Date()) -> Date {
        Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(24 * 3600)
    }

    /// Predict the XI is active when a followed team has a fixture within the 28-day
    /// window — the gate that hides the game (card + screen) in a long break. Derived
    /// from `nextPredictFixture` so the gate and the card read the SAME fixture.
    private var predictXIActive: Bool { nextPredictFixture != nil }

    /// One open Predict-the-XI fixture per followed team — that team's soonest upcoming
    /// game within the 28-day horizon — the SAME per-team set PredictXIView lists as open
    /// predictions (mirrors PredictXIViewModel.buildUpcoming). Sorted soonest kickoff first,
    /// so `.first` is the most imminent deadline. Empty → the game is dark (the gate).
    private var openPredictFixtures: [PredictionFixture] {
        let now = Date()
        let horizon = now.addingTimeInterval(PredictionFixture.activeWindow)
        var fixtures: [PredictionFixture] = []
        for id in following.followedIDs {
            guard let club = clubStore.club(id: id) else { continue }
            let next = matchStore.matches(for: club).first { event in
                guard let kickoff = event.kickoff else { return false }
                return kickoff > now && kickoff <= horizon
            }
            guard let event = next,
                  let kickoff = event.kickoff,
                  let home = event.homeCompetitor?.team?.abbreviation,
                  let away = event.awayCompetitor?.team?.abbreviation,
                  home == club.abbreviation || away == club.abbreviation else { continue }
            let isHome = home == club.abbreviation
            fixtures.append(PredictionFixture(
                eventID: event.id,
                teamAbbreviation: club.abbreviation,
                opponentAbbreviation: isHome ? away : home,
                isHome: isHome,
                kickoff: kickoff
            ))
        }
        return fixtures.sorted { $0.kickoff < $1.kickoff }
    }

    /// The most imminent open fixture (soonest deadline) — the one the single-team card
    /// names, and the gate's "is there anything to predict?" signal.
    private var nextPredictFixture: PredictionFixture? { openPredictFixtures.first }

    // MARK: - Module 4: Coming up (compact schedule strip)

    @ViewBuilder
    private var comingUp: some View {
        let fixtures = viewModel.nextMatches(following: following)
        if !fixtures.isEmpty {
            section("Coming up", accessory: { fullScheduleLink }) {
                VStack(spacing: 8) {
                    // Closure-based NavigationLink (Event isn't Hashable) — the whole row is
                    // the label so the card taps through to its fixture, like Schedule's cards.
                    ForEach(fixtures) { fixture in
                        NavigationLink {
                            MatchDetailView(event: fixture.event)
                        } label: {
                            ComingUpRow(fixture: fixture, anchor: matchStore.tickAnchor(for: fixture.event.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Jumps to the Schedule tab (via the shared AppRouter).
    private var fullScheduleLink: some View {
        Button { router.selectedTab = .schedule } label: {
            Text("Full schedule →")
                .dsFont(12)
                .foregroundStyle(Color.dsAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared building blocks

    @ViewBuilder
    private func section<Content: View, Accessory: View>(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .sectionTitle()
                    Spacer(minLength: 8)
                    accessory()
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .dsFont(12)
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
            content()
        }
    }

    /// A compact, honest per-module failure card: the whole card is tappable to
    /// retry (so the "tap to retry" copy is literal). Used by Modules 1 & 2 so a
    /// content/spotlight fetch failure degrades that module alone — never the whole
    /// hub, and never to stale/seed content.
    private func moduleError(_ message: String, retry: @escaping () async -> Void) -> some View {
        RetryStateView(message: message, icon: "exclamationmark.triangle", style: .cardTappable) {
            await retry()
        }
    }

    // MARK: - State plumbing

    private var errorMessage: String? {
        if case .error(let m) = viewModel.clubsState { return m }
        if case .error(let m) = matchStore.state { return m }
        return nil
    }

    private var isReady: Bool {
        if case .loaded = viewModel.clubsState, case .loaded = matchStore.state { return true }
        return false
    }

    private func reload() async {
        await matchStore.load()
        await clubStore.load()
        // Refetch Module-1 content, reset the chip to All, and rotate the window if
        // nothing new arrived (Change 1 pull-to-refresh behavior).
        await viewModel.refresh(following: following)
    }

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) {
            await reload()
        }
    }
}

#Preview {
    HomeView()
        .environment(AppRouter())
        .environment(FollowingStore())
        .environment(MatchStore())
        .environment(ClubStore())
        .environment(HomeContentStore())
        .environment(TriviaStore())
        .environment(BracketStore())
        .environment(PredictionStore())
        .environment(KnowHerGameStore())
        .environment(FanZoneSeenStore())
        .environment(AuthStore())
        .environment(NotificationPreferencesStore())
}
