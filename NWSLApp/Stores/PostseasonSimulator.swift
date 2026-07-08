//
//  PostseasonSimulator.swift
//  NWSLApp
//
//  DEBUG-only. Drives the Playoff feature off the REAL 2025 NWSL postseason (in-code, no
//  network) so every UI state can be seen in the sim months before the live playoffs. Real
//  teams, seeds, dates, venues, and broadcasts; the per-STAGE `state`/score dialing is the
//  only thing "simulated" — it lets one dataset show upcoming, live, final, TBD, eliminated,
//  Win→ projection, and the multi-team storyline.
//
//  Enabled by the `-simulatePostseason2025` launch arg (optionally `…Stage <qf|mid|done>`),
//  read in PlayoffStore.simulatePostseason2025(...). Compiled out of Release.
//

#if DEBUG
import Foundation

enum PostseasonSimulator {

    enum Stage: String {
        case preSeeding   // no playoff events, no clinches — the year-round TBD windows tail only
        case clinchWindow // late regular season: 2+ teams mathematically clinched → chip appears
        case qfUpcoming   // all 4 QFs upcoming (everyone alive; projection + storyline visible)
        case midRun       // 2 QFs final, 1 live, 1 upcoming; SF/Final TBD (the prototype state)
        case complete     // whole bracket final; GFC champion (historical/keepsake state)

        init(arg: String?) {
            switch arg?.lowercased() {
            case "pre", "preseeding": self = .preSeeding
            case "clinch", "clinchwindow": self = .clinchWindow
            case "qf", "qfupcoming": self = .qfUpcoming
            case "done", "complete": self = .complete
            default: self = .midRun
            }
        }
    }

    /// The real 2025 playoff-round windows (matches ESPN's season-type calendar shape) — drives
    /// the pre-seeding TBD tail in the sim.
    static let windows2025: [SeasonWindow] = [
        SeasonWindow(slug: "regular-season", name: "Regular Season",
                     startDate: "2025-01-01T05:00Z", endDate: "2025-11-04T04:59Z"),
        SeasonWindow(slug: "playoffs---quarterfinals", name: "Playoffs - Quarterfinals",
                     startDate: "2025-11-04T05:00Z", endDate: "2025-11-11T04:59Z"),
        SeasonWindow(slug: "playoffs---semifinals", name: "Playoffs - Semifinals",
                     startDate: "2025-11-11T05:00Z", endDate: "2025-11-18T04:59Z"),
        SeasonWindow(slug: "playoffs---championship", name: "Playoffs - Championship",
                     startDate: "2025-11-18T05:00Z", endDate: "2026-01-01T04:59Z"),
    ]

    /// A late-October table (constructed, plausible): KC + WAS mathematically clinched (the
    /// chip's 2+ trigger), SEA in position, CHI eliminated. 14 teams à la 2025; 26-game season.
    static let clinchTable: [PlayoffClinch.TeamLine] = [
        .init(abbreviation: "KC", points: 58, gamesPlayed: 24, rank: 1),
        .init(abbreviation: "WAS", points: 52, gamesPlayed: 24, rank: 2),
        .init(abbreviation: "POR", points: 44, gamesPlayed: 24, rank: 3),
        .init(abbreviation: "ORL", points: 43, gamesPlayed: 24, rank: 4),
        .init(abbreviation: "SEA", points: 38, gamesPlayed: 24, rank: 5),
        .init(abbreviation: "SD", points: 36, gamesPlayed: 24, rank: 6),
        .init(abbreviation: "LOU", points: 34, gamesPlayed: 24, rank: 7),
        .init(abbreviation: "GFC", points: 33, gamesPlayed: 24, rank: 8),
        .init(abbreviation: "NC", points: 31, gamesPlayed: 24, rank: 9),
        .init(abbreviation: "HOU", points: 28, gamesPlayed: 24, rank: 10),
        .init(abbreviation: "LA", points: 25, gamesPlayed: 24, rank: 11),
        .init(abbreviation: "UTA", points: 22, gamesPlayed: 24, rank: 12),
        .init(abbreviation: "BAY", points: 18, gamesPlayed: 24, rank: 13),
        .init(abbreviation: "CHI", points: 10, gamesPlayed: 24, rank: 14),
    ]

    /// abbr → seed for the full 2025 final table (top 8 make the bracket).
    static let seeds2025: [String: Int] = [
        "KC": 1, "WAS": 2, "POR": 3, "ORL": 4, "SEA": 5, "SD": 6, "LOU": 7, "GFC": 8,
        "NC": 9, "HOU": 10, "LA": 11, "UTA": 12, "BAY": 13, "CHI": 14,
    ]

    /// The events + seeds + a reference "now" for a stage.
    static func snapshot(_ stage: Stage) -> (events: [Event], seeds: [String: Int], now: Date) {
        (events(for: stage), seeds2025, referenceNow(for: stage))
    }

    // MARK: Stage → events (real 2025 values)

