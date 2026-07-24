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
    /// A scored match tapped in Recent Results → the per-match detail sheet (Batch 3).
    @State private var detailItem: PredictXIViewModel.PredictionItem?

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
                accent: accent,
                homeAbbr: fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation,
                awayAbbr: fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation,
                loadRoster: { await viewModel.roster(forTeam: fixture.teamAbbreviation) },
                club: { viewModel.club(forAbbreviation: $0) }
            )
        }
        // The per-match result detail (Batch 3), browsable signed-out — no gate.
        .sheet(item: $detailItem) { item in
            PredictMatchResultView(item: item, viewModel: viewModel)
        }
        // Mandatory sign-in + display name to play — gated at the open-fixture tap, so the
        // picker's submit is always signed in. "Go back" cancels (returns to the slate).
        .fanZoneGate(isRequested: $gateRequested, gameName: "Predict the XI", accent: accent) {
            activeFixture = pendingFixture
        }
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
    }

    // MARK: - Loaded

    private var loadedContent: some View {
        let teams = viewModel.leaderboards.map(\.team)
        let selected = selectedTeam ?? teams.first
        return ScrollView {
            VStack(spacing: 18) {
                if let selected {
                    // Returning: competitive identity first (season card + team chips), rules last.
                    seasonCard(team: selected)
                    if teams.count >= 2 { teamChips(teams: teams, selected: selected) }
                } else {
                    // First-timer (no board yet): the explainer header.
                    headerCard
                    rankedCallout
                }

                let open = viewModel.openItems(store: store)
                let results = viewModel.resultItems(store: store)

                if open.isEmpty && results.isEmpty {
                    emptyState
                }

                if !open.isEmpty {
                    sectionLabel("Open for predictions")
                    ForEach(open) { openItemCard($0) }
                }

                if !results.isEmpty {
                    sectionLabel("Recent results")
                    ForEach(results) { resultCard($0) }
                }

                if let selected { selectedTeamBoard(team: selected) }

                if selected != nil { howToPlayRow }

                if store.hasPredicted {
                    resetButton
                }
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
                .dsFont(14)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(store.seasonPoints) season points")
                .dsFont(13, weight: .semibold)
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
                    .dsFont(15, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                Text("Score your picks against every fan of your club. Track your accuracy in Your Stats.")
                    .dsFont(13)
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

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).dsFont(15, weight: .bold).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .dsFont(34)
                .foregroundStyle(.secondary)
            if let opening = viewModel.nextOpening {
                // The PAUSED state (an international break): the game isn't broken, the league is
                // resting — say when it comes back. Boards below stay browsable throughout (owner
                // rule: the card/screen never hide just because a week has no fixtures).
                Text("No NWSL matches this week")
                    .dsFont(17, weight: .semibold)
                Text("Predictions for \(viewModel.teamLabel(opening.team))'s next match open \(Self.pausedDateFormatter.string(from: max(opening.opensAt, Date()))).")
                    .dsFont(15)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No upcoming matches to predict")
                    .dsFont(17, weight: .semibold)
                Text("Follow a team with a fixture coming up and it'll appear here to predict.")
                    .dsFont(15)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// "Jun 12" — the paused state's reopen date.
    private static let pausedDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MMM d"; return f
    }()

    // MARK: - Open fixture card

    private func openItemCard(_ item: PredictXIViewModel.PredictionItem) -> some View {
        let fixture = item.fixture
        let colors = fixtureColors(fixture)
        return Button {
            pendingFixture = fixture
            gateRequested = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                matchHeader(fixture, finalScore: nil)

                openStatusRow(item)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Two-team club-color wash over the navy card — the schedule/match-detail treatment.
            .background { TeamWashBackground(base: .dsMdCard, home: colors.home, away: colors.away) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(item.phase == .closed)
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
                icon: "checkmark.seal.fill",
                tint: accent,
                title: "Locked in — \(item.prediction?.formation ?? "")  ·  \(scoreGuessLabel(item))",
                subtitle: "Submitted · awaiting the result. Tap to review."
            )
        case .closed:
            statusRow(
                icon: "lock.fill",
                tint: .secondary,
                title: "Submissions closed",
                subtitle: "You didn't submit in time for this one."
            )
        case .scored:
            EmptyView()
        }
    }

    private func statusRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(15, weight: .semibold)
                Text(subtitle).dsFont(12).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").dsFont(12).foregroundStyle(.tertiary)
        }
    }

    private func scoreGuessLabel(_ item: PredictXIViewModel.PredictionItem) -> String {
        guard let p = item.prediction else { return "" }
        return "\(p.homeScoreGuess)–\(p.awayScoreGuess)"
    }

    // MARK: - Result card

    /// Compact recent-result card (Batch 3): crests + FT, your total, a one-line summary, and "See details ›"
    /// → the full per-match breakdown (predicted vs actual XI). The heavy inline breakdown moved to the
    /// detail sheet so the landing stays scannable.
    private func resultCard(_ item: PredictXIViewModel.PredictionItem) -> some View {
        let score = item.score ?? .zero
        let colors = fixtureColors(item.fixture)
        return Button { detailItem = item } label: {
            VStack(alignment: .leading, spacing: 12) {
                matchHeader(item.fixture, finalScore: item.finalScore)
                HStack(spacing: 8) {
                    Text("\(score.total) / 88 pts").dsFont(16, weight: .bold).foregroundStyle(accent)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("See details").dsFont(13, weight: .semibold)
                        Image(systemName: "chevron.right").dsFont(11, weight: .bold)
                    }
                    .foregroundStyle(accent)
                }
                Text(resultSummaryLine(score)).dsFont(12).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { TeamWashBackground(base: .dsMdCard, home: colors.home, away: colors.away) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The one-line summary on a recent-result card: "8/11 starters · formation ✓ · score ✗".
    private func resultSummaryLine(_ s: PredictionScore) -> String {
        "\(s.correctPlayers)/11 starters · formation \(s.formationCorrect ? "✓" : "✗") · score \(s.exactScoreline ? "✓" : "✗")"
    }

    // MARK: - Shared match header

    private func matchHeader(_ fixture: PredictionFixture, finalScore: (home: Int, away: Int)?) -> some View {
        let homeAbbr = fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation
        let awayAbbr = fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation
        return HStack(spacing: 12) {
            teamColumn(homeAbbr, color: teamColor(homeAbbr))
            VStack(spacing: 4) {
                if let final = finalScore {
                    Text("\(final.home)–\(final.away)").dsFont(20, weight: .heavy)
                    Text("FT").dsFont(11, weight: .bold).foregroundStyle(.secondary)
                } else {
                    Text("VS").dsFont(12, weight: .bold).foregroundStyle(.secondary)
                    Text(Self.kickoffLabel(fixture.kickoff))
                        .dsFont(11, weight: .semibold)
                        .foregroundStyle(accent)
                }
            }
            .frame(minWidth: 84)
            teamColumn(awayAbbr, color: teamColor(awayAbbr))
        }
        .frame(maxWidth: .infinity)
    }

    private func teamColumn(_ abbreviation: String, color: Color) -> some View {
        VStack(spacing: 6) {
            TeamLogo(urlString: viewModel.club(forAbbreviation: abbreviation)?.logoURL, teamAbbreviation: abbreviation, size: 38)
            // Abbreviation in the club's color — the crest+abbreviation two-team rule (matches MatchCard).
            Text(abbreviation).dsFont(12, weight: .bold).foregroundStyle(color)
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
    // MARK: - Season card + team chips (Competitive Redesign)

    /// The competitive-identity card for the selected club: a season-AVERAGE ring (avg points per match,
    /// as a share of the 88 max), the average + match count, the club rank, and "↑ N since last match"
    /// movement. Average is nil (shows "—") until a prediction has been scored — never faked. (Batch 3:
    /// the board + card moved off cumulative points, which inflate to four digits mid-season, onto the
    /// per-match average, which stays comparable all season.)
    private func seasonCard(team: String) -> some View {
        let standing = viewModel.standingByTeam[team]
        let points = store.points(forTeam: team)
        let matches = store.scoredMatchCount(forTeam: team)
        let avg: Double? = matches > 0 ? Double(points) / Double(matches) : nil
        let teamName = viewModel.teamLabel(team)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.dsBgTertiary, lineWidth: 5)
                    Circle().trim(from: 0, to: (avg ?? 0) / 88)   // avg as a share of the 88-pt per-match max
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(avg.map { "\(Int($0.rounded()))" } ?? "—")
                        .dsFont(17, weight: .heavy, monospacedDigit: true).foregroundStyle(Color.dsFgPrimary)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SEASON AVERAGE").dsFont(11, weight: .bold).tracking(1.2).foregroundStyle(accent)
                    if let avg {
                        Text("\(String(format: "%.1f", avg)) avg · \(matches) match\(matches == 1 ? "" : "es")")
                            .dsFont(14, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                        if let rank = standing?.rank, let total = standing?.total {
                            Text("#\(rank) of \(total) \(teamName) predictor\(total == 1 ? "" : "s")")
                                .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                        }
                    } else {
                        Text("Predict \(teamName)'s XI to join the board")
                            .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let movement = predictMovementText(store.rankMovement(forTeam: team)) {
                Text(movement.text).dsFont(12, weight: .bold).foregroundStyle(movement.color)
            }
        }
        .padding(EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [accent.opacity(0.15), Color.dsMdCard], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.35)))
    }

    /// "↑ N since last match" / "↓ N …" — nil when there's no movement to show (no prior match, or no change).
    private func predictMovementText(_ delta: Int?) -> (text: String, color: Color)? {
        guard let delta, delta != 0 else { return nil }
        return delta > 0
            ? ("↑ \(delta) since last match", .dsSuccess)
            : ("↓ \(-delta) since last match", .dsError)
    }

    /// Team-filter chips — only shown when the user follows/predicts 2+ clubs. Selects which club the
    /// season card + board show.
    private func teamChips(teams: [String], selected: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(teams, id: \.self) { team in
                    let on = team == selected
                    Button { selectedTeam = team } label: {
                        Text(team).dsFont(12, weight: .bold)
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
                    Text("How to play").dsFont(14, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
                    Spacer()
                    Image(systemName: showHowTo ? "chevron.up" : "chevron.right").dsFont(13).foregroundStyle(Color.dsFgTertiary)
                }
                .padding(14)
                .contentShape(Rectangle())   // Fix 4 — the Spacer's middle is a dead zone without this
            }
            .buttonStyle(.plain)
            if showHowTo {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick your team's starting XI, formation, and final score before kickoff. Save a draft, tweak it on team news, then submit to lock it in — submissions close 2 hours before kickoff.")
                        .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("HOW POINTS WORK").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(accent)
                    VStack(spacing: 6) {
                        predictPointRow("Each correct starter", "+3")
                        predictPointRow("Right position band for a correct pick", "+2")
                        predictPointRow("Correct formation", "+5")
                        predictPointRow("Exact final score", "+10")
                        predictPointRow("Right result (win / draw / loss)", "+3")
                        predictPointRow("Perfect XI — all 11 right", "+15")
                        Divider().overlay(Color.dsFgQuaternary)
                        predictPointRow("Most possible in one match", "88 pts", bold: true)
                    }

                    // Fix 6 — the two score-related lines are easy to confuse, so spell out the difference.
                    Text("Right result vs exact score: \u{201C}right result\u{201D} (+3) just means you called the winner or a draw — say WAS win and they win 3\u{2013}1, you get it. \u{201C}Exact score\u{201D} (+10) means you nailed the actual scoreline, like calling 2\u{2013}1 and it finishing 2\u{2013}1. They stack — an exact score is always the right result too, so it banks both.")
                        .dsFont(12).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)

                    Text("Points build up across every match you predict all season, and you're ranked on a per-club leaderboard — by your average score per match, against other fans of your team, not the whole league.")
                        .dsFont(13).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)
                    Text("Your season accuracy — correct player picks out of every XI slot you've predicted — feeds up to 25 of your 100 Superfan points.")
                        .dsFont(13).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
            }
        }
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One "how points work" row for the Predict rules (label — value). Values transcribed from
    /// `PredictionScore` (Batch-2 Fix 4B — rules match the scorer, not a guess).
    private func predictPointRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).dsFont(13, weight: bold ? .semibold : .regular)
                .foregroundStyle(bold ? Color.dsFgPrimary : Color.dsFgSecondary)
            Spacer(minLength: 8)
            Text(value).dsFont(13, weight: .bold).foregroundStyle(accent)
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TeamLogo(urlString: viewModel.club(forAbbreviation: team)?.logoURL, teamAbbreviation: team, size: 22)
                Text(viewModel.teamLabel(team)).dsFont(17, weight: .semibold)
                Spacer()
                Text("Leaderboard").dsFont(12).foregroundStyle(.secondary)
            }
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
                        .dsFont(15, weight: row.isYou ? .bold : .regular)
                        .foregroundStyle(row.isYou ? accent : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    // Season board ranks by AVERAGE per match (+ match count as the credibility stat);
                    // the round board shows the week's raw points (Batch 3).
                    if let avg = row.avg {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(String(format: "%.1f avg", avg))
                                .dsFont(15, weight: .semibold).foregroundStyle(row.isYou ? accent : .secondary)
                            Text("\(row.matches ?? 0) match\(row.matches == 1 ? "" : "es")")
                                .dsFont(11).foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("\(row.points) pts").dsFont(15, weight: .semibold).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(row.isYou ? accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            // Honest sparse state: the board is real, just new. (You're always a row.)
            if rows.count == 1 {
                Text("You're first in line — standings grow as more fans play.")
                    .dsFont(12).foregroundStyle(.secondary)
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
                Text(title).dsFont(12, weight: .semibold)
                if let detail { Text(detail).dsFont(11).opacity(0.8) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isOn ? accent.opacity(0.2) : Color.dsBgTertiary.opacity(0.5))
            .foregroundStyle(isOn ? accent : .secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            withAnimation { viewModel.reset(store: store) }
        } label: {
            Text("Reset predictions")
                .dsFont(17, weight: .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(accent)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent, lineWidth: 1.5)
                )
        }
    }

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
