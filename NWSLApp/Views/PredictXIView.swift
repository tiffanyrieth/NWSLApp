//
//  PredictXIView.swift
//  NWSLApp
//
//  Predict the XI — Fan Zone game 1 (0.3.9, LIVE). Pushed from the Home "Play"
//  card, so it rides Home's NavigationStack (the nav-bar back button is the
//  explicit affordance), like DailyTriviaView and BracketBattleView.
//
//  Before a match you predict your followed team's starting XI (11 players), the
//  formation, and the final scoreline. A fixture is OPEN until kickoff − 2h; you
//  Save a draft and tweak it on team news, then Submit to lock it in (one-way — no
//  edits, and only a SUBMITTED prediction is ever scored). Once the match settles,
//  ESPN's real lineup auto-scores it Mastermind-style and it drops into Results.
//
//  Visual identity: the pink "matchday" accent (dsGamePredict), distinct from
//  Daily Trivia's indigo and Bracket Battle's teal. The slate + scoring derive in
//  PredictXIViewModel; durable predictions live in PredictionStore.
//

import SwiftUI

struct PredictXIView: View {
    @State private var viewModel = PredictXIViewModel()
    @Environment(PredictionStore.self) private var store
    @Environment(MatchStore.self) private var matches
    @Environment(ClubStore.self) private var clubs
    @Environment(FollowingStore.self) private var following
    @Environment(AuthStore.self) private var auth
    @Environment(AppRouter.self) private var router

    /// The fixture whose picker is open (nil = no sheet).
    @State private var activeFixture: PredictionFixture?
    // Fan Zone gate: tapping an open fixture requests sign-in + display name first; the
    // tapped fixture is stashed and opened only once authorized.
    @State private var gateRequested = false
    @State private var pendingFixture: PredictionFixture?
    /// The club the season card + board are showing (Competitive Redesign) — the team-filter chips switch
    /// it; defaults to the first board once loaded.
    @State private var selectedTeam: String?
    @State private var showHowTo = false
    /// The pushed screen, if any. Keyed by fixtureID rather than the item itself so the value stays
    /// cheap + Hashable and always resolves against the CURRENT store state.
    @State private var route: PredictRoute?
    /// Set once per appearance so the "one unseen result routes straight in" rule fires once and
    /// doesn't re-push after the user comes back.
    @State private var didAutoRoute = false

    private enum PredictRoute: Hashable {
        case result(String)   // fixtureID — the per-match reveal
        case locked(String)   // fixtureID — the locked wait
    }

