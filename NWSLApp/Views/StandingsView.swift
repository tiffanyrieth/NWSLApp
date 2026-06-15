//
//  StandingsView.swift
//  NWSLApp
//
//  The Standings tab, rebuilt in the redesign's "color-block" language
//  (Reference/Feed update/design-handoff — Standings.html / standings.jsx):
//  one rounded card, a team-color left edge + color-coded abbreviation on every
//  row, PTS as the bold white hero number, and a quiet "Last 5" recent-form
//  column on the far right. A cyan PLAYOFF LINE marks the top-8 cutoff; teams
//  below it dim. Followed clubs get the blue tint + accent rank + star, and
//  every row taps into TeamDetailView.
//
//  Columns: # · TEAM · PTS · GP · W · D · L · LAST 5. (GP is kept — owner
//  decision; the mock omits it.) The deliberate no-GF/GA/GD stance stands.
//
//  Data: the table itself is the same one-shot ESPN fetch (StandingsViewModel).
//  The Last-5 column has no ESPN source (the standings endpoint carries only
//  cumulative totals), so it's derived from the shared season in MatchStore via
//  the pure `RecentForm` helper — computed in the view so it lights up reactively
//  whenever the season finishes loading.
//
//  Navigation mirrors the Teams rows: a plain Button appends the Club to a
//  NavigationPath → the same TeamDetailView reached from the Teams tab.
//

import SwiftUI

struct StandingsView: View {
    @State private var viewModel = StandingsViewModel()
    @State private var path = NavigationPath()
    @Environment(FollowingStore.self) private var following
    // The shared season — source of the derived Last-5 form column.
    @Environment(MatchStore.self) private var matchStore

    // NWSL's current playoff format: the top 8 of the table advance. ESPN exposes
    // no playoff-spots field, so this is the single source of truth for both the
    // header pill and the in-table cutoff line. Update here if the league changes.
    private let playoffSpots = 8

