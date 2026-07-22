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
    }

    // MARK: - Loaded

    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard
                rankedCallout

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
                    sectionLabel("Results")
                    ForEach(results) { resultCard($0) }
                }

                leaderboardSection

                if store.hasPredicted {
                    resetButton
                }
            }
            .padding(20)
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
            Text("No upcoming matches to predict")
                .dsFont(17, weight: .semibold)
            Text("Follow a team with a fixture coming up and it'll appear here to predict.")
                .dsFont(15)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

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

    private func resultCard(_ item: PredictXIViewModel.PredictionItem) -> some View {
        let score = item.score ?? .zero
        let colors = fixtureColors(item.fixture)
        return VStack(alignment: .leading, spacing: 14) {
            matchHeader(item.fixture, finalScore: item.finalScore)

            HStack {
                Text("You scored").dsFont(12).foregroundStyle(.secondary)
                Spacer()
                Text("\(score.total) pts").dsFont(17, weight: .bold).foregroundStyle(accent)
            }

            VStack(spacing: 8) {
                breakdownRow("Correct players", detail: "\(score.correctPlayers)/11", points: score.playersPoints, earned: score.correctPlayers > 0)
                breakdownRow("Right position", detail: "\(score.correctPositions)", points: score.positionsPoints, earned: score.correctPositions > 0)
                breakdownRow("Formation", detail: score.formationCorrect ? "Correct" : "Missed", points: score.formationPoints, earned: score.formationCorrect)
                breakdownRow("Exact score", detail: score.exactScoreline ? "Nailed it" : "Missed", points: score.scorelinePoints, earned: score.exactScoreline)
                breakdownRow("Result (W/D/L)", detail: score.resultCorrect ? "Correct" : "Missed", points: score.resultPoints, earned: score.resultCorrect)
                if score.perfectXI {
                    breakdownRow("Perfect XI bonus", detail: "All 11!", points: score.perfectPoints, earned: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { TeamWashBackground(base: .dsMdCard, home: colors.home, away: colors.away) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func breakdownRow(_ title: String, detail: String, points: Int, earned: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: earned ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(earned ? .green : .secondary)
            Text(title).dsFont(15, weight: .semibold)
            Spacer()
            Text(detail).dsFont(12).foregroundStyle(.secondary)
            Text(earned ? "+\(points)" : "+0")
                .font(.caption.weight(.bold))
                .foregroundStyle(earned ? accent : .secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdPanelBottom)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
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

    /// One standings card per team you're predicting or have scored in. Empty (shows
    /// nothing) when you have no active/scored team — the screen's own empty state
    /// covers the no-activity case.
    @ViewBuilder
    private var leaderboardSection: some View {
        ForEach(viewModel.leaderboards, id: \.team) { board in
            teamLeaderboardCard(team: board.team, rows: board.rows)
        }
    }

    private func teamLeaderboardCard(team: String, rows: [PredictXIViewModel.LeaderboardRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TeamLogo(urlString: viewModel.club(forAbbreviation: team)?.logoURL, teamAbbreviation: team, size: 22)
                Text(viewModel.teamLabel(team)).dsFont(17, weight: .semibold)
                Spacer()
                Text("Predictors").dsFont(12).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                // A below-fold "You" row means you rank past the visible top — separate it
                // with a divider so the jump from #100 to your real rank reads honestly.
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
                    Text("\(row.points) pts").dsFont(15, weight: .semibold).foregroundStyle(.secondary)
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
