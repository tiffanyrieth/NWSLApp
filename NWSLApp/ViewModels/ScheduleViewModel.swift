//
//  ScheduleViewModel.swift
//  NWSLApp
//
//  Owns the *presentation* of ScheduleView: it groups the season's events into
//  local-day sections, labels them, and computes the section the view should
//  scroll to on first appearance (today, or the next upcoming matchday).
//
//  The season's events live in the shared MatchStore (injected app-wide), and
//  this view model derives its sections from that store — so the Schedule screen
//  and the Team page read the exact same data. The store is handed in by the
//  view (`store = ...`) before the first load, because a SwiftUI `@State` view
//  model can't read the environment at init.
//
//  The club directory it needs — to resolve the user's followed club IDs
//  (FollowingStore holds IDs) into team abbreviations for the "My teams" filter —
//  comes from the shared ClubStore (also handed in by the view), the same
//  directory Teams/Home/Feed read. One fetch, many readers (CLAUDE.md
//  What's-Next #15); a failed directory fetch now surfaces a real error + retry
//  on the My-teams path instead of an infinite spinner (#16).
//

import Foundation

@Observable
final class ScheduleViewModel {
    struct DaySection: Identifiable {
        let id: String       // "yyyy-MM-dd"
        let label: String    // "Today" or "Saturday, June 6"
        let isToday: Bool     // drives the date-header TODAY chip + white treatment
        let matches: [ScheduledMatch]   // tagged so the card can label non-NWSL competitions
    }

    /// One postseason round as a schedule section — the playoff merge (owner decision: the
    /// bracket IS the schedule). Placed games sort CHRONOLOGICALLY (not by bracket slot);
    /// TBD placeholders follow.
    struct RoundSection: Identifiable {
        enum Status { case upcoming, live, complete }
        let round: PlayoffRound
        let status: Status
        let dateRangeLabel: String?   // "Nov 4–11" from kickoffs, else the season window
        let matchups: [PlayoffMatchup]
        var id: String { round.slug }
    }

    /// The schedule list: chronological day sections, then the postseason round sections at
    /// the season's end (real, or the year-round TBD tail).
    enum ScheduleSection: Identifiable {
        case day(DaySection)
        case round(RoundSection)
        var id: String {
            switch self {
            case .day(let d): return "day-\(d.id)"
            case .round(let r): return "round-\(r.id)"
            }
        }
    }

