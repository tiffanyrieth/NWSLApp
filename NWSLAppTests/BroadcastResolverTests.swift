//
//  BroadcastResolverTests.swift
//  NWSLAppTests
//
//  The how-to-watch resolver + the single free/paid table.
//
//  ⚠️ WHY THIS FILE EXISTS. Before 2026-08-03 there were ZERO tests on `BroadcastInfo.info(for:)`,
//  the free/paid mapping, or `BroadcastBrand.color(for:)` — which is exactly why three user-facing
//  defects sat there unseen: a CBSSN match rendered NO how-to-watch card at all, ABC was badged
//  SUBSCRIPTION on one screen and FREE on another, and "Univision" resolved to ION.
//  Every case below is one of those, or a trap that would recreate one.
//

import Testing
@testable import NWSLApp

@Suite("Broadcast resolver")
struct BroadcastResolverTests {

    // MARK: - The reported bug

    @Test func cbssnResolvesInsteadOfVanishing() {
        // THE BUG: exact-key lookup missed "CBSSN", `info(for:)` returned nil, and the card had no
        // else-branch — so the whole how-to-watch section silently disappeared on the broadcaster
        // people struggle with most.
        #expect(BroadcastInfo.info(for: "CBSSN") != nil)
        #expect(BroadcastInfo.info(for: "CBS Sports Network") != nil)
        #expect(BroadcastInfo.info(for: "CBSSN")?.name == "CBS Sports Network")
        // And it must be honest that there is no cheap way in.
        #expect(BroadcastInfo.info(for: "CBSSN")?.access == .paid)
    }

    @Test func everyStringESPNActuallySendsResolves() {
        // Harvested from the app's own fixture (playoffs-2025-scoreboard.json) plus the 2026 partners.
        // ABC/ESPN Deportes/ESPN+ were ALL missing keys — same vanishing-card bug as CBSSN.
        for name in ["ABC", "ESPN", "ESPN2", "ESPN Deportes", "ESPN+", "CBS", "CBSSN",
                     "CBS Sports Network", "Paramount+", "NWSL+", "Prime Video", "ION"] {
            #expect(BroadcastInfo.info(for: name) != nil, "no guide for \(name)")
        }
    }

    // MARK: - Ordering traps (each would silently mis-resolve)

    @Test func univisionIsNotION() {
        // ⚠️ A bare contains("ion") matches "Univision". The app folds ~15 women's national-team
        // feeds into the schedule, so a Mexico fixture would have rendered a purple ION chip and a
        // FREE badge for a channel that is neither.
        #expect(BroadcastInfo.info(for: "Univision")?.name != "ION")
        #expect(BroadcastInfo.info(for: "TelevisaUnivision")?.name != "ION")
        #expect(BroadcastAccess.of("Univision") == .unknown)
    }

    @Test func golazoIsNotCBSSportsNetwork() {
        // Different channel, opposite access: Golazo is free ad-supported, CBSSN needs cable.
        #expect(BroadcastInfo.info(for: "CBS Sports Golazo Network")?.name == "CBS Sports Golazo Network")
        #expect(BroadcastInfo.info(for: "CBS Sports Golazo Network")?.access == .free)
        #expect(BroadcastInfo.info(for: "CBSSN")?.access == .paid)
    }

    @Test func espnVariantsDontCollapseIntoPlainESPN() {
        #expect(BroadcastInfo.info(for: "ESPN+")?.name == "ESPN+")
        #expect(BroadcastInfo.info(for: "ESPN Deportes")?.name == "ESPN Deportes")
        #expect(BroadcastInfo.info(for: "ESPN2")?.name == "ESPN")
    }

    @Test func nwslPlusDoesNotSwallowEveryStringContainingNWSL() {
        // "NWSL Championship on CBS" must resolve to CBS, not the streaming service.
        #expect(BroadcastInfo.info(for: "NWSL Championship on CBS")?.name == "CBS")
        #expect(BroadcastInfo.info(for: "NWSL+")?.name == "NWSL+")
    }

    // MARK: - Access: ONE table, and it must never guess

    @Test func abcIsFreeOverTheAir() {
        // ⚠️ THE DISAGREEMENT. Match Detail said SUBSCRIPTION for ABC; Home's Coming Up said FREE.
        // Same match, two screens, opposite answers — and ABC is free over the air, so Match Detail
        // was the wrong one. Both surfaces now read this.
        #expect(BroadcastAccess.of("ABC") == .free)
    }

