//
//  DSButton.swift
//  NWSLApp
//
//  The app's shared primary button. Before this, the accent CTA was hand-rolled per
//  screen and had drifted on corner radius (10 vs 14), font size, and disabled
//  treatment (see the design audit, cross-cutting #5). One component, one radius
//  (DS.radiusSm — the documented button token). RetryStateView's buttons also render
//  through this, so every "call to action" in the app shares one look.
//
//  Styles:
//   .filled          — solid dsAccent (the default primary CTA)
//   .outline         — clear fill + accent stroke (a secondary / not-yet-enabled CTA)
//   .gradient(style) — a caller-supplied gradient fill (e.g. Support's tip-jar CTA)
//  Disabled: filled/gradient dim to a dsBgCard fill + dsFgTertiary text; outline dims
//  its stroke + text. `isLoading` swaps the label for an in-place ProgressView.
//

import SwiftUI

struct DSButton: View {
    enum Style { case filled, outline, gradient(AnyShapeStyle) }
    enum Size { case regular, compact }
    enum Width { case fullWidth, hug }

    let title: String
    var style: Style = .filled
    var size: Size = .regular
    var icon: String? = nil
    var width: Width = .fullWidth
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    init(_ title: String,
         style: Style = .filled,
         size: Size = .regular,
         icon: String? = nil,
         width: Width = .fullWidth,
         isEnabled: Bool = true,
         isLoading: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.size = size
        self.icon = icon
        self.width = width
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: width == .fullWidth ? .infinity : nil)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, width == .fullWidth ? 0 : 18)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
                .overlay(outlineStroke)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            ProgressView().tint(foreground)
                .padding(.vertical, 1) // keep the height stable vs the text label
        } else {
            HStack(spacing: 8) {
                Text(title)
                if let icon { Image(systemName: icon) }
            }
            .dsFont(fontSize, weight: .semibold)
            .foregroundStyle(foreground)
        }
    }

    private var fontSize: CGFloat { size == .regular ? 16 : 15 }
    private var verticalPadding: CGFloat { size == .regular ? 14 : 10 }

    private var foreground: Color {
        switch style {
        // Filled stays WHITE even when disabled — the disabled fill is a muted accent (below),
        // so white text keeps the label legible (a dim gray label was unreadable + made the
        // button read as a search field). Only the fill intensity signals "not yet active".
        case .filled:            return .dsFgPrimary
        case .gradient:          return isEnabled ? .dsFgPrimary : .dsFgTertiary
        case .outline:           return isEnabled ? .dsAccent : .dsFgTertiary
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .filled:
            // Disabled = a muted-but-clearly-blue CTA-in-waiting (not a dark gray field).
            isEnabled ? Color.dsAccent : Color.dsAccent.opacity(0.35)
        case .gradient(let fill):
            if isEnabled { Rectangle().fill(fill) } else { Color.dsBgCard }
        case .outline:
            Color.clear
        }
    }

    @ViewBuilder private var outlineStroke: some View {
        if case .outline = style {
            RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous)
                .stroke(isEnabled ? Color.dsAccent : Color.dsFgTertiary, lineWidth: 1.5)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        DSButton("Update") {}
        DSButton("Add clubs to get started", style: .outline, isEnabled: false) {}
        DSButton("Send a tip", style: .gradient(AnyShapeStyle(Color.dsAccent))) {}
        DSButton("Working…", isLoading: true) {}
        DSButton("Retry", size: .compact, width: .hug) {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dsBgGrouped)
    .preferredColorScheme(.dark)
}
#endif
