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

    // The postseason bracket, derived from the shared season + standings and shown only
    // during the playoffs in the Standings tab — created once, injected, read there.
    @State private var playoffs = PlayoffStore()

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

    // Know Her Game state (per-edition scores + the weekly streak + the in-memory weekly
    // pool), created once and shared so the Home Fan Zone card, the picker, and the game
    // read the same played state (see KnowHerGameStore). A persistent Store, like the others.
    @State private var knowHer = KnowHerGameStore()

    // Fan Zone "seen" state — which game cycle the user last opened, for the new/unseen dot
    // (docs §10). Shared so the dot state is consistent wherever a card renders.
    @State private var seen = FanZoneSeenStore()

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

    // TEMP (iOS 27 beta Liquid Glass tab-bar workaround — remove once Apple patches):
    // one-shot flag so the relayout bridge fires exactly once per session (see
    // TabBarRelayoutBridge at the bottom of this file).
    @State private var didRelayoutBar = false

    // Involuntary-sign-out nudge (the 2026-07-15 field bug): app-level auto-present of the
    // sign-in sheet when the session lapsed OUT FROM UNDER a user who had opted into Tier-2
    // alerts. App-level (over ANY tab) because settings screens are rarely visited — the whole
    // point is telling her without waiting for a missed push. One-shot per launch; a deliberate
    // sign-out never triggers it (SignOutSentinels.deliberateSignOut suppresses).
    @State private var showSignedOutAlertNudge = false
    @State private var didPresentSignedOutNudge = false

    /// Brief launch state for a signed-in user whose follows are being restored from the server,
    /// shown instead of the onboarding picker (see the root gate). Honest + quiet, dark-theme.
    private var restoringView: some View {
        ZStack {
            Color.dsBgGrouped.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().tint(Color.dsAccent)
                Text("Restoring your teams…")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
            }
        }
    }

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
                // The `.background(TabBarRelayoutBridge…)` on each tab's CONTENT is the
                // iOS 27 beta Liquid Glass tab-bar workaround (see the struct at the bottom):
                // whichever tab appears first forces one corrective UITabBar relayout pass and
                // flips `didRelayoutBar`, so the rest no-op. On the content (not the TabView's
                // own background) so the hosting controller resolves `.tabBarController`.
                TabView(selection: tabSelection) {
                    HomeView()
                        .background(TabBarRelayoutBridge(done: $didRelayoutBar))
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(AppTab.home)

                    ScheduleView()
                        .background(TabBarRelayoutBridge(done: $didRelayoutBar))
                        .tabItem { Label("Schedule", systemImage: "calendar") }
                        .tag(AppTab.schedule)

                    StandingsView()
                        .background(TabBarRelayoutBridge(done: $didRelayoutBar))
                        .tabItem { Label("Standings", systemImage: "list.number") }
                        .tag(AppTab.standings)

                    TeamsView()
                        .background(TabBarRelayoutBridge(done: $didRelayoutBar))
                        .tabItem { Label("Teams", systemImage: "person.3.fill") }
                        .tag(AppTab.teams)

                    FeedView()
                        .background(TabBarRelayoutBridge(done: $didRelayoutBar))
                        .tabItem { Label("Social", systemImage: "dot.radiowaves.left.and.right") }
                        .tag(AppTab.feed)
                }
            } else if !auth.sessionRestoreAttempted
                        || (auth.isSignedIn && !(syncCoordinator?.restoreResolved ?? false)) {
                // A signed-in user's follows are being restored from the server (or the session
                // is still being restored at launch). Show a brief "Restoring…" rather than
                // flashing the onboarding picker — a returning signed-in user must NOT be sent
                // back through onboarding, and showing the picker is exactly what let onboarding
                // taps race the restore. `reconcile` flips `restoreResolved` once the server set
                // is known and calls `completeOnboarding()` when it restored follows (→ the hub).
                restoringView
            } else {
                // First open: full-screen team picker with NO tab bar. Two reasons:
                // (1) onboarding can't be skipped by tapping another tab (the TabView
                // isn't in the hierarchy yet); (2) the TabView's FIRST layout then happens
                // into the settled hub *after* onboarding completes — not mid-onboarding —
                // which avoids the iOS 26 floating-bar first-render label truncation a
                // fresh install hit. OnboardingView needs a NavigationStack (it sets a
                // navigationTitle) and reads FollowingStore + ClubStore from the env below.
                // Reached only once we KNOW there's no signed-in account with follows to
                // restore (signed out, or signed in with an empty server set).
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
        .environment(playoffs)
        .environment(clubs)
        .environment(trivia)
        .environment(bracket)
        .environment(predict)
        .environment(knowHer)
        .environment(seen)
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
            Task(priority: .utility) { if case .idle = matches.state { await matches.load() } }
            // Restore any saved Supabase session, then start follow sync. Guard so
            // re-running .task (it can fire again on scene changes) doesn't build a
            // second coordinator.
            #if DEBUG
            // `-simulateLostSession`: drop the keychain session BEFORE restore (UserDefaults
            // untouched) — the exact repro of "signed out involuntarily, toggles still stored".
            if ProcessInfo.processInfo.arguments.contains("-simulateLostSession") {
                await auth.debugSimulateLostSession()
            }
            #endif
            await auth.restoreSession()
            // Mirror Supabase auth events for the app's lifetime (idempotent). Started AFTER
            // restore so the initial state is settled; catches explicit terminations the
            // running app would otherwise only notice at next launch.
            auth.startAuthStateListener()
            #if DEBUG
            // `-resetOnboarding` simulates a brand-new install. Wiping the local
            // follows (App.init's debugResetState) isn't enough on its own: the
            // Supabase session lives in the keychain, untouched, so the restore
            // above signs us back in and FollowSyncCoordinator.reconcile() merges
            // the server's follows back DOWN into the just-cleared store — the
            // onboarding picker then shows phantom "followed" teams. Signing out
            // here clears the keychain session too, so reconcile has nothing to
            // pull and the next launch is a true fresh user. DEBUG-only, matching
            // the reset flag itself.
            if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
                await auth.signOut()
            }
            #endif
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
            Task(priority: .background) { await HeadshotStore.shared.load() }
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
                let coordinator = NotificationSyncCoordinator(
                    auth: auth, preferences: notifications, teamAlerts: teamAlerts)
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
            // V2 Live Activity observers are primed at app LAUNCH (AppDelegate → startObserving) so a
            // push-to-start *background* launch can register the per-Activity token; the sign-in token
            // flush lives in AuthStore.handleSignIn. Nothing to wire from the view here.
            #if DEBUG
            // Sim verification only: drive a full sample Live Activity lifecycle (pre→live→goal→HT→FT→end).
            if ProcessInfo.processInfo.arguments.contains("-driveLiveActivity") {
                Task { await LiveActivityManager.shared.debugDriveSampleLifecycle() }
            }
            #endif
            // Ensure this device is registered for pushes on EVERY open (self-heal) — see
            // reconcileNotificationRegistration. Replaces the old "register only if already
            // authorized" gate, which left opt-in / reinstalled users with no token forever.
            await reconcileNotificationRegistration()
            // Involuntary-sign-out nudge (launch check): if the session is gone but Tier-2
            // alert intent is still stored — and the user didn't sign out on purpose — tell
            // them NOW, over whatever tab they're on, instead of letting them discover it by
            // a missed goal push. (The coordinator sets the persisted sentinel + telemetry;
            // this recomputes the condition live so no ordering race can suppress the sheet.)
            maybePresentSignedOutAlertNudge()
            // Out-of-band: refresh the bundled crest/flag artwork if the cadence is due
            // (>30 days, or forced once in March). Deferred to its own low-priority task and
            // best-effort, so it never competes with the launch network window — the bundled
            // vectors already render; an override only changes things on the NEXT launch.
            Task(priority: .utility) { await AssetRefreshService.refreshIfDue() }
            // Prewarm the Feed (the known-slow path: the proxy `/feed` does server-side Haiku
            // tagging) at LOW priority after the foreground critical path, so the first switch
            // to the Feed tab is instant. Needs the directory loaded for follow-scoping; the
            // load self-guards, so the tab's own first-appearance load is then a no-op.
            Task(priority: .background) {
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
                GameCenterManager.shared.syncAll(trivia: trivia, predict: predict, bracket: bracket, knowHer: knowHer)
            }
        }
        // Live scoreboard poll: while the app is foregrounded, silently refresh the shared
        // season store so live cards (Schedule/Home) AND the Match Detail header advance
        // without a relaunch — the core fix for "live scores never update in-app." 60s while a
        // game is in progress (the ≤30s-fresh surface is the V2 card, not the in-app screens —
        // see the .task below), slow (~5min) otherwise. The loop suspends
        // in the background (Task.sleep) and resumes on foreground; scenePhase == .active also
        // kicks an immediate refresh so returning to the app is instant.
        .task {
            while !Task.isCancelled {
                // 60s live (owner call 2026-07-16): the ≤30s-fresh surface is the V2 lock-screen
                // card, which rides the WATCHER's poll + one broadcast POST (user-count-free) —
                // the in-app screens don't need to match it. 60s halves the per-watcher proxy
                // cost (the 100k/day requests cap scales with concurrent open apps), and the
                // foreground-push refresh below beats any poll for alert-opted-in users anyway.
                let interval: Duration = matches.hasLiveMatch ? .seconds(60) : .seconds(300)
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await matches.refresh()
            }
        }
        // A V1 match push ARRIVING while the app is open (banner, not tap) means the score just
        // changed — refresh now instead of waiting out the heartbeat. Event-driven: costs one
        // windowed refresh per real match event, and reaches opted-in users at push latency.
        .onChange(of: PushBridge.shared.foregroundPushNonce) { _, _ in
            Task { await matches.refresh() }
        }
        // Returning to the foreground re-syncs (covers scores earned while offline).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                GameCenterManager.shared.syncAll(trivia: trivia, predict: predict, bracket: bracket, knowHer: knowHer)
                // Refresh live scores immediately on return to foreground. The live-poll
                // loop below is suspended while backgrounded, so without this a game that
                // advanced (or finished) while the app was away would stay frozen at the
                // last-seen minute/score until the next tick — the exact "hours later, still
                // 51'" bug. Silent refresh: keeps the last good schedule on a transient miss.
                Task { await matches.refresh() }
                // Re-check token registration on EVERY foreground (self-heal): registers when
                // authorized, re-requests permission for an opted-in user whose grant was reset
                // (reinstall), retries a failed upload, and re-flushes the V2 push-to-start token.
                Task { await reconcileNotificationRegistration() }
                // Probe the session for the case the auth listener can't see: a refresh token
                // that died while the app was away. Nil-s the user ONLY on a definitive
                // termination (never a network blip) — the isSignedIn onChange below then
                // surfaces the nudge if Tier-2 intent is stranded.
                Task { await auth.revalidateSession() }
            }
            // Leaving the foreground flushes any pending no-silent-failure telemetry to the
            // remote sink (best-effort) so a field miss reaches the owner without a user report.
            if phase == .background {
                Task { await Diagnostics.shared.flushRemote() }
            }
        }
        // Mid-session involuntary sign-out (revalidateSession or the auth listener nil-ing the
        // user while the app runs): surface the nudge the moment it happens — the most honest
        // moment to tell her. Same one-shot guard as the launch check; a deliberate sign-out is
        // suppressed by its sentinel inside the helper.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if !signedIn { maybePresentSignedOutAlertNudge() }
        }
        .sheet(isPresented: $showSignedOutAlertNudge) {
            NotificationAuthPromptView(onSignedIn: {
                // handleSignIn already cleared the sentinels and the coordinator re-pushes the
                // preserved prefs snapshot; just re-register the device token right away rather
                // than waiting for the next foreground.
                Task { await reconcileNotificationRegistration() }
            })
            // Explicit: this .sheet sits OUTSIDE the .environment(...) wrappers above (modifier
            // order), so the prompt does NOT inherit them — omitting this crashes on present
            // (EnvironmentValues assertion; sim-caught 2026-07-16).
            .environment(auth)
        }
    }

    /// Present the involuntary-sign-out sign-in sheet if — right now — the user is signed out,
    /// didn't choose to be, and still has Tier-2 alert intent stored (global types or any team
    /// bell). Recomputed live (not read from the persisted sentinel) so it can't race the
    /// coordinator's async reconcile; one-shot per launch; "Not now" re-presents next cold
    /// launch while the state is still broken (still broken → still worth one honest mention).
    private func maybePresentSignedOutAlertNudge() {
        guard !didPresentSignedOutNudge, !auth.isSignedIn else { return }
        guard !UserDefaults.standard.bool(forKey: SignOutSentinels.deliberateSignOut) else { return }
        guard notifications.snapshot.anyServerPushEnabled || teamAlerts.enabledCount > 0 else { return }
        didPresentSignedOutNudge = true
        showSignedOutAlertNudge = true
    }

    /// Ensure this device has a registered APNs token whenever the app opens (cold launch + every
    /// foreground) and re-flush the V2 push-to-start token — the "check every time, self-heal" fix
    /// for the empty-token bug. Near-zero cost: `registerForRemoteNotifications()` just re-delivers
    /// the cached token when already authorized (no network to Apple), and the Supabase upsert is
    /// guarded to only write when the token/user changed. Keeps the model opt-in: only re-requests
    /// permission for a signed-in user who already has ≥1 alert on (the reinstall/restored-on state).
    private func reconcileNotificationRegistration() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let laEnabled = LiveActivityManager.areActivitiesEnabled
        let wantsNotifs = notifications.snapshot.anyEnabled || teamAlerts.enabledCount > 0
        NotifTrace.shared.log("reconcile", .ok,
            "auth=\(status.traceLabel) la=\(laEnabled) signedIn=\(auth.userID != nil) wantsNotifs=\(wantsNotifs)")

        switch status {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            NotifTrace.shared.log("register-called", .ok, status.traceLabel)
        case .notDetermined where auth.userID != nil && wantsNotifs:
            // Reinstall/restored-on: alerts are on but iOS permission was reset. Re-request
            // (owner-approved) so the token can register — no Settings trip needed.
            NotifTrace.shared.log("reprompt", .ok, "notDetermined + wantsNotifs → requesting")
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
                NotifTrace.shared.log("register-called", .ok, "after reprompt")
            } else {
                NotifTrace.shared.log("reprompt", .skip, "not granted at reprompt")
            }
        case .notDetermined:
            NotifTrace.shared.log("reconcile", .skip, "notDetermined, no alert intent — respecting opt-in")
        case .denied:
            if wantsNotifs {
                // Honest LOUD failure: they think alerts are on but iOS blocks them; iOS forbids a
                // re-prompt, so this needs a Settings trip (surfaced in the diagnostics screen).
                Diagnostics.shared.record(.apiFailure, "notifications DENIED but alerts on — user gets no pushes")
                NotifTrace.shared.log("reconcile", .fail, "denied but wantsNotifs — needs Settings")
            }
        @unknown default:
            break
        }

        // Retry any previously-failed device-token upload, re-flush the V2 push-to-start token
        // (fixes the returning-user session race), and push the trace to Supabase.
        notificationSyncCoordinator?.resync()
        await LiveActivityManager.shared.reflushStartToken(reason: "reconcile")
        await NotifTrace.shared.flush()
    }
}

