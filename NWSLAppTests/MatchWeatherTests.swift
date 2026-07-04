//
//  MatchWeatherTests.swift
//  NWSLAppTests
//
//  Decode + presentation tests for MatchWeather — the historical kickoff-weather stamp
//  in the Match Detail header. Covers the real proxy `/weather` response shape (the
//  captured Fixtures/weather.json), the "unavailable" envelope, and the WMO weather_code
//  → SF Symbol mapping in both day and night variants (the reason we carry is_day: a late
//  kickoff after sunset must render a moon icon, not a sun).
//
//  The fixture is read straight off disk via #filePath, so it needs no bundle membership,
//  matching MatchSummaryTests.
//

import Foundation
import Testing
@testable import NWSLApp

struct MatchWeatherTests {

    private func decode(_ json: String) throws -> MatchWeather {
        try JSONDecoder().decode(MatchWeather.self, from: Data(json.utf8))
    }

    @Test func decodesHistoricalFixture() throws {
        let fixture = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/weather.json")
        let weather = try JSONDecoder().decode(MatchWeather.self, from: Data(contentsOf: fixture))

        #expect(weather.isHistorical)
        #expect(weather.roundedTemp == 70)
        #expect(weather.weatherCode == 0)
        #expect(weather.condition == "Clear")
        #expect(weather.isNight == false)          // isDay 1 → day
        #expect(weather.symbolName == "sun.max.fill")
    }

    @Test func unavailableEnvelopeShowsNothing() throws {
        let weather = try decode(#"{"v":1,"mode":"unavailable","reason":"not-finished"}"#)
        #expect(weather.isHistorical == false)     // no stamp
        #expect(weather.roundedTemp == nil)
    }

    @Test func roundsFractionalTemperature() throws {
        // Defensive: even though the proxy already rounds, the view reads roundedTemp.
        let warm = try decode(#"{"mode":"historical","tempF":69.6,"weatherCode":3,"isDay":1}"#)
        #expect(warm.roundedTemp == 70)
        let cool = try decode(#"{"mode":"historical","tempF":58.2,"weatherCode":3,"isDay":0}"#)
        #expect(cool.roundedTemp == 58)
    }

    @Test func symbolMapsDayVariants() throws {
        func symbol(code: Int) throws -> String {
            try decode(#"{"mode":"historical","tempF":70,"weatherCode":\#(code),"isDay":1}"#).symbolName
        }
        #expect(try symbol(code: 0) == "sun.max.fill")        // Clear
        #expect(try symbol(code: 2) == "cloud.sun.fill")      // Partly cloudy
        #expect(try symbol(code: 3) == "cloud.fill")          // Cloudy
        #expect(try symbol(code: 48) == "cloud.fog.fill")     // Fog
        #expect(try symbol(code: 61) == "cloud.rain.fill")    // Rain
        #expect(try symbol(code: 75) == "cloud.snow.fill")    // Snow
        #expect(try symbol(code: 81) == "cloud.heavyrain.fill") // Showers
        #expect(try symbol(code: 95) == "cloud.bolt.rain.fill") // Thunderstorm
    }

    @Test func symbolMapsNightVariants() throws {
        func symbol(code: Int) throws -> String {
            try decode(#"{"mode":"historical","tempF":60,"weatherCode":\#(code),"isDay":0}"#).symbolName
        }
        #expect(try symbol(code: 0) == "moon.stars.fill")      // Clear night
        #expect(try symbol(code: 1) == "cloud.moon.fill")      // Partly cloudy night
        #expect(try symbol(code: 3) == "cloud.fill")           // Cloudy — no night variant
        #expect(try symbol(code: 61) == "cloud.moon.rain.fill") // Rain night
        #expect(try symbol(code: 81) == "cloud.moon.rain.fill") // Showers night
        #expect(try symbol(code: 95) == "cloud.moon.bolt.fill") // Thunderstorm night
    }

    @Test func unmappedOrMissingCodeFallsBackToCloud() throws {
        #expect(try decode(#"{"mode":"historical","tempF":70,"weatherCode":123,"isDay":1}"#).symbolName == "cloud.fill")
        #expect(try decode(#"{"mode":"historical","tempF":70,"isDay":1}"#).symbolName == "cloud.fill")
    }

    @Test func accessibilityLabelReadsConditionAndTemp() throws {
        let weather = try decode(#"{"mode":"historical","tempF":70,"weatherCode":0,"isDay":1,"condition":"Clear"}"#)
        #expect(weather.accessibilityLabel == "Clear, 70 degrees at kickoff")
    }
}
