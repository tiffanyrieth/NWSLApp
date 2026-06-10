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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: DS.radiusXs, style: .continuous))
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
