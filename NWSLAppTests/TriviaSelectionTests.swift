//
//  TriviaSelectionTests.swift
//  NWSLAppTests
//
//  Covers the pure daily-question selection (TriviaViewModel.dailySelection): the
//  deterministic, NON-REPEATING slice that backs Daily Trivia's "5 per day". The
//  live pool (proxy `/trivia`) can be any size, so the selection must be stable
//  per day, independent of the backend's ordering, and walk the WHOLE pool before
//  any question repeats (the point of a large live pool).
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

    @Test func sameDayIsDeterministic() {
        let p = pool(40)
        let a = TriviaViewModel.dailySelection(from: p, dayNumber: 123, count: 5)
        let b = TriviaViewModel.dailySelection(from: p, dayNumber: 123, count: 5)
        #expect(a.map(\.id) == b.map(\.id))
        #expect(a.count == 5)
    }

    @Test func differentDaysDiffer() {
        let p = pool(40)
        let day1 = TriviaViewModel.dailySelection(from: p, dayNumber: 1, count: 5).map(\.id)
        let day2 = TriviaViewModel.dailySelection(from: p, dayNumber: 2, count: 5).map(\.id)
        #expect(day1 != day2)
    }

    /// The pool is sorted by id before slicing, so however the backend orders the
    /// array, a given day yields the same 5.
    @Test func inputOrderDoesNotMatter() {
        let p = pool(40)
        let reordered = p.reversed().map { $0 }
        let a = TriviaViewModel.dailySelection(from: p, dayNumber: 7, count: 5).map(\.id)
        let b = TriviaViewModel.dailySelection(from: reordered, dayNumber: 7, count: 5).map(\.id)
        #expect(a == b)
    }

    // MARK: - Non-repeating coverage

    @Test func eachDaysFiveAreUnique() {
        let p = pool(40)
        for day in 0..<8 {
            let ids = TriviaViewModel.dailySelection(from: p, dayNumber: day, count: 5).map(\.id)
            #expect(Set(ids).count == 5)
        }
    }

    /// 40 questions / 5 per day = 8 disjoint days that cover the whole pool exactly
    /// once; day 8 wraps back to day 0's block.
    @Test func wholePoolPlaysBeforeRepeat() {
        let p = pool(40)
        var seen = Set<String>()
        for day in 0..<8 {
            seen.formUnion(TriviaViewModel.dailySelection(from: p, dayNumber: day, count: 5).map(\.id))
        }
        #expect(seen.count == 40)

        let day0 = TriviaViewModel.dailySelection(from: p, dayNumber: 0, count: 5).map(\.id)
        let day8 = TriviaViewModel.dailySelection(from: p, dayNumber: 8, count: 5).map(\.id)
        #expect(day0 == day8)
    }

    // MARK: - Edge cases

    @Test func negativeDayNumberStaysInBounds() {
        // Pre-2001 dates produce negative day numbers; the slice must not crash or
        // go out of range.
        let p = pool(40)
        let ids = TriviaViewModel.dailySelection(from: p, dayNumber: -3, count: 5).map(\.id)
        #expect(ids.count == 5)
        #expect(Set(ids).count == 5)
    }

    @Test func poolSmallerThanDailyCountReturnsWholePool() {
        let p = pool(3)
        let picked = TriviaViewModel.dailySelection(from: p, dayNumber: 5, count: 5)
        #expect(picked.count == 3)
        #expect(Set(picked.map(\.id)).count == 3)
    }

    @Test func emptyPoolReturnsEmpty() {
        #expect(TriviaViewModel.dailySelection(from: [], dayNumber: 1, count: 5).isEmpty)
    }
}
