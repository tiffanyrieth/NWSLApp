//
//  ScheduleViewModel.swift
//  NWSLApp
//
//  Owns state for ScheduleView: fetches the full current NWSL season,
//  groups events by local-day sections, and computes the section the
//  view should scroll to on first appearance (today or next upcoming).
//

import Foundation

@Observable
final class ScheduleViewModel {
    enum State {
        case idle
        case loading
        case loaded([Event])
        case error(String)
    }

    struct DaySection: Identifiable {
        let id: String       // "yyyy-MM-dd"
        let label: String    // "Today" or "Saturday, Jun 6"
        let events: [Event]
    }

    private(set) var state: State = .idle

    private let service: ESPNService
    private let calendar: Calendar
    private let now: () -> Date

    init(
        service: ESPNService = ESPNService(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.calendar = calendar
        self.now = now
    }

    func load() async {
        state = .loading
        let year = calendar.component(.year, from: now())
        do {
            let board = try await service.fetchScoreboard(year: year)
            state = .loaded(board.events)
        } catch {
            state = .error(message(for: error))
        }
    }

    var sections: [DaySection] {
        guard case .loaded(let events) = state else { return [] }
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
        if case .loaded = state { return true }
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

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code)). Pull to retry."
        case ESPNServiceError.decoding:
            return "Couldn't read the schedule response. Pull to retry."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load the schedule. Check your connection and pull to retry."
        }
    }
}
