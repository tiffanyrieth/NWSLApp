//
//  BracketStore.swift
//  NWSLApp
//
//  Durable Bracket Battle state — the LIVE community-voting game (Fan Zone game 2,
//  0.3.9). Shared app state (picks + points outlive a session and surface on the
//  game screen, the Home Play card, and the Profile total), so it lives in Stores/
//  and is injected app-wide via `.environment`, like PredictionStore / FollowingStore.
//
//  This persists the user's own picks + submission state per round (local
//  UserDefaults state, kept across launches) plus a small edition-summary snapshot
//  that drives the Home Fan Zone gate (show/hide + status) before the live fetch
//  returns. The edition itself, the community vote tally, cross-user leaderboard, and
//  edition generation are all server-side and fetched live (BracketService → Supabase)
//  — there is no offline edition cache. Submit is one-way per round (a committed round
//  can't be edited) and only flips after a real server ack; picks are keyed by edition
//  + round so a new edition / round starts clean.
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
        /// The SHORT tracked-caps theme label ("TOP FORWARD", "STARE-DOWN") — the Home card leads with this
        /// instead of the long `title` so a creative edition's question doesn't truncate off the round name.
        /// Optional so summaries cached before this field still decode (fall back to `title`).
        var themeLabel: String?
        /// The edition's entrant-pool size — lets the Superfan accuracy denominator be computed locally
        /// (Σ matchups over tallied rounds). Optional so summaries cached before this field still decode;
        /// nil ⇒ the bracket contributes from the durable server counts only until the next live fetch.
        var poolSize: Int?
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

    /// The rawValue of the most recent round whose RESULTS the user has already seen (nil = none yet) —
    /// backs the "show the post-round results screen ONCE per tally" gate (Competitive Redesign). Local +
    /// per-device (a cosmetic gate; a reinstall harmlessly re-shows the latest results). Reset on edition change.
    private(set) var lastResultsSeenRound: Int?

    /// The user's leaderboard rank as of the last round whose results they viewed (the baseline the next
    /// round's movement is measured against). Local snapshot; nil until the first results view.
    private(set) var lastSeenRank: Int?

    /// The rank change from the most recently viewed round (positive = climbed) — persisted so the
    /// returning landing shows "↑ N spots since last round" durably between rounds. nil until the second
    /// results view (the first has no prior baseline).
    private(set) var lastRoundRankDelta: Int?

    private let defaults: UserDefaults

    private enum Key {
        static let summary = "bracket.v2.summary"
        static let picks = "bracket.v2.picksByRound"
        static let submitted = "bracket.v2.submittedRounds"
        static let scores = "bracket.v2.roundScores"
        static let editionID = "bracket.v2.editionID"
        static let lastResultsSeen = "bracket.v2.lastResultsSeenRound"
        static let lastSeenRank = "bracket.v2.lastSeenRank"
        static let lastRoundDelta = "bracket.v2.lastRoundRankDelta"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.summary = Self.decode(defaults.data(forKey: Key.summary))
        self.picksByRound = Self.decode(defaults.data(forKey: Key.picks)) ?? [:]
        self.submittedRounds = Set(Self.decode(defaults.data(forKey: Key.submitted)) ?? [Int]())
        self.roundScores = Self.decode(defaults.data(forKey: Key.scores)) ?? [:]
        self.editionID = defaults.string(forKey: Key.editionID)
        self.lastResultsSeenRound = defaults.object(forKey: Key.lastResultsSeen) as? Int
        self.lastSeenRank = defaults.object(forKey: Key.lastSeenRank) as? Int
        self.lastRoundRankDelta = defaults.object(forKey: Key.lastRoundDelta) as? Int
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
            lastResultsSeenRound = nil   // a fresh edition: no results seen, no prior rank/movement
            lastSeenRank = nil
            lastRoundRankDelta = nil
        }
        persist()
    }

    /// Clear the cached edition when none is active (Home then hides the card).
    func clearActiveEdition() {
        if var s = summary, s.isActive {
            s = EditionSummary(id: s.id, title: s.title, currentRoundRaw: s.currentRoundRaw,
                               roundClosesAt: s.roundClosesAt, isActive: false,
                               themeLabel: s.themeLabel, poolSize: s.poolSize)
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

    /// Mark a round's post-round results as seen (so the results screen shows ONCE per tally, then the
    /// returning landing takes over). Monotonic in play order — never moves backward.
    func markResultsSeen(_ round: BracketRound) {
        if let seen = lastResultsSeenRound, let seenRound = BracketRound(rawValue: seen), !(seenRound < round) {
            return   // already at or past this round
        }
        lastResultsSeenRound = round.rawValue
        persist()
    }

    /// Record this round's rank movement at results-view time: the delta from the prior baseline (for the
    /// landing's durable "↑ N since last round"), then advance the baseline to the current rank. The first
    /// call (no baseline) just sets the baseline — no delta yet.
    func recordRoundMovement(currentRank: Int) {
        if let baseline = lastSeenRank { lastRoundRankDelta = baseline - currentRank }
        lastSeenRank = currentRank
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(Self.encode(summary), forKey: Key.summary)
        defaults.set(Self.encode(picksByRound), forKey: Key.picks)
        defaults.set(Self.encode(Array(submittedRounds)), forKey: Key.submitted)
        defaults.set(Self.encode(roundScores), forKey: Key.scores)
        defaults.set(editionID, forKey: Key.editionID)
        defaults.set(lastResultsSeenRound, forKey: Key.lastResultsSeen)
        defaults.set(lastSeenRank, forKey: Key.lastSeenRank)
        defaults.set(lastRoundRankDelta, forKey: Key.lastRoundDelta)
    }

    /// Wipe all local Bracket Battle progress on account deletion — resets the
    /// in-memory @Observable state AND persistence. The server leaderboard/edition
    /// rows are removed by the account-delete cascade; this clears the on-device cache
    /// so "delete account" truly forgets you.
    func resetForAccountDeletion() {
        summary = nil
        picksByRound = [:]
        submittedRounds = []
        roundScores = [:]
        editionID = nil
        lastResultsSeenRound = nil
        lastSeenRank = nil
        lastRoundRankDelta = nil
        persist()
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? { try? JSONEncoder().encode(value) }
    private static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    #if DEBUG
    /// Dev-only: wipe Bracket Battle progress (picks, submitted rounds, banked
    /// scores, edition snapshot) so `-resetOnboarding` simulates a brand-new install
    /// (see NWSLAppApp.init). Static + key-name-aware so it runs before any store
    /// instance exists. Local-only: the server leaderboard/edition rows are untouched
    /// and nothing syncs them back down, so the wipe sticks.
    ///
    /// Writes cleared SENTINELS rather than `removeObject` (see the note in
    /// FollowingStore.debugResetState — deletions don't reliably propagate against
    /// cfprefsd's snapshot at App.init in the Simulator; explicit writes do). The
    /// JSON-backed keys get an empty `Data()`: the store's `decode` does `try?`, which
    /// fails on it and falls back to nil/`[:]` — same fresh state as an absent key,
    /// and it sidesteps the `[Int: …]`-encodes-as-an-array decoding trap.
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set(Data(), forKey: Key.summary)
        defaults.set(Data(), forKey: Key.picks)
        defaults.set(Data(), forKey: Key.submitted)
        defaults.set(Data(), forKey: Key.scores)
        defaults.set("", forKey: Key.editionID)
        defaults.removeObject(forKey: Key.lastResultsSeen)
        defaults.removeObject(forKey: Key.lastSeenRank)
        defaults.removeObject(forKey: Key.lastRoundDelta)
    }
    #endif
}
