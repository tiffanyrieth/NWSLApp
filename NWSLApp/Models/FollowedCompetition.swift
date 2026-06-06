//
//  FollowedCompetition.swift
//  NWSLApp
//
//  An international competition an NWSL fan can follow alongside their clubs
//  (USWNT, the World Cup, …). Named FollowedCompetition (not Competition) to avoid
//  colliding with Scoreboard's `Competition`, which is ESPN's term for a single
//  match. Clubs come from ESPN's /teams directory; these don't live in that feed,
//  so they're a small curated static list here.
//
//  Following one is persisted in FollowingStore next to followed clubs. Today
//  that's the whole feature: the Schedule isn't competition-aware yet (it shows
//  NWSL fixtures only), so a followed competition is remembered but doesn't change
//  the schedule — that's the larger competition-aware-schedule work in CLAUDE.md's
//  What's-Next. The model + follow set are the groundwork for it.
//

import Foundation

struct FollowedCompetition: Identifiable, Hashable {
    let id: String          // stable slug, the key persisted in FollowingStore
    let name: String
    let systemImage: String // SF Symbol for the onboarding row

    /// The curated set offered in onboarding, in display order.
    static let all: [FollowedCompetition] = [
        FollowedCompetition(id: "uswnt", name: "USWNT", systemImage: "flag.fill"),
        FollowedCompetition(id: "womens-world-cup", name: "Women's World Cup", systemImage: "globe.americas.fill"),
        FollowedCompetition(id: "concacaf-w-champions", name: "CONCACAF W Champions Cup", systemImage: "trophy.fill"),
        FollowedCompetition(id: "olympics", name: "Olympic Games", systemImage: "medal.fill"),
        FollowedCompetition(id: "shebelieves-cup", name: "SheBelieves Cup", systemImage: "star.circle.fill"),
    ]
}
