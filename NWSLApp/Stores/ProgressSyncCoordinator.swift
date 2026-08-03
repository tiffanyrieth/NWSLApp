//
//  ProgressSyncCoordinator.swift
//  NWSLApp
//
//  The Fan Zone progress twin of FollowSyncCoordinator: bridges the game stores (TriviaStore /
//  KnowHerGameStore) and the server summary row (`fanzone_progress` via ProgressSyncService). Held
//  alive by RootTabView (not in the environment); the stores stay dependency-free and know nothing
//  about the network.
//
//  Flow: on sign-in (or a restored session at launch) → fetch the server snapshot → MERGE
//  (ProgressSnapshot.merge, monotonic) → fold back into the stores → upload the merged result so the
//  server row is immediately whole again. During play, the game views call `uploadCurrent()` after a
//  completion (fire-and-forget) — the device leads while playing; the server only ever leads at
//  sign-in on a device with less progress (fresh install / replacement phone).
//
//  Predict + Bracket contribute NO rows to `fanzone_progress` — their numbers live in their own
//  server tables (prediction_scores / bracket_user_edition_stats) and flow back through the
//  leaderboard reads. They are held here only for the Superfan merge below, which spans all four
//  games.
//
//  ⚠️ IT ALSO RUNS THE SUPERFAN MERGE AT SIGN-IN (2026-08-03, `docs/data-sync.md` gap 2). That
//  GREATEST-merge used to happen ONLY when SuperfanDetailView opened, so a replacement phone showed
//  an understated Superfan number on the Home card — and submitted that understated number to Game
//  Center — until the user happened to visit the detail screen. Nothing was ever lost, but the first
//  thing a returning user saw was a smaller score than they earned, which is exactly the "did I lose
//  my progress?" moment the durable tier exists to prevent.
//

import Foundation
import Observation

@MainActor
@Observable
final class ProgressSyncCoordinator {
    private let trivia: TriviaStore
    private let knowHer: KnowHerGameStore
    /// Predict + Bracket are here ONLY for the Superfan merge — `SuperfanCounts.fromStores` spans all
    /// four games. Neither contributes to the `fanzone_progress` snapshot.
    private let predict: PredictionStore
    private let bracket: BracketStore
    private let auth: AuthStore
    private let service: ProgressSyncService
    private let superfan: SuperfanService

    /// Last user id we restored for, so the (network) restore runs once per sign-in,
    /// not on every observation tick.
    private var lastUserID: UUID?

    init(trivia: TriviaStore, knowHer: KnowHerGameStore,
         predict: PredictionStore, bracket: BracketStore, auth: AuthStore,
         service: ProgressSyncService = ProgressSyncService(),
         superfan: SuperfanService = SuperfanService()) {
        self.trivia = trivia
        self.knowHer = knowHer
        self.predict = predict
        self.bracket = bracket
        self.auth = auth
        self.service = service
        self.superfan = superfan
    }

    /// Call once from RootTabView (after auth.restoreSession, like FollowSyncCoordinator.start).
    func start() {
        if let userID = auth.userID {
            lastUserID = userID
            restoreAndReconcile(userID: userID)
        }
        observeAuth()
    }

    // Per-completion uploads do NOT come through here: each game view fires its own PARTIAL
    // column upsert (ProgressSyncService.uploadTrivia/uploadKnowHer) so no view needs this
    // coordinator in the environment. This coordinator owns only the sign-in restore + round-trip.

    // MARK: - Internals

    private func currentSnapshot() -> ProgressSnapshot {
        let year = AppConfig.currentSeasonYear
        let t = trivia.progressSnapshot()
        let k = knowHer.progressSnapshot(year: year)
        return ProgressSnapshot(
            season: String(year),
            triviaLifetimeCorrect: t.lifetimeCorrect, triviaLifetimeAnswered: t.lifetimeAnswered,
            triviaBestStreak: t.bestStreak, triviaSeasonCorrect: t.seasonCorrect,
            triviaRoundStreak: t.roundStreak, triviaLastRound: t.lastRound,
            khgSeasonPoints: k.points, khgEditionsPlayed: k.editions,
            khgWeekStreak: k.weekStreak, khgBestWeekStreak: k.bestWeekStreak, khgLastWeek: k.lastWeek)
    }

