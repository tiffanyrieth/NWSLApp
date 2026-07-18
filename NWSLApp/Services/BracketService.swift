//
//  BracketService.swift
//  NWSLApp
//
//  The Bracket Battle data client (Fan Zone game 2, 0.3.9) — the networking twin of
//  FollowSyncService, talking to Supabase. The global edition + matchups + the
//  resolved community tally + the leaderboard are world-readable (the bracket is the
//  same for everyone; you can browse it signed-out); the user writes their OWN votes
//  RLS-scoped. Generation + tally are service-role jobs (the proxy Worker engine), so
//  the app never reads raw votes — only the resolved winner + split + count.
//
//  Offline-first: a read failure returns nil and the caller falls back to the edition
//  the store CACHED from the last good fetch. There is NO fabricated/sample bracket —
//  if nothing's been fetched and Supabase is unreachable, the game honestly shows its
//  empty state. The leaderboard's "You" row is the user's own live total, spliced in.
//

import Foundation
import Supabase

/// One row of the standings.
struct BracketLeaderboardRow: Identifiable, Equatable {
    let rank: Int
    let name: String
    let points: Int
    let isYou: Bool
    /// True for the "You" row shown UNDER a divider because you rank past the visible
    /// top (`rank` is then your real position). The compact card draws the separator.
    var isBelowFold: Bool = false
    var id: String { "\(rank)-\(name)-\(isBelowFold)" }
}

/// A richer standings row for the standalone Leaderboard screen — adds the accuracy
/// backing (correct/total picks) the Rankings table shows alongside points.
struct BracketStanding: Identifiable, Equatable {
    let rank: Int
    let name: String
    let points: Int
    let correct: Int
    let total: Int
    let isYou: Bool
    var id: String { "\(rank)-\(name)-\(isYou)" }
    /// Pick accuracy 0…1, or nil before any pick is scored (shown as "—", never faked).
    var accuracy: Double? { total > 0 ? Double(correct) / Double(total) : nil }
}

/// The standalone Leaderboard screen's Rankings payload: the top `visibleLimit` rows,
/// the signed-in user's OWN standing (their real rank even when past the top — powers
/// the "Your rank" banner), and the TRUE total player count (for the "of N" / percentile,
/// which must reflect everyone, not just the capped list).
struct BracketStandingsResult {
    let rows: [BracketStanding]
    let you: BracketStanding?
    let total: Int
    static let empty = BracketStandingsResult(rows: [], you: nil, total: 0)
}

/// One edition in the signed-in user's history (the Leaderboard "Your Stats" tab).
struct BracketEditionStat: Identifiable, Equatable {
    let editionID: String
    let title: String
    let themeLabel: String
    let points: Int
    let maxPoints: Int       // rule-derived from the edition's pool (0 when unknown)
    let correct: Int
    let total: Int
    let bestRoundRaw: Int?   // BracketRound rawValue of the user's best round (or nil)
    let bestRoundCorrect: Int
    let bestRoundTotal: Int
    let currentStreak: Int   // consecutive correct picks, carried across rounds (0 on a miss)
    let longestStreak: Int   // the per-edition best run
    let isComplete: Bool
    var id: String { editionID }
    var accuracy: Double? { total > 0 ? Double(correct) / Double(total) : nil }
    var bestRoundAccuracy: Double? { bestRoundTotal > 0 ? Double(bestRoundCorrect) / Double(bestRoundTotal) : nil }
}

struct BracketService {
    private var client: SupabaseClient { SupabaseManager.client }

    // MARK: - Read the active edition

