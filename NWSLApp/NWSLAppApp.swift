//
//  NWSLAppApp.swift
//  NWSLApp
//
//  Created by Tiffany Rieth on 5/19/26.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct NWSLAppApp: App {
    // A UIKit app delegate, adopted into SwiftUI's lifecycle. We need one because
    // APNs registration (device-token capture) and notification taps are delivered
    // only to a UIApplicationDelegate / UNUserNotificationCenterDelegate — there is
    // no pure-SwiftUI equivalent. The delegate forwards what it receives into
    // PushBridge, which the observable side reads (see PushBridge).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        // Dev-only: pass `-resetOnboarding` in the Run scheme's launch arguments
        // to wipe followed teams + the onboarding flag AND the notification first-run
        // state before any store reads UserDefaults, so the next launch is a true
        // brand-new user — first-open picker AND the Teams-tab match-alert coach mark
        // both fire again. Runs here (App.init) because it's the earliest hook — before
        // RootTabView creates the stores. Stripped from release builds.
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            FollowingStore.debugResetState()
            NotificationPreferencesStore.debugResetState()
            // Per-team match alerts are independent of follows — clearing them is what
            // makes the phantom "N teams with match alerts" footer go away on reset
            // (Part B Bug 2). Alerts require following, so a fresh install has none.
            TeamAlertStore.debugResetState()
            // Fan Zone game progress is local source-of-truth (the server holds only
            // additive leaderboard rows, never synced back down) — wipe it too so the
            // reset is a true brand-new install, not just fresh follows. The Supabase
            // session is cleared separately in RootTabView.task (signOut needs the
            // async client, unavailable this early).
            TriviaStore.debugResetState()
            BracketStore.debugResetState()
            PredictionStore.debugResetState()
            // One-time coach marks + the Fan Zone sign-in invite are bare @AppStorage
            // flags. Reset them (write `false` sentinels — same CFPreferences-snapshot
            // reason as the stores) so a reset truly re-fires them: the Teams bell mark,
            // the Social gear mark, and the Fan Zone intro (Part B Bug 9 — a sticky
            // `fanZone.introSeen` was why the intro stopped appearing after the update).
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "hasSeenTeamsAlertTooltip")
            defaults.set(false, forKey: "hasSeenSocialGearTooltip")
            defaults.set(false, forKey: "fanZone.introSeen")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                // TEMP: `-colorAudit` shows the 16-club color-audit screen instead
                // of the app, to verify the team palette. Remove with _ColorAuditView.
                if ProcessInfo.processInfo.arguments.contains("-colorAudit") {
                    ColorAuditView()
                } else if ProcessInfo.processInfo.arguments.contains("-assetAudit") {
                    AssetAuditView()
                } else {
                    RootTabView()
                }
                #else
                RootTabView()
                #endif
            }
            // Force a dark appearance app-wide (a single dark identity, like
            // the MLS app), independent of the device setting. Set on the
            // root view inside WindowGroup so it also reaches presented
            // sheets (onboarding, Feed content preferences). There's no
            // in-app appearance toggle, so this is the whole policy.
            .preferredColorScheme(.dark)
        }
    }
}

/// The UIKit app delegate, bridging APNs/notification callbacks into PushBridge.
/// It owns no app state — every value it receives is forwarded to the observable
/// side, which does the real work (uploading the token, routing the tap).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Become the notification delegate so we can present pushes in the
        // foreground and handle taps. Set early, before any push can arrive.
        UNUserNotificationCenter.current().delegate = self

        // Prime the V2 Live Activity observers HERE — at launch, not from a view — so they're listening
        // on a cold *background* launch (a push-to-start creates the Activity with the app not running;
        // iOS background-launches us, and only a launch-primed `activityUpdates` observer can capture
        // that Activity's per-update push token to register with the watcher). Independent of sign-in.
        Task { @MainActor in LiveActivityManager.shared.startObserving() }

        return true
    }

    // MARK: - APNs registration

    /// iOS handed us this device's APNs token (after `registerForRemoteNotifications`
    /// succeeds). Format it as the lowercase hex string APNs expects and surface it
    /// for upload to Supabase.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in PushBridge.shared.didRegister(token: hex) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected in the Simulator (no APNs) and offline; non-fatal — Tier 1 local
        // notifications and the whole app keep working without a token.
        print("[AppDelegate] APNs registration failed: \(error)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show goal/live pushes even while the app is in the foreground (otherwise iOS
    /// suppresses them). Banner + sound, no badge.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// A tapped push that carries an `eventID` deep-links into that match. We only
    /// surface the id here; RootTabView reads it and routes (see PushBridge).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let eventID = info["eventID"] as? String {
            await PushBridge.shared.didTapNotification(eventID: eventID)
        }
    }
}
