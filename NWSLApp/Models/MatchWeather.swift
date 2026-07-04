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
//  The envelope is versioned (`v`/`mode`) so a later forecast mode for upcoming matches can
//  be added without changing this decoder — today only `mode == "historical"` renders.
//

import Foundation

struct MatchWeather: Decodable {
    let v: Int?
    let mode: String?          // "historical" (renders) | "unavailable" (nothing to show)
    let tempF: Double?
    let weatherCode: Int?      // WMO code → symbol + label
    let isDay: Int?            // 1 = day, 0 = night at kickoff — picks the sun vs. moon icon
    let condition: String?     // time-neutral label from the proxy ("Clear", not "Sunny")
    let asOf: String?          // ISO8601 UTC kickoff hour the reading is for

    /// True only for a real historical reading with a temperature to show.
    var isHistorical: Bool { mode == "historical" && tempF != nil }

    /// Kickoff temperature rounded to a whole degree (the proxy already rounds, but
    /// this keeps the view honest if the shape ever changes). Nil when there's nothing to show.
    var roundedTemp: Int? {
        guard let tempF else { return nil }
        return Int(tempF.rounded())
    }

    /// Whether kickoff was at night — drives the moon vs. sun icon variants.
    var isNight: Bool { isDay == 0 }

    /// SF Symbol for the sky condition, night-aware. Grouped by WMO weather_code
    /// (the same groups the proxy's `conditionLabel` uses). An unmapped/absent code
    /// falls back to a neutral cloud so the stamp always renders something sensible.
    var symbolName: String {
        guard let code = weatherCode else { return "cloud.fill" }
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

    /// VoiceOver phrasing for the stamp, e.g. "Clear, 70 degrees at kickoff".
    var accessibilityLabel: String {
        let sky = (condition?.isEmpty == false) ? condition! : "Weather"
        if let temp = roundedTemp {
            return "\(sky), \(temp) degrees at kickoff"
        }
        return sky
    }
}
