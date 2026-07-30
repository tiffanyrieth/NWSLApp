//
//  SuspendedMatchTests.swift
//  NWSLAppTests
//
//  ⚠️ REGRESSION GUARD for a live-game data-loss bug (2026-07-29, UTA v WAS suspended for lightning
//  at 27'). ESPN moves a suspended match to `state == "post"` while setting `completed == false` and
//  `name == "STATUS_SUSPENDED"`. The app only read `state`, so it:
//    • displayed "FULL TIME 0–0" during the first half,
//    • stopped polling the match detail (temporalState == .past), so it could never recover, and
//    • SCORED the user's Predict entry against that fake final — then never revisited it, because a
//      scored fixture leaves `submittedAwaitingScore` permanently.
//
//  The real payloads, captured live that night:
//    finished   → state=post  completed=true   name=STATUS_FULL_TIME
//    suspended  → state=post  completed=false  name=STATUS_SUSPENDED
//

import Foundation
import Testing
@testable import NWSLApp

struct SuspendedMatchTests {

    private func event(state: String, completed: Bool? = nil, name: String? = nil,
                       home: Int? = nil, away: Int? = nil,
                       kickoff: String = "2026-07-30T01:00Z") -> Event {
        Event(id: "1", date: kickoff,
              status: EventStatus(type: StatusType(state: state, completed: completed, name: name)),
              competitions: [Competition(competitors: [
                  Competitor(homeAway: "home", score: home.map(String.init), team: Team(abbreviation: "UTA")),
                  Competitor(homeAway: "away", score: away.map(String.init), team: Team(abbreviation: "WAS")),
              ])],
              season: EventSeason(year: 2026, slug: "regular-season"))
    }

    // MARK: - The discriminator

    @Test func fullTimeIsAFinalResult() {
        let e = event(state: "post", completed: true, name: "STATUS_FULL_TIME", home: 2, away: 1)
        #expect(e.isFinalResult)
        #expect(!e.isUnfinishedPost)
    }

    @Test func suspendedIsNotAFinalResultDespiteReportingPost() {
        // The exact payload that caused the bug.
        let e = event(state: "post", completed: false, name: "STATUS_SUSPENDED", home: 0, away: 0)
        #expect(e.statusState == "post")     // ESPN really does say post…
        #expect(!e.isFinalResult)            // …but the result is NOT settled
        #expect(e.isUnfinishedPost)
    }

    @Test func otherAbandonmentStatusesAlsoBlock() {
        for name in ["STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_CANCELLED",
                     "STATUS_ABANDONED", "STATUS_DELAYED"] {
            let e = event(state: "post", completed: false, name: name)
            #expect(!e.isFinalResult, "\(name) must not count as final")
        }
    }

    @Test func liveAndUpcomingAreNeverFinal() {
        #expect(!event(state: "in", completed: false, name: "STATUS_SECOND_HALF").isFinalResult)
        #expect(!event(state: "pre", completed: false, name: "STATUS_SCHEDULED").isFinalResult)
        // …and neither is an "unfinished post", which is a post-only concept.
        #expect(!event(state: "in").isUnfinishedPost)
        #expect(!event(state: "pre").isUnfinishedPost)
    }

    // MARK: - Fail-open

    @Test func aSparsePayloadStillCountsAsFinal() {
        // ⚠️ POLARITY MATTERS. Only POSITIVE evidence of non-completion blocks a `post` match.
        // A payload with no `completed` and no `name` (an older/sparser feed) must still score, or a
        // single field disappearing upstream would silently stop grading every match — a far worse
        // failure than the one being fixed.
        #expect(event(state: "post").isFinalResult)
        #expect(event(state: "post", completed: nil, name: nil, home: 1, away: 0).isFinalResult)
    }

    @Test func anUnrecognisedPostStatusWithCompletedTrueStillCountsAsFinal() {
        // ESPN inventing a new FT-ish status name must not stop scoring — `completed` carries it.
        #expect(event(state: "post", completed: true, name: "STATUS_SOMETHING_NEW").isFinalResult)
    }

    @Test func completedFalseBlocksEvenWithoutAKnownStatusName() {
        // Belt: the flag alone is enough, so an unlisted abandonment status still can't score.
        #expect(!event(state: "post", completed: false, name: "STATUS_WEATHER_HOLD").isFinalResult)
    }
}
