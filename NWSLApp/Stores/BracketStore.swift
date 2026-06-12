//
//  BracketStore.swift
//  NWSLApp
//
//  Durable Bracket Battle state — the LIVE community-voting game (Fan Zone game 2,
//  0.3.9). Shared app state (picks + points outlive a session and surface on the
//  game screen, the Home Play card, and the Profile total), so it lives in Stores/
//  and is injected app-wide via `.environment`, like PredictionStore / FollowingStore.
//
//  Offline-first: this is the immediate LOCAL cache of the user's own picks +
//  submission state per round, plus a small cached edition summary so the Home gate
//  and card render WITHOUT a network round-trip. The real community vote tally,
//  cross-user leaderboard, and edition generation are server-side (BracketService →
//  Supabase). Submit is one-way per round (a committed round can't be edited), and
//  picks are keyed by edition + round so a new edition / round starts clean.
//

import Foundation

@Observable
final class BracketStore {
    /// A tiny cached snapshot of the active edition, persisted so Home can show /
    /// hide the card + render its status without loading the full edition.
    struct EditionSummary: Codable, Equatable {
        let id: String
        let title: String
        let currentRoundRaw: Int
        let roundClosesAt: Date?
        /// False when there's no active/upcoming edition (the Fan Zone gate).
        let isActive: Bool
    }

    private(set) var summary: EditionSummary?

    /// Picks per round: "r{roundRaw}" → (matchup id → chosen entrant id).
    private(set) var picksByRound: [String: [String: String]]

    /// Round raw-values the user has SUBMITTED (locked, eligible to score).
    private(set) var submittedRounds: Set<Int>

    /// Points banked per scored round: roundRaw → points.
    private(set) var roundScores: [Int: Int]

    /// The edition the above belong to. Changing edition resets picks/scores.
    private(set) var editionID: String?

    /// The last edition successfully fetched from Supabase, cached whole so the game
    /// renders offline-first when the network is briefly unreachable. This is the ONLY
    /// fallback — there is no fabricated/sample bracket. Nil before the first fetch.
    private(set) var cachedEdition: BracketEdition?

    private let defaults: UserDefaults

    private enum Key {
        static let summary = "bracket.v2.summary"
        static let picks = "bracket.v2.picksByRound"
        static let submitted = "bracket.v2.submittedRounds"
        static let scores = "bracket.v2.roundScores"
        static let editionID = "bracket.v2.editionID"
        static let edition = "bracket.v2.edition"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.summary = Self.decode(defaults.data(forKey: Key.summary))
        self.picksByRound = Self.decode(defaults.data(forKey: Key.picks)) ?? [:]
        self.submittedRounds = Set(Self.decode(defaults.data(forKey: Key.submitted)) ?? [Int]())
        self.roundScores = Self.decode(defaults.data(forKey: Key.scores)) ?? [:]
        self.editionID = defaults.string(forKey: Key.editionID)
        self.cachedEdition = Self.decode(defaults.data(forKey: Key.edition))
    }

    /// Cache the whole edition just fetched from Supabase (offline-first fallback).
    func cacheEdition(_ edition: BracketEdition) {
        cachedEdition = edition
        defaults.set(Self.encode(edition), forKey: Key.edition)
    }

    // MARK: - Readers (Home / Profile)

    /// Cumulative Bracket points (sum of scored rounds) — the Profile total reads
    /// this alongside Predict's season points.
    var points: Int { roundScores.values.reduce(0, +) }

    /// The Fan Zone visibility gate: is there an active/upcoming edition?
    var hasActiveEdition: Bool { summary?.isActive ?? false }

    /// True once the user has made any pick this edition (Home "Play now" vs status).
    var hasPlayed: Bool { !picksByRound.isEmpty }

    // MARK: - Per-round access

    private static func roundKey(_ round: BracketRound) -> String { "r\(round.rawValue)" }

    func picks(for round: BracketRound) -> [String: String] {
        picksByRound[Self.roundKey(round)] ?? [:]
    }

    func hasSubmitted(_ round: BracketRound) -> Bool { submittedRounds.contains(round.rawValue) }

    func pick(matchupID: String, in round: BracketRound) -> String? {
        picksByRound[Self.roundKey(round)]?[matchupID]
    }

    func score(for round: BracketRound) -> Int? { roundScores[round.rawValue] }

    // MARK: - Mutation

    /// Cache the active edition snapshot for the Home gate; reset picks/scores when
    /// the edition actually changes (a new themed bracket starts clean).
    func adopt(summary: EditionSummary) {
        self.summary = summary
        if editionID != summary.id {
            editionID = summary.id
            picksByRound = [:]
            submittedRounds = []
            roundScores = [:]
        }
        persist()
    }

    /// Clear the cached edition when none is active (Home then hides the card).
    func clearActiveEdition() {
        if var s = summary, s.isActive {
            s = EditionSummary(id: s.id, title: s.title, currentRoundRaw: s.currentRoundRaw,
                               roundClosesAt: s.roundClosesAt, isActive: false)
            summary = s
            persist()
        }
    }

    /// Save (or change) a pick — only while the round is an unsubmitted draft.
    func setPick(matchupID: String, entrantID: String, round: BracketRound) {
        guard !hasSubmitted(round) else { return }
        var roundPicks = picksByRound[Self.roundKey(round)] ?? [:]
        roundPicks[matchupID] = entrantID
        picksByRound[Self.roundKey(round)] = roundPicks
        persist()
    }

    /// Commit a round's picks. One-way: only a not-yet-submitted round can submit.
    func submit(round: BracketRound) {
        guard !hasSubmitted(round) else { return }
        submittedRounds.insert(round.rawValue)
        persist()
    }

    /// Record a round's earned points once its real tally has settled.
    func recordScore(_ points: Int, for round: BracketRound) {
        roundScores[round.rawValue] = points
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(Self.encode(summary), forKey: Key.summary)
        defaults.set(Self.encode(picksByRound), forKey: Key.picks)
        defaults.set(Self.encode(Array(submittedRounds)), forKey: Key.submitted)
        defaults.set(Self.encode(roundScores), forKey: Key.scores)
        defaults.set(editionID, forKey: Key.editionID)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
