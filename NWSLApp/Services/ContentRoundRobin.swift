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
//  Representation is COUNT-BASED, age-agnostic, and volume-blind: each followed club
//  contributes up to `slotsPerClub` of its most-recent posts (regardless of age), and
//  the rounds interleave one-per-club so every club gets an EQUAL allowance. A club
//  posting 40×/week can never exceed its allowance or steal a quieter club's slot — and
//  a club that's been silent for months still surfaces its most-recent posts as its
//  share. There is deliberately NO time window and NO chronological "fill the rest from
//  whoever posted most" pass (that rewarded volume — the LinkedIn failure mode).
//
//  Everything here is PURE + deterministic (no Date(), no randomness) so it unit-tests
//  like BracketScoring / PredictionScoring: the caller (HomeViewModel / FeedViewModel)
//  scopes the cards to followed clubs and hands them in. The content-type classifier
//  lives here too — it's content categorisation, the same family of logic.
//

import Foundation

enum ContentRoundRobin {

    /// The balanced module plus how many eligible cards didn't fit — the latter
    /// drives the "See more from your teams →" link.
    struct Result: Equatable {
        let cards: [ContentCard]
        let overflowCount: Int
    }

    /// First-load-only article preference (surface club-site articles for the weekly/biweekly
    /// opener). When passed to `balanced`, lead-eligible articles are preferred WITHIN each
    /// club's own slot allowance (never changing slot count or cross-club balance) and floated
    /// to the top positions. Gated on a RELATIVE staleness guard (NO time window): an article is
    /// lead-eligible unless it's `staleRatio`× older than the freshest non-article content, with
    /// `floorDays` only as the ratio's denominator floor — no card is ever filtered by age.
    /// `now` is injected so the whole thing stays pure + deterministic to unit-test.
    struct ArticlePriority {
        var now: Date
        var quota: Int = 3          // ≤ N lead-eligible articles preferred per club's slots ("2-3")
        var staleRatio: Double = 4
        var floorDays: Double = 14
        var maxLead: Int = 3        // ≤ N articles floated to the very front (round-robin)
    }

    /// Per-club slot allowance for Home's Module-1 PREVIEW, scaled by follow count so
    /// the preview stays bounded while the share stays equal. A single club has no
    /// fairness to enforce, so it gets a full preview; the rest split an equal
    /// allowance. The remainder beyond a club's allowance overflows to "See more →".
    static func homeSlotsPerClub(_ teamCount: Int) -> Int {
        switch teamCount {
        case ...1:  return 12   // one club — no fairness needed, show a full preview
        case 2:     return 6
        case 3...4: return 4
        case 5...7: return 3
        default:    return 2    // 8+ clubs
        }
    }

    /// Per-club slot allowance for the FEED club lane — larger than Home's preview
    /// (the Feed is the dedicated stream, not a teaser), still equal per club so a
    /// chatty club never dominates.
    static func feedSlotsPerClub(_ teamCount: Int) -> Int {
        switch teamCount {
        case ...2:  return 12
        case 3...4: return 8
        case 5...7: return 6
        default:    return 4    // 8+ clubs
        }
    }

