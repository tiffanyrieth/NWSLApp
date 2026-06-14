//
//  ContentRoundRobin.swift
//  NWSLApp
//
//  The pure brains behind Home Module 1's "From your teams" balancing (QOL Change 1).
//  With live data a loud club (10 videos/week) buries a quiet one (2/week) under a
//  plain reverse-chron sort. This replaces that with a round-robin fair-share: every
//  followed team gets a guaranteed minimum of slots, interleaved one-per-team so the
//  quiet club sits ALONGSIDE the loud one at the top, then the rest fills
//  chronologically up to a cap that scales with how many teams you follow.
//
//  Everything here is PURE + deterministic (no Date(), no randomness) so it unit-tests
//  like BracketScoring / PredictionScoring: HomeViewModel does the freshness filtering
//  (`.fresh(.home, now:)`) and the content-type chip filtering, then hands the result
//  in. The content-type classifier (Change 3) lives here too — it's content
//  categorisation, the same family of logic.
//

import Foundation

/// The Home content-type chips (Change 3). A superset of the Feed's filter — Home
/// adds `videos`, and (deliberately, unlike Feed) treats a social video clip as a
/// Video, not Social.
enum HomeContentFilter: String, CaseIterable, Hashable {
    case all, videos, news, social

    var label: String {
        switch self {
        case .all:    return "All"
        case .videos: return "Videos"
        case .news:   return "News"
        case .social: return "Social"
        }
    }
}

enum ContentRoundRobin {

    /// The balanced module plus how many eligible cards didn't fit — the latter
    /// drives the "See more from your teams →" link.
    struct Result: Equatable {
        let cards: [ContentCard]
        let overflowCount: Int
    }

    /// Guaranteed slots per team + the hard total ceiling, scaled by follow count
    /// (the spec's fair-share table). More follows → fewer guaranteed each, but a
    /// higher ceiling, so the module never balloons past ~2 screens.
    static func tier(_ teamCount: Int) -> (guaranteed: Int, cap: Int) {
        switch teamCount {
        case ...2: return (4, 10)   // 1–2 teams
        case 3...4: return (3, 12)
        case 5...7: return (2, 16)
        default:    return (2, 20)  // 8+ teams, hard ceiling
        }
    }

    /// Balance + cap the cards for Home Module 1.
    ///
    /// - cards: already freshness- and chip-filtered by the caller.
    /// - followedAbbreviations: the followed clubs in a STABLE order (alphabetical),
    ///   so the round-robin interleave is deterministic.
    /// - windowOffsets: per-team rotation offset for pull-to-refresh (see
    ///   `advancedOffsets`); 0 = newest.
    static func balanced(
        cards: [ContentCard],
        followedAbbreviations: [String],
        windowOffsets: [String: Int] = [:]
    ) -> Result {
        // 1. Group by team, newest-first within each (id-desc tiebreak = determinism).
        var byTeam: [String: [ContentCard]] = [:]
        for card in cards {
            guard let abbr = card.teamAbbreviation else { continue }
            byTeam[abbr, default: []].append(card)
        }
        for abbr in byTeam.keys {
            byTeam[abbr]!.sort(by: newestFirst)
        }

        let (guaranteed, cap) = tier(followedAbbreviations.count)

        // 2. Per team: rotate by its window offset, reserve the first `guaranteed`,
        //    spill the rest into the shared leftover pool.
        var reservedByTeam: [String: [ContentCard]] = [:]
        var leftover: [ContentCard] = []
        for abbr in followedAbbreviations {
            let all = byTeam[abbr] ?? []
            guard !all.isEmpty else { continue }
            let rotated = rotate(all, by: windowOffsets[abbr] ?? 0)
            reservedByTeam[abbr] = Array(rotated.prefix(guaranteed))
            leftover.append(contentsOf: rotated.dropFirst(guaranteed))
        }

        // 3. Interleave reserved slots round-robin: round 0 is one card per team (so a
        //    quiet team sits at the top beside a loud one), round 1 the seconds, etc.
        var shown: [ContentCard] = []
        var seen = Set<String>()
        var round = 0
        var addedThisRound = true
        while addedThisRound {
            addedThisRound = false
            for abbr in followedAbbreviations {
                guard let reserved = reservedByTeam[abbr], round < reserved.count else { continue }
                let card = reserved[round]
                if seen.insert(card.id).inserted { shown.append(card) }
                addedThisRound = true
            }
            round += 1
        }

        // 4. Fill remaining capacity chronologically from the leftover pool.
        leftover.sort(by: newestFirst)
        for card in leftover {
            if shown.count >= cap { break }
            if seen.insert(card.id).inserted { shown.append(card) }
        }

        // 5. Hard ceiling (guaranteed × teams can exceed cap with many follows).
        if shown.count > cap { shown = Array(shown.prefix(cap)) }

        let totalEligible = byTeam.values.reduce(0) { $0 + $1.count }
        return Result(cards: shown, overflowCount: max(0, totalEligible - shown.count))
    }

    /// Pull-to-refresh rotation: when no NEW content arrived, shift each team's window
    /// forward by one page (`guaranteed`), wrapping, so the user discovers cards they
    /// hadn't seen — natural forward motion, never random. `availableCounts` is each
    /// team's eligible-card count (the wrap modulus).
    static func advancedOffsets(
        current: [String: Int],
        availableCounts: [String: Int],
        guaranteed: Int
    ) -> [String: Int] {
        var next = current
        for (abbr, count) in availableCounts where count > 0 {
            let cur = current[abbr] ?? 0
            next[abbr] = (cur + guaranteed) % count
        }
        return next
    }

    /// The content-type chip → which layouts it admits (Change 3). Mirrors the Feed's
    /// classifier but adds `.videos`, and routes `.socialVideo` to Videos (the Feed
    /// counts it as Social) — a deliberate divergence: on Home, a clip is a video.
    static func passes(_ card: ContentCard, filter: HomeContentFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .videos:
            switch card.layout {
            case .youtube, .socialVideo: return true
            default: return false
            }
        case .news:
            return card.layout == .newsArticle
        case .social:
            switch card.layout {
            case .blueskyTeamText, .blueskyTeamMedia, .blueskyReporter, .instagramFallback:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Helpers

    /// Newest-first, with an id-descending tiebreak so equal timestamps never reorder
    /// run-to-run (the determinism guarantee the tests lean on).
    private static func newestFirst(_ lhs: ContentCard, _ rhs: ContentCard) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
        return lhs.id > rhs.id
    }

    /// Rotate so element `offset` becomes first, wrapping around. `offset` is taken
    /// modulo count, so any value is safe.
    static func rotate<T>(_ array: [T], by offset: Int) -> [T] {
        guard !array.isEmpty else { return array }
        let n = ((offset % array.count) + array.count) % array.count
        guard n > 0 else { return array }
        return Array(array[n...] + array[..<n])
    }
}
