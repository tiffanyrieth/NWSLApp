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
//  It DOES make one small fetch of its own: the club directory, used only to
//  resolve the user's followed club IDs (FollowingStore holds IDs) into team
//  abbreviations for the "My teams" filter. (HomeViewModel/TeamsViewModel fetch
//  the same directory — a future shared ClubStore could consolidate the three;
//  see CLAUDE.md What's-Next.)
//

import Foundation

@Observable
final class ScheduleViewModel {
    struct DaySection: Identifiable {
        let id: String       // "yyyy-MM-dd"
        let label: String    // "Today" or "Saturday, June 6"
        let events: [Event]
    }

    /// The three always-visible filter tabs (per the schedule design spec).
    enum Filter: String, CaseIterable, Identifiable {
        case nwsl, myTeams, allMatches
        var id: String { rawValue }
        var title: String {
            switch self {
            case .nwsl:       return "NWSL"
            case .myTeams:    return "My teams"
            case .allMatches: return "All matches"
            }
        }
    }

    // Set by ScheduleView from the environment before the first load. Optional
    // because the view model is constructed before the environment is readable;
    // until it's wired, the screen simply reads as `.idle`.
    var store: MatchStore?
    // Also handed in by the view: the personalization lens for the "My teams"
    // filter (which followed clubs are playing).
    var following: FollowingStore?

    private let service: ESPNService
    private let calendar: Calendar
    private let now: () -> Date

    // Club directory, fetched once, used only to map followed IDs → abbreviations.
    private(set) var clubs: [Club] = []

    init(
        service: ESPNService = ESPNService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.calendar = calendar
        self.now = now
    }

    // Proxy the shared store's state so ScheduleView's `switch` over
    // idle/loading/loaded/error is unchanged.
    var state: MatchStore.State { store?.state ?? .idle }

    func load() async {
        await store?.load()
        await loadClubs()
    }

    /// Club directory — fetched once, used only to resolve followed IDs →
    /// abbreviations for the "My teams" filter. Kept SEPARATE from the season
    /// load because it must run even when another screen (e.g. Home, the landing
    /// tab) already loaded the shared MatchStore: that path skips the season
    /// `.idle` guard, and if the club fetch rode along inside it the "My teams"
    /// filter would be stuck resolving forever. Idempotent via `clubs.isEmpty`,
    /// so it's safe to call on every appearance and from pull-to-refresh.
    func loadClubs() async {
        guard clubs.isEmpty else { return }
        clubs = (try? await service.fetchTeams()) ?? []
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

    /// True when the user follows clubs but the directory hasn't resolved yet —
    /// lets the view show a spinner instead of a misleading "follow teams" prompt.
    var isResolvingFollowedTeams: Bool {
        !(following?.followedIDs.isEmpty ?? true) && clubs.isEmpty
    }

    // MARK: - Filtering

    private func events(for filter: Filter) -> [Event] {
        let all = store?.events ?? []
        switch filter {
        case .nwsl, .allMatches:
            // Every match the app tracks today is NWSL, so these two tabs show
            // the same set. They diverge once non-NWSL competition data exists:
            // NWSL = NWSL + the user's *followed* competitions; All = *every*
            // competition the app tracks. Structurally distinct, identical now.
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
        }
    }

    private func sections(from events: [Event]) -> [DaySection] {
        let grouped = Dictionary(grouping: events.filter { $0.dayKey != nil }) { $0.dayKey! }
        return grouped
            .map { (key, events) in
                DaySection(
                    id: key,
                    label: label(forDayKey: key),
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
