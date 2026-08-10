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

    /// SEASON-board RECENCY window (owner ruling 2026-08-04 — replaced the old 3-match ranking gate).
    /// You rank from your FIRST prediction (no entry barrier); you only fall off the season board after
    /// going quiet for this long. ~3 months, break-tolerant (a World Cup / international window won't drop
    /// a casual player). Keeps the board low-stakes + fun-for-all while stopping a lucky one-off from
    /// sitting at the top for a whole season. Round boards are exempt (a round is one week).
    static let recencyWindow: TimeInterval = 90 * 24 * 3600

    /// ISO-8601 cutoff for "active this window" — `last_scored_at >= this` stays on the season board.
    private static func recencyCutoffISO() -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-recencyWindow))
    }

    /// One other player's standing for a team (the signed-in user is excluded by
    /// the caller and spliced in from their live local total instead). `matches`/`avg`
    /// populate for the SEASON board (ranked by average per match); the round board
    /// leaves them at 0 (it ranks by the week's raw points — a round is 1–2 matches).
    struct Standing {
        let userID: String
        let name: String
        let points: Int
        var matches: Int = 0
        var avg: Double = 0
    }

    private struct MergeBestsParams: Encodable {
        let p_season: String
        let p_match: Int
        let p_round: Int
    }

    /// Raise the user's season personal bests — the thresholds the superlative ladder compares
    /// against ("your best match of the season").
    ///
    /// ⚠️ Server-side `GREATEST`, not a read-then-write. Those marks must survive a reinstall and
    /// two devices used out of order, and the read-then-write shape used by `upsertScore` above
    /// carries a known race (see docs/roadmap.md's multi-device note) that an atomic merge simply
    /// doesn't have. Passing 0 leaves a mark untouched.
    ///
    /// Best-effort: a failure means the ladder's season-best rungs can't fire (its inputs stay
    /// unknown), which is a missing compliment — never a wrong one.
    func mergeSeasonBests(season: String, matchStarters: Int, roundStarters: Int) async {
        guard matchStarters > 0 || roundStarters > 0 else { return }
        do {
            try await client
                .rpc("predict_merge_bests", params: MergeBestsParams(
                    p_season: season, p_match: matchStarters, p_round: roundStarters))
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "predict season bests: \(error.localizedDescription)")
        }
    }

    /// The user's stored season bests, or nil when unavailable (signed out, offline, or never set).
    /// nil is meaningful: the ladder treats an unknown baseline differently from a zero one, so a
    /// user's very first result never claims to be a personal best.
    func seasonBests(season: String) async -> PredictSeasonBests? {
        struct Row: Decodable {
            let season: String
            let best_match_starters: Int
            let best_round_starters: Int
        }
        do {
            let rows: [Row] = try await client
                .from("predict_season_bests")
                .select("season,best_match_starters,best_round_starters")
                .eq("season", value: season)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return PredictSeasonBests(season: row.season,
                                      bestMatchStarters: row.best_match_starters,
                                      bestRoundStarters: row.best_round_starters)
        } catch {
            Diagnostics.shared.record(.apiFailure, "predict season bests read: \(error.localizedDescription)")
            return nil
        }
    }

    /// Push the user's season total for ONE team. Best-effort: a failure leaves the
    /// local score intact and the next load retries the push. Signed-in only (the
    /// caller guards on `userID`).
    func upsertScore(teamAbbreviation: String, points: Int, matches: Int,
                     displayName: String?, userID: UUID, season: String) async {
        do {
            // Guard against a DOWNWARD clobber. Both `points` and `matches` are monotonic (Σ of scored
            // fixtures; a scored fixture never un-scores), but the local store is UserDefaults-only and
            // resets to ~0 on a reinstall. A plain overwrite upsert would replace the server's accumulated
            // values (e.g. 300 pts / 15 matches) with the small post-reinstall local values — silent,
            // permanent standing loss. So read the user's current server pair first and push the GREATER of
            // each: the server can only ever go UP. `avg_points` is derived from the merged pair so the
            // board can ORDER BY it (and the rank COUNT can compare it) with no rows transferred. If the
            // READ fails we skip the push (throws → caught → retried next load) rather than risk a clobber.
            let server = try await currentScore(teamAbbreviation: teamAbbreviation, userID: userID, season: season)
            let mergedPoints = max(points, server.points)
            let mergedMatches = max(matches, server.matches)
            let avg = mergedMatches > 0 ? Double(mergedPoints) / Double(mergedMatches) : 0
            let row = ScoreUpsert(user_id: userID, team_abbreviation: teamAbbreviation,
                                  season: season,
                                  // Coalesce with the row's stored name: a pre-hydrate device (nil local
                                  // name) keeps writing the name the board already shows. nil-nil is safe
                                  // either way — synthesized Encodable OMITS a nil optional, so an upsert
                                  // can never null an existing name.
                                  display_name: displayName ?? server.name,
                                  points: mergedPoints, matches: mergedMatches, avg_points: avg)
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

    /// The signed-in user's OWN current server (points, matches, stored name) for a team this season
    /// (0/0/nil if no row yet). Used to clamp `upsertScore` to a non-decreasing pair. Throws on a read
    /// failure so the caller skips the push and retries next load — never worse than the old
    /// unconditional overwrite.
    private func currentScore(teamAbbreviation: String, userID: UUID,
                              season: String) async throws -> (points: Int, matches: Int, name: String?) {
        let rows: [ScoreRow] = try await client
            .from("prediction_scores")
            .select("user_id, display_name, points, matches")
            .eq("user_id", value: userID)
            .eq("team_abbreviation", value: teamAbbreviation)
            .eq("season", value: season)
            .limit(1)
            .execute()
            .value
        return (rows.first?.points ?? 0, rows.first?.matches ?? 0, rows.first?.display_name)
    }

    /// The signed-in user's OWN season standing for one team, as the SERVER holds it — the reinstall
    /// read: after a wipe, the board's "You" row renders from this instead of the empty local store.
    /// Filtered by the SAME recency window as `standings`, so a fallen-off row can't resurrect a rank
    /// the public board wouldn't show. nil = no (active) row, or the read failed (the caller falls
    /// back to local state — honest, never fabricated).
    func myScore(teamAbbreviation: String, season: String,
                 userID: UUID) async -> LeaderboardRanking.SeasonStanding? {
        do {
            let rows: [ScoreRow] = try await client
                .from("prediction_scores")
                .select("user_id, display_name, points, matches, avg_points")
                .eq("user_id", value: userID)
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .gte("last_scored_at", value: Self.recencyCutoffISO())
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return LeaderboardRanking.SeasonStanding(
                points: row.points, matches: row.matches ?? 0, avg: row.avg_points ?? 0)
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict myScore \(teamAbbreviation): \(error.localizedDescription)") }
            return nil
        }
    }

    /// Every team the signed-in user has a season row for — restores the BOARD SET after a reinstall
    /// (the local `scoredTeams` is empty until the results restore lands). Empty on failure.
    func myTeams(season: String, userID: UUID) async -> [String] {
        struct TeamRow: Decodable { let team_abbreviation: String }
        do {
            let rows: [TeamRow] = try await client
                .from("prediction_scores")
                .select("team_abbreviation")
                .eq("user_id", value: userID)
                .eq("season", value: season)
                .execute()
                .value
            return rows.map(\.team_abbreviation)
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict myTeams: \(error.localizedDescription)") }
            return []
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
                .select("user_id, display_name, points, matches, avg_points")
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                // Recency-to-remain: only predictors active within the window stay on the season board
                // (rank from game 1, fall off after ~3 months quiet). See `recencyWindow`.
                .gte("last_scored_at", value: Self.recencyCutoffISO())
                .order("avg_points", ascending: false)   // Batch 3: rank by AVERAGE, not cumulative
                .limit(LeaderboardRanking.visibleLimit)
                .execute()
                .value
            return rows.map { Standing(userID: $0.user_id, name: $0.display_name ?? "Fan",
                                       points: $0.points, matches: $0.matches ?? 0, avg: $0.avg_points ?? 0) }
        } catch {
            // Caller still shows the user's own live total (honest degrade); flag the read
            // failure so a down board isn't silently invisible to the owner.
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict standings \(teamAbbreviation): \(error.localizedDescription)") }
            return []
        }
    }


    /// The signed-in user's TRUE 1-based SEASON rank on a team's board, by AVERAGE per match, computed with
    /// a COUNT (rows averaging strictly higher, +1) — no rows transferred. `nil` on failure, so the caller
    /// falls back to an inline splice rather than a wrong number. Ties break in the user's favour
    /// (strictly-greater only), matching the on-device sort.
    func rank(teamAbbreviation: String, season: String, avgPoints: Double) async -> Int? {
        do {
            let response = try await client
                .from("prediction_scores")
                .select("user_id", head: true, count: .exact)
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                // Rank among ACTIVE predictors only — an inactive (fallen-off) rival can't push you down.
                .gte("last_scored_at", value: Self.recencyCutoffISO())
                .gt("avg_points", value: avgPoints)
                .execute()
            return (response.count ?? 0) + 1
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict rank \(teamAbbreviation): \(error.localizedDescription)") }
            return nil
        }
    }

    /// Total predictors on a team's SEASON board — a `head: true, count: .exact` on all rows for the team
    /// (no rows transferred), for the season card's "#N of M predictors · top X%". 0 on failure.
    func totalPredictors(teamAbbreviation: String, season: String) async -> Int {
        do {
            let response = try await client
                .from("prediction_scores")
                .select("user_id", head: true, count: .exact)
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                // "#N of M" counts ACTIVE predictors, so the shown total agrees with the rank number.
                .gte("last_scored_at", value: Self.recencyCutoffISO())
                .execute()
            return response.count ?? 0
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict total \(teamAbbreviation): \(error.localizedDescription)") }
            return 0
        }
    }

    // MARK: - ROUND boards (predict_round_scores — the comp arena's second clock)

    /// Push the user's points for ONE team in ONE soccer week. The round value is a completed sum
    /// (a week's scored fixtures can only add), so the same non-decreasing clamp as the season
    /// upsert applies — a reinstalled device's partial re-score can't lower the banked round.
    func upsertRoundScore(teamAbbreviation: String, week: Int, points: Int,
                          displayName: String?, userID: UUID, season: String) async {
        do {
            let server = try await currentRoundPoints(
                teamAbbreviation: teamAbbreviation, week: week, userID: userID, season: season)
            let row = RoundScoreUpsert(user_id: userID, team_abbreviation: teamAbbreviation,
                                       season: season, week: week,
                                       // Same coalesce as upsertScore — see the comment there.
                                       display_name: displayName ?? server.name,
                                       points: max(points, server.points))
            try await client
                .from("predict_round_scores")
                .upsert(row, onConflict: "user_id,team_abbreviation,season,week")
                .execute()
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict round upsert \(teamAbbreviation) w\(week): \(error.localizedDescription)") }
        }
    }

    private func currentRoundPoints(teamAbbreviation: String, week: Int,
                                    userID: UUID, season: String) async throws -> (points: Int, name: String?) {
        let rows: [ScoreRow] = try await client
            .from("predict_round_scores")
            .select("user_id, display_name, points")
            .eq("user_id", value: userID)
            .eq("team_abbreviation", value: teamAbbreviation)
            .eq("season", value: season)
            .eq("week", value: week)
            .limit(1)
            .execute()
            .value
        return (rows.first?.points ?? 0, rows.first?.display_name)
    }

    /// The top of a team's ROUND board (one soccer week) — same shape, cap, and honest-empty
    /// contract as the season `standings`.
    func roundStandings(teamAbbreviation: String, season: String, week: Int) async -> [Standing] {
        do {
            let rows: [ScoreRow] = try await client
                .from("predict_round_scores")
                .select("user_id, display_name, points")
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .eq("week", value: week)
                .order("points", ascending: false)
                .limit(LeaderboardRanking.visibleLimit)
                .execute()
                .value
            return rows.map { Standing(userID: $0.user_id, name: $0.display_name ?? "Fan", points: $0.points) }
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict round standings \(teamAbbreviation) w\(week): \(error.localizedDescription)") }
            return []
        }
    }

    /// Total predictors on a team's ROUND board for one soccer week — the "#N of M this round" denominator
    /// on the match-result detail. `head: true, count: .exact`, 0 on failure.
    func roundTotal(teamAbbreviation: String, season: String, week: Int) async -> Int {
        do {
            let response = try await client
                .from("predict_round_scores")
                .select("user_id", head: true, count: .exact)
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .eq("week", value: week)
                .execute()
            return response.count ?? 0
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict round total \(teamAbbreviation) w\(week): \(error.localizedDescription)") }
            return 0
        }
    }

    // MARK: - Graded match results (predict_match_results — reinstall durability, 2026-08-10)

    /// One restored graded match: the submitted XI (state `.submitted`) + the grade, exactly as
    /// this or another device banked them. Feeds `PredictionStore.restoreGradedResults`.
    struct RestoredResult {
        let prediction: XIPrediction
        let score: PredictionScore
    }

    /// Bank one graded match server-side (own-row RLS). PLAIN upsert on the PK — deliberately NOT
    /// max-merged like the board tables: a regrade (the suspended-match self-heal) must be able to
    /// REWRITE the row. Written only post-grading, so the pre-deadline pick-secrecy rule holds.
    /// Best-effort: the caller marks the fixture uploaded only on success and retries next load.
    /// Returns whether the write landed.
    @discardableResult
    func upsertMatchResult(prediction: XIPrediction, score: PredictionScore,
                           userID: UUID, season: String) async -> Bool {
        let row = MatchResultUpsert(
            user_id: userID, event_id: prediction.eventID,
            team_abbreviation: prediction.teamAbbreviation, season: season,
            week: score.soccerWeek,
            correct_players: score.correctPlayers, correct_positions: score.correctPositions,
            formation_correct: score.formationCorrect, exact_scoreline: score.exactScoreline,
            result_correct: score.resultCorrect, perfect_xi: score.perfectXI,
            graded_home_score: score.gradedHomeScore, graded_away_score: score.gradedAwayScore,
            formation: prediction.formation,
            // STRING keys, converted explicitly: the jsonb column's contract is a string-keyed
            // object, and that shouldn't hang on Codable's Int-key encoding special case.
            slots: Dictionary(uniqueKeysWithValues: prediction.slots.map { (String($0.key), $0.value) }),
            home_score_guess: prediction.homeScoreGuess,
            away_score_guess: prediction.awayScoreGuess,
            updated_at: ISO8601DateFormatter().string(from: Date()))
        do {
            try await client
                .from("predict_match_results")
                .upsert(row, onConflict: "user_id,event_id,team_abbreviation")
                .execute()
            return true
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict result upsert \(prediction.fixtureID): \(error.localizedDescription)") }
            return false
        }
    }

    /// Every graded match the user banked this season — the reinstall restore read
    /// (`ProgressSyncCoordinator.restorePredict`). Empty on failure (retried next sign-in observation
    /// or app launch; the boards still render from `myScore` in the meantime).
    func matchResults(season: String) async -> [RestoredResult] {
        do {
            let rows: [MatchResultRow] = try await client
                .from("predict_match_results")
                .select()
                .eq("season", value: season)   // RLS already scopes to the user; season filter is the key
                .execute()
                .value
            return rows.map { row in
                let prediction = XIPrediction(
                    fixtureID: "\(row.event_id)-\(row.team_abbreviation)",
                    eventID: row.event_id, teamAbbreviation: row.team_abbreviation,
                    formation: row.formation,
                    slots: Dictionary(uniqueKeysWithValues: row.slots.compactMap { key, value in
                        Int(key).map { ($0, value) }
                    }),
                    homeScoreGuess: row.home_score_guess, awayScoreGuess: row.away_score_guess,
                    state: .submitted)
                var score = PredictionScore(
                    correctPlayers: row.correct_players, correctPositions: row.correct_positions,
                    formationCorrect: row.formation_correct, exactScoreline: row.exact_scoreline,
                    resultCorrect: row.result_correct, perfectXI: row.perfect_xi)
                score.soccerWeek = row.week
                score.gradedHomeScore = row.graded_home_score
                score.gradedAwayScore = row.graded_away_score
                return RestoredResult(prediction: prediction, score: score)
            }
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict results restore: \(error.localizedDescription)") }
            return []
        }
    }

    /// True 1-based rank on a round board — the COUNT pattern of `rank`, week-scoped.
    func roundRank(teamAbbreviation: String, season: String, week: Int, points: Int) async -> Int? {
        do {
            let response = try await client
                .from("predict_round_scores")
                .select("user_id", head: true, count: .exact)
                .eq("team_abbreviation", value: teamAbbreviation)
                .eq("season", value: season)
                .eq("week", value: week)
                .gt("points", value: points)
                .execute()
            return (response.count ?? 0) + 1
        } catch {
            await MainActor.run { Diagnostics.shared.record(.apiFailure, "predict round rank \(teamAbbreviation) w\(week): \(error.localizedDescription)") }
            return nil
        }
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
// `matches`/`avg_points` are optional-decoded so a round-board row (which selects
// only points) and pre-migration rows still decode.
private struct ScoreRow: Decodable {
    let user_id: String
    let display_name: String?
    let points: Int
    let matches: Int?
    let avg_points: Double?
}

private struct ScoreUpsert: Encodable {
    let user_id: UUID
    let team_abbreviation: String
    let season: String
    let display_name: String?
    let points: Int
    let matches: Int
    let avg_points: Double
}

private struct RoundScoreUpsert: Encodable {
    let user_id: UUID
    let team_abbreviation: String
    let season: String
    let week: Int
    let display_name: String?
    let points: Int
}

// predict_match_results (reinstall durability). `slots` rides as an explicitly String-keyed
// object both ways — the wire contract, independent of Codable's Int-key encoding behavior.
private struct MatchResultUpsert: Encodable {
    let user_id: UUID
    let event_id: String
    let team_abbreviation: String
    let season: String
    let week: Int?
    let correct_players: Int
    let correct_positions: Int
    let formation_correct: Bool
    let exact_scoreline: Bool
    let result_correct: Bool
    let perfect_xi: Bool
    let graded_home_score: Int?
    let graded_away_score: Int?
    let formation: String
    let slots: [String: String]
    let home_score_guess: Int
    let away_score_guess: Int
    let updated_at: String
}

struct MatchResultRow: Decodable {
    let event_id: String
    let team_abbreviation: String
    let season: String
    let week: Int?
    let correct_players: Int
    let correct_positions: Int
    let formation_correct: Bool
    let exact_scoreline: Bool
    let result_correct: Bool
    let perfect_xi: Bool
    let graded_home_score: Int?
    let graded_away_score: Int?
    let formation: String
    let slots: [String: String]
    let home_score_guess: Int
    let away_score_guess: Int
}