    /// The active edition assembled from Supabase (edition + entrants + matchups).
    /// Online-only: `throws` on a fetch failure (the caller shows an honest error +
    /// retry — there is NO offline/cached edition fallback). Returns nil ONLY for a
    /// genuinely empty backend (no active edition), which is a legitimate state — the
    /// game simply hides. There is no fabricated/sample bracket anywhere.
    func currentEdition() async throws -> BracketEdition? {
        let editions: [EditionRow] = try await client
            .from("bracket_editions").select().eq("is_active", value: true)
            .limit(1).execute().value
        guard let e = editions.first else { return nil }

        async let entrantRows: [EntrantRow] = client
            .from("bracket_entrants").select().eq("edition_id", value: e.id)
            .order("seed").execute().value
        async let matchupRows: [MatchupRow] = client
            .from("bracket_matchups").select().eq("edition_id", value: e.id)
            .execute().value

        let entrants = try await entrantRows.map(\.entrant)
        guard !entrants.isEmpty else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: entrants.map { ($0.id, $0) })
        let matchups = try await matchupRows.compactMap { $0.matchup(entrants: byID) }
        return e.edition(entrants: entrants, matchups: matchups)
    }

    // MARK: - Write votes (owner-scoped)

    /// Persist the user's submitted picks for a round (one row per matchup).
    /// Online-only: `throws` on a failed write so the caller can keep the picks
    /// editable and show "Couldn't submit — tap to retry" — the local "locked in"
    /// state is only set AFTER this server ack (never faked ahead of it).
    func submit(editionID: String, round: BracketRound, picks: [String: String], userID: UUID) async throws {
        let rows = picks.map { matchupID, entrantID in
            VoteInsert(user_id: userID, matchup_id: matchupID, edition_id: editionID,
                       round: round.rawValue, entrant_id: entrantID)
        }
        guard !rows.isEmpty else { return }
        try await client.from("bracket_votes").upsert(rows, onConflict: "user_id,matchup_id").execute()
    }

    // MARK: - Results (a resolved round)

    func results(editionID: String, round: BracketRound) async -> [BracketMatchup] {
        do {
            let editions: [EditionRow] = try await client
                .from("bracket_editions").select().eq("id", value: editionID).limit(1).execute().value
            guard editions.first != nil else { return [] }
            let rows: [MatchupRow] = try await client
                .from("bracket_matchups").select()
                .eq("edition_id", value: editionID).eq("round", value: round.rawValue)
                .execute().value
            let entrantRows: [EntrantRow] = try await client
                .from("bracket_entrants").select().eq("edition_id", value: editionID).execute().value
            let byID = Dictionary(uniqueKeysWithValues: entrantRows.map { ($0.entrant_id, $0.entrant) })
            return rows.compactMap { $0.matchup(entrants: byID) }
        } catch {
            // Bracket scoring reads this; a failed read silently using an empty set would
            // mis-score a settled round — flag it so the owner sees the read failed.
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "bracket results r\(round.rawValue): \(error.localizedDescription)") }
            return []
        }
    }

    // MARK: - Leaderboard

    /// The real edition standings, capped to the visible top with the signed-in user
    /// spliced in at their TRUE rank — inline when within the top, else a below-fold
    /// "You" row (never a flattering ~101). Real `bracket_scores` only; a read failure
    /// honestly shows just the user.
    func leaderboard(myPoints: Int, myName: String, editionID: String, myUserID: UUID?) async -> [BracketLeaderboardRow] {
        var rivals: [(name: String, points: Int)] = []
        do {
            let rows: [StandingScoreRow] = try await client
                .from("bracket_scores").select("user_id, display_name, points")
                .eq("edition_id", value: editionID).order("points", ascending: false)
                .limit(LeaderboardRanking.visibleLimit)
                .execute().value
            let myID = myUserID?.uuidString.lowercased()
            rivals = rows
                .filter { $0.user_id.lowercased() != myID }              // never double the user
                .map { (name: $0.display_name ?? "Fan", points: $0.points) }
        } catch {
            rivals = []
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "bracket leaderboard: \(error.localizedDescription)") }
        }
        // Signed out → just the top rivals, no "You" row.
        guard myUserID != nil else {
            return rivals.enumerated().map { BracketLeaderboardRow(rank: $0 + 1, name: $1.name, points: $1.points, isYou: false) }
        }
        let trueRank = await rank(editionID: editionID, points: myPoints)
        let placement = LeaderboardRanking.placement(trueRank: trueRank, cappedRivalCount: rivals.count)
        if case .belowFold(let realRank) = placement {
            var rows = rivals.prefix(LeaderboardRanking.visibleLimit).enumerated().map {
                BracketLeaderboardRow(rank: $0 + 1, name: $1.name, points: $1.points, isYou: false)
            }
            rows.append(BracketLeaderboardRow(rank: realRank, name: myName, points: myPoints, isYou: true, isBelowFold: true))
            return rows
        }
        // .inline (or .none on a rank-lookup failure → append at the end): splice inline.
        let slot: Int = { if case .inline(let s) = placement { return s }; return rivals.count }()
        var all = rivals.map { (name: $0.name, points: $0.points, isYou: false) }
        all.insert((name: myName, points: myPoints, isYou: true), at: min(slot, all.count))
        return all.prefix(LeaderboardRanking.visibleLimit).enumerated().map {
            BracketLeaderboardRow(rank: $0 + 1, name: $1.name, points: $1.points, isYou: $1.isYou)
        }
    }

    /// The signed-in user's TRUE 1-based rank in an edition, computed with a COUNT (rows
    /// scoring strictly higher, +1) — no rows transferred, so it's flat regardless of how
    /// large the board is. `nil` on failure (caller degrades to an inline splice, never a
    /// wrong number). `myPoints` is the fresher LOCAL total (bracket_scores lags the tally).
    private func rank(editionID: String, points: Int) async -> Int? {
        do {
            let response = try await client.from("bracket_scores")
                .select("user_id", head: true, count: .exact)
                .eq("edition_id", value: editionID)
                .gt("points", value: points)
                .execute()
            return (response.count ?? 0) + 1
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "bracket rank: \(error.localizedDescription)") }
            return nil
        }
    }

    // MARK: - Standalone Leaderboard screen

    /// Rankings-tab payload: the top `visibleLimit` of `bracket_scores` joined with
    /// accuracy, PLUS the signed-in user's own standing (real rank even past the top, for
    /// the "Your rank" banner) and the TRUE total player count (for "of N" / percentile).
    /// Real data only — a failure honestly degrades to just you / nothing; no fabricated
    /// rivals, no padded accuracy.
    func standings(editionID: String, myUserID: UUID?, myName: String, myPoints: Int) async -> BracketStandingsResult {
        var scoreRows: [StandingScoreRow] = []
        var total = 0
        var accByUser: [String: (correct: Int, total: Int)] = [:]
        do {
            let response: PostgrestResponse<[StandingScoreRow]> = try await client.from("bracket_scores")
                .select("user_id, display_name, points", count: .exact)
                .eq("edition_id", value: editionID).order("points", ascending: false)
                .limit(LeaderboardRanking.visibleLimit)
                .execute()
            scoreRows = response.value
            total = response.count ?? scoreRows.count
            // Accuracy for the VISIBLE users only — bounded to the page, not the whole edition.
            let visibleIDs = scoreRows.map(\.user_id)
            if !visibleIDs.isEmpty {
                let statRows: [StandingStatRow] = try await client.from("bracket_user_edition_stats")
                    .select("user_id, correct_picks, total_picks")
                    .eq("edition_id", value: editionID)
                    .in("user_id", values: visibleIDs)
                    .execute().value
                for s in statRows { accByUser[s.user_id.lowercased()] = (s.correct_picks, s.total_picks) }
            }
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "bracket standings: \(error.localizedDescription)") }
        }
        let myID = myUserID?.uuidString.lowercased()
        let rows: [BracketStanding] = scoreRows.enumerated().map { i, r in
            let acc = accByUser[r.user_id.lowercased()] ?? (0, 0)
            return BracketStanding(rank: i + 1, name: r.display_name ?? "Fan", points: r.points,
                                   correct: acc.correct, total: acc.total, isYou: r.user_id.lowercased() == myID)
        }
        // The user's OWN standing for the banner: their in-list row if visible, else a
        // computed real-rank row (their accuracy fetched on its own).
        var you: BracketStanding? = rows.first { $0.isYou }
        if you == nil, let myUserID {
            let trueRank = await rank(editionID: editionID, points: myPoints) ?? (total + 1)
            let acc = await myAccuracy(editionID: editionID, userID: myUserID)
            you = BracketStanding(rank: trueRank, name: myName, points: myPoints,
                                  correct: acc.correct, total: acc.total, isYou: true)
        }
        let finalTotal = max(total, rows.count, you?.rank ?? 0)
        return BracketStandingsResult(rows: rows, you: you, total: finalTotal)
    }

    /// The signed-in user's own accuracy backing for an edition (a single-row lookup),
    /// used when they rank past the visible page so the banner still shows real accuracy.
    private func myAccuracy(editionID: String, userID: UUID) async -> (correct: Int, total: Int) {
        do {
            let rows: [StandingStatRow] = try await client.from("bracket_user_edition_stats")
                .select("user_id, correct_picks, total_picks")
                .eq("edition_id", value: editionID).eq("user_id", value: userID).limit(1)
                .execute().value
            if let r = rows.first { return (r.correct_picks, r.total_picks) }
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "bracket my-accuracy: \(error.localizedDescription)") }
        }
        return (0, 0)
    }

    /// Every edition the signed-in user has played (Your Stats tab), newest-scoring first.
    /// Joins their per-edition stats + banked points + the edition's metadata (for the
    /// rule-derived max). A read failure flags Diagnostics and returns [] (honest empty).
    func myEditionStats(userID: UUID) async -> [BracketEditionStat] {
        do {
            let stats: [MyStatRow] = try await client.from("bracket_user_edition_stats")
                .select("edition_id, correct_picks, total_picks, best_round, best_round_correct, best_round_total, current_streak, longest_streak")
                .eq("user_id", value: userID).execute().value
            let scores: [MyScoreRow] = try await client.from("bracket_scores")
                .select("edition_id, points").eq("user_id", value: userID).execute().value
            let pointsByEd = Dictionary(scores.map { ($0.edition_id, $0.points) }, uniquingKeysWith: { a, _ in a })
            let statByEd = Dictionary(stats.map { ($0.edition_id, $0) }, uniquingKeysWith: { a, _ in a })
            let edIDs = Set(stats.map(\.edition_id)).union(scores.map(\.edition_id))
            guard !edIDs.isEmpty else { return [] }
            let eds: [EdMetaRow] = try await client.from("bracket_editions")
                .select("id, title, theme_label, pool_size, is_active")
                .in("id", values: Array(edIDs)).execute().value
            let edByID = Dictionary(eds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return edIDs.compactMap { id -> BracketEditionStat? in
                guard let ed = edByID[id] else { return nil }
                let st = statByEd[id]
                let pool = ed.pool_size ?? 0
                let maxPts = pool > 0 ? BracketScoring.maxPoints(rounds: BracketRound.rounds(forEntrants: pool)) : 0
                return BracketEditionStat(
                    editionID: id, title: ed.title, themeLabel: ed.theme_label,
                    points: pointsByEd[id] ?? 0, maxPoints: maxPts,
                    correct: st?.correct_picks ?? 0, total: st?.total_picks ?? 0,
                    bestRoundRaw: st?.best_round, bestRoundCorrect: st?.best_round_correct ?? 0,
                    bestRoundTotal: st?.best_round_total ?? 0,
                    currentStreak: st?.current_streak ?? 0, longestStreak: st?.longest_streak ?? 0,
                    isComplete: !ed.is_active)
            }.sorted { $0.points > $1.points }
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "bracket my-stats: \(error.localizedDescription)") }
            return []
        }
    }
}

