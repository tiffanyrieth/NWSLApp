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
        // Empty inline title: the pinned header already shows the club name big,
        // so we leave the nav bar as just the back chevron (no duplicate name).
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Athlete.self) { athlete in
            PlayerDetailView(athlete: athlete, accentHex: viewModel.accentColorHex)
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
            TeamLogo(urlString: club.logoURL, size: 56)
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
                    SocialLinkButton(link: link, accentHex: viewModel.accentColorHex)
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
                .foregroundStyle(isFollowing ? .yellow : .secondary)
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
                                        PlayerCard(athlete: athlete, accentHex: viewModel.accentColorHex)
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
        .background(Color(.systemGroupedBackground))
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

    // MARK: - Stats (intentional placeholder)

    // Team leaders + most-recent formation per the design spec. The data
    // (per-player season stats, lineups/formation) isn't in the endpoints we map
    // yet — so this is a deliberate "coming soon", not a blank tab. Flagged as a
    // placeholder in the File Map; becomes the real section once stats land.
    private var statsSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Team stats coming soon")
                .font(.headline)
            Text("Team leaders and the latest formation will live here as the data comes online.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
