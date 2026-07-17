//
//  ProfileView.swift
//  NWSLApp
//
//  The account & settings screen, reached from the Home avatar button. Sections:
//  identity, the Fan Zone stat strip, a Settings group, My Teams, and Account.
//
//  Offline-first like the rest of the app: it renders fully signed-out too (an
//  identity sign-in CTA instead of the account block; the stat strip + follows are
//  all local, so they work without an account).
//
//  QOL v2: notification settings no longer live here. Every notif toggle moved to
//  the single NotificationsView hub; Profile just shows one "Notifications" row (with
//  a "{N} teams" / "Off" detail) that pushes it. A "Support NWSLApp" row joins the
//  Settings group in Phase B (StoreKit tips).
//

import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @Environment(FollowingStore.self) private var following
    @Environment(ClubStore.self) private var clubStore
    @Environment(TriviaStore.self) private var trivia
    @Environment(BracketStore.self) private var bracket
    @Environment(PredictionStore.self) private var predict
    @Environment(KnowHerGameStore.self) private var knowHer
    // Per-team alert state — drives the Notifications row's "{N} teams" detail.
    @Environment(TeamAlertStore.self) private var alerts
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(AppRouter.self) private var router

    @State private var signInError: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showDeletedConfirmation = false
    @State private var showNameEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    identity
                    fanZoneStrip
                    settingsSection
                    supportCard
                    myTeamsSection
                    if auth.isSignedIn { accountSection }
                    versionLabel
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.dsBgGrouped)
            // GC auth is triggered ON TAP of the 🏆 Leaderboards cell (see openLeaderboards),
            // NOT on Profile appear — so the Game Center sign-in banner only shows when the
            // user actually asks for leaderboards, never overlaying the Profile screen.
            .sheet(isPresented: $showNameEditor) { DisplayNameEditorSheet(currentName: auth.displayName ?? "") }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // "Profile" as a PRINCIPAL item (not `.navigationTitle`) so it doesn't
                // propagate as the back-button label on pushed children (SupportView) —
                // those get a bare ‹ chevron + their own centered title. Same centered look.
                ToolbarItem(placement: .principal) {
                    Text("Profile").font(.headline).foregroundStyle(Color.dsFgPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { Task { await runDeleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account and all your data — follows, match alerts, and Fan Zone scores — from our servers and this device. This can't be undone.")
            }
            .alert("Couldn't delete account", isPresented: Binding(
                get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
            ) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            // Succeed CLEARLY — the honest counterpart to the error alert. A
            // destructive, irreversible action gets an explicit acknowledgement, not a
            // silently-dismissed sheet; tapping OK closes Profile.
            .alert("Account deleted", isPresented: $showDeletedConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your account and all your data have been permanently deleted.")
            }
            // Honest result for a Leaderboards tap when Game Center isn't signed in — never a
            // silent dead tap (NO SILENT FAILURES). Bound to the GC singleton's @Observable flag.
            .alert("Game Center unavailable", isPresented: Binding(
                get: { GameCenterManager.shared.leaderboardsUnavailable },
                set: { if !$0 { GameCenterManager.shared.leaderboardsUnavailable = false } })
            ) {
                Button("OK", role: .cancel) { GameCenterManager.shared.leaderboardsUnavailable = false }
            } message: {
                Text("Sign in to Game Center in iOS Settings to view the leaderboards.")
            }
        }
        // Show the sheet grabber, matching the Profile handoff's sheet treatment.
        .presentationDragIndicator(.visible)
    }

    // MARK: - Settings (one door into the Notifications hub)

    // Every notification setting lives on ONE screen (NotificationsView). Profile is
    // just a door into it — no inline toggles here (QOL v2). The Support row sits
    // alongside it (QOL v2 §5: optional tips toward servers + data feeds).
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Settings")
            VStack(spacing: 0) {
                // Discoverable display-name editor (replaces the easy-to-miss pencil) — only
                // when signed in, since the name is a leaderboard identity.
                if auth.isSignedIn {
                    Button {
                        showNameEditor = true
                    } label: { displayNameRow }
                        .buttonStyle(.plain)
                    rowDivider
                }
                NavigationLink { NotificationsView() } label: { notificationsRow }
                    .buttonStyle(.plain)
                rowDivider
                // TEMP diagnostics entry — remove with NotifTrace once the token pipeline is proven.
                NavigationLink { NotificationDiagnosticsView() } label: { diagnosticsRow }
                    .buttonStyle(.plain)
            }
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
            Text("Match alerts, alert types, and activity — all in one place.")
                .dsFont(11)
                .foregroundStyle(Color.dsFgQuaternary)
                .padding(.horizontal, 4)
        }
    }

    // The leaderboard display-name row: pencil tile + label + "Shown on leaderboards"
    // subtitle + current value + chevron. Opens the shared DisplayNameEntry sheet.
    private var displayNameRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.dsBgTertiary)
                Image(systemName: "pencil")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
            }
            .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text("Username")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgPrimary)
                Text("Shown on leaderboards")
                    .dsFont(11)
                    .foregroundStyle(Color.dsFgTertiary)
            }
            Spacer(minLength: 8)
            Text(auth.displayName ?? "Set username")
                .dsFont(15)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }


    // Support is its OWN standalone card below the Settings card (not a row inside
    // it — that would mismatch the Notifications row height). ~2× a settings row
    // tall, a slightly larger heart, the subtitle given room, and a faint warm pink
    // wash so it reads as a tasteful CTA — not a loud banner.
    private var supportCard: some View {
        NavigationLink { SupportView() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: "FF375F"), Color(hex: "FF6B8A")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "heart.fill")
                        .dsFont(18)
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support NWSLApp")
                        .dsFont(16, weight: .semibold)
                        .foregroundStyle(Color.dsFgPrimary)
                    Text("Help keep this app free and growing")
                        .dsFont(13)
                        .foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsFgTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    Color.dsBgCard
                    LinearGradient(colors: [Color(hex: "FF375F").opacity(0.10), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var notificationsRow: some View {
        HStack(spacing: 12) {
            // Blue rounded-square bell, iOS-Settings-icon style.
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.dsAccent)
                Image(systemName: "bell.fill")
                    .dsFont(15)
                    .foregroundStyle(.white)
            }
            .frame(width: 29, height: 29)
            Text("Notifications")
                .dsFont(15)
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            Text(alerts.enabledCount == 0 ? "Off"
                 : "\(alerts.enabledCount) team\(alerts.enabledCount == 1 ? "" : "s")")
                .dsFont(15)
                .foregroundStyle(Color.dsFgSecondary)
            Image(systemName: "chevron.right")
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Identity

    @ViewBuilder
    private var identity: some View {
        if auth.isSignedIn {
            VStack(spacing: 10) {
                avatarCircle(initials)
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        // Three distinct states, NEVER "Member": show the name when we have one
                        // (cached or fetched); "Setting up…" while a returning user's name is
                        // still loading from the server (avoids a "Fan" → real-name flicker on
                        // the reinstall path); "Fan" only once hydrated with genuinely no name
                        // yet (brand-new user — the pencil + the Fan Zone gate lead them to set one).
                        Group {
                            if let name = auth.displayName {
                                Text(name).foregroundStyle(Color.dsFgPrimary)
                            } else if !auth.profileHydrated {
                                Text("Setting up…").foregroundStyle(Color.dsFgSecondary)
                            } else {
                                Text("Fan").foregroundStyle(Color.dsFgPrimary)
                            }
                        }
                        .dsFont(20, weight: .bold)
                        // Edit how the name appears on the leaderboards.
                        Button {
                            showNameEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .dsFont(13, weight: .semibold)
                                .foregroundStyle(Color.dsAccent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit username")
                    }
                    Text("Signed in with Apple")
                        .dsFont(12)
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
        } else {
            signedOutIdentity
        }
    }

    private var signedOutIdentity: some View {
        VStack(spacing: 12) {
            avatarCircle("?")
            Text("Not signed in")
                .dsFont(20, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            Text("Sign in to save your Fan Zone points and sync your follows across devices. The app works the same either way.")
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            SignInWithAppleButton(.signIn) { request in
                auth.configureSignInRequest(request)
            } onCompletion: { result in
                Task { await completeSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(Color.dsError)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func avatarCircle(_ text: String) -> some View {
        ZStack {
            Circle().fill(Color.dsBgTertiary)
            Text(text)
                .dsFont(24, weight: .bold)
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(width: DS.avatarProfile, height: DS.avatarProfile)
        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 2))
    }

    /// Up to two initials from the cached display name.
    private var initials: String {
        guard let name = auth.displayName else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    // MARK: - Fan Zone stat strip

    private var fanZoneStrip: some View {
        HStack(spacing: 0) {
            statCell("\(totalPoints)", "Points")
            statDivider
            // The middle cell opens the native Game Center dashboard (real cross-player ranks
            // live there). `openLeaderboards` triggers GC auth on this tap if needed, then
            // shows the dashboard once resolved — or an honest message if GC isn't available.
            Button { GameCenterManager.shared.openLeaderboards() } label: {
                statCell("🏆", "Leaderboards")
            }
            .buttonStyle(.plain)
            statDivider
            statCell("🔥 \(trivia.streak)", "Streak")
        }
        .padding(.vertical, 14)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .dsFont(17, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            Text(label)
                .dsFont(11)
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.dsSeparator).frame(width: 1, height: 28)
    }

    /// Points across the point-scoring games (the middle cell now opens the native
    /// Game Center dashboard for real cross-player ranks).
    private var totalPoints: Int { predict.seasonPoints + bracket.points }

    // MARK: - My Teams

    private var myTeamsSection: some View {
        let followed = clubStore.clubs.filter { following.isFollowing($0) }
        return settingsGroup("My Teams") {
            ForEach(followed) { club in
                HStack(spacing: 12) {
                    TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: DS.avatarMd)
                    Text(club.displayName)
                        .dsFont(15)
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer(minLength: 8)
                    Image(systemName: "star.fill")
                        .dsFont(16)
                        .foregroundStyle(Color.dsFollowStar)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                rowDivider
            }
            Button {
                router.selectedTab = .teams
                dismiss()
            } label: {
                HStack {
                    Text("Manage follows")
                        .dsFont(15)
                        .foregroundStyle(Color.dsAccent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .dsFont(13, weight: .semibold)
                        .foregroundStyle(Color.dsFgTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Account

    /// Permanently delete the account. The server-side delete (auth user + all rows)
    /// runs first via `auth.deleteAccount()`; ONLY on its success do we wipe the rest of
    /// the on-device state, so a failed delete leaves everything intact and surfaces an
    /// error instead of silently "succeeding." Each local store is reset through its
    /// real setter so the @Observable UI updates immediately.
    private func runDeleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteAccount()
            following.replace(ids: [])
            following.replaceCompetitionFollowKeys([])
            alerts.replaceEnabled([])
            // Tier-2 prefs teardown moved HERE from the coordinator's sign-out transition
            // (involuntary-sign-out fix): a plain sign-out now PRESERVES stored toggles
            // (display-gated), but a deleted account starts truly fresh — no stale alert
            // intent to resurrect onto a future new account.
            notifications.resetServerPushTypes()
            trivia.resetForAccountDeletion()
            bracket.resetForAccountDeletion()
            predict.resetForAccountDeletion()
            knowHer.resetForAccountDeletion()
            showDeletedConfirmation = true   // explicit success ack; its OK dismisses
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Account")
            VStack(spacing: 0) {
                Button { Task { await auth.signOut() } } label: {
                    accountRow("Sign out")
                }
                .buttonStyle(.plain)
                rowDivider
                Button { showDeleteConfirm = true } label: {
                    HStack {
                        accountRow("Delete account")
                        if isDeleting { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
            Text("Signing out keeps your follows on this device. Your Fan Zone points and rank stay with your account.")
                .dsFont(11)
                .foregroundStyle(Color.dsFgQuaternary)
                .padding(.horizontal, 4)
        }
    }

    private func accountRow(_ title: String) -> some View {
        Text(title)
            .dsFont(15)
            .foregroundStyle(Color.dsError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
    }

    // MARK: - Shared building blocks

    @ViewBuilder
    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            VStack(spacing: 0) { content() }
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .trackedCaps()
            .padding(.horizontal, 4)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.dsSeparator)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    // TEMP diagnostics entry (remove with NotifTrace once the token pipeline is proven).
    private var diagnosticsRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.dsBgTertiary)
                Image(systemName: "stethoscope").dsFont(15).foregroundStyle(Color.dsFgSecondary)
            }
            .frame(width: 29, height: 29)
            VStack(alignment: .leading, spacing: 1) {
                Text("Notification Diagnostics").dsFont(15).foregroundStyle(Color.dsFgPrimary)
                Text("Token registration state").dsFont(11).foregroundStyle(Color.dsFgTertiary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var versionLabel: some View {
        Text("NWSLApp \(appVersion)")
            .dsFont(11)
            .foregroundStyle(Color.dsFgQuaternary)
            .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3"
    }

    private func completeSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            try await auth.handleSignIn(result)
        } catch {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            signInError = "Sign in didn't complete. You can try again later."
        }
    }
}
