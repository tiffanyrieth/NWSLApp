//
//  NotificationScheduler.swift
//  NWSLApp
//
//  Owns all *local* notification scheduling — the Tier 1 reminders the phone can
//  fire by itself, with no server: the day-before match reminder and the weekly
//  Player Spotlight. (Tier 2 — live kickoff/goals/halftime/full-time — is server
//  push via APNs and a match-watcher Worker; it does not live here.)
//
//  Like FollowSyncCoordinator, this is a coordinator the root holds alive and
//  starts after launch — it is NOT injected into the environment, because no view
//  reads it. It depends on the shared stores; none of them depend on it. Stores
//  stay pure: the only `UNUserNotificationCenter` *scheduling* lives here.
//  (Permission prompting is a UI concern tied to the toggle gesture, so it lives
//  in ProfileView; see there.)
//
//  Rescheduling is "cancel everything, rebuild from scratch" and idempotent, with
//  deterministic identifiers, so a moved/cancelled game's stale reminder is
//  replaced the next time the app refreshes its data. We do NOT gate scheduling on
//  authorization: requests are added regardless, and iOS decides at *delivery*
//  time whether the user has granted permission — which avoids a prompt/reschedule
//  race and means a later "allow" in Settings starts delivering with no extra work.
//
//  `@MainActor` because it reads SwiftUI-observed stores and uses
//  withObservationTracking, which must register on the actor that mutates them.
//

import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let matches: MatchStore
    private let following: FollowingStore
    private let clubs: ClubStore
    private let preferences: NotificationPreferencesStore
    private let alerts: TeamAlertStore

    /// Deterministic identifier prefix so every rebuild replaces the prior set
    /// cleanly (see `nwsl.{eventID}.dayBefore`, `nwsl.spotlight.weekly`).
    private static let dayBeforeLeadTime: TimeInterval = 24 * 60 * 60

    init(
        matches: MatchStore,
        following: FollowingStore,
        clubs: ClubStore,
        preferences: NotificationPreferencesStore,
        alerts: TeamAlertStore
    ) {
        self.matches = matches
        self.following = following
        self.clubs = clubs
        self.preferences = preferences
        self.alerts = alerts
    }

    /// Wire up rescheduling. Call once, after the session restores, from RootTabView.
    func start() {
        // A preference toggle reschedules. `onPreferenceChanged` is unclaimed
        // (unlike FollowingStore.onFollowsChanged, which FollowSyncCoordinator
        // owns), so the scheduler can take it.
        preferences.onPreferenceChanged = { [weak self] in self?.reschedule() }
        observeStores()
        reschedule()
    }

    // MARK: - Observation

    // Reschedule whenever the season loads, the club directory loads (we need it
    // to map followed ids → abbreviations), or the followed set changes. We watch
    // `followedIDs` directly rather than FollowingStore.onFollowsChanged because
    // that single closure already belongs to FollowSyncCoordinator.
    private func observeStores() {
        withObservationTracking {
            _ = matches.state
            _ = clubs.state
            _ = following.followedIDs
            _ = following.followedNationalTeams
            // A team's 🔔 on/off must reschedule too. The store's onAlertChanged
            // closure is owned by TeamAlertSyncCoordinator, so we observe the set
            // directly (same reason we watch followedIDs, not onFollowsChanged). The
            // global day-before TYPE toggle reschedules via preferences.onPreferenceChanged.
            _ = alerts.enabledTeamIDs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reschedule()
                self.observeStores()
            }
        }
    }

    // MARK: - Rescheduling

    /// Rebuild all local notifications from scratch. Idempotent. Reads the stores
    /// on the main actor, then performs the center mutations off the synchronous path.
    func reschedule() {
        let requests = buildRequests()
        Task {
            // We own every locally-scheduled request, so clearing all pending ones
            // is a clean rebuild (delivered/server pushes are unaffected).
            center.removeAllPendingNotificationRequests()
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    private func buildRequests() -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        // Day-before is gated per-team inside (alertsEnabled && dayBefore), so it's
        // always considered here — the empty-set guard handles "nobody opted in".
        requests.append(contentsOf: dayBeforeRequests())
        if preferences.playerSpotlight { requests.append(weeklySpotlightRequest()) }
        return requests
    }

    // MARK: - Day-before reminders

    private func dayBeforeRequests() -> [UNNotificationRequest] {
        // Abbreviations of followed clubs that get the day-before reminder: the
        // team's 🔔 is on AND the GLOBAL day-before alert type is on (v2: per-team is
        // on/off, the alert TYPES are global). Scoreboard competitors carry an
        // abbreviation, not a club id, so we resolve through the directory (the same
        // fragile-but-verified join MatchStore.matches(for:) uses).
        guard preferences.dayBefore else { return [] }
        let alertingClubAbbreviations = Set(
            clubs.clubs
                .filter {
                    following.followedIDs.contains($0.id)
                        && alerts.alertsEnabled(for: $0.id)
                }
                .map { $0.abbreviation }
        )
        // National teams share the same per-team alert store, keyed by FIFA code —
        // and that code IS the abbreviation their matches carry, so an alerting code
        // joins to events directly (no directory lookup). Tier-1 day-before only;
        // Tier-2 server push for national teams rides the deferred match-watcher work.
        let alertingNationalCodes = following.followedNationalTeams
            .filter { alerts.alertsEnabled(for: $0) }
        let alertingAbbreviations = alertingClubAbbreviations.union(alertingNationalCodes)
        guard !alertingAbbreviations.isEmpty else { return [] }

        return matches.events.compactMap { event in
            // Upcoming only, and only if the day-before moment is still in the
            // future (skips in-progress/past and games already inside 24h).
            guard event.statusState == "pre", let kickoff = event.kickoff else { return nil }
            let interval = kickoff.timeIntervalSinceNow - Self.dayBeforeLeadTime
            guard interval > 0 else { return nil }

            guard let home = event.homeCompetitor?.team?.abbreviation,
                  let away = event.awayCompetitor?.team?.abbreviation,
                  alertingAbbreviations.contains(home) || alertingAbbreviations.contains(away)
            else { return nil }

            let content = UNMutableNotificationContent()
            // Two teams together → abbreviations (the app-wide naming rule).
            content.title = "Tomorrow: \(home) vs \(away)"
            content.body = dayBeforeBody(for: event)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            return UNNotificationRequest(
                identifier: "nwsl.\(event.id).dayBefore",
                content: content,
                trigger: trigger
            )
        }
    }

    /// "Kickoff at 7:30 PM · Audi Field" — kickoff time in the user's LOCAL zone.
    private func dayBeforeBody(for event: Event) -> String {
        var parts: [String] = []
        if let kickoff = event.kickoff {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = .current
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            parts.append("Kickoff at \(formatter.string(from: kickoff))")
        }
        if let venue = event.venueName { parts.append(venue) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Weekly Player Spotlight

    private func weeklySpotlightRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "New Player Spotlight"
        content.body = "This week's featured player is ready"
        content.sound = .default

        // Monday 10:00 AM, local. UNCalendarNotificationTrigger uses the device's
        // calendar + timezone by default (weekday 1 = Sunday, so 2 = Monday).
        var components = DateComponents()
        components.weekday = 2
        components.hour = 10
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(
            identifier: "nwsl.spotlight.weekly",
            content: content,
            trigger: trigger
        )
    }
}
