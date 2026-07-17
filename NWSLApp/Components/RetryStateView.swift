//
//  RetryStateView.swift
//  NWSLApp
//
//  The app's shared "couldn't load — tap to retry" surface. Before this, the same
//  VStack { message + Button("Try again"/"Retry") } was reimplemented in ~15 screens
//  and had drifted (label "Try again" vs "Retry", `.borderedProminent` vs `.bordered`
//  vs a custom card). One component, four layouts, one honest failure treatment —
//  never a blank screen or a silent fallback (see the NO SILENT FAILURES rule).
//
//  Styles:
//   .fullScreen   — centered, fills the space (an empty tab/list body)
//   .inline       — centered, width-only, sits under existing content (a failed section)
//   .card         — the message + button inside a dsBgCard card
//   .cardTappable — a dsBgCard card whose WHOLE surface is the retry target (no button)
//
//  The retry button renders through `DSButton`, so it shares the app's one CTA look.
//

import SwiftUI

struct RetryStateView: View {
    enum Style { case fullScreen, inline, card, cardTappable }

    var title: String? = nil
    let message: String
    var retryLabel: String = "Try again"
    var icon: String? = nil
    var style: Style = .fullScreen
    let retry: () async -> Void

    init(title: String? = nil,
         message: String,
         retryLabel: String = "Try again",
         icon: String? = nil,
         style: Style = .fullScreen,
         retry: @escaping () async -> Void) {
        self.title = title
        self.message = message
        self.retryLabel = retryLabel
        self.icon = icon
        self.style = style
        self.retry = retry
    }

    var body: some View {
        switch style {
        case .fullScreen:
            stack.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .inline:
            stack.frame(maxWidth: .infinity).padding(.vertical, DS.space13)
        case .card:
            stack
                .padding(DS.cardPadding)
                .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        case .cardTappable:
            Button { Task { await retry() } } label: {
                messageBlock
                    .frame(maxWidth: .infinity)
                    .padding(DS.cardPadding)
                    .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// message + an explicit retry button (all styles except .cardTappable).
    private var stack: some View {
        VStack(spacing: DS.space6) {
            messageBlock
            DSButton(retryLabel, size: .compact, width: .hug) { Task { await retry() } }
                .padding(.top, DS.space2)
        }
        .padding(.horizontal, DS.pagePadding)
    }

    /// The optional icon + optional bold title + secondary message (no button).
    private var messageBlock: some View {
        VStack(spacing: DS.space5) {
            if let icon {
                Image(systemName: icon)
                    .dsFont(26)
                    .foregroundStyle(Color.dsFgTertiary)
            }
            if let title {
                Text(title)
                    .dsFont(17, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .multilineTextAlignment(.center)
            }
            Text(message)
                .dsFont(15)
                .foregroundStyle(Color.dsFgSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        RetryStateView(message: "Couldn't load — tap to retry", style: .inline) {}
        RetryStateView(title: "Couldn't load the squad",
                       message: "Check your connection and try again.",
                       retryLabel: "Retry", icon: "person.3.sequence",
                       style: .card) {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dsBgGrouped)
    .preferredColorScheme(.dark)
}
#endif
