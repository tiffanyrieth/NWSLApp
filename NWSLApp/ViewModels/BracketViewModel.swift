//
//  BracketViewModel.swift
//  NWSLApp
//
//  Owns one Bracket Battle session — Fan Zone game 2 (0.3.9, LIVE). Same
//  idle/loading/loaded/error State as every other view model. Durable per-user state
//  (picks, submission, banked points) lives in BracketStore; this view model owns the
//  DERIVED view of the current edition fetched from BracketService (Supabase-backed,
//  offline-sample fallback): the round in play, its phase, the user's progress, the
//  results of a closed round, and the leaderboard.
//
//  A round's phase is resolved against an injectable clock ("now"), never stored:
//   • open      — current round, not submitted, before close → editable/submittable
//   • submitted — committed, awaiting the community tally
//   • closed    — deadline passed and never submitted (missed this round)
//   • scored    — round resolved + you submitted → has points
//

import Foundation

@Observable
final class BracketViewModel {
    enum State { case idle, loading, loaded, error(String) }
    enum RoundPhase { case open, submitted, closed, scored }

    private(set) var state: State = .idle
    private(set) var edition: BracketEdition?
    private(set) var leaderboard: [BracketLeaderboardRow] = []

    private let service: BracketService
    private let now: () -> Date

    init(service: BracketService = BracketService(), now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
    }

    // MARK: - Loading

    /// Fetch the active edition, cache its summary for the Home gate, score any
    /// settled-but-unscored round, and load the leaderboard. No active edition →
    /// loaded with `edition == nil` (the game hides), never an error.
    func load(store: BracketStore, userID: UUID? = nil, displayName: String? = nil) async {
        state = .loading
        guard let edition = await service.currentEdition() else {
            store.clearActiveEdition()
            self.edition = nil
            state = .loaded
            return
        }
        self.edition = edition
        store.adopt(summary: .init(
            id: edition.id, title: edition.title,
            currentRoundRaw: edition.currentRound.rawValue,
            roundClosesAt: edition.roundClosesAt, isActive: true
        ))
        await scoreSettledRounds(edition: edition, store: store)
        leaderboard = await service.leaderboard(myPoints: store.points,
                                                myName: displayName ?? "You", editionID: edition.id)
        state = .loaded
    }

    /// For each round the user submitted but isn't scored yet, if its real tally has
    /// resolved, run BracketScoring and bank the points (once).
    private func scoreSettledRounds(edition: BracketEdition, store: BracketStore) async {
        for round in edition.rounds where store.hasSubmitted(round) && store.score(for: round) == nil {
            var resolved = edition.matchups(in: round)
            if !resolved.contains(where: { $0.isResolved }) {
                resolved = await service.results(editionID: edition.id, round: round)
            }
            guard resolved.contains(where: { $0.isResolved }) else { continue }
            let points = BracketScoring.roundPoints(picks: store.picks(for: round), matchups: resolved)
            store.recordScore(points, for: round)
        }
    }

    // MARK: - Current round derivation

    var currentRound: BracketRound? { edition?.currentRound }

    var currentMatchups: [BracketMatchup] {
        guard let edition else { return [] }
        return edition.matchups(in: edition.currentRound)
    }

    /// The phase of the current round for this user.
    func phase(store: BracketStore) -> RoundPhase {
        guard let edition else { return .closed }
        let round = edition.currentRound
        if store.score(for: round) != nil { return .scored }
        if store.hasSubmitted(round) { return .submitted }
        if let closes = edition.roundClosesAt, now() >= closes { return .closed }
        return .open
    }

    func picksMade(store: BracketStore) -> Int {
        guard let edition else { return 0 }
        return store.picks(for: edition.currentRound).count
    }

    var totalMatchups: Int { currentMatchups.count }

    func allPicksMade(store: BracketStore) -> Bool {
        totalMatchups > 0 && picksMade(store: store) == totalMatchups
    }

    /// "Closes in 1d 8h" for the current round.
    var closesInText: String? {
        guard let closes = edition?.roundClosesAt else { return nil }
        let secs = closes.timeIntervalSince(now())
        guard secs > 0 else { return "Closing" }
        let h = Int(secs) / 3600
        if h >= 24 { return "Closes in \(h / 24)d \(h % 24)h" }
        if h >= 1 { return "Closes in \(h)h" }
        return "Closes in \(Int(secs) / 60)m"
    }

    // MARK: - Mutation

    func setPick(matchup: BracketMatchup, entrantID: String, store: BracketStore) {
        guard let round = currentRound else { return }
        store.setPick(matchupID: matchup.id, entrantID: entrantID, round: round)
    }

    /// Commit the current round and persist the votes to the backend. `userID` comes
    /// from the sign-in gate at the call site (votes are owner-scoped); a nil id
    /// records the local submit only.
    func submit(store: BracketStore, userID: UUID?) async {
        guard let edition, allPicksMade(store: store) else { return }
        let round = edition.currentRound
        store.submit(round: round)
        if let userID {
            await service.submit(editionID: edition.id, round: round,
                                 picks: store.picks(for: round), userID: userID)
        }
    }

    // MARK: - Results (a closed round)

    /// Resolved matchups for the most recently completed round (for the Results
    /// screen), or nil if no round has closed yet.
    func completedResults() -> (round: BracketRound, matchups: [BracketMatchup])? {
        guard let edition else { return nil }
        for round in edition.rounds.reversed() where round < edition.currentRound {
            let ms = edition.matchups(in: round)
            if ms.contains(where: { $0.isResolved }) { return (round, ms) }
        }
        return nil
    }
}
