//
//  BracketService.swift
//  NWSLApp
//
//  The Bracket Battle data client (Fan Zone game 2, 0.3.9) — the networking twin of
//  FollowSyncService, talking to Supabase. The global edition + matchups + the
//  resolved community tally + the leaderboard are world-readable (the bracket is the
//  same for everyone; you can browse it signed-out); the user writes their OWN votes
//  RLS-scoped. Generation + tally are service-role jobs (deferred Worker; seeded via
//  supabase/seed_bracket_edition.sql for now), so the app never reads raw votes.
//
//  Offline-first, like ContentService: any read failure (or, for now, an empty
//  backend) falls back to the BracketEditionProvider sample so the game always
//  renders in-sim / before the SQL is applied. The leaderboard's "You" row is the
//  user's own live total, spliced in client-side.
//

import Foundation
import Supabase

/// One row of the standings.
struct BracketLeaderboardRow: Identifiable, Equatable {
    let rank: Int
    let name: String
    let points: Int
    let isYou: Bool
    var id: String { "\(rank)-\(name)" }
}

struct BracketService {
    private var client: SupabaseClient { SupabaseManager.client }

    // MARK: - Read the active edition

    /// The active edition assembled from Supabase (edition + entrants + matchups).
    /// TEMP: an empty/unreachable backend falls back to the offline sample so the
    /// game is demoable before the seed SQL is applied; once editions rotate for
    /// real, an empty result should instead return nil (hide the game).
    func currentEdition() async -> BracketEdition? {
        do {
            let editions: [EditionRow] = try await client
                .from("bracket_editions").select().eq("is_active", value: true)
                .limit(1).execute().value
            guard let e = editions.first else { return BracketEditionProvider.sampleEdition() }

            async let entrantRows: [EntrantRow] = client
                .from("bracket_entrants").select().eq("edition_id", value: e.id)
                .order("seed").execute().value
            async let matchupRows: [MatchupRow] = client
                .from("bracket_matchups").select().eq("edition_id", value: e.id)
                .execute().value

            let entrants = try await entrantRows.map(\.entrant)
            let byID = Dictionary(uniqueKeysWithValues: entrants.map { ($0.id, $0) })
            let matchups = try await matchupRows.compactMap { $0.matchup(entrants: byID) }
            guard !entrants.isEmpty else { return BracketEditionProvider.sampleEdition() }
            return e.edition(entrants: entrants, matchups: matchups)
        } catch {
            return BracketEditionProvider.sampleEdition()
        }
    }

    // MARK: - Write votes (owner-scoped)

    /// Persist the user's submitted picks for a round (one row per matchup).
    /// Best-effort: a failure leaves the local submit intact to retry next load.
    func submit(editionID: String, round: BracketRound, picks: [String: String], userID: UUID) async {
        let rows = picks.map { matchupID, entrantID in
            VoteInsert(user_id: userID, matchup_id: matchupID, edition_id: editionID,
                       round: round.rawValue, entrant_id: entrantID)
        }
        guard !rows.isEmpty else { return }
        do {
            try await client.from("bracket_votes").upsert(rows, onConflict: "user_id,matchup_id").execute()
        } catch {
            // Local store already recorded the submit; next load retries the push.
        }
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
            return []
        }
    }

    // MARK: - Leaderboard

    /// The edition standings with the signed-in user spliced in and ranked. A read
    /// failure falls back to the offline sample names; an empty live board is just
    /// the user (honest for a new game).
    func leaderboard(myPoints: Int, myName: String, editionID: String) async -> [BracketLeaderboardRow] {
        var others: [(name: String, points: Int)]
        do {
            let rows: [ScoreRow] = try await client
                .from("bracket_scores").select("display_name, points")
                .eq("edition_id", value: editionID).order("points", ascending: false)
                .execute().value
            others = rows.map { (name: $0.display_name ?? "Fan", points: $0.points) }
        } catch {
            others = BracketEditionProvider.sampleLeaderboard().map { (name: $0.name, points: $0.points) }
        }
        var all = others.map { (name: $0.name, points: $0.points, isYou: false) }
        all.append((name: myName, points: myPoints, isYou: true))
        all.sort { $0.points != $1.points ? $0.points > $1.points : ($0.isYou && !$1.isYou) }
        return all.enumerated().map { i, r in
            BracketLeaderboardRow(rank: i + 1, name: r.name, points: r.points, isYou: r.isYou)
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
                       jerseyNumber: jersey_number, teamAbbreviation: team_abbreviation)
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

    func matchup(entrants: [String: BracketEntrant]) -> BracketMatchup? {
        guard let r = BracketRound(rawValue: round),
              let a = entrants[entrant_a_id], let b = entrants[entrant_b_id] else { return nil }
        return BracketMatchup(id: id, round: r, slot: slot, entrantA: a, entrantB: b,
                              communityWinnerID: community_winner_id, splitAPercent: split_a_percent)
    }
}

private struct ScoreRow: Decodable {
    let display_name: String?
    let points: Int
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
