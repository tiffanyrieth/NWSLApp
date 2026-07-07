//
//  PlayoffModels.swift
//  NWSLApp
//
//  Pure value types + bracket math for the postseason Playoff feature (Standings tab).
//  NO UI, NO services, NO ESPN fetching — this file only knows how to turn a set of
//  scoreboard `Event`s + a seed map into a resolved bracket and a per-team "road to the
//  Championship". All of it is deterministic and unit-tested (PlayoffDerivationTests).
//
//  Design law: the bracket is DERIVED, never stored. Two data sources:
//   • Standings `rank` → seed → standard single-elim bracket position (1v8 / 2v7 / …),
//     which resolves EVERY slot (QF from seeds, later rounds from feeder winners). This
//     is exactly how NWSL seeds the postseason (higher seed hosts).
//   • ESPN's published `playoffs---*` events → overlay real scores / winner / date / TV /
//     venue / live-state onto the matching slot.
//  Format resilience: the round LIST is data-driven from ESPN slugs; the pairing TREE is
//  computed from the seed count. If the two disagree (a novel format — e.g. a play-in),
//  `formatConsistent` goes false + `tripwireReason` is set → callers show ONLY real data
//  (never a wrong projection) and log a Diagnostics alert. See PlayoffStore.
//

import Foundation

// MARK: - Round

/// One postseason round. Modeled as a struct (not a fixed enum) so a future ESPN slug —
/// e.g. `playoffs---play-in` — is representable and renders, rather than being dropped.
struct PlayoffRound: Hashable, Comparable, Identifiable {
    let slug: String        // ESPN season slug, e.g. "playoffs---quarterfinals"
    let order: Int          // progression rank (play-in < QF < SF < Championship)
    let title: String       // header caps, e.g. "QUARTERFINALS"
    let singular: String    // inline, e.g. "Quarterfinal" ("face … in the Quarterfinal")

    var id: String { slug }
    static func < (a: PlayoffRound, b: PlayoffRound) -> Bool { a.order < b.order }

    /// Known NWSL slugs. Order/titles come from here; an UNKNOWN playoff slug still builds
    /// (title derived from the slug, order pushed to the end) so nothing is silently
    /// dropped — the store's tripwire flags it for the owner.
    private static let known: [String: (order: Int, title: String, singular: String)] = [
        "playoffs---play-in":        (0, "PLAY-IN", "Play-In"),
        "playoffs---quarterfinals":  (1, "QUARTERFINALS", "Quarterfinal"),
        "playoffs---semifinals":     (2, "SEMIFINALS", "Semifinal"),
        "playoffs---championship":   (3, "CHAMPIONSHIP", "Championship"),
    ]

    /// Build a round from an ESPN slug. Returns nil for a non-playoff slug.
    init?(slug: String) {
        guard slug.hasPrefix("playoffs") else { return nil }
        self.slug = slug
        if let k = PlayoffRound.known[slug] {
            self.order = k.order; self.title = k.title; self.singular = k.singular
        } else {
            // Unknown future round: derive a readable label, sort last (before Champ? unknown
            // → after known non-champ), flag via the store tripwire.
            let tail = slug.replacingOccurrences(of: "playoffs---", with: "")
                .replacingOccurrences(of: "-", with: " ")
            self.order = 90
            self.title = tail.uppercased()
            self.singular = tail.capitalized
        }
    }

    /// True when this slug isn't one we recognize — the format-change tripwire.
    var isUnknown: Bool { PlayoffRound.known[slug] == nil }

    // Convenience constants (standard NWSL bracket). Force-unwrap is safe: these are literal
    // slugs that all start with "playoffs", so `init?(slug:)` can never return nil for them.
    static let quarterfinal = PlayoffRound(slug: "playoffs---quarterfinals")!
    static let semifinal    = PlayoffRound(slug: "playoffs---semifinals")!
    static let championship = PlayoffRound(slug: "playoffs---championship")!
}

// MARK: - Sides & matchups

