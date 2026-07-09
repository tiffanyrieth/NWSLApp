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
//  rounds is deferred (persists intent only). Subs aren't shown — no backing; lineup-posted
//  IS shown now (the watcher polls /summary pre-kickoff, Stage D).
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
    // The Tier-2 toggle(s) awaiting sign-in — flipped on by the gate's onSignedIn. An array so a
    // GROUPED row (e.g. "Match updates" = kickoff+halftime+full time) can defer all of its columns.
    @State private var pendingTier2: [ReferenceWritableKeyPath<NotificationPreferencesStore, Bool>] = []
    // A team whose alerts are awaiting sign-in (the bundle cascade includes Tier-2, so turning a
    // team on while signed-out is gated too) — enabled + cascaded by the gate's onSignedIn.
    @State private var pendingTeamKey: String?

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
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAuthPrompt) {
            NotificationAuthPromptView(onSignedIn: {
                if !pendingTier2.isEmpty {
                    for kp in pendingTier2 { notifications[keyPath: kp] = true }
                    Task { await requestNotificationPermission() }
                }
                if let key = pendingTeamKey {
                    teamAlerts.setAlertsEnabled(true, for: key)
                    notifications.applyMatchAlertDefaultsIfFirstTime()   // cascade the bundle (first time)
                    Task { await requestNotificationPermission() }
                }
                pendingTier2 = []
                pendingTeamKey = nil
            })
        }
    }

    // MARK: - Section 1: Match alerts (per-team ON/OFF)

    private var matchAlertsSection: some View {
        // Clubs AND followed national teams share this one list (both buzz you on match day, both
        // respect the global Alert-types below). National teams are keyed by FIFA code.
        let clubs = clubStore.clubs.filter { following.isFollowing($0) }
        let ntCodes = following.followedNationalTeams.sorted()
        let hasAny = !clubs.isEmpty || !ntCodes.isEmpty
        return SettingsGroup(
            title: "Match alerts — your teams",
            subtitle: "Which teams buzz your phone on match day"
            // No "basic alerts are free / live updates require an account" note: the app
            // is always free, and the sign-in gate explains Tier-2 contextually when a
            // push toggle is tapped. The pre-emptive line read as a paywall (Part B Bug 8).
        ) {
            if !hasAny {
                Text("Follow teams to turn on match alerts.")
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            } else {
                ForEach(Array(clubs.enumerated()), id: \.element.id) { index, club in
                    if index > 0 { SettingsRowDivider() }
                    teamAlertRow(club)
                }
                ForEach(Array(ntCodes.enumerated()), id: \.element) { index, code in
                    if index > 0 || !clubs.isEmpty { SettingsRowDivider() }
                    nationalTeamAlertRow(code)
                }
            }
        }
    }

    // A followed national team's alert row — flag + name + the SAME intent-driven-cascade toggle as
    // a club (keyed by FIFA code). A code not in the bundled directory falls back to a globe + code.
    private func nationalTeamAlertRow(_ code: String) -> some View {
        let team = NationalTeam.team(code: code)
        return HStack(spacing: 12) {
            Group {
                if let flag = UIImage(named: "Flags/\(code.uppercased())") {
                    Image(uiImage: flag).resizable().scaledToFit()
                } else {
                    Image(systemName: "globe").foregroundStyle(Color.dsFgSecondary)
                }
            }
            .frame(width: DS.avatarMd, height: DS.avatarMd * 0.68)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(team?.name ?? code)
                .dsFont(15)
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { teamAlerts.alertsEnabled(for: code) },
                set: { newValue in
                    guard newValue else { teamAlerts.setAlertsEnabled(false, for: code); return }
                    if auth.isSignedIn {
                        teamAlerts.setAlertsEnabled(true, for: code)
                        notifications.applyMatchAlertDefaultsIfFirstTime()
                        Task { await requestNotificationPermission() }
                    } else {
                        pendingTeamKey = code
                        showAuthPrompt = true
                    }
                }
            ))
            .labelsHidden()
            .tint(Color.dsSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func teamAlertRow(_ club: Club) -> some View {
        HStack(spacing: 12) {
            TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: DS.avatarMd)
            Text(club.displayName)
                .dsFont(15)
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { teamAlerts.alertsEnabled(for: club.id) },
                set: { newValue in
                    guard newValue else { teamAlerts.setAlertsEnabled(false, for: club.id); return }
                    // Turning a team ON now cascades the full alert bundle the first time (intent-driven
                    // defaults). The bundle includes Tier-2, so a signed-out turn-on is gated: present the
                    // sign-in sheet and defer enable+cascade until it succeeds.
                    if auth.isSignedIn {
                        teamAlerts.setAlertsEnabled(true, for: club.id)
                        notifications.applyMatchAlertDefaultsIfFirstTime()
                        Task { await requestNotificationPermission() }
                    } else {
                        pendingTeamKey = club.id
                        showAuthPrompt = true
                    }
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
            // Regrouped (MLS-informed): the low-drama score updates collapse into ONE "Match updates"
            // toggle (kickoff/halftime/full time), while Goals + Lineups stay their own rows. Day-before
            // is Tier 1 (local, no account). The rest are Tier 2 (server push): the account requirement is
            // revealed on TAP (tier2Binding presents the sign-in sheet), not shown upfront.
            SettingsToggleRow(title: "Match updates", subtitle: "Kickoff, halftime & full time",
                              isOn: tier2GroupBinding([\.kickoff, \.halftime, \.fullTime]))
            SettingsRowDivider()
            SettingsToggleRow(title: "Goals", subtitle: "When any team scores",
                              isOn: tier2Binding(\.goals))
            SettingsRowDivider()
            SettingsToggleRow(title: "Lineups posted", subtitle: "Starting XI, ~1 hour before kickoff",
                              isOn: tier2Binding(\.lineupPosted))
            SettingsRowDivider()
            SettingsToggleRow(title: "Day-before reminder", subtitle: "24 hours before kickoff",
                              isOn: tier1Binding(\.dayBefore))
            SettingsRowDivider()
            // Live Activity (V2) — the silent live-score card. Tier-2 (the watcher push-to-starts it →
            // needs an account), so it's a sign-in-gated opt-in like the alerts above; it just doesn't buzz.
            // Title keeps Apple's term ("Live Activity", matches iOS Settings) + names WHERE it appears.
            // GRACEFUL DEGRADATION: the in-match update rail is APNs Broadcast Channels (iOS 18+), so on
            // iOS 17.x the row is disabled with an honest "Requires iOS 18" note (never a silent no-op).
            // All other alerts on this screen reach iOS 17.x in full.
            if #available(iOS 18.0, *) {
                SettingsToggleRow(title: "Live Activity on Lock Screen",
                                  subtitle: "Live score on your Lock Screen & Dynamic Island",
                                  isOn: tier2Binding(\.liveActivitiesEnabled))
            } else {
                SettingsToggleRow(title: "Live Activity on Lock Screen",
                                  subtitle: "Live score on your Lock Screen & Dynamic Island",
                                  note: "Requires iOS 18",
                                  isOn: .constant(false))
                    .disabled(true)
                    .opacity(0.55)
            }
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
            SettingsToggleRow(title: "Know Her Game", subtitle: "When a new weekly player quiz is ready",
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
                    pendingTier2 = [kp]
                    showAuthPrompt = true
                }
            }
        )
    }

    /// Tier-2 binding for a GROUPED row that toggles several columns as one (e.g. "Match updates" =
    /// kickoff + halftime + full time). Reads ON if ANY column is on; toggling normalizes all of them.
    /// This is a UI grouping only — each column still gates its own event server-side (fully reversible).
    private func tier2GroupBinding(_ kps: [ReferenceWritableKeyPath<NotificationPreferencesStore, Bool>]) -> Binding<Bool> {
        Binding(
            get: { kps.contains { notifications[keyPath: $0] } },
            set: { newValue in
                guard newValue else { for kp in kps { notifications[keyPath: kp] = false }; return }
                if auth.isSignedIn {
                    for kp in kps { notifications[keyPath: kp] = true }
                    Task { await requestNotificationPermission() }
                } else {
                    pendingTier2 = kps
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
