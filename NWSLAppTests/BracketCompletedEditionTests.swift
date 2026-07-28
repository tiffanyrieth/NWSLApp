//
//  BracketCompletedEditionTests.swift
//  NWSLAppTests
//
//  Pins the COMPLETED-edition contract (2026-07-28). When a bracket crowns a champion the proxy's
//  `finish()` sets `is_active = false`, stamps `completed_at`, and — critically — **nulls
//  `round_closes_at`**. The app keeps showing that edition through the between-editions review window
//  (the votes survive until the NEXT edition starts), so two things must hold at once:
//
//   1. it is VIEWABLE — the Home card and screen must not vanish the moment a winner is decided, and
//   2. it is NOT VOTABLE — with `roundClosesAt == nil` the deadline check (`if let closes …`) falls
//      through, so without an explicit `isComplete` test a finished bracket reads as OPEN.
//
//  (2) is the one that would silently let a vote land in a dead round, so it's tested from both the
//  phase resolution and the store-visibility side.
//

import Foundation
import Testing
@testable import NWSLApp

struct BracketCompletedEditionTests {

    // MARK: - Builders

    private func entrant(_ id: String) -> BracketEntrant {
        BracketEntrant(id: id, playerName: id.uppercased(), jerseyNumber: nil, teamAbbreviation: "WAS")
    }

    /// A 2-entrant edition whose FINAL is resolved — i.e. a crowned bracket.
    /// `complete` toggles only the completion flag so the two states differ by nothing else.
    private func edition(complete: Bool, closesAt: Date? = nil, winner: String? = "a0") -> BracketEdition {
        let final = BracketMatchup(
            id: "m0", round: .final, slot: 0,
            entrantA: entrant("a0"), entrantB: entrant("b0"),
            communityWinnerID: winner, splitAPercent: winner == nil ? nil : 71
        )
        return BracketEdition(
            id: "ed1", themeLabel: "TOP FORWARD", title: "Best Forward · 2026", emoji: "⚽",
            type: .statsSeeded, entrants: [entrant("a0"), entrant("b0")],
            currentRound: .final, roundOpenedAt: nil,
            // finish() nulls this — the whole trap in one line
            roundClosesAt: closesAt,
            fanCount: 42, matchups: [final],
            isComplete: complete
        )
    }

    private func freshStore() -> BracketStore {
        let d = UserDefaults(suiteName: "bracket-completed-tests-\(UUID().uuidString)")!
        return BracketStore(defaults: d)
    }

    // MARK: - Not votable

    /// `resolvePhase` with the two user-state flags off — the fresh-player path.
    private func phase(complete: Bool, closesAt: Date?) -> BracketViewModel.RoundPhase {
        BracketViewModel.resolvePhase(isComplete: complete, roundClosesAt: closesAt,
                                      now: Date(), hasScore: false, hasSubmitted: false)
    }

    @Test func aCompletedEditionIsClosedEvenThoughItHasNoCloseTime() {
        // The regression this guards: roundClosesAt == nil + no isComplete check ⇒ `.open`.
        #expect(phase(complete: true, closesAt: nil) == .closed)
    }

    @Test func anActiveEditionWithNoCloseTimeIsStillOpen() {
        // Manual mode legitimately has no close time — completion, not nil-ness, is what closes voting.
        #expect(phase(complete: false, closesAt: nil) == .open)
    }

    @Test func aFutureDeadlineOnALiveEditionStaysOpen() {
        #expect(phase(complete: false, closesAt: Date().addingTimeInterval(3600)) == .open)
    }

    @Test func aPassedDeadlineClosesALiveEdition() {
        #expect(phase(complete: false, closesAt: Date().addingTimeInterval(-60)) == .closed)
    }

    @Test func userStateStillWinsOverCompletion() {
        // A player who submitted and was scored sees their result, not a bare "closed".
        #expect(BracketViewModel.resolvePhase(isComplete: true, roundClosesAt: nil, now: Date(),
                                              hasScore: true, hasSubmitted: true) == .scored)
        #expect(BracketViewModel.resolvePhase(isComplete: true, roundClosesAt: nil, now: Date(),
                                              hasScore: false, hasSubmitted: true) == .submitted)
    }

    // MARK: - Still viewable

    @Test func aCompletedEditionKeepsTheHomeCardVisibleButNotPlayable() {
        let store = freshStore()
        store.adopt(summary: .init(id: "ed1", title: "Best Forward · 2026", currentRoundRaw: 2,
                                   roundClosesAt: nil, isActive: false, themeLabel: "TOP FORWARD",
                                   poolSize: 2, isComplete: true))
        #expect(store.hasViewableEdition)          // card stays — the champion is reachable
        #expect(!store.hasActiveEdition)           // …but nothing is open for voting
    }

    @Test func noEditionAtAllHidesTheCard() {
        let store = freshStore()
        store.adopt(summary: .init(id: "ed1", title: "t", currentRoundRaw: 2, roundClosesAt: nil,
                                   isActive: true, themeLabel: nil, poolSize: 2, isComplete: false))
        store.clearActiveEdition()
        #expect(!store.hasViewableEdition)
        #expect(!store.hasActiveEdition)
    }

    @Test func aSummaryCachedBeforeTheFlagExistedStillDecodesAsNotComplete() {
        // isComplete is optional precisely so pre-upgrade cached summaries keep working.
        let store = freshStore()
        store.adopt(summary: .init(id: "ed1", title: "t", currentRoundRaw: 2, roundClosesAt: nil,
                                   isActive: true, themeLabel: nil, poolSize: 2, isComplete: nil))
        #expect(store.hasActiveEdition)
        #expect(store.hasViewableEdition)
    }

    // MARK: - Champion

    @Test func championIsTheResolvedFinalWinner() {
        #expect(edition(complete: true).champion?.id == "a0")
    }

    @Test func championIsNilWhenTheFinalNeverResolved() {
        // Closed before a champion — the UI must say so honestly, never invent one.
        #expect(edition(complete: true, winner: nil).champion == nil)
    }
}