/// One side of a matchup: a resolved team (with seed) or an unplaced TBD slot.
struct BracketSide: Hashable {
    let abbreviation: String?   // nil = TBD
    let seed: Int?
    let score: Int?             // nil until the game is played
    let isWinner: Bool          // ESPN `winner` flag (authoritative on PK results)

    static let tbd = BracketSide(abbreviation: nil, seed: nil, score: nil, isWinner: false)
    var isTBD: Bool { abbreviation == nil }
}

enum MatchState: String { case pre, live, post }

/// One playoff game: two sides + scheduling + state. `eventID` links to the ESPN event
/// so a tap resolves to MatchDetailView (nil for a purely-projected future matchup).
struct PlayoffMatchup: Identifiable, Hashable {
    let round: PlayoffRound
    let slotIndex: Int          // position within its round (stable ordering)
    let home: BracketSide       // higher seed hosts (real data confirms)
    let away: BracketSide
    let kickoff: Date?
    let broadcast: String?
    let venue: String?
    let state: MatchState
    let eventID: String?

    var id: String { "\(round.slug)#\(slotIndex)" }

    /// Both sides known (real teams, not TBD) — a "placed" matchup.
    var isResolved: Bool { !home.isTBD && !away.isTBD }
    /// A finished game.
    var isFinal: Bool { state == .post }

    var winnerAbbreviation: String? {
        if home.isWinner { return home.abbreviation }
        if away.isWinner { return away.abbreviation }
        return nil
    }
    /// The non-TBD side that is NOT the given abbreviation (this team's opponent), if placed.
    func opponent(of abbr: String) -> BracketSide? {
        if home.abbreviation == abbr { return away.isTBD ? nil : away }
        if away.abbreviation == abbr { return home.isTBD ? nil : home }
        return nil
    }
    func contains(_ abbr: String) -> Bool { home.abbreviation == abbr || away.abbreviation == abbr }
}

// MARK: - Seed tree (pure bracket structure)

/// A standard single-elimination bracket for a power-of-two seed count. Produces the
/// first-round seed pairings and, for every later round, which two prior-round slots feed
/// each slot (adjacent pairing after the canonical seed order). For 8: first round order
/// [1,8,4,5,2,7,3,6] → QF pairs (1,8)(4,5)(2,7)(3,6); SF feeders (0,1)(2,3); Final (0,1).
struct SeedTree {
    let teamCount: Int
    let roundCount: Int
    /// firstRoundSeeds[i] = the (higherSeed, lowerSeed) pair for first-round slot i.
    let firstRoundSeeds: [(Int, Int)]
    /// feeders[r][i] = the two slot indices in round r-1 that feed round-r slot i.
    /// Index 0 == first round (no feeders); feeders[0] is empty.
    let feeders: [[(Int, Int)]]

    init(teamCount: Int) {
        // Snap to the nearest power of two ≥ teamCount (defensive; NWSL is 8).
        var n = 2
        while n < max(2, teamCount) { n *= 2 }
        self.teamCount = n
        self.roundCount = Int(log2(Double(n)))

        // Canonical bracket seed order (recursive standard seeding).
        var order = [1, 2]
        while order.count < n {
            let cap = order.count * 2
            var next: [Int] = []
            for s in order { next.append(s); next.append(cap + 1 - s) }
            order = next
        }
        // First-round matchups = consecutive pairs; home = higher seed (lower number).
        var first: [(Int, Int)] = []
        var i = 0
        while i < order.count { first.append((min(order[i], order[i+1]), max(order[i], order[i+1]))); i += 2 }
        self.firstRoundSeeds = first

        // Later rounds: slot j fed by prior slots (2j, 2j+1).
        var f: [[(Int, Int)]] = [[]]
        var slots = first.count
        while slots > 1 {
            let nextSlots = slots / 2
            f.append((0..<nextSlots).map { (2*$0, 2*$0 + 1) })
            slots = nextSlots
        }
        self.feeders = f
    }

