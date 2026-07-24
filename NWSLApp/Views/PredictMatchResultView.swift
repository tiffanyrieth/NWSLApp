//
//  PredictMatchResultView.swift
//  NWSLApp
//
//  The per-match result detail for Predict the XI (Fan Zone comp arena, Batch 3) — opened from a
//  "See details ›" tap on a Recent Results card. It shows what the compact card can't: your predicted XI
//  against the ACTUAL XI (player by player), the formation + scoreline calls, the full point breakdown, and
//  your rank for that fixture's soccer week.
//
//  The actual lineup is NOT persisted (the store keeps only the derived score breakdown), so it's re-fetched
//  from `/summary` on appear via `PredictXIViewModel.matchResultDetail` — matching the app's online-only
//  stance (no storage growth for history). A fetch failure shows an honest retry, never a blank or a guess.
//

import SwiftUI

struct PredictMatchResultView: View {
    let item: PredictXIViewModel.PredictionItem
    /// The screen's owner VM (held as `@State` in PredictXIView, passed in — it's a reference type).
    let viewModel: PredictXIViewModel

    @Environment(PredictionStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private let accent = Color.dsGamePredict

    @State private var detail: PredictXIViewModel.MatchResultDetail?
    @State private var phase: Phase = .loading
    private enum Phase { case loading, loaded, failed }

    private var score: PredictionScore { item.score ?? .zero }
    private var prediction: XIPrediction? { item.prediction }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    switch phase {
                    case .loading:
                        loadingRow
                    case .failed:
                        RetryStateView(title: "Couldn't load the lineup",
                                       message: "We couldn't reach the match details. Check your connection and try again.") {
                            await load()
                        }
                    case .loaded:
                        if let detail {
                            rankLine(detail)
                            callSummary(detail)
                            yourXISection(detail)
                            missedSection(detail)
                        }
                        breakdownSection
                    }
                }
                .padding(20)
            }
            .background(Color.dsBgGrouped)
            .navigationTitle("Match result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private func load() async {
        phase = .loading
        let result = await viewModel.matchResultDetail(for: item, store: store, auth: auth)
        detail = result
        phase = result == nil ? .failed : .loaded
    }

    // MARK: - Header (crests + FT score + your total)

    private var header: some View {
        let f = item.fixture
        let homeAbbr = f.isHome ? f.teamAbbreviation : f.opponentAbbreviation
        let awayAbbr = f.isHome ? f.opponentAbbreviation : f.teamAbbreviation
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                crestColumn(homeAbbr)
                VStack(spacing: 3) {
                    if let final = item.finalScore {
                        Text("\(final.home)–\(final.away)").dsFont(24, weight: .heavy)
                        Text("FT").dsFont(11, weight: .bold).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 72)
                crestColumn(awayAbbr)
            }
            Text("You scored \(score.total) / 88").dsFont(15, weight: .bold).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func crestColumn(_ abbr: String) -> some View {
        VStack(spacing: 6) {
            TeamLogo(urlString: viewModel.club(forAbbreviation: abbr)?.logoURL, teamAbbreviation: abbr, size: 40)
            Text(abbr).font(.caption.weight(.bold)).foregroundStyle(Color.teamColor(for: abbr, liftOnDark: true, fallback: accent))
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading the lineup…").dsFont(13).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    // MARK: - Rank line (round-scoped — the finest server rank we hold)

    @ViewBuilder
    private func rankLine(_ d: PredictXIViewModel.MatchResultDetail) -> some View {
        if let rank = d.roundRank, d.roundTotal > 0 {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").dsFont(13).foregroundStyle(accent)
                Text("This round: #\(rank) of \(d.roundTotal)\(d.weekLabel.map { " · \($0)" } ?? "")")
                    .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Formation + scoreline calls

    private func callSummary(_ d: PredictXIViewModel.MatchResultDetail) -> some View {
        let p = prediction
        return VStack(spacing: 10) {
            callRow(title: "Formation",
                    your: p?.formation ?? "—",
                    actual: d.actualFormation ?? "—",
                    correct: score.formationCorrect)
            callRow(title: "Final score",
                    your: p.map { "\($0.homeScoreGuess)–\($0.awayScoreGuess)" } ?? "—",
                    actual: item.finalScore.map { "\($0.home)–\($0.away)" } ?? "—",
                    correct: score.exactScoreline,
                    partial: score.resultCorrect ? "Right result" : nil)
        }
    }

    private func callRow(title: String, your: String, actual: String, correct: Bool, partial: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(correct ? Color.dsSuccess : Color.dsFgTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsFont(14, weight: .semibold)
                if let partial, !correct {
                    Text(partial).dsFont(11, weight: .semibold).foregroundStyle(accent)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("You: \(your)").dsFont(12).foregroundStyle(.secondary)
                Text("Actual: \(actual)").dsFont(12, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
            }
        }
        .padding(12)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Your XI vs actual

    @ViewBuilder
    private func yourXISection(_ d: PredictXIViewModel.MatchResultDetail) -> some View {
        if let p = prediction, let formation = Formation(raw: p.formation) {
            let actualIDs = Set(d.actualStarters.map(\.id))
            // Your picks in slot order (GK → attack), each flagged started / didn't.
            let picks: [(id: String, group: PositionGroup)] = formation.slots.compactMap { slot in
                guard let id = p.slots[slot.index] else { return nil }
                return (id, slot.group)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR XI").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
                ForEach(Array(picks.enumerated()), id: \.offset) { _, pick in
                    playerRow(name: d.names[pick.id] ?? "Player",
                              band: pick.group.shortLabel,
                              started: actualIDs.contains(pick.id))
                }
            }
        }
    }

    /// Actual starters the user did NOT pick — "who you missed".
    @ViewBuilder
    private func missedSection(_ d: PredictXIViewModel.MatchResultDetail) -> some View {
        let picked = prediction?.pickedAthleteIDs ?? []
        let missed = d.actualStarters.filter { !picked.contains($0.id) }
        if !missed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ALSO STARTED — YOU MISSED").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
                ForEach(Array(missed.enumerated()), id: \.offset) { _, s in
                    playerRow(name: d.names[s.id] ?? "Player", band: s.group.shortLabel, started: nil)
                }
            }
        }
    }

    /// One player row. `started == true` (a hit), `false` (your pick sat), `nil` (an actual starter you missed).
    private func playerRow(name: String, band: String, started: Bool?) -> some View {
        HStack(spacing: 10) {
            switch started {
            case .some(true):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dsSuccess)
            case .some(false):
                Image(systemName: "xmark.circle").foregroundStyle(Color.dsFgTertiary)
            case .none:
                Image(systemName: "arrow.down.circle").foregroundStyle(accent)
            }
            Text(name).dsFont(15, weight: .semibold)
                .foregroundStyle(started == false ? Color.dsFgSecondary : Color.dsFgPrimary)
                .strikethrough(started == false)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Text(band).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Point breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POINT BREAKDOWN").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
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

    private func breakdownRow(_ title: String, detail: String, points: Int, earned: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: earned ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(earned ? Color.dsSuccess : .secondary)
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
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }
}
