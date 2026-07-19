//
//  EventTimelineRow.swift
//  NWSLApp
//
//  One entry in a match's Play-by-Play: minute · a team-color crest box on the LEFT
//  (scan-by-color) · the event glyph (goal / card / sub / shot / save / foul / corner /
//  offside / VAR) · a primary line (scorer name, or the play label) + detail (assist /
//  "on for" / the ESPN commentary sentence) · and, for a goal, the running scoreline on
//  the right. A goal row gets a team-color wash fading right so big moments stand out.
//
//  Driven by the unified `PlayByPlayItem` (MatchSummary.swift) so both the enriched
//  keyEvents rows and the text-only commentary rows share one component. The team
//  identity (color + crest) is resolved by the caller (MatchDetailView) from `isHome`.
//

import SwiftUI

struct EventTimelineRow: View {
    let item: PlayByPlayItem
    /// Minute-marker tint — the match's temporal-state accent (cyan past/future, orange live).
    var minuteColor: Color = .secondary
    /// The event team's resolved color (left crest box + goal wash).
    var teamColor: Color = .dsFgSecondary
    /// The event team's crest (real art via TeamLogo) for the left box.
    var crestURL: String? = nil
    var crestAbbr: String? = nil

    private var isGoal: Bool { item.kind.isGoal }

    var body: some View {
        HStack(spacing: 11) {
            Text(item.minute)
                .dsFont(13, weight: .bold, monospacedDigit: true)
                // Stoppage minutes ("90'+11'") are long — shrink to one line rather than
                // wrap to three (a lone "'" on its own row); plain minutes stay centered.
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(minuteColor)
                .frame(width: 36, alignment: .center)

            // Team identity on the LEFT — a color-tinted box holding the real crest.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(teamColor.opacity(0.16))
                TeamLogo(urlString: crestURL, teamAbbreviation: crestAbbr, size: 20)
            }
            .frame(width: 30, height: 30)

            iconView.frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.primary)
                    .dsFont(14, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                if let detail = item.detail {
                    Text(detail)
                        .dsFont(11.5)
                        .foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)   // commentary can wrap 2 lines
                }
            }

            Spacer(minLength: 0)

            if isGoal, let score = item.score {
                Text(score)
                    .dsFont(15, weight: .heavy, design: .rounded, monospacedDigit: true)
                    .foregroundStyle(Color.dsFgPrimary)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 2)
        .padding(.trailing, 8)
        // Goals get a team-color wash fading right — scan the timeline by color.
        .background {
            if isGoal {
                LinearGradient(
                    stops: [
                        .init(color: teamColor.opacity(0.20), location: 0),
                        .init(color: teamColor.opacity(0), location: 0.72),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
            }
        }
    }

    // One glyph per play kind. Cards are drawn shapes; the rest are SF Symbols.
    @ViewBuilder
    private var iconView: some View {
        switch item.kind {
        case .goal:
            symbol("soccerball.inverse", size: 15, color: .dsFgPrimary)
        case .substitution:
            SubstitutionArrows()
        case .yellowCard:
            cardRect(.dsWarning)
        case .redCard:
            cardRect(.dsLive)
        case .shotOnTarget:
            symbol("soccerball", size: 13, color: .dsSuccess)   // on frame → saved/scored
        case .shotOffTarget, .shotBlocked:
            symbol("soccerball", size: 13, color: .dsFgTertiary)
        case .foul:
            symbol("exclamationmark.triangle.fill", size: 12, color: .dsWarning)
        case .corner:
            symbol("flag.fill", size: 12, color: .dsFgSecondary)
        case .offside:
            symbol("flag.slash.fill", size: 12, color: .dsFgTertiary)
        case .varReview:
            symbol("tv.fill", size: 11, color: .dsFgSecondary)
        case .other:
            symbol("circle.fill", size: 7, color: .secondary)
        }
    }

    private func symbol(_ name: String, size: CGFloat, color: Color) -> some View {
        Image(systemName: name).dsFont(size).foregroundStyle(color)
    }

    private func cardRect(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 13)
    }
}

/// The standard substitution marker: a green up-arrow (coming on) beside a red
/// down-arrow (going off).
private struct SubstitutionArrows: View {
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "arrow.up").foregroundStyle(Color.dsSuccess)
            Image(systemName: "arrow.down").foregroundStyle(Color.dsError)
        }
        .dsFont(11, weight: .bold)
    }
}
