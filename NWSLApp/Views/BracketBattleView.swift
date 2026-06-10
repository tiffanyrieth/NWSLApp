//
//  BracketBattleView.swift
//  NWSLApp
//
//  Bracket Battle — Home's Module 3 "Play", game 2 (Reference/Design/
//  games-design-spec.md §"Game 2: Bracket Battle"). Pushed from the Home "Play"
//  card, so it rides Home's NavigationStack (the nav-bar back button is the
//  explicit affordance — no own stack), exactly like DailyTriviaView.
//
//  A single-elimination tournament you vote through one round at a time: tap the
//  contender you think the community will advance in each matchup, then "Lock in"
//  the round to reveal the community result (winner + vote split) and bank a point
//  for every correct pick. Locked rounds collapse to a compact results card and
//  the next round opens right below — the approved "play through, daily-styled"
//  cadence (the per-round lock → reveal → advance rhythm carries the daily feel
//  without a calendar gate). A simulated leaderboard ranks you against sample
//  fans; the final's winner is crowned community champion.
//
//  Visual identity: a teal "tournament" accent, distinct from Daily Trivia's
//  indigo, the app's blue follow-highlight, and the green/red used only for
//  right/wrong pick reveals (per the spec's "own but cohesive game identity").
//
//  Durable state (votes, points, locked rounds) lives in BracketStore; this view
//  owns only the derived bracket via BracketViewModel.
//

import SwiftUI

struct BracketBattleView: View {
    @State private var viewModel = BracketViewModel()
    @Environment(BracketStore.self) private var store

