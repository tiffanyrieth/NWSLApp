//
//  HomeView.swift
//  NWSLApp
//
//  The Home tab — the app's your-teams-first hub, "alive between matchdays."
//  Until the user has been through onboarding it renders the "Make it yours"
//  team picker in place (tab bar stays visible); afterwards it shows the hub.
//
//  Modules, top to bottom (per Reference/Design/home-tab-design-spec.md —
//  content leads, schedule demoted):
//   1. From your teams          — team-channel content (the hook), real seeded.
//   2. Get to know your players — one weekly player spotlight (seeded).
//   3. Play                     — games (Trivia, Bracket Battle, Predict the XI).
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
    // Tracks the Module-2 spotlight carousel's current card, for the scroll dots.
    @State private var activeSpotlightID: String?
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore
    @Environment(ClubStore.self) private var clubStore
    // The shared, warmable/prewarmable Home content store — its raw items feed the
    // view model's derivation. Warmed during onboarding + prewarmed at launch.
    @Environment(HomeContentStore.self) private var homeContent
    @Environment(TriviaStore.self) private var trivia
    @Environment(BracketStore.self) private var bracket
    @Environment(PredictionStore.self) private var predict
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
        .padding(.bottom, 10)
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
            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .accessibilityLabel("Profile")
    }

    private var hub: some View {
        ScrollView {
            VStack(spacing: 28) {
                fromYourTeams
                getToKnowYourPlayers
                playSection
                comingUp
            }
            .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .background(Color.dsBgGrouped)
    }

    // MARK: - Module 1: From your teams (the hook)

    @ViewBuilder
    private var fromYourTeams: some View {
        let teams = viewModel.followedTeamAbbreviations(following: following)
        let result = viewModel.teamContent(following: following)
        section("Club News") {
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
                VStack(spacing: 14) {
                    // Per-team chips only when following 2+ teams — with one team
                    // there's nothing to filter (chip redesign).
                    if teams.count >= 2 {
                        HomeTeamChips(viewModel: viewModel, teams: teams)
                    }
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
                .font(.subheadline)
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
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .dsFont(28)
                .foregroundStyle(Color.dsFgSecondary)
            Text("No fresh posts from your teams right now.")
                .font(.subheadline)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await retry() } }
                .buttonStyle(.bordered)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
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

    // MARK: - Module 2: Get to know your players (spotlight)

    @ViewBuilder
    private var getToKnowYourPlayers: some View {
        let spotlights = viewModel.spotlights(following: following)
        if let error = viewModel.spotlightError {
            // Module 2 failed its live fetch — honest tap-to-retry, scoped to it.
            section(
                "Weekly Player Spotlight",
                subtitle: "Meet your squad — a different player each week so you know who to watch on match day"
            ) {
                moduleError(error) { await viewModel.retryContent(following: following) }
            }
        } else if !spotlights.isEmpty {
            section(
                "Weekly Player Spotlight",
                subtitle: "Meet your squad — a different player each week so you know who to watch on match day"
            ) {
                VStack(spacing: 10) {
                    // Equal-weight cards in a snapping horizontal carousel (one per
                    // followed team) — same visual weight, no full-size-vs-tap split.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(spotlights) { spotlight in
                                NavigationLink {
                                    PlayerSpotlightView(
                                        spotlight: spotlight,
                                        club: viewModel.club(forAbbreviation: spotlight.teamAbbreviation)
                                    )
                                } label: {
                                    PlayerSpotlightCard(
                                        spotlight: spotlight,
                                        club: viewModel.club(forAbbreviation: spotlight.teamAbbreviation)
                                    )
                                }
                                .buttonStyle(.plain)
                                // 85% of the carousel width so the next card peeks.
                                .containerRelativeFrame(.horizontal, count: 100, span: 85, spacing: 0)
                                .id(spotlight.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $activeSpotlightID)
                    .onAppear { if activeSpotlightID == nil { activeSpotlightID = spotlights.first?.id } }

                    if spotlights.count > 1 {
                        let active = spotlights.firstIndex { $0.id == activeSpotlightID } ?? 0
                        scrollDots(count: spotlights.count, activeIndex: active)
                    }
                }
            }
        }
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
    private enum FanGame: Hashable { case predict, bracket, trivia }
    private var visibleGames: [FanGame] {
        var games: [FanGame] = []
        if predictXIVisible { games.append(.predict) }
        if bracketVisible { games.append(.bracket) }
        if triviaVisible { games.append(.trivia) }
        return games
    }

    @ViewBuilder
    private var playSection: some View {
        let games = visibleGames
        if !games.isEmpty {
            section(
                "Fan Zone",
                subtitle: "Test your NWSL knowledge and compete with other fans",
                accessory: { activeGamesIndicator }
            ) {
                VStack(spacing: 10) {
                    // The cross-game Superfan summary, shown once the user has real scores
                    // in at least two games (never a meaningless "0" for a newcomer).
                    if superfanBannerVisible {
                        SuperfanBanner(
                            predictPoints: predict.seasonPoints,
                            bracketPoints: bracket.points,
                            triviaCorrect: trivia.totalCorrect
                        )
                    }
                    // Equal-weight, full-width stacked cards — every active game visible
                    // without a swipe, differentiated by accent color, not size.
                    ForEach(games, id: \.self) { game in
                        NavigationLink { destination(for: game) } label: {
                            FanZoneGameCard(model: cardModel(for: game))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Show the Superfan banner only once the user has genuine scores in ≥2 games AND a
    /// non-zero total — never a meaningless "0" for a new user (handoff visibility rule).
    private var superfanBannerVisible: Bool {
        let played = [predict.hasPredicted, bracket.hasPlayed, trivia.totalAnswered > 0]
            .filter { $0 }.count
        let total = GameCenterScores.superfanTotal(
            triviaTotalCorrect: trivia.totalCorrect,
            predictSeasonPoints: predict.seasonPoints,
            bracketPoints: bracket.points)
        return played >= 2 && total > 0
    }

    @ViewBuilder
    private func destination(for game: FanGame) -> some View {
        // `.fanZoneIntro()` wraps each game (outside its own body, so it doesn't collide with the
        // game's existing sheets) to show the one-time, skippable sign-in invite on first entry.
        switch game {
        case .predict: PredictXIView().fanZoneIntro()
        case .bracket: BracketBattleView().fanZoneIntro()
        case .trivia:  DailyTriviaView().fanZoneIntro()
        }
    }

    // MARK: Fan Zone card models — HomeView owns the per-game state logic and hands
    // FanZoneGameCard a flat model to render.

    private func cardModel(for game: FanGame) -> FanZoneCardModel {
        switch game {
        case .predict: return predictCardModel
        case .bracket: return bracketCardModel
        case .trivia:  return triviaCardModel
        }
    }

    private var predictCardModel: FanZoneCardModel {
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
        var model = FanZoneCardModel(game: .trivia, title: "Daily Trivia",
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

    /// The most imminent open Predict-the-XI fixture across followed teams — the same
    /// derivation PredictXIViewModel.buildUpcoming uses (Event → PredictionFixture within
    /// the 28-day horizon, soonest first), surfaced here so the Fan Zone card can show the
    /// opponent + kickoff + deadline countdown. Nil → the game is dark (the gate).
    private var nextPredictFixture: PredictionFixture? {
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
        return fixtures.min { $0.kickoff < $1.kickoff }
    }

    // "● 2 active" — a teal dot + count of games with something to do right now.
    @ViewBuilder
    private var activeGamesIndicator: some View {
        let n = activeGameCount
        if n > 0 {
            HStack(spacing: 5) {
                Circle().fill(Color.dsGameBracket).frame(width: 6, height: 6)
                Text("\(n) active")
                    .dsFont(11)
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
    }

    private var activeGameCount: Int {
        var n = 0
        if predictXIActive { n += 1 }                  // a followed-team fixture is up
        if bracket.hasActiveEdition { n += 1 }
        if !trivia.hasPlayedToday { n += 1 }
        return n
    }

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
                            ComingUpRow(fixture: fixture)
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
                        .dsFont(20, weight: .bold)
                        .foregroundStyle(Color.dsFgPrimary)
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
        Button { Task { await retry() } } label: {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .dsFont(22)
                    .foregroundStyle(Color.dsFgSecondary)
                Text(message)
                    .dsFont(14, weight: .medium)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Module-2 carousel scroll-position dots: one per spotlight, current filled.
    private func scrollDots(count: Int, activeIndex: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == activeIndex ? Color.dsFgSecondary : Color.dsFgQuaternary)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") { Task { await reload() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .environment(AuthStore())
        .environment(NotificationPreferencesStore())
}
