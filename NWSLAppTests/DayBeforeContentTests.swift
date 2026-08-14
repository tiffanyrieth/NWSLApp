//
//  DayBeforeContentTests.swift
//  NWSLAppTests
//
//  The pure day-before-reminder content seam (DayBeforeContent) + the scheduler's pure
//  windowing/signature helpers. No stores, no actor, no UNUserNotificationCenter — these
//  cover title/body/card building, the shortName fallback chain, the home-left card rule,
//  windowing, and the rebuild-signature contract (incl. the decaying-interval regression).
//

import Foundation
import Testing
@testable import NWSLApp

struct DayBeforeContentTests {

    // MARK: Fixtures

    /// A fixed Saturday kickoff: 2026-08-01 20:00 UTC = 4:00 PM EDT → "SAT" / "4:00 PM".
    private static let kickoffUTC = "2026-08-01T20:00Z"
    private static let enUS = Locale(identifier: "en_US_POSIX")
    private static let etZone = TimeZone(identifier: "America/New_York")!

    /// Build an Event with home/away competitors. Each side = (abbr, shortDisplayName?).
    private func makeEvent(
        home: (abbr: String, short: String?),
        away: (abbr: String, short: String?),
        date: String? = kickoffUTC,
        venue: String? = nil,
        broadcast: String? = nil
    ) -> Event {
        func competitor(_ side: (abbr: String, short: String?), homeAway: String) -> Competitor {
            Competitor(homeAway: homeAway, score: "0",
                       team: Team(displayName: side.abbr, abbreviation: side.abbr, shortDisplayName: side.short))
        }
        let comp = Competition(
            competitors: [competitor(home, homeAway: "home"), competitor(away, homeAway: "away")],
            venue: venue.map { Venue(fullName: $0) },
            broadcasts: broadcast.map { [Broadcast(names: [$0])] }
        )
        return Event(id: "e1", date: date, competitions: [comp])
    }

    private func make(_ event: Event, followed: String, clubs: [Club] = []) -> DayBeforeContent.Output? {
        DayBeforeContent.make(event: event, followedAbbr: followed, clubs: clubs,
                              locale: Self.enUS, timeZone: Self.etZone)
    }

    /// The expected localized kickoff time, built with the SAME locale/zone/template as production —
    /// so assertions are robust to iOS's narrow-no-break-space between time and AM/PM (U+202F, not a
    /// regular space). We're testing make()'s COMPOSITION, not re-testing Apple's time formatting.
    private static let expectedTime: String = {
        let f = DateFormatter()
        f.locale = enUS; f.timeZone = etZone
        f.setLocalizedDateFormatFromTemplate("jmm")
        let d = DateFormatter()
        d.locale = enUS; d.timeZone = TimeZone(identifier: "UTC")
        d.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f.string(from: d.date(from: kickoffUTC)!)
    }()

    // MARK: Title — shortName fallback chain

    @Test func titleUsesCompetitorShortDisplayName() {
        let event = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"))
        #expect(make(event, followed: "WAS")?.title == "Spirit play tomorrow")
    }

    @Test func titleFallsBackToDirectoryShortName() {
        // Competitor carries no shortDisplayName → fall back to the club directory's shortName.
        let event = makeEvent(home: ("WAS", nil), away: ("POR", nil))
        let clubs = [Club(id: "1", displayName: "Washington Spirit", abbreviation: "WAS",
                          logoURL: nil, shortName: "Washington")]
        #expect(make(event, followed: "WAS", clubs: clubs)?.title == "Washington play tomorrow")
    }

    @Test func titleFallsBackToNationalTeamName() {
        // National-team code, no shortDisplayName, not in the club directory → NationalTeam.name.
        let event = makeEvent(home: ("USA", nil), away: ("MEX", nil))
        #expect(make(event, followed: "USA")?.title == "United States play tomorrow")
    }

    @Test func titleLastResortIsAbbreviation() {
        let event = makeEvent(home: ("ZZZ", nil), away: ("POR", nil))
        #expect(make(event, followed: "ZZZ")?.title == "ZZZ play tomorrow")
    }

    // MARK: Body — heads-up framing

