//
//  NotificationPreferencesStore.swift
//  NWSLApp
//
//  The user's notification preferences — the 9 toggles on the Profile screen
//  (Match Day + Activity). Shared app-wide state persisted to UserDefaults and
//  injected via `.environment`, mirroring FeedPreferencesStore.
//
//  TEMP (no delivery yet): these toggles persist the user's *intent* only. Actual
//  notifications need APNs + the server poller (live updates) or local scheduling
//  (kickoff reminders) — see CLAUDE.md What's-Next #12. When that lands, the
//  scheduler reads these same flags; nothing here changes.
//

import Foundation

/// A plain value snapshot of all nine toggles — the shape that mirrors up to the
/// Supabase `notification_preferences` row so the match-watcher Worker can honor
/// "goals: off" without asking the device. Kept SDK-free (no Supabase import) so
/// the store stays pure; NotificationPrefsSyncService maps it to/from the row.
struct NotificationPreferencesSnapshot: Equatable {
    var dayBefore: Bool
    var lineupPosted: Bool
    var kickoff: Bool
    var goals: Bool
    var halftime: Bool
    var fullTime: Bool
    var substitutions: Bool
    var fanZoneRounds: Bool
    var playerSpotlight: Bool
    var liveActivitiesEnabled: Bool

    /// Any toggle on ⇒ the user has opted into notifications, so we may reconcile/re-request
    /// permission for them (used by the launch/foreground registration reconcile). Keeps the
    /// model opt-in: a user with everything off is never prompted.
    var anyEnabled: Bool {
        dayBefore || lineupPosted || kickoff || goals || halftime || fullTime
            || substitutions || fanZoneRounds || playerSpotlight || liveActivitiesEnabled
    }

    /// Any Tier-2 (server-push) type on — the "opted into live alerts" predicate. These are the
    /// types that structurally CANNOT deliver without a signed-in account (the watcher keys them
    /// to a Supabase user), so "signed out + anyServerPushEnabled" is the involuntary-sign-out
    /// desync both NotificationSyncCoordinator (sentinel + telemetry) and RootTabView (the
    /// auto-presented sign-in nudge) test for. Tier-1 locals (dayBefore, playerSpotlight) and
    /// deferred intents are deliberately excluded — they work signed-out.
    var anyServerPushEnabled: Bool {
        kickoff || goals || halftime || fullTime || lineupPosted || liveActivitiesEnabled
    }
}

/// Persisted cross-store sentinels for surfacing an INVOLUNTARY sign-out (a lapsed/lost Supabase
/// session) to a user who had opted into Tier-2 alerts. Two flags because "signed out with alert
/// intent stored" alone can't distinguish *chose this* from *happened to them* — and only the
/// second may nag (owner rule: a deliberate sign-out means you already know).
///
/// Lifecycle:
///  - `deliberateSignOut` — set by AuthStore BEFORE an explicit Sign Out / account delete drops the
///    session; cleared on the next successful sign-in. While set, the desync reconcile stays quiet.
///  - `tier2WasOnAtSignOut` — set (once, with telemetry) by NotificationSyncCoordinator when it
///    observes signed-out + Tier-2 intent stored + not deliberate; cleared by AuthStore on sign-in
///    success, explicit sign-out, and account delete.
enum SignOutSentinels {
    static let tier2WasOnAtSignOut = "notif.tier2WasOnAtSignOut"
    static let deliberateSignOut = "auth.deliberateSignOut"
}

@Observable
final class NotificationPreferencesStore {
    // MARK: Match Day
    var dayBefore: Bool      { didSet { persist(dayBefore, "dayBefore"); onPreferenceChanged?() } }
    var lineupPosted: Bool   { didSet { persist(lineupPosted, "lineupPosted"); onPreferenceChanged?() } }
    var kickoff: Bool        { didSet { persist(kickoff, "kickoff"); onPreferenceChanged?() } }
    var goals: Bool          { didSet { persist(goals, "goals"); onPreferenceChanged?() } }
    var halftime: Bool       { didSet { persist(halftime, "halftime"); onPreferenceChanged?() } }
    var fullTime: Bool       { didSet { persist(fullTime, "fullTime"); onPreferenceChanged?() } }
    var substitutions: Bool  { didSet { persist(substitutions, "substitutions"); onPreferenceChanged?() } }