    var matchupsPerRound: [Int] { // round 0 = first round … last = championship (1)
        var counts = [firstRoundSeeds.count]
        while counts.last! > 1 { counts.append(counts.last! / 2) }
        return counts
    }
}

// MARK: - Resolved bracket

struct PlayoffBracket {
    let rounds: [PlayoffRound]                       // ordered, first → championship (== tree levels)
    let matchups: [PlayoffRound: [PlayoffMatchup]]   // resolved + projected, padded to full width
    let seeds: [String: Int]                         // abbr → seed (from standings rank)
    let teamCount: Int
    let tree: SeedTree                               // authoritative pairing structure for projection
    /// False when ESPN's published structure doesn't match the seed-derived tree (a novel
    /// format). Callers then suppress forward projections and show only real published data.
    let formatConsistent: Bool
    let tripwireReason: String?

    var championship: PlayoffMatchup? { rounds.last.flatMap { matchups[$0]?.first } }
    func matchups(in round: PlayoffRound) -> [PlayoffMatchup] { matchups[round] ?? [] }

    /// Abbreviations still alive (not eliminated). A team is alive if it hasn't lost a played game.
    func isAlive(_ abbr: String) -> Bool {
        guard seeds[abbr] != nil else { return false }
        for r in rounds {
            for m in matchups(in: r) where m.isFinal && m.contains(abbr) {
                if m.winnerAbbreviation != abbr { return false }
            }
        }
        return true
    }

    /// The round in which `abbr` was eliminated, if any (nil = still alive / not in bracket).
    func eliminationRound(_ abbr: String) -> PlayoffRound? {
        for r in rounds {
            for m in matchups(in: r) where m.isFinal && m.contains(abbr) && m.winnerAbbreviation != abbr {
                return r
            }
        }
        return nil
    }
}

// MARK: - Derivation (events + seeds → bracket)

