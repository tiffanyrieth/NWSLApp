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
#if DEBUG
import SwiftUI   // ImageRenderer, for the -testDayBeforeCard render-to-Documents debug affordance
#endif

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
        #if DEBUG
        // `-testDayBeforeCard`: fire one synthetic day-before card ~5s out to eyeball the attachment
        // in the sim (local notifications DO deliver in the simulator, unlike push).
        if ProcessInfo.processInfo.arguments.contains("-testDayBeforeCard") { debugFireTestCard() }
        #endif
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

    /// A hash of the set we last actually scheduled, so a reschedule triggered by an UNRELATED store
    /// change is a no-op when the built set is identical. `observeStores` watches `matches.state`, which
    /// `MatchStore` reassigns on EVERY ~60s live-poll refresh — without this gate a live match rebuilt the
    /// whole day-before/spotlight set every minute (removeAll + ~50 add) and reopened a repeated window
    /// where all pending reminders were briefly gone. In-memory only (Hasher's per-run seed = within-process).
    private var lastScheduleSignature: Int?

    /// Rebuild all local notifications from scratch. Idempotent. Builds the day-before SPECS
    /// (pure, no I/O) first and gates on the signature — only when the built set actually changed
    /// do we render the card images (a handful of flat ImageRenderer passes) and re-add.
    func reschedule() {
        let specs = dayBeforeSpecs()
        let signature = Self.scheduleSignature(dayBefore: specs, spotlightEnabled: preferences.playerSpotlight)
        guard signature != lastScheduleSignature else { return }   // nothing changed → skip the churn
        lastScheduleSignature = signature

        // Render behind the gate: only now (the set changed) do we pay for the card images.
        var requests = specs.compactMap(request(from:))
        if preferences.playerSpotlight { requests.append(weeklySpotlightRequest()) }

        Task {
            // We own every locally-scheduled request, so clearing all pending ones
            // is a clean rebuild (delivered/server pushes are unaffected).
            center.removeAllPendingNotificationRequests()
            for request in requests {
                // A failed add means the user silently won't get that reminder — flag it.
                do { try await center.add(request) }
                catch { Diagnostics.shared.record(.apiFailure, "notif schedule \(request.identifier): \(error.localizedDescription)") }
            }
        }
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        lastScheduleSignature = nil   // force a full rebuild on the next reschedule
    }

    /// Order-independent hash of the day-before set (+ the spotlight bool). Each `DayBeforeSpec`
    /// is `Hashable` over its identifier, STABLE fireDate, title, body, card, and assetToken — so a
    /// re-render triggers when (and only when) any of those change. ⚠️ We hash the fireDate, NOT a
    /// now-relative interval: the old `scheduleSignature(of:)` hashed the trigger's `timeInterval`,
    /// which decays every second, so any pending day-before reminder defeated the churn gate and the
    /// 60s live-poll rebuilt the whole set every minute.
    nonisolated static func scheduleSignature(dayBefore: [DayBeforeSpec], spotlightEnabled: Bool) -> Int {
        var hasher = Hasher()
        for spec in dayBefore.sorted(by: { $0.identifier < $1.identifier }) { hasher.combine(spec) }
        hasher.combine(spotlightEnabled)
        return hasher.finalize()
    }

    /// Keep the NEXT `perTeamLimit` fixtures per followed team, sorted by kickoff, up to a global
    /// `cap` — iOS caps PENDING local notifications at 64/app, and the prune-all rebuild slides the
    /// window forward as matches are played. Pure + generic so it's unit-tested without a full spec.
    nonisolated static func windowed<T>(
        _ candidates: [(followed: String, kickoff: Date, value: T)],
        perTeamLimit: Int = 2, cap: Int = 50
    ) -> [T] {
        var perTeam: [String: Int] = [:]
        var out: [T] = []
        for candidate in candidates.sorted(by: { $0.kickoff < $1.kickoff }) {
            if perTeam[candidate.followed, default: 0] >= perTeamLimit { continue }
            perTeam[candidate.followed, default: 0] += 1
            out.append(candidate.value)
            if out.count >= cap { break }
        }
        return out
    }

    /// Turn a built spec into a request — rendering the card image (text-only if the render fails,
    /// via DayBeforeCardRenderer's diagnostic path). `nil` if the fire moment slid inside 24h
    /// between building and adding.
    private func request(from spec: DayBeforeSpec) -> UNNotificationRequest? {
        let interval = spec.fireDate.timeIntervalSinceNow
        guard interval > 0 else { return nil }

        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        if let attachment = DayBeforeCardRenderer.attachment(for: spec.card, eventID: spec.eventID) {
            content.attachments = [attachment]   // nil → text-only (already diagnosed); never skip the reminder
        }
        return UNNotificationRequest(
            identifier: spec.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
    }

    // MARK: - Day-before reminders

    /// One built day-before reminder — everything needed WITHOUT rendering, so the signature gate
    /// compares cheaply before any image work. `Hashable` so it folds into the rebuild signature.
    struct DayBeforeSpec: Hashable {
        let identifier: String            // "nwsl.<eventID>.dayBefore"
        let eventID: String
        let fireDate: Date                // kickoff − 24h — STABLE (not a decaying interval)
        let title: String
        let body: String
        let card: DayBeforeCardModel
        let assetToken: String            // crest-override presence ("h1|a0") — a rebrand retriggers a rebuild
    }

    /// The windowed set of day-before specs (pure — no rendering, no I/O beyond store reads).
    private func dayBeforeSpecs() -> [DayBeforeSpec] {
        let candidates = dayBeforeCandidates()
        return Self.windowed(candidates.map { (followed: $0.followed, kickoff: $0.kickoff, value: $0.spec) })
    }

    /// Build a spec per eligible upcoming fixture for a followed+alerting team.
    private func dayBeforeCandidates() -> [(followed: String, kickoff: Date, spec: DayBeforeSpec)] {
        // Abbreviations of followed clubs that get the day-before reminder: the team's 🔔 is on AND
        // the GLOBAL day-before alert type is on. Scoreboard competitors carry an abbreviation, not a
        // club id, so we resolve through the directory (the same join MatchStore.matches(for:) uses).
        guard preferences.dayBefore else { return [] }
        let alertingClubAbbreviations = Set(
            clubs.clubs
                .filter { following.followedIDs.contains($0.id) && alerts.alertsEnabled(for: $0.id) }
                .map { $0.abbreviation }
        )
        // National teams share the same per-team alert store, keyed by FIFA code — and that code IS
        // the abbreviation their matches carry, so an alerting code joins to events directly.
        let alertingNationalCodes = following.followedNationalTeams
            .filter { alerts.alertsEnabled(for: $0) }
        let alertingAbbreviations = alertingClubAbbreviations.union(alertingNationalCodes)
        guard !alertingAbbreviations.isEmpty else { return [] }

        return matches.events.compactMap { event in
            // Upcoming only, and only if the day-before moment is still in the future (skips
            // in-progress/past and games already inside 24h).
            guard event.statusState == "pre", let kickoff = event.kickoff else { return nil }
            let fireDate = kickoff.addingTimeInterval(-Self.dayBeforeLeadTime)
            guard fireDate > Date() else { return nil }

            guard let home = event.homeCompetitor?.team?.abbreviation,
                  let away = event.awayCompetitor?.team?.abbreviation,
                  alertingAbbreviations.contains(home) || alertingAbbreviations.contains(away)
            else { return nil }

            // The FOLLOWED side names the title's subject; if both are followed, home leads.
            let followed = alertingAbbreviations.contains(home) ? home : away
            guard let content = DayBeforeContent.make(event: event, followedAbbr: followed, clubs: clubs.clubs)
            else { return nil }

            let spec = DayBeforeSpec(
                identifier: "nwsl.\(event.id).dayBefore",
                eventID: event.id,
                fireDate: fireDate,
                title: content.title,
                body: content.body,
                card: content.card,
                assetToken: assetToken(home: home, away: away)
            )
            return (followed: followed, kickoff: kickoff, spec: spec)
        }
    }

    /// Presence flags for each side's crest OVERRIDE ("h1|a0") — folded into the signature so a
    /// downloaded rebrand override re-renders the card. (A replaced override image doesn't flip a
    /// presence flag; the next real content change re-renders. Documented, acceptable.)
    private func assetToken(home: String, away: String) -> String {
        func present(_ abbr: String) -> String {
            let key = abbr.uppercased()
            let has = AssetRefreshService.override(crest: key) != nil
                || AssetRefreshService.override(flag: key) != nil
            return has ? "1" : "0"
        }
        return "h\(present(home))|a\(present(away))"
    }

    #if DEBUG
    /// `-testDayBeforeCard`: schedule ONE synthetic day-before card ~5s out so the attachment can be
    /// eyeballed in the sim. Background the app after launch, wait, long-press the banner.
    private func debugFireTestCard() {
        let event = Event(
            id: "debug",
            date: "2026-08-01T20:00Z",
            competitions: [Competition(
                competitors: [
                    Competitor(homeAway: "home", score: "0",
                               team: Team(displayName: "Washington Spirit", abbreviation: "WAS", shortDisplayName: "Spirit")),
                    Competitor(homeAway: "away", score: "0",
                               team: Team(displayName: "Portland Thorns FC", abbreviation: "POR", shortDisplayName: "Thorns")),
                ],
                broadcasts: [Broadcast(names: ["ESPN"])]
            )]
        )
        guard let content = DayBeforeContent.make(event: event, followedAbbr: "WAS", clubs: clubs.clubs) else { return }
        // Also drop the rendered card PNG into Documents so the exact offscreen render can be pulled
        // for inspection (notification banners are permission-gated + not screenshot-able headlessly).
        if let png = ImageRenderer(content: DayBeforeCardView(model: content.card)).uiImage?.pngData(),
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? png.write(to: docs.appendingPathComponent("dayBeforeCard-debug.png"))
        }
        let notif = UNMutableNotificationContent()
        notif.title = content.title
        notif.body = content.body
        notif.sound = .default
        if let attachment = DayBeforeCardRenderer.attachment(for: content.card, eventID: "debug") {
            notif.attachments = [attachment]
        }
        let request = UNNotificationRequest(
            identifier: "nwsl.debug.dayBefore",
            content: notif,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        Task { try? await center.add(request) }
    }
    #endif

    // MARK: - Weekly Player Spotlight

    private func weeklySpotlightRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "New Know Her Game"
        content.body = "This week's players are ready — how well do you know them?"
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
