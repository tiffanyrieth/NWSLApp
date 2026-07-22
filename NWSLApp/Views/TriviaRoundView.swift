//
//  TriviaRoundView.swift
//  NWSLApp
//
//  NWSL Trivia — the community-family quiz, one biweekly ROUND per session (renamed from
//  DailyTriviaView with the round rebuild). Shares Know Her Game's interface family: an INTRO screen,
//  progress DOTS (not a bar), TAP-TO-ANSWER with ~1.2s auto-advance (no Submit button), a shared SCORE
//  RING, a score-based feel-good title, a "+N points" Superfan pill, and the shared
//  `CommunityResultsView` "how everyone did" panel (the community panel IS the post-game payoff).
//
//  ROUND MODEL: 10 questions per biweekly round (FanZoneCadence), one scored play per round; the round
//  streak replaces the day streak. `Entry` mirrors KHG: `.play` = the LIVE round (intro → questions →
//  result, locked to a recap once played); `.review(round:)` = a PAST round's read-only recap — the
//  slate recomputes deterministically from the pool, the score/picks come from TriviaStore. Entry
//  routes through TriviaLandingView (the front door), not straight from Home.
//
//  Sign-in + a chosen display name are gated at "Start the quiz" (community answers are always
//  written signed in).
//

import SwiftUI

struct TriviaRoundView: View {
    /// How this screen was entered — the live round, or a past round's read-only recap.
    enum Entry: Equatable {
        case play
        case review(round: Int)
    }

    var entry: Entry = .play

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
                ProgressView("Loading the round…")
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
            if case .idle = viewModel.state {
                if case .review(let round) = entry {
                    await viewModel.loadRound(round)
                } else {
                    await viewModel.loadRound()
                }
            }
        }
    }

    /// The round's questions as game-agnostic descriptors for the community-results panel.
    private var triviaCommunityQuestions: [CommunityResultsView.QuestionInfo] {
        viewModel.questions.map { .init(id: $0.id, prompt: $0.question, options: $0.options, correctIndex: $0.correctIndex) }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if case .review = entry {
            resultView()                      // past-round recap (read-only; score from the store)
        } else if viewModel.isFinished {
            resultView()                      // just-finished session
        } else if store.hasPlayedCurrentRound {
            resultView()                      // already played this round → locked recap
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
                    Text("Round \(viewModel.round) · \(viewModel.questionCount) questions")
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
                Text("A fresh round every two weeks — one attempt. Points add to your Superfan total.")
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
            metaItem("2 wks", "per round")
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
                Text("\(store.streak)-round streak").dsFont(13, weight: .bold)
                Text("Keep it going — play every round").dsFont(11).foregroundStyle(.secondary)
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
                if reviewedWithoutPlaying {
                    // KHG rule: last round's community results are browsable even if you sat it out —
                    // but never render a lying 0/10 ring for a round that was simply not played.
                    VStack(spacing: 8) {
                        Text("Round \(viewModel.round)").dsFont(22, weight: .bold)
                        Text("You didn't play this one — here's how everyone did.")
                            .dsFont(15).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .padding(.top, 12)
                } else {
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
                }
                // The community "how everyone did" panel IS the post-game payoff (the old Review list
                // was dropped as a duplicate). Live from the first responder, KHG-style.
                CommunityResultsView(game: "trivia", editionKey: viewModel.editionKey,
                                     questions: triviaCommunityQuestions, accent: accent,
                                     pendingWrite: writeTask)
                Button { dismiss() } label: {
                    Text("Back to Fan Zone")
                        .dsFont(17, weight: .semibold).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("A fresh 10 drop with every round — keep your streak alive!")
                    .dsFont(11).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            .padding(20)
        }
    }

    private var statMiniCards: some View {
        HStack(spacing: 8) {
            miniStat(icon: "flame.fill", tint: .orange, value: "\(store.streak)", label: "round streak")
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

    /// Bank the round's score, fire achievements, write the community answers, flip to the result.
    private func finishFlow() {
        guard !viewModel.isFinished else { return }
        store.recordCompletion(round: viewModel.round, editionKey: viewModel.editionKey,
                               correct: viewModel.score, outOf: viewModel.questionCount,
                               picks: viewModel.picks)
        viewModel.finish()
        // Game Center (additive): achievements only. NWSL Trivia has no competitive leaderboard — the
        // community-results panel replaces it; the Superfan total gets the season-correct count via syncAll.
        // The streak achievements now count ROUNDS (identifiers kept; 7 rounds ≈ a whole season showing up).
        if viewModel.score == viewModel.questionCount {
            GameCenterManager.shared.report(GameCenterID.Achievement.triviaPerfectDay)
        }
        if store.bestStreak >= 7 { GameCenterManager.shared.report(GameCenterID.Achievement.triviaStreak7) }
        if store.bestStreak >= 30 { GameCenterManager.shared.report(GameCenterID.Achievement.triviaStreak30) }
        // Signed in (gated at Start) → persist per-question answers to the shared community aggregate,
        // and push the progress summary (the reinstall-restore row — partial columns, trivia's only).
        if let userID = auth.userID {
            let answers = viewModel.communityAnswers()
            let edition = viewModel.editionKey
            // Hold the write so the community panel can await it before fetching (see writeTask).
            writeTask = Task {
                await QuizResultsService().upsert(game: "trivia", editionKey: edition,
                    answers: answers, userID: userID, season: String(AppConfig.currentSeasonYear))
            }
            let p = store.progressSnapshot()
            Task {
                await ProgressSyncService().uploadTrivia(
                    lifetimeCorrect: p.lifetimeCorrect, lifetimeAnswered: p.lifetimeAnswered,
                    bestStreak: p.bestStreak, seasonCorrect: p.seasonCorrect,
                    roundStreak: p.roundStreak, lastRound: p.lastRound,
                    userID: userID, season: String(AppConfig.currentSeasonYear))
            }
        }
    }

    // MARK: - Derived

    /// The just-played session score, or the banked score for this round (live recap / review).
    private var displayScore: Int {
        viewModel.isFinished ? viewModel.score : (store.score(editionKey: viewModel.editionKey) ?? 0)
    }

    /// Reviewing a round the user never played — community results only, no personal score UI.
    private var reviewedWithoutPlaying: Bool {
        if case .review = entry { return store.score(editionKey: viewModel.editionKey) == nil }
        return false
    }

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
        RetryStateView(message: message) {
            if case .review(let round) = entry {
                await viewModel.loadRound(round)
            } else {
                await viewModel.loadRound()
            }
        }
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
        TriviaRoundView()
            .environment(TriviaStore())
            .environment(AuthStore())
    }
}
