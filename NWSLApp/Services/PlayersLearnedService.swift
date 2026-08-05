//
//  PlayersLearnedService.swift
//  NWSLApp
//
//  Durable server mirror for the Superfan "players learned" collection (2026-08-05). The device-local
//  `PlayersLearnedStore` drives the live read; this makes the collection survive a REINSTALL and sync
//  across devices. Written on KHG finish (best-score-keeping upsert), fetched + merged into the local
//  store when the Superfan detail opens. Best-effort — Diagnostics on failure, never throws to the UI.
//

import Foundation
import Supabase

struct PlayersLearnedService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Idempotent upsert of one learned player. Guards against LOWERING the server's best (a replay with a
    /// worse score is a no-op) — a stamp only improves, never regresses (mirrors the counts GREATEST merge).
    func record(_ p: LearnedPlayer, season: Int, userID: UUID) async {
        do {
            if let existing = await fetch(season: season, userID: userID).first(where: { $0.athleteId == p.athleteId }),
               existing.bestCorrect >= p.bestCorrect {
                return   // server already holds an equal-or-better score — nothing to write
            }
            let row = PlayersLearnedInsert(
                user_id: userID, season: season, athlete_id: p.athleteId, player_name: p.name,
                team_abbr: p.teamAbbr, best_correct: p.bestCorrect, out_of: p.outOf)
            try await client.from("superfan_players_learned")
                .upsert(row, onConflict: "user_id,season,athlete_id")
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "players-learned record: \(error.localizedDescription)")
        }
    }

    /// The user's collection for a season (empty on failure — the local cache still renders).
    func fetch(season: Int, userID: UUID) async -> [LearnedPlayer] {
        do {
            let rows: [PlayersLearnedRow] = try await client.from("superfan_players_learned")
                .select("user_id,season,athlete_id,player_name,team_abbr,best_correct,out_of,learned_at")
                .eq("user_id", value: userID)
                .eq("season", value: season)
                .execute().value
            return rows.map {
                LearnedPlayer(athleteId: $0.athlete_id, name: $0.player_name, teamAbbr: $0.team_abbr,
                              bestCorrect: $0.best_correct, outOf: $0.out_of,
                              learnedAt: Self.epoch($0.learned_at))
            }
        } catch {
            Diagnostics.shared.record(.apiFailure, "players-learned fetch: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch the server collection and MERGE it into the local store (reinstall/second-device restore).
    /// Returns the merged local list, newest-first.
    @discardableResult
    func restoreIntoLocal(season: Int, userID: UUID) async -> [LearnedPlayer] {
        for p in await fetch(season: season, userID: userID) {
            PlayersLearnedStore.record(p, season: season)
        }
        return PlayersLearnedStore.load(season: season)
    }

    /// Best-effort parse of the server timestamptz → epoch seconds for ordering (0 fallback sorts last).
    private static func epoch(_ iso: String?) -> Double {
        guard let iso else { return 0 }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d.timeIntervalSince1970 }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)?.timeIntervalSince1970 ?? 0
    }
}

// Insert omits learned_at so the column keeps its `default now()` (an explicit null would override it).
private struct PlayersLearnedInsert: Encodable {
    let user_id: UUID
    let season: Int
    let athlete_id: String
    let player_name: String
    let team_abbr: String
    let best_correct: Int
    let out_of: Int
}

private struct PlayersLearnedRow: Decodable {
    let athlete_id: String
    let player_name: String
    let team_abbr: String
    let best_correct: Int
    let out_of: Int
    let learned_at: String?
}
