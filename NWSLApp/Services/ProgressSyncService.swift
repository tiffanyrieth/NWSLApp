//
//  ProgressSyncService.swift
//  NWSLApp
//
//  The Supabase client for `fanzone_progress` — the per-user, per-season Fan Zone SUMMARY row that
//  makes game progress survive a reinstall or a replaced phone. A sibling of SuperfanService: a plain
//  struct of async calls, best-effort (logs to Diagnostics on failure, never throws to the UI).
//
//  Direction of truth: the device leads DURING play (stores update instantly, then fire-and-forget
//  upload); the server leads only at SIGN-IN on a device with less progress — and even then through
//  `ProgressSnapshot.merge`, a MONOTONIC max-merge (a stale server row can never lower a fresher
//  local count; same clamp philosophy as SuperfanService.submit). Keyed on user_id, NEVER device_id:
//  a replacement phone gets a new Keychain device UUID, but the same Apple ID → the same user_id →
//  her season comes back.
//
//  Deliberately a SUMMARY, not history: raw quiz_answers are pruned to current+previous round
//  (retention rule), so restore must not depend on them. Predict + Bracket restore rides their own
//  existing server tables (prediction_scores / bracket_user_edition_stats).
//

import Foundation
import Supabase

/// The wire row + the merge rules. Codable once (upsert encodes it, fetch decodes it); pure, so the
/// merge is unit-testable without the network.
struct ProgressSnapshot: Codable, Equatable {
    var season: String

    var triviaLifetimeCorrect: Int
    var triviaLifetimeAnswered: Int
    var triviaBestStreak: Int
    var triviaSeasonCorrect: Int
    var triviaRoundStreak: Int
    var triviaLastRound: Int

    var khgSeasonPoints: Int
    var khgEditionsPlayed: Int
    var khgWeekStreak: Int
    var khgBestWeekStreak: Int
    var khgLastWeek: String?

    enum CodingKeys: String, CodingKey {
        case season
        case triviaLifetimeCorrect = "trivia_lifetime_correct"
        case triviaLifetimeAnswered = "trivia_lifetime_answered"
        case triviaBestStreak = "trivia_best_streak"
        case triviaSeasonCorrect = "trivia_season_correct"
        case triviaRoundStreak = "trivia_round_streak"
        case triviaLastRound = "trivia_last_round"
        case khgSeasonPoints = "khg_season_points"
        case khgEditionsPlayed = "khg_editions_played"
        case khgWeekStreak = "khg_week_streak"
        case khgBestWeekStreak = "khg_best_week_streak"
        case khgLastWeek = "khg_last_week"
    }

    /// MONOTONIC merge: counters take the max side (an upload-then-reinstall can only restore, never
    /// regress), and each STREAK travels as a PAIR with its last-completed marker — the side that has
    /// played more recently owns the streak, because a streak is only meaningful relative to when it
    /// was last extended. Mixing sides (server streak + local marker) would let the next completion
    /// wrongly continue a dead streak.
    static func merge(local: ProgressSnapshot, server: ProgressSnapshot) -> ProgressSnapshot {
        var out = local

        out.triviaLifetimeCorrect = max(local.triviaLifetimeCorrect, server.triviaLifetimeCorrect)
        out.triviaLifetimeAnswered = max(local.triviaLifetimeAnswered, server.triviaLifetimeAnswered)
        out.triviaBestStreak = max(local.triviaBestStreak, server.triviaBestStreak)
        out.triviaSeasonCorrect = max(local.triviaSeasonCorrect, server.triviaSeasonCorrect)
        if server.triviaLastRound > local.triviaLastRound {
            out.triviaRoundStreak = server.triviaRoundStreak
            out.triviaLastRound = server.triviaLastRound
        }

        out.khgSeasonPoints = max(local.khgSeasonPoints, server.khgSeasonPoints)
        out.khgEditionsPlayed = max(local.khgEditionsPlayed, server.khgEditionsPlayed)
        out.khgBestWeekStreak = max(local.khgBestWeekStreak, server.khgBestWeekStreak)
        if let serverWeek = server.khgLastWeek, serverWeek > (local.khgLastWeek ?? "") {
            // ISO weekKeys ("2026-W29") sort lexically == chronologically.
            out.khgWeekStreak = server.khgWeekStreak
            out.khgLastWeek = serverWeek
        }

        return out
    }
}

