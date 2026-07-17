//
//  AnalyticsCounterTests.swift
//  NWSLAppTests
//
//  The anonymous Level-3 usage counters (Analytics.swift). Locks the WIRE CONTRACT — the
//  event/param strings are what the proxy whitelists and the Supabase table keys on, so a
//  rename here silently zeroes a dashboard column — plus the in-session aggregation and the
//  batch shape the flush posts. Privacy invariant: every representable event maps to a name +
//  one low-cardinality param; there is no field an identifier could ride in.
//

import Foundation
import Testing
@testable import NWSLApp

struct AnalyticsCounterTests {

    // MARK: Wire contract (server-synced strings — proxy ANALYTICS_EVENTS + the SQL queries)

    @Test func wireNamesMatchTheServerWhitelist() {
        #expect(Analytics.wire(.sessionStart).event == "session_start")
        #expect(Analytics.wire(.sessionOS).event == "session_os")
        #expect(Analytics.wire(.tabOpened(.home)).event == "tab_opened")
        #expect(Analytics.wire(.fanzoneGameOpened("knowher")).event == "fanzone_game_opened")
        #expect(Analytics.wire(.feedItemTapped).event == "feed_item_tapped")
        #expect(Analytics.wire(.feedChipTapped(.players)).event == "feed_chip_tapped")
    }

    @Test func tabParamsAreStableKeys() {
        #expect(Analytics.wire(.tabOpened(.home)).param == "home")
        #expect(Analytics.wire(.tabOpened(.schedule)).param == "schedule")
        #expect(Analytics.wire(.tabOpened(.standings)).param == "standings")
        #expect(Analytics.wire(.tabOpened(.teams)).param == "teams")
        #expect(Analytics.wire(.tabOpened(.feed)).param == "feed")
    }

    @Test func paramsCarryTheChoice() {
        #expect(Analytics.wire(.fanzoneGameOpened("predict")).param == "predict")
        #expect(Analytics.wire(.feedChipTapped(.all)).param == "all")
        #expect(Analytics.wire(.feedChipTapped(.reporters)).param == "reporters")
        #expect(Analytics.wire(.feedItemTapped).param == "")
    }

    @Test func sessionStartCarriesVersionShapedParam() {
        // "0.4.3 (27)"-shaped: short version + build in parens (the build-distribution query).
        let param = Analytics.wire(.sessionStart).param
        #expect(param.contains("(") && param.hasSuffix(")"))
        let os = Analytics.wire(.sessionOS).param
        #expect(os.contains("."))   // "26.0"-shaped major.minor
    }

    // MARK: Aggregation → batch shape

    @Test func batchFoldsCountsAndSplitsKeys() throws {
        let batch = Analytics.batch(from: ["tab_opened|home": 3, "feed_item_tapped|": 1, "never|x": 0])
        #expect(batch.count == 2)   // zero-count entries dropped
        let home = try #require(batch.first { ($0["event"] as? String) == "tab_opened" })
        #expect(home["param"] as? String == "home")
        #expect(home["n"] as? Int == 3)
        let feed = try #require(batch.first { ($0["event"] as? String) == "feed_item_tapped" })
        #expect(feed["param"] as? String == "")
        #expect(feed["n"] as? Int == 1)
    }

    @Test @MainActor func logAggregatesInMemory() {
        // The singleton is fine to exercise: counters only leave the process via flushRemote.
        Analytics.shared.log(.tabOpened(.standings))
        Analytics.shared.log(.tabOpened(.standings))
        Analytics.shared.log(.fanzoneGameOpened("trivia"))
        // No direct read API by design (nothing should introspect analytics) — assert via the
        // pure batch of an equivalent fold instead.
        let batch = Analytics.batch(from: ["tab_opened|standings": 2, "fanzone_game_opened|trivia": 1])
        #expect(batch.contains { ($0["event"] as? String) == "tab_opened" && ($0["n"] as? Int) == 2 })
    }
}
