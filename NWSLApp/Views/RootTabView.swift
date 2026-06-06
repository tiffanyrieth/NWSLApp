//
//  RootTabView.swift
//  NWSLApp
//
//  The app's root: a five-tab bottom bar that is the navigation spine for the
//  whole app. Tabs are deliberately conventional ("conventional skeleton,
//  signature soul") — a bottom TabView is a learned thumb pattern, so the
//  novelty belongs inside the screens, not in how you switch between them.
//
//  Tab order is conventional (Home leftmost) and the app now *lands* on Home —
//  the your-teams-first hub (first open shows onboarding; afterwards the hub).
//  All five tabs are now built — no placeholder tab remains.
//
//  Navigation pattern: each tab's root view owns its OWN NavigationStack, so
//  every tab keeps an independent back-stack across tab switches, and a future
//  drilled-in detail screen can hide the tab bar without disturbing siblings.
//  Each tab's root view (HomeView, ScheduleView, FeedView, …) carries its own
//  NavigationStack internally.
//

import SwiftUI

struct RootTabView: View {
    /// Identifies each tab so we can set (and later restore) the selected one.
    private enum Tab: Hashable {
        case home, schedule, standings, teams, feed
    }

    // Land on Home — the your-teams-first hub (now built).
    @State private var selection: Tab = .home

    // The personalization lens, created once at the root and shared with every
    // tab via the environment so Teams (now) and Home/Feed (later) read the
    // same followed-clubs set.
    @State private var following = FollowingStore()

    // The season's matches, also created once and shared app-wide: Schedule
    // renders the whole season, a club's Team page renders its slice, and the
    // future Home will lead with followed clubs' next match — one fetch, many
    // readers (see MatchStore).
    @State private var matches = MatchStore()

    // Daily-Trivia stats (streak / accuracy / day-gate), created once and shared
    // app-wide so the game and a future Home Play-card badge read the same state
    // (see TriviaStore). Like the others, it's a persistent Store, not per-screen.
    @State private var trivia = TriviaStore()

    // Bracket Battle progress (votes / points / locked rounds), created once and
    // shared app-wide so the game and the Home Play-card badge read the same state
    // (see BracketStore). A persistent Store, not per-screen, like the others.
    @State private var bracket = BracketStore()

    // Predict the XI state (per-match predictions + a season-points snapshot),
    // created once and shared app-wide so the game and the Home Play-card badge read
    // the same state (see PredictionStore). A persistent Store, like the others.
    @State private var predict = PredictionStore()

    // Feed content preferences (content-type toggles + muted sources), created once
    // and shared so the Feed list and its Sources sheet read the same settings.
    @State private var feedPreferences = FeedPreferencesStore()

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(Tab.schedule)

            StandingsView()
                .tabItem { Label("Standings", systemImage: "list.number") }
                .tag(Tab.standings)

            TeamsView()
                .tabItem { Label("Teams", systemImage: "person.3.fill") }
                .tag(Tab.teams)

            FeedView()
                .tabItem { Label("Feed", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.feed)
        }
        .environment(following)
        .environment(matches)
        .environment(trivia)
        .environment(bracket)
        .environment(predict)
        .environment(feedPreferences)
    }
}

#Preview {
    RootTabView()
}
