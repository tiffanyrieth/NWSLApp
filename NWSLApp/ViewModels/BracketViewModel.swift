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
    /// Online-only submit lifecycle: `.submitting` while the server write is in
    /// flight, `.failed` if it errored (the view shows "Couldn't submit — tap to
    /// retry"; picks stay editable). The local "locked in" state only flips on a real
    /// ack, so success is never faked ahead of the server.
    enum SubmitState: Equatable { case idle, submitting, failed }

    private(set) var state: State = .idle
    private(set) var submitState: SubmitState = .idle
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
    /// settled-but-unscored round, and load the leaderboard. Online-only: a fetch
    /// FAILURE is an honest `.error` (tap to retry) — no cached-edition fallback. A
    /// genuinely empty backend (no active edition) is loaded with `edition == nil`
    /// (the game hides), which is not an error.
    func load(store: BracketStore, userID: UUID? = nil, displayName: String? = nil) async {
        state = .loading
        let fetched: BracketEdition?
        do {
            fetched = try await service.currentEdition()
        } catch {
            state = .error("Couldn't load the bracket — tap to retry.")
            return
        }
        guard let edition = fetched else {
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

            // Game Center: push the banked total + the "Bracket Round Won" badge.
            // Best-effort, no-ops when not signed in. Additive on top of Supabase.
            await MainActor.run {
                GameCenterManager.shared.submit(store.points, to: GameCenterID.Leaderboard.bracketTotalPoints)
                if points > 0 { GameCenterManager.shared.report(GameCenterID.Achievement.bracketRoundWon) }
            }
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

    /// Commit the current round by persisting the votes to the backend, then — only
    /// on a successful server ack — flipping the local "locked in" state. `userID`
    /// comes from the sign-in gate at the call site (votes are owner-scoped). Online-
    /// only: a failed (or sign-in-less) write sets `.failed` so the picks stay editable
    /// and the view offers "tap to retry"; we never fake the lock-in ahead of the ack.
    func submit(store: BracketStore, userID: UUID?) async {
        guard let edition, allPicksMade(store: store) else { return }
        guard let userID else { submitState = .failed; return }
        let round = edition.currentRound
        submitState = .submitting
        do {
            try await service.submit(editionID: edition.id, round: round,
                                     picks: store.picks(for: round), userID: userID)
            store.submit(round: round)   // local lock — ONLY after the server ack
            submitState = .idle
        } catch {
            submitState = .failed
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

    // MARK: - Rotating fandom flavor (one per edition, deterministic)

    enum FandomFlavor { case upsetClosest, cinderella, nextEdition }

    /// The single flavor feature this edition surfaces — stable across all its rounds,
    /// rotating each new edition. Deterministic by edition id so everyone sees the same.
    var flavor: FandomFlavor {
        guard let id = edition?.id else { return .upsetClosest }
        switch Self.stableHash(id) % 3 {
        case 0: return .upsetClosest
        case 1: return .cinderella
        default: return .nextEdition
        }
    }

    /// Biggest upset of the most-recent completed round: the community winner who was
    /// the lower seed, by the largest seed gap. Nil if no upset (or no seeds/results).
    var biggestUpset: (winner: BracketEntrant, loser: BracketEntrant)? {
        guard let ms = completedResults()?.matchups else { return nil }
        var best: (winner: BracketEntrant, loser: BracketEntrant, gap: Int)?
        for m in ms {
            guard let winnerID = m.communityWinnerID, let winner = m.entrant(winnerID) else { continue }
            let loser = winner.id == m.entrantA.id ? m.entrantB : m.entrantA
            guard let ws = winner.seed, let ls = loser.seed, ws > ls else { continue }
            let gap = ws - ls
            if best == nil || gap > best!.gap { best = (winner, loser, gap) }
        }
        return best.map { ($0.winner, $0.loser) }
    }

    /// Closest call of the most-recent completed round (winner % nearest 50).
    var closestCall: (matchup: BracketMatchup, winnerPct: Int)? {
        guard let ms = completedResults()?.matchups else { return nil }
        return ms.compactMap { m in m.winnerPercent.map { (m, $0) } }
            .min { abs($0.1 - 50) < abs($1.1 - 50) }
            .map { (matchup: $0.0, winnerPct: $0.1) }
    }

    /// Lowest-ranked entrant still alive (a Cinderella run) — "alive" = in a current-
    /// round matchup. Highest seed *number* = lowest rank.
    var cinderella: BracketEntrant? {
        guard let edition else { return nil }
        let alive = edition.matchups(in: edition.currentRound).flatMap { [$0.entrantA, $0.entrantB] }
        return alive.max { ($0.seed ?? 0) < ($1.seed ?? 0) }
    }

    /// A stable (launch-independent) hash for deterministic flavor selection.
    private static func stableHash(_ s: String) -> Int {
        var h = 5381
        for byte in s.utf8 { h = ((h << 5) &+ h) &+ Int(byte) }
        return abs(h)
    }
}
