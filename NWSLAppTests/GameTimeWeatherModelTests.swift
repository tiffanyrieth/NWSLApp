//
//  GameTimeWeatherModelTests.swift
//  NWSLAppTests
//
//  The two conditional footer gates of the game-time weather strip — pure logic, no SwiftUI.
//  Both are strictly data-driven per the design: surface a number only when it's meaningfully
//  different across the WHOLE window, stay silent otherwise.
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

    @Test func suppressedWhenOneHourIsWithin4Degrees() {
        // Three hours diverge ≥5, one is within 4 → the row is suppressed entirely.
        let hours = [hour(84, feels: 91), hour(83, feels: 90), hour(82, feels: 84), hour(81, feels: 86)]
        #expect(GameTimeWeatherModel.feelsLikeRow(hours: hours) == nil)
    }

    @Test func suppressedWhenDirectionsDisagree() {
        // Some hours hotter, some colder → no clean story, suppressed.
        let hours = [hour(84, feels: 91), hour(40, feels: 33), hour(82, feels: 89), hour(81, feels: 87)]
        #expect(GameTimeWeatherModel.feelsLikeRow(hours: hours) == nil)
    }

    @Test func suppressedWhenGapIsExactly4() {
        // The gate is ≥5; a uniform 4° gap stays silent.
        let hours = [hour(84, feels: 88), hour(83, feels: 87), hour(82, feels: 86), hour(81, feels: 85)]
        #expect(GameTimeWeatherModel.feelsLikeRow(hours: hours) == nil)
    }

    // MARK: sunsetInWindow

    private let kickoff = ISO8601DateFormatter().date(from: "2026-08-15T00:00:00Z")!

    @Test func sunsetShownWhenInsideTheWindow() {
        // Sunset 11:56 PM UTC = kickoff −4 min → inside [kickoff−1h, kickoff+2h].
        let sunset = ISO8601DateFormatter().date(from: "2026-08-14T23:56:00Z")!
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff) != nil)
    }

    @Test func sunsetHiddenWhenBeforeTheWindow() {
        // Sunset 90 min before kickoff → outside the −1h edge.
        let sunset = kickoff.addingTimeInterval(-90 * 60)
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff) == nil)
    }

    @Test func sunsetHiddenWhenAfterTheWindow() {
        // Sunset 3h after kickoff → past the +2h edge (window end is kickoff+3h boundary; 3h01m out).
        let sunset = kickoff.addingTimeInterval(3 * 3600 + 60)
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff) == nil)
    }

    @Test func sunsetHiddenWhenAbsent() {
        #expect(GameTimeWeatherModel.sunsetInWindow(sunset: nil, kickoff: kickoff) == nil)
    }
}