    /// The game's signature accent (per the approved teal theme).
    private let accent = Color.teal

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading the bracket…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            case .loaded:
                loadedContent
            }
        }
        .navigationContextLabel("Bracket Battle")
        .background(Color(.systemGroupedBackground))
        .task {
            if case .idle = viewModel.state { await viewModel.load(store: store) }
        }
    }

    // MARK: - Loaded

    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard

                if store.isComplete {
                    championCard
                }

                // Render every round up to and including the current one: closed
                // rounds show results, the current round is open for voting.
                let upperBound = min(store.currentRound, viewModel.roundCount - 1)
                if upperBound >= 0 {
                    ForEach(0...upperBound, id: \.self) { round in
                        if round < store.currentRound {
                            lockedRoundCard(round)
                        } else {
                            activeRoundCard(round)
                        }
                    }
                }

                leaderboardCard

                if store.isComplete {
                    restartButton
                }
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BRACKET BATTLE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                    Text(viewModel.edition?.title ?? "Bracket")
                        .font(.title2.weight(.bold))
                }
                Spacer(minLength: 0)
            }

            if let theme = viewModel.edition?.theme {
                Text(theme)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            progressPills

            HStack(spacing: 12) {
                headerStat(value: "\(store.points)", label: "your points")
                Divider().frame(height: 34)
                headerStat(value: "#\(viewModel.yourRank(store: store))", label: "leaderboard rank")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // One pill per round (R16 · QF · SF · F): filled when closed, outlined when
    // current, dim when still ahead.
    private var progressPills: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.roundCount, id: \.self) { round in
                let label = BracketRoundLabel.short(matchups: viewModel.matchups(inRound: round).count)
                let isDone = round < store.currentRound
                let isCurrent = round == store.currentRound && !store.isComplete
                Text(label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(isDone ? accent : (isCurrent ? accent.opacity(0.14) : Color(.systemGray6)))
                    .foregroundStyle(isDone ? .white : (isCurrent ? accent : .secondary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isCurrent ? accent : .clear, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private func headerStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(accent)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Champion (final closed)

    private var championCard: some View {
        let champion = viewModel.champion(store: store)
        return VStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(accent)
            Text("COMMUNITY CHAMPION")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            crest(champion, size: 56)
            Text(champion?.playerName ?? "—")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(teamLabel(for: champion))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let pct = viewModel.finalWinnerPercent() {
                Text("Took the final with \(pct)% of the vote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("You finished with \(store.points) points — rank #\(viewModel.yourRank(store: store)).")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(accent.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Active round (voting)

    private func activeRoundCard(_ round: Int) -> some View {
        let matchups = viewModel.matchups(inRound: round)
        let picked = matchups.filter { store.pick(for: $0.id) != nil }.count
        let ready = viewModel.allPicked(inRound: round, store: store)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.roundTitle(round))
                    .font(.headline)
                Spacer()
                Text("Round \(round + 1) of \(viewModel.roundCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("Tap who you think the community advances.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(matchups) { matchup in
                voteMatchup(matchup, round: round)
            }

            Button {
                withAnimation { viewModel.lockRound(round, store: store) }
            } label: {
                Text(ready ? "Lock in \(viewModel.roundTitle(round))" : "Pick all \(matchups.count) matchups (\(picked)/\(matchups.count))")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ready ? accent : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!ready)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // A matchup as two stacked, tappable contender rows with a "VS" divider.
    private func voteMatchup(_ matchup: BracketMatchup, round: Int) -> some View {
        VStack(spacing: 0) {
            contenderRow(matchup.entrantA, in: matchup, round: round)
            HStack {
                Rectangle().fill(Color(.systemGray5)).frame(height: 1)
                Text("VS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Rectangle().fill(Color(.systemGray5)).frame(height: 1)
            }
            .padding(.vertical, 6)
            contenderRow(matchup.entrantB, in: matchup, round: round)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func contenderRow(_ entrant: BracketEntrant?, in matchup: BracketMatchup, round: Int) -> some View {
        let isSelected = entrant != nil && store.pick(for: matchup.id) == entrant?.id
        return Button {
            if let entrant {
                store.setPick(matchupID: matchup.id, entrantID: entrant.id, round: round)
            }
        } label: {
            HStack(spacing: 12) {
                crest(entrant, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entrant?.playerName ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(teamLabel(for: entrant)) · \(entrant?.credential ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? accent : Color(.systemGray3))
            }
            .padding(8)
            .background(isSelected ? accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isRoundLocked(round))
    }

    // MARK: - Locked round (results)

    private func lockedRoundCard(_ round: Int) -> some View {
        let matchups = viewModel.matchups(inRound: round)
        let correct = viewModel.correctPicks(inRound: round, store: store)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.roundTitle(round))
                    .font(.headline)
                Spacer()
                Text("You got \(correct)/\(matchups.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }
            ForEach(matchups) { matchup in
                resultRow(matchup)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func resultRow(_ matchup: BracketMatchup) -> some View {
        let winner = viewModel.entrant(matchup.communityWinnerID)
        let loser = (matchup.entrantA?.id == matchup.communityWinnerID) ? matchup.entrantB : matchup.entrantA
        let didPick = store.pick(for: matchup.id) != nil
        let gotItRight = store.pick(for: matchup.id) == matchup.communityWinnerID
        return HStack(spacing: 10) {
            Image(systemName: gotItRight ? "checkmark.circle.fill" : (didPick ? "xmark.circle.fill" : "minus.circle"))
                .foregroundStyle(gotItRight ? .green : (didPick ? .red : .secondary))
            crest(winner, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(winner?.playerName ?? "—")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(matchup.votePercentWinner)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
                HStack {
                    Text(loser?.playerName ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(matchup.votePercentLoser)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Leaderboard

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leaderboard")
                .font(.headline)
            Text("\(viewModel.edition?.title ?? "This") edition")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(viewModel.leaderboard(store: store)) { row in
                HStack(spacing: 12) {
                    Text("\(row.rank)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(row.isYou ? accent : .secondary)
                        .frame(width: 28, alignment: .trailing)
                    Text(row.name)
                        .font(.subheadline.weight(row.isYou ? .bold : .regular))
                        .foregroundStyle(row.isYou ? accent : .primary)
                    Spacer()
                    Text("\(row.points) pts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(row.isYou ? accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var restartButton: some View {
        Button {
            withAnimation { store.restart() }
        } label: {
            Text("Play again")
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

    // MARK: - Shared building blocks

    @ViewBuilder
    private func crest(_ entrant: BracketEntrant?, size: CGFloat) -> some View {
        TeamLogo(urlString: viewModel.club(for: entrant)?.logoURL, size: size)
    }

    /// The short, chip-friendly club name (falls back to the abbreviation when the
    /// club directory didn't resolve — the game stays playable offline).
    private func teamLabel(for entrant: BracketEntrant?) -> String {
        guard let entrant else { return "—" }
        let club = viewModel.club(for: entrant)
        return club?.shortName ?? club?.displayName ?? entrant.teamAbbreviation
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") { Task { await viewModel.load(store: store) } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        BracketBattleView()
            .environment(BracketStore())
    }
}
