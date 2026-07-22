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

/// The user's Superfan standing among QUALIFYING fans (≥2 games this season). Only meaningful once enough
/// fans qualify — below `minQualifiers` the detail screen shows the honest "building your season" state
/// instead of a percentile (no "top 50% of 3 fans"). `rank` is 1-based.
struct SuperfanStanding {
    let rank: Int
    let qualifying: Int

    /// Below this many qualifying fans, a percentile/tier is not shown (honest at low scale).
    static let minQualifiers = 5

    var isMeaningful: Bool { qualifying >= Self.minQualifiers }

    /// Your position from the top as a fraction (rank 1 of 100 → 0.01). Drives the tier + "Top N%".
    var topFraction: Double { qualifying > 0 ? Double(rank) / Double(qualifying) : 1 }

    /// "Top N%" — at least 1 (being #1 of many is "Top 1%", never "Top 0%").
    var topPercent: Int { max(1, Int((topFraction * 100).rounded())) }

    var tier: SuperfanTier { SuperfanTier.forTopFraction(topFraction) }
}
