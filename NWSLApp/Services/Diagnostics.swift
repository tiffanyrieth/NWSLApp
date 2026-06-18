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

    /// Record an unexpected condition. Always emits to os_log; buffers for the in-app surface.
    func record(_ kind: Kind, _ detail: String = "") {
        logger.warning("\(kind.rawValue, privacy: .public) \(detail, privacy: .public)")
        events.insert(Event(date: Date(), kind: kind, detail: detail), at: 0)
        if events.count > cap { events.removeLast(events.count - cap) }
    }

    /// Count of a given kind — handy for a diagnostics summary row.
    func count(_ kind: Kind) -> Int { events.lazy.filter { $0.kind == kind }.count }
}
