//
//  SuperfanService.swift
//  NWSLApp
//
//  The Supabase client for `superfan_scores` — the Superfan Zone's 0–100 accuracy economy (Fan Zone
//  Competitive Redesign). A sibling of PredictLeaderboardService: plain async calls, best-effort (logs to
//  Diagnostics on failure, never throws to the UI). Season-scoped — every call carries the season string.
//
//  The redesign changed what's stored: instead of one opaque additive `total`, the row now holds per-game
//  CORRECT/ATTEMPTED counts (the source of truth), and `submit` GREATEST-merges the caller's LOCAL counts
//  with the server's before writing. Accuracy legitimately falls, so we can't clamp the score with a
//  `max(total)` — but the COUNTS only grow, so merging them is what keeps the score reinstall-safe: a
//  wiped device can't lower the server, yet a genuinely-dropped accuracy still recomputes. The derived
//  0–100 `total` + `tier` are written alongside for read convenience (leaderboard/card), but the counts
//  are authoritative. The competitive TIER is the absolute score band; the percentile `standing` stays a
//  separate rank query.
//

import Foundation
import Supabase

struct SuperfanService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Merge the caller's LOCAL counts into the server row (GREATEST per count) and write the full row
    /// back — total, tier, games_played all derived from the merged counts. Returns the MERGED counts so
    /// the caller displays the reconciled 0–100 score (which, after a reinstall, reflects the server's
    /// preserved history, not the empty local device). Best-effort; on failure returns the local counts so
    /// the UI still shows something honest.
    @discardableResult
    func submit(counts local: SuperfanCounts, season: String, userID: UUID,
                displayName: String?) async -> SuperfanCounts {
        do {
            let server = try await currentCounts(userID: userID, season: season)
            let merged = local.merged(with: server)
            let total = SuperfanScoring.total(counts: merged)
            let tier = SuperfanTier.forScore(total)
            let row = SuperfanUpsert(
                user_id: userID, season: season,
                total: total, games_played: merged.gamesPlayed,
                display_name: displayName, tier: tier.rawValue,
                predict_correct: merged.predictCorrect, predict_total: merged.predictTotal,
                bracket_correct: merged.bracketCorrect, bracket_total: merged.bracketTotal,
                khg_correct: merged.khgCorrect, khg_total: merged.khgTotal,
                trivia_correct: merged.triviaCorrect, trivia_total: merged.triviaTotal,
                trivia_streak: merged.triviaStreak)
            try await client.from("superfan_scores")
                .upsert(row, onConflict: "user_id,season")
                .execute()
            return merged
        } catch {
            Diagnostics.shared.record(.apiFailure, "superfan submit: \(error.localizedDescription)")
            return local
        }
    }

    /// The user's standing among QUALIFYING fans (≥2 games this season): two `head: true, count: .exact`
    /// reads (no rows transferred). rank = (fans scoring strictly higher) + 1; qualifying = all ≥2-game
    /// fans. nil on failure → the detail screen falls back to the honest "building" state. Unchanged by the
    /// redesign — this is the percentile RANK, a different axis than the absolute tier.
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

    /// The user's own current server counts (all-zero if no row yet) — the reinstall-safe merge floor.
    private func currentCounts(userID: UUID, season: String) async throws -> SuperfanCounts {
        let rows: [SuperfanRow] = try await client.from("superfan_scores")
            .select("predict_correct,predict_total,bracket_correct,bracket_total,khg_correct,khg_total,trivia_correct,trivia_total,trivia_streak")
            .eq("user_id", value: userID)
            .eq("season", value: season)
            .limit(1)
            .execute()
            .value
        guard let r = rows.first else { return .zero }
        return SuperfanCounts(
            predictCorrect: r.predict_correct, predictTotal: r.predict_total,
            bracketCorrect: r.bracket_correct, bracketTotal: r.bracket_total,
            khgCorrect: r.khg_correct, khgTotal: r.khg_total,
            triviaCorrect: r.trivia_correct, triviaTotal: r.trivia_total,
            triviaStreak: r.trivia_streak)
    }
}

// snake_case to match the Postgres columns 1:1 (PostgREST maps directly).
private struct SuperfanUpsert: Encodable {
    let user_id: UUID
    let season: String
    let total: Int
    let games_played: Int
    let display_name: String?
    let tier: String
    let predict_correct: Int
    let predict_total: Int
    let bracket_correct: Int
    let bracket_total: Int
    let khg_correct: Int
    let khg_total: Int
    let trivia_correct: Int
    let trivia_total: Int
    let trivia_streak: Int
}

private struct SuperfanRow: Decodable {
    let predict_correct: Int
    let predict_total: Int
    let bracket_correct: Int
    let bracket_total: Int
    let khg_correct: Int
    let khg_total: Int
    let trivia_correct: Int
    let trivia_total: Int
    let trivia_streak: Int
}
