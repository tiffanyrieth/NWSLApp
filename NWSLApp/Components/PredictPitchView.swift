//
//  PredictPitchView.swift
//  NWSLApp
//
//  The graded XI on a pitch — the centrepiece of Predict the XI's results screen (2026-07-28).
//  Your eleven picks laid out in the shape you actually chose, each marked with how she turned out,
//  revealed a line at a time.
//
//  ⚠️ POSITIONS ARE DERIVED FROM THE FORMATION, never hardcoded. The design handoff specified four
//  fixed band centres (84% / 64% / 42% / 17%), which is right for a 4-3-3 and wrong for a third of
//  the menu: `Formation.common` includes 4-2-3-1 and 4-1-4-1, which have FIVE rows. Rows are spread
//  between fixed top and bottom margins instead, matching how `FormationPitchView` places a real
//  lineup, so every selectable shape lays out correctly.
//
//  ⚠️ Iterate `formation.displayRowGroups` (identifiable row VALUES), never `ForEach(indices)`.
//  Index-subscripting a recomputed array is what crashed the picker out of bounds when a formation
//  change shrank the row count (2026-07-25).
//
//  The three node states come from `PredictPickResult.State` and are not "right/wrong": a pick who
//  started in another band still banked her 3 points, so she reads AMBER with the band she actually
//  played — never red, and never with a substitute's name under her, which would imply a
//  slot-for-slot swap the scorer never performs.
//

import SwiftUI

struct PredictPitchView: View {
    let formation: Formation
    let picks: [PredictPickResult]
    /// Bands revealed so far. Everything else renders dimmed and neutral — no result colour, no
    /// percentage, nothing that would give the line away before its beat.
    let revealedBands: Set<PositionGroup>
    let accent: Color

    /// Top and bottom of the band spread, as a share of pitch height. The user attacks UPWARD, so
    /// the keeper sits at `bottom` and the front line at `top`.
    private let top: CGFloat = 0.15
    private let bottom: CGFloat = 0.86

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                PredictPitchMarkings()
                    .stroke(Color.dsPitchLine, lineWidth: 1)

                ForEach(formation.displayRowGroups) { row in
                    ForEach(Array(row.slots.enumerated()), id: \.element.id) { position, slot in
                        node(for: slot,
                             at: point(row: row.row, position: position, of: row.slots.count, in: geo.size))
                    }
                }