extension PlayoffBracket {
    /// Build the bracket from ESPN playoff events + a seed map (abbr→rank from standings).
    /// `now` classifies matchup state where ESPN's own state is absent. Pure + deterministic.
    static func derive(from events: [Event], seeds: [String: Int], now: Date = Date()) -> PlayoffBracket {
        let playoffEvents = events.filter { $0.isPlayoffEvent }
        // Rounds present in the DATA, ordered — this is the format-resilient round list.
        let dataRounds = Set(playoffEvents.compactMap { $0.seasonSlug.flatMap(PlayoffRound.init(slug:)) })

        // teamCount from the first round's game count (× 2); default to 8 (standard NWSL).
        let firstRound = dataRounds.min()
        let firstRoundGames = firstRound.map { r in playoffEvents.filter { $0.seasonSlug == r.slug }.count } ?? 4
        let teamCount = max(2, firstRoundGames * 2)
        let tree = SeedTree(teamCount: teamCount)

        // The tree's canonical round list (first → championship), same length as tree rounds.
        // Map each tree round-level to a real PlayoffRound by matching the data's slugs in order.
        let orderedDataRounds = dataRounds.sorted()

        // seed → abbr (only the top `teamCount` seeds participate).
        var seedToAbbr: [Int: String] = [:]
        for (abbr, rank) in seeds where rank <= teamCount { seedToAbbr[rank] = abbr }

        // Index published events by round slug for overlay.
        var eventsByRound: [String: [Event]] = [:]
        for e in playoffEvents { eventsByRound[e.seasonSlug ?? "", default: []].append(e) }

        // Tripwire — fire ONLY on a genuine format mismatch, never on the normal case where
        // later rounds simply haven't been published yet (QF live, SF/Final still TBD).
        // Real mismatches: an unknown slug, MORE rounds than the seed tree expects, or a
        // published round carrying more games than its tree level allows (e.g. a play-in).
        var tripwire: String?
        if let unknown = orderedDataRounds.first(where: { $0.isUnknown }) {
            tripwire = "unrecognized playoff round slug '\(unknown.slug)'"
        } else if orderedDataRounds.count > tree.roundCount {
            tripwire = "published \(orderedDataRounds.count) rounds, seed tree expects \(tree.roundCount) (teamCount \(teamCount))"
        } else {
            for (i, r) in orderedDataRounds.enumerated() where i < tree.matchupsPerRound.count {
                let published = eventsByRound[r.slug]?.count ?? 0
                if published > tree.matchupsPerRound[i] {
                    tripwire = "\(r.title) has \(published) games, seed tree expects ≤ \(tree.matchupsPerRound[i])"
                    break
                }
            }
        }

        // Build each round's matchups by tree level. `winnersByLevel[level]` = winner abbr per slot.
        var matchupsByRound: [PlayoffRound: [PlayoffMatchup]] = [:]
        var winnersByLevel: [[String?]] = []

        for level in 0..<tree.roundCount {
            // The PlayoffRound to display for this tree level (fall back to a synthetic if the
            // data is short — keeps projection working even before a round is published).
            let round: PlayoffRound = level < orderedDataRounds.count
                ? orderedDataRounds[level]
                : Self.fallbackRound(forLevel: level, tree: tree)

            let slotCount = tree.matchupsPerRound[level]
            var rowsThisLevel: [PlayoffMatchup] = []
            var winnersThisLevel: [String?] = []

            for slot in 0..<slotCount {
                // Resolve the two sides for this slot.
                let (homeAbbr, awayAbbr): (String?, String?)
                if level == 0 {
                    let pair = tree.firstRoundSeeds[slot]
                    homeAbbr = seedToAbbr[pair.0]; awayAbbr = seedToAbbr[pair.1]
                } else {
                    let feed = tree.feeders[level][slot]
                    homeAbbr = winnersByLevel[level-1][safe: feed.0] ?? nil
                    awayAbbr = winnersByLevel[level-1][safe: feed.1] ?? nil
                }

                // Find a published event whose two teams match this slot's teams (in any order).
                let published = eventsByRound[round.slug]?.first { ev in
                    let a = ev.homeCompetitor?.team?.abbreviation
                    let b = ev.awayCompetitor?.team?.abbreviation
                    guard let a, let b else { return false }
                    let want = Set([homeAbbr, awayAbbr].compactMap { $0 })
                    return want.isEmpty ? false : Set([a, b]) == want
                }

                let matchup = Self.buildMatchup(round: round, slot: slot,
                                                homeAbbr: homeAbbr, awayAbbr: awayAbbr,
                                                seeds: seeds, event: published, now: now)
                rowsThisLevel.append(matchup)
                winnersThisLevel.append(matchup.winnerAbbreviation)
            }
            matchupsByRound[round] = rowsThisLevel
            winnersByLevel.append(winnersThisLevel)
        }

        let rounds = matchupsByRound.keys.sorted()
        // Store ONLY the bracket participants' seeds (top `teamCount`), so `seeds[abbr] != nil`
        // means "is in the bracket" everywhere — a followed team that missed the playoffs
        // (e.g. a #11 seed) must not get a Your Path section.
        let bracketSeeds = seeds.filter { $0.value <= teamCount }
        return PlayoffBracket(rounds: rounds, matchups: matchupsByRound, seeds: bracketSeeds,
                              teamCount: teamCount, tree: tree, formatConsistent: tripwire == nil,
                              tripwireReason: tripwire)
    }