    private let accent = Color.dsGamePredict

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading the slate…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            case .loaded:
                loadedContent
            }
        }
        .nativeBackButton(title: "Predict the XI")
        .background(Color.dsBgPrimary)
        .task {
            // Start Game Center auth here (a game screen) rather than at launch, so
            // the GC banner only shows when the user is about to play. Idempotent.
            GameCenterManager.shared.authenticate()
            if case .idle = viewModel.state { await reload() }
        }
        .sheet(item: $activeFixture) { fixture in
            XIPickerView(
                fixture: fixture,
                existing: store.prediction(for: fixture.id),
                // Pre-fill a fresh fixture from this team's last submitted XI (task 17). The VM ignores
                // it when an `existing` draft/submission is present, and gates every id on the live roster.
                savedLineup: store.lastLineup(forTeam: fixture.teamAbbreviation).map { ($0.formation, $0.slots) },
                accent: accent,
                homeAbbr: fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation,
                awayAbbr: fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation,
                loadRoster: { await viewModel.roster(forTeam: fixture.teamAbbreviation) },
                club: { viewModel.club(forAbbreviation: $0) }
            )
        }
        // Pushed, not presented: the results screen owns a reveal, a share affordance and a back
        // affordance, none of which sit well under a sheet's grabber. Browsable signed-out — no gate.
        .navigationDestination(item: $route) { destination(for: $0) }
        // Mandatory sign-in + display name to play — gated at the open-fixture tap, so the
        // picker's submit is always signed in. "Go back" cancels (returns to the slate).
        .fanZoneGate(isRequested: $gateRequested, gameName: "Predict the XI", accent: accent) {
            activeFixture = pendingFixture
        }
    }

    @ViewBuilder
    private func destination(for route: PredictRoute) -> some View {
        switch route {
        case .result(let fixtureID):
            if let item = viewModel.resultItems(store: store).first(where: { $0.fixture.id == fixtureID }) {
                PredictMatchResultView(
                    item: item,
                    viewModel: viewModel,
                    nextFixture: nextOpenFixture(excluding: fixtureID),
                    onPredictNext: { fixture in
                        self.route = nil
                        pendingFixture = fixture
                        gateRequested = true
                    })
            }
        case .locked(let fixtureID):
            // Search BOTH slates: a submitted prediction moves from `openItems` to `inFlightItems` at
            // kickoff, and looking only in `openItems` meant the locked screen silently failed to
            // resolve for a match in progress (blank push, no XI).
            let candidates = viewModel.openItems(store: store) + viewModel.inFlightItems(store: store)
            if let item = candidates.first(where: { $0.fixture.id == fixtureID }) {
                PredictLockedView(item: item, viewModel: viewModel)
            }
        }
    }

    /// The soonest fixture still open for prediction, for the results screen's closing CTA.
    private func nextOpenFixture(excluding fixtureID: String) -> PredictionFixture? {
        viewModel.openItems(store: store)
            .filter { $0.phase == .open && $0.fixture.id != fixtureID }
            .min { $0.fixture.kickoff < $1.fixture.kickoff }?
            .fixture
    }

    /// Results the user hasn't been shown yet, newest first.
    private var unseenResults: [PredictXIViewModel.PredictionItem] {
        viewModel.resultItems(store: store).filter { !store.hasSeenResult(fixtureID: $0.fixture.id) }
    }

    /// ⚠️ ROUTING RULE (mirrors The Bracket's show-results-once ladder):
    ///   0 unseen → the landing, untouched.
    ///   1 unseen → straight into that result, so the common single-club case never has to hunt for it.
    ///   2+       → stay on the landing; the rollup + NEW pills below let the user pick an order.
    ///              Playing three full reveals back to back would be 30+ seconds of animation.
    /// Fires only on entering PREDICT — never from Home or the Fan Zone, where a user who came to
    /// play The Bracket must not be ambushed by a Predict animation.
    private func autoRouteIfNeeded() {
        guard !didAutoRoute else { return }
        didAutoRoute = true
        let unseen = unseenResults
        guard unseen.count == 1, let only = unseen.first else { return }
        route = .result(only.fixture.id)
    }

    private func reload() async {
        // Self-sufficient: if this screen is reached before Home has populated the
        // shared stores (e.g. a cold deep-link), load them here so the slate isn't
        // empty. In the normal flow these are already `.loaded` and this no-ops.
        if case .idle = matches.state { await matches.load() }
        if case .idle = clubs.state { await clubs.load() }
        await viewModel.load(matches: matches, clubs: clubs, following: following, store: store, auth: auth)
        // Record each team's rank so the season card can show "↑ N since last match" (advances only when a
        // NEW match has scored — see PredictionStore.recordRankSnapshot).
        for (team, standing) in viewModel.standingByTeam {
            if let rank = standing.rank { store.recordRankSnapshot(team: team, currentRank: rank) }
        }
        if selectedTeam == nil { selectedTeam = viewModel.leaderboards.first?.team }
        // Keep the local seen/upload markers bounded — the recent-results window is the only thing
        // that can render them, so anything older has no reader (the local twin of the pg_cron sweep).
        store.pruneStaleMarkers(currentWeek: FanZoneCadence.currentSoccerWeek())
        consumePendingPredictResult()   // a post-match push tap targets a specific result — honor it first
        autoRouteIfNeeded()
    }

    /// A tapped post-match "your result is in" push (Change 8) routed here via `router.pendingPredictEventID`.
    /// Resolve that ESPN event id to its scored result and open it directly — even if already seen (the
    /// user chose to look). One item per event for a given user (they predict one team per fixture).
    private func consumePendingPredictResult() {
        guard let eventID = router.pendingPredictEventID else { return }
        router.pendingPredictEventID = nil
        if let item = viewModel.resultItems(store: store).first(where: { $0.fixture.eventID == eventID }) {
            route = .result(item.fixture.id)
            didAutoRoute = true   // don't let autoRouteIfNeeded override the deep-linked target
        }
    }

    // MARK: - Loaded

    private var loadedContent: some View {
        let teams = viewModel.leaderboards.map(\.team)
        let selected = selectedTeam ?? teams.first
        return ScrollView {
            VStack(spacing: 18) {
                if let selected {
                    // Returning player: a single optional personal line under the username — a genuine
                    // streak / personal best / climb, or nothing (the common case). No ranking GATE any
                    // more (recency-to-remain, 2026-08-04): you're on the board from your first prediction,
                    // so there's no "N more to rank" milestone to show. The season-average card is gone —
                    // standing lives in the board below.
                    if let line = hubStatusLine(team: selected) { statusLineView(line) }
                } else {
                    // First-timer (no board yet): the explainer header.
                    headerCard
                    rankedCallout
                }

                // Three buckets by lifecycle (owner categorization, 2026-08-04): OPEN FOR PREDICTIONS
                // (still editable) leads because it's the only actionable one, then LOCKED IN (submitted,
                // pre-kickoff or underway), then RESULTS. A `.closed` fixture — one you never submitted
                // before the deadline — is DROPPED entirely (it used to sit here as "Submissions closed",
                // which read as a nag for a match you'd chosen to skip).
                let allOpen = viewModel.openItems(store: store)
                let openForPredictions = allOpen.filter { $0.phase == .open }
                let lockedWaiting = allOpen.filter { $0.phase == .submitted }   // submitted here, pre-kickoff
                // Predicted on ANOTHER device (server mark, no local XI) — locked, grouped with waiting.
                let submittedElsewhere = allOpen.filter { $0.phase == .submittedElsewhere }
                let lockedInFlight = viewModel.inFlightItems(store: store)      // submitted, underway
                let lockedIn = lockedInFlight + lockedWaiting + submittedElsewhere  // live, waiting, elsewhere
                let results = viewModel.resultItems(store: store)

                if openForPredictions.isEmpty && lockedIn.isEmpty && results.isEmpty {
                    emptyState
                }

                if !openForPredictions.isEmpty {
                    sectionLabel("Open for predictions")
                    ForEach(openForPredictions) { openItemCard($0) }
                }

                // Locked in — a lock icon on the header + a slight dim on the WAITING cards signal "nothing
                // to do here". An underway card stays full opacity: it's live, the most dynamic thing on
                // screen, and before its section existed it vanished entirely at kickoff (see `inFlightItems`).
                if !lockedIn.isEmpty {
                    sectionLabel("Locked in", systemImage: "lock.fill")
                    ForEach(lockedIn) { openItemCard($0, dimmed: !$0.isUnderway) }
                }

                if !results.isEmpty {
                    // The round rollup sits ABOVE the existing list rather than beside it as a
                    // separate screen: the shipped "Recent results" section already spans every
                    // followed club, so a parallel list would be two renderings of the same results.
                    // What was missing was the rollup, the NEW treatment, and the routing.
                    roundRollup(results)
                    sectionLabel(unseenResults.isEmpty
                                 ? "Recent results"
                                 : "\(unseenResults.count) new to review")
                    ForEach(results) { resultCard($0) }
                }

                if let selected { selectedTeamBoard(team: selected) }

                if selected != nil { howToPlayRow }
            }
            .padding(20)
            .fanZonePlayingAsHeader(accent: accent)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "sportscourt.fill")
                .dsFont(28, weight: .bold)
                .foregroundStyle(accent)
            Text("PREDICT THE XI")
                .dsFont(12, weight: .bold)
                .tracking(1.5)
                .foregroundStyle(accent)
            Text("Call the lineup.")
                .dsFont(26, weight: .heavy)
                .foregroundStyle(Color.dsFgPrimary)
                .multilineTextAlignment(.center)
            Text("Pick your team's starting XI, formation, and final score before kickoff. Save a draft, tweak it on team news, then submit to lock it in — submissions close 2 hours before kickoff.")
                .dsFont(15)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // First-timer hero: a CTA, not a stat. No "season points" — the board runs on averages, and a
            // new player has nothing to show (this is the no-board-yet explainer).
            Text("Make your first prediction")
                .dsFont(15, weight: .semibold)
                .foregroundStyle(accent)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [accent.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous)
        )
        .background(Color.dsMdCard, in: RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }

    // The competitive signal: this is a ranked, per-club leaderboard game (like Bracket's).
    private var rankedCallout: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .dsFont(20)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ranked game")
                    .dsFont(16, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                Text("Score your picks against every fan of your club. Track your accuracy in Your Stats.")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard, in: RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous)
                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
        )
    }

    private func sectionLabel(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).dsFont(13, weight: .bold).foregroundStyle(Color.dsFgSecondary)
            }
            Text(text).dsFont(16, weight: .bold).foregroundStyle(Color.dsFgSecondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .dsFont(34)
                .foregroundStyle(Color.dsFgSecondary)
            if let opening = viewModel.nextOpening {
                // The PAUSED state (an international break): the game isn't broken, the league is
                // resting — say when it comes back. Boards below stay browsable throughout (owner
                // rule: the card/screen never hide just because a week has no fixtures).
                Text("No NWSL matches this week")
                    .dsFont(17, weight: .semibold)
                Text("Predictions for \(viewModel.teamLabel(opening.team))'s next match open \(Self.pausedDateFormatter.string(from: max(opening.opensAt, Date()))).")
                    .dsFont(16)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No upcoming matches to predict")
                    .dsFont(17, weight: .semibold)
                Text("Follow a team with a fixture coming up and it'll appear here to predict.")
                    .dsFont(16)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// "9:00 PM" — the kickoff TIME alone, matching the schedule card's centre column. The day
    /// belongs to the surrounding context (the card sits under "Open for predictions", and the lock
    /// line below names the day), so repeating it here only crowded the column.
    private static let kickoffTimeFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current; f.dateFormat = "h:mm a"; return f
    }()

    private static func kickoffTimeLabel(_ date: Date) -> String {
        kickoffTimeFormatter.string(from: date)
    }

    /// "Jun 12" — the paused state's reopen date.
    private static let pausedDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"; return f
    }()

    // MARK: - Open fixture card

    private func openItemCard(_ item: PredictXIViewModel.PredictionItem, dimmed: Bool = false) -> some View {
        let fixture = item.fixture
        let colors = fixtureColors(fixture)
        return Button {
            // A SUBMITTED entry goes to the locked wait, not back into the picker. Reopening a
            // read-only picker was the old behaviour and it's why the hours after submitting felt
            // empty: there was nowhere for a locked-in prediction to live.
            if item.phase == .submitted {
                route = .locked(fixture.id)
            } else if item.phase == .open {
                pendingFixture = fixture
                gateRequested = true
            }
            // .submittedElsewhere / .closed: no action — there's no local XI to open (see `.disabled`).
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // An underway match shows the live scoreline instead of its kickoff time — it already
                // kicked off, so "9:00 PM" would read as though it hadn't.
                matchHeader(fixture, finalScore: item.isUnderway ? item.finalScore : nil,
                            isLive: item.isUnderway, isSuspended: item.isSuspended)

                openStatusRow(item)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Two-team club-color wash over the navy card — the schedule/match-detail treatment.
            .background { TeamWashBackground(base: .dsMdCard, home: colors.home, away: colors.away) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // A waiting locked-in card reads as "done, nothing to do" — a slight dim without deadening it.
            .opacity(dimmed ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .disabled(item.phase == .closed || item.phase == .submittedElsewhere)
    }

    @ViewBuilder
    private func openStatusRow(_ item: PredictXIViewModel.PredictionItem) -> some View {
        switch item.phase {
        case .open:
            let count = item.prediction?.slots.count ?? 0
            statusRow(
                icon: count == 0 ? "plus.circle.fill" : "pencil.circle.fill",
                tint: accent,
                title: count == 0 ? "Make your prediction" : "Draft · \(count)/11 picked — tap to continue",
                subtitle: "Locks \(Self.deadlineLabel(item.fixture.deadline))"
            )
        case .submitted:
            statusRow(
                icon: item.isSuspended ? "exclamationmark.triangle.fill"
                    : (item.isUnderway ? "dot.radiowaves.left.and.right" : "checkmark.seal.fill"),
                tint: accent,
                title: "Locked in — \(item.prediction?.formation ?? "")  ·  \(scoreGuessLabel(item))",
                // Underway: "see how the club is picking" was pre-deadline copy and read as though
                // there were still something to do. Say where it actually stands.
                subtitle: item.isSuspended
                    ? "Match suspended · your score posts once it finishes."
                    : (item.isUnderway
                       ? "Match underway · your score posts after full time."
                       : "Submitted · see how the club is picking.")
            )
        case .closed:
            statusRow(
                icon: "lock.fill",
                tint: .secondary,
                title: "Submissions closed",
                subtitle: "You didn't submit in time for this one."
            )
        case .submittedElsewhere:
            statusRow(
                icon: "checkmark.seal.fill",
                tint: accent,
                title: "Prediction already made",
                subtitle: "You made this on another device. Your XI isn't stored here, so it can't be shown."
            )
        case .scored:
            EmptyView()
        }
    }

    private func statusRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(16, weight: .semibold)
                Text(subtitle).dsFont(13).foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").dsFont(13).foregroundStyle(.tertiary)
        }
    }

    private func scoreGuessLabel(_ item: PredictXIViewModel.PredictionItem) -> String {
        guard let p = item.prediction else { return "" }
        return "\(p.homeScoreGuess)–\(p.awayScoreGuess)"
    }

    // MARK: - Round rollup

    /// The round's headline across every followed club. Only shown once there are 2+ results in the
    /// round — for a single match the card below already says everything, and a "rollup" of one is
    /// just the same number twice.
    @ViewBuilder
    private func roundRollup(_ results: [PredictXIViewModel.PredictionItem]) -> some View {
        let week = FanZoneCadence.currentSoccerWeek()
        let inRound = results.filter { $0.score?.soccerWeek != nil && $0.score?.soccerWeek == week }
        if inRound.count >= 2 {
            let starters = inRound.reduce(0) { $0 + ($1.score?.correctPlayers ?? 0) }
            let points = inRound.reduce(0) { $0 + ($1.score?.total ?? 0) }
            let clubs = Set(inRound.map { $0.fixture.teamAbbreviation })
            let improved = clubs.filter { (store.rankMovement(forTeam: $0) ?? 0) > 0 }.count
            let superlative = PredictSuperlative.forRound(.init(
                startersCalled: starters,
                previousBestStarters: store.seasonBests.hasRoundBaseline ? store.seasonBests.bestRoundStarters : nil,
                clubsImproved: improved,
                clubsScored: clubs.count))

            VStack(spacing: 6) {
                Text("THIS ROUND\(week.flatMap { FanZoneCadence.weekLabel(week: $0) }.map { " · \($0.uppercased())" } ?? "")")
                    .dsFont(12, weight: .bold).tracking(1.2).foregroundStyle(accent)
                // Starters called is the hero here too; points are the supporting line.
                Text("\(starters) of \(inRound.count * 11)")
                    .dsFont(34, weight: .heavy, monospacedDigit: true).foregroundStyle(Color.dsFgPrimary)
                Text("starters called · +\(points) pts across \(inRound.count) matches")
                    .dsFont(15).foregroundStyle(Color.dsFgSecondary)
                if let superlative {
                    Text(superlative).dsFont(13, weight: .bold).foregroundStyle(accent)
                }
                if let contribution = predictSuperfanLine {
                    Text(contribution).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                }
                // ⚠️ Load-bearing copy, not decoration: points DO aggregate (they're league-wide) but
                // ranks do NOT (each club board has its own population). Without this line the card's
                // combined total sitting above per-club movements reads as one merged standing.
                Text("Points are league-wide. Ranks are per club — each board is scored separately.")
                    .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18).padding(.horizontal, 16)
            .background {
                LinearGradient(colors: [accent.opacity(0.15), Color.dsMdCard],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1))
        }
    }

    /// Predict's contribution to the Superfan score, derived LOCALLY from the store (Σ correct /
    /// Σ 11 × scored matches) — the same numerator and denominator `SuperfanCounts` uses, so no extra
    /// fetch and no chance of the two disagreeing. nil until something has been scored.
    private var predictSuperfanLine: String? {
        var correct = 0, matches = 0
        for (key, score) in store.scores {
            guard store.prediction(for: key) != nil else { continue }
            correct += score.correctPlayers
            matches += 1
        }
        guard matches > 0 else { return nil }
        let accuracy = Double(correct) / Double(matches * 11)
        return String(format: "Predict → Superfan · %.0f%% season accuracy · %.1f of 25",
                      accuracy * 100, accuracy * 25)
    }

    // MARK: - Result card

    /// Compact recent-result card (Batch 3): crests + FT, your total, a one-line summary, and "See details ›"
    /// → the full per-match breakdown (predicted vs actual XI). The heavy inline breakdown moved to the
    /// detail sheet so the landing stays scannable.
    private func resultCard(_ item: PredictXIViewModel.PredictionItem) -> some View {
        let score = item.score ?? .zero
        let colors = fixtureColors(item.fixture)
        let isUnseen = !store.hasSeenResult(fixtureID: item.fixture.id)
        return Button { route = .result(item.fixture.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                matchHeader(item.fixture, finalScore: item.finalScore)
                HStack(spacing: 8) {
                    // Starters called leads; points + round rank follow on the card now (game-feel pass),
                    // so the user sees their result without tapping in.
                    Text("\(score.correctPlayers) of 11 starters").dsFont(16, weight: .bold).foregroundStyle(accent)
                    Text("+\(score.total) pts").dsFont(15, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
                    if isUnseen {
                        Text("NEW")
                            .font(.system(size: 9, weight: .black)).tracking(0.6)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accent.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Text("See details").dsFont(15, weight: .semibold)
                        Image(systemName: "chevron.right").dsFont(13, weight: .bold)
                    }
                    .foregroundStyle(accent)
                }
                // Round rank — cached once the user has opened the result (network-only otherwise), so it
                // shows on a reviewed result, omitted (never faked) before then.
                if let rank = store.roundRank(forFixture: item.fixture.id) {
                    Text("\(ordinal(rank)) this round").dsFont(13, weight: .bold).foregroundStyle(accent)
                }
                Text(resultSummaryLine(score)).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                if let movement = rankMovementLine(for: item) {
                    Text(movement.text).dsFont(13, weight: .semibold).foregroundStyle(movement.color)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { TeamWashBackground(base: .dsMdCard, home: colors.home, away: colors.away) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // An unseen result reads as NEW, not as history.
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isUnseen ? accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Per-CLUB rank movement for a result row.
    ///
    /// ⚠️ Ranks never aggregate across clubs. Washington #12→#8 and Angel City #34→#31 are different
    /// boards with different populations, so each row carries its own club's movement and there is
    /// deliberately no combined rank or combined delta anywhere on this screen.
    private func rankMovementLine(for item: PredictXIViewModel.PredictionItem) -> (text: String, color: Color)? {
        let team = item.fixture.teamAbbreviation
        guard let delta = store.rankMovement(forTeam: team), delta != 0 else { return nil }
        let name = viewModel.teamLabel(team)
        return delta > 0
            ? ("\(name): ↑\(delta) since your last scored match", .dsSuccess)
            : ("\(name): ↓\(abs(delta)) since your last scored match", .dsError)
    }

    /// The one-line summary on a recent-result card: "8/11 starters · formation ✓ · score ✗".
    private func resultSummaryLine(_ s: PredictionScore) -> String {
        "\(s.correctPlayers)/11 starters · formation \(s.formationCorrect ? "✓" : "✗") · score \(s.exactScoreline ? "✓" : "✗")"
    }

    // MARK: - Shared match header

    /// `isLive` distinguishes an UNDERWAY scoreline from a finished one. Without it the header
    /// labelled every non-nil score "FT", so a match in progress read as full-time — the wrong-but-
    /// plausible kind of wrong that's worse than showing nothing.
    private func matchHeader(_ fixture: PredictionFixture, finalScore: (home: Int, away: Int)?,
                             isLive: Bool = false, isSuspended: Bool = false) -> some View {
        let homeAbbr = fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation
        let awayAbbr = fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation
        return HStack(spacing: 12) {
            teamColumn(homeAbbr, color: teamColor(homeAbbr))
            // The centre column mirrors the SCHEDULE card (MatchCard): a small tracked "KICKOFF"
            // eyebrow over a large cyan time. The old version read "VS" over a jammed
            // "Wed, Jul 29 · 9:00 PM" that wrapped into two cramped lines — and "vs" is redundant
            // when two crests already flank it. The date lives on the section/label context; what a
            // fan needs here is the time, at a glance.
            VStack(spacing: 4) {
                if let final = finalScore {
                    Text("\(final.home)–\(final.away)").dsFont(20, weight: .heavy)
                    Text(isSuspended ? "SUSP" : (isLive ? "LIVE" : "FT"))
                        .dsFont(13, weight: .bold)
                        .foregroundStyle(isSuspended ? Color.dsWarning
                                         : (isLive ? Color.dsStateLive : Color.dsStateFinal))
                } else {
                    Text("KICKOFF")
                        .dsFont(12, weight: .bold).tracking(0.6)
                        .foregroundStyle(Color.dsStateKickoff)
                    Text(Self.kickoffTimeLabel(fixture.kickoff))
                        .dsFont(22, weight: .bold, design: .rounded, monospacedDigit: true)
                        .foregroundStyle(Color.dsStateKickoff)
                        // At larger text the time would outgrow the column and clip ("9:00…").
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(minWidth: 96)
            teamColumn(awayAbbr, color: teamColor(awayAbbr))
        }
        .frame(maxWidth: .infinity)
    }

    private func teamColumn(_ abbreviation: String, color: Color) -> some View {
        VStack(spacing: 6) {
            TeamLogo(urlString: viewModel.club(forAbbreviation: abbreviation)?.logoURL, teamAbbreviation: abbreviation, size: 38)
            // Abbreviation in the club's color — the crest+abbreviation two-team rule (matches MatchCard).
            Text(abbreviation).dsFont(13, weight: .bold).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Team-color resolution (navy Competitive surface → liftOnDark)

    private func teamColor(_ abbreviation: String) -> Color {
        Color.teamColor(for: abbreviation, liftOnDark: true, fallback: .dsFgSecondary)
    }

    private func fixtureColors(_ fixture: PredictionFixture) -> (home: Color, away: Color) {
        let homeAbbr = fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation
        let awayAbbr = fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation
        return (teamColor(homeAbbr), teamColor(awayAbbr))
    }

    // MARK: - Leaderboard (REAL, per-team — you're ranked among fans of YOUR club)

    /// Which clock each team's standings card shows (the comp arena's two clocks —
    /// owner design ruling: this round AND the season, tab-switchable).
    @State private var boardClock: [String: BoardClock] = [:]
    private enum BoardClock: String { case round, season }

    /// One standings card per team you're predicting or have scored in. Empty (shows
    /// nothing) when you have no active/scored team — the screen's own empty state
    /// covers the no-activity case.
    // MARK: - Streak & milestone line (game-feel pass)

    /// The single contextual line under the username — a genuine personal best / hot streak / climb,
    /// or nil (the common case). Pure resolver in `PredictStreakLine`; inputs are all locally held
    /// (recent scored results, the season high-water mark, the store's persisted rank movement).
    private var streakResult: PredictStreakLine.Result? {
        let recent = viewModel.resultItems(store: store).map {
            PredictStreakLine.Match(kickoff: $0.fixture.kickoff, starters: $0.score?.correctPlayers ?? 0)
        }
        // The strongest upward move across the boards on screen (movement is per-club — never merged).
        let climb = viewModel.leaderboards.compactMap { board -> PredictStreakLine.Climb? in
            guard let delta = store.rankMovement(forTeam: board.team), delta > 0 else { return nil }
            return PredictStreakLine.Climb(delta: delta, teamLabel: viewModel.teamLabel(board.team))
        }.max(by: { $0.delta < $1.delta })
        return PredictStreakLine.resolve(
            recent: recent,
            bestMatchStarters: store.seasonBests.bestMatchStarters,
            hasMatchBaseline: store.seasonBests.hasMatchBaseline,
            bestClimb: climb)
    }

    /// The single contextual line under the username, for the SELECTED team: a genuine streak /
    /// personal best / climb, or nil (the common case). No ranking gate any more — recency-to-remain
    /// ranks you from your first prediction, so there's no "progress to rank" or "you're now ranked!"
    /// milestone to surface (both were the removed Update #1 3-match machinery). The `team` argument is
    /// kept for call-site symmetry with the board selection, though the streak resolver spans all boards.
    private func hubStatusLine(team: String) -> (icon: String, text: String)? {
        if let streak = streakResult { return (streak.icon, streak.text) }
        return nil
    }

    private func statusLineView(_ line: (icon: String, text: String)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: line.icon).dsFont(15).foregroundStyle(accent)
            Text(line.text).dsFont(15, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "↑ N since last match" / "↓ N …" — nil when there's no movement to show (no prior match, or no change).
    private func predictMovementText(_ delta: Int?) -> (text: String, color: Color)? {
        guard let delta, delta != 0 else { return nil }
        return delta > 0
            ? ("↑ \(delta) since last match", .dsSuccess)
            : ("↓ \(-delta) since last match", .dsError)
    }

    /// Team-filter tabs — only shown when the user follows/predicts 2+ clubs. Live in the leaderboard
    /// HEADER now (game-feel pass), so it's obvious they switch which club's board you're looking at.
    private func teamChips(teams: [String], selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(teams, id: \.self) { team in
                    let on = team == selected
                    Button { selectedTeam = team } label: {
                        Text(team).dsFont(13, weight: .bold)
                            .foregroundStyle(on ? teamColor(team) : Color.dsFgSecondary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(on ? teamColor(team).opacity(0.22) : Color.dsBgTertiary, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? teamColor(team).opacity(0.5) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    /// The selected club's leaderboard (only — the chips switch clubs, rather than stacking every board).
    @ViewBuilder
    private func selectedTeamBoard(team: String) -> some View {
        if let board = viewModel.leaderboards.first(where: { $0.team == team }) {
            teamLeaderboardCard(team: team, seasonRows: board.rows,
                                round: viewModel.roundBoards.first { $0.team == team })
        }
    }

    /// Collapsed "How to play" (rules-last for returning players) — expands the game explainer.
    private var howToPlayRow: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showHowTo.toggle() } } label: {
                HStack {
                    Text("How to play").dsFont(15, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
                    Spacer()
                    Image(systemName: showHowTo ? "chevron.up" : "chevron.right").dsFont(15).foregroundStyle(Color.dsFgTertiary)
                }
                .padding(14)
                .contentShape(Rectangle())   // Fix 4 — the Spacer's middle is a dead zone without this
            }
            .buttonStyle(.plain)
            if showHowTo {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick your team's starting XI, formation, and final score before kickoff. Save a draft, tweak it on team news, then submit to lock it in — submissions close 2 hours before kickoff.")
                        .dsFont(15).foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("HOW POINTS WORK").dsFont(12, weight: .bold).tracking(0.8).foregroundStyle(accent)
                    VStack(spacing: 6) {
                        predictPointRow("Each correct starter", "+\(PredictionScore.playerPoints)")
                        predictPointRow("Right position band for a correct pick", "+\(PredictionScore.positionPoints)")
                        predictPointRow("Correct formation", "+\(PredictionScore.formationPointsValue)")
                        predictPointRow("Exact final score", "+\(PredictionScore.scorelinePointsValue)")
                        predictPointRow("Right result (win / draw / loss)", "+\(PredictionScore.resultPointsValue)")
                        predictPointRow("Perfect XI — all 11 right", "+\(PredictionScore.perfectPointsValue)")
                        Divider().overlay(Color.dsFgQuaternary)
                        predictPointRow("Most possible in one match", "\(PredictionScore.maxPerMatch) pts", bold: true)
                    }

                    // Fix 6 — the two score-related lines are easy to confuse, so spell out the difference.
                    Text("Right result vs exact score: \u{201C}right result\u{201D} (+3) just means you called the winner or a draw — say WAS win and they win 3\u{2013}1, you get it. \u{201C}Exact score\u{201D} (+10) means you nailed the actual scoreline, like calling 2\u{2013}1 and it finishing 2\u{2013}1. They stack — an exact score is always the right result too, so it banks both.")
                        .dsFont(13).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)

                    Text("Points build up across every match you predict all season, and you're ranked on a per-club leaderboard — by your average score per match, against other fans of your team, not the whole league.")
                        .dsFont(15).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)
                    Text("Your season accuracy — correct player picks out of every XI slot you've predicted — feeds up to 25 of your 100 Superfan points.")
                        .dsFont(15).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)
                    // Points a returning player at the opt-in that replaced the old post-submit popup (task 16).
                    Text("Want a heads-up when your results land? Turn on \u{201C}Predict results\u{201D} in Notifications and we'll let you know the morning after each match.")
                        .dsFont(15).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
            }
        }
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One "how points work" row for the Predict rules (label — value). Values are READ FROM
    /// `PredictionScore`'s weight constants, not transcribed (Batch-2 Fix 4B wanted "rules match the
    /// scorer, not a guess"; since 2026-07-28 they cannot disagree at all). This screen is a
    /// published contract — logic gate #7 — so a scoring change must move this text with it.
    private func predictPointRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).dsFont(15, weight: bold ? .semibold : .regular)
                .foregroundStyle(bold ? Color.dsFgPrimary : Color.dsFgSecondary)
            Spacer(minLength: 8)
            Text(value).dsFont(15, weight: .bold).foregroundStyle(accent)
        }
    }

    private func teamLeaderboardCard(
        team: String, seasonRows: [PredictXIViewModel.LeaderboardRow],
        round: (team: String, week: Int, weekLabel: String, rows: [PredictXIViewModel.LeaderboardRow])?
    ) -> some View {
        // Default to the ROUND clock when a round board exists (the fresh "did I beat them this
        // week" read); season otherwise. The user's tab choice sticks per team for the session.
        let clock = boardClock[team] ?? (round != nil ? .round : .season)
        let rows = (clock == .round ? round?.rows : nil) ?? seasonRows
        // Fix 9 — the LANDING board is a compact preview: top 10 + your own row (owner: not the deep list).
        // If you're outside the top 10, append your row under a divider so the jump reads honestly (reusing
        // the below-fold treatment). The service still fetches up to `visibleLimit`; we just render the head.
        let landingRows: [PredictXIViewModel.LeaderboardRow] = {
            let top = Array(rows.prefix(10))
            guard let you = rows.first(where: { $0.isYou }), !top.contains(where: { $0.isYou }) else { return top }
            var youRow = you
            youRow.isBelowFold = true
            return top + [youRow]
        }()
        let allTeams = viewModel.leaderboards.map(\.team)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TeamLogo(urlString: viewModel.club(forAbbreviation: team)?.logoURL, teamAbbreviation: team, size: 22)
                Text(viewModel.teamLabel(team)).dsFont(17, weight: .semibold)
                Spacer()
                Text("Leaderboard").dsFont(13).foregroundStyle(Color.dsFgSecondary)
            }
            // Team tabs moved into the header (game-feel pass) — obvious they switch the board's club.
            if allTeams.count >= 2 { teamChips(teams: allTeams, selected: team) }
            if let round {
                // The two clocks. "This round" carries the honest date-range label (never a
                // week NUMBER — ESPN has no NWSL matchweek numbering to match).
                HStack(spacing: 8) {
                    clockTab("This round", detail: round.weekLabel,
                             isOn: clock == .round) { boardClock[team] = .round }
                    clockTab("Season", detail: nil,
                             isOn: clock == .season) { boardClock[team] = .season }
                    Spacer()
                }
            }
            // Your own rank movement since your last scored match — SEASON clock only (the round board
            // is a single week, where a "since last match" delta has no meaning). The chase-to-next line
            // was removed 2026-08-04: it leaned competitive/gamer, against the low-entry-fun vibe.
            if clock == .season, let movement = predictMovementText(store.rankMovement(forTeam: team)) {
                Text(movement.text).dsFont(13, weight: .bold).foregroundStyle(movement.color)
            }
            ForEach(landingRows) { row in
                // A below-fold "You" row means you rank past the visible top — separate it
                // with a divider so the jump from #10 to your real rank reads honestly.
                if row.isBelowFold {
                    Divider().overlay(Color.secondary.opacity(0.4))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                }
                HStack(spacing: 12) {
                    Text("\(row.rank)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(row.isYou ? accent : .secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text(row.name)
                        .dsFont(16, weight: row.isYou ? .bold : .regular)
                        .foregroundStyle(row.isYou ? accent : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    // Season board ranks by AVERAGE per match; the round board shows the week's raw
                    // points. The match count that used to sit under the average was removed
                    // 2026-07-28 — see the season card for the reasoning. `LeaderboardRow.matches`
                    // is still fetched (it derives the average server-side); it just isn't displayed.
                    if let avg = row.avg {
                        Text(String(format: "%.1f avg", avg))
                            .dsFont(16, weight: .semibold).foregroundStyle(row.isYou ? accent : .secondary)
                    } else {
                        Text("\(row.points) pts").dsFont(16, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(row.isYou ? accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            // Honest empty/sparse state. Everyone ranks from their first prediction now (recency-to-remain,
            // 2026-08-04), so an empty board means nobody has predicted this club's XI in the recency
            // window yet — not that a threshold is unmet.
            if rows.isEmpty {
                Text("No predictors yet — predict this club's XI to start the board.")
                    .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                    .padding(.horizontal, 10).padding(.top, 2)
            } else if rows.count == 1, rows.first?.isYou == true {
                Text("You're first in line — standings grow as more fans play.")
                    .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                    .padding(.horizontal, 10).padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Quiet single-team tint — this board is fans of ONE club, so it wears that club's color.
        .background { TeamWashBackground(base: .dsMdCard, home: teamColor(team)) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// One clock tab ("This round · Jun 22–28" / "Season") — a small segmented affordance in the
    /// board header, accent-filled when active (mirrors the Bracket leaderboard's two-tab read).
    private func clockTab(_ title: String, detail: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).dsFont(13, weight: .semibold)
                if let detail { Text(detail).dsFont(13).opacity(0.8) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isOn ? accent.opacity(0.2) : Color.dsBgTertiary.opacity(0.5))
            .foregroundStyle(isOn ? accent : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// "3rd" — ordinal for the recent-result card's round rank.
    private func ordinal(_ n: Int) -> String {
        let ones = n % 10, tens = (n / 10) % 10
        let suffix: String
        if tens == 1 { suffix = "th" }
        else { switch ones { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" } }
        return "\(n)\(suffix)"
    }

    // NOTE: there is deliberately no "Reset predictions" button here. One shipped from #47 as a dev
    // replay convenience, ungated by #if DEBUG, and reached TestFlight. It wiped the local prediction
    // history on a single tap with no confirmation, while leaving the server's `prediction_scores`
    // untouched — so the season card fell back to "Predict …'s XI to join the board" while the
    // leaderboard directly below still showed the user ranked on it. Don't re-add it.

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) { await reload() }
    }

    // MARK: - Date labels

    /// "Sat, Jul 4 · 7:30 PM" — kickoff in the user's local zone.
    static func kickoffLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f.string(from: date)
    }

    /// The submission deadline, phrased for the open-card subtitle.
    static func deadlineLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "EEE h:mm a"
        return f.string(from: date)
    }
}
