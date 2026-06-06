//
//  NWSLAppApp.swift
//  NWSLApp
//
//  Created by Tiffany Rieth on 5/19/26.
//

import SwiftUI

@main
struct NWSLAppApp: App {
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