    private static func events(for stage: Stage) -> [Event] {
        switch stage {
        case .preSeeding, .clinchWindow:
            return []   // no playoff fixtures yet — these stages drive windows/clinch state only
        case .qfUpcoming:
            return [
                game("760606", .qf, home: ("KC", nil),  away: ("GFC", nil), winner: nil, iso: "2025-11-09T17:30Z", tv: "ABC",  venue: "CPKC Stadium",        state: .pre),
                game("760607", .qf, home: ("POR", nil), away: ("SD", nil),  winner: nil, iso: "2025-11-09T20:00Z", tv: "ABC",  venue: "Providence Park",     state: .pre),
                game("760609", .qf, home: ("WAS", nil), away: ("LOU", nil), winner: nil, iso: "2025-11-08T17:00Z", tv: "CBS",  venue: "Audi Field",          state: .pre),
                game("760608", .qf, home: ("ORL", nil), away: ("SEA", nil), winner: nil, iso: "2025-11-08T01:00Z", tv: "Prime Video", venue: "Inter&Co Stadium", state: .pre),
            ]
        case .midRun:
            return [
                // Two QFs already decided…
                game("760608", .qf, home: ("ORL", 2), away: ("SEA", 0), winner: "ORL", iso: "2025-11-08T01:00Z", tv: "Prime Video", venue: "Inter&Co Stadium", state: .post),
                game("760607", .qf, home: ("POR", 1), away: ("SD", 0),  winner: "POR", iso: "2025-11-09T20:00Z", tv: "ABC",  venue: "Providence Park",     state: .post),
                // …one LIVE (your match, if you follow WAS)…
                game("760609", .qf, home: ("WAS", 0), away: ("LOU", 0), winner: nil,   iso: "2025-11-08T17:00Z", tv: "CBS",  venue: "Audi Field",          state: .live),
                // …one still upcoming (tomorrow).
                game("760606", .qf, home: ("KC", nil), away: ("GFC", nil), winner: nil, iso: "2025-11-09T17:30Z", tv: "ABC", venue: "CPKC Stadium",        state: .pre),
                // SF/Final not yet published → derived as TBD from the tree.
            ]
        case .complete:
            return [
                game("760608", .qf, home: ("ORL", 2), away: ("SEA", 0), winner: "ORL", iso: "2025-11-08T01:00Z", tv: "Prime Video", venue: "Inter&Co Stadium", state: .post),
                game("760609", .qf, home: ("WAS", 1), away: ("LOU", 1), winner: "WAS", iso: "2025-11-08T17:00Z", tv: "CBS",  venue: "Audi Field",          state: .post),
                game("760606", .qf, home: ("KC", 1),  away: ("GFC", 2), winner: "GFC", iso: "2025-11-09T17:30Z", tv: "ABC",  venue: "CPKC Stadium",        state: .post),
                game("760607", .qf, home: ("POR", 1), away: ("SD", 0),  winner: "POR", iso: "2025-11-09T20:00Z", tv: "ABC",  venue: "Providence Park",     state: .post),
                game("760610", .sf, home: ("WAS", 2), away: ("POR", 0), winner: "WAS", iso: "2025-11-15T17:00Z", tv: "CBS",  venue: "Audi Field",          state: .post),
                game("760611", .sf, home: ("ORL", 0), away: ("GFC", 1), winner: "GFC", iso: "2025-11-16T20:00Z", tv: "ABC",  venue: "Inter&Co Stadium",    state: .post),
                game("760618", .final, home: ("WAS", 0), away: ("GFC", 1), winner: "GFC", iso: "2025-11-23T01:00Z", tv: "CBS", venue: "PayPal Park",      state: .post),
            ]
        }
    }

    private static func referenceNow(for stage: Stage) -> Date {
        switch stage {
        case .preSeeding:   return iso("2025-07-15T18:00Z") ?? Date(timeIntervalSince1970: 1_752_602_400)
        case .clinchWindow: return iso("2025-10-20T18:00Z") ?? Date(timeIntervalSince1970: 1_760_983_200)
        case .qfUpcoming:   return iso("2025-11-07T18:00Z") ?? Date(timeIntervalSince1970: 1_762_538_400)
        case .midRun:       return iso("2025-11-08T18:00Z") ?? Date(timeIntervalSince1970: 1_762_624_800)
        case .complete:     return iso("2025-12-01T18:00Z") ?? Date(timeIntervalSince1970: 1_764_612_000)
        }
    }

    // MARK: Builders

    private enum Slug: String { case qf = "playoffs---quarterfinals", sf = "playoffs---semifinals", final = "playoffs---championship" }

    /// Build one Event. `home`/`away` carry (abbr, score?) — score nil for unplayed. Higher seed
    /// is passed as `home` (matches ESPN's real data). `winner` sets the ESPN winner flag.
    private static func game(_ id: String, _ slug: Slug,
                             home: (String, Int?), away: (String, Int?),
                             winner: String?, iso isoDate: String, tv: String, venue: String,
                             state: MatchState) -> Event {
        func competitor(_ team: (String, Int?), homeAway: String) -> Competitor {
            Competitor(homeAway: homeAway,
                       score: team.1.map(String.init),
                       team: Team(displayName: team.0, abbreviation: team.0),
                       winner: winner == team.0)
        }
        let statusState = state == .post ? "post" : (state == .live ? "in" : "pre")
        return Event(
            id: id,
            name: "\(away.0) at \(home.0)",
            shortName: "\(away.0) @ \(home.0)",
            date: isoDate,
            status: EventStatus(type: StatusType(state: statusState)),
            competitions: [Competition(
                competitors: [competitor(home, homeAway: "home"), competitor(away, homeAway: "away")],
                venue: Venue(fullName: venue),
                broadcasts: [Broadcast(names: [tv])]
            )],
            season: EventSeason(year: 2025, slug: slug.rawValue)
        )
    }

    private static func iso(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mmZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
#endif
