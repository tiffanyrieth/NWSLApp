//
//  BracketStore.swift
//  NWSLApp
//
//  Durable Bracket Battle state — Home's Module 3 "Play", game 2 (per
//  Reference/Design/games-design-spec.md §"Game 2: Bracket Battle"). Like
//  TriviaStore / FollowingStore, this is shared app state (votes + points persist
//  across launches and surface on more than one screen — the game itself and the
//  Home Play card), so it lives in Stores/ and is injected app-wide via
//  `.environment` in RootTabView, not owned by a single view.
//
//  Persistence is UserDefaults (the spec: "voting and results stored locally for
//  demo"). It holds only what must outlive a session: the user's pick per matchup,
//  how many rounds they've locked (closed), the cumulative points, and the round
//  count of the active edition (so the Home card can show "Round 2 of 4" without
//  loading the edition). The bracket structure + simulated community results are
//  NOT here — those are derived in BracketViewModel from the edition.
//
//  Rounds lock IN ORDER and locking is idempotent: lockRound only advances when
//  it's the next round, so a re-tap can't double-count points. Per the approved
//  "play through, daily-styled" cadence, there is no calendar day-gate (unlike
//  TriviaStore) — the per-round lock → reveal → advance rhythm carries the feel.
//

import Foundation

@Observable
final class BracketStore {
    /// The edition these picks/points belong to. If the active edition changes,
    /// progress resets (so a new themed bracket starts clean).
    private(set) var editionID: String?

    /// matchup id → chosen entrant id (the user's vote). Persisted as JSON.
    private(set) var picks: [String: String]

    /// How many rounds the user has locked (closed). Since rounds lock in order,
    /// this single count is also the index of the current (next open) round.
    private(set) var lockedRoundCount: Int

    /// Cumulative points earned (1 per matchup where the pick matched the
    /// community's choice), across all locked rounds.
    private(set) var points: Int

    /// Total rounds in the active edition (4 for a 16-team bracket). Stored so the
    /// Home card can render progress without loading the edition seed.
    private(set) var roundCount: Int

    private let defaults: UserDefaults

    private enum Key {
        static let editionID = "bracket.editionID"
        static let picks = "bracket.picks"
        static let lockedRoundCount = "bracket.lockedRoundCount"
        static let points = "bracket.points"
        static let roundCount = "bracket.roundCount"
    }

    /// `defaults` is injectable so tests/previews use an isolated store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.editionID = defaults.string(forKey: Key.editionID)
        self.picks = Self.decodePicks(defaults.data(forKey: Key.picks))
        self.lockedRoundCount = defaults.integer(forKey: Key.lockedRoundCount)
        self.points = defaults.integer(forKey: Key.points)
        self.roundCount = defaults.integer(forKey: Key.roundCount)
    }

    // MARK: - Derived

    /// The first round that isn't locked yet — the one the user votes on next.
    var currentRound: Int { lockedRoundCount }

    /// True once any voting has happened (drives the Home card's "Play now" vs
    /// "Round n of N" copy).
    var hasStarted: Bool { lockedRoundCount > 0 || !picks.isEmpty }

    /// True once every round is locked (the tournament is decided).
    var isComplete: Bool { roundCount > 0 && lockedRoundCount >= roundCount }

    func pick(for matchupID: String) -> String? { picks[matchupID] }

    func isRoundLocked(_ round: Int) -> Bool { round < lockedRoundCount }

    // MARK: - Mutation

    /// Adopt an edition. Always refreshes the round count; resets all progress
    /// only when the edition actually changed (so reopening the same bracket keeps
    /// your picks). Call once when the game loads.
    func beginEdition(_ id: String, roundCount: Int) {
        self.roundCount = roundCount
        if editionID != id {
            editionID = id
            picks = [:]
            lockedRoundCount = 0
            points = 0
        }
        persist()
    }

    /// Record (or change) a vote — only allowed while that matchup's round is
    /// still open.
    func setPick(matchupID: String, entrantID: String, round: Int) {
        guard !isRoundLocked(round) else { return }
        picks[matchupID] = entrantID
        persist()
    }

    /// Close a round: bank the points and advance. Guarded to the next round and
    /// idempotent — re-calling for an already-locked round does nothing, so points
    /// can't be farmed by re-tapping.
    func lockRound(_ round: Int, pointsEarned: Int) {
        guard round == lockedRoundCount else { return }
        lockedRoundCount += 1
        points += pointsEarned
        persist()
    }

    /// Clear all progress for the current edition (keep the edition) — the demo's
    /// "Play again" after a tournament completes.
    func restart() {
        picks = [:]
        lockedRoundCount = 0
        points = 0
        persist()
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(editionID, forKey: Key.editionID)
        defaults.set(encodePicks(), forKey: Key.picks)
        defaults.set(lockedRoundCount, forKey: Key.lockedRoundCount)
        defaults.set(points, forKey: Key.points)
        defaults.set(roundCount, forKey: Key.roundCount)
    }

    private func encodePicks() -> Data? {
        try? JSONEncoder().encode(picks)
    }

    private static func decodePicks(_ data: Data?) -> [String: String] {
        guard let data, let picks = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return picks
    }
}
