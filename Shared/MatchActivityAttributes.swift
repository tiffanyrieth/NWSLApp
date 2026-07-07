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
        var lastScorer: String?     // "S. Smith 67'", nil at 0–0 — legacy single line, kept as the
                                    // fallback when the per-side lists below are absent (old watcher)
        var broadcast: String?      // "Paramount+", nil if unknown
        // Per-side scorer lines ("C. Hutton 5'"), chronological, watcher-capped at 4 (+N overflow) —
        // rendered under each team, FIFA-style. ALL four fields below are Optional BY CONTRACT:
        // an old watcher payload omits them (this struct must still decode), and an old app build
        // ignores them (synthesized Codable skips unknown keys). Keys byte-match the watcher's
        // LiveContentState (activitykit.ts) — grow the two only in lock-step.
        var homeScorers: [String]?
        var awayScorers: [String]?
        var homeRedCards: Int?      // RED cards only (yellows excluded by design); nil when 0
        var awayRedCards: Int?
    }

    enum Phase: String, Codable, Hashable {
        case pre, live, halftime, extraTime, penalties, fulltime

        var isClockRunning: Bool { self == .live || self == .extraTime }
    }
}

/// The football match clock for the app's live surfaces (Schedule cards + Match Detail):
/// a smooth, broadcast-style minute that ticks locally via TimelineView, corrected on each
/// ~30s data refresh — no server cost. (The Live Activity widget deliberately stays on
/// Apple's self-ticking `Text(timerInterval:)` mm:ss to keep push volume to real game
/// events only; per-minute pushes don't scale. Lives in `Shared/` so it's one canonical
/// clock the widget CAN adopt later if that trade-off ever changes.)
///
/// Ticks by WHOLE MINUTE from kickoff (1', 2', … 45'), then shows stoppage as
/// "{cap}'+{n}'" past the regulation cap for the period (45' in H1, 90' in H2) — e.g.
/// "45'+2'", "90'+3'" — exactly like FIFA/Apple/Google. It does NOT decide HT/FT: those
/// come from the watcher/ESPN status (a static "HT"/"FT" label shown when the clock isn't
/// running). Input is match-ELAPSED seconds (ESPN's `status.clock` is continuous across
/// halves — a 2nd-half value reads "81'", not a reset "36'"), so H2 elapsed is ~2700–5400s
/// and the period cap turns that into "46'…90'…90'+n".
enum MatchClock {
    /// The minute label for a running clock, e.g. "23'", "45'+2'", "90'+3'".
    /// `elapsedSeconds` = match-elapsed time; `period` = 1/2 (regulation) or 3/4 (ET).
    static func minuteLabel(elapsedSeconds: Double, period: Int?) -> String {
        let wholeMinutes = max(0, Int(elapsedSeconds / 60))
        let displayMinute = wholeMinutes + 1              // 1-based "current minute"
        if let cap = regulationCap(period: period), displayMinute > cap {
            return "\(cap)'+\(displayMinute - cap)'"
        }
        return "\(displayMinute)'"
    }

    /// Regulation-minute cap by period: H1 45, H2 90, ET halves 105/120. `nil` for an
    /// unknown/absent period → no stoppage folding, just the raw minute (fail-soft).
    static func regulationCap(period: Int?) -> Int? {
        switch period {
        case 1: return 45
        case 2: return 90
        case 3: return 105
        case 4: return 120
        default: return nil
        }
    }
}
