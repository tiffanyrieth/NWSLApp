//
//  TeamDetailView.swift
//  NWSLApp
//
//  A club's page — the "gateway to all things" for a club — redesigned in the
//  color-block language (design-handoff/team-detail.jsx). A full-bleed team-color
//  header (crest + name + standing line + Follow star + match-alert bell) sits over
//  the club's links (OFFICIAL accounts + a fan-community card) and Squad / Stats
//  sub-tabs.
//
//  Pushed from the Teams directory AND from a Standings row, so the back button is
//  driven by an `origin` the pusher passes ("‹ Teams" / "‹ Standings") — the
//  parent-reflecting back rule. The header carries identity (full-bleed), so the
//  system nav bar is hidden and there's no centered title — just the origin back.
//
//  Two sub-tabs (Squad default, Stats), per the Teams tab design spec. One roster
//  fetch powers everything — the squad cards, the header standing line, and stats.
//

import SwiftUI

struct TeamDetailView: View {
    let club: Club
    /// The screen this was pushed from — drives the "‹ {origin}" back button
    /// (parent-reflecting back rule). Teams passes "Teams", Standings "Standings".
    var origin: String = "Teams"

    @State private var viewModel = TeamDetailViewModel()
    @Environment(FollowingStore.self) private var following
    // Per-team match-alert on/off (same store as the Teams list + the hub).
    @Environment(TeamAlertStore.self) private var teamAlerts
    // Gates the bell's first-tap "doorway" (push the hub before enabling) — mirrors
    // the Teams list bell, so a user always sees the hub before opting in.
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Named TeamSection (not Section) to avoid shadowing SwiftUI's Section view.
    private enum TeamSection: String, CaseIterable, Hashable {
        case squad = "Squad"
        case stats = "Stats"
    }
    @State private var section: TeamSection = .squad

