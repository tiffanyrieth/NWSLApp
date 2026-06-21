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
    // Re-sync Game Center when the app returns to the foreground (scores earned
    // offline get pushed once we're back online + authenticated).
    @Environment(\.scenePhase) private var scenePhase

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

    // Shared, prewarmable Feed cards store (Feed is the known-slow path; prewarmed below).
    @State private var feedStore = FeedStore()

    // Shared Home content store (Module 1 + spotlight), warmed during onboarding (as teams
    // are picked) and prewarmed at launch — so Home renders populated on arrival. Survives
    // the onboarding→Home flip because it lives here at the root (see HomeContentStore).
    @State private var homeContent = HomeContentStore()

    // The account layer (Sign in with Apple → Supabase user), created once and
    // shared so the post-onboarding sign-in prompt and the Profile screen read the
    // same signed-in state (see AuthStore).
    @State private var auth = AuthStore()

    // Notification preferences (the global Activity toggles + the migration seed for
    // per-team alerts), shared so Profile reads/writes the same persisted intent.
    @State private var notifications = NotificationPreferencesStore()

    // Per-team match-alert prefs (QOL Change 2: Follow vs Alerts), shared so each
    // club's detail sheet and the Profile summary read the same state. Keyed by ESPN
    // team id, like FollowingStore (see TeamAlertStore).
    @State private var teamAlerts = TeamAlertStore()

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

    // Mirrors per-team alert prefs ⟷ Supabase once signed in, and clears a team's
    // alerts when it leaves the followed set. Held alive here, not injected (see
    // TeamAlertSyncCoordinator).
    @State private var teamAlertSyncCoordinator: TeamAlertSyncCoordinator?

    var body: some View {
        @Bindable var router = router
        // A custom selection binding so we can detect a re-tap of the ALREADY-active
        // tab (TabView calls the setter with the same value) — used by Schedule to
        // snap back to today. A normal `$router.selectedTab` binding loses that.
        let tabSelection = Binding<AppTab>(
            get: { router.selectedTab },
            set: { newTab in
                if newTab == router.selectedTab {
                    router.tabReselected(newTab)
                } else {
                    router.selectedTab = newTab
                }
            }
        )
        Group {
            if following.hasOnboarded {
                TabView(selection: tabSelection) {
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
                        .tabItem { Label("Social", systemImage: "dot.radiowaves.left.and.right") }
                        .tag(AppTab.feed)
                }
            } else {
                // First open: full-screen team picker with NO tab bar. Two reasons:
                // (1) onboarding can't be skipped by tapping another tab (the TabView
                // isn't in the hierarchy yet); (2) the TabView's FIRST layout then happens
                // into the settled hub *after* onboarding completes — not mid-onboarding —
                // which avoids the iOS 26 floating-bar first-render label truncation a
                // fresh install hit. OnboardingView needs a NavigationStack (it sets a
                // navigationTitle) and reads FollowingStore + ClubStore from the env below.
                NavigationStack { OnboardingView() }
            }
        }
        // Accessibility: honor the user's text-size setting (Dynamic Type) for text AND
        // crests (which scale on the same axis — see DSText.dsFont / TeamLogo), but CAP at
        // AX1. This covers larger-text needs (older eyes, mild low-vision) without forcing
        // the dense tables to survive the extreme accessibility sizes (AX2–AX5 clamp to AX1);
        // beyond that the system reader is the right tool. Also bounds the system tab-bar labels.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .environment(router)
        .environment(following)
        .environment(matches)
        .environment(clubs)
        .environment(trivia)
        .environment(bracket)
        .environment(predict)
        .environment(feedPreferences)
        .environment(feedStore)
        .environment(homeContent)
        .environment(auth)
        .environment(notifications)
        .environment(teamAlerts)
        .task {
            // Hand the shared season store the follow lens (so load() fetches NWSL +
            // the user's followed national-team feeds) and refetch the schedule when a
            // competition/national-team follow changes. Set synchronously, before any
            // tab's first matchStore.load(). Idempotent (re-assigning is harmless).
            matches.following = following
            following.onCompetitionFollowsChanged = { [matches] in
                Task { await matches.load() }
            }
            // Prewarm the season schedule so Home/Schedule's first paint isn't gated on it.
            // DURING ONBOARDING this runs while the user picks teams, so by the time they reach
            // Home it's already past the full-screen "Loading…" gate (which needs clubs AND
            // matches loaded) — Home renders populated on arrival, not after a spinner. Guarded
            // on `.idle` (HomeView/ScheduleView guard the same way), so no double fetch; the NWSL
            // spine loads regardless of follows, and a later NT/competition follow reloads via
            // `onCompetitionFollowsChanged` above.
            Task { if case .idle = matches.state { await matches.load() } }
            // Restore any saved Supabase session, then start follow sync. Guard so
            // re-running .task (it can fire again on scene changes) doesn't build a
            // second coordinator.
            await auth.restoreSession()
            // Game Center auth is deliberately NOT started here. It's deferred until
            // the user actually reaches a Fan Zone game or the Game Center dashboard
            // (each game screen + the Profile leaderboards strip call
            // `GameCenterManager.shared.authenticate()` on appear), so the GC sign-in
            // banner never intrudes on the launch / first-impression. Once auth
            // resolves there, the `isAuthenticated` onChange below runs the first
            // syncAll.
            // Warm the player-headshot map once (best-effort) so squad grids, the pitch, and
            // the Fan Zone show real photos instead of monograms. LOW priority + non-blocking
            // (Tier-2 prefetch order): headshots aren't on the first screen (monogram fallback
            // everywhere), so this must NOT compete with the foreground critical path (scoreboard
            // + clubs + Home content, loaded on Home's appearance). Self-guards on re-fire.
            Task(priority: .utility) { await HeadshotStore.shared.load() }
            if syncCoordinator == nil {
                let coordinator = FollowSyncCoordinator(following: following, auth: auth)
                coordinator.start()
                syncCoordinator = coordinator
            }
            // One-time seed of per-team alerts from the old GLOBAL Match Day toggles,
            // so existing testers don't silently lose alerts on upgrade. Idempotent
            // (self-guards on a sentinel); must run before the alert sync coordinator's
            // first reconcile so the seeded prefs mirror up. FollowingStore has loaded
            // its ids by now (in its init), so the followed set is ready.
            teamAlerts.migrateFromGlobalIfNeeded(
                global: notifications.snapshot,
                followedIDs: following.followedIDs
            )
            if notificationScheduler == nil {
                let scheduler = NotificationScheduler(
                    matches: matches,
                    following: following,
                    clubs: clubs,
                    preferences: notifications,
                    alerts: teamAlerts
                )
                scheduler.start()
                notificationScheduler = scheduler
            }
            if notificationSyncCoordinator == nil {
                let coordinator = NotificationSyncCoordinator(auth: auth, preferences: notifications)
                coordinator.start()
                notificationSyncCoordinator = coordinator
            }
            if teamAlertSyncCoordinator == nil {
                let coordinator = TeamAlertSyncCoordinator(
                    auth: auth,
                    alerts: teamAlerts,
                    following: following
                )
                coordinator.start()
                teamAlertSyncCoordinator = coordinator
            }
            // If the user already granted notification permission in a prior launch,
            // re-register for remote notifications so APNs hands us a fresh device
            // token (tokens can rotate). No-op in the Simulator. New grants register
            // from ProfileView's permission flow.
            if await UNUserNotificationCenter.current().notificationSettings()
                .authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
            // Out-of-band: refresh the bundled crest/flag artwork if the cadence is due
            // (>30 days, or forced once in March). Deferred to its own low-priority task and
            // best-effort, so it never competes with the launch network window — the bundled
            // vectors already render; an override only changes things on the NEXT launch.
            Task(priority: .utility) { await AssetRefreshService.refreshIfDue() }
            // Prewarm the Feed (the known-slow path: the proxy `/feed` does server-side Haiku
            // tagging) at LOW priority after the foreground critical path, so the first switch
            // to the Feed tab is instant. Needs the directory loaded for follow-scoping; the
            // load self-guards, so the tab's own first-appearance load is then a no-op.
            Task(priority: .utility) {
                await clubs.loadIfNeeded()
                await feedStore.loadIfNeeded(following: following, clubStore: clubs)
            }
            // Prewarm Home content too, so the first Home paint on an already-onboarded launch
            // is instant (same rationale as the Feed prewarm). Guarded on `hasOnboarded`: a fresh
            // install has no followed set yet (an empty `?teams=` returns 0 home cards), and the
            // onboarding warm path covers the picking phase. Scope-aware, so Home's own load is a no-op.
            if following.hasOnboarded {
                Task(priority: .utility) {
                    await clubs.loadIfNeeded()
                    await homeContent.loadIfNeeded(following: following, clubStore: clubs)
                }
            }
        }
        // A tapped live push routes to its match (see PushBridge / AppRouter).
        .onChange(of: PushBridge.shared.tappedEventID) { _, eventID in
            if let eventID {
                router.openMatch(eventID: eventID)
                PushBridge.shared.tappedEventID = nil
            }
        }
        // Once Game Center auth resolves, push the current totals (Superfan combined
        // + cross-game achievements live here, where all three stores are in reach).
        .onChange(of: GameCenterManager.shared.isAuthenticated) { _, signedIn in
            if signedIn {
                GameCenterManager.shared.syncAll(trivia: trivia, predict: predict, bracket: bracket)
            }
        }
        // Returning to the foreground re-syncs (covers scores earned while offline).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                GameCenterManager.shared.syncAll(trivia: trivia, predict: predict, bracket: bracket)
            }
            // Leaving the foreground flushes any pending no-silent-failure telemetry to the
            // remote sink (best-effort) so a field miss reaches the owner without a user report.
            if phase == .background {
                Task { await Diagnostics.shared.flushRemote() }
            }
        }
    }
}

#Preview {
    RootTabView()
}
