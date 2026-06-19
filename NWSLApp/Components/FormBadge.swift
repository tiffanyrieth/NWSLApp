//
//  FormBadge.swift
//  NWSLApp
//
//  A W/D/L recent-form badge (design handoff `MatchDetailParts.jsx` →
//  `MDFormBadge`): a small rounded square tinted by the result, used in the
//  future-match "Recent Form" rows.
//

import SwiftUI

struct FormBadge: View {
    enum Result { case win, draw, loss }
    let result: Result
    /// Badge edge length. Defaults to the original 22pt (MatchDetail's Recent Form);
    /// Standings passes a smaller value for its dense Last-5 column.
    var size: CGFloat = 22
    /// Letter point size. Defaults to 11pt (the original look at size 22).
    var fontSize: CGFloat = 11

    init(result: Result, size: CGFloat = 22, fontSize: CGFloat = 11) {
        self.result = result
        self.size = size
        self.fontSize = fontSize
    }

    /// Convenience over the shared `MatchResult` domain type, so callers holding a
    /// `MatchResult` (e.g. `RecentForm`) don't repeat the mapping.
    init(_ matchResult: MatchResult, size: CGFloat = 22, fontSize: CGFloat = 11) {
        let mapped: Result
        switch matchResult {
        case .win: mapped = .win
        case .draw: mapped = .draw
        case .loss: mapped = .loss
        }
        self.init(result: mapped, size: size, fontSize: fontSize)
    }

    // Corner radius scales with the badge so it reads the same at any size
    // (size 22 → 5 = DS.radiusXs; size 13 → 3, matching the mock).
    private var cornerRadius: CGFloat { (size * 0.23).rounded() }

    private var letter: String {
        switch result {
        case .win: return "W"
        case .draw: return "D"
        case .loss: return "L"
        }
    }

    private var color: Color {
        switch result {
        case .win: return .dsResultWin
        case .draw: return .dsResultDraw
        case .loss: return .dsResultLoss
        }
    }

    var body: some View {
        Text(letter)
            .dsFont(fontSize, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

#Preview {
    HStack(spacing: 5) {
        FormBadge(result: .win)
        FormBadge(result: .win)
        FormBadge(result: .draw)
        FormBadge(result: .loss)
        FormBadge(result: .win)
    }
    .padding()
    .background(Color.dsBgPrimary)
}
