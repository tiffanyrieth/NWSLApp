//
//  DailyTriviaView.swift
//  NWSLApp
//
//  NWSL Trivia — the community-family quiz. Faceit-lifted (Fan Zone v2) onto Know Her Game's interface so
//  the two community games stop diverging: an INTRO screen, progress DOTS (not a bar), TAP-TO-ANSWER with
//  ~1.2s auto-advance (no Submit button), a shared SCORE RING, a score-based feel-good title, a "+N points"
//  Superfan pill, and the shared `CommunityResultsView` "how everyone did" panel moved up front (the old
//  Review recap list is gone — the community panel IS the post-game payoff).
//
//  CADENCE IS UNCHANGED — this is the interface facelift only. Trivia stays DAILY (one scored play per
//  local day; the same deterministic 5-of-N slice) until the separate question-sourcing project lands the
//  weekly/biweekly + 10-question rebuild. So the copy here is still daily ("Today's quiz", "day streak").
//
//  One scored play per day: `TriviaStore.hasPlayedToday` locks the result recap. Sign-in + a chosen
//  display name are gated at "Start the quiz" (community answers are always written signed in).
//

import SwiftUI

struct DailyTriviaView: View {
    @State private var viewModel = TriviaViewModel()
    @Environment(TriviaStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var gateRequested = false
    /// Flipped by the sign-in gate at "Start the quiz" — intro → questions.
    @State private var started = false
    /// Held so the results community panel AWAITS the write before fetching — the player then sees her own
    /// answer counted instead of a "0 fans played" flash (mirrors Know Her Game).
    @State private var writeTask: Task<Void, Never>?

    private let accent = Color.dsGameTrivia

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
        .fanZonePlayingAs(accent: accent)
        .background(Color.dsBgGrouped)
        // Mandatory sign-in + display name to play — gated at "Start the quiz", so the completion write
        // is always signed in. "Go back" cancels.
        .fanZoneGate(isRequested: $gateRequested, gameName: "NWSL Trivia", accent: accent) {
            started = true
        }
        .task {
            GameCenterManager.shared.authenticate()
            if case .idle = viewModel.state { await viewModel.loadDaily() }
        }
    }

    /// The day's questions as game-agnostic descriptors for the community-results panel.
    private var triviaCommunityQuestions: [CommunityResultsView.QuestionInfo] {
        viewModel.questions.map { .init(id: $0.id, prompt: $0.question, options: $0.options, correctIndex: $0.correctIndex) }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if viewModel.isFinished {
            resultView()                      // just-finished session
        } else if store.hasPlayedToday {
            resultView()                      // already played today → locked recap
        } else if started {
            questionView
        } else {
            introView
        }
    }

    // MARK: - Intro

