//
//  StandingsView.swift
//  NWSLApp
//
//  The Standings tab, rebuilt in the redesign's "color-block" language
//  (Reference/Feed update/design-handoff — Standings.html / standings.jsx):
//  one rounded card, a color-coded abbreviation + crest on every row (so the table
//  stays vibrant), PTS as the bold white hero number, and a quiet "Last 5"
//  recent-form column on the far right. The team-color left spine is a FOLLOW
//  indicator — only followed clubs get it (plus the blue tint + accent rank);
//  if you follow nobody, every row keeps its bar so the table isn't all-grey. A cyan
//  PLAYOFF LINE marks the top-8 cutoff — it's the ONLY cutoff cue; below-line rows
//  render at full opacity (no dimming). Every row taps into TeamDetailView.
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
    // rows. Per the §0 crest rule, secondary elements (gaps, the W/D/L columns, the
    // Last-5 width) are kept tight so the 32pt crest + abbreviation + ★ never clip.
    //
    // ⚠️ TWO SETS, and the split is at ACCESSIBILITY SIZES ONLY (2026-07-29). Measured
    // across every Dynamic Type step: the standard set carries the whole standard range
    // — xSmall through xxxLarge — with all nine columns on one line and nothing lost.
    // At AX1 it doesn't: `W` rendered as "…" and `GD` as "+…", because the text scales
    // 1.65× inside fixed-width columns and `minimumScaleFactor` runs out. So AX1 (and
    // only AX1) gets wider columns, funded by moving `Last 5` onto its own line in each
    // row. Everything below AX1 is byte-for-byte the layout that already worked — the
    // measurement is the whole reason the threshold sits here and not lower.
    private struct Columns {
        let rank, pts, gp, wdl, gd, form, gap: CGFloat

        /// xSmall … xxxLarge. Sized for 14pt digits; verified to fit through xxxLarge.
        static let standard = Columns(rank: 22, pts: 34, gp: 22, wdl: 19, gd: 26, form: 69, gap: 5)
        /// AX1 only. `Last 5`'s 69pt is redistributed to the numeric columns, which is
        /// what stops the ellipsis. Budget is tight by design: the crest stays 32pt (it
        /// does not shrink — §0) and the abbreviation is `fixedSize`, so the leftover has
        /// to cover both.
        static let accessibility = Columns(rank: 26, pts: 40, gp: 28, wdl: 26, gd: 36, form: 69, gap: 5)
    }

    /// The app caps Dynamic Type at AX1 (`RootTabView`), so this is true at exactly one
    /// size — AX1 — and every larger system setting resolves to it.
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }
    private var col: Columns { isAccessibilitySize ? .accessibility : .standard }
    // Row content insets (inside the card) and the card's own side margin. The
    // column header sits OUTSIDE the card, so its insets are the sum of the two —
    // that's what keeps the header cells aligned over the row cells.
    private enum Inset {
        static let cardMargin: CGFloat = DS.pagePadding   // 16
        static let rowLead: CGFloat = 18
        static let rowTrail: CGFloat = 14
        static var headerLead: CGFloat { cardMargin + rowLead }   // 34
        static var headerTrail: CGFloat { cardMargin + rowTrail } // 30
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
            // At AX1 the 32pt title and the pill can't share a line — side by side they
            // overflowed BOTH screen edges (the title clipped left, the pill ran off
            // right). Stacking them is the only thing that fits, and it's confined to
            // AX1; below it they stay on one row exactly as before.
            if isAccessibilitySize {
                titleText
                playoffPill
            } else {
                HStack(alignment: .firstTextBaseline) {
                    titleText
                    Spacer()
                    playoffPill
                }
            }
            // `String(...)` so the year renders "2026", not the locale-grouped "2,026".
            Text("\(String(seasonYear)) NWSL · Regular season")
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
        }
        // Fill the width and stay leading-aligned. The non-AX branch gets this for free from
        // its HStack's `Spacer()`; the AX branch has no full-width child, so without this the
        // VStack shrinks to its content and SwiftUI centres the whole header block.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.pagePadding)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var titleText: some View {
        Text("Standings")
            .dsFont(32, weight: .bold)
            .foregroundStyle(Color.dsFgPrimary)
            // Keep the large title on one line beside the "TOP N ADVANCE" pill at
            // larger text sizes (it otherwise wraps mid-word to "Standing"/"s").
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var playoffPill: some View {
        Text("TOP \(playoffSpots) ADVANCE")
            .dsFont(11, weight: .bold)
            .tracking(0.4)
            .foregroundStyle(Color.dsStateKickoff)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.dsStateKickoff.opacity(0.14), in: Capsule())
    }

    /// The season the loaded table represents (from the VM's rollover), so the offseason label shows the
    /// prior season it's actually serving — not the raw calendar year (which would mislabel the gap).
    private var seasonYear: Int { viewModel.servedSeason }

    // MARK: - Table

    private var tableBody: some View {
        // Compute the Last-5 map once per render (cheap, O(events)) and thread it
        // into the rows rather than recomputing per row.
        // NWSL-only events: a club's Last-5 is its LEAGUE form — Champions Cup ties
        // (which carry NWSL abbreviations) must not count toward it.
        let form = RecentForm.lastFiveByAbbreviation(in: matchStore.nwslEvents)
        return VStack(spacing: 0) {
            columnHeader
            card(form: form)
            footer
        }
    }

    private var columnHeader: some View {
        HStack(spacing: col.gap) {
            Text("#").frame(width: col.rank, alignment: .trailing)
            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
            Text("PTS").frame(width: col.pts, alignment: .trailing)
            Text("GP").frame(width: col.gp, alignment: .trailing)
            Text("W").frame(width: col.wdl, alignment: .trailing)
            Text("D").frame(width: col.wdl, alignment: .trailing)
            Text("L").frame(width: col.wdl, alignment: .trailing)
            Text("GD").frame(width: col.gd, alignment: .trailing)
            // At AX1 the badges move into the rows' second line, where they carry their
            // own "LAST 5" caption — so this header cell would label an empty column.
            if !isAccessibilitySize {
                Text("Last 5").frame(width: col.form, alignment: .trailing)
            }
        }
        .trackedCaps(size: 11, tracking: 0.4, weight: .semibold, color: .dsFgSecondary)
        // Keep the tight column headers on one line at larger text (else "GP" stacks
        // to "G/P"); they share the rows' fixed widths so they scale down to match.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.leading, Inset.headerLead)
        .padding(.trailing, Inset.headerTrail)
        .padding(.bottom, 8)
    }

    private func card(form: [String: [MatchResult]]) -> some View {
        // The colored left spine is the follow indicator. If the user follows no team,
        // keep every row's bar (edge case) so the table isn't all-grey.
        let followsAnyTeam = viewModel.rows.contains { following.isFollowing($0.club) }
        return VStack(spacing: 0) {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                if index == playoffSpots {
                    playoffLine
                } else if index > 0 {
                    rowDivider
                }
                rowButton(for: row, recent: form[row.club.abbreviation] ?? [],
                          followsAnyTeam: followsAnyTeam)
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
                .dsFont(10, weight: .bold)
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
            .frame(height: DS.hairline)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Row

    private func rowButton(for row: StandingsRow, recent: [MatchResult], followsAnyTeam: Bool) -> some View {
        let isFollowing = following.isFollowing(row.club)
        let accent = row.club.accentColor
        // Rank: accent for your teams, white for everyone else — no below-line dim
        // (below-playoff rows read at full strength, like the rest).
        let rankColor: Color = isFollowing ? .dsAccent : .dsFgPrimary

        return Button {
            path.append(row.club)
        } label: {
            // At AX1 the row is two lines (numbers, then Last 5); below it, one.
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: col.gap) {
                    Text("\(row.rank)")
                        .dsFont(14, weight: .bold, monospacedDigit: true)
                        .foregroundStyle(rankColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // Right-aligned + monospaced so 1–9 sit in the ones position under
                        // the second digit of 10–16, all ending at the same right edge.
                        .frame(width: col.rank, alignment: .trailing)

                    HStack(spacing: 7) {
                        // The crest is the hero (§0): 32pt, ring-free. Secondary elements
                        // around it stay tight so it never has to shrink.
                        TeamLogo(urlString: row.club.logoURL,
                                 teamAbbreviation: row.club.abbreviation,
                                 size: DS.avatarTeams)
                        // Abbreviation demoted to a 14pt label beside the crest.
                        Text(row.club.abbreviation)
                            .dsFont(14, weight: .bold)
                            .tracking(0.3)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(row.points)")
                        .dsFont(17, weight: .heavy, monospacedDigit: true)
                        .foregroundStyle(Color.dsFgPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: col.pts, alignment: .trailing)
                    statCell(row.gamesPlayed, width: col.gp)
                    statCell(row.wins, width: col.wdl)
                    statCell(row.draws, width: col.wdl)
                    statCell(row.losses, width: col.wdl)
                    gdCell(row)
                    if !isAccessibilitySize { formCell(recent) }
                }
                if isAccessibilitySize, !recent.isEmpty {
                    // Second line, right-aligned under the numbers it belongs to, with its
                    // own caption since the column header no longer labels it.
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text("LAST 5")
                            .trackedCaps(size: 10, tracking: 0.4, weight: .semibold, color: .dsFgSecondary)
                        formCell(recent)
                    }
                }
            }
            .padding(.leading, Inset.rowLead)
            .padding(.trailing, Inset.rowTrail)
            // minHeight, not height: the AX1 row is taller, and a fixed height is exactly
            // how text ends up escaping its container (the failure mode this pass exists
            // to avoid). Below AX1 the content is 60pt anyway, so nothing moves.
            .frame(minHeight: isAccessibilitySize ? 96 : 60)
            .background(isFollowing ? Color.dsFollowTint : Color.clear)
            // 3px team-color left spine — the FOLLOW indicator: only your teams get it
            // (inset from the rounded card corners). Follow nobody → every row keeps its
            // bar so the table isn't all-grey.
            .overlay(alignment: .leading) {
                if isFollowing || !followsAnyTeam {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 11)
                }
            }
            // No below-playoff-line dimming — the PLAYOFF LINE divider is the only
            // cutoff cue; every row renders at full opacity for readability.
            .contentShape(Rectangle())   // whole row tappable, incl. padding
        }
        .buttonStyle(.plain)
    }

    private func statCell(_ value: Int, width: CGFloat) -> some View {
        Text("\(value)")
            .dsFont(14, weight: .medium, monospacedDigit: true)
            .foregroundStyle(Color.dsFgSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .trailing)
    }

    /// Goal difference: signed, monospaced. A positive GD reads in white (a strength
    /// signal); zero and negative stay muted like the other secondary stats.
    private func gdCell(_ row: StandingsRow) -> some View {
        Text(row.goalDifferenceText)
            .dsFont(14, weight: .medium, monospacedDigit: true)
            .foregroundStyle(row.goalDifference > 0 ? Color.dsFgPrimary : Color.dsFgSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: col.gd, alignment: .trailing)
    }

    /// Up to five W/D/L badges, oldest → newest (newest on the right). Teams with
    /// fewer than five completed matches show only what they have — no padding.
    private func formCell(_ recent: [MatchResult]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(recent.enumerated()), id: \.offset) { _, result in
                FormBadge(result, size: 13, fontSize: 9)
            }
        }
        .frame(width: col.form, alignment: .trailing)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Tap any club for its full page · Last 5 shows recent results, newest on the right.")
            .dsFont(11.5)
            .lineSpacing(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.dsFgSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 20)
    }

    private func errorView(_ message: String) -> some View {
        RetryStateView(message: message, style: .inline) {
            await viewModel.load()
        }
        .padding(.top, 48)
    }
}

#Preview {
    StandingsView()
        .environment(FollowingStore())
        .environment(MatchStore())
}
