//
//  TeamsView.swift
//  NWSLApp
//
//  The Teams tab: a directory of all NWSL clubs, redesigned (color-block language,
//  `design-handoff/teams.jsx`) as a 2-column CREST GRID. Each card carries the
//  club crest, full name, a Follow/Following pill, and — once followed — a match-
//  alert bell. Following is the app's personalization lens (see FollowingStore);
//  followed cards get a team-color wash + border, but the grid stays in stable A–Z
//  order (no following-first float: with 16 clubs a fixed order scans better than a
//  grid that reshuffles as you follow).
//
//  The FollowingStore / ClubStore / TeamAlertStore arrive via the SwiftUI
//  environment (injected once in RootTabView), not constructed here — so this
//  screen and the rest of the app share one source of truth.
//
//  Each card opens TeamDetailView (crest, club schedule, roster, Follow). Only the
//  crest+name area opens the club; the Follow pill and bell are SIBLING buttons
//  (a Button nested in another Button swallows the outer tap), each owning its taps.
//

import SwiftUI

struct TeamsView: View {
    @State private var viewModel = TeamsViewModel()
    @State private var path = NavigationPath()
    @Environment(FollowingStore.self) private var following
    // The shared club directory (injected in RootTabView); the view model reads
    // its state/clubs through this.
    @Environment(ClubStore.self) private var clubStore
    // Per-team match-alert on/off — drives the card bells + the alerts footer line.
    @Environment(TeamAlertStore.self) private var teamAlerts
    // For the bell's intent-driven default cascade + Tier-2 sign-in intercept.
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(AuthStore.self) private var auth

    // The one extra route on this stack (besides Club → TeamDetailView): the
    // notifications hub, pushed from the header bell + the "Manage" line.
    private enum NotificationsRoute: Hashable { case hub }

    // One-time coach mark pointing at the header bell ("Manage your match alerts
    // here"), shown the first time the user lands on the Teams tab. Replaces the old
    // per-team-bell "doorway into the hub": the bells now toggle directly, and this
    // tooltip carries the educational job of revealing where alerts are managed.
    @AppStorage("hasSeenTeamsAlertTooltip") private var hasSeenAlertTooltip = false
    @State private var showAlertTooltip = false

    // Owns the bell's confirmation toast + the Tier-2 sign-in intercept (shared logic across
    // every bell — see MatchAlertPresenter / MatchAlertToast).
    @State private var alertPresenter = MatchAlertPresenter()

