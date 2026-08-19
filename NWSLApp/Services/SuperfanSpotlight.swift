//
//  SuperfanSpotlight.swift
//  NWSLApp
//
//  The rotating "what we noticed" spotlight for the rebuilt Superfan detail (2026-08-05, owner). PURE +
//  testable — no SwiftUI, no I/O. The old Superfan was a static accuracy spreadsheet nobody opened; this
//  is the hook: ONE fresh, real, personal item each visit, picked from a pool so it's never the same
//  twice. The rotation — not deep-history mining — is what makes it feel alive, so the pool is built
//  entirely from CHEAP signals we already have (tier progress, channel gaps, personal bests, achievements,
//  the players-learned count) plus a playful zero-state.
//
//  ⚠️ ZERO fabricated data: every item is a real fact or an honest empty-state; never invent a moment.
//  ⚠️ Keep the tone FANDOM-PLAYFUL, never tryhard-competitive ([[feedback_superfan_points_philosophy]] +
//  [[feedback_app_vibe_low_entry_fun]]) — nudges toward fun, self-deprecating at the bottom (the "Mario
//  Kart sad guy in the distance").
//

import Foundation

enum SuperfanSpotlight {

    struct Item: Equatable {
        let icon: String            // SF Symbol
        let headline: String
        let detail: String?
        enum Tone { case celebratory, nudge, playful, info }
        let tone: Tone
    }

    /// Everything the pool needs, all cheap/local. The view assembles this from the breakdown + stores.
    struct Input {
        let total: Int
        let breakdown: SuperfanBreakdown
        let playersLearned: Int          // KHG collection size this season
        let bestPredictStarters: Int?    // personal best (nil if never scored a Predict)
        let recentAchievement: String?   // a recently-earned achievement title (nil if none)
        let gamesPlayed: Int             // channels with ≥1 attempt
    }

    /// Tier boundaries + their names, kept next to `SuperfanScoring.tierThresholds` (pure — the SwiftUI
    /// `SuperfanTier` carries the colors, which a pure file can't import).
    private static let tiers: [(threshold: Int, name: String)] = [(25, "Rising"), (50, "All-Star"), (75, "MVP")]

    /// Friendly game names for the nudges (the display layer owns icons/colors; this is copy only).
    private static func gameName(_ g: SuperfanGame) -> String {
        switch g {
        case .predict: return "Predict"
        case .bracket: return "The Bracket"
        case .khg:     return "Know Her Game"
        case .trivia:  return "NWSL Trivia"
        }
    }

    /// The eligible spotlight items for this fan, most-motivating first. Only REAL items make the pool;
    /// an item that has nothing to say is simply absent.
    static func pool(_ input: Input) -> [Item] {
        var items: [Item] = []

        // 1. One tier away — the single most actionable nudge (unless already MVP).
        if let next = tiers.first(where: { $0.threshold > input.total }) {
            let gap = next.threshold - input.total
            items.append(Item(
                icon: "arrow.up.forward.circle.fill",
                headline: "\(gap) to \(next.name)",
                detail: gap <= 8 ? "You're one good round away." : "Keep showing up. You're climbing.",
                tone: .nudge))
        }

        // 2. A channel that's holding you back — breadth incentive, phrased as opportunity not scolding.
        //    An UNPLAYED channel first (biggest upside), else the lowest-scoring one.
        let unplayed = SuperfanGame.allCases.first { input.breakdown.channel(for: $0).accuracyRatio == 0
                                                     && input.breakdown.contribution(for: $0) == 0 }
        if let g = unplayed, input.gamesPlayed < 4 {
            items.append(Item(
                icon: "sparkle.magnifyingglass",
                headline: "\(gameName(g)) is untapped",
                detail: "You haven't played it yet. It's worth up to 25 of your 100.",
                tone: .nudge))
        } else if let weakest = SuperfanGame.allCases.min(by: {
            input.breakdown.contribution(for: $0) < input.breakdown.contribution(for: $1) }),
                  input.breakdown.contribution(for: weakest) > 0 {
            items.append(Item(
                icon: "chart.line.uptrend.xyaxis",
                headline: "\(gameName(weakest)) has the most room",
                detail: "It's your lightest channel. A strong round lifts the whole score.",
                tone: .info))
        }

        // 3. Players learned — the collection tease (ties into the grid below on the detail screen).
        if input.playersLearned > 0 {
            items.append(Item(
                icon: "person.crop.circle.badge.checkmark",
                headline: "\(input.playersLearned) player\(input.playersLearned == 1 ? "" : "s") learned",
                detail: "Your Know Her Game collection this season. Keep it growing.",
                tone: .celebratory))
        }

        // 4. A personal best — a real high-water mark.
        if let best = input.bestPredictStarters, best >= 6 {
            items.append(Item(
                icon: "star.circle.fill",
                headline: "Best Predict week: \(best) of 11",
                detail: "Your sharpest lineup call so far.",
                tone: .celebratory))
        }

        // 5. A recently-earned achievement.
        if let ach = input.recentAchievement {
            items.append(Item(icon: "rosette", headline: ach, detail: "Earned. Nice.", tone: .celebratory))
        }

        // 6. Playful floor — never leave the pool empty; the zero/low state gets personality, not a blank.
        if items.isEmpty || input.total < 15 {
            items.append(Item(
                icon: "figure.wave",
                headline: input.total == 0 ? "Fan tier: everyone starts here" : "Just getting warm",
                detail: "Play a game or two and watch this fill up.",
                tone: .playful))
        }

        return items
    }

    /// Pick ONE item for this visit. `rotation` is a per-open counter the view bumps, so consecutive opens
    /// show different items (that rotation is the whole "never the same twice" hook). nil only if the pool
    /// is empty, which `pool` prevents.
    static func pick(_ input: Input, rotation: Int) -> Item? {
        let p = pool(input)
        guard !p.isEmpty else { return nil }
        return p[((rotation % p.count) + p.count) % p.count]   // safe modulo for any Int
    }
}
