//
//  ForceUpdateView.swift
//  NWSLApp
//
//  The non-dismissible "please update" wall shown when this build is below the proxy's `minBuild`
//  (see ForceUpdateService). It fully replaces the app content — no tab bar, nothing behind it, no
//  dismiss/skip affordance — so an outdated client cannot be used. The only action is "Update",
//  which opens TestFlight (the App Store at public launch, via `AppConfig.updateURL`).
//

import SwiftUI

struct ForceUpdateView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.dsBgGrouped.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill")
                    .dsFont(52, weight: .semibold)
                    .foregroundStyle(Color.dsAccent)

                Text("Update Required")
                    .dsFont(24, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)

                Text("A new version of NWSLApp is available. Please update to continue.")
                    .dsFont(16, weight: .regular)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                DSButton("Update") {
                    openURL(AppConfig.updateURL)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
        }
        // Belt-and-suspenders: nothing can swipe or interactively dismiss this.
        .interactiveDismissDisabled(true)
    }
}

#Preview {
    ForceUpdateView().preferredColorScheme(.dark)
}
