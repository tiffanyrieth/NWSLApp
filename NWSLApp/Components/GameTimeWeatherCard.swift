//
//  GameTimeWeatherCard.swift
//  NWSLApp
//
//  "Expected game-time weather" — the forecast strip on an UPCOMING match's detail screen
//  (design handoff `design_handoff_weather`). A 4-column hourly strip (kickoff −1h, kickoff,
//  +1h, +2h) with temperature / condition / wind / precip, plus two conditional footer rows
//  (heat-index-or-wind-chill, sunset). Purely informational — no ratings, no "nice day" stamp;
//  the data is shown, the fan decides.
//
//  Prop-only (HowToWatchCard pattern): the caller supplies the decoded forecast + kickoff and
//  applies the 20pt horizontal margin. The card only renders when it has a full 4-hour window —
//  the caller gates on `weather.isForecast`, so this view assumes a valid strip.
//
//  ⚠️ Text sizes were raised to the 12pt readable floor from the handoff's 10–10.5pt (owner
//  2026-08-11): the handoff came from Claude Design, which sizes below our floor; the KICKOFF
//  marker keeps its eyebrow feel via small-caps tracking at 12.
//

import SwiftUI

struct GameTimeWeatherCard: View {
    let hours: [MatchWeather.ForecastHour]
    let sunset: Date?
    let kickoff: Date
    /// The VENUE's timezone — the hour labels and sunset are the stadium's local time (a sunset is a
    /// local event), while kickoff in the match header stays the fan's own clock. See MatchWeather.venueTimeZone.
    let venueTimeZone: TimeZone

    @Environment(\.dynamicTypeSize) private var typeSize
    private var isAccessibilitySize: Bool { typeSize.isAccessibilitySize }

    private var feelsRow: GameTimeWeatherModel.FeelsRow? {
        GameTimeWeatherModel.feelsLikeRow(hours: hours)
    }
    private var sunsetLabel: String? {
        GameTimeWeatherModel.sunsetInWindow(sunset: sunset, kickoff: kickoff, timeZone: venueTimeZone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            strip
            if feelsRow != nil || sunsetLabel != nil {
                Divider().overlay(Color.dsSeparator)
                footer
            }
            // CC-BY 4.0 attribution (kept minimal; the full credit lives on the roadmap's
            // privacy/disclaimer page). One credit covers all Open-Meteo data in the app.
            Text("Weather by Open-Meteo")
                .dsFont(13, weight: .regular)
                .foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // MARK: Title

    // The venue name is deliberately NOT shown here — it's already in the match-detail header right
    // above this card, so repeating it read as redundant (owner 2026-08-12).
    private var titleRow: some View {
        Text("Expected game-time weather")
            .dsFont(17, weight: .bold)
            .foregroundStyle(Color.dsFgPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Strip

    /// At AX1 the 4 columns can't sit side-by-side legibly, so they reflow to a 2×2 grid
    /// (StandingsView's isAccessibilitySize precedent). At every normal size it's a 4-wide HStack.
    @ViewBuilder
    private var strip: some View {
        if isAccessibilitySize {
            let rows = stride(from: 0, to: hours.count, by: 2).map { Array(hours[$0..<min($0 + 2, hours.count)]) }
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                    HStack(spacing: 10) {
                        ForEach(pair, id: \.time) { column(for: $0) }
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(hours, id: \.time) { column(for: $0) }
            }
        }
    }

    /// One hour column. Index 1 is kickoff (the proxy guarantees the ordering) — it gets the
    /// cyan highlight + "KICKOFF" marker.
    private func column(for hour: MatchWeather.ForecastHour) -> some View {
        let isKickoff = hours.firstIndex(of: hour) == 1
        return VStack(spacing: 5) {
            Text(hour.hourLabel(timeZone: venueTimeZone))
                .dsFont(13, weight: .semibold)
                .foregroundStyle(isKickoff ? Color.dsStateKickoff : Color.dsFgSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("KICKOFF")
                .dsFont(12, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(Color.dsStateKickoff)
                .opacity(isKickoff ? 1 : 0)   // reserve the row so all columns align

            Image(systemName: hour.symbolName)
                .font(.system(size: 28))
                .symbolRenderingMode(.multicolor)
                .frame(height: 30)

            Text("\(hour.roundedTemp)°")
                .dsFont(20, weight: .bold, monospacedDigit: true)
                .foregroundStyle(Color.dsFgPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            (Text(Image(systemName: "wind")) + Text(" \(hour.roundedWind) mph"))
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(hour.showsPrecip ? "\(hour.precipPct)%" : " ")
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsWeatherPrecip)
                .opacity(hour.showsPrecip ? 1 : 0)   // reserve the row so columns stay aligned
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 0)   // ⚠️ minHeight/flex, never fixed height (AX1)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background {
            if isKickoff {
                RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous)
                    .fill(Color.dsStateKickoff.opacity(0.08))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(columnAccessibilityLabel(hour, isKickoff: isKickoff))
    }

    private func columnAccessibilityLabel(_ hour: MatchWeather.ForecastHour, isKickoff: Bool) -> String {
        var parts: [String] = []
        if isKickoff { parts.append("Kickoff") }
        parts.append(hour.hourLabel(timeZone: venueTimeZone))
        parts.append("\(hour.roundedTemp) degrees")
        parts.append("wind \(hour.roundedWind) miles per hour")
        if hour.showsPrecip { parts.append("\(hour.precipPct) percent chance of precipitation") }
        return parts.joined(separator: ", ")
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let feelsRow {
                footerLine(
                    icon: feelsIcon(feelsRow.kind),
                    iconColor: Color.dsFgSecondary,
                    label: feelsLabel(feelsRow.kind),
                    value: feelsRow.minF == feelsRow.maxF ? "\(feelsRow.minF)°" : "\(feelsRow.minF)–\(feelsRow.maxF)°",
                    trailing: "during the match")
            }
            if let sunsetLabel {
                footerLine(
                    icon: "sunset.fill",
                    iconColor: Color.dsWeatherSunset,
                    label: "Sunset at",
                    value: sunsetLabel,
                    trailing: nil)
            }
        }
    }

    private func feelsIcon(_ kind: GameTimeWeatherModel.FeelsKind) -> String {
        switch kind {
        case .heatIndex: return "thermometer.high"
        case .windChill: return "wind.snow"
        case .feelsLike: return "wind"
        }
    }

    private func feelsLabel(_ kind: GameTimeWeatherModel.FeelsKind) -> String {
        switch kind {
        case .heatIndex: return "Heat index"
        case .windChill: return "Wind chill"
        case .feelsLike: return "Feels like"
        }
    }

    /// A footer row: icon + "<label> <bold value> <trailing>", all quiet-tertiary with the value
    /// bumped to secondary-bold.
    private func footerLine(icon: String, iconColor: Color, label: String, value: String, trailing: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 20)
            (
                Text(label + " ")
                    + Text(value).foregroundColor(.dsFgSecondary).fontWeight(.bold)
                    + Text(trailing.map { " \($0)" } ?? "")
            )
            .dsFont(13)
            .foregroundStyle(Color.dsFgSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
