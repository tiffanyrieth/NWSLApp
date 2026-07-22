//
//  FanZoneCadenceTests.swift
//  NWSLAppTests
//
//  The Fan Zone calendar: quiz-slot alternation (KHG ↔ Trivia), round numbering, round windows, and
//  Predict's soccer week. Pure + date-injected, so two-week rollovers are testable instantly.
//
//  ⚠️ `anchorMatchesTheProxysCommittedAnchor` is a CONTRACT test. The same anchor is committed in the
//  proxy repo (`scripts/assemble_knowher_prompt.mjs` SEASON_ANCHOR) and drives which week the content
//  routine generates for. If the two drift, a fan opens a game whose content was never generated.
//

import Foundation
import Testing
@testable import NWSLApp

struct FanZoneCadenceTests {

    /// A UTC date, so tests never depend on the machine's timezone.
    private func utc(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)!
    }

    // MARK: - The cross-repo contract

    @Test func anchorMatchesTheProxysCommittedAnchor() {
        // Must equal SEASON_ANCHOR in nwslapp-proxy/scripts/assemble_knowher_prompt.mjs. Bump BOTH each
        // season — the app decides what to show, the proxy decides what to generate.
        #expect(FanZoneCadence.seasonAnchor == "2026-03-09")
    }

    @Test func anchorWeekIsKnowHerRoundOne() {
        // Week 1 = Know Her Game (owner's cadence: KHG opens the season). Trivia's first round doesn't
        // open until week 2, so it has no live round yet.
        let monday = utc("2026-03-09")
        #expect(FanZoneCadence.quizSlot(for: monday) == .knowHerGame)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: monday) == 1)
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: monday) == nil)
    }

    // MARK: - Overlapping rounds (a round runs 2 weeks; drops are staggered 1 week apart)

    @Test func bothGamesAreLiveOnceTheStaggerIsEstablished() {
        // Owner's cadence: "week 1 KHG goes on for 2 weeks before closing, week 2 Trivia closes in 2
        // weeks". So in week 2 KHG is in its SECOND week while Trivia's round 1 is brand new — both
        // playable. A model where only the drop-week game is live would blank one game every week.
        let week2 = utc("2026-03-16")
        #expect(FanZoneCadence.quizSlot(for: week2) == .trivia)          // Trivia is what's NEW
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: week2) == 1)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: week2) == 1) // KHG still live
        #expect(FanZoneCadence.isDropWeek(for: .trivia, at: week2))
        #expect(!FanZoneCadence.isDropWeek(for: .knowHerGame, at: week2))
    }

    @Test func aRoundStaysOnTheSameNumberThroughItsSecondWeek() {
        // KHG round 1 spans weeks 1–2; round 2 opens week 3.
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: utc("2026-03-09")) == 1)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: utc("2026-03-16")) == 1)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: utc("2026-03-23")) == 2)
        // Trivia round 1 spans weeks 2–3; round 2 opens week 4.
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: utc("2026-03-16")) == 1)
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: utc("2026-03-23")) == 1)
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: utc("2026-03-30")) == 2)
    }

    // MARK: - Alternation

    @Test func slotsAlternateEveryWeek() {
        let expected: [FanZoneCadence.QuizSlot] = [
            .knowHerGame, .trivia, .knowHerGame, .trivia, .knowHerGame, .trivia,
        ]
        for (i, slot) in expected.enumerated() {
            let d = utc("2026-03-09").addingTimeInterval(Double(i) * 7 * 86_400)
            #expect(FanZoneCadence.quizSlot(for: d) == slot, "week \(i) should be \(slot)")
        }
    }

    @Test func eachGameNumbersItsOwnRoundsOnItsOwnDropWeeks() {
        // KHG drops weeks 0,2,4 → rounds 1,2,3.  Trivia drops weeks 1,3,5 → rounds 1,2,3.
        let anchor = utc("2026-03-09")
        func week(_ n: Int) -> Date { anchor.addingTimeInterval(Double(n) * 7 * 86_400) }

        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: week(0)) == 1)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: week(2)) == 2)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: week(4)) == 3)

        #expect(FanZoneCadence.roundNumber(for: .trivia, at: week(1)) == 1)
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: week(3)) == 2)
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: week(5)) == 3)
    }

    @Test func aRoundCoversItsWholeWeekRegardlessOfDay() {
        // Any day Mon–Sun of a KHG week resolves to the same round — a Sunday player must not see the
        // next round appear early.
        for day in ["2026-03-09", "2026-03-11", "2026-03-15"] {
            #expect(FanZoneCadence.quizSlot(for: utc(day)) == .knowHerGame)
            #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: utc(day)) == 1)
        }
    }

    @Test func preseasonHasNoRoundNumber() {
        let before = utc("2026-03-02")   // the week before the anchor
        #expect(FanZoneCadence.weekOffset(for: before) == -1)
        #expect(FanZoneCadence.roundNumber(for: .knowHerGame, at: before) == nil)
        #expect(FanZoneCadence.roundNumber(for: .trivia, at: before) == nil)
    }

    @Test func preseasonParityDoesNotFlipOnNegativeOffsets() {
        // Swift's % keeps the dividend's sign, so -1 % 2 == -1: a naive `== 0` test would call the week
        // BEFORE the anchor a KHG week and shift the whole alternation. Guards the %% normalisation.
        #expect(FanZoneCadence.quizSlot(for: utc("2026-03-02")) == .trivia)      // offset -1
        #expect(FanZoneCadence.quizSlot(for: utc("2026-02-23")) == .knowHerGame) // offset -2
    }

    // MARK: - Round windows

    @Test func weekStartResolvesToTheMonday() {
        // Regression: the Unix epoch was a THURSDAY, so rebuilding a date from `ordinal × 7 days` lands
        // 3 days off (this shipped as 2026-03-12). Week differences were unaffected, which is why only
        // the absolute-date path was wrong — and why the proxy's identical subtraction stays correct.
        #expect(FanZoneCadence.weekStart(for: utc("2026-03-11")) == utc("2026-03-09")) // mid-week
        #expect(FanZoneCadence.weekStart(for: utc("2026-03-15")) == utc("2026-03-09")) // Sunday
        #expect(FanZoneCadence.weekStart(for: utc("2026-03-09")) == utc("2026-03-09")) // the Monday
    }

    @Test func aRoundRunsTwoWeeksFromItsOwnOpeningMonday() {
        // KHG round 1 opened 03-09 and closes 03-23 — asked mid-round (its second week), the close date
        // must NOT slide forward a week.
        #expect(FanZoneCadence.roundStart(for: .knowHerGame, at: utc("2026-03-11")) == utc("2026-03-09"))
        #expect(FanZoneCadence.roundCloses(for: .knowHerGame, at: utc("2026-03-11")) == utc("2026-03-23"))
        #expect(FanZoneCadence.roundStart(for: .knowHerGame, at: utc("2026-03-18")) == utc("2026-03-09"))
        #expect(FanZoneCadence.roundCloses(for: .knowHerGame, at: utc("2026-03-18")) == utc("2026-03-23"))
        // Trivia's round 1 opened a week later and closes a week later.
        #expect(FanZoneCadence.roundStart(for: .trivia, at: utc("2026-03-18")) == utc("2026-03-16"))
        #expect(FanZoneCadence.roundCloses(for: .trivia, at: utc("2026-03-18")) == utc("2026-03-30"))
    }

    @Test func editionKeyIsStableAndSortable() {
        #expect(FanZoneCadence.editionKey(round: 8, seasonYear: 2026) == "2026-R08")
        #expect(FanZoneCadence.editionKey(round: 12, seasonYear: 2026) == "2026-R12")
        // Zero-padding keeps lexical order == numeric order (matters for any key-range prune).
        #expect(FanZoneCadence.editionKey(round: 2, seasonYear: 2026)
                < FanZoneCadence.editionKey(round: 10, seasonYear: 2026))
    }

    @Test func consecutiveRoundsAreAdjacentNumbers() {
        #expect(FanZoneCadence.isConsecutiveRound(previous: 3, current: 4))
        #expect(!FanZoneCadence.isConsecutiveRound(previous: 3, current: 5))  // missed a round
        #expect(!FanZoneCadence.isConsecutiveRound(previous: 3, current: 3))  // same round
    }

    // MARK: - Predict's soccer week

    @Test func soccerWeekCountsFromTheSeasonOpenersWeek() {
        // The 2026 season opened Fri 2026-03-13, so that whole week is Week 1 — the opener itself and
        // the Monday that starts its week must agree.
        #expect(FanZoneCadence.soccerWeek(for: utc("2026-03-13")) == 1)  // opening night
        #expect(FanZoneCadence.soccerWeek(for: utc("2026-03-09")) == 1)  // its Monday
        #expect(FanZoneCadence.soccerWeek(for: utc("2026-03-16")) == 2)
        #expect(FanZoneCadence.soccerWeek(for: utc("2026-06-01")) == 13)
        #expect(FanZoneCadence.soccerWeek(for: utc("2026-03-02")) == nil)  // preseason
    }

    @Test func twoFixturesInOneWeekShareARound() {
        // The owner's case: a club playing Wednesday AND Saturday scores both into one weekly round.
        let wednesday = utc("2026-03-18")
        let saturday = utc("2026-03-21")
        #expect(FanZoneCadence.soccerWeek(for: wednesday) == FanZoneCadence.soccerWeek(for: saturday))
    }
}
