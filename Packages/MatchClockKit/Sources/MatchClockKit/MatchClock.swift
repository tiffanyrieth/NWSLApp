//
//  MatchClock.swift
//  MatchClockKit
//
//  The pure football-minute formatter for the app's live surfaces (Schedule cards + Match Detail):
//  a smooth, broadcast-style minute that ticks locally via TimelineView (see LiveMinuteText),
//  corrected on each ~30s data refresh — no server cost. (The Live Activity widget deliberately stays
//  on Apple's self-ticking `Text(timerInterval:)` mm:ss to keep push volume to real game events only;
//  per-minute pushes don't scale.)
//
//  Ticks by WHOLE MINUTE from kickoff (1', 2', … 45'), then shows stoppage as "{cap}'+{n}'" past the
//  regulation cap for the period (45' in H1, 90' in H2) — e.g. "45'+2'", "90'+3'" — exactly like
//  FIFA/Apple/Google. It does NOT decide HT/FT: those come from the watcher/ESPN status (a static
//  "HT"/"FT" label shown when the clock isn't running). Input is match-ELAPSED seconds (ESPN's
//  `status.clock` is continuous across halves — a 2nd-half value reads "81'", not a reset "36'"), so
//  H2 elapsed is ~2700–5400s and the period cap turns that into "46'…90'…90'+n".
//

public enum MatchClock {
    /// The minute label for a running clock, e.g. "23'", "45'+2'", "90'+3'".
    /// `elapsedSeconds` = match-elapsed time; `period` = 1/2 (regulation) or 3/4 (ET).
    public static func minuteLabel(elapsedSeconds: Double, period: Int?) -> String {
        let wholeMinutes = max(0, Int(elapsedSeconds / 60))
        let displayMinute = wholeMinutes + 1              // 1-based "current minute"
        if let cap = regulationCap(period: period), displayMinute > cap {
            return "\(cap)'+\(displayMinute - cap)'"
        }
        return "\(displayMinute)'"
    }

    /// Regulation-minute cap by period: H1 45, H2 90, ET halves 105/120. `nil` for an
    /// unknown/absent period → no stoppage folding, just the raw minute (fail-soft).
    public static func regulationCap(period: Int?) -> Int? {
        switch period {
        case 1: return 45
        case 2: return 90
        case 3: return 105
        case 4: return 120
        default: return nil
        }
    }
}
