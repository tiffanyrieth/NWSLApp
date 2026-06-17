//
//  NotificationsView.swift
//  NWSLApp
//
//  The ONE notification home (QOL v2). Every notification setting lives here — no
//  fragmentation, no buried sheets. Reachable from three doors that all push this
//  same view: the Teams nav-bar 🔔, the Teams "Manage" link, and the Profile
//  "Notifications" row.
//
//  Three sections:
//   1. Match alerts — your teams: a per-team ON/OFF toggle (WHICH teams buzz you).
//   2. Alert types: the global WHAT (day-before, kickoff, goals, halftime, full time),
//      applied to every team with alerts on. Dimmed + inert when no team is on.
//   3. Activity: league-wide, team-independent (Fan Zone rounds, Player Spotlight).
//
//  Tiering: day-before + Player Spotlight are Tier 1 (local) — they flip silently and
//  request iOS permission on first-on. Kickoff/goals/halftime/full-time are Tier 2
//  (server push) — turning one on while signed out presents the honest sign-in gate
//  (NotificationAuthPromptView) and does NOT flip until sign-in succeeds. Fan Zone
//  rounds is deferred (persists intent only). Lineup/subs aren't shown — no backing.
//

import SwiftUI
import UIKit
import UserNotifications

struct NotificationsView: View {
    @Environment(ClubStore.self) private var clubStore
    @Environment(FollowingStore.self) private var following
    @Environment(TeamAlertStore.self) private var teamAlerts
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(AuthStore.self) private var auth

    @State private var showAuthPrompt = false
    // The Tier-2 toggle awaiting sign-in — flipped on by the gate's onSignedIn.
    @State private var pendingTier2: ReferenceWritableKeyPath<NotificationPreferencesStore, Bool>?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                matchAlertsSection
                alertTypesSection
                activitySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.dsBgGrouped)
        // On the first visit, establishes the auth-aware Tier-2 defaults (ON only if
        // signed in — upholds `Tier 2 ON ⟹ signed in`).
        .onAppear { notifications.markHubVisited(isSignedIn: auth.isSignedIn) }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAuthPrompt) {
            NotificationAuthPromptView(onSignedIn: {
                if let kp = pendingTier2 {
                    notifications[keyPath: kp] = true
                    Task { await requestNotificationPermission() }
                }
                pendingTier2 = nil
            })
        }
    }

    // MARK: - Section 1: Match alerts (per-team ON/OFF)

    private var matchAlertsSection: some View {
        let followed = clubStore.clubs.filter { following.isFollowing($0) }
        return SettingsGroup(
            title: "Match alerts — your teams",
            subtitle: "Which teams buzz your phone on match day",
            note: "Basic alerts are free. Live match updates require an account."
        ) {
            if followed.isEmpty {
                Text("Follow teams to turn on match alerts.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            } else {
                ForEach(Array(followed.enumerated()), id: \.element.id) { index, club in
                    if index > 0 { SettingsRowDivider() }
                    teamAlertRow(club)
                }
            }
        }
    }

    private func teamAlertRow(_ club: Club) -> some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: DS.avatarMd)
            Text(club.displayName)
                .font(.system(size: 15))
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { teamAlerts.alertsEnabled(for: club.id) },
                set: { newValue in
                    teamAlerts.setAlertsEnabled(newValue, for: club.id)
                    // A team's day-before is delivered locally, so a bare on still
                    // needs permission. Per-team is gate-free (no sign-in needed).
                    if newValue { Task { await requestNotificationPermission() } }
                }
            ))
            .labelsHidden()
            .tint(Color.dsSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Section 2: Alert types (global; dimmed when no team is on)

    private var alertTypesSection: some View {
        let anyTeamOn = teamAlerts.enabledCount > 0
        return SettingsGroup(
            title: "Alert types",
            subtitle: "What you'll be notified about, for the teams above"
        ) {
            // Day-before is Tier 1 (local, no account needed). Kickoff/Goals/
            // Halftime/Full time are Tier 2 (server push): the account requirement is
            // revealed on TAP (the tier2Binding presents the sign-in sheet), not shown
            // upfront — keeps the rows clean.
            SettingsToggleRow(title: "Day-before reminder", subtitle: "24 hours before kickoff",
                              isOn: tier1Binding(\.dayBefore))
            SettingsRowDivider()
            SettingsToggleRow(title: "Kickoff", subtitle: "When the match starts",
                              isOn: tier2Binding(\.kickoff))
            SettingsRowDivider()
            SettingsToggleRow(title: "Goals", subtitle: "When any team scores",
                              isOn: tier2Binding(\.goals))
            SettingsRowDivider()
            SettingsToggleRow(title: "Halftime", subtitle: "Halftime score update",
                              isOn: tier2Binding(\.halftime))
            SettingsRowDivider()
            SettingsToggleRow(title: "Full time", subtitle: "Final score when the match ends",
                              isOn: tier2Binding(\.fullTime))
        }
        // Inert + greyed until at least one team has alerts on (these types have
        // nothing to apply to otherwise). Un-dims reactively when §1 turns one on.
        .opacity(anyTeamOn ? 1 : 0.45)
        .allowsHitTesting(anyTeamOn)
    }

    // MARK: - Section 3: Activity (global, team-independent)

    private var activitySection: some View {
        SettingsGroup(title: "Activity", subtitle: "Not tied to a team") {
            // Deferred (real game backends): persists intent, no permission/gate.
            SettingsToggleRow(title: "Fan Zone rounds", subtitle: "When a new bracket round or trivia opens",
                              isOn: deferredBinding(\.fanZoneRounds))
            SettingsRowDivider()
            SettingsToggleRow(title: "Player Spotlight", subtitle: "When a new weekly spotlight is posted",
                              isOn: tier1Binding(\.playerSpotlight))
        }
    }

    // MARK: - Tier-aware bindings

    /// Tier 1 (local): flips silently, requests permission on first-on.
    private func tier1Binding(_ kp: ReferenceWritableKeyPath<NotificationPreferencesStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { notifications[keyPath: kp] },
            set: { newValue in
                notifications[keyPath: kp] = newValue
                if newValue { Task { await requestNotificationPermission() } }
            }
        )
    }

    /// Tier 2 (server push): turning ON while signed out presents the honest sign-in
    /// gate and does NOT flip the store — the toggle snaps back off until sign-in.
    private func tier2Binding(_ kp: ReferenceWritableKeyPath<NotificationPreferencesStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { notifications[keyPath: kp] },
            set: { newValue in
                guard newValue else { notifications[keyPath: kp] = false; return }
                if auth.isSignedIn {
                    notifications[keyPath: kp] = true
                    Task { await requestNotificationPermission() }
                } else {
                    pendingTier2 = kp
                    showAuthPrompt = true
                }
            }
        )
    }

    /// Deferred: persists intent only — no permission request, no sign-in gate.
    private func deferredBinding(_ kp: ReferenceWritableKeyPath<NotificationPreferencesStore, Bool>) -> Binding<Bool> {
        Binding(get: { notifications[keyPath: kp] }, set: { notifications[keyPath: kp] = $0 })
    }

    // MARK: - Permission (requested on the toggle gesture, never at launch)

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        if await center.notificationSettings().authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
