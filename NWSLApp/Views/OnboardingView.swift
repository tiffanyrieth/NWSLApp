//
//  OnboardingView.swift
//  NWSLApp
//
//  First-open onboarding — "Make it yours": pick the teams you follow. One
//  screen, one purpose (per the Home design spec). A crest-forward 2-up grid of
//  every club (no search — 16-20 teams scroll faster than they type); the WHOLE
//  TILE is the follow toggle, and a match-alert bell drops into the tile once
//  followed. A persistent bottom bar shows the running "Follow N teams" count
//  and the "you can always change this later" reassurance.
//
//  It's the full-screen first-open gate: RootTabView renders it (in its own
//  NavigationStack) IN PLACE OF the whole TabView while `FollowingStore.hasOnboarded`
//  is false, so there is NO tab bar and onboarding can't be skipped by tapping a tab.
//  Tapping "Follow N teams" calls `completeOnboarding()`, which flips RootTabView to
//  the TabView. It also `dismiss()`es (a harmless no-op in the gate path) so the same
//  view still works when re-presented as a sheet from Home's "edit teams" empty state.
//
//  Reuses TeamsViewModel for the club fetch (identical need: the directory) and
//  the shared FollowingStore for the toggles — the picks made here are the same
//  follows the Teams tab shows.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = TeamsViewModel()
    @Environment(FollowingStore.self) private var following
    // The shared club directory (injected in RootTabView); the view model reads
    // its state/clubs through this.
    @Environment(ClubStore.self) private var clubStore
    // The shared Home content store — warmed the instant a team is picked so Home is
    // already populated by the time onboarding finishes (no first-paint loading flash).
    @Environment(HomeContentStore.self) private var homeContent
    // Per-team match-alert toggles. Onboarding rows surface a bell the moment a club is
    // followed (OFF by default) so the follow-vs-alerts distinction is taught visually.
    @Environment(TeamAlertStore.self) private var teamAlerts
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    // Shared bell logic (same as the Teams tab): a signed-out match-alert tap presents Sign in
    // with Apple, then on success enables + cascades the full Tier-2 bundle (match updates, goals,
    // lineups, day-before, Live Activity — Fan Zone left off). NO confirmation toast here: onboarding
    // can't navigate to the notifications hub mid-flow (the toast's "Customize" action), and the
    // Teams-tab coach mark already nudges customization the moment onboarding finishes.
    @State private var alertPresenter = MatchAlertPresenter()

    // After the picker, a one-screen thesis statement frames what the app is before
    // dropping the user into Home. "Let's go" there completes onboarding.
    @State private var showThesis = false

    // Visible bell-circle diameter (2026-08-10 tap-target pass: was a hardcoded 30 — the one
    // frozen element on a card whose crest/name scale with Dynamic Type, and 14pt under the
    // HIG minimum). Scales on the same .body axis as the crest; padding in `tileBell` tops the
    // HIT area up to DS.tapTarget. A missed bell tap lands on the surrounding tile button and
    // silently unfollows + clears alerts, so this target must be generous.
    @ScaledMetric(relativeTo: .body) private var tileBellSize: CGFloat = 38

    private var followCount: Int { following.followedIDs.count }

    var body: some View {
        content
            .navigationTitle("Make it yours")
            .navigationBarTitleDisplayMode(.large)
            .task {
                viewModel.clubStore = clubStore
                if case .idle = clubStore.state { await viewModel.load() }
            }
            .fullScreenCover(isPresented: $showThesis) {
                ThesisView(
                    clubs: followedClubsInOrder,
                    alertCount: teamAlerts.enabledCount
                ) {
                    following.completeOnboarding()
                    dismiss()
                }
            }
            // Tier-2 sign-in intercept for the alert bells: signed-out ON presents this first;
            // success runs the deferred enable+cascade, cancel leaves the bell off. (No toast —
            // see the alertPresenter comment above.)
            .sheet(isPresented: $alertPresenter.showAuthPrompt,
                   onDismiss: { alertPresenter.cancelPending() }) {
                NotificationAuthPromptView(onSignedIn: { alertPresenter.onSignedIn() })
            }
    }

    // Followed clubs in the same alphabetical order the picker shows them — feeds the
    // thesis screen's crest row + name list.
    private var followedClubsInOrder: [Club] {
        viewModel.clubs.filter { following.isFollowing($0) }
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
            picker
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introBlock
                    .padding(.horizontal, 20)

                // Crest-forward 2-up grid: the club crest leads (the fandom identity),
                // selection rings the tile in the club's color + a check, and the bell
                // toggle appears in-tile once followed.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(viewModel.clubs) { clubTile(for: $0) }
                }
                .padding(.horizontal, 16)

                internationalPointerCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .padding(.top, 8)
        }
        // Persistent bottom bar: the running follow count + reassurance, always
        // visible above the list (and above the tab bar).
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Frame following as building a content feed (the YouTube/IG model), not
            // declaring allegiance + alerts — the #1 first-time-user misread. The bell
            // toggle on each followed row (below) teaches the alerts distinction visually,
            // so the old "following isn't notifications" footnote is no longer needed.
            Text("Your feed starts here. Tap any clubs you're interested in — their news, videos, and social posts will show up on your Home tab.")
                .dsFont(16)
                .foregroundStyle(Color.dsFgSecondary)
                // Guarantee full wrapping (never truncate) on the smallest screens (SE/mini).
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Toggle a follow + keep alerts honest: unfollowing clears the team's alert (alerts
    // require following). Warms Home content for the new selection (debounced).
    private func toggleFollow(_ club: Club) {
        following.toggle(club)
        if !following.isFollowing(club) {
            teamAlerts.clearAlerts(for: club.id)
        }
        homeContent.warm(following: following, clubStore: clubStore)
    }

    // A quiet pointer, not a toggle list: national teams are followed in their own hub
    // (Teams → Follow competitions), which is the designed flow. Onboarding stays focused
    // on picking clubs; this just tells a new fan the rest exists. (The old inert
    // competition toggles lived here.)
    private var internationalPointerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .dsFont(17)
                .foregroundStyle(Color.dsFgSecondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Following a national team?")
                    .dsFont(16)
                    .foregroundStyle(Color.dsFgPrimary)
                Text("Add national teams later in Teams → Follow competitions.")
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Direction B: crest-grid tile

    private func clubTile(for club: Club) -> some View {
        let isFollowing = following.isFollowing(club)
        // Compact tile: crest + name only when unselected (so all 16 clubs come into view
        // fast — the point of onboarding); the bell drops in below the name once followed.
        // Shared crest + card surface with the Teams tab (TeamTile) so they can't drift.
        return Button { toggleFollow(club) } label: {
            VStack(spacing: 10) {
                TeamCrestGlow(club: club, size: 60)
                Text(club.displayName)
                    .dsFont(15, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minHeight: 38, alignment: .center)   // reserve 2 lines so names align
            }
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 16, leading: 12, bottom: 14, trailing: 12))
            .teamTileSurface(club: club, isFollowing: isFollowing)
            // The bell + follow-check sit TOGETHER in the top-right (as an overlay, so selecting
            // never changes the tile's height — grid stays compact AND uniform). Grouped, not
            // split across corners, so the related controls read as a pair. The corner is also
            // deliberately far from where follow-taps land (tile center), since the bell
            // materializes under the finger right after a follow tap.
            .overlay(alignment: .topTrailing) {
                if isFollowing {
                    VStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .dsFont(20)
                            .foregroundStyle(club.accentColor)
                        tileBell(for: club)
                    }
                    // 6 here + the bell's own hit-ring padding ≈ the old 9pt visual inset.
                    .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.radiusXl))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isFollowing)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    // In-tile match-alert bell (labeled, so it reads as an alerts toggle at grid size).
    // Same on/off behavior as the Teams-tab bell and the old list-row bell.
    private func tileBell(for club: Club) -> some View {
        let on = teamAlerts.alertsEnabled(for: club.id)
        return Button {
            // Same path as every other bell: signed-out ON presents Sign in with Apple first
            // (bell stays off until sign-in), then enables + cascades the full match-alert bundle.
            alertPresenter.requestToggle(key: club.id, turnOn: !on, isSignedIn: auth.isSignedIn,
                                         alerts: teamAlerts, prefs: notifications)
        } label: {
            Image(systemName: on ? "bell.fill" : "bell")
                .dsFont(13, weight: .medium)
                .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
                .frame(width: tileBellSize, height: tileBellSize)
                .background(on ? Color.dsAccentMuted : Color.dsBgTertiary, in: Circle())
                // Invisible ring topping the HIT area up to the 44pt HIG minimum (the visible
                // circle stays 38). contentShape AFTER the padding so the ring is tappable;
                // max(0,…) because past ~AX sizes the scaled circle alone exceeds 44.
                .padding(max(0, (DS.tapTarget - tileBellSize) / 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            on ? "Turn off match alerts for \(club.displayName)"
               : "Turn on match alerts for \(club.displayName)"
        )
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            followButton

            Text("You can always change this later")
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // One shared filled CTA (DSButton): dimmed/disabled until ≥1 club is picked, then
    // lights up — no outline→filled swap, and it's the SAME button+size as the "Let's go"
    // CTA on the next (Thesis) screen, so the primary action never jumps between screens.
    private var followButton: some View {
        let title = followCount == 0
            ? "Add clubs to get started"
            : "Continue with \(followCount) club\(followCount == 1 ? "" : "s")"
        return DSButton(title, isEnabled: followCount > 0) {
            // Frame the app on a thesis screen before Home; "Let's go" there completes onboarding.
            showThesis = true
        }
        .accessibilityHint(followCount == 0 ? "Select at least one team to continue" : "")
    }

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) {
            await viewModel.load()
        }
    }
}

#Preview {
    NavigationStack {
        OnboardingView()
            .environment(FollowingStore())
            .environment(ClubStore())
            .environment(HomeContentStore())
            .environment(TeamAlertStore())
    }
}
