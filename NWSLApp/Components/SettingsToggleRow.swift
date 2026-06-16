//
//  SettingsToggleRow.swift
//  NWSLApp
//
//  The shared visual for a labelled settings toggle — title + subtitle, an optional
//  secondary note, and a success-tinted switch. Extracted so ProfileView (global
//  Activity toggles) and the per-team Match Alerts sheet render identical rows; the
//  per-call-site behavior (permission request, sign-in nudge) stays at the binding,
//  not here. Carries no logic, just layout — mirrors the rest of the DesignSystem.
//

import SwiftUI

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    /// A muted note under the row — e.g. "Available when live tracking ships" for a
    /// server-push alert that persists intent but can't deliver yet.
    var note: String? = nil
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.dsFgPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgSecondary)
                if let note {
                    Text(note)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.dsFgTertiary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.dsSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

/// A titled card group — a tracked-caps label (and optional sentence-case subtitle)
/// over a rounded card that stacks its rows with hairline dividers. Shared by the
/// Notifications hub sections so they read as one settings surface.
struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Sentence-case bold white title (redesign language), not tracked caps.
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.dsFgPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
            .padding(.horizontal, 6)
            VStack(spacing: 0) { content }
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        }
    }
}

/// The hairline divider between settings rows (inset to match the row's leading text).
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.dsSeparator)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}
