//
//  GameTimeWeatherModel.swift
//  NWSLApp
//
//  Pure presentation logic for the game-time weather strip's two conditional footer rows —
//  extracted from the view so the gates are unit-testable without SwiftUI. Both are strictly
//  data-driven (no judgments, per the design): they surface a number only when it's meaningfully
//  different, and stay silent otherwise.
//

import Foundation

enum GameTimeWeatherModel {

    /// The "feels like" footer row — heat index, wind chill, or a neutral feels-like.
    ///
    /// Design gate: show ONLY when EVERY hour in the 4-hour window has a ≥5° gap between actual
    /// and feels-like, in the SAME direction. If even one hour is within 4°, or the directions
    /// disagree, the row is suppressed — a "feels like" that only diverges for one hour, or flips
    /// sign across the window, isn't a clean story worth a line. The range is the exact min–max
    /// feels-like across the window (not rounded to 5° increments).
    ///
    /// ⚠️ THE LABEL IS REGIME-AWARE (bug fix 2026-08-11 — a GFC game at ~80°F was labeled "Wind
    /// chill", which is meteorologically wrong: wind chill is a COLD-weather term, defined only at
    /// ≤50°F; heat index is a HOT-humid term). So:
    ///   • feels HOTTER (by definition a warm regime) → "Heat index"
    ///   • feels COLDER and actually cold (≤ `windChillMaxTempF`) → "Wind chill"
    ///   • feels COLDER but mild/warm (a breezy 80°) → neutral "Feels like" — honest, not a misnomer
    enum FeelsKind: Equatable { case heatIndex, windChill, feelsLike }
    struct FeelsRow: Equatable { let kind: FeelsKind; let minF: Int; let maxF: Int }

    /// The upper bound where "wind chill" is a real term (US NWS defines it at ≤50°F).
    static let windChillMaxTempF = 50

    static func feelsLikeRow(hours: [MatchWeather.ForecastHour]) -> FeelsRow? {
        guard !hours.isEmpty else { return nil }
        // Every hour must diverge by ≥5° in the SAME direction.
        let hotter = hours.allSatisfy { $0.feelsLikeF - $0.tempF >= 5 }
        let colder = hours.allSatisfy { $0.tempF - $0.feelsLikeF >= 5 }
        guard hotter || colder else { return nil }
        let feels = hours.map(\.roundedFeelsLike)
        let kind: FeelsKind
        if hotter {
            kind = .heatIndex
        } else if hours.allSatisfy({ $0.tempF <= Double(windChillMaxTempF) }) {
            kind = .windChill   // genuinely cold all window → wind chill is the right word
        } else {
            kind = .feelsLike   // cooler-feeling but mild (a breezy warm day) → neutral
        }
        return FeelsRow(kind: kind, minF: feels.min()!, maxF: feels.max()!)
    }

    /// The sunset footer row: shown only when sunset falls inside the game window
    /// [kickoff −1h, kickoff +2h] — i.e. the fan would actually watch the sun go down during
    /// the broadcast. `kickoff` is the match kickoff instant; `windowHours` is the forecast strip.
    /// Returns the local-time label ("7:56 PM") or nil.
    static func sunsetInWindow(sunset: Date?, kickoff: Date) -> String? {
        guard let sunset else { return nil }
        let start = kickoff.addingTimeInterval(-3600)      // window opens at kickoff −1h
        let end = kickoff.addingTimeInterval(3 * 3600)     // ...closes at kickoff +2h (inclusive end of the +2h hour)
        guard sunset >= start && sunset <= end else { return nil }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: sunset)
    }
}
