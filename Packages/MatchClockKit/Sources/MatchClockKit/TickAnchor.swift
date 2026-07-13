//
//  TickAnchor.swift
//  MatchClockKit
//
//  The monotonic live-clock anchor + its reconcile rule — the stoppage-time freeze fix (2026-07-04/05).
//  ESPN FREEZES `status.clock` at 45:00/90:00 through stoppage time, and re-anchoring to the fetch
//  instant on every ~30s poll wiped the local accumulation before it could cross a minute boundary —
//  pinning the display at 45'+1'/90'+1' for ALL of stoppage. Rule: while a match's (clock, period)
//  hasn't advanced, KEEP the anchor from when that clock value was FIRST seen, so
//  `clock + (now − anchor)` keeps counting +2'…+11'. Re-anchor when the clock advances or the period
//  changes (the halftime pause breaks continuity legitimately).
//
//  Pure value logic (nonisolated, Foundation-only) so it's exercised directly in tests. The app owns
//  durability (MatchStore persists `[String: TickAnchor]` to UserDefaults so a mid-stoppage relaunch
//  doesn't reset the count) — the package stays storage-agnostic.
//

import Foundation

public struct TickAnchor: Equatable, Codable {
    public let clock: Double
    public let period: Int
    public let date: Date
    /// True when this match was FIRST seen with its clock already frozen at the regulation cap
    /// (45:00/90:00) — i.e. we joined mid-stoppage with no history. The true stoppage minute is
    /// unknowable (ESPN doesn't transmit it), so ticking from "now" would fabricate 45'+1' at the 7th
    /// minute of added time. Consumers treat a fresh-at-cap anchor as "no local tick" and fall back to
    /// ESPN's own display string until the clock advances again and a real anchor forms.
    public var freshAtCap: Bool

    public init(clock: Double, period: Int, date: Date, freshAtCap: Bool = false) {
        self.clock = clock
        self.period = period
        self.date = date
        self.freshAtCap = freshAtCap
    }

    /// Pure reconcile of the live anchor set: keep a frozen/stalled clock's original anchor (so local
    /// accumulation keeps climbing through stoppage), re-anchor on advance/period-change, flag a cold
    /// start already at the cap as `freshAtCap`, and drop non-live matches. Generic over any
    /// `ClockTickSource` so the package never touches the ESPN `Event` model.
    public static func reconcile<Source: ClockTickSource>(
        previous: [String: TickAnchor],
        sources: [Source],
        at instant: Date
    ) -> [String: TickAnchor] {
        var next: [String: TickAnchor] = [:]
        for source in sources where source.statusState == "in" {
            guard let clock = source.clockSeconds else { continue }
            let period = source.period ?? 0
            if let old = previous[source.id], old.period == period, clock <= old.clock {
                next[source.id] = old // frozen/stalled server clock → keep accumulating locally
            } else {
                // First sighting AT the frozen regulation cap (e.g. cold start mid-stoppage): the true
                // stoppage minute is unknowable — flag it so consumers fall back to ESPN's string
                // instead of fabricating 45'+1'. Clears itself once the clock advances.
                let cap = MatchClock.regulationCap(period: period).map { Double($0) * 60 }
                let freshAtCap = previous[source.id] == nil && cap != nil && clock >= cap!
                next[source.id] = TickAnchor(clock: clock, period: period, date: instant, freshAtCap: freshAtCap)
            }
        }
        return next // non-live matches drop out
    }
}
