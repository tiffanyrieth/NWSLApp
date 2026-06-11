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

    init() {
        #if DEBUG
        // DEBUG launch arg `-startTab <home|schedule|standings|teams|feed>` lands the
        // app on a given tab at launch, so in-sim screenshot verification doesn't
        // depend on flaky synthetic tab taps (the UIKit tab bar responds, but precise
        // taps are unreliable — see CLAUDE.md → Commands). A testing affordance only,
        // like `-resetOnboarding`/`-useESPNDirect`; compiled out of release builds.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count {
            switch args[i + 1] {
            case "home": selectedTab = .home
            case "schedule": selectedTab = .schedule
            case "standings": selectedTab = .standings
            case "teams": selectedTab = .teams
            case "feed": selectedTab = .feed
            default: break
            }
        }
        #endif
    }

    /// The match a live push (goal/kickoff/…) tap wants to open, by ESPN event id.
    /// Set via `openMatch(eventID:)` and consumed by the Schedule tab.
    ///
    /// TEMP seam: the Schedule/Home stacks use closure-based NavigationLinks (no
    /// path-bound NavigationStack), so a tap currently lands the user on the
    /// Schedule tab — where the match lives — rather than pushing MatchDetailView
    /// directly. Auto-opening the detail needs those stacks converted to a
    /// `navigationDestination`/path model; this id is the hook for that follow-up.
    var pendingMatchEventID: String?

    /// Route a live-push tap to its match: jump to the Schedule tab and record the
    /// event id. See `pendingMatchEventID`.
    func openMatch(eventID: String) {
        pendingMatchEventID = eventID
        selectedTab = .schedule
    }
}
