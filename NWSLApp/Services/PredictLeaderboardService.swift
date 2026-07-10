//
//  PredictLeaderboardService.swift
//  NWSLApp
//
//  The Supabase data client for the Predict the XI per-team leaderboard (Fan Zone
//  game 1, 0.3.9) — the networking twin of FollowSyncService/BracketService.
//
//  UNLIKE BracketService (whose scores are written by the service-role tally job
//  because community votes are tallied server-side), Predict scores are computed
//  ON-DEVICE: PredictXIViewModel grades a submitted prediction against ESPN's real
//  lineup, so the APP writes its OWN score row here, owner-scoped by RLS. Because
//  we hold the user's display name (AuthStore), real rival names appear — not the
//  anonymous "Fan" rows the bracket board falls back to.
//
//  Scope is PER-TEAM: a query filters by `team_abbreviation`, so a Spirit fan only
//  sees other Spirit predictors. Reads are world-readable (browsable signed-out);
//  writes need a signed-in user. A read failure returns an empty rival list — the
//  caller still shows the user's own live total (offline-first; never fabricated).
//

import Foundation
import Supabase

struct PredictLeaderboardService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// One other player's standing for a team (the signed-in user is excluded by
    /// the caller and spliced in from their live local total instead).
    struct Standing {
        let userID: String
        let name: String
        let points: Int
    }

    /// Push the user's season total for ONE team. Best-effort: a failure leaves the
    /// local score intact and the next load retries the push. Signed-in only (the
    /// caller guards on `userID`).
    func upsertScore(teamAbbreviation: String, points: Int,
                     displayName: String?, userID: UUID, season: String) async {
        let row = ScoreUpsert(user_id: userID, team_abbreviation: teamAbbreviation,
                              season: season, display_name: displayName, points: points)
        do {
            try await client
                .from("prediction_scores")
                .upsert(row, onConflict: "user_id,team_abbreviation,season")
                .execute()
        } catch {
            // Local store already holds the score; next load retries the push. NOT silent:
            // flag it so a failing push (RLS/auth, network) reaches the owner via telemetry.
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict upsertScore \(teamAbbreviation): \(error.localizedDescription)") }
        }
    }

    /// The TOP of a team's board this season — capped at `visibleLimit` so a giant
    /// board never pulls every row just to draw a short list (the caller filters out
    /// the signed-in user and splices their fresher local total + true rank). Empty on
    /// any failure.
    func standings(teamAbbreviation: String, season: String) async -> [Standing] {
        do {
            let rows: [ScoreRow] = try await client
                .from("prediction_scores")
                .select("user_id, display_name, points")
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .order("points", ascending: false)
                .limit(LeaderboardRanking.visibleLimit)
                .execute()
                .value
            return rows.map { Standing(userID: $0.user_id, name: $0.display_name ?? "Fan", points: $0.points) }
        } catch {
            // Caller still shows the user's own live total (honest degrade); flag the read
            // failure so a down board isn't silently invisible to the owner.
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict standings \(teamAbbreviation): \(error.localizedDescription)") }
            return []
        }
    }

    /// The signed-in user's TRUE 1-based rank on a team's board, computed with a COUNT
    /// (rows scoring strictly higher, +1) — no rows transferred. `nil` on failure, so
    /// the caller falls back to an inline splice rather than a wrong number. Ties break
    /// in the user's favour (strictly-greater only), matching the on-device sort.
    func rank(teamAbbreviation: String, season: String, points: Int) async -> Int? {
        do {
            let response = try await client
                .from("prediction_scores")
                .select("user_id", head: true, count: .exact)
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .gt("points", value: points)
                .execute()
            return (response.count ?? 0) + 1
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict rank \(teamAbbreviation): \(error.localizedDescription)") }
            return nil
        }
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct ScoreRow: Decodable {
    let user_id: String
    let display_name: String?
    let points: Int
}

private struct ScoreUpsert: Encodable {
    let user_id: UUID
    let team_abbreviation: String
    let season: String
    let display_name: String?
    let points: Int
}
