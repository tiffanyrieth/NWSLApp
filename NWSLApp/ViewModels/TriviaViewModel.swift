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
//  Daily selection: the 5 questions are a DETERMINISTIC, NON-REPEATING slice of
//  the pool. The pool is sorted by id (so the order is independent of however the
//  backend returns it), shuffled ONCE by a fixed-seed SplitMix64 (the stable
//  "cycle order", identical on every device), then paged by the local day number
//  (day N → questions [N*5 ..< N*5+5], wrapping). So a ~500-question pool yields
//  ~100 days of unique sets before any repeat — the whole point of a large live
//  pool — while staying stable all day with no persistence (the day IS the index).
//  (Earlier this re-shuffled the whole pool per day, which overlapped across days
//  and squandered a large pool's longevity.)
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

    /// Real league-wide best-streak standings, fetched in `refreshLeaderboard`.
    /// You are spliced in from your live local best streak. Empty until loaded.
    private(set) var leaderboard: [LeaderboardRow] = []

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

    /// Fixed seed for the one-time "cycle order" shuffle. Constant (not the day
    /// number) so the pool's playback order is the same on every device and every
    /// day; only the *page* into it advances daily. ("nWSLTRV1" as hex.)
    private static let cycleSeed: UInt64 = 0x6E57_534C_5452_5631

    private let service: TriviaService
    private let leaderboardService: TriviaLeaderboardService
    private let calendar: Calendar
    private let now: () -> Date

    /// The league-wide best-streak season key (matches the Supabase column default).
    private static let currentSeason = "2026"

    init(
        service: TriviaService = TriviaService(),
        leaderboardService: TriviaLeaderboardService = TriviaLeaderboardService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.leaderboardService = leaderboardService
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Loading

    /// Load the live question pool (proxy `/trivia`) and lock in today's deterministic
    /// 5. Online-only: any failure — network error or an empty pool (no playable quiz)
    /// — surfaces as an honest error with "Try again"; there is no seed fallback.
    func loadDaily() async {
        state = .loading
        do {
            let all = try await service.triviaQuestions()
            questions = dailyQuestions(from: all)
            resetSession()
            state = .loaded
        } catch {
            state = .error("Couldn't load today's trivia — tap to retry.")
        }
    }

    /// Today's deterministic 5: derive the local day number, then delegate to the
    /// pure `dailySelection` slice.
    private func dailyQuestions(from all: [TriviaQuestion]) -> [TriviaQuestion] {
        let startOfToday = calendar.startOfDay(for: now())
        let dayNumber = Int(startOfToday.timeIntervalSinceReferenceDate / 86_400)
        return Self.dailySelection(from: all, dayNumber: dayNumber, count: dailyCount)
    }

    /// Pure, NON-REPEATING daily slice (factored out so it's unit-testable without
    /// the network/clock). Sort by id (so the result is independent of the
    /// backend's ordering), shuffle ONCE with a fixed seed (the stable cycle
    /// order), then take the day-numbered block of `count`, wrapping at the end.
    /// The whole pool plays before any question repeats.
    static func dailySelection(from all: [TriviaQuestion], dayNumber: Int, count: Int) -> [TriviaQuestion] {
        let n = all.count
        guard n > 0, count > 0 else { return [] }

        let ordered = all.sorted { $0.id < $1.id }
        var generator = SeededGenerator(seed: cycleSeed)
        let cycle = ordered.shuffled(using: &generator)

        let take = min(count, n)
        // day N → block N, wrapping. The extra `+ n) % n` keeps it non-negative
        // for pre-2001 dates (negative day numbers).
        let start = ((dayNumber * take) % n + n) % n
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

    // MARK: - Leaderboard (REAL, league-wide best-streak via Supabase)

    struct LeaderboardRow: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let streak: Int
        let isYou: Bool
    }

    /// Push the user's best streak (signed-in only; best-effort) then read the
    /// world-readable standings and splice the user's LIVE local best streak in
    /// (fresher than any just-written row, and the only row when signed out). No
    /// fabricated rivals — a sparse board (just you) early on is the honest state.
    /// Safe to call on every results-screen appearance; idempotent.
    func refreshLeaderboard(store: TriviaStore, auth: AuthStore) async {
        let season = Self.currentSeason

        if let userID = auth.userID {
            await leaderboardService.upsertScore(
                bestStreak: store.bestStreak, displayName: auth.displayName,
                userID: userID, season: season)
        }

        let standings = await leaderboardService.standings(season: season)
        let myID = auth.userID?.uuidString
        var entries = standings
            .filter { $0.userID != myID }
            .map { (name: $0.name, streak: $0.bestStreak, isYou: false) }
        entries.append((name: auth.displayName ?? "You", streak: store.bestStreak, isYou: true))
        entries.sort { $0.streak != $1.streak ? $0.streak > $1.streak : ($0.isYou && !$1.isYou) }
        leaderboard = entries.enumerated().map { i, e in
            LeaderboardRow(rank: i + 1, name: e.name, streak: e.streak, isYou: e.isYou)
        }
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
