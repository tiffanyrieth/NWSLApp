//
//  Analytics.swift
//  NWSLApp
//
//  Anonymous Level-3 usage counters — the "measure the product, not the person" channel
//  (owner decision 2026-07-16; design + privacy analysis in the session plan; backend =
//  proxy POST /analytics → Supabase `analytics_counters` daily rollups).
//
//  PRIVACY IS THE DESIGN (App Store label: Usage Data, NOT linked to identity):
//   • No user id, no device id, no session id, no IP, no timestamps finer than a day.
//   • Every event is one whitelisted name + at most ONE low-cardinality param, all derived
//     from fixed enums — the type system makes a fingerprintable payload unrepresentable.
//   • Counts aggregate IN MEMORY during the session and flush as one pre-summed batch on
//     app-background (the same lifecycle hook as Diagnostics.flushRemote) — one tiny POST
//     per session, never a per-tap network call, nothing stored client-side.
//
//  Deliberately a SEPARATE channel from Diagnostics: Diagnostics is fail-LOUD operational
//  telemetry for the engineer; this is quiet aggregate product measurement. Same proxy
//  transport idiom, different route, different store, different purpose.
//

import Foundation
import Observation

@MainActor
@Observable
final class Analytics {
    static let shared = Analytics()
    private init() {}

    /// The complete event vocabulary. Adding a case = update `wire(_:)` below AND the proxy's
    /// `ANALYTICS_EVENTS` whitelist (nwslapp-proxy src/index.ts) — an unlisted name is dropped
    /// server-side, so the two must move together.
    enum Event {
        case sessionStart            // param: app version "0.4.3 (27)" — the build-distribution query
        case sessionOS               // param: iOS "26.0" — the when-can-we-drop-17 query
        case tabOpened(AppTab)       // param: home/schedule/standings/teams/feed
        case fanzoneGameOpened(String) // param: predict/bracket/trivia/knowher (HomeView seenKey)
        case feedItemTapped          // no param — do people engage Feed content at all?
        case feedChipTapped(FeedViewModel.ContentFilter) // param: all/reporters/players/clubs
    }

    /// In-memory rollup: "event|param" → count. Cleared only after a successful flush, so a
    /// failed upload retries with the next background (counts are never lost to a blip, only
    /// to a force-kill mid-session — acceptable for aggregate trends).
    private var counters: [String: Int] = [:]
    private var isFlushing = false
    /// One quiet breadcrumb per session on upload failure — a persistently broken analytics
    /// path must surface to the engineer (NO SILENT FAILURES) without spamming a crumb per retry.
    private var reportedFailure = false

    func log(_ event: Event) {
        let (name, param) = Self.wire(event)
        counters["\(name)|\(param)", default: 0] += 1
    }

    /// Pure event → (wire name, param) mapping (unit-tested — the strings are the server
    /// contract; a rename here silently zeroes a dashboard column).
    nonisolated static func wire(_ event: Event) -> (event: String, param: String) {
        switch event {
        case .sessionStart: return ("session_start", appVersion)
        case .sessionOS: return ("session_os", osVersion)
        case .tabOpened(let tab): return ("tab_opened", tab.analyticsKey)
        case .fanzoneGameOpened(let key): return ("fanzone_game_opened", key)
        case .feedItemTapped: return ("feed_item_tapped", "")
        case .feedChipTapped(let filter): return ("feed_chip_tapped", filter.rawValue)
        }
    }

    /// The batch the flush would send right now — split out pure for unit tests.
    nonisolated static func batch(from counters: [String: Int]) -> [[String: Any]] {
        counters.compactMap { key, n in
            guard n > 0 else { return nil }
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard let event = parts.first else { return nil }
            return ["event": String(event), "param": parts.count > 1 ? String(parts[1]) : "", "n": n]
        }
    }

    /// POST the session's counts to the proxy (fire on `scenePhase == .background`, beside
    /// Diagnostics.flushRemote). Clears the counters ONLY on a 2xx, so a transient failure
    /// re-sends with the next background — the server side adds counts atomically, and a rare
    /// double-send inflates a daily count by a session's taps, which aggregate trends absorb.
    func flushRemote() async {
        guard !isFlushing, !counters.isEmpty, let url = AppConfig.analyticsURL() else { return }
        isFlushing = true
        defer { isFlushing = false }
        let events = Self.batch(from: counters)
        guard !events.isEmpty,
              let body = try? JSONSerialization.data(withJSONObject: ["events": events]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            counters.removeAll()
        } catch {
            if !reportedFailure {
                reportedFailure = true
                Diagnostics.shared.record(.apiFailure, "analytics flush: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Version strings (mirror Diagnostics' formats — same fields, same shapes)

    nonisolated private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    nonisolated private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }
}

extension AppTab {
    /// Stable wire key for the tab_opened counter — decoupled from the case name so a future
    /// rename can't silently split a dashboard column.
    var analyticsKey: String {
        switch self {
        case .home: return "home"
        case .schedule: return "schedule"
        case .standings: return "standings"
        case .teams: return "teams"
        case .feed: return "feed"
        }
    }
}
