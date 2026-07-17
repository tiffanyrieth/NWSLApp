//
//  MetricKitCollector.swift
//  NWSLApp
//
//  Apple-native crash/hang/perf reporting (MetricKit — zero dependency, the "if Apple
//  provides a framework, use it" rule). iOS batches diagnostics on-device and delivers them
//  to the app (typically on the next launch, at most ~daily); this collector summarizes each
//  payload into ONE compact Diagnostics breadcrumb, so crashes and hangs land in the SAME
//  place the owner already looks — the in-app Diagnostics screen + the proxy's
//  /telemetry/recent — instead of only in App Store Connect's delayed dashboard.
//
//  Privacy: only COUNTS + a coarse first-crash signal/exception code are forwarded — no stack
//  traces, no identifiers — matching the telemetry sink's "Diagnostics, not linked to
//  identity" posture (its fields are capped server-side anyway).
//
//  Delivery notes: payloads arrive ONLY on a real device (simulator never delivers — a silent
//  no-op there), and work fully in TestFlight/App Store builds. `didReceive` is called on a
//  background queue → hop to the main actor for Diagnostics.
//

import Foundation
import MetricKit

final class MetricKitCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitCollector()
    private override init() { super.init() }

    /// Subscribe once at launch (AppDelegate.didFinishLaunching). Cheap; iOS handles the rest.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Diagnostics: crashes / hangs / CPU + disk-write exceptions — the "something went wrong
    /// on a tester's device" payloads. One breadcrumb per payload with counts; a crash also
    /// carries its (coarse) signal + exception type so the owner can tell a watchdog kill from
    /// a real crash without opening Xcode Organizer.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics ?? []
            let hangs = payload.hangDiagnostics ?? []
            let cpu = payload.cpuExceptionDiagnostics ?? []
            let disk = payload.diskWriteExceptionDiagnostics ?? []
            guard !crashes.isEmpty || !hangs.isEmpty || !cpu.isEmpty || !disk.isEmpty else { continue }
            var detail = "crashes=\(crashes.count) hangs=\(hangs.count) cpu=\(cpu.count) disk=\(disk.count)"
            if let first = crashes.first {
                let signal = first.signal.map(String.init) ?? "-"
                let exception = first.exceptionType.map(String.init) ?? "-"
                detail += " sig=\(signal) exc=\(exception)"
            }
            let summary = detail
            Task { @MainActor in
                Diagnostics.shared.record(.metricKitDiagnostic, summary)
            }
        }
    }

    /// Daily metrics (launch times, hang rates, battery…): deliberately NOT forwarded — that's
    /// dashboard-grade data Xcode Organizer already charts, and echoing it daily would be noise
    /// in a sink meant for "something needs attention". Diagnostics-only by design.
    func didReceive(_ payloads: [MXMetricPayload]) {}
}
