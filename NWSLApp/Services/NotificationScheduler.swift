//
//  NotificationScheduler.swift
//  NWSLApp
//
//  Owns all *local* notification scheduling — the Tier 1 reminders the phone can
//  fire by itself, with no server: the day-before match reminder and the weekly
//  Know Her Game "new round" nudge. (Tier 2 — live kickoff/goals/halftime/full-time
//  — is server push via APNs and a match-watcher Worker; it does not live here.)
//
//  The KHG nudge follows the SCHEDULED-notification model (docs/notifications.md's
//  event-driven-vs-scheduled rule): fire at a good LOCAL hour, never before content
//  is live, never at night — see `spotlightFireDate`.
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
        let daySpecs = dayBeforeSpecs()
        let spotSpecs = spotlightSpecs()
        let signature = Self.scheduleSignature(dayBefore: daySpecs, spotlight: spotSpecs)
        guard signature != lastScheduleSignature else { return }   // nothing changed → skip the churn
        lastScheduleSignature = signature

        // Render behind the gate: only now (the set changed) do we pay for the card images.
        var requests = daySpecs.compactMap(request(from:))
        requests += spotSpecs.compactMap(spotlightRequest(from:))

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

    /// Order-independent hash of the day-before set + the KHG spotlight set. Each spec is `Hashable`
    /// over its identifier, STABLE fireDate, and content — so a re-render triggers when (and only when)
    /// any of those change. ⚠️ We hash the fireDate, NOT a now-relative interval: the old
    /// `scheduleSignature(of:)` hashed the trigger's `timeInterval`, which decays every second, so any
    /// pending reminder defeated the churn gate and the 60s live-poll rebuilt the whole set every minute.
    /// The spotlight specs hash their absolute fireDates too, so the set is byte-identical within a week
    /// (no churn) and rehashes exactly once when a week rolls — re-arming the nudge on the next foreground.
    /// An empty spotlight array encodes "opt-in off", so no separate bool is needed.
    nonisolated static func scheduleSignature(dayBefore: [DayBeforeSpec], spotlight: [SpotlightSpec]) -> Int {
        var hasher = Hasher()
        for spec in dayBefore.sorted(by: { $0.identifier < $1.identifier }) { hasher.combine(spec) }
        for spec in spotlight.sorted(by: { $0.identifier < $1.identifier }) { hasher.combine(spec) }
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

    // MARK: - Weekly Know Her Game nudge (scheduled-class — local-time, quiet-hours-guarded)
    //
    // The standing rule (docs/notifications.md): a SCHEDULED "new content" notification is delivered on the
    // LOCAL-TIME model — anchored to a good local hour (10 AM), gated to never precede the content going
    // live, and quiet-hours-guarded (no night pings). (This is the event-driven-vs-scheduled axis, distinct
    // from the delivery Tier 1/Tier 2 = local/watcher-push axis; this nudge is delivery-Tier-1 local.) NWSL
    // is worldwide (100+ followable national teams, international stars), so a fan in London/Sydney must
    // never be told "new round" before it exists. KHG content publishes at a single global UTC instant;
    // only the NUDGE is per-timezone. Trivia gets no nudge by design; the future bracket-round nudge
    // inherits this same model.

    static let spotlightTitle = "New Know Her Game"
    static let spotlightBody = "This week's players are ready. How well do you know them?"

    /// One built KHG "new round" nudge. `Hashable` so it folds into the rebuild signature; the fireDate is
    /// a STABLE absolute instant (never a decaying interval — see `scheduleSignature`).
    struct SpotlightSpec: Hashable {
        let identifier: String    // "nwsl.spotlight.<mondayOrdinal>"
        let fireDate: Date
        let title: String
        let body: String
    }

    /// How many upcoming KHG drops to keep scheduled. KHG is biweekly, so 4 ≈ 8 weeks of lead; the set
    /// re-arms whenever the app foregrounds (`observeStores` → `reschedule`). Kept small to preserve
    /// headroom under iOS's 64-pending cap (4 + the day-before window ≤ 50 stays well clear).
    private static let spotlightHorizon = 4

    /// The upcoming KHG nudge specs (pure — no I/O). Empty when the opt-in is off. One per upcoming KHG
    /// drop Monday, each fired on the scheduled local-time model (`spotlightFireDate`); Trivia drop weeks
    /// produce nothing.
    private func spotlightSpecs() -> [SpotlightSpec] {
        guard preferences.playerSpotlight else { return [] }
        let now = Date()
        return FanZoneCadence.upcomingKnowHerDrops(from: now, count: Self.spotlightHorizon).compactMap { monday in
            guard let fire = Self.spotlightFireDate(dropMonday: monday, now: now) else { return nil }
            return SpotlightSpec(
                identifier: "nwsl.spotlight.\(FanZoneCadence.mondayOrdinal(monday))",
                fireDate: fire, title: Self.spotlightTitle, body: Self.spotlightBody)
        }
    }

    /// The instant to fire the KHG nudge for `dropMonday`'s week: the LATER of the device's local Monday
    /// 10:00 (so it reads as a Monday-morning nudge) and the moment KHG content is actually live worldwide
    /// (`availabilityInstant` + a propagation buffer), then quiet-hours-guarded so it never lands at night.
    /// Returns nil if that instant has already passed. `calendar`/`now` are injected so the timezone
    /// behaviour is unit-testable.
    ///
    /// The `max` guarantees "fire ≥ content-live" for EVERY timezone (a fan east of the publisher — London,
    /// Sydney — must not be told "new round" before it exists). The night guard handles the far-east, where
    /// content going live in local evening/night rolls to the next morning rather than pinging at 11 PM.
    /// Worked cases: LA/NY → Mon 10 AM local; Hawaii → Mon 10 AM (no midnight ping); London → ~11 AM;
    /// Sydney → ~8 PM same-day; Auckland → Tue 10 AM.
    nonisolated static func spotlightFireDate(
        dropMonday: Date,                       // FanZoneCadence.weekStart → UTC Monday 00:00
        calendar: Calendar = .current,          // the device's timezone
        now: Date = Date(),
        buffer: TimeInterval = 10 * 60,         // covers the ≤5-min edge cache + publish propagation
        eveningCutoffHour: Int = 21             // 9 PM: no nudge at/after this local hour → roll to next 10 AM
    ) -> Date? {
        let availability = FanZoneCadence.availabilityInstant(for: .knowHerGame, dropMonday: dropMonday)

        // "Local Monday 10:00": take the UTC Monday's calendar DATE LABELS (Y/M/D) and reinterpret them at
        // 10:00 in the device timezone. Deriving from the labels — not from the availability instant's local
        // calendar day — keeps the anchor on the correct Monday even when the offset pushes the instant into
        // Sunday locally (US-west) or Tuesday (far-east).
        var utc = Calendar(identifier: .iso8601)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let ymd = utc.dateComponents([.year, .month, .day], from: dropMonday)
        var local = DateComponents()
        local.year = ymd.year; local.month = ymd.month; local.day = ymd.day
        local.hour = 10; local.minute = 0
        guard let localMonday10 = calendar.date(from: local) else { return nil }

        var fire = max(localMonday10, availability.addingTimeInterval(buffer))

        // Quiet-hours guard: keep the fire in [10:00, eveningCutoffHour) local; otherwise advance to the
        // next local 10:00 AM at-or-after it. Only the extreme far-east (UTC+12+) ever trips this.
        let hour = calendar.component(.hour, from: fire)
        if hour < 10 || hour >= eveningCutoffHour {
            if let rolled = calendar.nextDate(after: fire,
                                              matching: DateComponents(hour: 10, minute: 0),
                                              matchingPolicy: .nextTime) {
                fire = rolled
            }
        }

        return fire > now ? fire : nil
    }

    /// Turn a KHG nudge spec into a request, using the day-before absolute-instant trigger. `nil` if the
    /// fire moment slid into the past between building and adding.
    private func spotlightRequest(from spec: SpotlightSpec) -> UNNotificationRequest? {
        let interval = spec.fireDate.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = .default
        return UNNotificationRequest(
            identifier: spec.identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }
}
