//
//  TriviaViewModel.swift
//  NWSLApp
//
//  Owns one NWSL Trivia *session* — the biweekly 10-question round being played (or
//  reviewed) right now. Same idle/loading/loaded/error State shape as the other view
//  models, here tracking the question-bank load. The durable stats (round streak,
//  accuracy, the round-gate) are NOT here — they live in TriviaStore.
//
//  Round selection: the round's 10 questions are a DETERMINISTIC, NON-REPEATING slice
//  of the pool. The pool is sorted by id (so the order is independent of however the
//  backend returns it), shuffled ONCE by a fixed-seed SplitMix64 (the stable "cycle
//  order", identical on every device), then paged by the ROUND number (round N →
//  questions [(N−1)*10 ..< N*10], wrapping). Determinism is what makes review work
//  with no stored questions: last round's slate recomputes from the same pool + the
//  round number, so only the user's picks/score need persisting (TriviaStore).
//  ⚠️ Wrapping honesty: today's ~41-question pool covers 4 rounds before questions
//  repeat — an accepted interim until the annual content-generation pipeline stocks
//  the full pool (roadmap; the 530-question target = 53 rounds, zero repeats).
//
//  Flow per question: select an option (changeable) → submit (locks + reveals
//  correct/incorrect) → next (advance), matching the spec's "tap to select, tap
//  Next to advance, see correct/incorrect immediately after submitting."
//
//  (The old league-wide best-streak leaderboard was retired — the community
//  "how everyone did" panel replaced it; its dead service/rows are gone.)
//

import Foundation

@Observable
final class TriviaViewModel {
    enum State {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private(set) var state: State = .idle

    /// The round's 10 questions (empty until `.loaded`).
    private(set) var questions: [TriviaQuestion] = []

    /// The round this session belongs to (the live round for play; a past round for review).
    private(set) var round: Int = 1

    // MARK: Session state (transient — reset each play)

    private(set) var currentIndex = 0
    /// The option tapped for the current question. Changeable until `submit()`.
    private(set) var selectedIndex: Int?
    /// True once the current answer is submitted (correct/incorrect now shown).
    private(set) var isRevealed = false
    /// Running tally of correct answers this session.
    private(set) var correctCount = 0
    /// The option the user picked for each answered question, for the recap.
    private(set) var picks: [Int] = []
    /// True once the last question's results have been requested.
    private(set) var isFinished = false

    private let service: TriviaService
    private let now: () -> Date

    init(
        service: TriviaService = TriviaService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.now = now
    }

    /// The edition key this session banks/reads under (matches TriviaStore + `quiz_answers`).
    var editionKey: String {
        FanZoneCadence.editionKey(round: round, seasonYear: FanZoneCadence.seasonYear)
    }

    // MARK: - Loading

    /// Load a round's questions from the proxy `/trivia?round=<editionKey>` route. `round: nil` = the LIVE
    /// round (play); passing a round = that round's slate (review). The proxy returns the 10 questions the
    /// yearly pipeline PRE-ASSIGNED to that round (roadmap #2) — the app no longer slices a pool client-side,
    /// so a round's questions are the same for everyone and never repeat within the season. Only the current
    /// or a specific (previous) round is ever fetched — never the whole year. Online-only: any failure — a
    /// network error or an empty round (no playable quiz) — surfaces an honest error; no seed fallback.
    func loadRound(_ requested: Int? = nil) async {
        state = .loading
        // Before Trivia's first-ever round (a fresh preseason install), fall back to round 1 rather than
        // erroring — the gate on PLAYING is the store's, not the loader's.
        round = requested ?? FanZoneCadence.roundNumber(for: .trivia, at: now()) ?? 1
        do {
            questions = try await service.triviaQuestions(round: editionKey)
            resetSession()
            state = .loaded
        } catch {
            Diagnostics.shared.record(.apiFailure, "trivia load \(editionKey): \(error.localizedDescription)")
            state = .error("Couldn't load this round's trivia. Tap to retry.")
        }
    }

    private func resetSession() {
        currentIndex = 0
        selectedIndex = nil
        isRevealed = false
        correctCount = 0
        picks = []
        isFinished = false
    }

    // MARK: - Derived

    var currentQuestion: TriviaQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    var questionNumber: Int { currentIndex + 1 }
    var questionCount: Int { questions.count }
    var isLastQuestion: Bool { currentIndex == questions.count - 1 }

    /// Whether the submitted answer was correct (only meaningful once revealed).
    var isCurrentCorrect: Bool {
        guard let selectedIndex, let q = currentQuestion else { return false }
        return selectedIndex == q.correctIndex
    }

    /// This session's score so far.
    var score: Int { correctCount }

    // MARK: - Actions

    /// Pick (or change) an answer — only allowed before submitting.
    func select(_ index: Int) {
        guard !isRevealed else { return }
        selectedIndex = index
    }

    /// Lock the current answer and reveal correctness.
    func submit() {
        guard !isRevealed, let selectedIndex, let q = currentQuestion else { return }
        isRevealed = true
        picks.append(selectedIndex)
        if selectedIndex == q.correctIndex { correctCount += 1 }
    }

    /// Advance to the next question (resets the per-question state).
    func advance() {
        guard isRevealed, !isLastQuestion else { return }
        currentIndex += 1
        selectedIndex = nil
        isRevealed = false
    }

    /// Finish the session (called from the last question's results button).
    func finish() {
        guard isRevealed, isLastQuestion else { return }
        isFinished = true
    }

    /// The per-question answers to persist to the shared community aggregate (`quiz_answers`,
    /// game "trivia") — one row per answered question, built from `picks` vs the round's questions.
    /// Powers the NYT-style "how everyone did" screen (docs §11b).
    func communityAnswers() -> [QuizAnswer] {
        zip(questions, picks).map { question, pick in
            QuizAnswer(questionID: question.id, selectedIndex: pick, isCorrect: pick == question.correctIndex)
        }
    }
}
