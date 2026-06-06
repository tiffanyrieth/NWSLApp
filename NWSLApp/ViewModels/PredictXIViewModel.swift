//
//  PredictXIViewModel.swift
//  NWSLApp
//
//  Owns one Predict the XI "session" — Home's Module 3 "Play", game 3. Same
//  idle/loading/loaded/error State shape as the other view models. The durable
//  state (the user's picks + a season-points snapshot) lives in PredictionStore;
//  this view model owns the DERIVED slate: which matches are open vs settled, and
//  the scoring of every settled match against its answer key.
//
//  "Open vs settled" is the one thing the store can't know — it depends on the
//  current time. The seed carries kickoff as an offset from now (so the demo never
//  runs out of an open match — see PredictionMatch's header); this view model
//  resolves that offset against an injectable clock and decides lock state here.
//  Predictions lock at kickoff: a settled match is read-only and scored; an open
//  match is editable and never reveals its answers.
//
//  Scoring is the spec's difficulty-weighted sum: each correct pick earns its
//  category's points (formation 2, GK 1, captain 2, first scorer 3). The season
//  total feeds a simulated leaderboard (fixed sample opponents + "You"), exactly
//  like Bracket Battle, standing in for real multi-user scoring until a backend
//  exists. Club crests/names are resolved best-effort via the club directory; a
//  failed fetch leaves the game fully playable with abbreviations.
//

import Foundation

@Observable
final class PredictXIViewModel {
    enum State {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var matches: [PredictionMatch] = []
    private(set) var clubsByAbbr: [String: Club] = [:]

    private let provider: PredictionMatchProvider
    private let service: ESPNService
    private let now: () -> Date

    init(provider: PredictionMatchProvider = PredictionMatchProvider(),
         service: ESPNService = ESPNService(),
         now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.service = service
        self.now = now
    }

    // MARK: - Loading

    /// Load the slate, then push the freshly-scored season total into the store so
    /// the Home card stays in sync. The slate is a local seed (so the game always
    /// reaches `.loaded`); the club directory is best-effort enrichment for crests.
    func load(store: PredictionStore) async {
        if case .loaded = state { return }
        state = .loading

        matches = await provider.matches()

        // Best-effort crest/name resolution — a failure here must not break play.
        if let clubs = try? await service.fetchTeams() {
            clubsByAbbr = Dictionary(clubs.map { ($0.abbreviation, $0) }, uniquingKeysWith: { first, _ in first })
        }

        store.updateSeasonPoints(seasonPoints(store: store))
        state = .loaded
    }

    // MARK: - Lock state

    /// Kickoff for a match = now + its offset. Computed, never stored.
    func kickoff(for match: PredictionMatch) -> Date {
        now().addingTimeInterval(match.kickoffOffsetHours * 3600)
    }

    /// A match is settled once kickoff has passed — read-only, results revealed,
    /// and scored. Before kickoff it's open: editable, answers hidden.
    func isSettled(_ match: PredictionMatch) -> Bool {
        kickoff(for: match) <= now()
    }

    /// Matches still open to predict (soonest kickoff first), then the settled ones
    /// (most recent first) — the order the slate renders top-to-bottom.
    var openMatches: [PredictionMatch] {
        matches.filter { !isSettled($0) }.sorted { kickoff(for: $0) < kickoff(for: $1) }
    }

    var settledMatches: [PredictionMatch] {
        matches.filter { isSettled($0) }.sorted { kickoff(for: $0) > kickoff(for: $1) }
    }

    // MARK: - Scoring

    /// Whether the user's pick for a question is correct (only meaningful once the
    /// match is settled — the answer key isn't revealed before kickoff).
    func isCorrect(_ question: PredictionQuestion, store: PredictionStore) -> Bool {
        store.pick(for: question.id) == question.correctOptionID
    }

    /// Points the user earned on one settled match (sum of correct picks' values).
    func points(for match: PredictionMatch, store: PredictionStore) -> Int {
        guard isSettled(match) else { return 0 }
        return match.questions
            .filter { isCorrect($0, store: store) }
            .reduce(0) { $0 + $1.points }
    }

    /// Total points across every settled match — the season score.
    func seasonPoints(store: PredictionStore) -> Int {
        settledMatches.reduce(0) { $0 + points(for: $1, store: store) }
    }

    /// How many of a match's questions the user has predicted (for the open-match
    /// "3 of 4 predicted" progress + the lock-in affordance).
    func predictedCount(for match: PredictionMatch, store: PredictionStore) -> Int {
        match.questions.filter { store.pick(for: $0.id) != nil }.count
    }

    func allPredicted(for match: PredictionMatch, store: PredictionStore) -> Bool {
        !match.questions.isEmpty && predictedCount(for: match, store: store) == match.questions.count
    }

    // MARK: - Picking

    /// Record a prediction for an open match. No-op once the match is settled (the
    /// store also guards, and the view disables the controls) so a result can't be
    /// edited after kickoff.
    func predict(_ optionID: String, for question: PredictionQuestion, in match: PredictionMatch, store: PredictionStore) {
        store.setPick(questionID: question.id, optionID: optionID, locked: isSettled(match))
    }

    /// Clear the slate and resync the (now zero) total — the demo's replay.
    func reset(store: PredictionStore) {
        store.reset()
        store.updateSeasonPoints(0)
    }

    // MARK: - Club lookup

    func club(forAbbreviation abbreviation: String) -> Club? { clubsByAbbr[abbreviation] }

    /// The short, chip-friendly club name (falls back to the abbreviation when the
    /// directory didn't resolve — the game stays playable offline).
    func teamLabel(_ abbreviation: String) -> String {
        let club = clubsByAbbr[abbreviation]
        return club?.shortName ?? club?.displayName ?? abbreviation
    }

    // MARK: - Leaderboard (simulated)

    struct LeaderboardRow: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let points: Int
        let isYou: Bool
    }

    /// The simulated season leaderboard: fixed sample opponents plus "You" (live
    /// season points), sorted high-to-low. On a tie, "You" sorts ahead so climbing
    /// reads cleanly. Replaced by a real board when a scoring backend exists.
    func leaderboard(store: PredictionStore) -> [LeaderboardRow] {
        var entries = provider.leaderboardOpponents().map { (name: $0.name, points: $0.points, isYou: false) }
        entries.append((name: "You", points: seasonPoints(store: store), isYou: true))
        entries.sort { lhs, rhs in
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            return lhs.isYou && !rhs.isYou
        }
        return entries.enumerated().map { index, entry in
            LeaderboardRow(rank: index + 1, name: entry.name, points: entry.points, isYou: entry.isYou)
        }
    }

    func yourRank(store: PredictionStore) -> Int {
        leaderboard(store: store).first(where: \.isYou)?.rank ?? 0
    }
}
