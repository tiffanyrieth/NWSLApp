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
    /// Design gate (revised 2026-08-12): show when the KICKOFF hour diverges ≥5° from the air
    /// temp, then range over the hours that actually diverge in that direction. The earlier
    /// "EVERY hour must diverge" gate was too strict — a single cooling hour (a storm rolling in,
    /// or the forecast refining run-to-run) suppressed the whole heat-index line exactly when the
    /// heat mattered most. Anchoring on kickoff keeps the story clean (no line for a game that's
    /// only briefly muggy an hour before) while surviving a tail that eases off.
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

    /// The ≥° gap (actual vs feels-like) at which a "feels like" line is worth showing.
    static let feelsGapF = 5.0

    static func feelsLikeRow(hours: [MatchWeather.ForecastHour]) -> FeelsRow? {
        guard !hours.isEmpty else { return nil }
        // Key on the KICKOFF hour (index 1 — the proxy guarantees kickoff there; fall back to the first),
        // NOT "every hour diverges" (bug 2026-08-12). The strict all-hours gate suppressed the heat-index row
        // whenever a single later hour cooled within 4° — e.g. a hot game with a storm rolling in, or the
        // forecast refining run-to-run ("yesterday 99°, today gone") — which is exactly when the heat matters.
        let anchor = hours.indices.contains(1) ? hours[1] : hours[0]
        let hotGap = anchor.feelsLikeF - anchor.tempF
        let coldGap = anchor.tempF - anchor.feelsLikeF

        if hotGap >= feelsGapF {
            // Range over only the hours that are actually elevated (a cooling tail shouldn't drag the low end
            // down to the air temp and read as a bogus "heat index 78°").
            let hot = hours.filter { $0.feelsLikeF - $0.tempF >= feelsGapF }.map(\.roundedFeelsLike)
            guard let lo = hot.min(), let hi = hot.max() else { return nil }
            return FeelsRow(kind: .heatIndex, minF: lo, maxF: hi)
        }
        if coldGap >= feelsGapF {
            let cold = hours.filter { $0.tempF - $0.feelsLikeF >= feelsGapF }.map(\.roundedFeelsLike)
            guard let lo = cold.min(), let hi = cold.max() else { return nil }
            // "Wind chill" is a COLD-weather term (US NWS: ≤50°F); a breezy-cooler mild day is neutral "Feels like".
            let kind: FeelsKind = hours.allSatisfy { $0.tempF <= Double(windChillMaxTempF) } ? .windChill : .feelsLike
            return FeelsRow(kind: kind, minF: lo, maxF: hi)
        }
        return nil
    }

    /// The sunset footer row: shown only when sunset falls inside the game window
    /// [kickoff −1h, kickoff +2h] — i.e. the fan would actually watch the sun go down during
    /// the broadcast. `kickoff` is the match kickoff instant; `timeZone` is the VENUE's timezone,
    /// because a sunset is a local event ("8:18 PM" in the stadium's city, not the fan's clock —
    /// bug fix 2026-08-12). Returns the venue-local label ("7:56 PM") or nil.
    static func sunsetInWindow(sunset: Date?, kickoff: Date, timeZone: TimeZone) -> String? {
        guard let sunset else { return nil }
        let start = kickoff.addingTimeInterval(-3600)      // window opens at kickoff −1h
        let end = kickoff.addingTimeInterval(3 * 3600)     // ...closes at kickoff +2h (inclusive end of the +2h hour)
        guard sunset >= start && sunset <= end else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "h:mm a"
        return f.string(from: sunset)
    }
}