                Text(formation.raw.replacingOccurrences(of: "-", with: "\u{2011}"))   // non-breaking hyphens
                    .dsFont(10, weight: .bold)
                    .tracking(0.8)
                    .foregroundStyle(Color.dsFgPrimary.opacity(0.34))
                    .padding(.leading, 10)
                    .padding(.top, 8)
            }
        }
        .frame(height: 400)
        .background(
            LinearGradient(colors: [.dsPitch, .dsPitchBottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous)
                .stroke(Color.dsFgPrimary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Layout

    /// Row 0 is the keeper; the highest row is the front line. Spread evenly between the margins so
    /// a 4-row and a 5-row formation both fill the pitch.
    private func point(row: Int, position: Int, of count: Int, in size: CGSize) -> CGPoint {
        let maxRow = max(1, (formation.displayRowGroups.map(\.row).max() ?? 1))
        let y = bottom - (bottom - top) * CGFloat(row) / CGFloat(maxRow)
        // Evenly spaced within the row, inset so a 4-across defence doesn't clip the touchline.
        let x = CGFloat(position * 2 + 1) / CGFloat(count * 2)
        let inset: CGFloat = 0.08
        return CGPoint(x: size.width * (inset + x * (1 - inset * 2)), y: size.height * y)
    }

    private func pick(for slot: Formation.Slot) -> PredictPickResult? {
        picks.first { $0.slot.index == slot.index }
    }

    // MARK: - Node

    @ViewBuilder
    private func node(for slot: Formation.Slot, at point: CGPoint) -> some View {
        let pick = pick(for: slot)
        let shown = revealedBands.contains(slot.group)
        let tint = shown ? color(for: pick?.state) : Color.dsFgQuaternary

        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.dsBgTertiary)
                    .overlay(Circle().stroke(tint, lineWidth: 2))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(initials(pick?.name))
                            // Fixed-size container ⇒ fixed-size text (the DS monogram exemption):
                            // a scaled monogram would overflow a 34pt disc at AX1.
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(tint)
                    )
                if shown, let state = pick?.state {
                    Image(systemName: state.started ? "checkmark" : "xmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.dsBgPrimary)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(tint))
                        .overlay(Circle().stroke(Color.dsBgPrimary, lineWidth: 1.5))
                        .offset(x: 5, y: -4)
                }
            }
            if shown {
                Text(pick?.name ?? slot.group.shortLabel)
                    .dsFont(10, weight: .semibold)
                    .foregroundStyle(started(pick) ? Color.dsFgPrimary : Color.dsFgTertiary)
                    .strikethrough(pick.map { !$0.state.started } ?? false)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let share = pick?.communityShare {
                    Text(Self.percent(share)).dsFont(9, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
                }
                if case .startedOffBand(let actual) = pick?.state {
                    Text("played \(actual.shortLabel)")
                        .dsFont(9, weight: .bold)
                        .foregroundStyle(Color.dsWarning)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 88)
        .opacity(shown ? 1 : 0.18)
        .scaleEffect(shown ? 1 : 0.82)
        .position(point)
        // One node = one a11y element, and its label always describes the FINAL state even mid-
        // reveal: the animation is visual, and a VoiceOver user must never have to wait for it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: slot, pick: pick))
    }

    private func started(_ pick: PredictPickResult?) -> Bool { pick?.state.started ?? false }

    private func color(for state: PredictPickResult.State?) -> Color {
        switch state {
        case .startedInBand: return .dsSuccess
        case .startedOffBand: return .dsWarning
        case .didNotStart: return .dsError
        case nil: return .dsFgQuaternary
        }
    }

    private func initials(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "—" }
        return name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    private func accessibilityLabel(for slot: Formation.Slot, pick: PredictPickResult?) -> String {
        guard let pick else { return "\(slot.group.shortLabel), empty" }
        switch pick.state {
        case .startedInBand: return "\(pick.name), \(slot.group.shortLabel), started"
        case .startedOffBand(let actual):
            return "\(pick.name), you played her at \(slot.group.shortLabel), started in \(actual.shortLabel)"
        case .didNotStart: return "\(pick.name), \(slot.group.shortLabel), did not start"
        }
    }
}

/// Pitch markings at the keeper's end — outer box, one line across, penalty and six-yard boxes, and
/// the centre circle. Drawn as one `Shape` (a single stroked path) rather than stacked overlays.
private struct PredictPitchMarkings: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02)
        path.addRect(inset)

        // The halfway line sits where the centre circle is drawn.
        let midY = rect.minY + rect.height * 0.30
        path.move(to: CGPoint(x: inset.minX, y: midY))
        path.addLine(to: CGPoint(x: inset.maxX, y: midY))

        // Penalty box + six-yard box at the bottom (the goalkeeper's end — the user attacks up).
        let penalty = CGRect(x: rect.midX - rect.width * 0.22, y: inset.maxY - rect.height * 0.16,
                             width: rect.width * 0.44, height: rect.height * 0.16)
        path.addRect(penalty)
        let six = CGRect(x: rect.midX - rect.width * 0.09, y: inset.maxY - rect.height * 0.06,
                         width: rect.width * 0.18, height: rect.height * 0.06)
        path.addRect(six)

        let radius = rect.width * 0.20
        path.addEllipse(in: CGRect(x: rect.midX - radius, y: midY - radius,
                                   width: radius * 2, height: radius * 2))
        return path
    }
}
