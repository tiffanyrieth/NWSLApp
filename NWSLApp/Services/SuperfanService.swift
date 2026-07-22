//
//  SuperfanService.swift
//  NWSLApp
//
//  The Supabase client for `superfan_scores` — the Superfan Zone's season total + tier/percentile. A sibling
//  of PredictLeaderboardService: a plain struct of async calls, best-effort (logs to Diagnostics on failure,
//  never throws to the UI). The tier is computed CLIENT-SIDE from two count=exact reads (no Postgres
//  function). Season-scoped — every call carries `season = String(AppConfig.currentSeasonYear)`.
//

import Foundation
import Supabase

struct SuperfanService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Upsert this user's season Superfan total + games-played. MONOTONIC — writes `max(total, serverTotal)`
    /// so a reinstall / local reset can't lower the server total (fan-zone rule #5). Best-effort.
    func submit(total: Int, gamesPlayed: Int, season: String, userID: UUID, displayName: String?) async {
        do {
            let serverTotal = try await currentTotal(userID: userID, season: season)
            let row = SuperfanUpsert(user_id: userID, season: season,
                                     total: max(total, serverTotal), games_played: gamesPlayed,
                                     display_name: displayName)
            try await client.from("superfan_scores")
                .upsert(row, onConflict: "user_id,season")
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "superfan submit: \(error.localizedDescription)")
        }
    }

    /// The user's standing among QUALIFYING fans (≥2 games this season): two `head: true, count: .exact`
    /// reads (no rows transferred). rank = (fans scoring strictly higher) + 1; qualifying = all ≥2-game
    /// fans. nil on failure → the detail screen falls back to the honest "building" state.
    func standing(season: String, total: Int) async -> SuperfanStanding? {
        do {
            let higher = try await client.from("superfan_scores")
                .select("user_id", head: true, count: .exact)
                .eq("season", value: season)
                .gte("games_played", value: 2)
                .gt("total", value: total)
                .execute().count ?? 0
            let qualifying = try await client.from("superfan_scores")
                .select("user_id", head: true, count: .exact)
                .eq("season", value: season)
                .gte("games_played", value: 2)
                .execute().count ?? 0
            return SuperfanStanding(rank: higher + 1, qualifying: qualifying)
        } catch {
            Diagnostics.shared.record(.apiFailure, "superfan standing: \(error.localizedDescription)")
            return nil
        }
    }

    /// The user's own current server total (0 if no row yet) — the non-decreasing clamp for `submit`.
    private func currentTotal(userID: UUID, season: String) async throws -> Int {
        let rows: [SuperfanRow] = try await client.from("superfan_scores")
            .select("total")
            .eq("user_id", value: userID)
            .eq("season", value: season)
            .limit(1)
            .execute()
            .value
        return rows.first?.total ?? 0
    }
}

// snake_case to match the Postgres columns 1:1 (PostgREST maps directly).
private struct SuperfanUpsert: Encodable {
    let user_id: UUID
    let season: String
    let total: Int
    let games_played: Int
    let display_name: String?
}
private struct SuperfanRow: Decodable {
    let total: Int
}
