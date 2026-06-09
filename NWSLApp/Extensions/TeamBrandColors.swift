//
//  TeamBrandColors.swift
//  NWSLApp
//
//  Brand-color overrides for the handful of clubs whose ESPN color data is wrong
//  or incomplete. ESPN's unofficial NWSL feed ships some teams a near-black
//  primary plus a muted alternate and never their real identity color — e.g.
//  Angel City sends #202121 (black) + #898c8f (gray), never their "Sol Rosa"
//  coral. These overrides supply the true brand hexes and are consulted BEFORE
//  ESPN's, so the right color shows everywhere team colors appear (resolved
//  through Color.resolveMatchColors).
//
//  Keyed by ESPN team id (stable — verified the same across /teams, standings,
//  and /summary). Add an entry ONLY when ESPN is actually wrong; otherwise let
//  ESPN's data flow through unchanged.
//

import Foundation

enum TeamBrandColors {
    /// (primary, alternate) hex without '#', overriding ESPN's for these team ids.
    private static let overrides: [String: (primary: String, alternate: String?)] = [
        // Angel City FC (id 21422) — "Sol Rosa" coral; ESPN ships black + gray.
        "21422": (primary: "E6447B", alternate: "202121"),
    ]

    /// The brand primary hex for a team, or nil when ESPN's value should stand.
    static func primary(for teamID: String?) -> String? {
        guard let teamID else { return nil }
        return overrides[teamID]?.primary
    }

    /// The brand alternate hex for a team, or nil when ESPN's value should stand.
    static func alternate(for teamID: String?) -> String? {
        guard let teamID else { return nil }
        return overrides[teamID]?.alternate
    }
}
