//
//  ProfileView.swift
//  NWSLApp
//
//  The account & settings screen, reached from the Home avatar button (design
//  handoff `ProfileScreen.jsx`). Sections: identity, the Fan Zone stat strip,
//  Match Day + Activity notification toggles, My Teams, and Account.
//
//  Offline-first like the rest of the app: it renders fully signed-out too (an
//  identity sign-in CTA instead of the account block; the stat strip + follows +
//  toggles are all local, so they work without an account). Notification toggles
//  persist intent only — actual delivery (APNs / local scheduling) is 0.3 backend
//  work (#12); see NotificationPreferencesStore.
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
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(AppRouter.self) private var router

    @State private var signInError: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    identity
                    fanZoneStrip
                    matchDaySection
                    activitySection
                    myTeamsSection
                    if auth.isSignedIn { accountSection }
                    versionLabel
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.dsBgGrouped)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { Task { await auth.deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This signs you out on this device. Your Fan Zone points and follows are kept locally.")
            }
        }
    }

    // MARK: - Identity

    @ViewBuilder
    private var identity: some View {
        if auth.isSignedIn {
            VStack(spacing: 10) {
                avatarCircle(initials)
                VStack(spacing: 2) {
                    Text(auth.displayName ?? "Member")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.dsFgPrimary)
                    Text("Signed in with Apple")
                        .font(.system(size: 12))
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            Text("Sign in to save your Fan Zone points and sync your follows across devices. The app works the same either way.")
                .font(.system(size: 13))
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
                .font(.system(size: 24, weight: .bold))
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
            statCell(rankText, "Rank")
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
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.dsSeparator).frame(width: 1, height: 28)
    }

    /// Points across the point-scoring games. Rank needs a real leaderboard
    /// backend (#12), so it shows "—" until then.
    private var totalPoints: Int { predict.seasonPoints + bracket.points }
    private var rankText: String { "—" }

    // MARK: - Notification sections

    private var matchDaySection: some View {
        @Bindable var notif = notifications
        return settingsGroup("Match Day") {
            toggleRow("Day-before reminder", "24 hours before your teams play", $notif.dayBefore)
            rowDivider
            toggleRow("Lineup posted", "When the starting XI is announced", $notif.lineupPosted)
            rowDivider
            toggleRow("Kickoff", "When the match starts", $notif.kickoff)
            rowDivider
            toggleRow("Goals", "When any team scores", $notif.goals)
            rowDivider
            toggleRow("Halftime", "Halftime score update", $notif.halftime)
            rowDivider
            toggleRow("Full time", "Final score when the match ends", $notif.fullTime)
            rowDivider
            toggleRow("Substitutions", "When subs are made during the match", $notif.substitutions)
        }
    }

    private var activitySection: some View {
        @Bindable var notif = notifications
        return settingsGroup("Activity") {
            toggleRow("Fan Zone rounds", "When a new bracket round or trivia opens", $notif.fanZoneRounds)
            rowDivider
            toggleRow("Player Spotlight", "When a new weekly spotlight is posted", $notif.playerSpotlight)
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsFgPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.dsSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - My Teams

    private var myTeamsSection: some View {
        let followed = clubStore.clubs.filter { following.isFollowing($0) }
        return settingsGroup("My Teams") {
            ForEach(followed) { club in
                HStack(spacing: 12) {
                    TeamLogo(urlString: club.logoURL, size: DS.avatarMd)
                    Text(club.displayName)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer(minLength: 8)
                    Image(systemName: "star.fill")
                        .font(.system(size: 16))
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
                        .font(.system(size: 15))
                        .foregroundStyle(Color.dsAccent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
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
                    accountRow("Delete account")
                }
                .buttonStyle(.plain)
            }
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
            Text("Signing out keeps your follows on this device. Your Fan Zone points and rank stay with your account.")
                .font(.system(size: 11))
                .foregroundStyle(Color.dsFgQuaternary)
                .padding(.horizontal, 4)
        }
    }

    private func accountRow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
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
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
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

    private var versionLabel: some View {
        Text("NWSLApp \(appVersion)")
            .font(.system(size: 11))
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
