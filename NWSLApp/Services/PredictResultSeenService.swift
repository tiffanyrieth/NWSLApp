//
//  PredictResultSeenService.swift
//  NWSLApp
//
//  Writes the server-visible "this user viewed this match's Predict result" mark (Change 8 — the
//  post-match "your result is in" push). Until this, seen-ness was LOCAL-ONLY
//  (`PredictionStore.seenResultFixtureIDs`), so the match-watcher had no way to skip people who already
//  looked. The result screen calls `markSeen` when it renders; the watcher left-anti-joins
//  `predict_result_seen` so a viewer is never pushed the next-day reminder.
//
//  Fire-and-forget after the local seen-write, offline-tolerant (mirrors PredictCommunityService): a
//  failure never throws to the UI and only means one user might get a redundant "your result is in"
//  push they'd otherwise be spared. Retry-until-written is driven by the caller (PredictionStore's
//  `uploadedResultSeenFixtureIDs` fast-path re-attempts on each result-screen open until the write lands).
//

import Foundation
import Supabase

struct PredictResultSeenService {
    /// The row shape — `(user_id, event_id)`; `seen_at` defaults server-side. Insert-if-absent.
    private struct SeenRow: Encodable {
        let user_id: UUID
        let event_id: String
    }

    /// Record that `userID` has seen the result for `eventID`. Idempotent on `(user_id, event_id)`.
    /// Returns true on a confirmed write so the caller can latch the local fast-path.
    @discardableResult
    func markSeen(eventID: String, userID: UUID) async -> Bool {
        do {
            try await SupabaseManager.client
                .from("predict_result_seen")
                .upsert(SeenRow(user_id: userID, event_id: eventID), onConflict: "user_id,event_id")
                .execute()
            return true
        } catch {
            Diagnostics.shared.record(.apiFailure,
                "predict result-seen \(eventID): \(error.localizedDescription)")
            return false
        }
    }
}
