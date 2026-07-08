//
//  PlayoffOverride.swift
//  NWSLApp
//
//  The operator escape hatch for the postseason bracket. ESPN is the sole data source and it
//  DOES corrupt NWSL data (the roster-wipe-on-trade incident) and is slow to fix it. This is the
//  same last-known-good philosophy applied to the playoff bracket: an optional JSON served by the
//  proxy (`GET /playoff-override?season=YYYY`) that the app LAYERS over its ESPN-derived bracket,
//  so a bad game (wrong winner/score, a dropped match) or a format surprise is corrected with a
//  server edit — live for everyone in minutes — instead of an App Store release.
//
//  Dormant by default: no override set → the proxy returns `override: null` → the app derives
//  purely from ESPN, unchanged. Everything here is PURE + unit-tested (PlayoffOverrideTests) so
//  the escape hatch isn't an untested code path the one time it's needed.
//

import Foundation

/// The proxy envelope: `{ version, season, override }`.
struct PlayoffOverrideEnvelope: Decodable {
    let version: Int?
    let season: Int?
    let override: PlayoffOverride?
}

/// Operator corrections layered over the ESPN-derived bracket. All fields optional; the app
/// ignores unknown keys (forward-compatible).
struct PlayoffOverride: Decodable, Equatable {
    /// Operator-only note (why this exists) — not shown in the app.
    let note: String?
    /// Kill switch: hide the whole postseason feature (if ESPN is too broken to show anything).
    let hideBracket: Bool?
    /// Force the bracket size (e.g. an expansion/format change ESPN mis-reports).
    let teamCount: Int?
    /// Correct specific seeds (merged OVER the ESPN standings seeds).
    let seeds: [String: Int]?
    /// Correct or inject specific games.
    let matchups: [MatchupPatch]?

    var isEmpty: Bool {
        (hideBracket != true) && teamCount == nil && (seeds?.isEmpty ?? true) && (matchups?.isEmpty ?? true)
    }
}

/// A per-matchup correction/injection, identified by round slug + the two team abbreviations.
struct MatchupPatch: Decodable, Equatable {
    let round: String       // ESPN season slug, e.g. "playoffs---semifinals"
    let home: String        // abbreviation
    let away: String        // abbreviation
    let homeScore: Int?
    let awayScore: Int?
    let winner: String?     // abbreviation of the side that advanced (PK-safe)
    let state: String?      // "pre" | "in" | "post"
    let kickoff: String?    // ISO8601, e.g. "2026-11-15T17:00Z"
    let broadcast: String?
    let venue: String?
}

// MARK: - Application (pure — feeds corrected inputs to PlayoffBracket.derive)

extension PlayoffOverride {
    /// Apply this override to the raw derivation inputs. Seed corrections merge OVER ESPN's; each
    /// matchup patch REPLACES any existing event for that round + team pair (or injects one if ESPN
    /// dropped it). Because corrections are applied at the EVENT level before `derive`, a fixed
    /// winner propagates naturally to the next round. `hideBracket` is read by the caller.
    func corrected(events: [Event], seeds baseSeeds: [String: Int]) -> (events: [Event], seeds: [String: Int]) {
        var outSeeds = baseSeeds
        for (abbr, seed) in self.seeds ?? [:] { outSeeds[abbr] = seed }   // override seeds win

        var outEvents = events
        for patch in matchups ?? [] {
            let patchTeams: Set<String> = [patch.home, patch.away]
            outEvents.removeAll { ev in
                guard ev.seasonSlug == patch.round else { return false }
                let a = ev.homeCompetitor?.team?.abbreviation
                let b = ev.awayCompetitor?.team?.abbreviation
                return Set([a, b].compactMap { $0 }) == patchTeams
            }
            outEvents.append(patch.asEvent())
        }
        return (outEvents, outSeeds)
    }
}

extension MatchupPatch {
    /// Synthesize an ESPN-shaped Event from this patch (higher seed as `home` is preserved as
    /// given; `derive` re-normalizes home/away by seed anyway).
    func asEvent() -> Event {
        let statusState = state ?? (winner != nil ? "post" : "pre")
        func competitor(_ abbr: String, score: Int?, homeAway: String) -> Competitor {
            Competitor(homeAway: homeAway, score: score.map(String.init),
                       team: Team(displayName: abbr, abbreviation: abbr),
                       winner: winner == abbr)
        }
        return Event(
            id: "override-\(round)-\(home)-\(away)",
            name: "\(away) at \(home)", shortName: "\(away) @ \(home)",
            date: kickoff,
            status: EventStatus(type: StatusType(state: statusState)),
            competitions: [Competition(
                competitors: [competitor(home, score: homeScore, homeAway: "home"),
                              competitor(away, score: awayScore, homeAway: "away")],
                venue: venue.map { Venue(fullName: $0) },
                broadcasts: broadcast.map { [Broadcast(names: [$0])] }
            )],
            season: EventSeason(slug: round)
        )
    }
}
