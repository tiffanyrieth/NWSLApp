//
//  NotificationDiagnosticsView.swift
//  NWSLApp
//
//  DISPOSABLE DEBUG SCAFFOLDING (remove with NotifTrace once the token pipeline is proven — see
//  supabase/migration_notification_diagnostics.sql). A TestFlight-visible, self-serve view of the
//  notification TOKEN-REGISTRATION state, so a tester (or the owner's brother) can look and say "it
//  says push-to-start = NOT REGISTERED" and screenshot it — no SQL needed. Also shows this device's
//  `device_id`, which keys the `notification_diagnostics` Supabase table for post-game queries.
//

import SwiftUI
import UserNotifications

#if DEBUG
struct NotificationDiagnosticsView: View {
    @Environment(AuthStore.self) private var auth
    @State private var trace = NotifTrace.shared
    @State private var bridge = PushBridge.shared
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private var laEnabled: Bool { LiveActivityManager.areActivitiesEnabled }
    private var startTokenPrefix: String? { LiveActivityManager.shared.startTokenPrefix }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stateCard
                crumbsCard
                Text("Debug tool — remove before App Store. device_id keys the notification_diagnostics table.")
                    .font(.system(size: 10)).foregroundStyle(Color.dsFgTertiary)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 14)
        }
        .background(Color.dsBgGrouped)
        .navigationTitle("Notification Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    private var stateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Signed in", auth.userID != nil ? "yes" : "NO", ok: auth.userID != nil)
            row("iOS permission", authStatus.traceLabel, ok: authStatus == .authorized)
            row("Live Activities (Settings)", laEnabled ? "on" : "OFF", ok: laEnabled)
            row("V1 device token", bridge.deviceToken != nil ? "registered" : "NOT registered",
                ok: bridge.deviceToken != nil)
            row("V2 push-to-start token", startTokenPrefix != nil ? "seen (\(startTokenPrefix!)…)" : "NOT seen",
                ok: startTokenPrefix != nil)
            Divider().overlay(Color.dsSeparator)
            row("device_id", DeviceIdentity.deviceID, ok: nil, mono: true)
        }
        .padding(16)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func row(_ label: String, _ value: String, ok: Bool?, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.dsFgSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: mono ? 10 : 13, weight: .semibold, design: mono ? .monospaced : .default))
                .foregroundStyle(ok == nil ? Color.dsFgPrimary : (ok! ? Color.green : Color.red))
                .multilineTextAlignment(.trailing)
        }
    }

    private var crumbsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent steps (\(trace.recent.count))")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.dsFgPrimary)
            if trace.recent.isEmpty {
                Text("No steps recorded yet.").font(.system(size: 11)).foregroundStyle(Color.dsFgSecondary)
            } else {
                ForEach(trace.recent) { c in
                    HStack(alignment: .top, spacing: 6) {
                        Text(c.status.uppercased())
                            .font(.system(size: 9, weight: .heavy).monospaced())
                            .foregroundStyle(c.status == "ok" ? Color.green : c.status == "fail" ? Color.red : Color.orange)
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.step).font(.system(size: 11, weight: .semibold).monospaced())
                                .foregroundStyle(Color.dsFgPrimary)
                            if !c.detail.isEmpty {
                                Text(c.detail).font(.system(size: 10).monospaced())
                                    .foregroundStyle(Color.dsFgSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}
#endif
