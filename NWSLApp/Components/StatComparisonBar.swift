//
//  StatComparisonBar.swift
//  NWSLApp
//
//  One head-to-head stat row: the home value (left) and away value (right) of a
//  labelled stat, over a single split track whose fill widths show the share
//  each team owns (possession, shots, passes, …). Team-tinted so the bar reads
//  at a glance which side dominated.
//
//  Used in the past-match Stats tab (from the summary boxscore) and the
//  future-match "Season Comparison" preview (from derived season averages), so
//  it takes plain numbers + display strings rather than any match-specific type.
//

import SwiftUI

struct StatComparisonBar: View {
    let label: String
    /// Raw values used only to size the bar split (not shown).
    let home: Double
    let away: Double
    /// What the user reads — pre-formatted by the caller ("61", "0.9" → "90%", …).
    let homeDisplay: String
    let awayDisplay: String
    var homeColor: Color = .dsAccent
    var awayColor: Color = .dsFgSecondary

    /// Home's share of the track. Equal split when both are zero (no data) so the
    /// bar never collapses to one side or divides by zero.
    private var homeFraction: Double {
        let total = home + away
        guard total > 0 else { return 0.5 }
        return home / total
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(homeDisplay)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(homeColor)
                    .frame(width: 52, alignment: .leading)
                Text(label)
                    .trackedCaps(size: 10, tracking: 1, weight: .semibold)
                    .frame(maxWidth: .infinity)
                Text(awayDisplay)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(awayColor)
                    .frame(width: 52, alignment: .trailing)
            }

            // Split track: home fill | away fill (away slightly dimmed, per spec).
            GeometryReader { geo in
                let homeWidth = max(0, geo.size.width * homeFraction - 2)
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(homeColor)
                        .frame(width: homeWidth)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(awayColor.opacity(0.85))
                }
            }
            .frame(height: 5)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StatComparisonBar(label: "Possession", home: 61, away: 39,
                          homeDisplay: "61%", awayDisplay: "39%",
                          homeColor: .red, awayColor: .blue)
        StatComparisonBar(label: "Shots", home: 12, away: 8,
                          homeDisplay: "12", awayDisplay: "8",
                          homeColor: .red, awayColor: .blue)
    }
    .padding()
}
