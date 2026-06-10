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
import UIKit
import UserNotifications

struct RootTabView: View {
    // Tab selection lives in a shared AppRouter (injected below) so screens can
    // jump across tabs — e.g. Home's "Full schedule →". Lands on Home.
    @State private var router = AppRouter()

    // The personalization lens, created once at the root and shared with every
    // tab via the environment so Teams (now) and Home/Feed (later) read the
    // same followed-clubs set.
    @State private var following = FollowingStore()

    // The season's matches, also created once and shared app-wide: Schedule
    // renders the whole season, a club's Team page renders its slice, and the
    // future Home will lead with followed clubs' next match — one fetch, many
    // readers (see MatchStore).
    @State private var matches = MatchStore()

    // The league's club directory (all 16 clubs), created once and shared
    // app-wide: Teams lists it, Onboarding picks from it, and Home/Schedule/Feed
    // resolve followed IDs → Clubs — one fetch, many readers (see ClubStore).
    @State private var clubs = ClubStore()

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

    // The account layer (Sign in with Apple → Supabase user), created once and
    // shared so the post-onboarding sign-in prompt and the Profile screen read the
    // same signed-in state (see AuthStore).
    @State private var auth = AuthStore()

    // Notification preferences (the Profile screen's 9 toggles), shared so the
    // Profile reads/writes the same persisted intent (see NotificationPreferencesStore).
    @State private var notifications = NotificationPreferencesStore()

    // Bridges local follows ⟷ Supabase once signed in. Not injected into the
    // environment — no view needs it; RootTabView just holds it alive and starts
    // it after the session restores (see FollowSyncCoordinator).
    @State private var syncCoordinator: FollowSyncCoordinator?

    // Owns local (Tier 1) notification scheduling — day-before match reminders +
    // the weekly Player Spotlight. Like syncCoordinator, held alive here and not
    // injected (no view reads it); it reschedules when the season, the club
    // directory, the followed set, or the notification toggles change. Permission
    // prompting lives in ProfileView, tied to the toggle gesture (see
    // NotificationScheduler).
    @State private var notificationScheduler: NotificationScheduler?

    // Bridges the device's APNs token + the 9 notification toggles to Supabase once
    // signed in — the Tier 2 (server push) twin of syncCoordinator. Held alive here,
    // not injected; the match-watcher Worker reads what it writes (see
    // NotificationSyncCoordinator).
    @State private var notificationSyncCoordinator: NotificationSyncCoordinator?

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.schedule)

            StandingsView()
                .tabItem { Label("Standings", systemImage: "list.number") }
                .tag(AppTab.standings)

            TeamsView()
                .tabItem { Label("Teams", systemImage: "person.3.fill") }
                .tag(AppTab.teams)

            FeedView()
                .tabItem { Label("Feed", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.feed)
        }
        .environment(router)
        .environment(following)
        .environment(matches)
        .environment(clubs)
        .environment(trivia)
        .environment(bracket)
        .environment(predict)
        .environment(feedPreferences)
        .environment(auth)
        .environment(notifications)
        .task {
            // Restore any saved Supabase session, then start follow sync. Guard so
            // re-running .task (it can fire again on scene changes) doesn't build a
            // second coordinator.
            await auth.restoreSession()
            if syncCoordinator == nil {
                let coordinator = FollowSyncCoordinator(following: following, auth: auth)
                coordinator.start()
                syncCoordinator = coordinator
            }
            if notificationScheduler == nil {
                let scheduler = NotificationScheduler(
                    matches: matches,
                    following: following,
                    clubs: clubs,
                    preferences: notifications
                )
                scheduler.start()
                notificationScheduler = scheduler
            }
            if notificationSyncCoordinator == nil {
                let coordinator = NotificationSyncCoordinator(auth: auth, preferences: notifications)
                coordinator.start()
                notificationSyncCoordinator = coordinator
            }
            // If the user already granted notification permission in a prior launch,
            // re-register for remote notifications so APNs hands us a fresh device
            // token (tokens can rotate). No-op in the Simulator. New grants register
            // from ProfileView's permission flow.
            if await UNUserNotificationCenter.current().notificationSettings()
                .authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        // A tapped live push routes to its match (see PushBridge / AppRouter).
        .onChange(of: PushBridge.shared.tappedEventID) { _, eventID in
            if let eventID {
                router.openMatch(eventID: eventID)
                PushBridge.shared.tappedEventID = nil
            }
        }
    }
}

#Preview {
    RootTabView()
}
