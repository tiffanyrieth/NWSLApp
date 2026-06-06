//
//  BracketViewModel.swift
//  NWSLApp
//
//  Owns one Bracket Battle "session" — Home's Module 3 "Play", game 2. Same
//  idle/loading/loaded/error State shape as the other view models. The durable
//  state (votes, locked rounds, points) lives in BracketStore; this view model
//  owns the DERIVED bracket: the matchup tree and the simulated "community"
//  result for every matchup.
//
//  The community is simulated DETERMINISTICALLY (no backend yet): the bracket is
//  built by standard tournament seeding, and each matchup's winner + vote split
//  come from a SplitMix64 RNG seeded by a stable hash of the matchup id, weighted
//  by the entrants' seed strength so favourites usually (but not always) advance.
//  Same edition in → same bracket out, every launch — which is what lets a locked
//  round's results stay stable and the leaderboard make sense.
//
//  Club crests/names are resolved best-effort via the club directory (like Home /
//  Feed / Schedule). If that fetch fails the game is still fully playable — the
//  entrants just render with their team abbreviation instead of a crest.
//

import Foundation

@Observable
final class BracketViewModel {
    enum State {
        case idle
        case loading
        case loaded
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var edition: BracketEdition?
    /// rounds[r] = that round's matchups, slot order. Round 0 is the Round of 16.
    private(set) var rounds: [[BracketMatchup]] = []
    private(set) var clubsByAbbr: [String: Club] = [:]

    private let provider: BracketEditionProvider
    private let service: ESPNService

    init(provider: BracketEditionProvider = BracketEditionProvider(),
         service: ESPNService = ESPNService()) {
        self.provider = provider
        self.service = service
    }

    // MARK: - Loading

    /// Load the edition, build + simulate the bracket, and adopt it in the store.
    /// The edition is a local seed (so the game always reaches `.loaded`); the club
    /// directory is a best-effort enrichment for crests/names.
    func load(store: BracketStore) async {
        if case .loaded = state { return }
        state = .loading

        let edition = await provider.edition()
        self.edition = edition
        rounds = Self.buildBracket(edition: edition)
        store.beginEdition(edition.id, roundCount: rounds.count)

        // Best-effort crest/name resolution — a failure here must not break play.
        if let clubs = try? await service.fetchTeams() {
            clubsByAbbr = Dictionary(clubs.map { ($0.abbreviation, $0) }, uniquingKeysWith: { first, _ in first })
        }

        state = .loaded
    }

    // MARK: - Bracket construction + simulation

    /// Standard single-elimination seeding for 16 entrants (1 v 16, 8 v 9, …), as
    /// 0-based indices into the seed-ordered entrant list. Falls back to sequential
    /// pairing for any other count (keeps the model general).
    private static let seedOrder16 = [0, 15, 7, 8, 4, 11, 3, 12, 2, 13, 5, 10, 6, 9, 1, 14]

    private static func buildBracket(edition: BracketEdition) -> [[BracketMatchup]] {
        let entrants = edition.entrants
        guard entrants.count >= 2 else { return [] }

        // Strength = position in the seed-ordered list (0 = strongest); used to
        // weight the simulated upset chance.
        var strength: [String: Int] = [:]
        for (index, entrant) in entrants.enumerated() { strength[entrant.id] = index }

        // Round 0 contenders in bracket order.
        let ordered: [BracketEntrant]
        if entrants.count == 16 {
            ordered = seedOrder16.map { entrants[$0] }
        } else {
            ordered = entrants
        }

        var rounds: [[BracketMatchup]] = []
        var advancing = ordered    // entrants entering the current round, slot order

        var roundIndex = 0
        while advancing.count >= 2 {
            var matchups: [BracketMatchup] = []
            var winners: [BracketEntrant] = []

            var slot = 0
            var i = 0
            while i + 1 < advancing.count {
                let a = advancing[i]
                let b = advancing[i + 1]
                let id = "\(edition.id)-r\(roundIndex)-s\(slot)"
                let result = simulate(
                    id: id,
                    a: a, b: b,
                    strengthA: strength[a.id] ?? 0,
                    strengthB: strength[b.id] ?? 0
                )
                matchups.append(BracketMatchup(
                    id: id,
                    roundIndex: roundIndex,
                    slot: slot,
                    entrantA: a,
                    entrantB: b,
                    communityWinnerID: result.winner.id,
                    votePercentWinner: result.winnerPercent
                ))
                winners.append(result.winner)
                slot += 1
                i += 2
            }

            rounds.append(matchups)
            advancing = winners
            roundIndex += 1
        }
        return rounds
    }

