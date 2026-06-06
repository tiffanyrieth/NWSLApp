//
//  BracketEditionProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 3 "Play",
//  game 2 (Bracket Battle), per Reference/Design/games-design-spec.md.
//
//  WHAT: one complete "Best Goalkeeper" edition — a 16-team bracket with one real
//  goalkeeper per club (all 16, incl. the 2026 Denver Summit / Boston Legacy
//  expansion sides). Entrants are listed in SEED ORDER (strongest first); the
//  ViewModel builds the bracket by standard tournament seeding and simulates the
//  "community" vote deterministically. Also provides a simulated leaderboard of
//  sample usernames the user is ranked against (the spec's demo leaderboard).
//
//  WHY: the spec wants Bracket Battle real and playable for a concept demo
//  without a backend — votes + results stored locally (BracketStore), a simulated
//  community + leaderboard standing in for real multi-user voting. This seed is
//  the contender list; the rest is derived.
//
//  ACCURACY: keeper↔club pairings and credentials are a 2026 snapshot gathered by
//  research, leaning on DURABLE facts (trophies, caps, awards) over volatile
//  current-season form. Seed ORDER is an editorial reputation ranking and is
//  inherently subjective. Treat as curated demo content to be editorially
//  re-verified, not a live source of truth.
//
//  WHEN REMOVED: replace `edition()` with a real editorial/voting backend (or the
//  planned proxy) returning the same `BracketEdition`, and `leaderboardOpponents()`
//  with real standings once multi-user voting exists (the leaderboard needs the
//  server — spec §Leaderboard). The async signature is already shaped for it.
//

import Foundation

struct BracketEditionProvider {
    func edition() async -> BracketEdition { Self.bestGoalkeeper }

    /// Sample opponents for the simulated leaderboard — fixed per-edition point
    /// totals the user (whose points grow as rounds close) is ranked among, so the
    /// user climbs the board across the tournament. Replaced by real standings
    /// when a voting backend exists.
    func leaderboardOpponents() -> [(name: String, points: Int)] { Self.opponents }

    private static func gk(_ abbr: String, _ name: String, _ credential: String) -> BracketEntrant {
        BracketEntrant(id: "GK-\(abbr)", teamAbbreviation: abbr, playerName: name, credential: credential)
    }

    // Listed strongest-first (seed 1 → 16). Reputation order is editorial.
    private static let bestGoalkeeper = BracketEdition(
        id: "best-goalkeeper-2026",
        title: "Best Goalkeeper",
        theme: "16 keepers, one champion. Vote who the community sends through.",
        entrants: [
            gk("CHI", "Alyssa Naeher",
               "Two-time World Cup champion; saved the decisive kick in the 2019 final"),
            gk("SD", "Kailen Sheridan",
               "Canada's Olympic gold-winning No. 1 and a Wave shot-stopping wall"),
            gk("GFC", "Ann-Katrin Berger",
               "Germany international and Olympic medallist; NWSL Championship winner"),
            gk("ORL", "Anna Moorhouse",
               "Anchored Orlando's 2024 NWSL Shield and Championship double"),
            gk("BOS", "Casey Murphy",
               "USWNT goalkeeper anchoring expansion side Boston Legacy"),
            gk("HOU", "Jane Campbell",
               "Longtime Houston No. 1 and capped USWNT goalkeeper"),
            gk("POR", "Bella Bixby",
               "Portland mainstay and NWSL Championship winner between the posts"),
            gk("KC", "Adrianna Franch",
               "Two-time NWSL Goalkeeper of the Year"),
            gk("WAS", "Aubrey Kingsbury",
               "Washington Spirit veteran and 2021 NWSL champion"),
            gk("SEA", "Claudia Dickey",
               "Seattle Reign's rising shot-stopper and USWNT call-up"),
            gk("UTA", "Mandy McGlynn",
               "Shot-stopping standout and Utah Royals' first-choice keeper"),
            gk("LOU", "Katie Lund",
               "Racing Louisville's reliable first-choice goalkeeper"),
            gk("LA", "Angelina Anderson",
               "Young American keeper rising through Angel City's ranks"),
            gk("NC", "Katelyn Rowland",
               "Experienced keeper with NWSL Championship pedigree at the Courage"),
            gk("BAY", "Jordan Silkowitz",
               "Bay FC shot-stopper earning her stripes in the NWSL"),
            gk("DEN", "Michelle Betos",
               "Veteran NWSL goalkeeper bringing experience to expansion Denver"),
        ]
    )

    // Soccer-fan-flavoured handles + fixed totals spanning the achievable range
    // (max 15 points across a 16-team bracket: 8 + 4 + 2 + 1 correct picks).
    private static let opponents: [(name: String, points: Int)] = [
        ("keeperqueen", 13),
        ("backline_betty", 12),
        ("pk_saver", 11),
        ("glove_affair", 10),
        ("cleansheet_carl", 9),
        ("sixyardbox", 8),
        ("top_bins", 7),
        ("nutmeg_nina", 6),
        ("farpost_fran", 4),
        ("rookie_riley", 3),
        ("benchwarmer", 1),
    ]
}
