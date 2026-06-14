//
//  TeamDetailView.swift
//  NWSLApp
//
//  A club's page, pushed from the Teams directory (and from a Standings row). A
//  pinned header — crest + name + standing line ("4th in NWSL — 21 pts") + the
//  same Follow star used in the Teams list — sits above a segmented sub-tab bar,
//  and only the selected section scrolls.
//
//  Two sub-tabs, per the Teams tab design spec:
//   • Squad (default) — the "meet the team" grid: a 2-column LazyVGrid of player
//     cards grouped FWD → MID → DEF → GK, each accented in the club's color.
//     Tapping a card pushes PlayerDetailView.
//   • Stats — team leaders + formation; the data (per-player stats, lineups)
//     isn't in the endpoints we map yet, so this is an intentional placeholder.
//
//  Earlier this page had Overview and Schedule sub-tabs too; the spec's identity
//  audit removed them — schedule lives in the Schedule tab, and the per-club
//  "next match / recent result" belongs to the future Home. Teams now answers
//  one question: "who are these people?"
//
//  No NavigationStack of its own: it rides the pushing tab's stack, so the back
//  affordance comes for free (UI rule: every drilled-in view is reversible).
//  One roster fetch powers everything — the colored cards AND the header line.
//

import SwiftUI

struct TeamDetailView: View {
    let club: Club

    @State private var viewModel = TeamDetailViewModel()
    @Environment(FollowingStore.self) private var following

    // Named TeamSection (not Section) to avoid shadowing SwiftUI's Section view.
    private enum TeamSection: String, CaseIterable, Hashable {
        case squad = "Squad"
        case stats = "Stats"
    }

    @State private var section: TeamSection = .squad

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            socialRow

            Picker("Section", selection: $section) {
                ForEach(TeamSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            switch section {
            case .squad: squadSection
            case .stats: statsSection
            }
        }
        // Left-aligned "‹ Teams" context label (the pinned header below shows the
        // club name big, so the nav bar is just a where-am-I reminder).
        .navigationContextLabel("Teams")
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
            // row appears right away, then the roster fetch fills the squad and the
            // accent color the icons recolor to.
            await viewModel.loadSocialLinks(abbreviation: club.abbreviation)
            await viewModel.load(clubID: club.id)
        }
    }

    // MARK: - Header (pinned)

    private var header: some View {
        HStack(spacing: 16) {
            TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(club.displayName)
                    .font(.title2.weight(.bold))
                // Prefer the live standing line; fall back to the abbreviation
                // so the header never looks empty while the roster loads.
                if let standingLine = viewModel.standingLine {
                    Text(standingLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !club.abbreviation.isEmpty {
                    Text(club.abbreviation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            followButton
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Social row (below the header, above the sub-tabs)

    // A centered cluster of the club's social/community links, per the Teams tab
    // spec. Hidden entirely when the club has none, so there's no empty gap or dead
    // icons. The cluster is centered (not full-width-distributed) so it stays
    // balanced whether a team has two links or five.
    @ViewBuilder
    private var socialRow: some View {
        if !viewModel.socialLinks.isEmpty {
            HStack(spacing: 28) {
                ForEach(viewModel.socialLinks) { link in
                    SocialLinkButton(link: link, accentHex: accentHex)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
    }

    private var followButton: some View {
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
        } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .foregroundStyle(isFollowing ? Color.dsFollowStar : Color.dsFgSecondary)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    // MARK: - Squad (grouped player-card grid)

    @ViewBuilder
    private var squadSection: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            case .error(let message):
                squadError(message)
            case .loaded:
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.positionGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.label)
                                .font(.headline)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(group.athletes) { athlete in
                                    NavigationLink(value: athlete) {
                                        PlayerCard(athlete: athlete, accentHex: accentHex)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBgGrouped)
    }

    private func squadError(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.load(clubID: club.id) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 32)
    }

    // MARK: - Stats (season summary + team leaders)

    // A real season block — the club's record (real, from the roster payload) plus
    // team leaders in goals / assists / clean sheets. The leaders come from real
    // ESPN Core API per-player season stats (ESPNService.seasonStats), so they
    // match each player's own page exactly. A formation pitch still needs an
    // unmapped lineup endpoint and isn't shown (its absence is a missing feature,
    // not a "coming soon" card — see CLAUDE.md What's-Next).
    @ViewBuilder
    private var statsSection: some View {
        ScrollView {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            case .error(let message):
                squadError(message)
            case .loaded:
                VStack(alignment: .leading, spacing: 24) {
                    if let season = seasonSummary { seasonCard(season) }
                    leaderCard("Goals", systemImage: "soccerball",
                               leaders: viewModel.teamLeaders.topScorers)
                    leaderCard("Assists", systemImage: "arrow.up.forward",
                               leaders: viewModel.teamLeaders.topAssists)
                    leaderCard("Clean Sheets", systemImage: "hand.raised.fill",
                               leaders: viewModel.teamLeaders.topCleanSheets)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBgGrouped)
    }

    /// The club's accent hex: the design palette (by abbreviation) wins, then the
    /// roster's ESPN color — so dark ESPN primaries (Spirit navy, etc.) don't read
    /// as an invisible-on-dark accent. Threaded to the squad cards, player detail,
    /// and social icons so they all share the club's color.
    private var accentHex: String? {
        DesignTeamColors.hex(for: club.abbreviation) ?? viewModel.accentColorHex
    }

    private var accent: Color {
        Color.teamAccent(hex: accentHex).fill
    }

    // Parse the real "W-D-L" record into the season summary numbers.
    private var seasonSummary: (gp: Int, w: Int, d: Int, l: Int, pts: Int)? {
        guard let record = viewModel.record else { return nil }
        let parts = record.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (w, d, l) = (parts[0], parts[1], parts[2])
        return (w + d + l, w, d, l, w * 3 + d)
    }

    private func seasonCard(_ s: (gp: Int, w: Int, d: Int, l: Int, pts: Int)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Season")
                .font(.headline)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statCell(_ label: String, _ value: Int, emphasized: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(emphasized ? accent : .primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // One leaders block (e.g. top scorers). Hidden entirely when nobody qualifies,
    // so a category with no contributions doesn't leave an empty card.
    @ViewBuilder
    private func leaderCard(_ title: String, systemImage: String, leaders: [StatLeader]) -> some View {
        if !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(accent)
                VStack(spacing: 0) {
                    ForEach(Array(leaders.enumerated()), id: \.element.id) { index, leader in
                        HStack {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .leading)
                            Text(leader.name)
                                .font(.subheadline)
                            Spacer()
                            Text("\(leader.value)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 10)
                        if index < leaders.count - 1 { Divider() }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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
