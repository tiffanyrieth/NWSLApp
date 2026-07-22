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
//  Predict + Bracket are absent on purpose: their numbers already live in their own server tables
//  (prediction_scores / bracket_user_edition_stats) and flow back through the leaderboard reads.
//

import Foundation
import Observation

@MainActor
@Observable
final class ProgressSyncCoordinator {
    private let trivia: TriviaStore
    private let knowHer: KnowHerGameStore
    private let auth: AuthStore
    private let service: ProgressSyncService

    /// Last user id we restored for, so the (network) restore runs once per sign-in,
    /// not on every observation tick.
    private var lastUserID: UUID?

    init(trivia: TriviaStore, knowHer: KnowHerGameStore, auth: AuthStore,
         service: ProgressSyncService = ProgressSyncService()) {
        self.trivia = trivia
        self.knowHer = knowHer
        self.auth = auth
        self.service = service
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
            guard let server = await service.fetch(userID: userID, season: String(year)) else {
                // No row yet (first sign-in) or a transient failure — nothing to restore; the next
                // completion uploads and creates the row. fetch() already logged any failure.
                return
            }
            let merged = ProgressSnapshot.merge(local: currentSnapshot(), server: server)
            trivia.restoreProgress(
                lifetimeCorrect: merged.triviaLifetimeCorrect,
                lifetimeAnswered: merged.triviaLifetimeAnswered,
                bestStreak: merged.triviaBestStreak,
                seasonCorrect: merged.triviaSeasonCorrect,
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
