//
//  LiveMinuteText.swift
//  NWSLApp
//
//  A live football-minute label that ticks LOCALLY between data refreshes, so a running
//  match's minute advances smoothly on-screen ("51'" → "52'", "45'+2'" → "45'+3'") with
//  zero network/server cost — the premium clock, done client-side (see the cost analysis
//  behind Phase 3: per-minute server pushes don't scale, local TimelineView ticking does).
//
//  Seeded from ESPN's `status.clock` (match-elapsed seconds) captured at `anchor` (the
//  fetch instant, MatchStore.lastLoadedAt); MatchClock formats it. Each ~30s live refresh
//  hands in a fresh (clock, anchor) that re-seeds and corrects any drift. Render only while
//  the match is live; pre/half/full-time show a static label elsewhere.
//

import SwiftUI

struct LiveMinuteText<Content: View>: View {
    /// ESPN `status.clock` — match-elapsed seconds as of `anchor`.
    let clockSeconds: Double
    /// ESPN `status.period` — 1/2 regulation, 3/4 ET (drives the 45'/90' cap).
    let period: Int?
    /// When `clockSeconds` was current (MatchStore.lastLoadedAt).
    let anchor: Date
    /// Styles the computed label (e.g. `Text($0).dsFont(...)`), so each surface keeps its look.
    @ViewBuilder var content: (String) -> Content

    var body: some View {
        // Re-render on each whole MATCH-minute boundary (aligned, so the label flips exactly
        // when the minute rolls over — not up to 60s late) and every 60s after.
        TimelineView(.periodic(from: currentMinuteStart, by: 60)) { context in
            let elapsed = clockSeconds + context.date.timeIntervalSince(anchor)
            content(MatchClock.minuteLabel(elapsedSeconds: elapsed, period: period))
        }
    }

    /// The start instant of the CURRENT match minute (in the past), so the periodic schedule
    /// always has an entry ≤ now (immediate render) and steps exactly on minute rollovers.
    private var currentMinuteStart: Date {
        let now = Date()
        let elapsedNow = clockSeconds + now.timeIntervalSince(anchor)
        let intoMinute = elapsedNow.truncatingRemainder(dividingBy: 60)
        return now.addingTimeInterval(-intoMinute)
    }
}
