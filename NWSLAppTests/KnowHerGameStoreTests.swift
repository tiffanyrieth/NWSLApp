//
//  KnowHerGameStoreTests.swift
//  NWSLAppTests
//
//  Know Her Game store — the post-completion-flow additions: week-agnostic edition reads (so a
//  LAST-WEEK player reads the right edition, not the current week) and the one-week "Last week"
//  retention rule. Pure/local — no network (the pool fetch is exercised in the sim).
//

import Foundation
import Testing
@testable import NWSLApp

struct KnowHerGameStoreTests {

    private func store() -> KnowHerGameStore {
        // Isolated defaults per test so banked scores don't leak across cases / the real app.
        let suite = UserDefaults(suiteName: "knowher.tests.\(UUID().uuidString)")!
        return KnowHerGameStore(defaults: suite)
    }

    @Test func editionKeyReadsAreWeekAgnostic() {
        let s = store()
        // Bank a score under LAST week's edition key.
        s.recordCompletion(editionKey: "2026-W28-WAS-317423", weekKey: "2026-W28", correct: 6)

        // The raw edition read finds it regardless of the current week…
        #expect(s.score(editionKey: "2026-W28-WAS-317423") == 6)
        #expect(s.isPlayed(editionKey: "2026-W28-WAS-317423"))
        // …and a DIFFERENT edition (e.g. this week's) is untouched — the bug last-week reads would hit
        // if they keyed on the current week.
        #expect(s.score(editionKey: "2026-W29-WAS-317423") == nil)
        #expect(!s.isPlayed(editionKey: "2026-W29-WAS-317423"))
    }

    @Test func retainsPreviousWeekOnlyForTheExactlyPriorWeek() {
        // Kept: the immediately-prior ISO week becomes "last week".
        #expect(KnowHerGameStore.retainsPreviousWeek(old: "2026-W28", new: "2026-W29"))
        // Kept across the year boundary (W52 → W01).
        #expect(KnowHerGameStore.retainsPreviousWeek(old: "2025-W52", new: "2026-W01"))
        // Dropped: a 2-week gap (app not opened in a while) must NOT show as "last week".
        #expect(!KnowHerGameStore.retainsPreviousWeek(old: "2026-W27", new: "2026-W29"))
        // Dropped: same week (a reload, not a rotation).
        #expect(!KnowHerGameStore.retainsPreviousWeek(old: "2026-W29", new: "2026-W29"))
    }
}
