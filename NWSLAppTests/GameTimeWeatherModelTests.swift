//
//  GameTimeWeatherModelTests.swift
//  NWSLAppTests
//
//  The two conditional footer gates of the game-time weather strip — pure logic, no SwiftUI.
//  Both are strictly data-driven per the design: the feels-like row surfaces when the KICKOFF
//  hour diverges ≥5° (ranging over the still-diverging hours); the sunset row when sunset falls
//  in the game window, labeled in the venue's timezone.
//

import Foundation
import Testing
@testable import NWSLApp

struct GameTimeWeatherModelTests {

    private func hour(_ temp: Double, feels: Double) -> MatchWeather.ForecastHour {
        MatchWeather.ForecastHour(time: "2026-08-15T00:00Z", tempF: temp, feelsLikeF: feels,
                                  weatherCode: 0, isDay: 1, windMph: 5, precipPct: 0)
    }

    // MARK: feelsLikeRow

    @Test func heatIndexWhenEveryHourFeelsHotterByAtLeast5() {
        let hours = [hour(84, feels: 91), hour(83, feels: 90), hour(82, feels: 88), hour(81, feels: 86)]
        let row = GameTimeWeatherModel.feelsLikeRow(hours: hours)
        #expect(row?.kind == .heatIndex)
        #expect(row?.minF == 86)   // exact min–max, not rounded to 5s
        #expect(row?.maxF == 91)
    }

    @Test func windChillOnlyWhenGenuinelyCold() {
        // ≤50°F all window + feels colder → "wind chill" is the correct meteorological term.
        let hours = [hour(40, feels: 33), hour(39, feels: 31), hour(38, feels: 30), hour(37, feels: 29)]
        let row = GameTimeWeatherModel.feelsLikeRow(hours: hours)
        #expect(row?.kind == .windChill)
        #expect(row?.minF == 29)
        #expect(row?.maxF == 33)
    }

    /// ⚠️ THE BUG (2026-08-11): the GFC game was ~76–83°F feeling ~72–77° (a breeze) and got labeled
    /// "Wind chill" — meteorologically wrong (wind chill is ≤50°F only). A cooler-feeling but MILD
    /// window is a neutral "Feels like", never wind chill.
    @Test func feelsLikeNotWindChillWhenMildButBreezy() {
        let hours = [hour(83, feels: 78), hour(81, feels: 76), hour(79, feels: 74), hour(76, feels: 71)]
        let row = GameTimeWeatherModel.feelsLikeRow(hours: hours)
        #expect(row?.kind == .feelsLike)   // NOT .windChill
        #expect(row?.minF == 71)
        #expect(row?.maxF == 78)
    }

    /// The boundary: if any hour is above the 50°F wind-chill ceiling, it's "feels like", not "wind chill".
    @Test func mixedColdAndMildFallsToFeelsLike() {
        let hours = [hour(48, feels: 41), hour(52, feels: 45), hour(50, feels: 43), hour(47, feels: 40)]
        #expect(GameTimeWeatherModel.feelsLikeRow(hours: hours)?.kind == .feelsLike)  // the 52° hour disqualifies wind chill
    }

    /// ⚠️ THE BUG (2026-08-12): the old gate required EVERY hour to diverge ≥5°, so a single cooling
    /// tail hour (a storm rolling in, or the forecast easing run-to-run) suppressed the whole heat-index
    /// line — exactly when a hot kickoff mattered most. The new gate anchors on the KICKOFF hour (index 1)
    /// and ranges over only the still-diverging hours, so the cooling hour is excluded, not fatal.
    @Test func heatIndexSurvivesACoolingTailHour() {
        let hours = [hour(84, feels: 91), hour(83, feels: 90), hour(82, feels: 84), hour(81, feels: 86)]
        let row = GameTimeWeatherModel.feelsLikeRow(hours: hours)
        #expect(row?.kind == .heatIndex)
        #expect(row?.minF == 86)   // ranges over the hot hours only (91, 90, 86) — the 84° hour is excluded,
        #expect(row?.maxF == 91)   // so the low end never collapses to a bogus "heat index 84°"
    }

    @Test func suppressedWhenKickoffHourIsWithin4() {
        // The kickoff hour (index 1) is within 4° → suppressed, even though later hours diverge. The
        // anchor is kickoff; a hot spell an hour after the whistle isn't the story worth a line.
        let hours = [hour(84, feels: 91), hour(83, feels: 86), hour(82, feels: 90), hour(81, feels: 89)]
        #expect(GameTimeWeatherModel.feelsLikeRow(hours: hours) == nil)
    }

    @Test func suppressedWhenKickoffGapIsExactly4() {
        // The gate is ≥5; a 4° gap at kickoff stays silent.
        let hours = [hour(84, feels: 88), hour(83, feels: 87), hour(82, feels: 86), hour(81, feels: 85)]
        #expect(GameTimeWeatherModel.feelsLikeRow(hours: hours) == nil)
    }

    // MARK: sunsetInWindow

    private let kickoff = ISO8601DateFormatter().date(from: "2026-08-15T00:00:00Z")!
    private let utc = TimeZone(identifier: "UTC")!

    @Test func sunsetShownWhenInsideTheWindow() {
        // Sunset 11:56 PM UTC = kickoff −4 min → inside [kickoff−1h, kickoff+2h].
        let sunset = ISO8601DateFormatter().date(from: "2026-08-14T23:56:00Z")!
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff, timeZone: utc) == "11:56 PM")
    }

    /// The label is rendered in the VENUE's timezone, not the device's — a sunset is a local event.
    @Test func sunsetLabelUsesVenueTimeZone() {
        let sunset = ISO8601DateFormatter().date(from: "2026-08-14T23:56:00Z")!
        let pacific = TimeZone(identifier: "America/Los_Angeles")!   // UTC−7 in August (DST)
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff, timeZone: pacific) == "4:56 PM")
    }

    @Test func sunsetHiddenWhenBeforeTheWindow() {
        // Sunset 90 min before kickoff → outside the −1h edge.
        let sunset = kickoff.addingTimeInterval(-90 * 60)
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff, timeZone: utc) == nil)
    }

    @Test func sunsetHiddenWhenAfterTheWindow() {
        // Sunset 3h after kickoff → past the +2h edge (window end is kickoff+3h boundary; 3h01m out).
        let sunset = kickoff.addingTimeInterval(3 * 3600 + 60)
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff, timeZone: utc) == nil)
    }

    @Test func sunsetHiddenWhenAbsent() {
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: nil, kickoff: kickoff, timeZone: utc) == nil)
    }
}
