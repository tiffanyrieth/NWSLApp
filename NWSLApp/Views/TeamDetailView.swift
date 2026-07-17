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
//  Pushed from the Teams directory AND from a Standings row. The full-bleed header
//  carries identity, so there's no centered title — just a bare ‹ chevron over a
//  transparent nav bar (the team-color wash shows through), via `nativeBackButton()`.
//
//  Two sub-tabs (Squad default, Stats), per the Teams tab design spec. One roster
//  fetch powers everything — the squad cards, the header standing line, and stats.
//

import SwiftUI

struct TeamDetailView: View {
    let club: Club

    @State private var viewModel = TeamDetailViewModel()
    @Environment(FollowingStore.self) private var following
    // Per-team match-alert on/off (same store as the Teams list + the hub).
    @Environment(TeamAlertStore.self) private var teamAlerts
    @Environment(\.openURL) private var openURL

    // Named TeamSection (not Section) to avoid shadowing SwiftUI's Section view.
    private enum TeamSection: String, CaseIterable, Hashable {
        case squad = "Squad"
        case stats = "Stats"
    }
    @State private var section: TeamSection = .squad

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    // Social link-pill glyph size at the default text setting, scaled with Dynamic
    // Type on the `.body` axis so the brand glyph moves in lockstep with its `.dsFont`
    // label (capped at AX1 at the root — see RootTabView). Custom template images
    // render at their intrinsic SVG size and ignore `.font`, so unlike the old SF
    // Symbols these need an explicit scaled frame. ~15pt ≈ the prior 13pt symbol's
    // optical footprint (SF Symbols sit smaller than their point size).
    @ScaledMetric(relativeTo: .body) private var socialGlyphSize: CGFloat = 15

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
        // Bare ‹ chevron, no centered title — the full-bleed header carries identity.
        // Transparent (not hidden) nav bar so the team-color wash bleeds up behind it
        // AND the edge-swipe-back gesture is preserved (hiding the bar breaks swipe).
        .nativeBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: Athlete.self) { athlete in
            PlayerDetailView(
                athlete: athlete,
                accentHex: accentHex,
                stats: viewModel.stats(for: athlete),
                seasonLabel: viewModel.seasonLabel
            )
        }
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
            HStack(spacing: 14) {
                TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(club.displayName)
                        .dsFont(21, weight: .bold)
                        .foregroundStyle(Color.dsFgPrimary)
                        .lineLimit(2)
                    // Live standing line; fall back to the abbreviation so the header
                    // never looks empty while the roster loads.
                    Text(viewModel.standingLine ?? club.abbreviation)
                        .dsFont(13.5)
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

    private var bellControl: some View {
        let on = teamAlerts.alertsEnabled(for: club.id)
        // Direct toggle — tap = on/off, always. (The old first-tap "doorway into the
        // hub" was retired in favor of the Teams-tab coach mark.) The bell never
        // requests iOS notification permission — that fires only from inside the hub.
        return Button { teamAlerts.toggle(for: club.id) } label: { bellCircle(on: on) }
            .buttonStyle(.plain)
            .accessibilityLabel(on
                ? "Turn off match alerts for \(club.displayName)"
                : "Turn on match alerts for \(club.displayName)")
    }

    private func bellCircle(on: Bool) -> some View {
        Image(systemName: on ? "bell.fill" : "bell")
            .dsFont(15, weight: .medium)
            .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
            .frame(width: 38, height: 38)
            .background(on ? Color.dsAccentMuted : Color.dsBgTertiary, in: Circle())
    }

    private var followButton: some View {
        let isFollowing = following.isFollowing(club)
        return Button { following.toggle(club) } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .dsFont(16, weight: .medium)
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
                    .dsFont(11, weight: .semibold).tracking(0.5)
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
                        .dsFont(15, weight: .bold)
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer()
                    Text("FAN-RUN · UNOFFICIAL")
                        .dsFont(10, weight: .semibold).tracking(0.4)
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
        // Calm-rainbow rule: the platform color lives on the GLYPH only (for
        // at-a-glance recognizability); the pill fill is the neutral surface and the
        // label is white, so the OFFICIAL row reads as a calm button set rather than
        // a color strip competing with the team-color header. (Platform colors are
        // scoped to these outbound-link glyphs — all in-app chrome stays club-accent.)
        Button { openURL(link.url) } label: {
            HStack(spacing: 7) {
                Image(link.platform.iconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: socialGlyphSize, height: socialGlyphSize)
                    .foregroundStyle(platformColor(link.platform))
                Text(link.platform.label)
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .fixedSize()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Color.dsBgTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(link.platform.label) — open")
    }

    // Per-platform brand tint, used ONLY for the link-pill glyphs above (recognizable
    // destinations). Nowhere else — in-app chrome uses the club accent.
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
                            .dsFont(12, weight: .semibold).tracking(1)
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
        RetryStateView(message: message, style: .inline) {
            await viewModel.load(clubID: club.id)
        }
    }

    // MARK: - Squad (grouped player cards)

    private var squadContent: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            // Honest staleness indicator: shown ONLY when the roster was served from the
            // proxy's last-known-good cache (ESPN returned an implausibly small squad).
            // Subtle + secondary — the squad is real, just not freshly from ESPN.
            if let cachedAsOf = viewModel.rosterCachedAsOf {
                Text("Roster as of \(cachedAsOf.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .dsFont(12)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.positionGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label)
                        .dsFont(13, weight: .bold).tracking(0.3)
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
                        .dsFont(14, weight: .bold)
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(athlete.shortName ?? athlete.name)
                    .dsFont(14.5, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    // Player names must never truncate on the roster — wrap to a 2nd line
                    // (the grid row grows to the tallest card) with a scale backstop.
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                if let jersey = athlete.jersey, !jersey.isEmpty {
                    Text("#\(jersey)")
                        .dsFont(11.5).monospaced()
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
                .dsFont(15, weight: .bold)
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
                .dsFont(20, weight: .heavy, monospacedDigit: true)
                .foregroundStyle(emphasized ? accent : Color.dsFgPrimary)
            Text(label)
                .dsFont(11).foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // One leaders block. Hidden entirely when nobody qualifies (no empty card).
    @ViewBuilder
    private func leaderCard(_ title: String, leaders: [StatLeader]) -> some View {
        if !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .dsFont(14, weight: .bold)
                    .foregroundStyle(accent)
                VStack(spacing: 0) {
                    ForEach(Array(leaders.enumerated()), id: \.element.id) { index, leader in
                        HStack {
                            Text("\(index + 1)")
                                .dsFont(13, weight: .semibold)
                                .foregroundStyle(Color.dsFgSecondary)
                                .frame(width: 18, alignment: .leading)
                            Text(leader.name)
                                .dsFont(14.5)
                                .foregroundStyle(Color.dsFgPrimary)
                            Spacer()
                            Text("\(leader.value)")
                                .dsFont(15, weight: .bold, monospacedDigit: true)
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
        ))
    }
    .environment(FollowingStore())
}