extension UNAuthorizationStatus {
    /// Compact label for the diagnostics trail.
    var traceLabel: String {
        switch self {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
}

// TEMP: iOS 27 beta Liquid Glass tab-bar relayout workaround — remove once Apple patches.
//
// On iOS 27 beta 1 / iPhone 17 Pro hardware, the bottom tab-bar labels render garbled/ghosted
// on first appearance and only clean up after the user taps each tab a second time — a known
// system Liquid Glass compositing regression (reproduces in Apple's own apps; NOT our code; does
// NOT reproduce on regular iPhone 17, older Pros, or the simulator). This bridge programmatically
// does what the manual "second tap" does: it forces ONE corrective UITabBar relayout pass on first
// appearance, deferred to the next runloop (the first pass is the corrupted one). Gated by the
// shared `done` binding so it fires exactly once per session, then no-ops.
//
// Attach via `.background(...)` on each tab's CONTENT (a content hosting controller reliably
// resolves `.tabBarController`; the TabView's own background may not). Defensive only — verify by
// "builds, runs, doesn't break other devices," not by reproducing the glitch.
//
// FALLBACK (do NOT implement unless asked): if the bar still re-corrupts on device, opt the tab bar
// out of the Liquid Glass material with an opaque `UITabBarAppearance`. Escalation: if it re-corrupts
// on tab *switch* (not just cold launch), gate on each selection change instead of once per session.
private struct TabBarRelayoutBridge: UIViewControllerRepresentable {
    @Binding var done: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard !done else { return }
        DispatchQueue.main.async {
            guard let bar = vc.tabBarController?.tabBar else { return }
            bar.setNeedsLayout()
            bar.layoutIfNeeded()
            bar.subviews.forEach { $0.setNeedsDisplay() }
            done = true
        }
    }
}

#Preview {
    RootTabView()
}
