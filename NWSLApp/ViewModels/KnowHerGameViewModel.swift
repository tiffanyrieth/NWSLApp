//
//  KnowHerGameViewModel.swift
//  NWSLApp
//
//  Owns ONE Know Her Game session for one featured player (mirror of TriviaViewModel).
//  The questions come straight from the `KnowHerPlayer` (the store already fetched the
//  pool), so unlike Trivia there's no daily-slice or network load here — the view model
//  is pure transient session state: which question, the current pick, the reveal, the
//  running score, and the per-question picks (for the result recap + the community write).
//
//  Flow per question: select an option (changeable) → submit (locks + reveals
//  correct/incorrect) → auto-advance ~1.2s → … → finish (result screen).
//

import Foundation

@Observable
final class KnowHerGameViewModel {
    let player: KnowHerPlayer
    let weekKey: String

    private(set) var currentIndex = 0
    private(set) var selectedIndex: Int?
    private(set) var isRevealed = false
    private(set) var correctCount = 0
    /// The option picked for each answered question (parallel to `questions`), for the recap
    /// and the per-question community write.
    private(set) var picks: [Int] = []
    private(set) var isFinished = false

    init(player: KnowHerPlayer, weekKey: String) {
        self.player = player
        self.weekKey = weekKey
    }

    // MARK: - Derived

    var questions: [KnowHerQuestion] { player.questions }
    var currentQuestion: KnowHerQuestion? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }
    var questionNumber: Int { currentIndex + 1 }
    var questionCount: Int { questions.count }
    var isLastQuestion: Bool { currentIndex == questions.count - 1 }
    var score: Int { correctCount }
    var editionKey: String { player.editionKey(weekKey: weekKey) }

    var isCurrentCorrect: Bool {
        guard let selectedIndex, let q = currentQuestion else { return false }
        return selectedIndex == q.correctIndex
    }

    // MARK: - Actions

    /// Pick (or change) an answer — only before submitting.
    func select(_ index: Int) {
        guard !isRevealed else { return }
        selectedIndex = index
    }

    /// Lock the current answer and reveal correctness.
    func submit() {
        guard !isRevealed, let selectedIndex, currentQuestion != nil else { return }
        isRevealed = true
        picks.append(selectedIndex)
        if isCurrentCorrect { correctCount += 1 }
    }

    /// Advance to the next question (resets per-question state). No-op on the last.
    func advance() {
        guard isRevealed, !isLastQuestion else { return }
        currentIndex += 1
        selectedIndex = nil
        isRevealed = false
    }

    /// Finish the session — flips to the result screen (called on the last question).
    func finish() {
        guard isRevealed, isLastQuestion else { return }
        isFinished = true
    }

    /// The per-question answers to persist to the community aggregate (`quiz_answers`), one
    /// row per answered question. Built from `picks` against the question list.
    func communityAnswers() -> [QuizAnswer] {
        zip(questions, picks).map { question, pick in
            QuizAnswer(
                questionID: question.id,
                selectedIndex: pick,
                isCorrect: pick == question.correctIndex
            )
        }
    }
}
