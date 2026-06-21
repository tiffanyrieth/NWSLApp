//
//  CoachMarkTriangle.swift
//  NWSLApp
//
//  Shared upward-pointing triangle for coach-mark arrows (apex centered at the top).
//  Used by the Teams-tab bell coach mark and the Social-tab gear nudge — extracted so
//  both point at their target with the same arrow rather than duplicating the shape.
//

import SwiftUI

struct CoachMarkTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