    @Test func cbsSportsNetworkIsPaidEvenThoughItContainsCBS() {
        // The other half of the disagreement: Home called any "CBS*" string FREE, which is right for
        // the broadcast network and wrong for the cable sports channel.
        #expect(BroadcastAccess.of("CBS") == .free)
        #expect(BroadcastAccess.of("CBSSN") == .paid)
        #expect(BroadcastAccess.of("CBS Sports Network") == .paid)
    }

    @Test func unknownBroadcasterGetsNoBadgeAtAll() {
        // ⚠️ Tri-state, not Bool. The old pair defaulted unknown → (free: false), which rendered a
        // confident SUBSCRIPTION badge for a channel we'd never heard of — possibly a free
        // over-the-air one. A fabricated paywall is the banned "fallback that looks like success".
        #expect(BroadcastAccess.of("Telemundo") == .unknown)
        #expect(BroadcastAccess.of("Telemundo").badge == nil)
        #expect(BroadcastAccess.of("Telemundo").shortBadge == nil)
        #expect(BroadcastAccess.of(nil) == .unknown)
    }

    @Test func freeAndPaidBadgesAreStillRendered() {
        #expect(BroadcastAccess.of("ION").badge == "FREE")
        #expect(BroadcastAccess.of("ION").shortBadge == "FREE")
        #expect(BroadcastAccess.of("Prime Video").badge == "SUBSCRIPTION")
        #expect(BroadcastAccess.of("Prime Video").shortBadge == "SUB")
    }

    // MARK: - Input hygiene

    @Test func emptyAndWhitespaceNamesResolveToNothing() {
        // `Event.broadcastName` filters empty but not whitespace, so "   " can reach the card.
        #expect(BroadcastInfo.info(for: nil) == nil)
        #expect(BroadcastInfo.info(for: "") == nil)
        #expect(BroadcastInfo.info(for: "   ") == nil)
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(BroadcastInfo.info(for: "cbssn")?.name == "CBS Sports Network")
        #expect(BroadcastInfo.info(for: "prime video")?.name == "Prime Video")
    }

    // MARK: - Content promises the copy makes

    @Test func deviceRowsAreStablyIdentified() {
        // ⚠️ `Device.id` used to be `UUID()`, which was safe only while every value was a static
        // let. The unknown-broadcaster path constructs values, and fresh ids on each body pass would
        // re-create every ForEach row and break the expand animation.
        let ion = BroadcastInfo.info(for: "ION")!
        #expect(Set(ion.devices.map(\.id)).count == ion.devices.count)
        #expect(ion.devices.first?.id == ion.devices.first?.device)
    }

    @Test func cbssnCopyDoesNotSendPeopleToParamountPlus() {
        // The owner spent an hour on this: Paramount+ carries NO tier that includes CBS Sports
        // Network, so the old "open the Paramount+ app" step meant paying and still missing the
        // match. The entry must say so rather than imply a path that doesn't exist.
        let steps = BroadcastInfo.info(for: "CBSSN")!.devices.map(\.steps).joined(separator: " ")
        #expect(steps.contains("does NOT carry"))
        #expect(steps.contains("NWSL+"), "must offer the free replay fallback")
    }

    @Test func ionCopyCarriesTheFreePathsPeopleMiss() {
        // A fan paid $120/month for Fubo before learning ION is free. These are the paths named on
        // r/NWSL that the old copy omitted.
        let steps = BroadcastInfo.info(for: "ION")!.devices.map(\.steps).joined(separator: " ")
        for path in ["Tubi", "Pluto TV", "Plex", "iontelevision.com/find-us"] {
            #expect(steps.contains(path), "ION guidance is missing \(path)")
        }
    }

    @Test func victoryPlusExplainsWhereItWent() {
        // ESPN's feed may still carry the string. Dropping the key would fall through to the generic
        // unknown card and say nothing about the July 2026 termination.
        let info = BroadcastInfo.info(for: "Victory+")
        #expect(info != nil)
        #expect(info!.note.contains("NWSL+"))
    }
}

@Suite("Broadcast brand colors")
struct BroadcastBrandTests {

    @Test func ionColorDoesNotLeakOntoUnivision() {
        // The chip is a separate table from the guide and had the same substring trap.
        #expect(BroadcastBrand.color(for: "Univision") != BroadcastBrand.color(for: "ION"))
        #expect(BroadcastBrand.color(for: "Scripps Sports") == BroadcastBrand.color(for: "ION"))
    }

    @Test func knownBrandsKeepTheirColors() {
        #expect(BroadcastBrand.color(for: "CBSSN") == BroadcastBrand.color(for: "CBS"))
        #expect(BroadcastBrand.color(for: "ABC") == BroadcastBrand.color(for: "ESPN"))
    }
}
