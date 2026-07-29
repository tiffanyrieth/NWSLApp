//
//  PredictPitchChrome.swift
//  NWSLApp
//
//  THE Predict field — the one shared chrome behind both the picker's grid and the results pitch
//  (2026-07-28, owner call). Consistency here is enforced structurally: there is exactly one field,
//  so the two screens cannot drift apart. If a third Predict surface ever draws a pitch, it applies
//  this modifier rather than rolling its own background.
//
//  Markings are AMBIANCE, not a diagram: a quiet background layer (halfway line, centre circle,
//  penalty + six-yard box at the keeper's end) at the same subtle `dsPitchLine` opacity as the
//  border. The cells stack in rows on top and don't align to the geometry — that's fine and
//  deliberate. The earlier attempt drew a bright circle BETWEEN the player names and it competed
//  with them; behind the cells at 12% white, it reads as a field, not as content.
//
//  Both consumers place the GOALKEEPER AT THE BOTTOM (attack-first rows), which is why the boxes
//  are drawn at the bottom edge.
//

import SwiftUI

extension View {
    /// The Predict field: green gradient + subtle markings + rounded border. Apply to a row-stack
    /// of player cells (picker slots or results nodes).
    func predictPitchChrome() -> some View {
        self
            .background(
                LinearGradient(colors: [.dsPitch, .dsPitchBottom], startPoint: .top, endPoint: .bottom)
            )
            .background(alignment: .center) { Color.clear }   // keeps the gradient the sizing layer
            .overlay(PredictPitchMarkings().stroke(Color.dsPitchLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.dsPitchLine, lineWidth: 1)
            )
    }
}

/// One stroked path: halfway line, centre circle, penalty box and six-yard box at the bottom
/// (the keeper's end). Proportions echo `FormationPitchView`'s real-lineup pitch so the app's
/// fields rhyme, without pretending to be a measured diagram.
private struct PredictPitchMarkings: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Halfway line + centre circle at the visual middle.
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        let radius = min(rect.width, rect.height) * 0.16
        path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius,
                                   width: radius * 2, height: radius * 2))

        // Penalty box + six-yard box at the keeper's end (bottom).
        let penalty = CGRect(x: rect.midX - rect.width * 0.24, y: rect.maxY - rect.height * 0.13,
                             width: rect.width * 0.48, height: rect.height * 0.13)
        path.addRect(penalty)
        let six = CGRect(x: rect.midX - rect.width * 0.11, y: rect.maxY - rect.height * 0.055,
                         width: rect.width * 0.22, height: rect.height * 0.055)
        path.addRect(six)

        return path
    }
}
