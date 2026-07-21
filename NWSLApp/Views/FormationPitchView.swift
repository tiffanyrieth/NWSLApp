//
//  FormationPitchView.swift
//  NWSLApp
//
//  Renders a team's starting XI on a vertical pitch.
//
//  Row structure comes from the FORMATION STRING ("4-2-3-1" → rows [4,2,3,1]),
//  which is the only reliable source of how many lines there are and how many
//  players each holds — ESPN's per-player abbreviations are specific in most
//  matches but generic ("M" for every midfielder) in some, which made a 4-2-3-1
//  collapse into a 4-5-1 blob. So we slice the 10 outfielders into the formation's
//  rows after ordering them defence → attack (by abbreviation line, then
//  formationPlace), and only USE the abbreviation for the left/right ordering
//  within a row. If the formation string doesn't parse cleanly we fall back to
//  classifying purely by abbreviation band.
//
//  Never a broken pitch: if there aren't 11 startable players (`supports(...)`),
//  the caller shows the list lineup instead.
//
//  TEMP (headshots): dots are jersey-number monograms for now. Branch 2 swaps the
//  dot fill for a real HeadshotStore photo (see match-detail-v2-spec §7c/§8a) —
//  the dot frame + fallback monogram stay as the placeholder.
//

import SwiftUI

struct FormationPitchView: View {
    let formation: String?
    let players: [MatchPlayer]   // starters
    /// The team's resolved match color (distinct from the opponent's, legible on
    /// the pitch) — fill for the dot, onText for the jersey number.
    let accent: ResolvedTeamColor
    /// Team abbreviation, used to color the pushed player-stat screen when a dot is
    /// tapped. nil ⇒ dots stay non-tappable (no navigation target).
    var abbr: String? = nil
    /// Team's ESPN club id — lets a tapped player fetch her full roster bio + stats.
    var clubID: String? = nil

    /// Whether a pitch can be drawn for these starters (else the caller lists them).
    static func supports(formation: String?, players: [MatchPlayer]) -> Bool {
        let startable = players.filter { ($0.position?.abbreviation?.isEmpty == false) }
        return startable.count == 11
    }

    /// Pitch lines: faint white over green (design token).
    private let line = Color.dsPitchLine

