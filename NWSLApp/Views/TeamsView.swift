//
//  TeamsView.swift
//  NWSLApp
//
//  The Teams tab: a directory of all NWSL clubs, each with a Follow toggle.
//  Following is the app's personalization lens (see FollowingStore) — so a
//  "Following" section floats followed clubs to the top, making the lens
//  visible the moment you tap a star. The full roster always shows below,
//  end-to-end (UI rule: no truncation).
//
//  The FollowingStore arrives via the SwiftUI environment (injected once in
//  RootTabView), not constructed here — so this screen and future ones share
//  the same single source of truth for who you follow.
//
//  Each row is a NavigationLink into TeamDetailView (crest, club schedule,
//  roster, Follow). The destination reads the shared MatchStore + FollowingStore
//  from the environment, both injected in RootTabView.
//

import SwiftUI
import UIKit
import UserNotifications

struct TeamsView: View {
    @State private var viewModel = TeamsViewModel()
    @State private var path = NavigationPath()
    @Environment(FollowingStore.self) private var following
    // The shared club directory (injected in RootTabView); the view model reads
    // its state/clubs through this.
    @Environment(ClubStore.self) private var clubStore
    // Per-team match-alert on/off — drives the row bells + the "{N} teams" line.
    @Environment(TeamAlertStore.self) private var teamAlerts

    // The one extra route on this stack (besides Club → TeamDetailView): the
    // notifications hub, pushed from the nav-bar bell + the "Manage" line.
    private enum NotificationsRoute: Hashable { case hub }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Teams")
                .navigationDestination(for: Club.self) { club in
                    TeamDetailView(club: club)
                }
                .navigationDestination(for: NotificationsRoute.self) { _ in
                    NotificationsView()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { path.append(NotificationsRoute.hub) } label: {
                            Image(systemName: "bell")
                                .foregroundStyle(Color.dsAccent)
                        }
                        .accessibilityLabel("Notifications")
                    }
                }
                // No pull-to-refresh: the club directory is static; nothing to refetch.
        }
        // Load once on first appearance; don't refetch every time the tab is
        // re-selected (pull-to-refresh covers manual reloads).
        .task {
            viewModel.clubStore = clubStore
            if case .idle = clubStore.state { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading teams…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message)
        case .loaded:
            directory
        }
    }

    private var directory: some View {
        // One continuous list (no "Following" / "All Clubs" headers): followed teams
        // float to the top (tint + star + bell), unfollowed below — each club once.
        // The blue tint + star + bell already mark the followed set, so the divider
        // headers were clutter. The "{N} teams · Manage" line sits at the boundary.
        let followed = viewModel.clubs.filter { following.isFollowing($0) }
        let unfollowed = viewModel.clubs.filter { !following.isFollowing($0) }
        return List {
            Section {
                ForEach(followed) { row(for: $0) }
                if teamAlerts.enabledCount > 0 { matchAlertsLine }
                ForEach(unfollowed) { row(for: $0) }
            } header: {
                // The subtitle (sentence case, never truncated) — same role as Home's
                // "From your teams". `textCase(nil)` stops the default header uppercasing.
                Text("Tap any club to explore their squad and stats")
                    .font(.subheadline)
                    .foregroundStyle(Color.dsFgSecondary)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
            }

            // A way back into international competitions for anyone who skipped
            // them during onboarding (the only other place they're offered).
            Section {
                NavigationLink {
                    CompetitionsView()
                } label: {
                    Label("Follow competitions", systemImage: "globe")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for club: Club) -> some View {
        // Navigation and the Follow star are SIBLING buttons, not nested: a
        // `Button` inside a `NavigationLink` swallows the row's navigation tap
        // (the star toggles, the rest of the row goes dead). So the row body is
        // its own button that pushes the club via the navigation path, and the
        // star is a separate button beside it — each owns its own taps.
        let isFollowing = following.isFollowing(club)
        return HStack(spacing: 12) {
            Button {
                path.append(club)
            } label: {
                HStack(spacing: 12) {
                    TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 32)
                    // Full name — the directory is the one place full names show.
                    Text(club.displayName)
                        .foregroundStyle(isFollowing ? Color.dsAccent : Color.dsFgPrimary)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())   // whole left area is tappable
            }
            .buttonStyle(.plain)

            // A quick match-alert on/off for followed teams (same state as the
            // Notifications hub). Only followed teams can have alerts.
            if isFollowing { bellButton(for: club) }
            followButton(for: club)
        }
        // Followed rows get a soft blue tint so the Following lens is visible.
        .listRowBackground(isFollowing ? Color.dsFollowTint : nil)
    }

    private func bellButton(for club: Club) -> some View {
        let on = teamAlerts.alertsEnabled(for: club.id)
        return Button {
            teamAlerts.toggle(for: club.id)
            // Turning a team on may need notification permission (its day-before is
            // delivered locally). Gate-free — no sign-in needed for the on/off itself.
            if !on { Task { await requestNotificationPermission() } }
        } label: {
            Image(systemName: on ? "bell.fill" : "bell")
                .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(on ? "Turn off match alerts for \(club.displayName)"
                               : "Turn on match alerts for \(club.displayName)")
    }

    // The "{N} team(s) with match alerts · Manage" line under Following → the hub.
    private var matchAlertsLine: some View {
        let n = teamAlerts.enabledCount
        return Button { path.append(NotificationsRoute.hub) } label: {
            HStack(spacing: 4) {
                Text("\(n) team\(n == 1 ? "" : "s") with match alerts ·")
                    .foregroundStyle(Color.dsFgSecondary)
                Text("Manage")
                    .foregroundStyle(Color.dsAccent)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func followButton(for club: Club) -> some View {
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
        } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .foregroundStyle(isFollowing ? Color.dsFollowStar : Color.dsFgSecondary)
                .imageScale(.large)
        }
        // .borderless so only the star toggles — not the whole row.
        .buttonStyle(.borderless)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    /// Request notification permission on the gesture (never at launch), so a
    /// bell-on team's day-before reminder can actually be delivered.
    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        if await center.notificationSettings().authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    TeamsView()
        .environment(FollowingStore())
        .environment(MatchStore())
        .environment(ClubStore())
}
