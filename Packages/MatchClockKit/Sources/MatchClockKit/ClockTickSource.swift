//
//  ClockTickSource.swift
//  MatchClockKit
//
//  The minimal read surface the anchor engine needs from a live match, so MatchClockKit stays a leaf
//  and never imports the app's ESPN `Event` model. The app conforms `Event` to this (see MatchStore).
//  Keeps the package testable in isolation via a lightweight mock.
//

import Foundation

public protocol ClockTickSource {
    /// Stable per-match identifier (ESPN event id) — the anchor dictionary key.
    var id: String { get }
    /// ESPN status state: "pre" | "in" | "post". Only "in" matches get an anchor.
    var statusState: String? { get }
    /// Match-ELAPSED seconds (ESPN `status.clock`; continuous across halves). nil → no anchor.
    var clockSeconds: Double? { get }
    /// ESPN `status.period` — 1/2 regulation, 3/4 ET (drives the 45'/90' stoppage cap).
    var period: Int? { get }
}
