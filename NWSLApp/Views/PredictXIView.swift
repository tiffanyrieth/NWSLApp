//
//  PredictXIView.swift
//  NWSLApp
//
//  Predict the XI — Home's Module 3 "Play", game 3 (Reference/Design/
//  games-design-spec.md §"Game 3: Predict the XI"). Pushed from the Home "Play"
//  card, so it rides Home's NavigationStack (the nav-bar back button is the
//  explicit affordance — no own stack), exactly like DailyTriviaView and
//  BracketBattleView.
//
//  Before a match you predict four things — formation (2 pts), starting GK (1 pt),
//  captain (2 pts), first goal scorer (3 pts). An OPEN match (kickoff still ahead)
//  shows tappable prediction questions; a SETTLED match (past kickoff) collapses to
//  a results review — your pick vs the actual, the points you earned, the final
//  score. A season total ranks you on a simulated leaderboard.
//
//  Predictions lock AT KICKOFF, automatically — so there's no manual "submit"
//  button that could imply otherwise. Picks save the moment you tap (the modern
//  feel, like Bracket's vote rows); the open-match footer just states the live
//  status and when it locks. Honest over ceremonial.
//
//  Visual identity: a pink "matchday" accent, distinct from Daily Trivia's indigo,
//  Bracket Battle's teal, the app's blue follow-highlight, and the green/red used
//  only for right/wrong reveals (per the spec's "own but cohesive game identity").
//
//  Durable state (picks, season-points snapshot) lives in PredictionStore; this
//  view owns only the derived slate via PredictXIViewModel.
//

import SwiftUI

struct PredictXIView: View {
    @State private var viewModel = PredictXIViewModel()
    @Environment(PredictionStore.self) private var store

    /// The game's signature accent (per the approved pink theme).
    private let accent = Color.pink

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
            if case .idle = viewModel.state { await viewModel.load(store: store) }
        }
    }

    // MARK: - Loaded

    private var loadedContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerCard

                if !viewModel.openMatches.isEmpty {
                    sectionLabel("Open for predictions")
                    ForEach(viewModel.openMatches) { openMatchCard($0) }
                }

                if !viewModel.settledMatches.isEmpty {
                    sectionLabel("Results")
                    ForEach(viewModel.settledMatches) { settledMatchCard($0) }
                }

                leaderboardCard

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

            Text("Predict each match before kickoff — formation, keeper, captain, and the first scorer. Lock in your read and climb the board.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                headerStat(value: "\(viewModel.seasonPoints(store: store))", label: "season points")
                Divider().frame(height: 34)
                headerStat(value: "#\(viewModel.yourRank(store: store))", label: "leaderboard rank")
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
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Open match (predicting)

    private func openMatchCard(_ match: PredictionMatch) -> some View {
        let predicted = viewModel.predictedCount(for: match, store: store)
        let ready = viewModel.allPredicted(for: match, store: store)
        return VStack(alignment: .leading, spacing: 16) {
            matchHeader(match, settled: false)

            ForEach(match.questions) { question in
                questionBlock(question, in: match)
            }

            // Auto-saved status footer (no manual submit — picks lock at kickoff).
            HStack(spacing: 8) {
                Image(systemName: ready ? "checkmark.seal.fill" : "pencil.circle")
                    .foregroundStyle(ready ? accent : .secondary)
                Text(ready
                     ? "Locked in — change anytime before kickoff."
                     : "\(predicted) of \(match.questions.count) predicted — pick them all to lock in.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ready ? accent : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // One prediction question: header (icon + title + point chip), prompt, options.
    private func questionBlock(_ question: PredictionQuestion, in match: PredictionMatch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: question.category.icon)
                    .font(.subheadline)
                    .foregroundStyle(accent)
                Text(question.prompt)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                pointChip(question.points)
            }
            VStack(spacing: 8) {
                ForEach(question.options) { option in
                    optionRow(option, in: question, match: match)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func optionRow(_ option: PredictionOption, in question: PredictionQuestion, match: PredictionMatch) -> some View {
        let isSelected = store.pick(for: question.id) == option.id
        return Button {
            viewModel.predict(option.id, for: question, in: match, store: store)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let detail = option.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? accent : Color(.systemGray3))
            }
            .padding(10)
            .background(isSelected ? accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent : Color(.systemGray5), lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pointChip(_ points: Int) -> some View {
        Text("+\(points) pt\(points == 1 ? "" : "s")")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent.opacity(0.14))
            .foregroundStyle(accent)
            .clipShape(Capsule())
    }

    // MARK: - Settled match (results review)

    private func settledMatchCard(_ match: PredictionMatch) -> some View {
        let earned = viewModel.points(for: match, store: store)
        return VStack(alignment: .leading, spacing: 14) {
            matchHeader(match, settled: true)

            HStack {
                Text("You scored")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(earned) / \(match.pointsAvailable) pts")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
            }

            ForEach(match.questions) { question in
                resultRow(question)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func resultRow(_ question: PredictionQuestion) -> some View {
        let pick = question.option(store.pick(for: question.id))
        let correct = question.correctOption
        let didPredict = pick != nil
        let gotItRight = viewModel.isCorrect(question, store: store)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: gotItRight ? "checkmark.circle.fill" : (didPredict ? "xmark.circle.fill" : "minus.circle"))
                .foregroundStyle(gotItRight ? .green : (didPredict ? .red : .secondary))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(question.category.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(gotItRight ? "+\(question.points)" : "+0")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(gotItRight ? accent : .secondary)
                }
                // The actual outcome (the answer key, now revealed).
                Text("Actual: \(correct?.label ?? "—")")
                    .font(.subheadline.weight(.semibold))
                // Show the user's pick only when it differs (or they skipped it).
                if !gotItRight {
                    Text(didPredict ? "Your pick: \(pick?.label ?? "—")" : "You didn't predict this")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Shared match header

    private func matchHeader(_ match: PredictionMatch, settled: Bool) -> some View {
        HStack(spacing: 12) {
            teamColumn(match.homeAbbreviation)

            VStack(spacing: 4) {
                if settled {
                    Text("\(match.homeScore)–\(match.awayScore)")
                        .font(.title3.weight(.heavy))
                    Text("FT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("VS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Label(kickoffLabel(match), systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(minWidth: 80)

            teamColumn(match.awayAbbreviation)
        }
        .frame(maxWidth: .infinity)
    }

    private func teamColumn(_ abbreviation: String) -> some View {
        VStack(spacing: 6) {
            TeamLogo(urlString: viewModel.club(forAbbreviation: abbreviation)?.logoURL, size: 38)
            Text(abbreviation)
                .font(.caption.weight(.bold))
        }
        .frame(maxWidth: .infinity)
    }

    /// "Locks Fri, Jul 3 · 7:30 PM" — the kickoff the open match closes at.
    private func kickoffLabel(_ match: PredictionMatch) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: viewModel.kickoff(for: match))
    }

    // MARK: - Leaderboard

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Leaderboard")
                .font(.headline)
            Text("Season standings")
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

    private var resetButton: some View {
        Button {
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
            Button("Try again") { Task { await viewModel.load(store: store) } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        PredictXIView()
            .environment(PredictionStore())
    }
}
