//
//  FormationPitchView.swift
//  NWSLApp
//
//  Renders a team's starting XI on a vertical pitch. Each starter is a dot at a
//  position derived from their ESPN position abbreviation (G / RB / CD-R / AM-L /
//  CF-R …), which encodes both the line (defence → attack) and the left/center/
//  right placement.
//
//  Why not place by formationPlace + the formation string? ESPN's formationPlace
//  is NOT row-major — for a 4-2-3-1 it interleaves a midfielder among the
//  fullbacks — so a string→slot table would misplace players. The abbreviation,
//  by contrast, names each player's role directly, so we classify by it and then
//  distribute each line's players evenly across the width (which can't collide
//  and needs no per-formation table — it draws any standard shape, a superset of
//  the spec's five). The formation string is shown only as a label.
//
//  Never a broken pitch: if there aren't 11 startable players, or any lacks a
//  classifiable position, `supports(...)` returns false and the caller shows the
//  list lineup instead.
//
//  TEMP (headshots): dots are jersey-number monograms for now. Branch 2 swaps the
//  dot fill for a real HeadshotStore photo (see match-detail-v2-spec §7c/§8a) —
//  the dot frame + fallback monogram stay as the placeholder.
//

import SwiftUI

struct FormationPitchView: View {
    let formation: String?
    let players: [MatchPlayer]   // starters
    let teamAccentHex: String?

    /// Whether a pitch can be drawn for these starters (else the caller lists them).
    static func supports(formation: String?, players: [MatchPlayer]) -> Bool {
        let startable = players.filter { ($0.position?.abbreviation?.isEmpty == false) }
        return startable.count == 11
    }

    /// Pitch lines: faint white over green.
    private let line = Color.white.opacity(0.35)

    var body: some View {
        let placed = layout()
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack {
                    pitch
                    ForEach(placed) { dot in
                        playerDot(dot.player)
                            .position(
                                x: dot.point.x * geo.size.width,
                                y: dot.point.y * geo.size.height
                            )
                    }
                }
            }
            .aspectRatio(0.66, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pitch background

    private var pitch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.18, green: 0.42, blue: 0.24),
                                 Color(red: 0.13, green: 0.34, blue: 0.19)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    // Halfway line.
                    p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                    // Penalty boxes (top = attack, bottom = own goal).
                    let boxW = w * 0.5, boxH = h * 0.16, boxX = (w - boxW) / 2
                    p.addRect(CGRect(x: boxX, y: 0, width: boxW, height: boxH))
                    p.addRect(CGRect(x: boxX, y: h - boxH, width: boxW, height: boxH))
                }
                .stroke(line, lineWidth: 1)
                // Center circle.
                Circle()
                    .stroke(line, lineWidth: 1)
                    .frame(width: w * 0.28, height: w * 0.28)
                    .position(x: w / 2, y: h / 2)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(line, lineWidth: 1))
    }

    // MARK: - Player dot (TEMP jersey-number monogram)

    private func playerDot(_ player: MatchPlayer) -> some View {
        let accent = Color.teamAccent(hex: teamAccentHex)
        return VStack(spacing: 3) {
            ZStack {
                Circle().fill(Color.teamFillOnDark(hex: teamAccentHex))
                Circle().stroke(.white.opacity(0.7), lineWidth: 1.5)
                Text(player.jersey ?? "")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent.on)
            }
            .frame(width: 30, height: 30)
            Text(lastName(player))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(radius: 1)
        }
        .frame(width: 60)
    }

    private func lastName(_ player: MatchPlayer) -> String {
        player.athlete?.lastName
            ?? player.athlete?.shortName
            ?? player.athlete?.displayName
            ?? ""
    }

    // MARK: - Layout

    private struct PlacedPlayer: Identifiable {
        let id: String
        let player: MatchPlayer
        let point: CGPoint   // normalized 0…1, y already in screen space (top = attack)
    }

    /// The six vertical bands a player can fall into, own-goal → attack.
    private enum Line: Double, CaseIterable {
        case gk = 0.08, def = 0.26, dm = 0.40, mid = 0.55, am = 0.70, fwd = 0.87
    }

    /// Classify each starter into (line, horizontal hint), then spread each line's
    /// players evenly across the width sorted by that hint. y is flipped so attack
    /// sits at the top of the screen.
    private func layout() -> [PlacedPlayer] {
        let starters = players.filter { ($0.position?.abbreviation?.isEmpty == false) }
        // Group by line, preserving each player's left→right ordering hint.
        var byLine: [Line: [(player: MatchPlayer, hint: Double)]] = [:]
        for player in starters {
            let (line, hint) = slot(player)
            byLine[line, default: []].append((player, hint))
        }

        var placed: [PlacedPlayer] = []
        for line in Line.allCases {
            guard let group = byLine[line] else { continue }
            let sorted = group.sorted { $0.hint < $1.hint }
            let n = sorted.count
            for (i, entry) in sorted.enumerated() {
                let x = n == 1 ? 0.5 : 0.15 + 0.70 * Double(i) / Double(n - 1)
                let y = 1 - line.rawValue   // flip: attack at top
                placed.append(PlacedPlayer(
                    id: entry.player.athlete?.id ?? "\(line)-\(i)",
                    player: entry.player,
                    point: CGPoint(x: x, y: y)
                ))
            }
        }
        return placed
    }

    /// Maps a position abbreviation to its vertical band + a horizontal ordering
    /// hint (−2 wide-left … +2 wide-right; 0 center). Only the relative order
    /// matters — exact x is assigned by even distribution within the line.
    private func slot(_ player: MatchPlayer) -> (Line, Double) {
        let raw = (player.position?.abbreviation ?? "").uppercased()
        let parts = raw.split(separator: "-").map(String.init)
        let base = parts.first ?? raw
        let suffix = parts.count > 1 ? parts[1] : ""

        let sign: Double = {
            if suffix == "R" || base.hasPrefix("R") { return 1 }
            if suffix == "L" || base.hasPrefix("L") { return -1 }
            return 0
        }()
        let wide: Set<String> = ["RB", "LB", "RM", "LM", "RW", "LW", "RWB", "LWB"]
        let magnitude: Double = wide.contains(base) ? 2 : (sign == 0 ? 0 : 1)
        let hint = sign * magnitude

        return (line(forBase: base), hint)
    }

    private func line(forBase base: String) -> Line {
        switch base {
        case "G", "GK":
            return .gk
        case "DM", "CDM", "DMF":
            return .dm
        case "AM", "CAM", "RAM", "LAM", "AMF":
            return .am
        case "F", "CF", "ST", "S", "SS", "W", "RW", "LW", "RF", "LF", "FW":
            return .fwd
        case "D", "CB", "CD", "RB", "LB", "RCB", "LCB", "WB", "RWB", "LWB", "SW", "FB":
            return .def
        default:
            return .mid   // M, CM, RM, LM, RCM, LCM, MF, and anything unrecognized
        }
    }
}
