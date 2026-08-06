//
//  MatchStoreClubJoinTests.swift
//  NWSLAppTests
//
//  `MatchStore.matches(for:)` resolves a club to its fixtures by ESPN's STABLE team id, not the
//  abbreviation (fixed 2026-08-06 — ESPN sends `team.id` on scoreboard competitors; it just wasn't
//  decoded, which forced a rename-fragile abbreviation join). These lock the id-first rule and its
//  fail-open abbreviation fallback, tested through the extracted pure static (no live store needed).
//

import Foundation
import Testing
@testable import NWSLApp

struct MatchStoreClubJoinTests {

    private func club(id: String, abbr: String) -> Club {
        Club(id: id, displayName: abbr, abbreviation: abbr, logoURL: nil)
    }

    private func event(home: Team, away: Team) -> Event {
        Event(id: UUID().uuidString,
              competitions: [Competition(competitors: [
                  Competitor(homeAway: "home", team: home),
                  Competitor(homeAway: "away", team: away),
              ])])
    }

    /// THE POINT: the id join survives an abbreviation rebrand/relocation. The club is still "CHI"
    /// but ESPN now sends the abbreviation as "CHICAGO" on the wire — the stable id still resolves it.
    @Test func joinsByStableIdEvenWhenAbbreviationChanged() {
        let chi = club(id: "15360", abbr: "CHI")
        let renamed = event(home: Team(id: "15360", abbreviation: "CHICAGO"),
                            away: Team(id: "20905", abbreviation: "LOU"))
        #expect(MatchStore.matches(for: chi, in: [renamed]).count == 1)
    }

    /// The id also PREVENTS a false match: another team that happens to share the "CHI" abbreviation
    /// (a stale/duplicated code) but a different id must not land in this club's record.
    @Test func sharedAbbreviationWithDifferentIdIsNotMatched() {
        let chi = club(id: "15360", abbr: "CHI")
        let imposter = event(home: Team(id: "99999", abbreviation: "CHI"),
                             away: Team(id: "20905", abbreviation: "LOU"))
        #expect(MatchStore.matches(for: chi, in: [imposter]).isEmpty)
    }

    /// Fail-open: a competitor that carries NO id falls back to the abbreviation (never worse than the
    /// old behaviour) — matching on the same abbreviation, not matching on a different one.
    @Test func fallsBackToAbbreviationWhenNoId() {
        let chi = club(id: "15360", abbr: "CHI")
        let noId = event(home: Team(id: nil, abbreviation: "CHI"),
                         away: Team(id: nil, abbreviation: "LOU"))
        #expect(MatchStore.matches(for: chi, in: [noId]).count == 1)
        #expect(MatchStore.matches(for: club(id: "77777", abbr: "WAS"), in: [noId]).isEmpty)
    }
}
