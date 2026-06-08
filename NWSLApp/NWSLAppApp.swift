//
//  NWSLAppApp.swift
//  NWSLApp
//
//  Created by Tiffany Rieth on 5/19/26.
//

import SwiftUI

@main
struct NWSLAppApp: App {
    init() {
        #if DEBUG
        // Dev-only: pass `-resetOnboarding` in the Run scheme's launch arguments
        // to wipe followed teams + the onboarding flag before any store reads
        // UserDefaults, so the next launch starts at the first-open picker. Runs
        // here (App.init) because it's the earliest hook — before RootTabView
        // creates the stores. Stripped from release builds.
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            FollowingStore.debugResetState()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Force a dark appearance app-wide (a single dark identity, like
                // the MLS app), independent of the device setting. Set on the
                // root view inside WindowGroup so it also reaches presented
                // sheets (onboarding, Feed content preferences). There's no
                // in-app appearance toggle, so this is the whole policy.
                .preferredColorScheme(.dark)
        }
    }
}
