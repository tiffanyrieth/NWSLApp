//
//  OnboardingView.swift
//  NWSLApp
//
//  First-open onboarding — "Make it yours": pick the teams you follow. One
//  screen, one purpose (per the Home design spec). A single alphabetical list
//  of every club (no grid, no search — 16-20 teams scroll faster than they
//  type), each row a whole-row follow toggle. A persistent bottom bar shows the
//  running "Follow N teams" count and the "you can always change this later"
//  reassurance.
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
    @Environment(\.dismiss) private var dismiss

    // After the picker, a one-screen thesis statement frames what the app is before
    // dropping the user into Home. "Let's go" there completes onboarding.
    @State private var showThesis = false

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
        List {
            // The intro rides a BORDERLESS row (not a section header): List headers
            // render with reduced/vibrant prominence that compounds on `.secondary`
            // and pushes it below readable contrast, so we keep it as normal row
            // content where `.secondary` renders at its true secondaryLabel tone.
            // Hierarchy is bold nav title → readable subtitle → smaller caption,
            // established by SIZE + spacing (not by dimming the caption).
            Section {
                introBlock
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
            }

            Section {
                ForEach(viewModel.clubs) { row(for: $0) }
            }

            internationalSection
            playerFollowingTeaser
        }
        .listStyle(.insetGrouped)
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
            Text("Your feed starts here. Add any clubs you're interested in — their news, videos, and social posts will show up on your Home tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // Guarantee full wrapping (never truncate) on the smallest screens (SE/mini).
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for club: Club) -> some View {
        // Two independent tap targets in one row: the crest+name+checkmark toggle follow,
        // and (once followed) a separate bell toggles match alerts. Both are `.plain`
        // buttons so List hit-tests them independently (the bell isn't a follow tap).
        let isFollowing = following.isFollowing(club)
        return HStack(spacing: 10) {
            Button { toggleFollow(club) } label: {
                HStack(spacing: 12) {
                    TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 32)
                    Text(club.displayName)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")

            // Bell appears only after following (alerts require following), OFF by default.
            if isFollowing {
                bellButton(for: club)
                    .transition(.opacity)
            }

            Button { toggleFollow(club) } label: {
                Image(systemName: isFollowing ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isFollowing ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .animation(.easeOut(duration: 0.2), value: isFollowing)
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

    // Match-alert bell — same chrome/behavior as the Teams-tab bell. Direct on/off toggle;
    // never requests iOS notification permission (that fires only from the Notifications
    // hub on a first toggle-on — the Bell-Tap fix).
    private func bellButton(for club: Club) -> some View {
        let on = teamAlerts.alertsEnabled(for: club.id)
        return Button {
            let turningOn = !on
            teamAlerts.toggle(for: club.id)
            if turningOn {
                // Onboarding opt-in enables the account-free Tier-1 day-before reminder (owner: at least
                // this should be on, not a silent bell-with-nothing). The full Tier-2 bundle is NOT enabled
                // here — no mid-onboarding sign-in — and the first-time sentinel is left untouched, so a
                // later in-app bell tap still cascades the whole bundle at Sign in with Apple.
                notifications.dayBefore = true
                Task { await MatchAlertPresenter.requestNotificationPermission() }
            }
        } label: {
            Image(systemName: on ? "bell.fill" : "bell")
                .dsFont(13, weight: .medium)
                .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
                .frame(width: 36, height: 32)
                .background(on ? Color.dsAccentMuted : Color.dsBgTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            on ? "Turn off match alerts for \(club.displayName)"
               : "Turn on match alerts for \(club.displayName)"
        )
    }

    // A quiet pointer, not a toggle list: international competitions (national teams
    // + the Champions Cup) are followed in their own hub (Teams → Follow competitions),
    // which is the designed flow. Onboarding stays focused on picking clubs; this just
    // tells a new fan the rest exists. (The old inert competition toggles lived here.)
    private var internationalSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Following a national team?")
                        .foregroundStyle(.primary)
                    Text("Add national teams + the Champions Cup later in Teams → Follow competitions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // A forward-looking teaser for the future player-following feature — purely
    // informational (not tappable). Sits below the national-teams pointer, same styling.
    private var playerFollowingTeaser: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Follow individual players")
                            .foregroundStyle(.primary)
                        Text("COMING SOON")
                            .dsFont(10, weight: .bold)
                            .tracking(0.5)
                            .foregroundStyle(Color.dsAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.dsAccentMuted, in: Capsule())
                    }
                    Text("Keep tabs on your favorite players across the league — no matter what team they're on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            followButton

            Text("You can always change this later")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // The follow CTA progresses outline → filled as teams are picked. The empty
    // state uses an explicit accent *outline* (visible border, no fill) so it
    // reads as a not-yet-active button — the old disabled `.borderedProminent`
    // gray capsule with muted centered text looked like a search bar. We draw the
    // border ourselves rather than leaning on `.bordered` + `.disabled`, whose
    // system dimming washes the tint back to gray. Filled blue once ≥1 team is
    // selected; the empty action is a no-op so onboarding still needs a pick.
    // `.controlSize(.regular)` keeps it tappable without eating a full row.
    @ViewBuilder
    private var followButton: some View {
        let title = followCount == 0
            ? "Add clubs to get started"
            : "Continue with \(followCount) club\(followCount == 1 ? "" : "s")"

        if followCount == 0 {
            Button {} label: {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Select at least one team to continue")
        } else {
            Button {
                // Frame the app on a thesis screen before Home; "Let's go" there
                // completes onboarding.
                showThesis = true
            } label: {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
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
    NavigationStack {
        OnboardingView()
            .environment(FollowingStore())
            .environment(ClubStore())
            .environment(HomeContentStore())
            .environment(TeamAlertStore())
    }
}