    @Test func bodyWithBroadcastIsTimeThenTV() {
        // Venue IS set on the fixture — proving it's dropped from the body.
        let event = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"),
                              venue: "Audi Field", broadcast: "ESPN")
        #expect(make(event, followed: "WAS")?.body == "\(Self.expectedTime) · ESPN")
    }

    @Test func bodyWithoutBroadcastIsTimeOnly() {
        let event = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"), venue: "Audi Field")
        #expect(make(event, followed: "WAS")?.body == Self.expectedTime)
    }

    // MARK: Card

    @Test func cardIsHomeLeftRegardlessOfFollowedSide() {
        let event = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"))
        // Following the AWAY side must NOT flip the card — home stays left.
        let followingAway = make(event, followed: "POR")?.card
        #expect(followingAway?.homeAbbr == "WAS")
        #expect(followingAway?.awayAbbr == "POR")
        // Following the HOME side → same card.
        let followingHome = make(event, followed: "WAS")?.card
        #expect(followingHome?.homeAbbr == "WAS")
        #expect(followingHome?.awayAbbr == "POR")
    }

    @Test func cardDayTimeAndBroadcast() {
        let withTV = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"), broadcast: "ESPN")
        let card = make(withTV, followed: "WAS")?.card
        #expect(card?.dayLabel == "SAT")
        #expect(card?.timeLabel == Self.expectedTime)
        #expect(card?.broadcast == "ESPN")
        // No broadcast → nil chip.
        let noTV = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"))
        #expect(make(noTV, followed: "WAS")?.card.broadcast == nil)
    }

    @Test func makeReturnsNilWithoutKickoffOrSides() {
        let noDate = makeEvent(home: ("WAS", "Spirit"), away: ("POR", "Thorns"), date: nil)
        #expect(make(noDate, followed: "WAS") == nil)
        // No competitions at all → no home/away.
        let noSides = Event(id: "e1", date: Self.kickoffUTC, competitions: nil)
        #expect(make(noSides, followed: "WAS") == nil)
    }

    // MARK: Windowing (NotificationScheduler.windowed — pure, generic)

    @Test func windowingKeepsNextTwoPerTeamAndGlobalCap() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func kickoff(_ hours: Double) -> Date { base.addingTimeInterval(hours * 3600) }

        // Three WAS fixtures → only the earliest two survive; POR is independent.
        let candidates: [(followed: String, kickoff: Date, value: String)] = [
            ("WAS", kickoff(72), "was3"),
            ("WAS", kickoff(24), "was1"),
            ("WAS", kickoff(48), "was2"),
            ("POR", kickoff(30), "por1"),
        ]
        let picked = NotificationScheduler.windowed(candidates)
        #expect(picked.contains("was1"))
        #expect(picked.contains("was2"))
        #expect(!picked.contains("was3"))   // 3rd WAS fixture dropped (per-team limit 2)
        #expect(picked.contains("por1"))

        // Global cap: 60 candidates across 60 teams (1 each) → capped at 50.
        let many: [(followed: String, kickoff: Date, value: Int)] =
            (0..<60).map { ("T\($0)", kickoff(Double($0)), $0) }
        #expect(NotificationScheduler.windowed(many).count == 50)
    }

    // MARK: Rebuild signature contract

    private func spec(id: String, fire: Date, title: String, body: String,
                      card: DayBeforeCardModel, assetToken: String) -> NotificationScheduler.DayBeforeSpec {
        NotificationScheduler.DayBeforeSpec(
            identifier: id, eventID: id, fireDate: fire,
            title: title, body: body, card: card, assetToken: assetToken)
    }

    @Test func signatureIsOrderIndependentAndContentSensitive() {
        let fire = Date(timeIntervalSince1970: 1_800_000_000)
        let cardA = DayBeforeCardModel(homeAbbr: "WAS", awayAbbr: "POR",
                                       dayLabel: "SAT", timeLabel: "4:00 PM", broadcast: nil)
        let s1 = spec(id: "a", fire: fire, title: "A", body: "b", card: cardA, assetToken: "h0|a0")
        let s2 = spec(id: "b", fire: fire, title: "B", body: "b", card: cardA, assetToken: "h0|a0")
        let spot = NotificationScheduler.SpotlightSpec(
            identifier: "nwsl.spotlight.1", fireDate: fire, title: "New Know Her Game", body: "b")

        // Order-independent (regression: the signature must not depend on now-derived values —
        // both spec kinds store a fixed fireDate, never a decaying interval).
        let sig1 = NotificationScheduler.scheduleSignature(dayBefore: [s1, s2], spotlight: [spot])
        let sig2 = NotificationScheduler.scheduleSignature(dayBefore: [s2, s1], spotlight: [spot])
        #expect(sig1 == sig2)

        // Broadcast appearing later → different signature (so a rebuild actually re-renders).
        let cardWithTV = DayBeforeCardModel(homeAbbr: "WAS", awayAbbr: "POR",
                                            dayLabel: "SAT", timeLabel: "4:00 PM", broadcast: "ESPN")
        let s1TV = spec(id: "a", fire: fire, title: "A", body: "4:00 PM · ESPN",
                        card: cardWithTV, assetToken: "h0|a0")
        #expect(NotificationScheduler.scheduleSignature(dayBefore: [s1TV, s2], spotlight: [spot]) != sig1)

        // Asset-override flip → different signature.
        let s1Asset = spec(id: "a", fire: fire, title: "A", body: "b", card: cardA, assetToken: "h1|a0")
        #expect(NotificationScheduler.scheduleSignature(dayBefore: [s1Asset, s2], spotlight: [spot]) != sig1)

        // Spotlight set matters: dropping it (opt-in off) OR a different drop week re-hashes.
        #expect(NotificationScheduler.scheduleSignature(dayBefore: [s1, s2], spotlight: []) != sig1)
        let spot2 = NotificationScheduler.SpotlightSpec(
            identifier: "nwsl.spotlight.2", fireDate: fire, title: "New Know Her Game", body: "b")
        #expect(NotificationScheduler.scheduleSignature(dayBefore: [s1, s2], spotlight: [spot2]) != sig1)
    }
}