    // Shared fixed column widths + gap so the (non-pinned) header lines up with the
    // rows. Tightened from the mock to fit GP + Last-5 on one phone width with no
    // horizontal scroll.
    private enum Col {
        static let rank: CGFloat = 18
        static let pts: CGFloat = 34
        static let stat: CGFloat = 20    // GP · W · D · L
        static let form: CGFloat = 78    // five 13pt badges + 3pt gaps
        static let gap: CGFloat = 5
    }
    // Row content insets (inside the card) and the card's own side margin. The
    // column header sits OUTSIDE the card, so its insets are the sum of the two —
    // that's what keeps the header cells aligned over the row cells.
    private enum Inset {
        static let cardMargin: CGFloat = DS.pagePadding   // 16
        static let rowLead: CGFloat = 14
        static let rowTrail: CGFloat = 12
        static var headerLead: CGFloat { cardMargin + rowLead }   // 30
        static var headerTrail: CGFloat { cardMargin + rowTrail } // 28
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                // Inline header replaces the system large title (like TeamsView),
                // so hide the root nav bar; pushed views keep their own bar + back.
                .toolbar(.hidden, for: .navigationBar)
                .background(Color.dsBgGrouped)
                .navigationDestination(for: Club.self) { club in
                    TeamDetailView(club: club)
                }
        }
        // Load once on first appearance. Standings also reads the shared season for
        // its Last-5 column, so ensure that's fetched too (guarded on .idle — a
        // no-op if Home/Schedule already loaded it; this just covers Standings being
        // the first screen a user lands on).
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
            if case .idle = matchStore.state { await matchStore.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("Loading standings…")
                        .padding(.top, 100)
                        .frame(maxWidth: .infinity)
                case .error(let message):
                    errorView(message)
                case .loaded:
                    tableBody
                }
            }
        }
    }

    // MARK: - Header (title + playoff pill + season subtitle)

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Standings")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.dsFgPrimary)
                Spacer()
                Text("TOP \(playoffSpots) ADVANCE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.dsStateKickoff)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.dsStateKickoff.opacity(0.14), in: Capsule())
            }
            // `String(...)` so the year renders "2026", not the locale-grouped "2,026".
            Text("\(String(seasonYear)) NWSL · Regular season")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsFgSecondary)
        }
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// The active season year — same source MatchStore uses for the scoreboard.
    private var seasonYear: Int { Calendar.current.component(.year, from: Date()) }

    // MARK: - Table

    private var tableBody: some View {
        // Compute the Last-5 map once per render (cheap, O(events)) and thread it
        // into the rows rather than recomputing per row.
        let form = RecentForm.lastFiveByAbbreviation(in: matchStore.events)
        return VStack(spacing: 0) {
            columnHeader
            card(form: form)
            footer
        }
    }

    private var columnHeader: some View {
        HStack(spacing: Col.gap) {
            Text("#").frame(width: Col.rank, alignment: .leading)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            Text("PTS").frame(width: Col.pts, alignment: .trailing)
            Text("GP").frame(width: Col.stat, alignment: .trailing)
            Text("W").frame(width: Col.stat, alignment: .trailing)
            Text("D").frame(width: Col.stat, alignment: .trailing)
            Text("L").frame(width: Col.stat, alignment: .trailing)
            Text("Last 5").frame(width: Col.form, alignment: .trailing)
        }
        .trackedCaps(size: 11, tracking: 0.4, weight: .semibold, color: .dsFgTertiary)
        .padding(.leading, Inset.headerLead)
        .padding(.trailing, Inset.headerTrail)
        .padding(.bottom, 8)
    }

    private func card(form: [String: [MatchResult]]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                if index == playoffSpots {
                    playoffLine
                } else if index > 0 {
                    rowDivider
                }
                rowButton(for: row, recent: form[row.club.abbreviation] ?? [])
            }
        }
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .padding(.horizontal, Inset.cardMargin)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.dsSeparator)
            .frame(height: DS.hairline)
            .padding(.leading, Inset.rowLead)
    }

    private var playoffLine: some View {
        HStack(spacing: 10) {
            playoffRule
            Text("PLAYOFF LINE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.dsStateKickoff)
            playoffRule
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var playoffRule: some View {
        Rectangle()
            .fill(Color.dsStateKickoff.opacity(0.4))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Row

    private func rowButton(for row: StandingsRow, recent: [MatchResult]) -> some View {
        let isFollowing = following.isFollowing(row.club)
        let playoff = row.rank <= playoffSpots
        let accent = row.club.accentColor
        // Rank: accent for your teams, white inside the playoff line, dim below it.
        let rankColor: Color = isFollowing ? .dsAccent : (playoff ? .dsFgPrimary : .dsFgTertiary)

        return Button {
            path.append(row.club)
        } label: {
            HStack(spacing: Col.gap) {
                Text("\(row.rank)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(rankColor)
                    .frame(width: Col.rank, alignment: .leading)

                HStack(spacing: 7) {
                    TeamLogo(urlString: row.club.logoURL,
                             teamAbbreviation: row.club.abbreviation,
                             size: DS.avatarSm)
                    Text(row.club.abbreviation)
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(accent)
                        // The "pop on dark" glow — the single biggest lever per the
                        // design language. Subtle so the letters stay crisp.
                        .shadow(color: accent.opacity(0.27), radius: 6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isFollowing {
                        Text("★")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.dsFollowStar)
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(row.points)")
                    .font(.system(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.dsFgPrimary)
                    .frame(width: Col.pts, alignment: .trailing)
                statCell(row.gamesPlayed)
                statCell(row.wins)
                statCell(row.draws)
                statCell(row.losses)
                formCell(recent)
            }
            .padding(.leading, Inset.rowLead)
            .padding(.trailing, Inset.rowTrail)
            .frame(height: 50)
            .background(isFollowing ? Color.dsFollowTint : Color.clear)
            // 3px team-color left edge, inset from the rounded card corners.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 9)
            }
            // Teams below the playoff line read quieter.
            .opacity(playoff ? 1 : 0.6)
            .contentShape(Rectangle())   // whole row tappable, incl. padding
        }
        .buttonStyle(.plain)
    }

    private func statCell(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 14, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.dsFgSecondary)
            .frame(width: Col.stat, alignment: .trailing)
    }

    /// Up to five W/D/L badges, oldest → newest (newest on the right). Teams with
    /// fewer than five completed matches show only what they have — no padding.
    private func formCell(_ recent: [MatchResult]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, result in
                FormBadge(result, size: 13, fontSize: 8)
            }
        }
        .frame(width: Col.form, alignment: .trailing)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Tap any club for its full page · Last 5 shows recent results, newest on the right.")
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.dsFgTertiary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 20)
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
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StandingsView()
        .environment(FollowingStore())
        .environment(MatchStore())
}
