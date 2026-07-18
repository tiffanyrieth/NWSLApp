//
//  CombinedPitchView.swift
//  NWSLApp
//
//  Both teams' starting XIs on ONE pitch (design handoff `MatchDetailParts.jsx` →
//  `MDPitch`): the home side fills the top half (its GK at the top edge), the away
//  side the bottom half (its GK at the bottom), so the two attacks meet at the
//  halfway line — the way a broadcast formation graphic reads.
//
//  Placement reuses `FormationPitchView.layout` (the formation-string row logic +
//  abbreviation fallback) and just remaps each team's normalized Y into its half.
//  Falls back to per-team lists in the caller when either side can't be placed.
//

import SwiftUI

struct CombinedPitchView: View {
    struct Side {
        let abbr: String
        let formation: String?
        let players: [MatchPlayer]   // starters
        let accent: ResolvedTeamColor
        /// Team's ESPN club id — lets a tapped player fetch her full roster bio + stats.
        var clubID: String? = nil
    }

    let home: Side
    let away: Side

    /// True only when BOTH teams can be drawn (else the caller lists them).
    static func supports(home: Side, away: Side) -> Bool {
        FormationPitchView.supports(formation: home.formation, players: home.players)
            && FormationPitchView.supports(formation: away.formation, players: away.players)
    }

    private let line = Color.dsPitchLine

    var body: some View {
        let homePlaced = FormationPitchView
            .layout(formation: home.formation, players: home.players)
            .map { remap($0, top: true) }
        let awayPlaced = FormationPitchView
            .layout(formation: away.formation, players: away.players)
            .map { remap($0, top: false) }

        VStack(spacing: 10) {
            formationHeader
            GeometryReader { geo in
                ZStack {
                    pitch
                    ForEach(homePlaced) { dot in
                        playerDot(dot.player, side: home)
                            .position(x: dot.point.x * geo.size.width, y: dot.point.y * geo.size.height)
                    }
                    ForEach(awayPlaced) { dot in
                        playerDot(dot.player, side: away)
                            .position(x: dot.point.x * geo.size.width, y: dot.point.y * geo.size.height)
                    }
                }
            }
            .aspectRatio(0.66, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    /// A pitch marker that pushes the player's stat screen when tapped (same PlayerDetailView
    /// as Teams → team → player). Falls back to a plain, non-tappable dot when ESPN gave no
    /// athlete id. `.buttonStyle(.plain)` keeps the disc's look; the destination is registered
    /// in MatchDetailView (`navigationDestination(for: LineupPlayerRef.self)`).
    @ViewBuilder
    private func playerDot(_ player: MatchPlayer, side: Side) -> some View {
        if let athlete = player.asAthlete {
            NavigationLink(value: LineupPlayerRef(athlete: athlete,
                                                  clubID: side.clubID,
                                                  accentHex: DesignTeamColors.hex(for: side.abbr))) {
                PitchDot(player: player, accent: side.accent)
            }
            .buttonStyle(.plain)
        } else {
            PitchDot(player: player, accent: side.accent)
        }
    }

    // "WAS 4-2-3-1 · ORL 4-3-3" — each side in its own color.
    private var formationHeader: some View {
        (Text(label(home)).foregroundColor(home.accent.fill)
         + Text("  ·  ").foregroundColor(.dsFgQuaternary)
         + Text(label(away)).foregroundColor(away.accent.fill))
            .dsFont(11, weight: .semibold)
            .tracking(0.5)
            .frame(maxWidth: .infinity)
    }

    private func label(_ side: Side) -> String {
        if let f = side.formation, !f.isEmpty { return "\(side.abbr) \(f)" }
        return side.abbr
    }

    /// Remap a full-pitch normalized Y (GK ≈ 0.88, forwards ≈ 0.15) into a half:
    /// home → top (GK 0.06 → forwards 0.45), away → bottom (GK 0.94 → forwards 0.55).
    private func remap(_ p: FormationPitchView.PlacedPlayer, top: Bool) -> FormationPitchView.PlacedPlayer {
        let defensiveness = 0.88 - p.point.y            // 0 (GK) … ~0.73 (forwards)
        let t = min(max(defensiveness / 0.73, 0), 1)    // 0 (GK) … 1 (forwards)
        let newY = top ? 0.06 + 0.39 * t                // 0.06 … 0.45
                       : 0.94 - 0.39 * t                // 0.94 … 0.55
        return FormationPitchView.PlacedPlayer(
            id: (top ? "h-" : "a-") + p.id,
            player: p.player,
            point: CGPoint(x: p.point.x, y: newY)
        )
    }

    // Full pitch with both penalty boxes, halfway line, and center circle.
    private var pitch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.radiusMd)
                .fill(LinearGradient(colors: [.dsPitch, .dsPitchBottom],
                                     startPoint: .top, endPoint: .bottom))
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                    let boxW = w * 0.5, boxH = h * 0.12, boxX = (w - boxW) / 2
                    p.addRect(CGRect(x: boxX, y: 0, width: boxW, height: boxH))
                    p.addRect(CGRect(x: boxX, y: h - boxH, width: boxW, height: boxH))
                }
                .stroke(line, lineWidth: 1)
                Circle()
                    .stroke(line, lineWidth: 1)
                    .frame(width: w * 0.24, height: w * 0.24)
                    .position(x: w / 2, y: h / 2)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMd).stroke(line, lineWidth: 1))
    }
}