    /// Compose one matchup from resolved abbreviations + an optional published event.
    private static func buildMatchup(round: PlayoffRound, slot: Int,
                                     homeAbbr: String?, awayAbbr: String?,
                                     seeds: [String: Int], event: Event?, now: Date) -> PlayoffMatchup {
        // Higher seed hosts: if both seeds known, ensure the lower seed number is "home".
        var hAbbr = homeAbbr, aAbbr = awayAbbr
        if let hs = hAbbr.flatMap({ seeds[$0] }), let as_ = aAbbr.flatMap({ seeds[$0] }), as_ < hs {
            swap(&hAbbr, &aAbbr)
        }
        let state: MatchState = {
            switch event?.statusState { case "post": return .post; case "in": return .live; default: return .pre }
        }()
        func side(_ abbr: String?, competitor: Competitor?) -> BracketSide {
            guard let abbr else { return .tbd }
            return BracketSide(abbreviation: abbr, seed: seeds[abbr],
                               score: competitor?.score.flatMap { Int($0) },
                               isWinner: competitor?.winner == true)
        }
        // Map the event's competitors to our home/away by abbreviation (ESPN's home may differ).
        let evHome = event?.homeCompetitor, evAway = event?.awayCompetitor
        func competitor(for abbr: String?) -> Competitor? {
            guard let abbr else { return nil }
            if evHome?.team?.abbreviation == abbr { return evHome }
            if evAway?.team?.abbreviation == abbr { return evAway }
            return nil
        }
        return PlayoffMatchup(
            round: round, slotIndex: slot,
            home: side(hAbbr, competitor: competitor(for: hAbbr)),
            away: side(aAbbr, competitor: competitor(for: aAbbr)),
            kickoff: event?.kickoff, broadcast: event?.broadcastName, venue: event?.venueName,
            state: state, eventID: event?.id
        )
    }

