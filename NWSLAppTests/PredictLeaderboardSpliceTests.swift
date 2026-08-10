//
//  PredictLeaderboardSpliceTests.swift
//  NWSLAppTests
//
//  The board-assembly splice (PredictXIViewModel.rankedRows, extracted pure 2026-08-10 for exactly
//  these tests). The bug this file pins: after a reinstall the user's rank query was skipped
//  (gated on empty local state), the anti-double-row filter removed her REAL server row, and no
//  replacement was spliced — she vanished from her own leaderboard while every other fan still saw
//  her ranked. The rule now: NEVER drop the user's fetched row without a replacement.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictLeaderboardSpliceTests {
    private typealias Standing = PredictLeaderboardService.Standing

    private let me = "B7E7C1F2-0000-0000-0000-000000000000"   // UPPERCASE, as UUID.uuidString yields
    private var meLower: String { me.lowercased() }           // as PostgREST returns it

    private func board(_ rows: [(id: String, name: String, avg: Double)]) -> [Standing] {
        rows.enumerated().map { i, r in
            Standing(userID: r.id, name: r.name, points: 100 - i * 10, matches: 5, avg: r.avg)
        }
    }

    /// The reinstall case: empty local state, but a true rank derived from the server row —
    /// the You row renders at that rank with the server-truth values passed by the caller.
    @Test func serverDerivedRankSplicesTheYouRowInline() {
        let standings = board([(meLower, "Tiff", 60.0), ("rival-1", "A", 55), ("rival-2", "B", 50)])
        let rows = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: 1, myID: me, myName: "Tiff",
            points: 300, seasonAvg: 60, seasonMatches: 5)

        #expect(rows.first?.isYou == true)
        #expect(rows.first?.rank == 1)
        #expect(rows.first?.points == 300)
        // The anti-double-row guard: my server row must not ALSO appear as a rival.
        #expect(rows.filter(\.isYou).count == 1)
        #expect(rows.count == 3)
    }

    /// ⚠️ THE REGRESSION GUARD. trueRank nil (rank query failed/skipped) while my real row is in
    /// the fetched standings: the row is kept in place and flagged mine — never silently dropped.
    @Test func rankQueryFailureNeverErasesMyFetchedRow() {
        let standings = board([("rival-1", "A", 70.0), (meLower, "Tiff", 60), ("rival-2", "B", 50)])
        let rows = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: nil, myID: me, myName: "Tiff",
            points: 0, seasonAvg: 0, seasonMatches: 0)

        let mine = rows.first(where: \.isYou)
        #expect(mine != nil)
        #expect(mine?.rank == 2)      // its fetched position
        #expect(mine?.points == 90)   // the SERVER row's values (local is empty — they're the honest display)
        #expect(rows.count == 3)      // rivals intact around it
    }

    /// A truly signed-out user (no id) still gets the plain rivals board, no You row.
    @Test func signedOutGetsRivalsOnly() {
        let standings = board([("rival-1", "A", 70.0), ("rival-2", "B", 50)])
        let rows = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: nil, myID: nil, myName: "You", points: 0)
        #expect(rows.allSatisfy { !$0.isYou })
        #expect(rows.count == 2)
    }

    /// A signed-in user with NO row anywhere (never played) also gets rivals only — the fallback
    /// splices only a row that genuinely exists.
    @Test func noRowAnywhereMeansNoYouRow() {
        let standings = board([("rival-1", "A", 70.0)])
        let rows = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: nil, myID: me, myName: "Tiff", points: 0)
        #expect(rows.allSatisfy { !$0.isYou })
    }

    /// The 2026-07-29 case-mismatch bug stays dead: an UPPERCASE UUID must match the lowercase
    /// PostgREST id both in the rivals filter and the fallback splice.
    @Test func uppercaseUUIDStillMatchesLowercaseServerRow() {
        let standings = board([(meLower, "Tiff", 60.0), ("rival-1", "A", 55)])
        let spliced = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: 1, myID: me, myName: "Tiff",
            points: 300, seasonAvg: 60, seasonMatches: 5)
        #expect(spliced.filter(\.isYou).count == 1)

        let fallback = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: nil, myID: me, myName: "Tiff", points: 0)
        #expect(fallback.filter(\.isYou).count == 1)
    }

    /// Below-fold users keep their honest real rank (regression: never a flattering ~101).
    @Test func belowFoldKeepsTheTrueRank() {
        let standings = board((1...5).map { ("rival-\($0)", "R\($0)", Double(100 - $0)) })
        let rows = PredictXIViewModel.rankedRows(
            standings: standings, trueRank: 412, myID: me, myName: "Tiff",
            points: 12, seasonAvg: 12, seasonMatches: 1)
        let mine = rows.last
        #expect(mine?.isYou == true)
        #expect(mine?.rank == 412)
        #expect(mine?.isBelowFold == true)
    }
}
