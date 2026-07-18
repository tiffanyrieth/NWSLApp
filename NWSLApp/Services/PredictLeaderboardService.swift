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
        do {
            // Guard against a DOWNWARD clobber. A season total is monotonic (Σ of scored fixtures, and
            // a scored fixture never re-scores lower), but the local store is UserDefaults-only and
            // resets to ~0 on a reinstall. A plain overwrite upsert would then replace the server's
            // accumulated total (e.g. 300) with the small post-reinstall local value (e.g. 40) —
            // silent, permanent standing loss. So read the user's current server total first and push
            // the GREATER of the two: the server can only ever go UP. Also improves the two-device case
            // (max-writer-wins instead of last-writer-wins). If the READ fails we skip the push (throws
            // → caught → retried next load) rather than risk a clobber.
            let serverPoints = try await currentPoints(teamAbbreviation: teamAbbreviation, userID: userID, season: season)
            let row = ScoreUpsert(user_id: userID, team_abbreviation: teamAbbreviation,
                                  season: season, display_name: displayName, points: max(points, serverPoints))
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

    /// The signed-in user's OWN current server total for a team this season (0 if no row yet). Used to
    /// clamp `upsertScore` to a non-decreasing value. Throws on a read failure so the caller skips the
    /// push and retries next load — never worse than the old unconditional overwrite.
    private func currentPoints(teamAbbreviation: String, userID: UUID, season: String) async throws -> Int {
        let rows: [ScoreRow] = try await client
            .from("prediction_scores")
            .select("user_id, display_name, points")
            .eq("user_id", value: userID)
            .eq("team_abbreviation", value: teamAbbreviation)
            .eq("season", value: season)
            .limit(1)
            .execute()
            .value
        return rows.first?.points ?? 0
    }

    /// Everyone ranked for a team this season (raw — the caller filters out the
    /// signed-in user and splices their fresher local total). Empty on any failure.
    func standings(teamAbbreviation: String, season: String) async -> [Standing] {
        do {
            let rows: [ScoreRow] = try await client
                .from("prediction_scores")
                .select("user_id, display_name, points")
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .order("points", ascending: false)
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