    /// A pitch marker that pushes the player's stat screen when tapped (same PlayerDetailView
    /// as Teams → team → player). Non-tappable when we have no athlete id or no `abbr` to
    /// color the destination.
    ///
    /// CLOSURE-based NavigationLink (not value + `navigationDestination(for:)`) — see the same
    /// note in CombinedPitchView: a for-based destination registered on the pushed MatchDetail
    /// is mis-scoped and double-pushed the screen (2026-07-18 bug); a self-contained closure
    /// link works in any host stack.
    @ViewBuilder
    private func playerDot(_ player: MatchPlayer) -> some View {
        if let abbr, let athlete = player.asAthlete {
            NavigationLink {
                LineupPlayerStatsView(ref: LineupPlayerRef(athlete: athlete,
                                                           clubID: clubID,
                                                           accentHex: DesignTeamColors.hex(for: abbr)))
            } label: {
                PitchDot(player: player, accent: accent)
            }
            .buttonStyle(.plain)
        } else {
            PitchDot(player: player, accent: accent)
        }
    }

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
            .aspectRatio(0.70, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pitch background

    private var pitch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.radiusMd)
                .fill(
                    LinearGradient(
                        colors: [.dsPitch, .dsPitchBottom],
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
        .overlay(RoundedRectangle(cornerRadius: DS.radiusMd).stroke(line, lineWidth: 1))
    }

    // MARK: - Layout

    struct PlacedPlayer: Identifiable {
        let id: String
        let player: MatchPlayer
        let point: CGPoint   // normalized 0…1, y already in screen space (top = attack)
    }

    /// The six vertical bands the abbreviation fallback can use, own-goal → attack.
    /// (gk/fwd kept off the very edges so dot labels don't clip — #20.)
    private enum Line: Double, CaseIterable {
        case gk = 0.12, def = 0.27, dm = 0.40, mid = 0.55, am = 0.70, fwd = 0.85
    }

    /// Placed starters. Prefers the formation string for row structure; falls back
    /// to abbreviation bands when it doesn't parse. `static` + the typealias below
    /// so the layout is unit-testable without a live view.
    func layout() -> [PlacedPlayer] {
        Self.layout(formation: formation, players: players)
    }

    static func layout(formation: String?, players: [MatchPlayer]) -> [PlacedPlayer] {
        let starters = players.filter { ($0.position?.abbreviation?.isEmpty == false) }
        let goalkeepers = starters.filter { line(forBase: base(of: $0)) == .gk }
        let outfield = starters.filter { line(forBase: base(of: $0)) != .gk }

        // Preferred: the formation string defines the rows (e.g. "4-2-3-1" → [4,2,3,1]).
        if let rows = parseFormationRows(formation), rows.reduce(0, +) == outfield.count {
            return placeByFormation(goalkeepers: goalkeepers, outfield: outfield, rows: rows)
        }
        // Fallback: classify purely by abbreviation band.
        return placeByBands(starters)
    }

    /// Slice the outfielders (ordered defence → attack) into the formation's rows,
    /// then place each row across an evenly-spaced height.
    private static func placeByFormation(goalkeepers: [MatchPlayer], outfield: [MatchPlayer], rows: [Int]) -> [PlacedPlayer] {
        var placed: [PlacedPlayer] = []
        if let gk = goalkeepers.first {
            placed.append(PlacedPlayer(id: gk.athlete?.id ?? "gk", player: gk,
                                       point: CGPoint(x: 0.5, y: 1 - Line.gk.rawValue)))
        }
        // Order defence → attack: by line rank, then formationPlace as a tiebreak.
        let ordered = outfield.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return (a.formationPlaceValue ?? .max) < (b.formationPlaceValue ?? .max)
        }
        let n = rows.count
        var index = 0
        for (rowIndex, count) in rows.enumerated() {
            let row = Array(ordered[index ..< min(index + count, ordered.count)])
            index += count
            let bandY = n == 1 ? 0.5 : 0.27 + (0.85 - 0.27) * Double(rowIndex) / Double(n - 1)
            let sorted = row.sorted { hint(of: $0) < hint(of: $1) }
            let m = sorted.count
            for (i, player) in sorted.enumerated() {
                let x = m == 1 ? 0.5 : 0.15 + 0.70 * Double(i) / Double(m - 1)
                placed.append(PlacedPlayer(id: player.athlete?.id ?? "\(rowIndex)-\(i)",
                                           player: player, point: CGPoint(x: x, y: 1 - bandY)))
            }
        }
        return placed
    }

    /// Abbreviation-band fallback: group by classified line, distribute each evenly.
    private static func placeByBands(_ starters: [MatchPlayer]) -> [PlacedPlayer] {
        var byLine: [Line: [MatchPlayer]] = [:]
        for player in starters {
            byLine[line(forBase: base(of: player)), default: []].append(player)
        }
        var placed: [PlacedPlayer] = []
        for band in Line.allCases {
            guard let group = byLine[band] else { continue }
            let sorted = group.sorted { hint(of: $0) < hint(of: $1) }
            let n = sorted.count
            for (i, player) in sorted.enumerated() {
                let x = n == 1 ? 0.5 : 0.15 + 0.70 * Double(i) / Double(n - 1)
                placed.append(PlacedPlayer(id: player.athlete?.id ?? "\(band)-\(i)",
                                           player: player, point: CGPoint(x: x, y: 1 - band.rawValue)))
            }
        }
        return placed
    }

    /// "4-2-3-1" → [4,2,3,1]; nil unless it's 2–5 positive numbers.
    private static func parseFormationRows(_ formation: String?) -> [Int]? {
        guard let formation else { return nil }
        let rows = formation.split(separator: "-").compactMap { Int($0) }
        guard (2...5).contains(rows.count), rows.allSatisfy({ $0 > 0 }) else { return nil }
        return rows
    }

    private static func rank(_ player: MatchPlayer) -> Int {
        Line.allCases.firstIndex(of: line(forBase: base(of: player))) ?? 3
    }

    /// The base of a position abbreviation (before any "-R"/"-L" suffix), e.g.
    /// "CD-R" → "CD".
    private static func base(of player: MatchPlayer) -> String {
        let raw = (player.position?.abbreviation ?? "").uppercased()
        return raw.split(separator: "-").first.map(String.init) ?? raw
    }

    /// Horizontal ordering hint within a row (−2 wide-left … +2 wide-right; 0
    /// center). Only the relative order matters — exact x is assigned by even
    /// distribution.
    private static func hint(of player: MatchPlayer) -> Double {
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
        return sign * magnitude
    }

    private static func line(forBase base: String) -> Line {
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
