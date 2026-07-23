//
//  ClubOrderRotationTests.swift
//  NWSLAppTests
//
//  Equal representation has TWO halves. The slot allowance (ContentRoundRobinTests) guarantees each
//  followed club the same NUMBER of cards. This file guards the other half: which club is seen
//  FIRST. The club order was `.sorted()` by abbreviation, so following LA + ORL + WAS put Angel City
//  first, Pride second, Spirit third — on every launch and every pull-to-refresh, permanently. A
//  quiet club could hold its slot count and still always be the one you had to scroll to find.
//

import Testing
@testable import NWSLApp

struct ClubOrderRotationTests {

    private let clubs = ["LA", "ORL", "WAS"]   // ACFC, Pride, Spirit — the owner's own follow set

    @Test func rotationIsTotalAndOrderPreserving() {
        // Offset 0 is the plain sorted order; each step advances the leader by one, wrapping.
        #expect(HomeViewModel.rotated(clubs, by: 0) == ["LA", "ORL", "WAS"])
        #expect(HomeViewModel.rotated(clubs, by: 1) == ["ORL", "WAS", "LA"])
        #expect(HomeViewModel.rotated(clubs, by: 2) == ["WAS", "LA", "ORL"])
        #expect(HomeViewModel.rotated(clubs, by: 3) == ["LA", "ORL", "WAS"])   // wraps cleanly
    }

    @Test func rotationSurvivesDegenerateInput() {
        // Called from `body` with whatever the user follows — it must never trap.
        #expect(HomeViewModel.rotated([], by: 7).isEmpty)
        #expect(HomeViewModel.rotated(["LA"], by: 7) == ["LA"])
        #expect(HomeViewModel.rotated(clubs, by: 1_000_000).count == 3)
        #expect(HomeViewModel.rotated(clubs, by: -1) == ["WAS", "LA", "ORL"])  // no negative-modulo crash
    }

    /// THE REGRESSION: over one full cycle every followed club leads exactly once. This is what
    /// makes it "no club is favoured" rather than merely "not always alphabetical" — a shuffle
    /// could satisfy the latter while still repeating a leader.
    @Test func everyClubLeadsExactlyOncePerCycle() {
        let leaders = (0..<clubs.count).map { HomeViewModel.rotated(clubs, by: $0).first! }
        #expect(Set(leaders) == Set(clubs))
        #expect(leaders.count == clubs.count)
    }

    /// Rotation reorders the clubs; it never adds, drops, or duplicates one — so the round-robin's
    /// per-club slot allowance downstream is untouched.
    @Test func rotationIsAPermutation() {
        for offset in 0..<12 {
            #expect(Set(HomeViewModel.rotated(clubs, by: offset)) == Set(clubs))
            #expect(HomeViewModel.rotated(clubs, by: offset).count == clubs.count)
        }
    }
}
