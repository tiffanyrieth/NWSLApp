//
//  RootTabView.swift
//  NWSLApp
//
//  The app's root: a five-tab bottom bar that is the navigation spine for the
//  whole app. Tabs are deliberately conventional ("conventional skeleton,
//  signature soul") — a bottom TabView is a learned thumb pattern, so the
//  novelty belongs inside the screens, not in how you switch between them.
//
//  Tab order is conventional (Home leftmost), but the app *lands* on Schedule
//  for now because Home is still a placeholder: there's no point opening onto a
//  "coming soon" screen. Once Home is real, flip `selection`'s default to .home.
//
//  Navigation pattern: each tab's root view owns its OWN NavigationStack, so
//  every tab keeps an independent back-stack across tab switches, and a future
//  drilled-in detail screen can hide the tab bar without disturbing siblings.
//  ScheduleView already carries its own NavigationStack; the not-yet-built tabs
//  get one here via the placeholder wrapper.
//

import SwiftUI

struct RootTabView: View {
    /// Identifies each tab so we can set (and later restore) the selected one.
    private enum Tab: Hashable {
        case home, schedule, standings, teams, feed
    }

    // Land on Schedule for now — the only fully-built screen. Becomes .home
    // once Home is built out.
    @State private var selection: Tab = .schedule

    var body: some View {
        TabView(selection: $selection) {
            placeholderTab(title: "Home", systemImage: "house")
                .tag(Tab.home)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Tab.schedule)

            placeholderTab(title: "Standings", systemImage: "list.number")
                .tag(Tab.standings)

            placeholderTab(title: "Teams", systemImage: "shield")
                .tag(Tab.teams)

            placeholderTab(title: "Feed", systemImage: "dot.radiowaves.left.and.right")
                .tag(Tab.feed)
        }
    }

    /// A not-yet-built tab: a clean "coming soon" screen in its own
    /// NavigationStack (so its title bar and future back-stack already work),
    /// tagged into the tab bar with a matching icon.
    private func placeholderTab(title: String, systemImage: String) -> some View {
        NavigationStack {
            ComingSoonView(title: title, systemImage: systemImage)
        }
        .tabItem { Label(title, systemImage: systemImage) }
    }
}

#Preview {
    RootTabView()
}
