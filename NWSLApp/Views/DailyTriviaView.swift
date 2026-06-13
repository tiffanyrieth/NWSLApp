//
//  DailyTriviaView.swift
//  NWSLApp
//
//  Daily Trivia — Home's Module 3 "Play", game 1 (Reference/Design/
//  games-design-spec.md). Pushed from the Home "Play" card, so it rides Home's
//  NavigationStack (the nav-bar back button is the explicit affordance — no own
//  stack). Five multiple-choice questions a day; select → submit (reveals
//  correct/incorrect) → next; a results screen at the end shows today's score,
//  the streak, and all-time accuracy.
//
//  Visual identity: an indigo "quiz" accent, distinct from team colors and the
//  app's blue follow-highlight, per the spec's "own but cohesive game identity."
//  Correct/incorrect reveals use green/red — the one place those colors read as
//  right/wrong rather than a team.
//
//  One scored play per day (the streak mechanic): once TriviaStore.hasPlayedToday
//  is true, the screen shows the locked results summary and "come back tomorrow"
//  instead of replaying. Durable stats live in TriviaStore; this view owns only
//  the in-progress session via TriviaViewModel.
//

import SwiftUI

struct DailyTriviaView: View {
    @State private var viewModel = TriviaViewModel()
    @Environment(TriviaStore.self) private var store
    @Environment(AuthStore.self) private var auth

