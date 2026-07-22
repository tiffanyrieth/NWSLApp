//
//  FanZoneCadence.swift
//  NWSLApp
//
//  The ONE place the Fan Zone's calendar lives: which game owns this week's quiz slot, which round
//  number we're on, and when a round opens/closes.
//
//  Why it exists: the quiz slot ALTERNATES. Know Her Game runs season weeks 1, 3, 5…, NWSL Trivia runs
//  2, 4, 6… — so only one community-stats game drops content in a given week and neither competes with
//  the other for attention. That parity rule is also committed server-side (the proxy's
//  `assemble_knowher_prompt.mjs` SEASON_ANCHOR + `isKnowHerWeek`), and the two MUST agree: if the app
//  thinks it's a Trivia week and the content pipeline thinks it's a KHG week, a fan opens a game with no
//  content. `FanZoneCadenceTests` locks the app side against the proxy's committed anchor.
//
//  Everything here is PURE and date-injectable (no `Date()` defaults captured at call sites we can't
//  control), so round rollover is testable without waiting two weeks.
//
//  Terminology (owner): a ROUND is one edition of a game — two weeks long, numbered from 1 each season.
//  For Predict the XI a round is instead the SOCCER WEEK (see `soccerWeek`), because its content is the
//  fixture list, not a generated pool: a club playing twice in one week has both matches in that round.
//

import Foundation

enum FanZoneCadence {

    /// The Monday of regular-season Week 1 — the cadence anchor, shared with the proxy's committed
    /// `SEASON_ANCHOR`. The 2026 season opened Fri 2026-03-13, so Week 1 is the week of Mon 2026-03-09.
    /// ⚠️ Bump this each new season, IN LOCK-STEP with `scripts/assemble_knowher_prompt.mjs` in the proxy
    /// repo — they are two halves of one contract (see `FanZoneCadenceTests.anchorMatchesProxy`).
    static let seasonAnchor = "2026-03-09"

    /// Which game owns a given week's quiz slot.
    enum QuizSlot: Equatable {
        case knowHerGame   // even week-offsets from the anchor (season weeks 1, 3, 5…)
        case trivia        // odd  week-offsets (season weeks 2, 4, 6…)
    }

    // MARK: - Week math (UTC, Monday-start — matches the proxy exactly)

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// UTC midnight on the Monday that opens `date`'s week. The single source for all week math —
    /// `mondayOrdinal` and `weekStart` both derive from it, so they can't disagree.
    private static func mondayStart(_ date: Date) -> Date {
        let cal = utcCalendar
        let start = cal.startOfDay(for: date)
        // Monday=1 … Sunday=7, derived rather than read from `firstWeekday` (which is locale-dependent
        // and would otherwise shift every round boundary for non-Monday-first users).
        let weekday = cal.component(.weekday, from: start)          // Sun=1 … Sat=7
        let mondayBased = weekday == 1 ? 7 : weekday - 1
        return cal.date(byAdding: .day, value: -(mondayBased - 1), to: start) ?? start
    }

    /// Monotonic count of weeks since the epoch for `date`'s week — a comparable week ordinal, matching
    /// the proxy's `mondayOrdinal`. ⚠️ Only ever compare/subtract these: the Unix epoch was a THURSDAY,
    /// so multiplying an ordinal back into a Date lands 3 days off. Use `weekStart` for an actual date.
    static func mondayOrdinal(_ date: Date) -> Int {
        Int((mondayStart(date).timeIntervalSince1970 / (7 * 86_400)).rounded(.down))
    }

