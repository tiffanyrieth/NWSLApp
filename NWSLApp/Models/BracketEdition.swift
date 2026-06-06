//
//  BracketEdition.swift
//  NWSLApp
//
//  Bracket Battle — Home's Module 3 "Play", game 2 (per
//  Reference/Design/games-design-spec.md §"Game 2: Bracket Battle"). A themed,
//  single-elimination tournament where the community votes a contender per club
//  through the rounds (the first edition is "Best Goalkeeper" — one GK per club).
//
//  Flat, view-friendly, and Codable-shaped like TriviaQuestion / PlayerSpotlight,
//  so today's TEMP static seed (BracketEditionProvider) can later be swapped for a
//  real editorial/voting backend with no model or view change. `teamAbbreviation`
//  is the join key the view uses to resolve the club crest + name — the same
//  abbreviation-join the rest of the app uses (ESPN gives no stable competitor id).
//
//  A live matchup (who plays whom, who advanced, the vote split) is NOT modelled
//  here — that is derived at runtime in BracketViewModel from the edition (the
//  bracket structure) plus a deterministic simulation (the demo "community"). The
//  model is just the static edition: its contenders, in seed order.
//

import Foundation

/// One contender in an edition — e.g. a single goalkeeper in "Best Goalkeeper."
struct BracketEntrant: Identifiable, Codable, Equatable {
    let id: String
    /// Join key → club crest + name (mirrors FeedItem / PlayerSpotlight).
    let teamAbbreviation: String
    let playerName: String
    /// A short, durable credential shown on the matchup card to inform the vote
    /// ("Two-time World Cup champion"), not a volatile current-season stat.
    let credential: String
}

/// A themed single-elimination edition (Best Goalkeeper, Best Forward, …).
///
/// `entrants` are listed in SEED ORDER — strongest first. The bracket is built by
/// standard tournament seeding (1 v 16, 8 v 9, …) so the favourites don't collide
/// in the first round, and a deterministic, seed-weighted simulation decides who
/// the "community" advances (see BracketViewModel).
struct BracketEdition: Identifiable, Codable, Equatable {
    let id: String
    /// Display name, e.g. "Best Goalkeeper".
    let title: String
    /// One-line framing shown under the title.
    let theme: String
    let entrants: [BracketEntrant]
}

/// Human labels for a round, derived from how many matchups it holds so the
/// scheme generalises to any power-of-two edition (not hardcoded to 16 teams).
enum BracketRoundLabel {
    static func title(matchups: Int) -> String {
        switch matchups {
        case 1: return "Final"
        case 2: return "Semifinals"
        case 4: return "Quarterfinals"
        default: return "Round of \(matchups * 2)"
        }
    }

    static func short(matchups: Int) -> String {
        switch matchups {
        case 1: return "F"
        case 2: return "SF"
        case 4: return "QF"
        default: return "R\(matchups * 2)"
        }
    }
}
