//
//  PredictCommunityTests.swift
//  NWSLAppTests
//
//  The community pick aggregate — the counts behind Predict the XI's share bars, consensus XI and
//  contrarian panel.
//
//  ⚠️ THE PROPERTY MOST WORTH PINNING: sealed is not zero. Before submissions close the proxy sends
//  no per-player data, and every derived read must return nil rather than 0 or 0%. A "0% picked her"
//  rendered as fact would be the banned failure-that-looks-like-success, and it would leak the
//  shape of the answer to anyone still picking.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictCommunityTests {

    private func community(revealed: Bool = true,
                           submissions: Int = 100,
                           counts: [PredictCommunity.Pick: Int] = [:]) -> PredictCommunity {
        PredictCommunity(eventID: "e1", team: "WAS", week: 12, revealed: revealed,
                         closesAt: nil, submissions: submissions, counts: counts)
    }

    // MARK: - Shares

    /// Set-wise across slots, matching how the scorer treats a hit: she counts wherever you put her.
    /// If this counted per-slot, a versatile player's percentage would read lower than the number of
    /// people who actually picked her.
    @Test func shareSumsAPlayerAcrossEverySlotSheWasPickedIn() {
        let c = community(counts: [
            .init(playerID: "p1", slot: 1): 30,
            .init(playerID: "p1", slot: 4): 20,
            .init(playerID: "p2", slot: 2): 50,
        ])
        #expect(c.share(forPlayer: "p1") == 0.5)
        #expect(c.share(forPlayer: "p2") == 0.5)
    }

    @Test func shareIsNilWhileSealed() {
        let c = community(revealed: false, counts: [.init(playerID: "p1", slot: 1): 30])
        #expect(c.share(forPlayer: "p1") == nil)
    }

    /// No submissions means no denominator. Returning 0 would be a division-by-zero dressed up as a
    /// fact; nil makes the caller hide the bar.
    @Test func shareIsNilWithNoSubmissions() {
        let c = community(submissions: 0, counts: [.init(playerID: "p1", slot: 1): 0])
        #expect(c.share(forPlayer: "p1") == nil)
    }

    @Test func aPlayerNobodyPickedHasAZeroShareNotANilOne() {
        // Distinct from "sealed": here we genuinely know nobody picked her.
        let c = community(counts: [.init(playerID: "p1", slot: 1): 40])
        #expect(c.share(forPlayer: "unpicked") == 0)
    }

    // MARK: - Consensus XI

    @Test func consensusPicksTheMostBackedPlayerInEachSlot() {
        let c = community(counts: [
            .init(playerID: "p1", slot: 0): 80,
            .init(playerID: "p2", slot: 0): 20,
            .init(playerID: "p3", slot: 1): 60,
        ])
        let xi = c.consensusXI(slots: [0, 1])
        #expect(xi[0] == "p1")
        #expect(xi[1] == "p3")
    }

    /// ⚠️ An XI cannot field the same player twice. A versatile player can lead at two slots, so the
    /// more decisive slot keeps her and the other falls through to its runner-up.
    @Test func consensusNeverNamesTheSamePlayerTwice() {
        let c = community(counts: [
            .init(playerID: "utility", slot: 1): 90,   // leads slot 1 decisively
            .init(playerID: "utility", slot: 2): 55,   // also leads slot 2, but narrowly
            .init(playerID: "backup", slot: 2): 40,
        ])
        let xi = c.consensusXI(slots: [1, 2])
        #expect(xi[1] == "utility")
        #expect(xi[2] == "backup")
        #expect(Set(xi.values).count == xi.count)
    }

    @Test func consensusIsEmptyWhileSealed() {
        let c = community(revealed: false, counts: [.init(playerID: "p1", slot: 0): 80])
        #expect(c.consensusXI(slots: [0]).isEmpty)
        #expect(c.consensusCorrect(slots: [0], actualStarterIDs: ["p1"]) == nil)
    }

    @Test func consensusCorrectCountsOnlyThoseWhoStarted() {
        let c = community(counts: [
            .init(playerID: "p1", slot: 0): 80,
            .init(playerID: "p2", slot: 1): 70,
        ])
        #expect(c.consensusCorrect(slots: [0, 1], actualStarterIDs: ["p1"]) == 1)
    }

    // MARK: - Contrarians and omissions

    @Test func contrariansAreYourLowestOwnedPicksMostContrarianFirst() {
        let c = community(counts: [
            .init(playerID: "rare", slot: 1): 12,
            .init(playerID: "uncommon", slot: 2): 25,
            .init(playerID: "popular", slot: 3): 90,
        ])
        let result = c.contrarians(among: ["rare", "uncommon", "popular"], below: 0.30)
        #expect(result.map(\.playerID) == ["rare", "uncommon"])
    }

    @Test func omissionsAreWidelyBackedPlayersYouLeftOut() {
        let c = community(counts: [
            .init(playerID: "mine", slot: 1): 40,
            .init(playerID: "theirs", slot: 2): 68,
        ])
        let result = c.highOwnershipOmissions(notPicked: ["mine"], above: 0.60)
        #expect(result.map(\.playerID) == ["theirs"])
    }

    @Test func contrariansAreEmptyWhileSealed() {
        let c = community(revealed: false, counts: [.init(playerID: "rare", slot: 1): 12])
        #expect(c.contrarians(among: ["rare"], below: 0.30).isEmpty)
    }

    // MARK: - Wire decoding

    /// The proxy withholds `picks` entirely on a sealed fixture — not an empty array, no key at all.
    /// Decoding must survive that and produce a sealed value carrying only the count.
    @Test func decodesASealedFixtureWithOnlyASubmissionCount() throws {
        let json = """
        {"season":"2026","fixtures":[
          {"event":"401","team":"WAS","week":12,"revealed":false,"closesAt":"2026-07-26T21:00:00Z","submissions":312}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PredictCommunityResponse.self, from: json)
        let fixture = try #require(decoded.fixtures?.first).domain()
        #expect(fixture.revealed == false)
        #expect(fixture.submissions == 312)
        #expect(fixture.counts.isEmpty)
        #expect(fixture.closesAt != nil)
    }

    @Test func decodesARevealedFixtureAndFoldsDuplicateRows() throws {
        let json = """
        {"season":"2026","fixtures":[
          {"event":"401","team":"WAS","week":12,"revealed":true,"submissions":100,
           "picks":[{"playerId":"p1","slot":1,"count":30},
                    {"playerId":"p1","slot":1,"count":10},
                    {"playerId":"p2","slot":2,"count":0}]}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PredictCommunityResponse.self, from: json)
        let fixture = try #require(decoded.fixtures?.first).domain()
        #expect(fixture.counts[.init(playerID: "p1", slot: 1)] == 40)
        // A zero-count row carries no information and shouldn't create an entry.
        #expect(fixture.counts[.init(playerID: "p2", slot: 2)] == nil)
    }

    /// Decode-defensively: a payload missing optional fields must still produce a usable (sealed)
    /// value rather than throwing and taking the whole screen down.
    @Test func decodesAMinimalPayloadWithoutThrowing() throws {
        let json = """
        {"fixtures":[{"event":"401","team":"WAS"}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PredictCommunityResponse.self, from: json)
        let fixture = try #require(decoded.fixtures?.first).domain()
        #expect(fixture.revealed == false)
        #expect(fixture.submissions == 0)
    }

    @Test func unavailableRendersLikeSealed() {
        let c = PredictCommunity.unavailable(eventID: "e1", team: "WAS", week: 12)
        #expect(c.revealed == false)
        #expect(c.share(forPlayer: "anyone") == nil)
        #expect(c.consensusXI(slots: [0]).isEmpty)
    }

    // MARK: - Phase.resolve (cross-device double-submit lock, Gap 2)

    private typealias Phase = PredictXIViewModel.PredictionItem.Phase

    @Test func resolveLocalSubmittedAlwaysWins() {
        let deadline = Date(timeIntervalSince1970: 1_000)
        // A local submit shows the real XI regardless of a stray server mark or the clock.
        #expect(Phase.resolve(hasLocalSubmitted: true, submittedElsewhere: true,
                              now: deadline.addingTimeInterval(-10), deadline: deadline) == .submitted)
        #expect(Phase.resolve(hasLocalSubmitted: true, submittedElsewhere: false,
                              now: deadline.addingTimeInterval(10), deadline: deadline) == .submitted)
    }

    @Test func resolveSubmittedElsewhereLocksEvenInsideTheDeadlineWindow() {
        let deadline = Date(timeIntervalSince1970: 1_000)
        // Predicted on another device, still before the deadline → locked, not open.
        #expect(Phase.resolve(hasLocalSubmitted: false, submittedElsewhere: true,
                              now: deadline.addingTimeInterval(-10), deadline: deadline) == .submittedElsewhere)
        // …and still locked (not "closed"/"you missed it") after the deadline — the user DID submit.
        #expect(Phase.resolve(hasLocalSubmitted: false, submittedElsewhere: true,
                              now: deadline.addingTimeInterval(10), deadline: deadline) == .submittedElsewhere)
    }

    @Test func resolveOpenBeforeDeadlineThenClosedAfterWhenNeverSubmitted() {
        let deadline = Date(timeIntervalSince1970: 1_000)
        #expect(Phase.resolve(hasLocalSubmitted: false, submittedElsewhere: false,
                              now: deadline.addingTimeInterval(-10), deadline: deadline) == .open)
        #expect(Phase.resolve(hasLocalSubmitted: false, submittedElsewhere: false,
                              now: deadline.addingTimeInterval(10), deadline: deadline) == .closed)
    }
}
