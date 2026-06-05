//
//  PlayerSpotlightProvider.swift
//  NWSLApp
//
//  ⚠️ TEMP / SCAFFOLDING — curated static seed for Home's Module 2 ("Get to know
//  your players").
//
//  WHAT: One "player of the week" candidate per club (all 16, incl. the 2026
//  Denver Summit / Boston Legacy expansion sides), each a real 2026-roster player
//  with their real jersey number + position — verified against current club
//  rosters (player-movement traps like mid-2025 transfers were screened out). The
//  `watchURL` points at that team's real YouTube channel (a per-player deep link
//  arrives with a real source). Module 2 still hides cleanly if a followed team
//  ever has no spotlight.
//
//  WHY: The spec made Module 2 visible by default — a compact card that introduces
//  the roster one player at a time. There's no player-content backend yet, so this
//  seed lets the module be real and functional for concept demos, mirroring the
//  Feed/Module-1 seed approach.
//
//  WHEN REMOVED: Replace `spotlights()` with a real source (curated editorial
//  feed or the planned proxy) returning the same `[PlayerSpotlight]`, ideally with
//  per-player content links + the club's color for a team-colored jersey badge.
//  The async signature is already shaped for it; the ViewModel/view don't change.
//

import Foundation

struct PlayerSpotlightProvider {
    func spotlights() async -> [PlayerSpotlight] { Self.seed }

    /// Team YouTube channels (same durable URLs as TeamContentProvider).
    private static let yt: [String: String] = [
        "LA":  "https://www.youtube.com/@AngelCityFC",
        "BAY": "https://www.youtube.com/@WeAreBayFC",
        "CHI": "https://www.youtube.com/chicagoredstarsnwsl",
        "GFC": "https://www.youtube.com/channel/UCX5SydaP78jaqqcNx9ZrrtQ",
        "HOU": "https://www.youtube.com/user/houstondash",
        "KC":  "https://www.youtube.com/kccurrent",
        "NC":  "https://www.youtube.com/c/NorthCarolinaCourage",
        "ORL": "https://www.youtube.com/@ORLPride",
        "POR": "https://www.youtube.com/user/PortlandThornsFC",
        "LOU": "https://www.youtube.com/channel/UC3xOx0RR9rerRp20jJyHQdw",
        "SD":  "https://www.youtube.com/@sandiegowavefc",
        "SEA": "https://www.youtube.com/seattlereignfc",
        "UTA": "https://www.youtube.com/@utahroyalsfc",
        "WAS": "https://www.youtube.com/WashingtonSpirit",
        "DEN": "https://www.youtube.com/channel/UC55HcqZQqqdnkjsWWrD01Wg",
        "BOS": "https://www.youtube.com/@BostonLegacyFC",
    ]

    private static func spot(
        _ abbr: String, _ name: String, _ number: Int, _ position: String
    ) -> PlayerSpotlight {
        PlayerSpotlight(
            id: abbr, teamAbbreviation: abbr, playerName: name,
            jerseyNumber: number, position: position, watchURL: URL(string: yt[abbr] ?? "")
        )
    }

    private static let seed: [PlayerSpotlight] = [
        spot("LA",  "Sveindís Jónsdóttir", 32, "Forward"),
        spot("BAY", "Racheal Kundananji",   9, "Forward"),
        spot("BOS", "Casey Murphy",         1, "Goalkeeper"),
        spot("CHI", "Mallory Swanson",      9, "Forward"),
        spot("DEN", "Yazmeen Ryan",         9, "Forward"),
        spot("GFC", "Esther González",      9, "Forward"),
        spot("HOU", "Messiah Bright",       6, "Forward"),
        spot("KC",  "Temwa Chawinga",       6, "Forward"),
        spot("NC",  "Manaka Matsukubo",    34, "Midfielder"),
        spot("ORL", "Marta",               10, "Forward"),
        spot("POR", "Sophia Wilson",        9, "Forward"),
        spot("LOU", "Emma Sears",          13, "Forward"),
        spot("SD",  "Kenza Dali",          10, "Midfielder"),
        spot("SEA", "Nérilia Mondésir",    30, "Forward"),
        spot("UTA", "Mina Tanaka",         11, "Forward"),
        spot("WAS", "Trinity Rodman",       2, "Forward"),
    ]
}