// MARK: - Postgres row DTOs (snake_case → PostgREST maps 1:1)

private struct EditionRow: Decodable {
    let id, theme_label, title, emoji, type: String
    let current_round: Int
    let round_opened_at: String?
    let round_closes_at: String?
    let fan_count: Int

    func edition(entrants: [BracketEntrant], matchups: [BracketMatchup]) -> BracketEdition {
        BracketEdition(
            id: id, themeLabel: theme_label, title: title, emoji: emoji,
            type: BracketThemeType(rawValue: type) ?? .statsSeeded,
            entrants: entrants,
            currentRound: BracketRound(rawValue: current_round) ?? (BracketRound.rounds(forEntrants: entrants.count).first ?? .roundOf16),
            roundOpenedAt: BracketDate.parse(round_opened_at),
            roundClosesAt: BracketDate.parse(round_closes_at),
            fanCount: fan_count, matchups: matchups
        )
    }
}

private struct EntrantRow: Decodable {
    let entrant_id: String
    let seed: Int
    let player_name: String
    let jersey_number: Int?
    let team_abbreviation: String

    var entrant: BracketEntrant {
        BracketEntrant(id: entrant_id, playerName: player_name,
                       jerseyNumber: jersey_number, teamAbbreviation: team_abbreviation, seed: seed)
    }
}

