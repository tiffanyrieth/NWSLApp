//
//  MatchAlertToast.swift
//  NWSLApp
//
//  The bell-confirmation toast, extracted from TeamsView so BOTH the Teams grid and the
//  Competitions screen can show it (plan §Phase 1 — problem B: the toast used to be private to
//  TeamsView, so the national-team bell fired nothing). A `.matchAlertToast(_:onCustomize:)`
//  modifier: floats above the tab bar, auto-dismisses after ~3s or on tap; tapping the "on"
//  toast runs `onCustomize` (each host routes into ITS nav stack's Notifications hub) and dismisses.
//

import SwiftUI

private struct MatchAlertToastModifier: ViewModifier {
    @Bindable var presenter: MatchAlertPresenter
    let onCustomize: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = presenter.toast {
                card(toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        // Auto-dismiss after ~3s; cancels if a new toast replaces this one.
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled, presenter.toast?.id == toast.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { presenter.toast = nil }
                    }
                    .animation(.easeOut(duration: 0.2), value: presenter.toast)
            }
        }
    }

    // Tappable: "on" routes to the hub (its CTA is "Customize alerts"); either way the toast clears.
    private func card(_ toast: MatchAlertPresenter.Toast) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { presenter.toast = nil }
            if toast.on { onCustomize() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: toast.on ? "bell.fill" : "bell.slash.fill")
                    .dsFont(14, weight: .semibold)
                    .foregroundStyle(toast.on ? Color.dsAccent : Color.dsFgSecondary)
                Group {
                    if toast.on {
                        Text("Match alerts on. ")
                            .foregroundStyle(Color.dsFgPrimary)
                        + Text("Customize alerts ").foregroundStyle(Color.dsAccent).fontWeight(.semibold)
                        + Text(Image(systemName: "gearshape.fill")).foregroundStyle(Color.dsAccent)
                    } else {
                        Text("Match alerts off.").foregroundStyle(Color.dsFgPrimary)
                    }
                }
                .dsFont(13)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous).stroke(Color.dsSeparator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Attach the match-alert confirmation toast, driven by a `MatchAlertPresenter`. `onCustomize`
    /// runs when the user taps an "on" toast — the host routes it into its own nav stack's hub.
    func matchAlertToast(_ presenter: MatchAlertPresenter, onCustomize: @escaping () -> Void) -> some View {
        modifier(MatchAlertToastModifier(presenter: presenter, onCustomize: onCustomize))
    }
}
