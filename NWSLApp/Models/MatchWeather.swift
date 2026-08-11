//
//  MatchWeather.swift
//  NWSLApp
//
//  The historical kickoff weather for a PAST match — the little "☀️ 70°" stamp in
//  the Match Detail header. ESPN carries no weather for NWSL, so this comes from the
//  proxy's `GET /weather?event={id}` route (Open-Meteo behind it, keyed by venue → the
//  temperature at the exact kickoff hour, not the daily high). See nwslapp-proxy/src/weather.ts.
//
//  Decoded defensively (every field optional) like the rest of the app's models: weather
//  is additive and nice-to-have, so anything unexpected → no stamp, never a broken screen.
//  The envelope is versioned (`v`/`mode`): `historical` = the past-match stamp; `forecast`
//  = the game-time weather strip on an UPCOMING match (the 4-hour game window). `roundedTemp`
//  is HISTORICAL-ONLY on purpose — it gates the Match Detail header rail, so a forecast must
//  never populate it (the forecast lives in `hours`, not the top-level temp).
//

import Foundation

struct MatchWeather: Decodable {
    let v: Int?
    let mode: String?          // "historical" (stamp) | "forecast" (strip) | "unavailable"
    let tempF: Double?         // HISTORICAL only — absent in forecast mode (see roundedTemp)
    let weatherCode: Int?      // WMO code → symbol + label (historical)
    let isDay: Int?            // 1 = day, 0 = night at kickoff — picks the sun vs. moon icon
    let condition: String?     // time-neutral label from the proxy ("Clear", not "Sunny")
    let asOf: String?          // ISO8601 UTC kickoff hour the reading is for

    // Forecast mode (upcoming matches): the 4-hour game window + venue + sunset.
    let hours: [ForecastHour]?
    let sunset: String?        // ISO8601 UTC sunset instant nearest kickoff (nil if none/absent)
    let venueName: String?

    /// One hour of the game-window forecast, mirroring the proxy envelope.
    struct ForecastHour: Decodable, Equatable {
        let time: String       // "YYYY-MM-DDTHH:00Z"
        let tempF: Double
        let feelsLikeF: Double
        let weatherCode: Int
        let isDay: Int
        let windMph: Double
        let precipPct: Int

        var isNight: Bool { isDay == 0 }
        var roundedTemp: Int { Int(tempF.rounded()) }
        var roundedFeelsLike: Int { Int(feelsLikeF.rounded()) }
        var roundedWind: Int { Int(windMph.rounded()) }
        var symbolName: String { MatchWeather.symbol(code: weatherCode, isNight: isNight) }

        /// The window's local-time hour label, e.g. "8 PM". Formatted in the DEVICE timezone
        /// from the UTC instant (Open-Meteo gives UTC; the fan sees their own clock).
        var hourLabel: String {
            guard let date = MatchWeather.parseISO(time) else { return "" }
            let f = DateFormatter()
            f.dateFormat = "h a"   // "8 PM"
            return f.string(from: date)
        }

        /// Precip is only shown at ≥20% (design: below that it's noise, not signal).
        var showsPrecip: Bool { precipPct >= 20 }
    }

    /// True only for a real historical reading with a temperature to show.
    var isHistorical: Bool { mode == "historical" && tempF != nil }

    /// True only for a forecast with a full 4-hour window. A partial window never renders
    /// (the proxy already refuses to emit one, but the app guards too).
    var isForecast: Bool { mode == "forecast" && (hours?.count ?? 0) == 4 }

    /// Kickoff temperature rounded to a whole degree — HISTORICAL ONLY. ⚠️ This feeds the Match
    /// Detail header-rail gate (`hasCompactInfo`), so it stays nil in forecast mode by design;
    /// the forecast temperatures live in `hours`, never here.
    var roundedTemp: Int? {
        guard let tempF else { return nil }
        return Int(tempF.rounded())
    }

    /// Whether kickoff was at night — drives the moon vs. sun icon variants (historical stamp).
    var isNight: Bool { isDay == 0 }

    /// SF Symbol for the historical stamp's sky condition.
    var symbolName: String { Self.symbol(code: weatherCode, isNight: isNight) }

    /// The sunset instant, if the proxy sent one and it parses.
    var sunsetDate: Date? { sunset.flatMap { Self.parseISO($0) } }

    /// Parse an ISO-8601 UTC instant, tolerating BOTH fractional-second (`…00.000Z`, what the proxy's
    /// `new Date().toISOString()` emits for the forecast) and whole-second (`…00Z`) forms — the default
    /// `ISO8601DateFormatter` rejects fractional seconds, which silently nil-ed the sunset.
    static func parseISO(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// WMO weather_code → SF Symbol, night-aware. THE shared table for both the historical stamp
    /// and every forecast hour column (one source of truth). An unmapped/absent code → neutral cloud.
    static func symbol(code: Int?, isNight: Bool) -> String {
        guard let code else { return "cloud.fill" }
        switch code {
        case 0:            return isNight ? "moon.stars.fill" : "sun.max.fill"       // Clear
        case 1, 2:         return isNight ? "cloud.moon.fill" : "cloud.sun.fill"     // Partly cloudy
        case 3:            return "cloud.fill"                                        // Cloudy
        case 45, 48:       return "cloud.fog.fill"                                    // Fog
        case 51...67:      return isNight ? "cloud.moon.rain.fill" : "cloud.rain.fill" // Drizzle / Rain
        case 71...77, 85, 86: return "cloud.snow.fill"                                // Snow / snow showers
        case 80...82:      return isNight ? "cloud.moon.rain.fill" : "cloud.heavyrain.fill" // Showers
        case 95...99:      return isNight ? "cloud.moon.bolt.fill" : "cloud.bolt.rain.fill" // Thunderstorm
        default:           return "cloud.fill"
        }
    }

    /// VoiceOver phrasing for the historical stamp, e.g. "Clear, 70 degrees at kickoff".
    var accessibilityLabel: String {
        let sky = (condition?.isEmpty == false) ? condition! : "Weather"
        if let temp = roundedTemp {
            return "\(sky), \(temp) degrees at kickoff"
        }
        return sky
    }
}
