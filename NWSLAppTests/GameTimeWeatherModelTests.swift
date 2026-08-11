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

    @Test func windChillWhenEveryHourFeelsColderByAtLeast5() {
        let hours = [hour(40, feels: 33), hour(39, feels: 31), hour(38, feels: 30), hour(37, feels: 29)]
        let row = GameTimeWeatherModel.feelsLikeRow(hours: hours)
        #expect(row?.kind == .windChill)
        #expect(row?.minF == 29)
        #expect(row?.maxF == 33)
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