    /// Balance cards across followed clubs by EQUAL count — volume-blind, age-agnostic.
    ///
    /// - cards: scoped to followed clubs by the caller (no freshness filter — there is
    ///   no time window anymore).
    /// - followedAbbreviations: the followed clubs in a STABLE order (alphabetical),
    ///   so the round-robin interleave is deterministic.
    /// - slotsPerClub: the equal per-club allowance (`homeSlotsPerClub` /
    ///   `feedSlotsPerClub`). Each club shows `min(slotsPerClub, itsCount)` of its
    ///   most-recent posts; anything beyond is overflow (never another club's slot).
    /// - windowOffsets: per-team rotation offset for pull-to-refresh (see
    ///   `advancedOffsets`); 0 = newest.
    static func balanced(
        cards: [ContentCard],
        followedAbbreviations: [String],
        slotsPerClub: Int,
        windowOffsets: [String: Int] = [:],
        articlePriority: ArticlePriority? = nil
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

        // Lead-eligibility (first-load article preference only): an article is eligible unless
        // it's dramatically older than the freshest NON-article content — a RELATIVE guard, not
        // a date cutoff (the floor is only the ratio's denominator; no card is filtered by age).
        // When `articlePriority` is nil this is a no-op, so the default path is unchanged.
        let isArticle: (ContentCard) -> Bool = { $0.layout == .newsArticle }
        let leadEligible: (ContentCard) -> Bool
        if let ap = articlePriority {
            if let freshestOther = cards.lazy.filter({ !isArticle($0) }).map(\.timestamp).max() {
                let denom = max(ap.now.timeIntervalSince(freshestOther), ap.floorDays * 86_400)
                let maxAge = ap.staleRatio * denom
                leadEligible = { isArticle($0) && ap.now.timeIntervalSince($0.timestamp) <= maxAge }
            } else {
                leadEligible = isArticle      // no non-article content to defer to → all eligible
            }
        } else {
            leadEligible = { _ in false }
        }

        // 2. Per club: take its most-recent `slotsPerClub` in STRICT recency order — UNLESS
        //    article priority is on (first load), in which case prefer up to `quota` lead-
        //    eligible articles FIRST within the club's OWN allowance, then fill the rest by
        //    recency. Same slot COUNT, same cross-club balance, still volume-blind — only WHICH
        //    of a club's own sources fill its slots changes (articles over IG/YT when fresh
        //    enough). A stale article gets no preference → it competes by plain recency.
        //    `rotate` shifts the pull-to-refresh window (a no-op at offset 0).
        var slotsByTeam: [String: [ContentCard]] = [:]
        for abbr in followedAbbreviations {
            let all = byTeam[abbr] ?? []
            guard !all.isEmpty else { continue }
            let recencyOrdered = rotate(all, by: windowOffsets[abbr] ?? 0)
            if let ap = articlePriority {
                let articles = recencyOrdered.filter(leadEligible)
                let take = min(ap.quota, slotsPerClub, articles.count)
                let chosen = Array(articles.prefix(take))
                let chosenIDs = Set(chosen.map(\.id))
                let fill = recencyOrdered.filter { !chosenIDs.contains($0.id) }.prefix(max(0, slotsPerClub - take))
                slotsByTeam[abbr] = chosen + Array(fill)
            } else {
                slotsByTeam[abbr] = Array(recencyOrdered.prefix(slotsPerClub))
            }
        }

        // 3. Interleave the per-club slots round-robin: round 0 is one card per club
        //    (so a quiet club sits at the top beside a loud one), round 1 the seconds,
        //    etc. A club that runs out simply stops contributing — the others continue,
        //    but no club exceeds its own `slotsPerClub` allowance.
        var shown: [ContentCard] = []
        var seen = Set<String>()
        var round = 0
        var addedThisRound = true
        while addedThisRound {
            addedThisRound = false
            for abbr in followedAbbreviations {
                guard let slots = slotsByTeam[abbr], round < slots.count else { continue }
                let card = slots[round]
                if seen.insert(card.id).inserted { shown.append(card) }
                addedThisRound = true
            }
            round += 1
        }

        // 4. First-load article reorder: float up to `maxLead` lead-eligible articles to the
        //    very front, round-robined one-per-club-per-round (so 2+ clubs interleave and a
        //    no-article club's content doesn't sit between two articles). Everything else keeps
        //    its order — the SAME multiset, just reordered (per-club counts untouched).
        if let ap = articlePriority {
            var articlesByClub: [String: [ContentCard]] = [:]
            for card in shown where leadEligible(card) {
                if let abbr = card.teamAbbreviation { articlesByClub[abbr, default: []].append(card) }
            }
            var lead: [ContentCard] = []
            var r = 0
            var more = true
            while more && lead.count < ap.maxLead {
                more = false
                for abbr in followedAbbreviations {
                    guard let arr = articlesByClub[abbr], r < arr.count else { continue }
                    lead.append(arr[r])
                    more = true
                    if lead.count >= ap.maxLead { break }
                }
                r += 1
            }
            let leadIDs = Set(lead.map(\.id))
            shown = lead + shown.filter { !leadIDs.contains($0.id) }
        }

        let totalEligible = byTeam.values.reduce(0) { $0 + $1.count }
        return Result(cards: shown, overflowCount: max(0, totalEligible - shown.count))
    }

    /// Pull-to-refresh rotation: when no NEW content arrived, shift each team's window
    /// forward by one page (`pageSize`, = the per-club slot allowance), wrapping, so the
    /// user discovers cards they hadn't seen — natural forward motion, never random.
    /// `availableCounts` is each team's eligible-card count (the wrap modulus).
    static func advancedOffsets(
        current: [String: Int],
        availableCounts: [String: Int],
        pageSize: Int
    ) -> [String: Int] {
        var next = current
        for (abbr, count) in availableCounts where count > 0 {
            let cur = current[abbr] ?? 0
            next[abbr] = (cur + pageSize) % count
        }
        return next
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