    /// The filter chips. NWSL + My teams always; "Playoffs" appears when 2+ teams have
    /// mathematically clinched (or the bracket is seeded) — see `visibleFilters`.
    enum Filter: String, CaseIterable, Identifiable {
        case nwsl, myTeams, playoffs
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nwsl:     return "NWSL"
            case .myTeams:  return "My teams"
            case .playoffs: return "Playoffs"
            }
        }
    }

    /// Chips actually shown — the Playoffs chip is clinch/seeding-gated, so don't iterate
    /// `Filter.allCases` blindly in the chip bar.
    var visibleFilters: [Filter] {
        (playoffs?.isChipVisible ?? false) ? [.nwsl, .myTeams, .playoffs] : [.nwsl, .myTeams]
    }

    // Set by ScheduleView from the environment before the first load. Optional
    // because the view model is constructed before the environment is readable;
    // until it's wired, the screen simply reads as `.idle`.
    var store: MatchStore?
    // The shared club directory, handed in by the view: used only to map followed
    // IDs → abbreviations for the "My teams" filter.
    var clubStore: ClubStore?
    // Also handed in by the view: the personalization lens for the "My teams"
    // filter (which followed clubs are playing).
    var following: FollowingStore?
    // The postseason state (bracket / windows / clinch) — drives the round sections and the
    // Playoffs chip. Handed in by the view like the other shared stores.
    var playoffs: PlayoffStore?

    private let calendar: Calendar
    private let now: () -> Date

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
    }

    /// The shared club directory (empty unless the store is `.loaded`). Used only
    /// to resolve followed IDs → abbreviations for the "My teams" filter.
    var clubs: [Club] { clubStore?.clubs ?? [] }

    // Proxy the shared store's state so ScheduleView's `switch` over
    // idle/loading/loaded/error is unchanged.
    var state: MatchStore.State { store?.state ?? .idle }

    func load() async {
        await store?.load()
        await clubStore?.load()
    }

    /// The full schedule for a filter tab: day sections + (NWSL chip) the postseason round
    /// sections at the end. My teams keeps playoff games inline as day cards — it's the
    /// personal chronological timeline; the league-structure view lives on the NWSL chip.
    func scheduleSections(for filter: Filter) -> [ScheduleSection] {
        switch filter {
        case .nwsl:
            let rounds = roundSections()
            let days = sections(from: matches(for: filter), excludingPlayoffs: !rounds.isEmpty)
            return days.map { .day($0) } + rounds.map { .round($0) }
        case .myTeams, .playoffs:
            return sections(from: matches(for: filter), excludingPlayoffs: false).map { .day($0) }
        }
    }

    /// The round sections for the Playoffs chip's clinch-window "road ahead" tail.
    func scheduleRoundSectionsForPlayoffsChip() -> [RoundSection] { roundSections() }

    /// The postseason round sections: the derived bracket when seeded, else the year-round TBD
    /// tail from ESPN's published windows. Empty only when the playoff pipeline is unavailable
    /// (windows fetch failed AND no bracket) — playoff games then fall back to day cards above
    /// (honest degrade; they never vanish).
    private func roundSections() -> [RoundSection] {
        guard let playoffs else { return [] }

        if let bracket = playoffs.bracket {
            return bracket.rounds.map { round in
                let all = bracket.matchups(in: round)
                let placed = all.filter { $0.isResolved }
                    .sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }
                let tbd = all.filter { !$0.isResolved }
                let status: RoundSection.Status = {
                    if !all.isEmpty, all.allSatisfy({ $0.isFinal }) { return .complete }
                    if all.contains(where: { $0.state == .live }) { return .live }
                    return .upcoming
                }()
                return RoundSection(round: round, status: status,
                                    dateRangeLabel: dateRange(placed.compactMap(\.kickoff))
                                        ?? windowRange(for: round),
                                    matchups: placed + tbd)
            }
        }

        // Pre-seeding: the TBD tail from the season windows.
        return playoffs.upcomingRounds.map { upcoming in
            let placeholders = (0..<upcoming.slotCount).map { slot in
                PlayoffMatchup(round: upcoming.round, slotIndex: slot,
                               home: .tbd, away: .tbd,
                               kickoff: nil, broadcast: nil, venue: nil,
                               state: .pre, eventID: nil)
            }
            return RoundSection(round: upcoming.round, status: .upcoming,
                                dateRangeLabel: dateRange([upcoming.start, upcoming.end].compactMap { $0 }),
                                matchups: placeholders)
        }
    }

    /// "Nov 4–11" (same-month), "Nov 28–Dec 2" (cross-month), or "Nov 8" (single day).
    private func dateRange(_ dates: [Date]) -> String? {
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let f = DateFormatter(); f.locale = .current; f.timeZone = .current; f.dateFormat = "MMM d"
        if calendar.isDate(first, inSameDayAs: last) { return f.string(from: first) }
        let d = DateFormatter(); d.locale = .current; d.timeZone = .current; d.dateFormat = "d"
        let sameMonth = calendar.component(.month, from: first) == calendar.component(.month, from: last)
        return sameMonth ? "\(f.string(from: first))–\(d.string(from: last))"
                         : "\(f.string(from: first))–\(f.string(from: last))"
    }

    private func windowRange(for round: PlayoffRound) -> String? {
        guard let window = playoffs?.windows.first(where: { $0.slug == round.slug }) else { return nil }
        return dateRange([window.start, window.end].compactMap { $0 })
    }

    /// Followed clubs' team abbreviations — the join key for the "My teams"
    /// filter (scoreboard competitors carry an abbreviation, not a club id).
    var followedAbbreviations: Set<String> {
        guard let following else { return [] }
        return Set(
            clubs.filter { following.followedIDs.contains($0.id) }.map(\.abbreviation)
        )
    }

    /// True when the user follows clubs but the directory is still loading — lets
    /// the view show a spinner instead of a misleading "follow teams" prompt. A
    /// *failed* directory load is NOT "resolving" (see `clubsError`): it gets a
    /// real error + retry instead of an endless spinner (#16).
    var isResolvingFollowedTeams: Bool {
        guard !(following?.followedIDs.isEmpty ?? true) else { return false }
        switch clubStore?.state {
        case .loaded, .error: return false
        default: return true   // idle / loading / not-yet-wired
        }
    }

    /// The directory-load error message, if the club fetch failed — surfaced on
    /// the "My teams" path so a failed directory shows a retry, not "No matches".
    var clubsError: String? {
        if case .error(let message) = clubStore?.state { return message }
        return nil
    }

    // MARK: - Filtering

    private func matches(for filter: Filter) -> [ScheduledMatch] {
        let all = store?.matches ?? []
        switch filter {
        case .nwsl, .playoffs:
            // The home-league chip shows NWSL competitions — the regular season/playoffs
            // AND the NWSL Challenge Cup (an NWSL competition, even though it's excluded
            // from the league table). The Champions Cup / national-team matches stay out.
            // (.playoffs shows its own content in the view; the match set is the NWSL one.)
            return all.filter { $0.competition.inNWSLScheduleView }
        case .myTeams:
            // "Everything you care about", woven into one timeline:
            //  • National-team matches — already filtered to FOLLOWED teams upstream
            //    in MatchStore, so always keep them.
            //  • NWSL + Champions Cup matches — keep only those involving a FOLLOWED
            //    club (the Champions Cup global toggle gates the FETCH; this narrows
            //    its matches to the clubs you actually follow).
            let abbreviations = followedAbbreviations
            return all.filter { match in
                if case .international = match.competition { return true }
                let home = match.event.homeCompetitor?.team?.abbreviation
                let away = match.event.awayCompetitor?.team?.abbreviation
                return (home.map(abbreviations.contains) ?? false)
                    || (away.map(abbreviations.contains) ?? false)
            }
        }
    }

    /// `excludingPlayoffs` — when the round sections are rendered, playoff games live THERE
    /// (round-grouped), so day-grouping drops them to avoid double-rendering. When the playoff
    /// pipeline is unavailable they stay here as plain day cards (never vanish).
    private func sections(from matches: [ScheduledMatch], excludingPlayoffs: Bool) -> [DaySection] {
        let today = todayKey()
        let visible = excludingPlayoffs ? matches.filter { !$0.event.isPlayoffEvent } : matches
        let grouped = Dictionary(grouping: visible.filter { $0.event.dayKey != nil }) { $0.event.dayKey! }
        return grouped
            .map { (key, dayMatches) in
                DaySection(
                    id: key,
                    label: label(forDayKey: key),
                    isToday: key == today,
                    matches: dayMatches.sorted {
                        ($0.event.kickoff ?? .distantFuture) < ($1.event.kickoff ?? .distantFuture)
                    }
                )
            }
            .sorted { $0.id < $1.id }
    }

    // True once the schedule has finished loading. Lets the view drive its
    // one-time scroll-to-today off the clean idle/loading -> loaded edge,
    // rather than watching `sections.first?.id` (which is the season opener
    // and stays identical across reloads, so it's a fragile trigger).
    var isLoaded: Bool {
        if case .loaded = store?.state { return true }
        return false
    }

    // The EVENT the schedule rests at on open (the rest "boundary"): the most recent
    // game that has already kicked off — so its card sits at the very top with the
    // upcoming fixtures (today's date bar + future matchdays) just below, making it
    // obvious history is scrollable above. If every game in the filter is still
    // upcoming (season start), the first one; nil if the filter has no dated games.
    // Computed live from `now()`, so it advances on its own. Anchored via
    // ScrollViewReader to the card's id (`event.id`), so the last result is the first
    // visible row — not the season opener, and not today's header flush at the top.
    func initialScrollEventID(for filter: Filter) -> String? {
        let dated = matches(for: filter)
            .compactMap { match -> (String, Date)? in match.event.kickoff.map { (match.id, $0) } }
            .sorted { $0.1 < $1.1 }
        guard !dated.isEmpty else { return nil }
        let cutoff = now()
        if let lastStarted = dated.last(where: { $0.1 <= cutoff }) { return lastStarted.0 }
        return dated.first?.0
    }

    // MARK: - Private

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now())
    }

    private func label(forDayKey key: String) -> String {
        if key == todayKey() { return "Today" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }

        let display = DateFormatter()
        display.locale = .current
        display.timeZone = .current
        display.dateFormat = "EEEE, MMMM d"   // "Friday, June 6" (per the spec)
        return display.string(from: date)
    }
}
