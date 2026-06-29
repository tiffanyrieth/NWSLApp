//
//  MatchActivityAttributes.swift
//  Shared between the NWSLApp app target AND the NWSLLiveActivity widget extension.
//
//  ActivityKit matches a running Activity to its widget by THIS exact type, so the app (which
//  starts/observes Activities + registers push tokens) and the widget (which renders) must compile
//  the SAME definition. That's why it lives in `Shared/` with explicit membership in both targets —
//  NOT in either target's file-system-synchronized group (which would make it app-only or widget-only).
//
//  V2 Live Activity — the silent "glance" layer (lock screen + Dynamic Island live score) that
//  complements the V1 rich push. Static fields are set once at start; ContentState is what the watcher
//  pushes on each update.
//

import ActivityKit
import Foundation

struct MatchActivityAttributes: ActivityAttributes {
    // Static — fixed for the life of the Activity (set at start, never pushed again).
    let matchId: String
    let homeAbbr: String
    let awayAbbr: String
    let homeColorHex: String   // brand hex WITHOUT '#', from DesignTeamColors
    let awayColorHex: String
    let competition: String    // "NWSL" today (NWSL-only until the watcher is competition-aware — V1 gap)

    struct ContentState: Codable, Hashable {
        var homeScore: Int
        var awayScore: Int
        var phase: Phase
        // Local advancing clock: the "virtual kickoff" instant as UNIX SECONDS (= now − elapsedSeconds).
        // While the clock runs, the widget renders an auto-advancing minute from this anchor (no
        // per-minute push); the watcher pushes a corrected value on each half/event. A plain number
        // (not a Date) so it decodes unambiguously from the ActivityKit remote push. nil when paused.
        var clockStartEpoch: Double?
        // Shown verbatim when the clock is NOT ticking: pre = "3:00 PM", halftime = "HT", fulltime = "FT".
        var staticLabel: String?
        var lastScorer: String?     // "S. Smith 67'", nil at 0–0
        var broadcast: String?      // "Paramount+", nil if unknown
    }

    enum Phase: String, Codable, Hashable {
        case pre, live, halftime, extraTime, penalties, fulltime

        var isClockRunning: Bool { self == .live || self == .extraTime }
    }
}
