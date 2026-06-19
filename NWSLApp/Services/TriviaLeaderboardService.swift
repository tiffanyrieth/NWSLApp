//
//  TriviaLeaderboardService.swift
//  NWSLApp
//
//  The Supabase data client for the Daily Trivia leaderboard (Fan Zone game 3,
//  0.3.9) — the league-wide twin of PredictLeaderboardService. Trivia has no club,
//  so the board is global (everyone ranked together), and the metric is BEST STREAK
//  (consecutive days played) — it rewards daily consistency, not raw volume.
//
//  Like Predict, the score is computed ON-DEVICE (TriviaStore's day-gated streak),
//  so the APP writes its OWN owner-scoped row; we hold the display name, so real
//  names appear. Reads are world-readable (browsable signed-out); a read failure
//  returns an empty list and the caller still shows the user's own live streak
//  (offline-first — never a fabricated rival).
//

import Foundation
import Supabase

struct TriviaLeaderboardService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// One other player's standing (the signed-in user is excluded by the caller
    /// and spliced in from their live local best streak instead).
    struct Standing {
        let userID: String
        let name: String
        let bestStreak: Int
    }

    /// Push the user's best streak. Best-effort: a failure leaves the local stat
    /// intact and the next load retries. Signed-in only (caller guards on `userID`).
    func upsertScore(bestStreak: Int, displayName: String?, userID: UUID, season: String) async {
        let row = ScoreUpsert(user_id: userID, season: season,
                              display_name: displayName, best_streak: bestStreak)
        do {
            try await client
                .from("trivia_scores")
                .upsert(row, onConflict: "user_id,season")
                .execute()
        } catch {
            // Local store already holds the streak; next load retries the push. NOT silent:
            // flag it so a failing push (e.g. RLS/auth, network) reaches the owner via telemetry.
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "trivia upsertScore: \(error.localizedDescription)") }
        }
    }

    /// Everyone ranked this season (raw — the caller filters out the signed-in user
    /// and splices their fresher local streak). Empty on any failure.
    func standings(season: String) async -> [Standing] {
        do {
            let rows: [ScoreRow] = try await client
                .from("trivia_scores")
                .select("user_id, display_name, best_streak")
                .eq("season", value: season)
                .order("best_streak", ascending: false)
                .execute()
                .value
            return rows.map { Standing(userID: $0.user_id, name: $0.display_name ?? "Fan", bestStreak: $0.best_streak) }
        } catch {
            // Caller still shows the user's own live streak (honest degrade), but the read
            // failure is flagged so a down board doesn't go silently unnoticed by the owner.
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "trivia standings: \(error.localizedDescription)") }
            return []
        }
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct ScoreRow: Decodable {
    let user_id: String
    let display_name: String?
    let best_streak: Int
}

private struct ScoreUpsert: Encodable {
    let user_id: UUID
    let season: String
    let display_name: String?
    let best_streak: Int
}