    // Two equal columns with the same 12pt gutter as the row spacing (per the mock).
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Color.dsBgGrouped)
                // The title + bell scroll with the grid (per the mock), so the
                // system nav bar is hidden on this root. Pushed destinations
                // (TeamDetailView, the hub, Competitions) keep their own nav bars.
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Club.self) { club in
                    TeamDetailView(club: club)
                }
                .navigationDestination(for: NotificationsRoute.self) { _ in
                    NotificationsView()
                }
        }
        // Load once on first appearance; don't refetch every time the tab is
        // re-selected (the directory is static — nothing to refresh).
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
        // Stable A–Z by full name — followed clubs keep their wash + border in place
        // but never reshuffle (you always know where Spirit is).
        let clubs = viewModel.clubs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        return ScrollView {
            VStack(spacing: 0) {
                // zIndex lifts the header (and its coach-mark overlay, which hangs DOWN
                // past the header frame via offset) above the later siblings — without
                // it the subtitle/grid composite on top and hide the tooltip.
                header
                    .zIndex(1)
                subtitle
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(clubs) { teamCard($0) }
                }
                .padding(.horizontal, 16)
                competitionsRow
                alertsFooter
            }
        }
        // Tap anywhere in the grid dismisses the coach mark. `simultaneousGesture`
        // runs alongside the cards' own taps (it doesn't swallow them), so a tap that
        // also opens a club / toggles follow still dismisses the tooltip. No-op once
        // the tooltip is gone.
        .simultaneousGesture(TapGesture().onEnded {
            if showAlertTooltip { dismissAlertTooltip() }
        })
        // First time the Teams tab is reached, point the user at the bell. Mark it
        // seen on show (not just on dismiss) so it's truly one-and-done — it won't
        // reappear after a force-quit or when returning from a club detail.
        .onAppear {
            if !hasSeenAlertTooltip {
                hasSeenAlertTooltip = true
                withAnimation(.easeOut(duration: 0.25).delay(0.35)) {
                    showAlertTooltip = true
                }
            }
        }
        // Bell-confirmation toast (shared modifier): floats above the tab bar, fixed. Tapping the
        // "on" toast pushes the hub on THIS stack.
        .matchAlertToast(alertPresenter) { path.append(NotificationsRoute.hub) }
        // Tier-2 sign-in intercept: a signed-out bell tap presents this first; success runs the
        // deferred activation (enable + cascade + toast), cancel leaves the bell off.
        .sheet(isPresented: $alertPresenter.showAuthPrompt, onDismiss: { alertPresenter.cancelPending() }) {
            NotificationAuthPromptView(onSignedIn: { alertPresenter.onSignedIn() })
        }
    }

    // "Teams" title with the notifications bell inline on the SAME row, right-aligned
    // (the system nav-bar item pins up by the status bar). A live dot rides the bell
    // when any followed club has match alerts on.
    private var header: some View {
        HStack {
            Text("Teams")
                .dsFont(32, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            Spacer()
            Button {
                // Tapping the bell both dismisses the coach mark and opens the hub.
                if showAlertTooltip { dismissAlertTooltip() }
                path.append(NotificationsRoute.hub)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .dsFont(17, weight: .semibold)
                        .foregroundStyle(Color.dsAccent)
                        .frame(width: 40, height: 40)
                        .background(Color.dsBgCard)
                        .clipShape(Circle())
                    if teamAlerts.enabledCount > 0 {
                        Circle()
                            .fill(Color.dsLive)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.dsBgGrouped, lineWidth: 1.5))
                            .offset(x: -6, y: 6)
                    }
                }
            }
            .accessibilityLabel("Notifications")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        // The coach mark hangs below the bell, arrow pointing up at it. Anchored to
        // the padded header so it stays inset from the screen edge and extends left.
        .overlay(alignment: .topTrailing) {
            if showAlertTooltip {
                alertTooltip
                    .fixedSize()
                    .padding(.trailing, 16)
                    .offset(y: 46)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
            }
        }
    }

    private var subtitle: some View {
        Text("Tap any club to explore their squad and stats.")
            .dsFont(13)
            .foregroundStyle(Color.dsFgSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
    }

    // MARK: - Coach mark

    // A small blue callout anchored under the header bell (arrow up), shown once. The
    // arrow sits near the bubble's trailing edge so it lines up under the right-aligned
    // bell. Tapping the bubble dismisses it (so does tapping anywhere / the bell).
    private var alertTooltip: some View {
        VStack(alignment: .trailing, spacing: 0) {
            CoachMarkTriangle()
                .fill(Color.dsAccent)
                .frame(width: 16, height: 8)
                .padding(.trailing, 12)
            Text("Manage your match alerts here")
                .dsFont(13, weight: .semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.dsAccent, in: RoundedRectangle(cornerRadius: 10))
        }
        .onTapGesture { dismissAlertTooltip() }
        .accessibilityLabel("Manage your match alerts here. Tap the bell to open notification settings.")
    }

    private func dismissAlertTooltip() {
        hasSeenAlertTooltip = true
        withAnimation(.easeOut(duration: 0.2)) { showAlertTooltip = false }
    }

    // MARK: - Team card

    private func teamCard(_ club: Club) -> some View {
        let isFollowing = following.isFollowing(club)
        return VStack(spacing: 9) {
            // Only the crest + name open the club; the controls below are siblings.
            Button { path.append(club) } label: {
                VStack(spacing: 9) {
                    crest(for: club)
                    Text(club.displayName)
                        .dsFont(14, weight: .semibold)
                        .foregroundStyle(Color.dsFgPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .lineSpacing(1)
                        // Reserve two lines so the crest (above) and controls (below)
                        // stay vertically consistent across 1- and 2-line names; CENTER
                        // the name in that reserved space so a 1-line name's slack is
                        // split above/below rather than dumped under it.
                        .frame(minHeight: 35, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            controlRow(for: club)
        }
        .padding(EdgeInsets(top: 18, leading: 12, bottom: 13, trailing: 12))
        .frame(maxWidth: .infinity)
        .background(cardBackground(for: club, isFollowing: isFollowing))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .stroke(isFollowing ? club.accentColor.opacity(0.4) : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl))
    }

    // Ring-free crest with a soft team-color halo (a blurred color behind it — NOT a
    // drop shadow, keeping the app's no-shadow rule). Real crest via TeamLogo.
    private func crest(for club: Club) -> some View {
        TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 58)
            .background(
                Circle()
                    .fill(club.accentColor.opacity(0.22))
                    .blur(radius: 14)
            )
    }

    @ViewBuilder
    private func cardBackground(for club: Club, isFollowing: Bool) -> some View {
        if isFollowing {
            // Team-color wash blooming from behind the crest, over the base card.
            ZStack {
                Color.dsBgCard
                RadialGradient(
                    colors: [club.accentColor.opacity(0.17), .clear],
                    center: UnitPoint(x: 0.5, y: 0.32),
                    startRadius: 0, endRadius: 115
                )
            }
        } else {
            Color.dsBgCard
        }
    }

    // The Follow/Following pill (flexes to fill) + a square match-alert bell that
    // only appears once the club is followed (alerts require following).
    private func controlRow(for club: Club) -> some View {
        let isFollowing = following.isFollowing(club)
        return HStack(spacing: 7) {
            followPill(for: club, isFollowing: isFollowing)
            if isFollowing { bellButton(for: club) }
        }
        .padding(.top, 2)
    }

    private func followPill(for club: Club, isFollowing: Bool) -> some View {
        Button { following.toggle(club) } label: {
            HStack(spacing: 5) {
                Image(systemName: isFollowing ? "star.fill" : "star")
                    .dsFont(11)
                    .foregroundStyle(isFollowing ? Color.dsFollowStar : Color.dsFgSecondary)
                Text(isFollowing ? "Following" : "Follow")
                    .dsFont(12.5, weight: .semibold)
                    .foregroundStyle(isFollowing ? Color.dsFgPrimary : Color.dsFgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isFollowing ? Color.dsBgTertiary : Color.clear)
            .overlay(
                Capsule().stroke(isFollowing ? .clear : Color.dsFgQuaternary, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    private func bellButton(for club: Club) -> some View {
        let on = teamAlerts.alertsEnabled(for: club.id)
        // Direct toggle — tap = on/off, always. (The old first-tap "doorway into the
        // hub" was retired in favor of the Teams-tab coach mark.) The bell never
        // requests iOS notification permission — that fires only from inside the hub
        // on a first toggle-on (Bell-Tap fix, Bug 3).
        return Button { toggleAlerts(for: club) } label: {
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

    // Route the bell through the shared presenter: turning ON cascades the default bundle (first
    // time) + intercepts sign-in when signed out; OFF is immediate. Always breadcrumbs via the toast.
    private func toggleAlerts(for club: Club) {
        let turnOn = !teamAlerts.alertsEnabled(for: club.id)
        alertPresenter.requestToggle(key: club.id, turnOn: turnOn, isSignedIn: auth.isSignedIn,
                                     alerts: teamAlerts, prefs: notifications)
    }

    // MARK: - Competitions + alerts footer

    // A way back into international competitions for anyone who skipped them during
    // onboarding (the only other place they're offered).
    private var competitionsRow: some View {
        NavigationLink {
            CompetitionsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .dsFont(18)
                    .foregroundStyle(Color.dsAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Follow competitions")
                        .dsFont(15, weight: .semibold)
                        .foregroundStyle(Color.dsFgPrimary)
                    Text(competitionsSubtitle)
                        .dsFont(12.5)
                        .foregroundStyle(Color.dsFgSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if competitionFollowCount > 0 {
                    Text("\(competitionFollowCount) ON")
                        .dsFont(11, weight: .bold)
                        .foregroundStyle(Color.dsSuccess)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.dsSuccess.opacity(0.18), in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .dsFont(15, weight: .semibold)
                    .foregroundStyle(Color.dsFgTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    // Active-state count for the green "N ON" badge: the Champions Cup toggle (1) +
    // each followed national team.
    private var competitionFollowCount: Int {
        (following.isConcacafFollowed ? 1 : 0) + following.followedNationalTeams.count
    }

    // Subtitle reflecting what's turned on behind the row (per the handoff table).
    private var competitionsSubtitle: String {
        let championsCup = following.isConcacafFollowed
        let teams = following.followedNationalTeams.count
        if !championsCup && teams == 0 { return "Champions Cup, national teams & more" }
        if championsCup && teams == 0 { return "Champions Cup on" }
        var parts: [String] = []
        if championsCup { parts.append("Champions Cup") }
        parts.append(teams == 1 ? "1 national team" : "\(teams) national teams")
        return parts.joined(separator: " · ")
    }

    // "{N} team(s) with match alerts · Manage" → the hub, OR an empty-state hint.
    @ViewBuilder
    private var alertsFooter: some View {
        let n = teamAlerts.enabledCount
        Group {
            if n > 0 {
                Button { path.append(NotificationsRoute.hub) } label: {
                    Text("\(n) team\(n == 1 ? "" : "s") with match alerts · ")
                        .foregroundStyle(Color.dsFgSecondary)
                    + Text("Manage").foregroundStyle(Color.dsAccent).fontWeight(.semibold)
                }
                .buttonStyle(.plain)
            } else {
                Text("Tap the bell on a followed club to get match alerts.")
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
        .dsFont(13)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 22)
    }

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message) {
            await viewModel.load()
        }
    }
}

#Preview {
    TeamsView()
        .environment(FollowingStore())
        .environment(MatchStore())
        .environment(ClubStore())
}
