//
//  PredictPitchView.swift
//  NWSLApp
//
//  The REAL starting XI on a pitch, marked with what the user called — the centrepiece of Predict
//  the XI's results screen. Reworked 2026-07-28 (owner review): it shows the actual lineup, not the
//  user's guess, and it is deliberately the SAME FIELD the picker uses.
//
//  ⚠️ ANTI-DRIFT CONTRACT: this view and `XIPickerView.pitchGrid` share ONE field —
//  `.predictPitchChrome()` (gradient + markings + border) — plus the same 46pt `PlayerHeadshot`
//  cells, 62pt cell width and row stacking. You build your XI on a field and get graded on that
//  same field; restyling means restyling the shared chrome, which restyles both by construction.
//  The Match Detail lineup view (`FormationPitchView`) is intentionally its own thing — it shows
//  BOTH teams.
//
//  ⚠️ TWO STATES ONLY: green ✓ you called her, red ✗ you missed her. The old third state (amber
//  "played MID") was cut — it explained a scoring subtlety on a surface that should read at a
//  glance; the position bonus lives in the point breakdown. And per the owner's labeling rule, the
//  screen carries a legend line — a mark nobody explains is an apple on a pitch.
//

import SwiftUI

struct PredictPitchView: View {
    /// The real XI in lineup order (ESPN formation-place order — index i maps to formation slot i).
    let starters: [PredictStarterResult]
    /// The ACTUAL formation, when ESPN's string parsed. nil → rows fall back to position bands.
    let formation: Formation?
    /// Bands revealed so far; unrevealed rows render dimmed and unmarked.
    let revealedBands: Set<PositionGroup>

    var body: some View {
        VStack(spacing: 16) {
            // Iterate identifiable ROW VALUES — never `ForEach(indices)`, which crashed the picker
            // out-of-bounds when a row count shrank (see Formation.DisplayRow).
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row.starters) { starter in
                        starterCell(starter)
                    }
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .predictPitchChrome()
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let id: Int
        let starters: [PredictStarterResult]
    }

    /// Attack first (top of the field), keeper last — the picker's orientation. Preferred source is
    /// the ACTUAL formation's rows (starter i ↔ slot i, the same mapping `FormationPitchView` uses);
    /// when ESPN's formation string doesn't parse, fall back to grouping by position band, which
    /// always renders something honest.
    private var rows: [Row] {
        if let formation, starters.count == formation.slots.count {
            return formation.displayRowGroups.map { group in
                Row(id: group.row, starters: group.slots.compactMap { slot in
                    starters.indices.contains(slot.index) ? starters[slot.index] : nil
                })
            }
        }
        let bands: [PositionGroup] = [.fwd, .mid, .def, .gk]
        return bands.enumerated().compactMap { offset, band in
            let inBand = starters.filter { $0.group == band }
            return inBand.isEmpty ? nil : Row(id: offset, starters: inBand)
        }
    }

    // MARK: - Cell

    private func starterCell(_ starter: PredictStarterResult) -> some View {
        let shown = revealedBands.contains(starter.group)
        let tint: Color = starter.called ? .dsSuccess : .dsError
        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                PlayerHeadshot(athleteID: starter.athleteID, size: 46) {
                    // Fallback monogram — fixed-size text in a fixed-size disc (the DS exemption).
                    ZStack {
                        Circle().fill(Color.white.opacity(0.14))
                        Text(initials(starter.name))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                }
                .overlay(Circle().stroke(shown ? tint : Color.white.opacity(0.35), lineWidth: shown ? 2 : 1))
                if shown {
                    Image(systemName: starter.called ? "checkmark" : "xmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(Color.dsBgPrimary)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(tint))
                        .overlay(Circle().stroke(Color.dsPitch, lineWidth: 1.5))
                        .offset(x: 4, y: -3)
                }
            }
            Text(shortName(starter.name))
                .dsFont(13, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 62)
        .opacity(shown ? 1 : 0.18)
        .scaleEffect(shown ? 1 : 0.82)
        // One node = one a11y element, and the label always describes the FINAL state — the
        // animation is visual only; VoiceOver never waits for it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(starter.name), \(starter.group.shortLabel), \(starter.called ? "you called her" : "you missed her")")
    }

    // MARK: - Helpers

    /// "Sandy MacIver" → "S. MacIver" — the picker's name format, so the two fields match.
    private func shortName(_ full: String) -> String {
        let parts = full.split(separator: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return full }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
}