    /// Deterministic community result for a matchup: who advances + the winner's
    /// vote share. The favourite (lower strength index) usually wins; the upset
    /// chance shrinks as the seed gap grows. Stable across launches because it's
    /// seeded by a stable hash of the matchup id.
    private static func simulate(id: String, a: BracketEntrant, b: BracketEntrant,
                                 strengthA: Int, strengthB: Int)
        -> (winner: BracketEntrant, winnerPercent: Int) {
        var generator = SeededGenerator(seed: stableHash(id))
        let roll = unitInterval(&generator)        // decides upset
        let split = unitInterval(&generator)        // decides the vote margin

        let gap = abs(strengthA - strengthB)
        // gap 1 → ~0.39 upset chance (near coin flip); gap 15 → floored at 0.08.
        let upsetChance = max(0.08, 0.42 - 0.025 * Double(gap))
        let favouriteIsA = strengthA < strengthB
        let favouriteWins = roll >= upsetChance
        let winnerIsA = favouriteIsA ? favouriteWins : !favouriteWins

        let winner = winnerIsA ? a : b
        // Winner's share lands in 54–76% — a believable community split.
        let winnerPercent = 54 + Int((split * 22).rounded())
        return (winner, winnerPercent)
    }

    // MARK: - Derived

    var roundCount: Int { rounds.count }

    func matchups(inRound round: Int) -> [BracketMatchup] {
        rounds.indices.contains(round) ? rounds[round] : []
    }

    func roundTitle(_ round: Int) -> String {
        BracketRoundLabel.title(matchups: matchups(inRound: round).count)
    }

    func entrant(_ id: String?) -> BracketEntrant? {
        guard let id else { return nil }
        for round in rounds {
            for matchup in round {
                if matchup.entrantA?.id == id { return matchup.entrantA }
                if matchup.entrantB?.id == id { return matchup.entrantB }
            }
        }
        return nil
    }

    func club(for entrant: BracketEntrant?) -> Club? {
        guard let entrant else { return nil }
        return clubsByAbbr[entrant.teamAbbreviation]
    }

    /// True once every matchup in a round has a vote (enables the Lock button).
    func allPicked(inRound round: Int, store: BracketStore) -> Bool {
        let ms = matchups(inRound: round)
        return !ms.isEmpty && ms.allSatisfy { store.pick(for: $0.id) != nil }
    }

    /// Correct picks in a round (each worth a point) — the round score.
    func correctPicks(inRound round: Int, store: BracketStore) -> Int {
        matchups(inRound: round).filter { store.pick(for: $0.id) == $0.communityWinnerID }.count
    }

    /// Close the current round, banking its points. No-op unless every matchup is
    /// voted (the view also gates the button) and it's the next round to lock.
    func lockRound(_ round: Int, store: BracketStore) {
        guard allPicked(inRound: round, store: store) else { return }
        store.lockRound(round, pointsEarned: correctPicks(inRound: round, store: store))
    }

    /// The community champion — the final's winner, known once the final is locked.
    func champion(store: BracketStore) -> BracketEntrant? {
        guard store.isComplete, let final = rounds.last?.first else { return nil }
        return entrant(final.communityWinnerID)
    }

    /// The final's winning vote share (for the champion banner).
    func finalWinnerPercent() -> Int? {
        rounds.last?.first?.votePercentWinner
    }

    // MARK: - Leaderboard (simulated)

    struct LeaderboardRow: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let points: Int
        let isYou: Bool
    }

    /// The simulated per-edition leaderboard: fixed sample opponents plus "You"
    /// (live points), sorted high-to-low. On a tie, "You" sorts ahead so climbing
    /// reads cleanly. Replaced by a real board when a voting backend exists.
    func leaderboard(store: BracketStore) -> [LeaderboardRow] {
        var entries = provider.leaderboardOpponents().map { (name: $0.name, points: $0.points, isYou: false) }
        entries.append((name: "You", points: store.points, isYou: true))
        entries.sort { lhs, rhs in
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            return lhs.isYou && !rhs.isYou
        }
        return entries.enumerated().map { index, entry in
            LeaderboardRow(rank: index + 1, name: entry.name, points: entry.points, isYou: entry.isYou)
        }
    }

    /// The user's current rank in the simulated board (for the header + share).
    func yourRank(store: BracketStore) -> Int {
        leaderboard(store: store).first(where: \.isYou)?.rank ?? 0
    }
}

/// A single matchup, derived at runtime (not persisted). Entrants are known for
/// every round because the simulation is deterministic; the view decides when to
/// REVEAL future rounds so results aren't spoiled before you've voted.
struct BracketMatchup: Identifiable {
    let id: String
    let roundIndex: Int
    let slot: Int
    let entrantA: BracketEntrant?
    let entrantB: BracketEntrant?
    /// The community's choice to advance (the demo simulation).
    let communityWinnerID: String?
    /// The winning entrant's vote share; the loser's is 100 − this.
    let votePercentWinner: Int

    var votePercentLoser: Int { 100 - votePercentWinner }

    func percent(forEntrant id: String?) -> Int {
        id == communityWinnerID ? votePercentWinner : votePercentLoser
    }
}

// MARK: - Deterministic helpers

/// A stable FNV-1a hash so a matchup id maps to the same RNG seed on every launch
/// (Swift's built-in Hasher is intentionally randomised per-process, which would
/// reshuffle results between runs).
private func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return hash
}

/// A double in [0, 1) from the next 53 bits of the generator.
private func unitInterval(_ generator: inout SeededGenerator) -> Double {
    Double(generator.next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
}

/// A tiny deterministic RNG (SplitMix64), matching the one TriviaViewModel uses
/// for its daily pick — same seed in, same sequence out, on every device.
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
