//
//  BroadcastLinkTests.swift
//  NWSLAppTests
//
//  Verifies the broadcast-name → streaming-URL mapping (used by the tappable 📺
//  label on MatchCard and MatchDetailView), including the unknown → nil case.
//

import Foundation
import Testing
@testable import NWSLApp

struct BroadcastLinkTests {

    @Test func mapsKnownBroadcasters() {
        #expect(BroadcastLink.url(for: "Prime Video")?.host == "www.amazon.com")
        #expect(BroadcastLink.url(for: "Amazon Prime")?.host == "www.amazon.com")
        #expect(BroadcastLink.url(for: "ESPN")?.host == "www.espn.com")
        #expect(BroadcastLink.url(for: "ABC")?.host == "www.espn.com")
        #expect(BroadcastLink.url(for: "CBS Sports Network")?.host == "www.cbssports.com")
        #expect(BroadcastLink.url(for: "Paramount+")?.host == "www.paramountplus.com")
        #expect(BroadcastLink.url(for: "Victory+")?.host == "www.victoryplus.com")
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(BroadcastLink.url(for: "prime video") != nil)
        #expect(BroadcastLink.url(for: "PARAMOUNT+") != nil)
    }

    @Test func unknownBroadcasterIsNil() {
        #expect(BroadcastLink.url(for: "Some Local Channel 7") == nil)
        #expect(BroadcastLink.url(for: "") == nil)
    }
}
