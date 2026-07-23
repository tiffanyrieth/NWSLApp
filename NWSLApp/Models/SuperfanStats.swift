//
//  SuperfanStats.swift
//  NWSLApp
//
//  The Superfan Zone's competitive tier + standing (Fan Zone v2, Priority #3). The tier is the user's
//  percentile across all QUALIFYING fans (≥2 games played this season), computed client-side from a count
//  query (SuperfanService) — no server function. Season-scoped: each NWSL season stands alone.
//

import SwiftUI

/// The competitive tier from the user's Superfan percentile (design table). Fan (everyone) → Rising (top
/// 50%) → All-Star (top 20%) → MVP (top 5%). Each keeps its own SF Symbol + accent.
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

    var color: Color {
        switch self {
        case .fan: return .dsFgSecondary
        case .rising: return .dsGameTrivia    // indigo
        case .allStar: return .dsGameBracket  // teal
        case .mvp: return .dsGamePredict      // pink
        }
    }

    /// The tier for a top-fraction (0 = the very top, 1 = the bottom): top 5% → MVP, top 20% → All-Star,
    /// top 50% → Rising, else Fan (thresholds inclusive).
    static func forTopFraction(_ f: Double) -> SuperfanTier {
        if f <= 0.05 { return .mvp }
        if f <= 0.20 { return .allStar }
        if f <= 0.50 { return .rising }
        return .fan
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

    var tier: SuperfanTier { SuperfanTier.forTopFraction(topFraction) }

    /// The standing line under the season total. A field of ONE has no meaningful percentile (every
    /// fraction is 100%), so it reads as a rank; every larger field gets the real percentile. Owns the
    /// pluralisation so the view never has to branch.
    var standingText: String {
        qualifying <= 1
            ? "#\(rank) of 1 fan"
            : "Top \(topPercent)% of \(qualifying) fans"
    }
}
