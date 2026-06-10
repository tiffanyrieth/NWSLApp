//
//  AppRouter.swift
//  NWSLApp
//
//  The app's tab-selection router — created once at the root (RootTabView) and
//  shared via the environment so a screen can send the user to another tab. Home
//  uses it for the "Full schedule →" shortcut (jump to the Schedule tab); future
//  cross-tab shortcuts (e.g. a Home "see standings") reuse it.
//
//  `AppTab` is top-level (not nested/private) so any screen can name a tab.
//

import SwiftUI

/// The five top-level tabs. The raw `TabView` selection value.
enum AppTab: Hashable {
    case home, schedule, standings, teams, feed
}

@Observable
final class AppRouter {
    /// The selected tab. RootTabView binds the `TabView` to this; any screen can
    /// set it to navigate across tabs.
    var selectedTab: AppTab = .home
}