    // MARK: Activity
    var fanZoneRounds: Bool  { didSet { persist(fanZoneRounds, "fanZoneRounds"); onPreferenceChanged?() } }
    var playerSpotlight: Bool { didSet { persist(playerSpotlight, "playerSpotlight"); onPreferenceChanged?() } }

    // MARK: Live Activities (V2)
    /// The V2 Live Activity glance layer (lock screen + Dynamic Island live score). A Tier-2 OPT-IN
    /// (default OFF, sign-in-gated like Kickoff/Goals): the watcher push-to-starts it, which needs an
    /// account. Server-read (the watcher gates on this AND team_alert_preferences); the app uploads the
    /// push-to-start token regardless (cheap/idempotent). Preserved (display-gated) across sign-out;
    /// reset only on account delete (`resetServerPushTypes`).
    var liveActivitiesEnabled: Bool { didSet { persist(liveActivitiesEnabled, "liveActivitiesEnabled"); onPreferenceChanged?() } }

    /// All toggles as a value snapshot. Reading it touches every flag, so it
    /// also doubles as the single property NotificationSyncCoordinator observes via
    /// withObservationTracking to mirror any change up to Supabase.
    var snapshot: NotificationPreferencesSnapshot {
        NotificationPreferencesSnapshot(
            dayBefore: dayBefore,
            lineupPosted: lineupPosted,
            kickoff: kickoff,
            goals: goals,
            halftime: halftime,
            fullTime: fullTime,
            substitutions: substitutions,
            fanZoneRounds: fanZoneRounds,
            playerSpotlight: playerSpotlight,
            liveActivitiesEnabled: liveActivitiesEnabled
        )
    }

    /// Fired after any toggle changes, so the NotificationScheduler can rebuild
    /// local notifications. Optional and nil by default — when nil (no scheduler
    /// wired, tests, previews) the store behaves exactly as before. Mirrors
    /// FollowingStore.onFollowsChanged. Property observers don't run during `init`,
    /// so loading persisted defaults never fires this.
    var onPreferenceChanged: (() -> Void)?

