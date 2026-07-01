//
//  AppGateView.swift
//  NWSLApp
//
//  The launch gate that runs the forced-update check BEFORE the app content mounts — so the tab
//  bar, data loading, and follows sync never start on an outdated build. While the check runs it
//  shows a plain dark screen (indistinguishable from the launch screen on a dark app, so a current
//  build sees no perceptible delay); the check is fast and FAILS OPEN (see ForceUpdateService), so a
//  slow/unreachable proxy resolves to the normal app, never a hang.
//

import SwiftUI

struct AppGateView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var phase: Phase = .checking
    private enum Phase { case checking, allowed, blocked }

    var body: some View {
        switch phase {
        case .checking:
            Color.dsBgGrouped
                .ignoresSafeArea()
                .task {
                    #if DEBUG
                    // Dev-only: preview the non-dismissible update wall without shipping a blocking
                    // config — same launch-arg pattern as `-colorAudit`/`-resetOnboarding`. Release strips it.
                    if ProcessInfo.processInfo.arguments.contains("-forceUpdateWall") { phase = .blocked; return }
                    #endif
                    phase = await ForceUpdateService.isUpdateRequired() ? .blocked : .allowed
                }
        case .allowed:
            content()
        case .blocked:
            ForceUpdateView()
        }
    }
}
