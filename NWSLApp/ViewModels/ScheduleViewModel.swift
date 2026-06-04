//
//  ScheduleViewModel.swift
//  NWSLApp
//
//  Owns the *presentation* of ScheduleView: it groups the season's events into
//  local-day sections, labels them, and computes the section the view should
//  scroll to on first appearance (today, or the next upcoming matchday).
//
//  It no longer fetches. The season's events live in the shared MatchStore
//  (injected app-wide), and this view model derives its sections from that
//  store — so the Schedule screen and the Team page read the exact same data.
//  The store is handed in by the view (`store = ...`) before the first load,
//  because a SwiftUI `@State` view model can't read the environment at init.
//

import Foundation

@Observable
final class ScheduleViewModel {
    struct DaySection: Identifiable {
        let id: String       // "yyyy-MM-dd"
        let label: String    // "Today" or "Saturday, Jun 6"
        let events: [Event]
    }

    // Set by ScheduleView from the environment before the first load. Optional
    // because the view model is constructed before the environment is readable;
    // until it's wired, the screen simply reads as `.idle`.
    var store: MatchStore?

    private let calendar: Calendar
    private let now: () -> Date

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
    }

    // Proxy the shared store's state so ScheduleView's `switch` over
    // idle/loading/loaded/error is unchanged.
    var state: MatchStore.State { store?.state ?? .idle }

    func load() async {
        await store?.load()
    }

    var sections: [DaySection] {
        let events = store?.events ?? []
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

    // Today's section if present, otherwise the first future section.
    // Returns nil if everything in the season is in the past.
    var initialScrollSectionID: String? {
        let today = todayKey()
        let ids = sections.map(\.id)
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
        display.dateFormat = "EEEE, MMM d"
        return display.string(from: date)
    }
}
