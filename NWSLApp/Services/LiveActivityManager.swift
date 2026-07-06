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
import UIKit

@MainActor
@Observable
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private let client = SupabaseManager.client
    private static let log = Logger(subsystem: "com.tiffanyrieth.nwslapp", category: "LiveActivity")
    private var observing = false
    /// Latest push-to-start token seen this launch — cached so a token captured before the Supabase
    /// session is restored (the first sign-in during onboarding) can be flushed by `userDidSignIn()`.
    private var latestStartToken: String?

    /// Prime the ActivityKit observers. MUST run at app launch (AppDelegate.didFinishLaunching) and NOT
    /// from a view — so it also runs on a cold *background* launch: when a push-to-start arrives with the
    /// app not running, iOS launches us in the background and creates the Activity, and only a
    /// launch-primed `activityUpdates` observer can capture that Activity's per-update push token. Wiring
    /// this behind a SwiftUI view (which never renders on a background launch) is the bug that left the
    /// per-Activity token unregistered. Independent of sign-in — uploads resolve the user from the
    /// restored session at write time. Idempotent.
    ///
    /// Apple caveat: if the user *force-quits* the app (swipes it from the App Switcher and never
    /// reopens), push-to-start still creates and renders the Activity but `pushTokenUpdates` never fires,
    /// so the watcher can't update/end it. That single case is a platform limitation, not coverable here.
    func startObserving() {
        guard !observing else { return }
        observing = true
        // Breadcrumb: proves the observer was primed AND whether this is a background launch (the
        // whole point of #104). `activities` is the snapshot of Activities that already exist — on a
        // push-to-start background launch the just-created Activity is usually here.
        let snapshot = Activity<MatchActivityAttributes>.activities
        let laEnabled = Self.areActivitiesEnabled
        Diagnostics.shared.record(.liveActivityTrace,
            "startObserving state=\(Self.appStateLabel) snapshot=\(snapshot.count) laEnabled=\(laEnabled)")
        // Gap E: if Live Activities are OFF in iOS Settings the OS NEVER yields a push-to-start token,
        // so `live_activity_start_tokens` can't populate. Surface it as a fail crumb so it's diagnosable
        // rather than looking identical to "token received and uploaded" from the server's side.
        NotifTrace.shared.log("push-start-observe", laEnabled ? .ok : .fail,
            "laEnabled=\(laEnabled) snapshot=\(snapshot.count) state=\(Self.appStateLabel)")
        observePushToStartTokens()
        observeNewActivities()
        for activity in snapshot { track(activity) }
    }

    /// Whether iOS Live Activities are enabled for this app (the Settings toggle). When false the OS
    /// emits no push-to-start token — read by the reconcile + surfaced in the diagnostics screen.
    static var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Diagnostics-only: the 10-char prefix of the push-to-start token the OS has emitted this process,
    /// or nil if none seen yet (the empty-table symptom). For the in-app Notification Diagnostics screen.
    var startTokenPrefix: String? { latestStartToken.map { String($0.prefix(10)) } }

    /// Call when a user signs in — flush a push-to-start token captured before the session existed (the
    /// observer skipped its upload). Returning users upload directly from the restored session, so this
    /// covers only the brand-new-sign-in path.
    func userDidSignIn() {
        guard let token = latestStartToken else { return }
        Task { await upsertStartToken(token) }
    }

    /// Re-upload the last-known push-to-start token — the RETRY/re-flush hook. Called from the launch +
    /// foreground reconcile and after session restore, so a token that was dropped because the session
    /// wasn't ready yet (the returning-user race, Gap A) gets uploaded once a session exists. No-op if
    /// the OS hasn't emitted a token yet.
    func reflushStartToken(reason: String) async {
        guard let token = latestStartToken else {
            NotifTrace.shared.log("push-start-reflush", .skip, "no token yet (\(reason))")
            return
        }
        await upsertStartToken(token)
    }

    // MARK: - Push-to-start token (per device → lets the watcher remote-start the Activity)
    private func observePushToStartTokens() {
        Task {
            for await tokenData in Activity<MatchActivityAttributes>.pushToStartTokenUpdates {
                let token = Self.hex(tokenData)
                latestStartToken = token
                Diagnostics.shared.record(.liveActivityTrace, "start-token rx state=\(Self.appStateLabel)")
                NotifTrace.shared.log("push-start-rx", .ok, "token=\(token.prefix(10))… state=\(Self.appStateLabel)")
                await upsertStartToken(token)
            }
        }
    }

    // MARK: - Per-Activity update token + end-of-life pruning
    private func observeNewActivities() {
        Task {
            for await activity in Activity<MatchActivityAttributes>.activityUpdates {
                Diagnostics.shared.record(.liveActivityTrace,
                    "activityUpdate match=\(activity.attributes.matchId) state=\(Self.appStateLabel)")
                track(activity)
            }
        }
    }

    private func track(_ activity: Activity<MatchActivityAttributes>) {
        let matchId = activity.attributes.matchId
        Task {
            for await tokenData in activity.pushTokenUpdates {
                Diagnostics.shared.record(.liveActivityTrace, "activity-token rx match=\(matchId)")
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

    /// The signed-in user's id from the Supabase session, with ONE short retry. `auth.session` loads the
    /// persisted session from the Keychain (independent of any view/`restoreSession()`), and *refreshes*
    /// it over the network if the access token expired (Supabase tokens last ~1h — a backgrounded phone
    /// idle >1h will refresh). On a background launch that refresh can be mid-flight; the retry gives it a
    /// beat to settle before we give up. Callers run this INSIDE `withBackgroundTime`, so the refresh has
    /// protected runtime. Signed-out → nil → the caller skips (loudly).
    private func resolveUserID() async -> UUID? {
        if let id = try? await client.auth.session.user.id { return id }
        try? await Task.sleep(nanoseconds: 700_000_000)
        return try? await client.auth.session.user.id
    }

    private func upsertStartToken(_ token: String) async {
        await withBackgroundTime("LA start-token upsert") {
            guard let userID = await self.resolveUserID() else {
                Diagnostics.shared.record(.liveActivityTrace, "start-token drop: no session state=\(Self.appStateLabel)")
                NotifTrace.shared.log("push-start-upsert", .skip, "dropped: no session (reflushed later) state=\(Self.appStateLabel)")
                return
            }
            do {
                try await self.client.from("live_activity_start_tokens")
                    .upsert(["user_id": userID.uuidString, "device_id": DeviceIdentity.deviceID, "token": token],
                            onConflict: "user_id,device_id")
                    .execute()
                Diagnostics.shared.record(.liveActivityTrace, "start-token upsert ok")
                NotifTrace.shared.log("push-start-upsert", .ok, "token=\(token.prefix(10))…")
            } catch {
                Diagnostics.shared.record(.apiFailure, "LA start-token upsert: \(error.localizedDescription)")
                NotifTrace.shared.log("push-start-upsert", .fail, error.localizedDescription)
            }
        }
    }

    private func upsertActivityToken(matchId: String, token: String) async {
        await withBackgroundTime("LA activity-token upsert") {
            guard let userID = await self.resolveUserID() else {
                // The exact failure the whole background-launch design hinges on — NEVER silent.
                Diagnostics.shared.record(.liveActivityTrace,
                    "activity-token DROP: no session state=\(Self.appStateLabel) match=\(matchId)")
                return
            }
            do {
                try await self.client.from("live_activities")
                    .upsert(["user_id": userID.uuidString, "match_id": matchId, "push_token": token],
                            onConflict: "user_id,match_id")
                    .execute()
                Diagnostics.shared.record(.liveActivityTrace, "activity-token upsert ok match=\(matchId)")
            } catch { Diagnostics.shared.record(.apiFailure, "LA activity-token upsert: \(error.localizedDescription)") }
        }
    }

    private func deleteActivity(matchId: String) async {
        await withBackgroundTime("LA activity delete") {
            guard let userID = await self.resolveUserID() else {
                Diagnostics.shared.record(.liveActivityTrace, "activity delete skip: no session match=\(matchId)")
                return
            }
            do {
                try await self.client.from("live_activities")
                    .delete()
                    .eq("user_id", value: userID.uuidString)
                    .eq("match_id", value: matchId)
                    .execute()
            } catch { Diagnostics.shared.record(.apiFailure, "LA activity delete: \(error.localizedDescription)") }
        }
    }

    // MARK: - Background runtime + helpers

    /// Run `work` under a UIKit background-task assertion so a push-to-start BACKGROUND launch grants
    /// enough runtime to finish the async session-refresh + Supabase (RLS) write instead of suspending
    /// us mid-flight — the leak that left `live_activities` empty. Balanced end in both the normal and
    /// expiration paths.
    private func withBackgroundTime(_ reason: String, _ work: () async -> Void) async {
        let app = UIApplication.shared
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = app.beginBackgroundTask(withName: reason) {
            // Gap D: the assertion ran out of time — the upsert may have been abandoned mid-flight.
            // Was previously silent; leave a crumb so a timed-out write is diagnosable (a reflush on
            // the next foreground/reconcile recovers it).
            NotifTrace.shared.log("bg-expiry", .fail, reason)
            if taskID != .invalid { app.endBackgroundTask(taskID); taskID = .invalid }
        }
        await work()
        if taskID != .invalid { app.endBackgroundTask(taskID); taskID = .invalid }
    }

    /// Coarse app state for telemetry — `background` in a breadcrumb proves the observer fired on a
    /// background launch (vs a foreground open), which is what we're verifying.
    private static var appStateLabel: String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
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
                   minute: Int? = nil, label: String? = nil, scorer: String? = nil,
                   homeScorers: [String]? = nil, awayScorers: [String]? = nil,
                   homeReds: Int? = nil, awayReds: Int? = nil)
            -> MatchActivityAttributes.ContentState {
            .init(homeScore: h, awayScore: a, phase: phase,
                  clockStartEpoch: minute.map { Date().timeIntervalSince1970 - Double($0) * 60 },
                  staticLabel: label, lastScorer: scorer, broadcast: "Paramount+",
                  homeScorers: homeScorers, awayScorers: awayScorers,
                  homeRedCards: homeReds, awayRedCards: awayReds)
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
        // Steps exercise the per-side layout: scorer columns fill in under each team, a red
        // card appears on the away side at 61', and the legacy lastScorer keeps riding along
        // (production sends both; the widget prefers the columns and drops the footer line).
        let steps: [(MatchActivityAttributes.ContentState, UInt64)] = [
            (state(.live, 0, 0, minute: 1), 5),
            (state(.live, 1, 0, minute: 23, scorer: "B. Banda 23'",
                   homeScorers: ["B. Banda 23'"]), 5),
            (state(.halftime, 1, 0, label: "HT",
                   homeScorers: ["B. Banda 23'"]), 5),
            (state(.live, 1, 0, minute: 46,
                   homeScorers: ["B. Banda 23'"]), 5),
            (state(.live, 1, 0, minute: 61,
                   homeScorers: ["B. Banda 23'"], awayReds: 1), 5),
            (state(.live, 2, 1, minute: 78, scorer: "Marta 78'",
                   homeScorers: ["B. Banda 23'", "Marta 78'"],
                   awayScorers: ["S. Wilson 70'"], awayReds: 1), 5),
            (state(.fulltime, 2, 1, label: "FT",
                   homeScorers: ["B. Banda 23'", "Marta 78'"],
                   awayScorers: ["S. Wilson 70'"], awayReds: 1), 5),
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