    /// The game's signature accent (per the approved indigo theme).
    private let accent = Color.indigo

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading today's trivia…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            case .loaded:
                loadedContent
            }
        }
        .navigationContextLabel("Daily Trivia")
        .background(Color(.systemGroupedBackground))
        .task {
            if case .idle = viewModel.state { await viewModel.loadDaily() }
            // Load the real standings (and self-heal the user's row) whenever the
            // screen appears — the results screen reads `viewModel.leaderboard`.
            await viewModel.refreshLeaderboard(store: store, auth: auth)
        }
    }

    // Decide which screen: a just-finished session shows the full recap; a user
    // who already played today sees the locked summary; otherwise, play.
    @ViewBuilder
    private var loadedContent: some View {
        if viewModel.isFinished {
            resultsView(showRecap: true)
        } else if store.hasPlayedToday {
            resultsView(showRecap: false)
        } else {
            questionView
        }
    }

    // MARK: - Question screen

    @ViewBuilder
    private var questionView: some View {
        if let question = viewModel.currentQuestion {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        progressHeader
                        categoryChip(for: question)
                        Text(question.question)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 12) {
                            ForEach(question.options.indices, id: \.self) { index in
                                optionRow(question: question, index: index)
                            }
                        }
                    }
                    .padding(20)
                }
                actionBar(for: question)
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("DAILY TRIVIA", systemImage: "brain.head.profile")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
                Text("Question \(viewModel.questionNumber) of \(viewModel.questionCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            // Progress bar: indigo fill over a track, one segment per question.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(accent)
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)
        }
    }

    private var progressFraction: CGFloat {
        guard viewModel.questionCount > 0 else { return 0 }
        return CGFloat(viewModel.questionNumber) / CGFloat(viewModel.questionCount)
    }

    private func categoryChip(for question: TriviaQuestion) -> some View {
        HStack(spacing: 8) {
            Text(question.category.label.uppercased())
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accent.opacity(0.12))
                .foregroundStyle(accent)
                .clipShape(Capsule())
            Text(question.difficulty.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // One answer option. Styling depends on selected / revealed / correctness.
    private func optionRow(question: TriviaQuestion, index: Int) -> some View {
        let style = optionStyle(question: question, index: index)
        return Button {
            viewModel.select(index)
        } label: {
            HStack(spacing: 14) {
                Text(letter(index))
                    .font(.subheadline.weight(.bold))
                    .frame(width: 26, height: 26)
                    .background(style.badgeFill)
                    .foregroundStyle(style.badgeText)
                    .clipShape(Circle())
                Text(question.options[index])
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let icon = style.trailingIcon {
                    Image(systemName: icon)
                        .foregroundStyle(style.borderColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.fill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(style.borderColor, lineWidth: style.borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRevealed)
    }

    // Pinned bottom bar: Submit → Next → See Results, respecting safe area.
    private func actionBar(for question: TriviaQuestion) -> some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if !viewModel.isRevealed {
                    Button("Submit Answer") { viewModel.submit() }
                        .disabled(viewModel.selectedIndex == nil)
                } else if viewModel.isLastQuestion {
                    Button("See Results") {
                        store.recordCompletion(correct: viewModel.score, outOf: viewModel.questionCount)
                        viewModel.finish()
                        // Push the freshly-bumped best streak + refresh the board.
                        Task { await viewModel.refreshLeaderboard(store: store, auth: auth) }
                    }
                } else {
                    Button("Next Question") { viewModel.advance() }
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(viewModel.selectedIndex == nil && !viewModel.isRevealed ? Color(.systemGray4) : accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(.bar)
    }

    // MARK: - Results screen

    private func resultsView(showRecap: Bool) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 44))
                        .foregroundStyle(accent)
                    Text(showRecap ? "Nice work!" : "You're all set for today")
                        .font(.title2.weight(.bold))
                }
                .padding(.top, 12)

                scoreCard

                leaderboardCard

                if showRecap {
                    recapList
                }

                Text("Come back tomorrow for a fresh set of five — keep your streak alive!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(20)
        }
    }

    // Today's score + streak + all-time accuracy.
    private var scoreCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("\(store.lastScore) / \(viewModel.questionCount)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text("Today's score")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                statItem(
                    value: "\(store.streak)",
                    label: store.streak == 1 ? "day streak" : "day streak",
                    icon: "flame.fill",
                    tint: .orange
                )
                Divider().frame(height: 40)
                statItem(
                    value: "\(Int((store.accuracy * 100).rounded()))%",
                    label: "all-time accuracy",
                    icon: "target",
                    tint: accent
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Real league-wide best-streak standings (you highlighted). Always has at least
    // your row on this screen, so it never renders empty.
    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("Streak leaders").font(.headline)
                Spacer()
                Text("League-wide").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(viewModel.leaderboard) { row in
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
                    HStack(spacing: 4) {
                        Text("\(row.streak)").font(.subheadline.weight(.semibold))
                        Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(row.isYou ? accent.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if viewModel.leaderboard.count == 1 {
                Text("You're on the board — leaders fill in as more fans play daily.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statItem(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(value).font(.title3.weight(.bold))
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // Per-question recap (fresh session only): correct answer + whether you got it.
    private var recapList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.headline)
            ForEach(viewModel.questions.indices, id: \.self) { index in
                let question = viewModel.questions[index]
                let pick = index < viewModel.picks.count ? viewModel.picks[index] : nil
                let gotItRight = pick == question.correctIndex
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: gotItRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(gotItRight ? .green : .red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.question)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Answer: \(question.correctAnswer)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") { Task { await viewModel.loadDaily() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Option styling

    private struct OptionStyle {
        var fill: Color
        var borderColor: Color
        var borderWidth: CGFloat
        var badgeFill: Color
        var badgeText: Color
        var trailingIcon: String?
    }

    private func optionStyle(question: TriviaQuestion, index: Int) -> OptionStyle {
        let base = Color(.secondarySystemGroupedBackground)
        let isSelected = viewModel.selectedIndex == index
        let isCorrect = index == question.correctIndex

        if !viewModel.isRevealed {
            // Pre-submit: only the current selection is highlighted (indigo).
            return OptionStyle(
                fill: isSelected ? accent.opacity(0.12) : base,
                borderColor: isSelected ? accent : Color(.systemGray4),
                borderWidth: isSelected ? 2 : 1,
                badgeFill: isSelected ? accent : Color(.systemGray5),
                badgeText: isSelected ? .white : .secondary,
                trailingIcon: nil
            )
        }
        // Post-submit reveal: correct = green, your wrong pick = red, rest dim.
        if isCorrect {
            return OptionStyle(
                fill: Color.green.opacity(0.14),
                borderColor: .green,
                borderWidth: 2,
                badgeFill: .green,
                badgeText: .white,
                trailingIcon: "checkmark"
            )
        }
        if isSelected {
            return OptionStyle(
                fill: Color.red.opacity(0.12),
                borderColor: .red,
                borderWidth: 2,
                badgeFill: .red,
                badgeText: .white,
                trailingIcon: "xmark"
            )
        }
        return OptionStyle(
            fill: base,
            borderColor: Color(.systemGray5),
            borderWidth: 1,
            badgeFill: Color(.systemGray5),
            badgeText: .secondary,
            trailingIcon: nil
        )
    }

    private func letter(_ index: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        return index < letters.count ? letters[index] : ""
    }
}

#Preview {
    NavigationStack {
        DailyTriviaView()
            .environment(TriviaStore())
            .environment(AuthStore())
    }
}
