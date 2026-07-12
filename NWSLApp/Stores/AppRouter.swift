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

    /// Bumped whenever the user taps the ALREADY-ACTIVE tab (re-selecting the tab
    /// they're already on). A screen observes `reselectNonce` + `reselectedTab` to
    /// react — e.g. the Schedule tab snaps its list back to today. SwiftUI's
    /// `onChange(of: selectedTab)` can't see this: the value doesn't change on a
    /// re-tap, so the change observer never fires. RootTabView's selection binding
    /// detects the same-value set and calls `tabReselected`.
    private(set) var reselectNonce = 0
    private(set) var reselectedTab: AppTab?

    /// Record a re-tap of the active tab (does not change `selectedTab`).
    func tabReselected(_ tab: AppTab) {
        reselectedTab = tab
        reselectNonce += 1
    }

    init() {
        #if DEBUG
        // DEBUG launch arg `-startTab <home|schedule|standings|teams|social>` lands the
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
            case "social", "feed": selectedTab = .feed   // `.feed` is the internal case; "social" is the label
            default: break
            }
        }
        // DEBUG launch arg `-debugOpenMatch <espnEventID>` deep-links straight to a match detail at
        // launch (via the same pendingMatch path a push tap uses), so in-sim screenshot verification
        // of a specific Match Detail screen doesn't need taps — essential on Xcode 27, where idb HID
        // is dead and there's no Simulator window to cliclick. A testing affordance like `-startTab`.
        if let i = args.firstIndex(of: "-debugOpenMatch"), i + 1 < args.count {
            pendingMatchEventID = args[i + 1]
            selectedTab = .schedule
        }
        #endif
    }

    /// The match a live push (goal/lineup/FT/…) tap wants to open, by ESPN event id.
    /// Set via `openMatch(eventID:)`; ScheduleView consumes it (`consumePendingMatch`)
    /// and pushes MatchDetailView via an `isPresented` navigationDestination — resolved
    /// against the loaded season, retried when the season lands (a tap can beat first
    /// load). Cleared on consumption so re-taps re-fire.
    var pendingMatchEventID: String?

    /// Route a live-push tap to its match: jump to the Schedule tab and record the
    /// event id. See `pendingMatchEventID`.
    func openMatch(eventID: String) {
        pendingMatchEventID = eventID
        selectedTab = .schedule
    }
}
