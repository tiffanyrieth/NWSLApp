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
        let events: [Event]
    }

    /// The three always-visible filter tabs (per the schedule design spec).
    enum Filter: String, CaseIterable, Identifiable {
        case nwsl, myTeams, international
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nwsl:          return "NWSL"
            case .myTeams:       return "My teams"
            case .international: return "International"
            }
        }
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

    /// Day-grouped sections for a given filter tab.
    func sections(for filter: Filter) -> [DaySection] {
        sections(from: events(for: filter))
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

    private func events(for filter: Filter) -> [Event] {
        let all = store?.events ?? []
        switch filter {
        case .nwsl:
            // Every match on the scoreboard today is NWSL regular season.
            return all
        case .myTeams:
            let abbreviations = followedAbbreviations
            guard !abbreviations.isEmpty else { return [] }
            return all.filter { event in
                if let home = event.homeCompetitor?.team?.abbreviation,
                   abbreviations.contains(home) { return true }
                if let away = event.awayCompetitor?.team?.abbreviation,
                   abbreviations.contains(away) { return true }
                return false
            }
        case .international:
            // The international / national-team-window bucket. The ESPN scoreboard
            // Event carries no competition field yet, so nothing qualifies and the
            // view shows the designed "coming soon" empty state. When competition-
            // aware schedule data lands (FollowedCompetition + a competition id on
            // Event), filter here — NWSL stays the domestic league, International the
            // cups/windows; they never overlap (so this is NOT a duplicate of NWSL).
            return all.filter(isInternational)
        }
    }

    /// Whether a match belongs to the International bucket. No competition metadata
    /// rides on the scoreboard Event yet, so this is always false today — the hook
    /// that lights up when competition-aware data lands.
    private func isInternational(_ event: Event) -> Bool {
        false
    }

    private func sections(from events: [Event]) -> [DaySection] {
        let today = todayKey()
        let grouped = Dictionary(grouping: events.filter { $0.dayKey != nil }) { $0.dayKey! }
        return grouped
            .map { (key, events) in
                DaySection(
                    id: key,
                    label: label(forDayKey: key),
                    isToday: key == today,
                    events: events.sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }
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

    // Today's section if present, otherwise the first future section, within the
    // given filter. Returns nil if everything in that filter is in the past.
    // Used both for the one-time scroll-to-today and to re-anchor on filter change.
    func initialScrollSectionID(for filter: Filter) -> String? {
        let today = todayKey()
        let ids = sections(for: filter).map(\.id)
        if ids.contains(today) { return today }
        return ids.first(where: { $0 > today })
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