private struct MatchupRow: Decodable {
    let id: String
    let round: Int
    let slot: Int
    let entrant_a_id, entrant_b_id: String
    let points: Int
    let community_winner_id: String?
    let split_a_percent: Int?
    let vote_count: Int?

    func matchup(entrants: [String: BracketEntrant]) -> BracketMatchup? {
        guard let r = BracketRound(rawValue: round),
              let a = entrants[entrant_a_id], let b = entrants[entrant_b_id] else { return nil }
        return BracketMatchup(id: id, round: r, slot: slot, entrantA: a, entrantB: b,
                              communityWinnerID: community_winner_id, splitAPercent: split_a_percent,
                              voteCount: vote_count)
    }
}

private struct StandingScoreRow: Decodable { let user_id: String; let display_name: String?; let points: Int }
private struct StandingStatRow: Decodable { let user_id: String; let correct_picks: Int; let total_picks: Int }
private struct MyStatRow: Decodable {
    let edition_id: String
    let correct_picks: Int
    let total_picks: Int
    let best_round: Int?
    let best_round_correct: Int
    let best_round_total: Int
    let current_streak: Int
    let longest_streak: Int
}
private struct MyScoreRow: Decodable { let edition_id: String; let points: Int }
private struct EdMetaRow: Decodable {
    let id: String
    let title: String
    let theme_label: String
    let pool_size: Int?
    let is_active: Bool
}

private struct VoteInsert: Encodable {
    let user_id: UUID
    let matchup_id, edition_id: String
    let round: Int
    let entrant_id: String
}

/// Lenient Postgres-timestamp → Date (best-effort; nil just drops the countdown).
private enum BracketDate {
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
