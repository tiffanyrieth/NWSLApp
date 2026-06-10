//
//  StandingsView.swift
//  NWSLApp
//
//  The Standings tab: a clean, glanceable league table — the simplest tab in
//  the app (design spec: pure reference utility, not a spreadsheet). All 16
//  teams end to end, six stat columns (GP · W · D · L · PTS), followed teams
//  highlighted in blue, every row tappable into TeamDetailView.
//
//  Deliberately NO goals-for / goals-against / goal-difference or home/away
//  splits: those force horizontal scrolling on a phone and serve a
//  stat-obsessive audience that already has FotMob/ESPN. The thesis here is
//  connection and narrative — "did Spirit win?" — not stat overload. (See
//  Reference/Design/standings-tab-design-spec.md.)
//
//  Layout note: the column header sits OUTSIDE the ScrollView so it stays put
//  while the rows scroll. To keep it aligned with the rows, the header and the
//  rows share one set of fixed column widths (the `Col` constants) and the same
//  cell builders — there's no Grid spanning both because a Grid can't bridge the
//  scroll boundary.
//
//  Like the Teams rows, navigation is a plain Button that appends to a
//  NavigationPath (not a NavigationLink) so the destination is TeamDetailView —
//  the exact same club page reached from the Teams tab.
//

import SwiftUI

struct StandingsView: View {
    @State private var viewModel = StandingsViewModel()
    @State private var path = NavigationPath()
    @Environment(FollowingStore.self) private var following

    // Shared fixed column widths so the non-scrolling header lines up with the
    // scrolling rows. Tuned so all six columns + crest + name fit one phone
    // width with no horizontal scroll.
    private enum Col {
        static let rank: CGFloat = 24
        static let stat: CGFloat = 30
        static let points: CGFloat = 38
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Standings")
                .navigationDestination(for: Club.self) { club in
                    TeamDetailView(club: club)
                }
                .refreshable { await viewModel.load() }
        }
        // Load once on first appearance; pull-to-refresh covers manual reloads.
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading standings…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message)
        case .loaded:
            table
        }
    }

    // The column header is a PINNED section header inside the scroll (not a
    // separate band above it): it collapses cleanly under the large nav title and
    // then sticks below the bar as rows scroll — fixing the old title/header
    // overlap (#17) while still "staying put" over the rows.
    private var table: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(viewModel.rows) { row in
                        rowButton(for: row)
                        Divider().padding(.leading)
                    }
                    legend
                } header: {
                    columnHeader
                }
            }
        }
    }

    // MARK: - Header

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: Col.rank, alignment: .leading)
            Text("Team")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PTS")
                .frame(width: Col.points, alignment: .trailing)
            statHeader("GP")
            statHeader("W")
            statHeader("L")
            statHeader("D")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.dsFgSecondary)
        .padding(.horizontal)
        .padding(.vertical, 10)
        // Opaque so scrolling rows don't bleed through when this header pins.
        .background(Color.dsBgGrouped)
    }

    private func statHeader(_ title: String) -> some View {
        Text(title)
            .frame(width: Col.stat, alignment: .trailing)
    }

    // MARK: - Rows

    private func rowButton(for row: StandingsRow) -> some View {
        let isFollowing = following.isFollowing(row.club)
        // Followed teams: accent text + a soft blue-tinted row so the eye finds
        // your teams instantly on open (spec: highlight the Following lens).
        let tint: Color = isFollowing ? .dsAccent : .dsFgPrimary

        return Button {
            path.append(row.club)
        } label: {
            HStack(spacing: 0) {
                Text("\(row.rank)")
                    .font(.subheadline.weight(.medium))
                    .frame(width: Col.rank, alignment: .leading)

                HStack(spacing: 8) {
                    TeamLogo(urlString: row.club.logoURL, size: 24)
                    // Abbreviation, not the full name — full names get truncated on
                    // a phone (matches the app-wide abbreviation convention).
                    Text(row.club.abbreviation)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(row.points)")
                    .font(.subheadline.weight(.bold))
                    .frame(width: Col.points, alignment: .trailing)
                statCell(row.gamesPlayed)
                statCell(row.wins)
                statCell(row.losses)
                statCell(row.draws)
            }
            .foregroundStyle(tint)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(isFollowing ? Color.dsFollowTint : .clear)
            .contentShape(Rectangle())   // whole row is tappable, incl. padding
        }
        .buttonStyle(.plain)
    }

    private func statCell(_ value: Int) -> some View {
        Text("\(value)")
            .font(.subheadline)
            .frame(width: Col.stat, alignment: .trailing)
    }

    // MARK: - Footer

    private var legend: some View {
        Text("PTS = points · GP = games played · W = wins · L = losses · D = draws")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.vertical, 16)
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
    StandingsView()
        .environment(FollowingStore())
        .environment(MatchStore())
}
