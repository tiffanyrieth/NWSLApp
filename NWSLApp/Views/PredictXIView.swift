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
        .navigationContextLabel("Predict the XI")
        .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "sportscourt.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PREDICT THE XI")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                    Text("Call the lineup")
                        .font(.title2.weight(.bold))
                }
                Spacer(minLength: 0)
            }

            Text("Pick your team's starting XI, formation, and final score before kickoff. Save a draft, tweak it on team news, then submit to lock it in — submissions close 2 hours before kickoff.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                headerStat(value: "\(store.seasonPoints)", label: "season points")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func headerStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(accent)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No upcoming matches to predict")
                .font(.headline)
            Text("Follow a team with a fixture coming up and it'll appear here to predict.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Open fixture card

    private func openItemCard(_ item: PredictXIViewModel.PredictionItem) -> some View {
        let fixture = item.fixture
        return Button {
            activeFixture = fixture
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                matchHeader(fixture, finalScore: nil)

                openStatusRow(item)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
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
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func scoreGuessLabel(_ item: PredictXIViewModel.PredictionItem) -> String {
        guard let p = item.prediction else { return "" }
        return "\(p.homeScoreGuess)–\(p.awayScoreGuess)"
    }

    // MARK: - Result card

    private func resultCard(_ item: PredictXIViewModel.PredictionItem) -> some View {
        let score = item.score ?? .zero
        return VStack(alignment: .leading, spacing: 14) {
            matchHeader(item.fixture, finalScore: item.finalScore)

            HStack {
                Text("You scored").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(score.total) pts").font(.headline.weight(.bold)).foregroundStyle(accent)
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func breakdownRow(_ title: String, detail: String, points: Int, earned: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: earned ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(earned ? .green : .secondary)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Text(earned ? "+\(points)" : "+0")
                .font(.caption.weight(.bold))
                .foregroundStyle(earned ? accent : .secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Shared match header

    private func matchHeader(_ fixture: PredictionFixture, finalScore: (home: Int, away: Int)?) -> some View {
        let homeAbbr = fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation
        let awayAbbr = fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation
        return HStack(spacing: 12) {
            teamColumn(homeAbbr)
            VStack(spacing: 4) {
                if let final = finalScore {
                    Text("\(final.home)–\(final.away)").font(.title3.weight(.heavy))
                    Text("FT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                } else {
                    Text("VS").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(Self.kickoffLabel(fixture.kickoff))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            .frame(minWidth: 84)
            teamColumn(awayAbbr)
        }
        .frame(maxWidth: .infinity)
    }

    private func teamColumn(_ abbreviation: String) -> some View {
        VStack(spacing: 6) {
            TeamLogo(urlString: viewModel.club(forAbbreviation: abbreviation)?.logoURL, teamAbbreviation: abbreviation, size: 38)
            Text(abbreviation).font(.caption.weight(.bold))
        }
        .frame(maxWidth: .infinity)
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
                Text(viewModel.teamLabel(team)).font(.headline)
                Spacer()
                Text("Predictors").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                HStack(spacing: 12) {
                    Text("\(row.rank)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(row.isYou ? accent : .secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text(row.name)
                        .font(.subheadline.weight(row.isYou ? .bold : .regular))
                        .foregroundStyle(row.isYou ? accent : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(row.points) pts").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(row.isYou ? accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            // Honest sparse state: the board is real, just new. (You're always a row.)
            if rows.count == 1 {
                Text("You're first in line — standings grow as more fans play.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            withAnimation { viewModel.reset(store: store) }
        } label: {
            Text("Reset predictions")
                .font(.headline)
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