    /// A stand-in round when the data hasn't published this level yet (keeps SF/Final projecting).
    private static func fallbackRound(forLevel level: Int, tree: SeedTree) -> PlayoffRound {
        // For the standard 3-round NWSL bracket, levels map QF/SF/Championship.
        let standard = [PlayoffRound.quarterfinal, .semifinal, .championship]
        if tree.roundCount == 3, level < standard.count { return standard[level] }
        // Generic fallback: synthesize a slug so it still renders/sorts.
        return PlayoffRound(slug: "playoffs---round-\(level)") ?? .championship
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Your Path (per-team road to the Championship)

/// One step in a followed team's path: the round, the matchup (real or projected), the
/// team's state at that step, and the plain-language "Win → …" context.
struct PlayoffPathStep: Identifiable {
    enum Progress { case done, current, future }
    let round: PlayoffRound
    let matchup: PlayoffMatchup?     // known matchup at this step (may be TBD-sided if projected)
    let progress: Progress
    let winContext: String?          // "face Portland in the Semifinal" / "advance to the Championship"
    var id: String { round.slug }
}

extension PlayoffBracket {
    /// The tree level (0 = first round) at which `abbr` currently sits: the deepest round it's
    /// placed in. nil if not in the bracket.
    func frontierLevel(forAbbreviation abbr: String) -> Int? {
        guard seeds[abbr] != nil else { return nil }
        var frontier: Int?
        for (level, round) in rounds.enumerated() where matchups(in: round).contains(where: { $0.contains(abbr) }) {
            frontier = level
        }
        return frontier
    }

    /// The team's slot index within a given level (nil if not placed there).
    private func slot(forAbbreviation abbr: String, atLevel level: Int) -> Int? {
        guard level < rounds.count else { return nil }
        return matchups(in: rounds[level]).firstIndex { $0.contains(abbr) }
    }

    /// The ordered road for a followed team from its CURRENT round to the Championship.
    /// Returns nil if the team isn't in the bracket. On a format-mismatch the forward
    /// projection is suppressed (only real placed matchups are shown, no guessed opponent).
    func path(forAbbreviation abbr: String) -> [PlayoffPathStep]? {
        guard let frontier = frontierLevel(forAbbreviation: abbr) else { return nil }
        let eliminatedAt = eliminationRound(abbr)
        var steps: [PlayoffPathStep] = []

        // An eliminated team's road ends at its exit round (no phantom future steps); an alive
        // team's runs from its current round to the Championship.
        let end = eliminatedAt != nil ? frontier + 1 : rounds.count
        for level in frontier..<end {
            let round = rounds[level]
            let placed = matchups(in: round).first { $0.contains(abbr) }

            let progress: PlayoffPathStep.Progress
            if let elim = eliminatedAt, round > elim { progress = .future }
            else if let placed, placed.isFinal { progress = .done }
            else if level == frontier { progress = .current }
            else { progress = .future }

            // Win → context: only while alive, format consistent, and a next round exists.
            var win: String?
            if formatConsistent, eliminatedAt == nil, level + 1 < rounds.count {
                win = winContext(forAbbreviation: abbr, atLevel: level)
            }
            steps.append(PlayoffPathStep(round: round, matchup: placed, progress: progress, winContext: win))
        }
        return steps
    }

    /// The round the team is currently contesting (its frontier round), if any.
    func currentRound(forAbbreviation abbr: String) -> PlayoffRound? {
        frontierLevel(forAbbreviation: abbr).map { rounds[$0] }
    }

    /// Plain-language "Win → …" for the team after winning the round at `level` — computed
    /// from the TREE (authoritative), not by guessing. Names the opponent if decided, else the
    /// two teams that could produce it.
    private func winContext(forAbbreviation abbr: String, atLevel level: Int) -> String? {
        guard level + 1 < rounds.count, level + 1 < tree.feeders.count else { return nil }
        guard let mySlot = slot(forAbbreviation: abbr, atLevel: level) else { return nil }
        let nextRound = rounds[level + 1]
        // Which next-level slot does mySlot feed, and what's the sibling feeder slot?
        guard let nextSlot = tree.feeders[level + 1].firstIndex(where: { $0.0 == mySlot || $0.1 == mySlot })
        else { return "advance to the \(nextRound.singular)" }
        let feed = tree.feeders[level + 1][nextSlot]
        let siblingSlot = feed.0 == mySlot ? feed.1 : feed.0

        let siblingMatchups = matchups(in: rounds[level])
        guard siblingSlot < siblingMatchups.count else { return "advance to the \(nextRound.singular)" }
        let sibling = siblingMatchups[siblingSlot]

        if let w = sibling.winnerAbbreviation {
            return "face \(w) in the \(nextRound.singular)"          // opponent decided
        }
        if let h = sibling.home.abbreviation, let a = sibling.away.abbreviation {
            return "face the winner of \(h) vs \(a) in the \(nextRound.singular)"
        }
        return "advance to the \(nextRound.singular)"
    }

    // MARK: Multi-team storyline

    /// If two followed teams could still meet, the round + phrase for it. Both must be alive
    /// and land in the same slot at some future round per the tree. nil otherwise.
    func storyline(between a: String, and b: String) -> (round: PlayoffRound, text: String)? {
        guard formatConsistent, isAlive(a), isAlive(b),
              let la = frontierLevel(forAbbreviation: a), let lb = frontierLevel(forAbbreviation: b),
              let sa = slot(forAbbreviation: a, atLevel: la), let sb = slot(forAbbreviation: b, atLevel: lb)
        else { return nil }
        // Already facing each other (same current matchup) → they can't BOTH win, no storyline.
        if la == lb, sa == sb { return nil }
        // Walk both slots up the tree; the first common (level, slot) is where they'd meet.
        let pathA = ascend(fromLevel: la, slot: sa)
        let pathB = ascend(fromLevel: lb, slot: sb)
        for (lvl, slt) in pathA where pathB.contains(where: { $0.0 == lvl && $0.1 == slt }) {
            guard lvl < rounds.count else { return nil }
            let r = rounds[lvl]
            return (r, "If both win, \(a) and \(b) would meet in the \(r.singular).")
        }
        return nil
    }

    /// Slots a starting (level,slot) would occupy up through the championship.
    private func ascend(fromLevel level: Int, slot: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        var lvl = level, slt = slot
        while lvl + 1 < rounds.count, lvl + 1 < tree.feeders.count {
            guard let nextSlot = tree.feeders[lvl + 1].firstIndex(where: { $0.0 == slt || $0.1 == slt })
            else { break }
            result.append((lvl + 1, nextSlot))
            lvl += 1; slt = nextSlot
        }
        return result
    }
}

