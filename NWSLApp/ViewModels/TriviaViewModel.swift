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

    /// Questions per round (the biweekly redesign: 10, up from the daily 5 — 8/10 feels
    /// earned where 3/5 felt punishing).
    private let roundCount = 10

    /// Fixed seed for the one-time "cycle order" shuffle. Constant (not the round
    /// number) so the pool's playback order is the same on every device and every
    /// round; only the *page* into it advances per round. ("nWSLTRV1" as hex.)
    private static let cycleSeed: UInt64 = 0x6E57_534C_5452_5631

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

    /// Load the live question pool (proxy `/trivia`) and lock in a round's deterministic 10.
    /// `round: nil` = the LIVE round (play); passing a round = that round's slate (review —
    /// determinism recomputes exactly what that round served). Online-only: any failure —
    /// network error or an empty pool (no playable quiz) — surfaces as an honest error with
    /// "Try again"; there is no seed fallback.
    func loadRound(_ requested: Int? = nil) async {
        state = .loading
        // Before Trivia's first-ever round (a fresh preseason install), fall back to round 1's
        // slate rather than erroring — the gate on PLAYING is the store's, not the loader's.
        round = requested ?? FanZoneCadence.roundNumber(for: .trivia, at: now()) ?? 1
        do {
            let all = try await service.triviaQuestions()
            questions = Self.roundSelection(from: all, roundNumber: round, count: roundCount)
            resetSession()
            state = .loaded
        } catch {
            Diagnostics.shared.record(.apiFailure, "trivia load: \(error.localizedDescription)")
            state = .error("Couldn't load this round's trivia — tap to retry.")
        }
    }

    /// Pure, NON-REPEATING per-round slice (factored out so it's unit-testable without
    /// the network/clock). Sort by id (so the result is independent of the backend's
    /// ordering), shuffle ONCE with a fixed seed (the stable cycle order), then take
    /// the round-numbered block of `count`, wrapping at the end. The whole pool plays
    /// before any question repeats.
    static func roundSelection(from all: [TriviaQuestion], roundNumber: Int, count: Int) -> [TriviaQuestion] {
        let n = all.count
        guard n > 0, count > 0 else { return [] }

        let ordered = all.sorted { $0.id < $1.id }
        var generator = SeededGenerator(seed: cycleSeed)
        let cycle = ordered.shuffled(using: &generator)

        let take = min(count, n)
        // Round N → block N−1 (rounds are 1-based), wrapping. The extra `+ n) % n`
        // keeps a defensive round-0/negative input non-crashing.
        let start = (((roundNumber - 1) * take) % n + n) % n
        return (0..<take).map { cycle[(start + $0) % n] }
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

/// A tiny deterministic RNG (SplitMix64) so the round's question pick is stable for
/// a given seed — same round in, same 10 questions out, on every device.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
