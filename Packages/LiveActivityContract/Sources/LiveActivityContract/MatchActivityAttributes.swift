//
//  MatchActivityAttributes.swift
//  LiveActivityContract
//
//  The app↔widget V2 Live Activity data contract. ActivityKit matches a running Activity to its
//  widget by THIS exact type, so the app (which starts/observes Activities + registers push tokens)
//  and the widget (which renders) must compile the SAME definition. It used to live in a hand-shared
//  `Shared/` file with explicit dual target-membership; it now lives in this package so the shared
//  definition is a COMPILER-ENFORCED dependency instead of a manual pbxproj hack.
//
//  V2 Live Activity — the silent "glance" layer (lock screen + Dynamic Island live score) that
//  complements the V1 rich push. Static fields are set once at start; ContentState is what the watcher
//  pushes on each update.
//
//  ⚠️ CONTRACT: the Codable keys below BYTE-MATCH the `nwslapp-match-watcher` repo's `activitykit.ts`
//  (LiveAttributes / LiveContentState). NEVER rename a field or add CodingKeys here without changing
//  the watcher in lock-step — a mismatch makes ActivityKit's remote decode fail and V2 silently stops
//  rendering. `LiveActivityContractTests` locks the ContentState key set as a guard.
//

// ActivityKit's `ActivityAttributes` is marked unavailable off iOS, and this package is only ever
// linked into the iOS app + widget targets — so gate the whole contract on iOS. Off-iOS (e.g. a host
// `swift build` or SourceKit indexing for macOS) the module is intentionally empty.
#if os(iOS)
import ActivityKit
import Foundation

public struct MatchActivityAttributes: ActivityAttributes {
    // Static — fixed for the life of the Activity (set at start, never pushed again).
    public let matchId: String
    public let homeAbbr: String
    public let awayAbbr: String
    public let homeColorHex: String   // brand hex WITHOUT '#', from DesignTeamColors
    public let awayColorHex: String
    public let competition: String    // "NWSL", "International" (USWNT V2), …
    // True for a NATIONAL-TEAM match → the widget renders FIFA-code FLAGS instead of club crests
    // (USWNT V2). Defaulted `var` so it's ADDITIVE-optional both ways: old app builds omit it (club
    // crest path), the watcher's newer payload sets it, and the synthesized decoder populates it from
    // JSON when present (absent → nil → club crests). Keys byte-match the watcher's LiveAttributes.
    public var isNational: Bool?

    public init(
        matchId: String,
        homeAbbr: String,
        awayAbbr: String,
        homeColorHex: String,
        awayColorHex: String,
        competition: String,
        isNational: Bool? = nil
    ) {
        self.matchId = matchId
        self.homeAbbr = homeAbbr
        self.awayAbbr = awayAbbr
        self.homeColorHex = homeColorHex
        self.awayColorHex = awayColorHex
        self.competition = competition
        self.isNational = isNational
    }

    public struct ContentState: Codable, Hashable {
        public var homeScore: Int
        public var awayScore: Int
        public var phase: Phase
        // Local advancing clock: the "virtual kickoff" instant as UNIX SECONDS (= now − elapsedSeconds).
        // While the clock runs, the widget renders an auto-advancing minute from this anchor (no
        // per-minute push); the watcher pushes a corrected value on each half/event. A plain number
        // (not a Date) so it decodes unambiguously from the ActivityKit remote push. nil when paused.
        public var clockStartEpoch: Double?
        // Shown verbatim when the clock is NOT ticking: pre = "3:00 PM", halftime = "HT", fulltime = "FT".
        public var staticLabel: String?
        public var lastScorer: String?     // "S. Smith 67'", nil at 0–0 — legacy single line, kept as the
                                           // fallback when the per-side lists below are absent (old watcher)
        public var broadcast: String?      // "Paramount+", nil if unknown
        // Per-side scorer lines ("C. Hutton 5'"), chronological, watcher-capped at 4 (+N overflow) —
        // rendered under each team, FIFA-style. ALL four fields below are Optional BY CONTRACT:
        // an old watcher payload omits them (this struct must still decode), and an old app build
        // ignores them (synthesized Codable skips unknown keys). Keys byte-match the watcher's
        // LiveContentState (activitykit.ts) — grow the two only in lock-step.
        public var homeScorers: [String]?
        public var awayScorers: [String]?
        public var homeRedCards: Int?      // RED cards only (yellows excluded by design); nil when 0
        public var awayRedCards: Int?
        // Stoppage-time label ("45'+2'" / "90'+3'"), set by the watcher ONLY while the match is in
        // added time (numeric clock frozen at the 45:00/90:00 cap). The widget renders THIS verbatim
        // instead of the self-ticking mm:ss timer, since Apple's Text(timerInterval:) can't format
        // football stoppage and its free-run would read "91:12". nil during normal play/pre/HT/FT →
        // widget falls back to the timer/static label. Additive-optional BY CONTRACT (old builds ignore
        // it, old watcher payloads omit it); byte-matches the watcher's LiveContentState key.
        public var stoppageDisplay: String?

        // Optionals default to nil (replicating Swift's synthesized memberwise init) so additive-optional
        // call sites — e.g. the app's debug lifecycle driver — construct a state without every field.
        public init(
            homeScore: Int,
            awayScore: Int,
            phase: Phase,
            clockStartEpoch: Double? = nil,
            staticLabel: String? = nil,
            lastScorer: String? = nil,
            broadcast: String? = nil,
            homeScorers: [String]? = nil,
            awayScorers: [String]? = nil,
            homeRedCards: Int? = nil,
            awayRedCards: Int? = nil,
            stoppageDisplay: String? = nil
        ) {
            self.homeScore = homeScore
            self.awayScore = awayScore
            self.phase = phase
            self.clockStartEpoch = clockStartEpoch
            self.staticLabel = staticLabel
            self.lastScorer = lastScorer
            self.broadcast = broadcast
            self.homeScorers = homeScorers
            self.awayScorers = awayScorers
            self.homeRedCards = homeRedCards
            self.awayRedCards = awayRedCards
            self.stoppageDisplay = stoppageDisplay
        }
    }

    public enum Phase: String, Codable, Hashable {
        case pre, live, halftime, extraTime, penalties, fulltime

        public var isClockRunning: Bool { self == .live || self == .extraTime }
    }
}
#endif