    private let defaults: UserDefaults
    private static let prefix = "notif."
    /// One-time sentinel: has the first-bell default bundle been applied yet? (see
    /// `applyMatchAlertDefaultsIfFirstTime`). Reset on sign-out so a returning user re-cascades.
    private static let appliedDefaultsKey = "notif.appliedAlertDefaults"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` so an unset pref takes the default, not `bool(forKey:)`'s false.
        // Invariant: **Tier 2 DISPLAYED-ON ⟹ signed in.** Turning a type on is sign-in-gated
        // (`tier2Binding`), and while signed out the STORED value is display-gated to read off
        // (NotificationsView + the desync sentinel) rather than destructively reset — so a
        // re-sign-in restores the exact prior selection. Only account delete wipes them.
        func load(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: Self.prefix + key) as? Bool ?? value
        }
        // PURE OPT-IN: every toggle defaults OFF, nothing is ever auto-enabled. The user turns on
        // exactly what they want (discoverable via the Teams-tab coaching note → the gear icon, and the
        // Alert-types section un-graying when a team's alerts go on). No dark-pattern default-ons.
        dayBefore = load("dayBefore", default: false)         // Tier 1 (local)
        playerSpotlight = load("playerSpotlight", default: false) // Tier 1 (local)
        fanZoneRounds = load("fanZoneRounds", default: false) // activity (local intent)
        kickoff = load("kickoff", default: false)             // Tier 2 (server push)
        goals = load("goals", default: false)                 // Tier 2 (server push)
        halftime = load("halftime", default: false)           // Tier 2 (server push)
        fullTime = load("fullTime", default: false)           // Tier 2 (server push)
        lineupPosted = load("lineupPosted", default: false)   // Tier 2 (server, Stage D)
        substitutions = load("substitutions", default: false) // Tier 2 (server, Stage D)
        liveActivitiesEnabled = load("liveActivitiesEnabled", default: false) // Tier 2 (V2 Live Activity)
    }

    private func persist(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: Self.prefix + key)
    }

    /// Turn off every Tier-2 (server-push) type — kickoff, goals, halftime, full-time, AND the V2 Live
    /// Activity. Called ONLY from account-delete teardown (ProfileView.runDeleteAccount): a deleted
    /// account starts truly fresh. A plain sign-out no longer calls this (involuntary-sign-out fix) —
    /// stored toggles are preserved and display-gated on auth instead, so a re-sign-in restores the
    /// exact prior selection. The Tier-1 locals stay — they work signed-out. Each setter persists +
    /// fires `onPreferenceChanged`.
    func resetServerPushTypes() {
        kickoff = false
        goals = false
        halftime = false
        fullTime = false
        lineupPosted = false
        liveActivitiesEnabled = false
        // Also clear the first-bell sentinel: sign-out wiped the Tier-2 intent, so a returning
        // signed-in user's next bell tap must re-cascade the bundle — otherwise they'd land back in
        // the silent-failure paradox (bell on, nothing fires). A sign-out reset is NOT a manual
        // per-type override, so this honors the "respect the user's edits" rule.
        defaults.set(false, forKey: Self.appliedDefaultsKey)
    }

    /// INTENT-DRIVEN DEFAULTS (docs / plan §Phase 1). The FIRST time the user turns on match alerts
    /// for any team (an explicit bell tap = an explicit opt-in), cascade the FULL alert bundle once so
    /// the feature works out of the box and makes the best first impression — rather than turning a team
    /// on with every alert-type off (the silent-failure paradox the owner hit). Guarded by a one-time
    /// sentinel so a SECOND team's bell never re-enables types the user has since turned off: their
    /// manual edits are respected. NOT a dark pattern — the bell tap is the opt-in (see the CLAUDE.md
    /// notifications rule). Each setter persists + fires `onPreferenceChanged` (local reschedule +
    /// Supabase mirror). Callers gate on sign-in first (the bundle is mostly Tier-2), so this runs
    /// signed-in and the Tier-2 fields mirror up cleanly.
    func applyMatchAlertDefaultsIfFirstTime() {
        guard !defaults.bool(forKey: Self.appliedDefaultsKey) else { return }
        dayBefore = true
        kickoff = true
        goals = true
        halftime = true
        fullTime = true
        lineupPosted = true
        liveActivitiesEnabled = true
        defaults.set(true, forKey: Self.appliedDefaultsKey)
    }

    #if DEBUG
    /// Wipe notification first-run state so `-resetOnboarding` simulates a brand-NEW
    /// user. Clears every toggle (so `init` re-applies the fresh all-OFF opt-in defaults) and the
    /// Teams-tab match-alert coach mark so it re-fires. Mirrors `FollowingStore.debugResetState`; runs
    /// (from `NWSLAppApp.init`) before the store is constructed.
    static func debugResetState(defaults: UserDefaults = .standard) {
        // The one-time Teams-tab "Manage your match alerts here" coach mark
        // (TeamsView @AppStorage) — clear so a reset re-shows it for a true new user.
        defaults.removeObject(forKey: "hasSeenTeamsAlertTooltip")
        defaults.removeObject(forKey: appliedDefaultsKey)   // re-arm the first-bell cascade
        for key in ["dayBefore", "playerSpotlight", "fanZoneRounds", "kickoff", "goals",
                    "halftime", "fullTime", "lineupPosted", "substitutions", "liveActivitiesEnabled"] {
            defaults.removeObject(forKey: prefix + key)
        }
    }
    #endif
}
