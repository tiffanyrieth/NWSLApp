//
//  MatchClockDisplay.swift
//  MatchClockKit
//
//  The single consolidated live-clock GUARD. Every live surface (Schedule card, Match Detail header,
//  Home "coming up" row) used to re-implement the same three-branch ladder inline — halftime → static
//  label, live+anchored → tick, else → ESPN fallback string. Duplicated across three frequently-edited
//  view files, an innocent layout edit could drop the `isHalftime` branch (ticking through the break)
//  or the anchor guard (fabricating a stoppage minute) — both already-fixed mid-match bugs, invisible
//  until a real live game. `resolve(...)` encodes that decision ONCE; the views call it + render the
//  result through `LiveMatchClockView`, keeping only their own styling.
//

import SwiftUI

/// The resolved live-clock display for a match: tick locally, show a fixed string, or show nothing.
public enum MatchClockDisplay: Equatable {
    /// Tick a local football minute from this anchor (LiveMinuteText).
    case ticking(clockSeconds: Double, period: Int?, anchor: Date)
    /// Show this fixed string, no ticking (halftime label, or ESPN's own clock fallback).
    case staticLabel(String)
    /// Nothing to show here (not live, or no data + no fallback) — the caller renders its own text.
    case empty

    /// The one place the halftime / anchor / fallback decision lives. Only an "in" match ever ticks;
    /// halftime NEVER ticks (a static label instead); a nil `anchor` (e.g. a fresh-at-cap match whose
    /// stoppage minute is unknowable) falls back to the ESPN string rather than fabricating a minute.
    ///
    /// - Parameters:
    ///   - halftimeLabel: shown when the match is at halftime; nil → `.empty` (caller supplies its own).
    ///   - fallback: shown live when there's no local anchor/clock; nil → `.empty`.
    public static func resolve(
        statusState: String?,
        isHalftime: Bool,
        clockSeconds: Double?,
        period: Int?,
        anchor: Date?,
        halftimeLabel: String? = nil,
        fallback: String? = nil
    ) -> MatchClockDisplay {
        guard statusState == "in" else { return .empty }
        if isHalftime { return halftimeLabel.map(MatchClockDisplay.staticLabel) ?? .empty }
        if let anchor, let clock = clockSeconds {
            return .ticking(clockSeconds: clock, period: period, anchor: anchor)
        }
        if let fallback { return .staticLabel(fallback) }
        return .empty
    }
}

/// Renders a resolved `MatchClockDisplay`, styled by the caller's `content` closure. `suffix` is
/// appended ONLY to the ticking minute (e.g. " — Second Half", " · 1–0") — static labels already carry
/// their full text. This is the view the three live surfaces call instead of re-implementing the ladder.
public struct LiveMatchClockView<Content: View>: View {
    public let display: MatchClockDisplay
    public let suffix: String
    @ViewBuilder public let content: (String) -> Content

    public init(
        display: MatchClockDisplay,
        suffix: String = "",
        @ViewBuilder content: @escaping (String) -> Content
    ) {
        self.display = display
        self.suffix = suffix
        self.content = content
    }

    public var body: some View {
        switch display {
        case let .ticking(clockSeconds, period, anchor):
            LiveMinuteText(clockSeconds: clockSeconds, period: period, anchor: anchor) { content($0 + suffix) }
        case let .staticLabel(label):
            content(label)
        case .empty:
            EmptyView()
        }
    }
}
