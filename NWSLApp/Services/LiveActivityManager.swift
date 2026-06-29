//
//  LiveActivityManager.swift
//  NWSLApp
//
//  The app side of V2 Live Activities — the token plumbing the watcher needs. It does NOT decide
//  which matches start an Activity (that's the watcher's push-to-start trigger, gated on
//  team_alert_preferences); the app's job is to (1) register this device's push-to-start token so the
//  watcher can remotely create the Activity ~5 min before kickoff, (2) capture each running Activity's
//  per-Activity update token (keyed by match) so the watcher can push goal/HT/FT updates, and (3) prune
//  the row when an Activity ends. Tokens mirror to Supabase, RLS-scoped like device_tokens.
//
//  Push-to-start needs iOS 17.2+ (the app's min deployment). Silent always — the Live Activity never
//  buzzes; V1 push owns the interrupt.
//

import ActivityKit
import Foundation
import os
import Supabase

@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private let client = SupabaseManager.client
    private static let log = Logger(subsystem: "com.tiffanyrieth.nwslapp", category: "LiveActivity")
    private var userID: UUID?
    private var started = false

    /// Wire up once a user is signed in (called from the same place as the other sync coordinators).
    /// Idempotent. Registers the push-to-start token and tracks any already-running Activities.
    func start(userID: UUID) {
        self.userID = userID
        guard !started else { return }
        started = true
        observePushToStartTokens()
        observeNewActivities()
        for activity in Activity<MatchActivityAttributes>.activities { track(activity) }
    }

    func signOut() { userID = nil }

    // MARK: - Push-to-start token (per device → lets the watcher remote-start the Activity)
    private func observePushToStartTokens() {
        Task {
            for await tokenData in Activity<MatchActivityAttributes>.pushToStartTokenUpdates {
                await upsertStartToken(Self.hex(tokenData))
            }
        }
    }

    // MARK: - Per-Activity update token + end-of-life pruning
    private func observeNewActivities() {
        Task {
            for await activity in Activity<MatchActivityAttributes>.activityUpdates { track(activity) }
        }
    }

    private func track(_ activity: Activity<MatchActivityAttributes>) {
        let matchId = activity.attributes.matchId
        Task {
            for await tokenData in activity.pushTokenUpdates {
                await upsertActivityToken(matchId: matchId, token: Self.hex(tokenData))
            }
        }
        Task {
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                await deleteActivity(matchId: matchId)
            }
        }
    }

    // MARK: - Supabase mirror (non-fatal, telemetry-flagged — NO silent failures)
    private func upsertStartToken(_ token: String) async {
        guard let userID else { return }
        do {
            try await client.from("live_activity_start_tokens")
                .upsert(["user_id": userID.uuidString, "token": token], onConflict: "user_id,token")
                .execute()
        } catch { Diagnostics.shared.record(.apiFailure, "LA start-token upsert: \(error.localizedDescription)") }
    }

    private func upsertActivityToken(matchId: String, token: String) async {
        guard let userID else { return }
        do {
            try await client.from("live_activities")
                .upsert(["user_id": userID.uuidString, "match_id": matchId, "push_token": token],
                        onConflict: "user_id,match_id")
                .execute()
        } catch { Diagnostics.shared.record(.apiFailure, "LA activity-token upsert: \(error.localizedDescription)") }
    }

    private func deleteActivity(matchId: String) async {
        guard let userID else { return }
        do {
            try await client.from("live_activities")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .eq("match_id", value: matchId)
                .execute()
        } catch { Diagnostics.shared.record(.apiFailure, "LA activity delete: \(error.localizedDescription)") }
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    #if DEBUG
    /// Sim/verification only: start a local Activity (no push) so the four surfaces can be eyeballed,
    /// then step it through the full lifecycle (pre → live → goal → HT → 2nd half → goal → FT → end)
    /// with the clock anchored so the minute advances locally. NOT the production start path.
    func debugDriveSampleLifecycle() async {
        let attrs = MatchActivityAttributes(
            matchId: "debug-ORL-POR", homeAbbr: "ORL", awayAbbr: "POR",
            homeColorHex: "B07CE8", awayColorHex: "FF4D6D", competition: "NWSL")
        func state(_ phase: MatchActivityAttributes.Phase, _ h: Int, _ a: Int,
                   minute: Int? = nil, label: String? = nil, scorer: String? = nil)
            -> MatchActivityAttributes.ContentState {
            .init(homeScore: h, awayScore: a, phase: phase,
                  clockStartEpoch: minute.map { Date().timeIntervalSince1970 - Double($0) * 60 },
                  staticLabel: label, lastScorer: scorer, broadcast: "Paramount+")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.log.error("Live Activities disabled in Settings; cannot start sample.")
            return
        }
        let activity: Activity<MatchActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state(.pre, 0, 0, label: "3:00 PM"), staleDate: nil))
        } catch {
            Self.log.error("sample LA start failed: \(error.localizedDescription)")
            return
        }
        let steps: [(MatchActivityAttributes.ContentState, UInt64)] = [
            (state(.live, 0, 0, minute: 1), 5),
            (state(.live, 1, 0, minute: 23, scorer: "B. Banda 23'"), 5),
            (state(.halftime, 1, 0, label: "HT"), 5),
            (state(.live, 1, 0, minute: 46), 5),
            (state(.live, 2, 1, minute: 78, scorer: "Marta 78'"), 5),
            (state(.fulltime, 2, 1, label: "FT"), 5),
        ]
        for (s, delay) in steps {
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            await activity.update(.init(state: s, staleDate: nil))
        }
        try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
        await activity.end(.init(state: steps.last!.0, staleDate: nil), dismissalPolicy: .immediate)
    }
    #endif
}