    // Route for the bell's first-tap doorway into the notifications hub.
    private enum ClubRoute: Hashable { case hub }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    linksSection
                    tabBar
                    sectionContent
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 24)
                }
            }
            .background(Color.dsBgGrouped)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Athlete.self) { athlete in
            PlayerDetailView(
                athlete: athlete,
                accentHex: accentHex,
                stats: viewModel.stats(for: athlete),
                seasonLabel: viewModel.seasonLabel
            )
        }
        .navigationDestination(for: ClubRoute.self) { _ in NotificationsView() }
        .task {
            // Social links are local seed data (instant) — load them first so the
            // links appear right away, then the roster fetch fills the squad/stats
            // and the accent the page colors itself with.
            await viewModel.loadSocialLinks(abbreviation: club.abbreviation)
            await viewModel.load(clubID: club.id)
        }
    }

    // MARK: - Full-bleed header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "‹ {origin}" back button (parent-reflecting). The full-bleed header
            // carries identity, so this is the only nav affordance.
            Button { dismiss() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    Text(origin).font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color.dsAccent)
            }

            HStack(spacing: 14) {
                TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(club.displayName)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.dsFgPrimary)
                        .lineLimit(2)
                    // Live standing line; fall back to the abbreviation so the header
                    // never looks empty while the roster loads.
                    Text(viewModel.standingLine ?? club.abbreviation)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.dsFgSecondary)
                }
                Spacer(minLength: 8)
                headerActions
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
        }
    }

    // Team-color diagonal wash over the dark match-detail panel gradient.
    private var headerBackground: some View {
        ZStack {
            LinearGradient(colors: [Color.dsMdPanel, Color.dsMdPanelBottom],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: 8) {
            if following.isFollowing(club) { bellControl }
            followButton
        }
    }

    @ViewBuilder
    private var bellControl: some View {
        let on = teamAlerts.alertsEnabled(for: club.id)
        if notifications.hubVisited {
            Button { teamAlerts.toggle(for: club.id) } label: { bellCircle(on: on) }
                .buttonStyle(.plain)
                .accessibilityLabel(on
                    ? "Turn off match alerts for \(club.displayName)"
                    : "Turn on match alerts for \(club.displayName)")
        } else {
            // First tap before the hub's ever been seen: push the hub (a doorway,
            // not a silent enable) — same rule as the Teams list bell.
            NavigationLink(value: ClubRoute.hub) { bellCircle(on: false) }
                .accessibilityLabel("Set up match alerts for \(club.displayName)")
        }
    }

    private func bellCircle(on: Bool) -> some View {
        Image(systemName: on ? "bell.fill" : "bell")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
            .frame(width: 38, height: 38)
            .background(on ? Color.dsAccentMuted : Color.dsBgTertiary, in: Circle())
    }

    private var followButton: some View {
        let isFollowing = following.isFollowing(club)
        return Button { following.toggle(club) } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isFollowing ? Color.dsFollowStar : Color.dsFgSecondary)
                .frame(width: 38, height: 38)
                .background(Color.dsBgTertiary, in: Circle())
                .overlay(Circle().stroke(isFollowing ? .clear : Color.dsFgQuaternary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    // MARK: - Links (OFFICIAL accounts + fan community)

    // The club's links split into OFFICIAL (the club's own accounts) and a
    // FAN-COMMUNITY card (fan-run spaces). A pill renders only for a link that
    // exists — missing platforms are gracefully omitted (no dead/greyed stubs).
    // Website/Shop/Tickets/Discord are spec'd but not yet in the data (a documented
    // follow-up data pass), so they simply don't appear until curated.
    @ViewBuilder
    private var linksSection: some View {
        let official = viewModel.socialLinks.filter { $0.platform != .reddit }
        let community = viewModel.socialLinks.filter { $0.platform == .reddit }

        if !official.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("OFFICIAL")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Color.dsFgTertiary)
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(official) { linkChip($0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 14)
        }

        if !community.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Fan community")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer()
                    Text("FAN-RUN · UNOFFICIAL")
                        .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                        .foregroundStyle(Color.dsFgTertiary)
                }
                HStack(spacing: 8) {
                    ForEach(community) { linkChip($0) }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl))
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private func linkChip(_ link: SocialLink) -> some View {
        let color = platformColor(link.platform)
        return Button { openURL(link.url) } label: {
            HStack(spacing: 7) {
                Image(systemName: link.platform.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(link.platform.label)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(link.platform.label) — open")
    }

    // Per-platform brand tint for the link pills (the redesign uses platform colors
    // here — deliberately louder than the header's single team color, to read as a
    // row of recognizable destinations).
    private func platformColor(_ platform: SocialPlatform) -> Color {
        switch platform {
        case .instagram: return Color(hex: "E1306C")
        case .bluesky:   return Color(hex: "1185FE")
        case .youtube:   return Color(hex: "FF3B30")
        case .tiktok:    return Color(hex: "25C9D6")
        case .reddit:    return Color(hex: "FF4500")
        }
    }

    // MARK: - Sub-tabs (team-color underline)

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TeamSection.allCases, id: \.self) { sec in
                Button { section = sec } label: {
                    VStack(spacing: 8) {
                        Text(sec.rawValue.uppercased())
                            .font(.system(size: 12, weight: .semibold)).tracking(1)
                            .foregroundStyle(section == sec ? Color.dsFgPrimary : Color.dsFgTertiary)
                        Rectangle()
                            .fill(section == sec ? accent : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        case .error(let message):
            sectionError(message)
        case .loaded:
            switch section {
            case .squad: squadContent
            case .stats: statsContent
            }
        }
    }

    private func sectionError(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try again") { Task { await viewModel.load(clubID: club.id) } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 32)
    }

    // MARK: - Squad (grouped player cards)

    private var squadContent: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(viewModel.positionGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label)
                        .font(.system(size: 13, weight: .bold)).tracking(0.3)
                        .foregroundStyle(accent)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(group.athletes) { athlete in
                            NavigationLink(value: athlete) { playerCard(athlete) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // A horizontal player card: team-color left border, headshot/initials circle,
    // name + jersey number (the redesign's squad cell).
    private func playerCard(_ athlete: Athlete) -> some View {
        HStack(spacing: 11) {
            PlayerHeadshot(athleteID: athlete.id, size: 42) {
                ZStack {
                    Circle().fill(accent.opacity(0.16))
                    Text(initials(for: athlete))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(athlete.shortName ?? athlete.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                if let jersey = athlete.jersey, !jersey.isEmpty {
                    Text("#\(jersey)")
                        .font(.system(size: 11.5).monospaced())
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd))
        .overlay(alignment: .leading) {
            // Team-color left edge (clipped to the card's rounded shape).
            Rectangle().fill(accent).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd))
        }
    }

    private func initials(for athlete: Athlete) -> String {
        let parts = athlete.name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init)
        return parts.isEmpty ? "—" : parts.joined()
    }

    // MARK: - Stats (season summary + team leaders)

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let season = seasonSummary { seasonCard(season) }
            leaderCard("Goals", leaders: viewModel.teamLeaders.topScorers)
            leaderCard("Assists", leaders: viewModel.teamLeaders.topAssists)
            leaderCard("Clean Sheets", leaders: viewModel.teamLeaders.topCleanSheets)
        }
    }

    private var seasonSummary: (gp: Int, w: Int, d: Int, l: Int, pts: Int)? {
        guard let record = viewModel.record else { return nil }
        let parts = record.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (w, d, l) = (parts[0], parts[1], parts[2])
        return (w + d + l, w, d, l, w * 3 + d)
    }

    private func seasonCard(_ s: (gp: Int, w: Int, d: Int, l: Int, pts: Int)) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Season")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.dsFgPrimary)
            HStack(spacing: 0) {
                statCell("GP", s.gp)
                statCell("W", s.w)
                statCell("D", s.d)
                statCell("L", s.l)
                statCell("PTS", s.pts, emphasized: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl))
    }

    private func statCell(_ label: String, _ value: Int, emphasized: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 20, weight: .heavy)).monospacedDigit()
                .foregroundStyle(emphasized ? accent : Color.dsFgPrimary)
            Text(label)
                .font(.system(size: 11)).foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // One leaders block. Hidden entirely when nobody qualifies (no empty card).
    @ViewBuilder
    private func leaderCard(_ title: String, leaders: [StatLeader]) -> some View {
        if !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                VStack(spacing: 0) {
                    ForEach(Array(leaders.enumerated()), id: \.element.id) { index, leader in
                        HStack {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.dsFgSecondary)
                                .frame(width: 18, alignment: .leading)
                            Text(leader.name)
                                .font(.system(size: 14.5))
                                .foregroundStyle(Color.dsFgPrimary)
                            Spacer()
                            Text("\(leader.value)")
                                .font(.system(size: 15, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Color.dsFgPrimary)
                        }
                        .padding(.vertical, 9)
                        if index < leaders.count - 1 {
                            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl))
        }
    }

    // MARK: - Color

    /// The club's accent hex: the design palette (by abbreviation) wins, then the
    /// roster's ESPN color. Threaded to the squad cards, player detail, and the
    /// header wash so they all share the club's color.
    private var accentHex: String? {
        DesignTeamColors.hex(for: club.abbreviation) ?? viewModel.accentColorHex
    }

    private var accent: Color {
        Color.teamAccent(hex: accentHex).fill
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(club: Club(
            id: "15365",
            displayName: "Washington Spirit",
            abbreviation: "WAS",
            logoURL: nil
        ), origin: "Teams")
    }
    .environment(FollowingStore())
}
