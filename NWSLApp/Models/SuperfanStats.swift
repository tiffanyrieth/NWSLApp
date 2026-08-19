//
//  SuperfanStats.swift
//  NWSLApp
//
//  The Superfan Zone's competitive tier + standing (Fan Zone v2, Priority #3). The tier is the user's
//  percentile across all QUALIFYING fans (≥2 games played this season), computed client-side from a count
//  query (SuperfanService) — no server function. Season-scoped: each NWSL season stands alone.
//

import SwiftUI

/// The competitive tier from the user's ABSOLUTE 0–100 Superfan score (Fan Zone Competitive Redesign):
/// even quartiles — Fan 0–24 → Rising 25–49 → All-Star 50–74 → MVP 75–100 (one tier per game's worth of
/// the 4×25 economy). Replaced the old percentile model (top 5% = MVP), which made "13 points to All-Star"
/// meaningless. Each tier keeps its own SF Symbol + a DEDICATED tier color (not a game color).
enum SuperfanTier: String, CaseIterable {
    case fan, rising, allStar, mvp

    var label: String {
        switch self {
        case .fan: return "Fan"
        case .rising: return "Rising"
        case .allStar: return "All-Star"
        case .mvp: return "MVP"
        }
    }

    /// SF Symbol per the design (never emoji in game UI).
    var symbol: String {
        switch self {
        case .fan: return "person.fill"
        case .rising: return "arrow.up.circle.fill"
        case .allStar: return "star.circle.fill"
        case .mvp: return "crown.fill"
        }
    }

    /// Dedicated tier palette (design tokens, not game colors): Fan gray, Rising green, All-Star blue,
    /// MVP gold. Maps to existing DS tokens — no raw hex (fan-zone rule: add a token, never a hex).
    var color: Color {
        switch self {
        case .fan: return .dsFgSecondary   // gray  #8E8E93
        case .rising: return .dsSuccess     // green #30D158
        case .allStar: return .dsAccent     // blue  #0A84FF
        case .mvp: return .dsWarning        // gold  #FFD60A
        }
    }

    /// The inclusive lower bound of this tier on the 0–100 scale (Fan 0, Rising 25, All-Star 50, MVP 75).
    var threshold: Int {
        switch self {
        case .fan: return 0
        case .rising: return 25
        case .allStar: return 50
        case .mvp: return 75
        }
    }

    /// The tier for an absolute 0–100 score (quartile bands).
    static func forScore(_ score: Int) -> SuperfanTier {
        if score >= 75 { return .mvp }
        if score >= 50 { return .allStar }
        if score >= 25 { return .rising }
        return .fan
    }

    /// The next tier up (nil at MVP — the top).
    var next: SuperfanTier? {
        switch self {
        case .fan: return .rising
        case .rising: return .allStar
        case .allStar: return .mvp
        case .mvp: return nil
        }
    }
}

/// The progress toward the next tier for the Superfan detail bar. Pure so it's testable.
struct TierProgress: Equatable {
    let current: SuperfanTier
    let score: Int

    init(score: Int) {
        self.score = score
        self.current = SuperfanTier.forScore(score)
    }

    /// 0…1 fill: (score − currentThreshold) / (nextThreshold − currentThreshold). MVP fills to 1.0.
    var fraction: Double {
        guard let next = current.next else { return 1.0 }
        let span = Double(next.threshold - current.threshold)
        guard span > 0 else { return 1.0 }
        return min(1.0, max(0.0, Double(score - current.threshold) / span))
    }

    /// Points remaining to the next tier (0 at MVP).
    var pointsToNext: Int {
        guard let next = current.next else { return 0 }
        return max(0, next.threshold - score)
    }

    /// The bar's caption: "13 points to All-Star" — or the MVP terminal line.
    var caption: String {
        guard let next = current.next else { return "MVP: you've reached the top" }
        return "\(pointsToNext) point\(pointsToNext == 1 ? "" : "s") to \(next.label)"
    }
}

/// The user's Superfan standing among QUALIFYING fans (≥2 games this season). `rank` is 1-based.
///
/// SHOWN AT EVERY SCALE (owner ruling 2026-07-22). This used to hide the tier, the percentile AND the
/// whole tier ladder below 5 qualifying fans, on the reasoning that "top 50% of 3 fans" overstates.
/// That traded one awkward number for an empty screen — the first players, exactly the ones we need to
/// come back, saw none of the feature. It also made Superfan the odd one out: the community games
/// already reveal from responder #1 (the KHG live-community model, proxy `quiz-results.ts`). The one
/// genuinely broken case was N=1, where `rank/qualifying` is 1.0 → a meaningless "Top 100% of 1 fans";
/// `standingText` special-cases that to a rank instead. Everything from 2 up shows the real percentile.
struct SuperfanStanding {
    let rank: Int
    let qualifying: Int

    /// Your position from the top as a fraction (rank 1 of 100 → 0.01). Drives the tier + "Top N%".
    var topFraction: Double { qualifying > 0 ? Double(rank) / Double(qualifying) : 1 }

    /// "Top N%" — at least 1 (being #1 of many is "Top 1%", never "Top 0%").
    var topPercent: Int { max(1, Int((topFraction * 100).rounded())) }

    // NOTE: the competitive TIER is no longer derived from the percentile — it comes from the absolute
    // 0–100 score (`SuperfanTier.forScore`). The standing stays purely about rank/percentile: "Top N% of
    // N fans" and where you sit on the board, which is a DIFFERENT axis than the tier.

    /// The standing line under the season total. A field of ONE has no meaningful percentile (every
    /// fraction is 100%), so it reads as a rank; every larger field gets the real percentile. Owns the
    /// pluralisation so the view never has to branch.
    var standingText: String {
        qualifying <= 1
            ? "#\(rank) of 1 fan"
            : "Top \(topPercent)% of \(qualifying) fans"
    }
}
