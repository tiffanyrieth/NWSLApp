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
    private let accent = Color.dsGameTrivia

    /// Presents the sign-in invite when a signed-out user finishes a game (their result
    /// needs an account to reach the Supabase leaderboard). Skippable; local stats persist.
    @State private var gateRequested = false

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
        .nativeBackButton(title: "NWSL Trivia")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { PlayingAsBadge(accent: Color.dsGameTrivia) } }
        .background(Color.dsBgGrouped)
        // Mandatory sign-in + display name to play — gated at the first "Submit Answer", so
        // a finished game's streak always reaches the leaderboard. "Go back" cancels.
        .fanZoneGate(isRequested: $gateRequested, gameName: "NWSL Trivia", accent: accent) {
            viewModel.submit()
        }
        .task {
            // Start Game Center auth here (a game screen) rather than at launch, so
            // the GC banner only shows when the user is about to play. Idempotent.
            GameCenterManager.shared.authenticate()
            if case .idle = viewModel.state { await viewModel.loadDaily() }
        }
    }

    /// The day's questions as game-agnostic descriptors for the community-results panel.
    private var triviaCommunityQuestions: [CommunityResultsView.QuestionInfo] {
        viewModel.questions.map { .init(id: $0.id, prompt: $0.question, options: $0.options, correctIndex: $0.correctIndex) }
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
                Label("NWSL TRIVIA", systemImage: "brain.head.profile")
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
                    Capsule().fill(Color.dsBgTertiary)
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
                    // Gate the FIRST submit on sign-in + display name; the gate runs
                    // viewModel.submit() once authorized (instantly after the first time).
                    Button("Submit Answer") { gateRequested = true }
                        .disabled(viewModel.selectedIndex == nil)
                } else if viewModel.isLastQuestion {
                    Button("See Results") {
                        // Double-tap guard: `finish()` flips `isFinished` synchronously, so a
                        // second tap before the results view swaps in bails (no duplicate submits).
                        guard !viewModel.isFinished else { return }
                        store.recordCompletion(correct: viewModel.score, outOf: viewModel.questionCount)
                        viewModel.finish()
                        // Game Center (additive): achievements only. NWSL Trivia has NO competitive
                        // leaderboard now (docs §11) — the community-results screen replaces it; the
                        // superfan total still gets the lifetime-correct count via syncAll.
                        if viewModel.score == viewModel.questionCount {
                            GameCenterManager.shared.report(GameCenterID.Achievement.triviaPerfectDay)
                        }
                        if store.bestStreak >= 7 { GameCenterManager.shared.report(GameCenterID.Achievement.triviaStreak7) }
                        if store.bestStreak >= 30 { GameCenterManager.shared.report(GameCenterID.Achievement.triviaStreak30) }
                        // Signed in (gated at the first Submit) → persist per-question answers to the
                        // shared community aggregate. Edition key = today's day-key (store stamped it).
                        if let userID = auth.userID, let edition = store.lastCompletedDay {
                            let answers = viewModel.communityAnswers()
                            Task {
                                await QuizResultsService().upsert(game: "trivia", editionKey: edition,
                                    answers: answers, userID: userID, season: "2026")
                            }
                        }
                    }
                } else {
                    Button("Next Question") { viewModel.advance() }
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(viewModel.selectedIndex == nil && !viewModel.isRevealed ? Color.dsBgTertiary : accent)
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
                        .dsFont(44)
                        .foregroundStyle(accent)
                    Text(showRecap ? "Nice work!" : "You're all set for today")
                        .font(.title2.weight(.bold))
                }
                .padding(.top, 12)

                scoreCard

                // Community "how everyone did" replaces the old streak leaderboard (docs §11).
                // Trivia reveals it AFTER the day closes (server-decided); today shows the
                // "check back tomorrow" state alongside the personal score.
                if let edition = store.lastCompletedDay {
                    CommunityResultsView(game: "trivia", editionKey: edition,
                                         questions: triviaCommunityQuestions, accent: accent)
                }

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
                    .dsFont(48, weight: .heavy, design: .rounded)
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
        .background(Color.dsBgCard)
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
                        .foregroundStyle(gotItRight ? Color.dsSuccess : Color.dsError)
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
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) { await viewModel.loadDaily() }
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
        let base = Color.dsBgCard
        let isSelected = viewModel.selectedIndex == index
        let isCorrect = index == question.correctIndex

        if !viewModel.isRevealed {
            // Pre-submit: only the current selection is highlighted (indigo).
            return OptionStyle(
                fill: isSelected ? accent.opacity(0.12) : base,
                borderColor: isSelected ? accent : Color.dsBgTertiary,
                borderWidth: isSelected ? 2 : 1,
                badgeFill: isSelected ? accent : Color.dsBgTertiary,
                badgeText: isSelected ? .white : .secondary,
                trailingIcon: nil
            )
        }
        // Post-submit reveal: correct = green, your wrong pick = red, rest dim.
        if isCorrect {
            return OptionStyle(
                fill: Color.dsSuccess.opacity(0.14),
                borderColor: Color.dsSuccess,
                borderWidth: 2,
                badgeFill: Color.dsSuccess,
                badgeText: .white,
                trailingIcon: "checkmark"
            )
        }
        if isSelected {
            return OptionStyle(
                fill: Color.dsError.opacity(0.12),
                borderColor: Color.dsError,
                borderWidth: 2,
                badgeFill: Color.dsError,
                badgeText: .white,
                trailingIcon: "xmark"
            )
        }
        return OptionStyle(
            fill: base,
            borderColor: Color.dsBgTertiary,
            borderWidth: 1,
            badgeFill: Color.dsBgTertiary,
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