    private var introView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "brain.head.profile")
                    .dsFont(36).foregroundStyle(accent)
                    .frame(width: 80, height: 80)
                    .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.top, 8)
                Text("NWSL TRIVIA")
                    .dsFont(11, weight: .bold).tracking(0.5)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(accent.opacity(0.14)).foregroundStyle(accent).clipShape(Capsule())
                VStack(spacing: 4) {
                    Text("Test your league knowledge").dsFont(28, weight: .bold).multilineTextAlignment(.center)
                    Text("Today's quiz · \(viewModel.questionCount) questions")
                        .dsFont(15).foregroundStyle(.secondary)
                }
                metaRow.padding(.vertical, 4)
                if store.streak > 0 { streakCard }
                Button { gateRequested = true } label: {
                    Text("Start the quiz")
                        .dsFont(17, weight: .semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("A fresh quiz each day — one attempt. Points add to your Superfan total.")
                    .dsFont(12).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            .padding(20)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 0) {
            metaItem("\(viewModel.questionCount)", "questions")
            Divider().frame(height: 32)
            metaItem("Daily", "new quiz")
            Divider().frame(height: 32)
            metaItem("\(viewModel.questionCount)", "max points")
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metaItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).dsFont(17, weight: .semibold).foregroundStyle(accent)
            Text(label).dsFont(11).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var streakCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill").dsFont(18).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.streak)-day streak").dsFont(13, weight: .bold)
                Text("Keep it going — play every day").dsFont(11).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Question (dots + tap-to-answer)

    @ViewBuilder
    private var questionView: some View {
        if let question = viewModel.currentQuestion {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    progressHeader(question)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 20)).foregroundStyle(accent)
                            .frame(width: 44, height: 44)
                            .background(accent.opacity(0.14), in: Circle())
                        Text(question.question)
                            .dsFont(20, weight: .bold).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 12) {
                        ForEach(question.options.indices, id: \.self) { index in
                            optionRow(question: question, index: index)
                        }
                    }
                    Text("Tap an answer — auto-advances")
                        .dsFont(11).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
    }

    private func progressHeader(_ question: TriviaQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Question \(viewModel.questionNumber) of \(viewModel.questionCount)")
                    .dsFont(12, weight: .semibold).foregroundStyle(.secondary)
                Spacer()
                Text(question.category.label.uppercased())
                    .dsFont(11, weight: .bold)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(accent.opacity(0.14)).foregroundStyle(accent).clipShape(Capsule())
            }
            HStack(spacing: 6) {
                ForEach(0..<viewModel.questionCount, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.questionNumber ? accent : Color.dsBgTertiary)
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    private func optionRow(question: TriviaQuestion, index: Int) -> some View {
        let style = optionStyle(question: question, index: index)
        return Button {
            answer(index)
        } label: {
            HStack(spacing: 14) {
                Text(letter(index))
                    .font(.subheadline.weight(.bold))
                    .frame(width: 26, height: 26)
                    .background(style.badgeFill).foregroundStyle(style.badgeText)
                    .clipShape(Circle())
                Text(question.options[index])
                    .dsFont(17).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let icon = style.trailingIcon {
                    Image(systemName: icon).foregroundStyle(style.borderColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.fill)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(style.borderColor, lineWidth: style.borderWidth))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRevealed)
    }

    // MARK: - Result (score ring + community)

    private func resultView() -> some View {
        ScrollView {
            VStack(spacing: 24) {
                ScoreRing(score: displayScore, total: viewModel.questionCount, accent: accent)
                    .padding(.top, 12)
                VStack(spacing: 8) {
                    Text(feelGoodTitle).dsFont(22, weight: .bold).multilineTextAlignment(.center)
                    if let learned = learnLine {
                        Text(learned).dsFont(15).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                }
                if displayScore > 0 {
                    Text("+\(displayScore) points")
                        .dsFont(17, weight: .semibold).foregroundStyle(accent)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(accent.opacity(0.14)).clipShape(Capsule())
                }
                statMiniCards
                // The community "how everyone did" panel IS the post-game payoff (the old Review list was
                // dropped as a duplicate). Trivia reveals it after the day closes (server-decided).
                if let edition = store.lastCompletedDay {
                    CommunityResultsView(game: "trivia", editionKey: edition,
                                         questions: triviaCommunityQuestions, accent: accent,
                                         pendingWrite: writeTask)
                }
                Button { dismiss() } label: {
                    Text("Back to Fan Zone")
                        .dsFont(17, weight: .semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Come back tomorrow for a fresh set of five — keep your streak alive!")
                    .dsFont(11).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            .padding(20)
        }
    }

    private var statMiniCards: some View {
        HStack(spacing: 8) {
            miniStat(icon: "flame.fill", tint: .orange, value: "\(store.streak)", label: "day streak")
            miniStat(icon: "target", tint: accent,
                     value: "\(Int((store.accuracy * 100).rounded()))%", label: "all-time")
        }
    }

    private func miniStat(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).dsFont(15, weight: .bold)
                Text(label).dsFont(10).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    /// Tap-to-answer: lock + reveal immediately, then auto-advance (~1.2s). Guarded so a second tap during
    /// the reveal is ignored. Mirrors Know Her Game's `answer(_:)`.
    private func answer(_ index: Int) {
        guard !viewModel.isRevealed else { return }
        viewModel.select(index)
        viewModel.submit()
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if viewModel.isLastQuestion { finishFlow() } else { viewModel.advance() }
            }
        }
    }

    /// Bank the day's score, fire achievements, write the community answers, flip to the result.
    private func finishFlow() {
        guard !viewModel.isFinished else { return }
        store.recordCompletion(correct: viewModel.score, outOf: viewModel.questionCount)
        viewModel.finish()
        // Game Center (additive): achievements only. NWSL Trivia has no competitive leaderboard — the
        // community-results panel replaces it; the Superfan total gets the lifetime-correct count via syncAll.
        if viewModel.score == viewModel.questionCount {
            GameCenterManager.shared.report(GameCenterID.Achievement.triviaPerfectDay)
        }
        if store.bestStreak >= 7 { GameCenterManager.shared.report(GameCenterID.Achievement.triviaStreak7) }
        if store.bestStreak >= 30 { GameCenterManager.shared.report(GameCenterID.Achievement.triviaStreak30) }
        // Signed in (gated at Start) → persist per-question answers to the shared community aggregate.
        if let userID = auth.userID, let edition = store.lastCompletedDay {
            let answers = viewModel.communityAnswers()
            // Hold the write so the community panel can await it before fetching (see writeTask).
            writeTask = Task {
                await QuizResultsService().upsert(game: "trivia", editionKey: edition,
                    answers: answers, userID: userID, season: String(AppConfig.currentSeasonYear))
            }
        }
    }

    // MARK: - Derived

    /// The just-played session score, or today's banked score on a locked re-open.
    private var displayScore: Int { viewModel.isFinished ? viewModel.score : store.lastScore }

    private var feelGoodTitle: String {
        let total = viewModel.questionCount
        let pct = total > 0 ? Int((Double(displayScore) / Double(total) * 100).rounded()) : 0
        switch pct {
        case 100: return "Perfect — you really know your league!"
        case 80...: return "You know your league!"
        case 60...: return "Getting there!"
        default: return "We all start somewhere 🌱"
        }
    }

    /// The learning payoff — the correct answer to the first question you missed (Trivia questions carry no
    /// standalone fact, so the answer itself is the "learn". Only after a fresh play, when picks exist).
    private var learnLine: String? {
        guard viewModel.isFinished else { return nil }
        for (q, pick) in zip(viewModel.questions, viewModel.picks) where pick != q.correctIndex {
            return "The answer was \(q.correctAnswer)."
        }
        return nil
    }

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) { await viewModel.loadDaily() }
    }

    // MARK: - Option styling (correct=dsSuccess, wrong pick=dsError)

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
            return OptionStyle(
                fill: isSelected ? accent.opacity(0.12) : base,
                borderColor: isSelected ? accent : Color.dsBgTertiary,
                borderWidth: isSelected ? 2 : 1,
                badgeFill: isSelected ? accent : Color.dsBgTertiary,
                badgeText: isSelected ? .white : .secondary,
                trailingIcon: nil
            )
        }
        if isCorrect {
            return OptionStyle(
                fill: Color.dsSuccess.opacity(0.14), borderColor: Color.dsSuccess, borderWidth: 2,
                badgeFill: Color.dsSuccess, badgeText: .white, trailingIcon: "checkmark"
            )
        }
        if isSelected {
            return OptionStyle(
                fill: Color.dsError.opacity(0.12), borderColor: Color.dsError, borderWidth: 2,
                badgeFill: Color.dsError, badgeText: .white, trailingIcon: "xmark"
            )
        }
        return OptionStyle(
            fill: base, borderColor: Color.dsBgTertiary, borderWidth: 1,
            badgeFill: Color.dsBgTertiary, badgeText: .secondary, trailingIcon: nil
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
