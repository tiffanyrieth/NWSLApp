//
//  PredictCommunity.swift
//  NWSLApp
//
//  How a club's predictors collectively picked one match — the data behind Predict the XI's share
//  bars, consensus XI, standout picks, and the post-close contrarian panel (results redesign,
//  2026-07-28).
//
//  ⚠️ THESE ARE COUNTS, NOT LINEUPS. No individual's XI is ever uploaded (docs/fan-zone.md §3);
//  the server holds only "N people picked player P in slot S", which is why the storage cost is
//  flat in user count. Nothing here can identify a person, and nothing here should try.
//
//  ⚠️ SEALED IS NOT ZERO. Before submissions close (kickoff − 2h) the proxy withholds per-player
//  data entirely, and `revealed` is false. Every derived read below returns nil in that state
//  rather than 0 or 0%, so a caller cannot accidentally render "0% picked her" as a fact — that
//  would be exactly the banned failure-that-looks-like-success. The submission COUNT is still
//  present while sealed: it's what the locked-wait card's "312 fans have locked in" reads.
//

import Foundation

// MARK: - Domain

struct PredictCommunity: Equatable {
    /// One counted pick: a player in a specific formation slot.
    struct Pick: Hashable {
        let playerID: String
        let slot: Int
    }

    let eventID: String
    let team: String
    let week: Int
    /// False until submissions close. While false, `counts` is empty BY DESIGN, not by failure.
    let revealed: Bool
    let closesAt: Date?
    /// Complete XIs submitted for this match — the percentage denominator, and the one number
    /// that is readable while sealed.
    let submissions: Int
    let counts: [Pick: Int]

    /// The share of predictors who picked this player ANYWHERE in their XI, 0…1.
    ///
    /// Set-wise across slots on purpose: that is exactly how the scorer treats a hit
    /// (`actualIDs.contains(pick.id)` — she counts wherever you put her), so the percentage a fan
    /// reads next to a ✓ has to be counted the same way or the two contradict each other.
    /// nil while sealed or with no submissions — never a fabricated 0%.
    func share(forPlayer playerID: String) -> Double? {
        guard revealed, submissions > 0 else { return nil }
        let picked = counts.reduce(0) { $1.key.playerID == playerID ? $0 + $1.value : $0 }
        return Double(picked) / Double(submissions)
    }

    /// Every player anyone picked, most-picked first. Used for the consensus XI and omissions.
    var playersByShare: [(playerID: String, share: Double)] {
        guard revealed, submissions > 0 else { return [] }
        var totals: [String: Int] = [:]
        for (pick, n) in counts { totals[pick.playerID, default: 0] += n }
        return totals
            .map { (playerID: $0.key, share: Double($0.value) / Double(submissions)) }
            // Deterministic: ties break on id so the same data always renders the same order.
            .sorted { $0.share == $1.share ? $0.playerID < $1.playerID : $0.share > $1.share }
    }

    /// The XI the crowd would field: each slot's most-picked player, in slot order.
    ///
    /// ⚠️ Deduped greedily. Taking each slot's winner independently can name the same player twice
    /// (a versatile player leads at both full-back slots), and an XI with ten distinct names is not
    /// an XI. Slots are filled in order of how decisive their leader is, so the most clear-cut slot
    /// keeps its player and the contested one falls through to its runner-up.
    func consensusXI(slots: [Int]) -> [Int: String] {
        guard revealed, submissions > 0 else { return [:] }
        var rankedBySlot: [Int: [(player: String, count: Int)]] = [:]
        for slot in slots {
            rankedBySlot[slot] = counts
                .filter { $0.key.slot == slot }
                .map { (player: $0.key.playerID, count: $0.value) }
                .sorted { $0.count == $1.count ? $0.player < $1.player : $0.count > $1.count }
        }
        let order = slots.sorted { a, b in
            let lead = { (s: Int) -> Int in rankedBySlot[s]?.first?.count ?? 0 }
            return lead(a) == lead(b) ? a < b : lead(a) > lead(b)
        }
        var used = Set<String>()
        var result: [Int: String] = [:]
        for slot in order {
            guard let winner = rankedBySlot[slot]?.first(where: { !used.contains($0.player) }) else { continue }
            used.insert(winner.player)
            result[slot] = winner.player
        }
        return result
    }

    /// How many of the crowd's XI actually started — the "the crowd got 9 of 11" line.
    func consensusCorrect(slots: [Int], actualStarterIDs: Set<String>) -> Int? {
        guard revealed, submissions > 0 else { return nil }
        return consensusXI(slots: slots).values.filter(actualStarterIDs.contains).count
    }

    /// The user's picks that few others made — "you're one of 14% starting Yara Sène".
    /// Sorted most-contrarian first.
    func contrarians(among pickedIDs: [String], below threshold: Double) -> [(playerID: String, share: Double)] {
        pickedIDs
            .compactMap { id in share(forPlayer: id).map { (playerID: id, share: $0) } }
            .filter { $0.share < threshold }
            .sorted { $0.share == $1.share ? $0.playerID < $1.playerID : $0.share < $1.share }
    }

    /// Players a large share of the club picked that the user did not — the other half of
    /// "where you went your own way". Sorted most-owned first.
    func highOwnershipOmissions(notPicked pickedIDs: Set<String>, above threshold: Double)
        -> [(playerID: String, share: Double)] {
        playersByShare
            .filter { !pickedIDs.contains($0.playerID) && $0.share > threshold }
    }

    /// An honestly-empty value for a fixture we could not read. Distinguishable from a sealed one
    /// only by intent — both render the same way, which is the point: no community data shown.
    static func unavailable(eventID: String, team: String, week: Int) -> PredictCommunity {
        PredictCommunity(eventID: eventID, team: team, week: week, revealed: false,
                         closesAt: nil, submissions: 0, counts: [:])
    }
}

// MARK: - Wire (proxy `GET /predict/community`)

/// Decode-defensively, per the app's standing rule about upstream shapes: every field beyond the
/// identifiers is optional, so a proxy that adds or drops one can never fail the whole decode.
struct PredictCommunityResponse: Decodable {
    let season: String?
    let fixtures: [Fixture]?

    struct Fixture: Decodable {
        let event: String
        let team: String
        let week: Int?
        let revealed: Bool?
        let closesAt: String?
        let submissions: Int?
        let picks: [Pick]?

        struct Pick: Decodable {
            let playerId: String?
            let slot: Int?
            let count: Int?
        }

        func domain() -> PredictCommunity {
            var counts: [PredictCommunity.Pick: Int] = [:]
            for pick in picks ?? [] {
                guard let id = pick.playerId, let slot = pick.slot, let n = pick.count, n > 0 else { continue }
                counts[PredictCommunity.Pick(playerID: id, slot: slot), default: 0] += n
            }
            return PredictCommunity(
                eventID: event,
                team: team,
                week: week ?? 0,
                revealed: revealed ?? false,
                closesAt: closesAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                submissions: max(0, submissions ?? 0),
                counts: counts
            )
        }
    }
}
