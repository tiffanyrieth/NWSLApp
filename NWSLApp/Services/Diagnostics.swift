//
//  Diagnostics.swift
//  NWSLApp
//
//  The app's NO-SILENT-FAILURES spine. Every unexpected condition — a fallback, an API
//  failure, a stale serve, a parse error, a retry, an unexpected-empty result — records an
//  event here, even when the user never notices. The rule: fail LOUD to the engineer always
//  (os_log + this in-memory log, surfaced in dev/TestFlight builds), fail HONESTLY to the user
//  proportionally (degraded-but-working shows a subtle truthful indicator; blocked shows a
//  clear message + retry — never a fake-perfect fallback or a silent swap).
//
//  This is intentionally tiny and dependency-free: an os.Logger emission (always) + a capped
//  in-memory ring buffer (@Observable, so a diagnostics surface can show it live). A remote
//  sink is a deliberate follow-up — local emission already satisfies "visible to the engineer";
//  shipping field events off-device is data egress that needs a collection endpoint + sign-off.
//

import Foundation
import OSLog

@MainActor
@Observable
final class Diagnostics {
    static let shared = Diagnostics()
    private init() {}

    enum Kind: String {
        // Assets
        case assetBundleMiss            // a SHOULD-be-bundled crest/flag fell through to network
        case assetOverrideApplied       // a cached rebrand override is being used over the bundle
        case assetVectorRebrandPending  // a vector asset rebranded but can't override (needs re-bundle)
        // Reserve the rest of the surface for the rest of the app as #5 is adopted everywhere:
        case apiFailure                 // a network/API call failed
        case parseError                 // a decode/parse failed
        case unexpectedEmpty            // a load succeeded but returned nothing where content was due
        case staleServe                 // served older-than-expected data
    }

    struct Event: Identifiable {
        let id = UUID()
        let date: Date
        let kind: Kind
        let detail: String
    }

    /// Most-recent-first, capped. Read by the dev/TestFlight diagnostics surface.
    private(set) var events: [Event] = []
    private let cap = 200

    private let logger = Logger(subsystem: "com.tiffanyrieth.nwslapp", category: "diagnostics")

    /// Record an unexpected condition. Always emits to os_log; buffers for the in-app surface
    /// AND for the remote sink (so a field miss reaches the owner without a user report).
    func record(_ kind: Kind, _ detail: String = "") {
        logger.warning("\(kind.rawValue, privacy: .public) \(detail, privacy: .public)")
        let event = Event(date: Date(), kind: kind, detail: detail)
        events.insert(event, at: 0)
        if events.count > cap { events.removeLast(events.count - cap) }
        pendingRemote.append(event)
        // Flush eagerly on a burst so a flood (e.g. an offline spell) reaches the sink even if
        // the app is never backgrounded; otherwise the scenePhase-background flush covers it.
        if pendingRemote.count >= flushThreshold { Task { await flushRemote() } }
    }

    /// Count of a given kind — handy for a diagnostics summary row.
    func count(_ kind: Kind) -> Int { events.lazy.filter { $0.kind == kind }.count }

    // MARK: - Remote sink (best-effort, NON-PII operational events only)

    private var pendingRemote: [Event] = []
    private var isFlushing = false
    private let flushThreshold = 25

    /// POST the pending events to the proxy `/telemetry` sink. Best-effort: on any failure the
    /// events stay queued for the next flush. Sends ONLY kind + a short operational detail + a
    /// timestamp + app/OS version — no identifiers, no device id (App Store "Diagnostics", not
    /// linked to identity). Called on app background (RootTabView) and on a burst.
    func flushRemote() async {
        guard !isFlushing, !pendingRemote.isEmpty, let url = AppConfig.telemetryURL() else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = pendingRemote
        let payload = Payload(
            app: Self.appVersion,
            os: Self.osVersion,
            events: batch.map { Payload.Item(kind: $0.kind.rawValue, detail: $0.detail, ts: $0.date.timeIntervalSince1970) }
        )
        guard let body = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 204 else { return }
        // Drop exactly the sent prefix; events appended during the await stay queued.
        pendingRemote.removeFirst(min(batch.count, pendingRemote.count))
    }

    private struct Payload: Encodable {
        let app: String
        let os: String
        let events: [Item]
        struct Item: Encodable {
            let kind: String
            let detail: String
            let ts: TimeInterval
        }
    }

    private static let appVersion: String =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    private static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }()
}