    /// The anchor as a Date (UTC midnight). Non-optional by construction — `seasonAnchor` is a literal
    /// we control — but parsed rather than force-unwrapped so a bad edit degrades instead of crashing.
    static var anchorDate: Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: seasonAnchor) ?? Date(timeIntervalSince1970: 0)
    }

    /// Whole weeks since the season anchor (negative before the season opens).
    static func weekOffset(for date: Date) -> Int {
        mondayOrdinal(date) - mondayOrdinal(anchorDate)
    }

    // MARK: - The quiz slot

    /// The season year the anchor belongs to — the year component of every round edition key. A round
    /// that spills past New Year keeps its season's year ("2026-R26" in January), the same season-
    /// scoping rule KHG's seasonPoints uses.
    static var seasonYear: Int { Int(seasonAnchor.prefix(4)) ?? 2026 }

    /// Which game DROPS a new round in `date`'s week. Even offsets = Know Her Game (Week 1 is KHG),
    /// odd = Trivia.
    ///
    /// ⚠️ This is the *drop* week, NOT "the only live game". Rounds are two weeks long and staggered by
    /// one, so both games are almost always playable: in a Trivia-drop week, KHG's round is in its
    /// second week. Use `roundNumber` to ask what's live for a game; use this only to ask what's NEW.
    static func quizSlot(for date: Date) -> QuizSlot {
        // Swift's % keeps the sign of the dividend, so a negative offset needs normalising before the
        // parity test — otherwise preseason weeks alternate the wrong way round.
        let offset = weekOffset(for: date)
        return offset %% 2 == 0 ? .knowHerGame : .trivia
    }

    /// The week offset in which `slot`'s currently-live round OPENED — this week if the game drops this
    /// week, otherwise last week (its round's second week). Negative ⇒ that game hasn't started yet.
    private static func openOffset(for slot: QuizSlot, at date: Date) -> Int {
        let offset = weekOffset(for: date)
        return quizSlot(for: date) == slot ? offset : offset - 1
    }

    /// The 1-based ROUND number currently live for `slot`, or nil before that game's first round opens.
    /// Each game numbers its OWN editions: KHG drops in weeks 0,2,4… (its rounds 1,2,3…), Trivia in
    /// weeks 1,3,5… — so in season week 1 (offset 0) KHG is on round 1 and Trivia has not started yet.
    static func roundNumber(for slot: QuizSlot, at date: Date) -> Int? {
        let open = openOffset(for: slot, at: date)
        guard open >= 0 else { return nil }
        return open / 2 + 1
    }

    /// True when `slot` drops a NEW round in `date`'s week (the "fresh content" signal for Home's unseen
    /// dot and the landing page's round eyebrow).
    static func isDropWeek(for slot: QuizSlot, at date: Date) -> Bool {
        weekOffset(for: date) >= 0 && quizSlot(for: date) == slot
    }

    // MARK: - Round windows

    /// The Monday (UTC) that opens `date`'s week.
    static func weekStart(for date: Date) -> Date { mondayStart(date) }

    /// The Monday that opened `slot`'s currently-live round. A date in the round's SECOND week resolves
    /// back to the round's first Monday — otherwise "closes in N days" would reset halfway through.
    static func roundStart(for slot: QuizSlot, at date: Date) -> Date {
        let start = mondayStart(date)
        return quizSlot(for: date) == slot ? start : start.addingTimeInterval(-7 * 86_400)
    }

    /// When `slot`'s live round closes — two weeks after it opened. Drives "closes in N days".
    static func roundCloses(for slot: QuizSlot, at date: Date) -> Date {
        roundStart(for: slot, at: date).addingTimeInterval(14 * 86_400)
    }

    /// A stable per-round edition key for `quiz_answers` / community results — e.g. `"2026-R08"`.
    /// Distinct from KHG's own key (which is `{weekKey}-{team}-{athleteId}`, one per featured player);
    /// Trivia has a single slate per round so the round key IS its edition key.
    static func editionKey(round: Int, seasonYear: Int) -> String {
        "\(seasonYear)-R\(String(format: "%02d", round))"
    }

    /// Are two of a game's rounds adjacent? Used for streaks and for "keep only the previous round".
    /// Trivially `current == previous + 1` — round numbers already absorb the two-week spacing, which is
    /// why generalising KHG's ISO-week-gap arithmetic into round numbers is worth doing.
    static func isConsecutiveRound(previous: Int, current: Int) -> Bool {
        current == previous + 1
    }

    // MARK: - Predict the XI — the soccer week

    /// The 1-based SOCCER WEEK for a kickoff date (Week 1 = the anchor week, i.e. the week containing
    /// the season opener — Fri 2026-03-13 for 2026). Predict's round is the week, not a two-week
    /// edition: a club playing Wednesday AND Saturday has both fixtures scored into the same round.
    /// nil before the season opens.
    ///
    /// ⚠️ This is a CALENDAR-derived week, deliberately, even though the concept is a soccer matchweek.
    /// It is the leaderboard's primary key, so it must be stable: a fixture that gets postponed or
    /// rescheduled would RENUMBER every later week under a "count only weeks that have fixtures" scheme,
    /// silently corrupting already-banked round scores. A calendar grid can't be renumbered by a
    /// schedule change — a break week simply has no rows, which is harmless. Derive the DISPLAY label
    /// from fixtures if it ever needs to match the league's official matchweek numbering.
    static func soccerWeek(for kickoff: Date) -> Int? {
        let offset = weekOffset(for: kickoff)
        return offset >= 0 ? offset + 1 : nil
    }
}

// Modulo that always returns a non-negative result, unlike Swift's `%` (which keeps the dividend's
// sign). Needed for parity on preseason (negative) week offsets.
infix operator %%: MultiplicationPrecedence
private func %% (lhs: Int, rhs: Int) -> Int {
    let r = lhs % rhs
    return r < 0 ? r + abs(rhs) : r
}
