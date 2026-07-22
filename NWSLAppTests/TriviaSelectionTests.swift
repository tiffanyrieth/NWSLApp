//
//  TriviaSelectionTests.swift
//  NWSLAppTests
//
//  Covers the pure per-round question selection (TriviaViewModel.roundSelection): the
//  deterministic, NON-REPEATING slice that backs NWSL Trivia's "10 per biweekly round".
//  The live pool (proxy `/trivia`) can be any size, so the selection must be stable per
//  round, independent of the backend's ordering, and walk the WHOLE pool before any
//  question repeats — determinism is also what makes past-round REVIEW work with no
//  stored questions (round N always recomputes the same slate).
//

import Foundation
import Testing
@testable import NWSLApp

struct TriviaSelectionTests {

    /// A synthetic pool of `n` questions with ids q001…qNNN.
    private func pool(_ n: Int) -> [TriviaQuestion] {
        (1...n).map { i in
            TriviaQuestion(
                id: String(format: "q%03d", i),
                question: "Question \(i)?",
                options: ["a", "b", "c", "d"],
                correctIndex: i % 4,
                category: .leagueHistory,
                difficulty: .easy
            )
        }
    }

    // MARK: - Determinism

    @Test func sameRoundIsDeterministic() {
        let p = pool(40)
        let a = TriviaViewModel.roundSelection(from: p, roundNumber: 12, count: 10)
        let b = TriviaViewModel.roundSelection(from: p, roundNumber: 12, count: 10)
        #expect(a.map(\.id) == b.map(\.id))
        #expect(a.count == 10)
    }

    @Test func differentRoundsDiffer() {
        let p = pool(40)
        let r1 = TriviaViewModel.roundSelection(from: p, roundNumber: 1, count: 10).map(\.id)
        let r2 = TriviaViewModel.roundSelection(from: p, roundNumber: 2, count: 10).map(\.id)
        #expect(r1 != r2)
    }

    /// The pool is sorted by id before slicing, so however the backend orders the
    /// array, a given round yields the same 10.
    @Test func inputOrderDoesNotMatter() {
        let p = pool(40)
        let reordered = p.reversed().map { $0 }
        let a = TriviaViewModel.roundSelection(from: p, roundNumber: 3, count: 10).map(\.id)
        let b = TriviaViewModel.roundSelection(from: reordered, roundNumber: 3, count: 10).map(\.id)
        #expect(a == b)
    }

    // MARK: - Non-repeating coverage

    @Test func eachRoundsTenAreUnique() {
        let p = pool(40)
        for round in 1...5 {
            let ids = TriviaViewModel.roundSelection(from: p, roundNumber: round, count: 10).map(\.id)
            #expect(Set(ids).count == 10)
        }
    }

    /// 40 questions / 10 per round = 4 disjoint rounds that cover the whole pool exactly
    /// once; round 5 wraps back to round 1's block — the honest interim behavior until the
    /// content pipeline stocks the 530-question pool (53 rounds, zero repeats).
    @Test func wholePoolPlaysBeforeRepeat() {
        let p = pool(40)
        var seen = Set<String>()
        for round in 1...4 {
            seen.formUnion(TriviaViewModel.roundSelection(from: p, roundNumber: round, count: 10).map(\.id))
        }
        #expect(seen.count == 40)

        let r1 = TriviaViewModel.roundSelection(from: p, roundNumber: 1, count: 10).map(\.id)
        let r5 = TriviaViewModel.roundSelection(from: p, roundNumber: 5, count: 10).map(\.id)
        #expect(r1 == r5)
    }

    /// Rounds are 1-based (round 1 = the first block). Locks the −1 offset so a refactor
    /// can't silently shift every round's slate by one block.
    @Test func roundOneTakesTheFirstBlock() {
        let p = pool(40)
        let r1 = Set(TriviaViewModel.roundSelection(from: p, roundNumber: 1, count: 10).map(\.id))
        var firstBlock = Set<String>()
        for round in 1...4 {
            firstBlock.formUnion(TriviaViewModel.roundSelection(from: p, roundNumber: round, count: 10).map(\.id))
            if round == 1 { #expect(firstBlock == r1) }
        }
    }

    // MARK: - Edge cases

    @Test func defensiveRoundNumbersStayInBounds() {
        // Round 0 / negative can't occur from the cadence, but a bad caller must not crash.
        let p = pool(40)
        for bad in [0, -3] {
            let ids = TriviaViewModel.roundSelection(from: p, roundNumber: bad, count: 10).map(\.id)
            #expect(ids.count == 10)
            #expect(Set(ids).count == 10)
        }
    }

    @Test func poolSmallerThanRoundCountReturnsWholePool() {
        let p = pool(3)
        let picked = TriviaViewModel.roundSelection(from: p, roundNumber: 5, count: 10)
        #expect(picked.count == 3)
        #expect(Set(picked.map(\.id)).count == 3)
    }

    @Test func emptyPoolReturnsEmpty() {
        #expect(TriviaViewModel.roundSelection(from: [], roundNumber: 1, count: 10).isEmpty)
    }
}