    private func restoreAndReconcile(userID: UUID) {
        Task {
            let year = AppConfig.currentSeasonYear

            // ⚠️ SUPERFAN FIRST, and deliberately OUTSIDE the `fanzone_progress` guard below.
            // A Predict/Bracket-only player has NO fanzone_progress row at all (that table carries
            // only Trivia + Know Her Game), yet can have a rich superfan_scores row — so running this
            // after the guard would skip exactly the replacement-phone user it exists to serve.
            await mergeSuperfan(userID: userID, year: year)

            guard let server = await service.fetch(userID: userID, season: String(year)) else {
                // No row yet (first sign-in) or a transient failure — nothing to restore; the next
                // completion uploads and creates the row. fetch() already logged any failure.
                return
            }
            let merged = ProgressSnapshot.merge(local: currentSnapshot(), server: server)
            // NOTE: merged.triviaSeasonCorrect is NOT passed — the season accuracy pair is never
            // restored (KHG-sibling rule; fanzone_progress has no season-answered twin, and restoring
            // one half inflated accuracy to a false 100%). Reinstall durability for season accuracy
            // rides superfan_scores, same as Know Her Game. The column is still uploaded (round-trip
            // below) so older builds that read it keep working.
            trivia.restoreProgress(
                lifetimeCorrect: merged.triviaLifetimeCorrect,
                lifetimeAnswered: merged.triviaLifetimeAnswered,
                bestStreak: merged.triviaBestStreak,
                roundStreak: merged.triviaRoundStreak,
                lastRound: merged.triviaLastRound)
            knowHer.restoreProgress(
                year: year,
                points: merged.khgSeasonPoints,
                editions: merged.khgEditionsPlayed,
                weekStreak: merged.khgWeekStreak,
                bestWeekStreak: merged.khgBestWeekStreak,
                lastWeek: merged.khgLastWeek)
            // Round-trip the merged row so the server is whole even if this device had the fresher
            // side (e.g. an offline play followed by sign-in on the same device).
            await service.upload(merged, userID: userID)
        }
    }

    /// Adopt the server's Superfan counts at sign-in, so Home and Game Center show the real score on
    /// a replacement phone without waiting for a visit to Superfan detail.
    ///
    /// Safe to run on every sign-in: `submit` GREATEST-merges per counter server-side and returns the
    /// merged result, so a device that has played less can only ever raise the number, never lower it
    /// — and a later SuperfanDetailView open re-running the same merge is a no-op on identical input.
    /// Best-effort throughout (`submit` never throws; it logs and returns `local` on failure), because
    /// this must never be able to fail the progress restore that follows it.
    private func mergeSuperfan(userID: UUID, year: Int) async {
        let local = SuperfanCounts.fromStores(
            season: year, predict: predict, bracket: bracket, trivia: trivia, knowHer: knowHer)
        // A signed-in user who has never played would otherwise get an all-zero row written on every
        // cold launch — pure churn, and a null-display-name row on the board's backing table.
        guard local != .zero else { return }

        let merged = await superfan.submit(
            counts: local, season: String(year), userID: userID, displayName: auth.displayName)
        SuperfanCountsCache.save(merged, season: year)
        // The season record book is monotonic on `peak_score`, so this is idempotent too. Without it
        // a user who never opens the detail screen keeps a stale record all season.
        await superfan.submitSeasonHistory(
            seasonYear: year, score: SuperfanScoring.total(counts: merged), userID: userID)
    }

    /// Re-arming observation of `auth.userID` — same pattern (and reasoning) as FollowSyncCoordinator.
    private func observeAuth() {
        withObservationTracking {
            _ = auth.userID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newID = auth.userID
                defer { lastUserID = newID }
                if let newID, newID != lastUserID {
                    restoreAndReconcile(userID: newID)
                }
                observeAuth()
            }
        }
    }
}
