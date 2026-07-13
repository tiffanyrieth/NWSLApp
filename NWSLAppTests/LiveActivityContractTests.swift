//
//  LiveActivityContractTests.swift
//  NWSLAppTests
//
//  Guards the app↔widget Live Activity data contract (LiveActivityContract package). The Codable keys
//  of `MatchActivityAttributes.ContentState` BYTE-MATCH the `nwslapp-match-watcher` repo's
//  `activitykit.ts` (LiveContentState). ActivityKit decodes the watcher's remote push into this exact
//  struct — a renamed/added/dropped key makes that decode fail and V2 silently stops rendering (a bug
//  class that cost weeks: see docs/live-activity-v2.md §0). These tests turn that comment-only contract
//  into a compiler + test guard: the key-set test fails the instant a field is renamed, and the
//  tolerance test locks the "additive-optional" rule (an OLD watcher payload must still decode).
//

import Foundation
import Testing
import LiveActivityContract

struct LiveActivityContractTests {

    /// The exact wire key set the watcher sends. Update BOTH this set and `activitykit.ts` together —
    /// never one alone. A diff here is the tripwire for an app↔watcher contract drift.
    private static let expectedContentStateKeys: Set<String> = [
        "homeScore", "awayScore", "phase",
        "clockStartEpoch", "staticLabel", "lastScorer", "broadcast",
        "homeScorers", "awayScorers", "homeRedCards", "awayRedCards",
        "stoppageDisplay",
    ]

    @Test func contentStateEncodesExactlyTheContractKeys() throws {
        // Every field NON-nil so the encoder emits all keys (synthesized Codable uses encodeIfPresent
        // for optionals → a nil field would be silently absent and hide a rename).
        let state = MatchActivityAttributes.ContentState(
            homeScore: 2, awayScore: 1, phase: .live,
            clockStartEpoch: 1_000_000, staticLabel: "HT",
            lastScorer: "B. Banda 23'", broadcast: "Paramount+",
            homeScorers: ["B. Banda 23'"], awayScorers: ["S. Wilson 70'"],
            homeRedCards: 1, awayRedCards: 0, stoppageDisplay: "90'+2'"
        )

        let data = try JSONEncoder().encode(state)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set(object?.keys ?? [:].keys)

        #expect(keys == Self.expectedContentStateKeys)
    }

    @Test func oldWatcherPayloadStillDecodes() throws {
        // Additive-optional contract: a payload from an OLD watcher (only the original core fields,
        // none of the later per-side/stoppage keys) must decode without error — old server + new app.
        let legacyJSON = """
        { "homeScore": 1, "awayScore": 0, "phase": "live", "clockStartEpoch": 123, "broadcast": "Paramount+" }
        """
        let data = Data(legacyJSON.utf8)
        let state = try JSONDecoder().decode(MatchActivityAttributes.ContentState.self, from: data)

        #expect(state.homeScore == 1)
        #expect(state.phase == .live)
        #expect(state.homeScorers == nil)       // absent additive key → nil, not a decode failure
        #expect(state.stoppageDisplay == nil)
    }

    @Test func phaseClockRunningMatchesTheLiveStates() {
        // The widget keys clock ticking off this — only live/extraTime run the auto-advancing minute.
        #expect(MatchActivityAttributes.Phase.live.isClockRunning)
        #expect(MatchActivityAttributes.Phase.extraTime.isClockRunning)
        #expect(!MatchActivityAttributes.Phase.pre.isClockRunning)
        #expect(!MatchActivityAttributes.Phase.halftime.isClockRunning)
        #expect(!MatchActivityAttributes.Phase.fulltime.isClockRunning)
        #expect(!MatchActivityAttributes.Phase.penalties.isClockRunning)
    }
}
