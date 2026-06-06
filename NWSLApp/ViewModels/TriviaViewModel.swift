//
//  TriviaViewModel.swift
//  NWSLApp
//
//  Owns one Daily-Trivia *session* — Home's Module 3 "Play", game 1. Same
//  idle/loading/loaded/error State shape as the other view models, here tracking
//  the question-bank load. The durable stats (streak, accuracy, the day-gate)
//  are NOT here — they live in TriviaStore; this only holds the transient state
//  of the 5 questions being played right now.
//
//  Daily selection: the 5 questions are drawn from the pool by a DETERMINISTIC
//  daily shuffle (a SplitMix64 RNG seeded by the local day number), so everyone
//  gets a stable set all day and the pool rotates as days pass — no persistence
//  needed, the day itself is the seed (spec §"Shuffle and serve 5 per day").
//
//  Flow per question: select an option (changeable) → submit (locks + reveals
//  correct/incorrect) → next (advance), matching the spec's "tap to select, tap
//  Next to advance, see correct/incorrect immediately after submitting."
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

    /// Today's 5 questions (empty until `.loaded`).
    private(set) var questions: [TriviaQuestion] = []

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

    /// How many questions to serve per day (spec: 5).
    private let dailyCount = 5

    private let provider: TriviaQuestionProvider
    private let calendar: Calendar
    private let now: () -> Date

    init(
        provider: TriviaQuestionProvider = TriviaQuestionProvider(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Loading

    /// Load the question bank and lock in today's deterministic 5.
    func loadDaily() async {
        state = .loading
        let all = await provider.questions()
        guard !all.isEmpty else {
            state = .error("No trivia questions are available right now.")
            return
        }
        questions = dailyQuestions(from: all)
        resetSession()
        state = .loaded
    }

    /// Deterministic per-day pick: seed a SplitMix64 with the local day number,
    /// shuffle the pool, take the first `dailyCount`. Stable all day; rotates daily.
    private func dailyQuestions(from all: [TriviaQuestion]) -> [TriviaQuestion] {
        let startOfToday = calendar.startOfDay(for: now())
        let dayNumber = Int(startOfToday.timeIntervalSinceReferenceDate / 86_400)
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(dayNumber)))
        return Array(all.shuffled(using: &generator).prefix(dailyCount))
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
}

/// A tiny deterministic RNG (SplitMix64) so the daily question pick is stable for
/// a given seed — same day in, same 5 questions out, on every device.
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
