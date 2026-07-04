//
//  MatchAlertPresenter.swift
//  NWSLApp
//
//  The shared "turn on match alerts for a team" flow, used by every bell (Teams grid,
//  Competitions national-team cards, the Notifications hub rows) so all three behave
//  identically (plan §Phase 1):
//
//   • Tapping a bell ON is an EXPLICIT opt-in → cascade the full default alert bundle the
//     FIRST time (NotificationPreferencesStore.applyMatchAlertDefaultsIfFirstTime), so the
//     feature works out of the box instead of leaving a team "armed" with every alert type
//     off (the silent-failure paradox).
//   • The live match types are Tier-2 (server push, need an account), so a SIGNED-OUT bell tap
//     presents Sign in with Apple FIRST and does NOT flip the bell — on success it enables +
//     cascades + toasts; on cancel nothing happens. This is Gemini's "intercept pattern": the
//     account cost is asked at the moment of peak intent, and the tap is honored only once paid.
//   • A confirmation toast breadcrumbs to the hub ("Customize alerts").
//
//  Owned per-screen as `@State` (each screen presents its own sheet + toast, so pushed screens
//  don't fight over one shared sheet). The actual alert state lives in the shared TeamAlertStore /
//  NotificationPreferencesStore — this only owns the transient presentation + the intercept.
//

import SwiftUI
import UIKit
import UserNotifications

@MainActor
@Observable
final class MatchAlertPresenter {
    /// A transient confirmation toast; `on` picks the copy/icon.
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let on: Bool
    }

    var toast: Toast?
    var showAuthPrompt = false
    /// The activation deferred behind the sign-in sheet (nil unless a signed-out ON is pending).
    private var pending: (() -> Void)?

    /// The one entry point every bell calls. OFF is immediate. ON while signed-in enables + cascades
    /// + toasts. ON while signed-out defers the whole thing behind the Apple sheet (bell stays off
    /// until sign-in succeeds).
    func requestToggle(key: String, turnOn: Bool, isSignedIn: Bool,
                       alerts: TeamAlertStore, prefs: NotificationPreferencesStore) {
        guard turnOn else {
            performActivate(key: key, enabled: false, alerts: alerts, prefs: prefs)
            return
        }
        if isSignedIn {
            performActivate(key: key, enabled: true, alerts: alerts, prefs: prefs)
        } else {
            pending = { [weak self] in
                self?.performActivate(key: key, enabled: true, alerts: alerts, prefs: prefs)
            }
            showAuthPrompt = true
        }
    }

    /// Run the deferred activation after a successful sign-in (from the sheet's onSignedIn).
    func onSignedIn() {
        pending?()
        pending = nil
    }

    /// Drop a deferred activation when the sheet is dismissed without signing in (the bell stays off).
    func cancelPending() { pending = nil }

    private func performActivate(key: String, enabled: Bool,
                                 alerts: TeamAlertStore, prefs: NotificationPreferencesStore) {
        alerts.setAlertsEnabled(enabled, for: key)
        if enabled {
            prefs.applyMatchAlertDefaultsIfFirstTime()   // cascade the full bundle once (explicit opt-in)
            Task { await Self.requestNotificationPermission() }
        }
        toast = Toast(on: enabled)
    }

    /// Ask iOS for notification permission on the opt-in gesture (never at launch), then register for
    /// remote notifications if granted. Shared so the bell path and the hub toggles behave the same.
    static func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let status = await center.notificationSettings().authorizationStatus
        NotifTrace.shared.log("bell-permission", status == .authorized ? .ok : .fail, status.traceLabel)
        if status == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
            NotifTrace.shared.log("register-called", .ok, "from bell toggle")
        }
    }
}