struct ProgressSyncService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Upsert the user's whole summary row (the coordinator's post-merge round-trip). Best-effort —
    /// a failure leaves local state intact (it's the source during play) and is flagged via
    /// telemetry, never surfaced to the user.
    func upload(_ snapshot: ProgressSnapshot, userID: UUID) async {
        do {
            try await client.from("fanzone_progress")
                .upsert(UpsertRow(user_id: userID, snapshot: snapshot), onConflict: "user_id,season")
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "progress upload: \(error.localizedDescription)")
        }
    }

    /// Per-game PARTIAL upserts, called fire-and-forget from a game's completion flow. PostgREST's
    /// merge-duplicates upsert updates ONLY the supplied columns, so Trivia's write can never clobber
    /// Know Her's numbers (and vice versa) — which is what lets each game view push its own progress
    /// without a shared coordinator in the environment.
    func uploadTrivia(lifetimeCorrect: Int, lifetimeAnswered: Int, bestStreak: Int,
                      seasonCorrect: Int, roundStreak: Int, lastRound: Int,
                      userID: UUID, season: String) async {
        struct Row: Encodable {
            let user_id: UUID, season: String
            let trivia_lifetime_correct: Int, trivia_lifetime_answered: Int
            let trivia_best_streak: Int, trivia_season_correct: Int
            let trivia_round_streak: Int, trivia_last_round: Int
        }
        do {
            try await client.from("fanzone_progress")
                .upsert(Row(user_id: userID, season: season,
                            trivia_lifetime_correct: lifetimeCorrect, trivia_lifetime_answered: lifetimeAnswered,
                            trivia_best_streak: bestStreak, trivia_season_correct: seasonCorrect,
                            trivia_round_streak: roundStreak, trivia_last_round: lastRound),
                        onConflict: "user_id,season")
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "progress upload trivia: \(error.localizedDescription)")
        }
    }

    func uploadKnowHer(points: Int, editions: Int, weekStreak: Int, bestWeekStreak: Int,
                       lastWeek: String?, userID: UUID, season: String) async {
        struct Row: Encodable {
            let user_id: UUID, season: String
            let khg_season_points: Int, khg_editions_played: Int
            let khg_week_streak: Int, khg_best_week_streak: Int, khg_last_week: String?
        }
        do {
            try await client.from("fanzone_progress")
                .upsert(Row(user_id: userID, season: season,
                            khg_season_points: points, khg_editions_played: editions,
                            khg_week_streak: weekStreak, khg_best_week_streak: bestWeekStreak,
                            khg_last_week: lastWeek),
                        onConflict: "user_id,season")
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "progress upload knowher: \(error.localizedDescription)")
        }
    }

    /// The user's server snapshot for `season` (nil = no row yet, or a read failure — the caller
    /// just skips the restore; the next completion uploads and self-heals).
    func fetch(userID: UUID, season: String) async -> ProgressSnapshot? {
        do {
            let rows: [ProgressSnapshot] = try await client.from("fanzone_progress")
                .select()
                .eq("user_id", value: userID)
                .eq("season", value: season)
                .execute().value
            return rows.first
        } catch {
            Diagnostics.shared.record(.apiFailure, "progress fetch: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct UpsertRow: Encodable {
    let user_id: UUID
    let snapshot: ProgressSnapshot

    func encode(to encoder: Encoder) throws {
        // Flatten: one wire row = user_id + the snapshot's columns.
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(user_id, forKey: AnyCodingKey("user_id"))
        try snapshot.encode(to: encoder)
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
