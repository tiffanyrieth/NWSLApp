//
//  NotifTrace.swift
//  NWSLApp
//
//  DISPOSABLE DEBUG SCAFFOLDING (remove once the token pipeline is proven solid — see
//  supabase/migration_notification_diagnostics.sql). A device-keyed breadcrumb log of the
//  notification TOKEN-REGISTRATION chain, so a failed registration is diagnosable after the fact
//  instead of silent. It exists because the primary `Diagnostics` spine flushes to an
//  identity-STRIPPED Cloudflare-KV sink you can't query per device — and the token pipeline was
//  emitting only on failure. NotifTrace persists a crumb at every link, keyed to `device_id`, into
//  the `notification_diagnostics` Supabase table, so after a live game we `SELECT … where
//  device_id = …` and read exactly where the chain stopped.
//
//  Buffering model: crumbs are appended to a disk-persisted queue (survives process death) and
//  flushed to Supabase ONLY when a session exists, stamped with the signed-in `user_id`. So a step
//  that happens before sign-in (a common failure point) is captured locally with its real timestamp
//  and uploaded once signed in — no anon writes. Mirrors `Diagnostics.shared` (@MainActor @Observable
//  singleton) so call sites read `NotifTrace.shared.log(...)` the same way.
//

import Foundation
import OSLog
import Supabase

@MainActor
@Observable
final class NotifTrace {
    static let shared = NotifTrace()
    private init() { pending = Self.loadPending() }

    enum Status: String { case ok, skip, fail }

    struct Crumb: Codable, Identifiable {
        var id = UUID()
        let occurredAt: Date
        let step: String
        let status: String
        let detail: String
    }

    /// Recent crumbs, most-recent-first, for the in-app Notification Diagnostics screen.
    private(set) var recent: [Crumb] = []
    private let recentCap = 80

    /// Not-yet-uploaded crumbs, persisted so pre-sign-in / pre-kill steps survive to be flushed.
    private var pending: [Crumb]
    private var isFlushing = false
    private static let pendingKey = "notifTrace.pending.v1"

    private let logger = Logger(subsystem: "com.tiffanyrieth.nwslapp", category: "NotifTrace")

    /// Record one step of the registration chain. Always os_logs; buffers to disk; opportunistically
    /// flushes to Supabase if signed in.
    func log(_ step: String, _ status: Status, _ detail: String = "") {
        // DEBUG-ONLY. NotifTrace persists IDENTITY-LINKED (user_id + device_id) breadcrumbs to the
        // Supabase `notification_diagnostics` table — it must NOT ship in Release/TestFlight, so the
        // App Store "Data Not Linked to You" posture holds (only contact info is ever linked). In
        // shipped builds this is a no-op; the anonymous `Diagnostics` spine still records failures.
        #if DEBUG
        logger.info("\(step, privacy: .public) \(status.rawValue, privacy: .public) \(detail, privacy: .public)")
        let crumb = Crumb(occurredAt: Date(), step: step, status: status.rawValue, detail: detail)
        recent.insert(crumb, at: 0)
        if recent.count > recentCap { recent.removeLast(recent.count - recentCap) }
        pending.append(crumb)
        Self.savePending(pending)
        Task { await flush() }
        #endif
    }

    /// Flush the pending queue to `notification_diagnostics`. No-op (keeps buffering) until a session
    /// exists. Best-effort: on failure crumbs stay queued for the next attempt (sign-in / foreground).
    func flush() async {
        // DEBUG-ONLY (see `log`): no identity-linked upload in shipped builds.
        #if DEBUG
        guard !isFlushing, !pending.isEmpty else { return }
        guard let userID = SupabaseManager.client.auth.currentUser?.id else { return }  // buffer until signed in
        isFlushing = true
        defer { isFlushing = false }

        let batch = pending
        let rows = batch.map {
            Row(user_id: userID,
                device_id: DeviceIdentity.deviceID,
                step: $0.step,
                status: $0.status,
                detail: $0.detail,
                app_build: Self.appBuild,
                os: Self.os,
                occurred_at: Self.iso.string(from: $0.occurredAt))
        }
        do {
            try await SupabaseManager.client.from("notification_diagnostics").insert(rows).execute()
            pending.removeFirst(min(batch.count, pending.count))  // crumbs added during the await stay queued
            Self.savePending(pending)
        } catch {
            // The trace sink itself failed — surface on the primary spine so we still know.
            Diagnostics.shared.record(.apiFailure, "notifTrace flush: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Row (snake_case → Postgres columns 1:1)

    private struct Row: Encodable {
        let user_id: UUID
        let device_id: String
        let step: String
        let status: String
        let detail: String
        let app_build: String
        let os: String
        let occurred_at: String   // ISO8601; PostgREST parses into timestamptz
    }

    // MARK: - Persistence

    private static func loadPending() -> [Crumb] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let crumbs = try? JSONDecoder().decode([Crumb].self, from: data) else { return [] }
        return crumbs
    }
    private static func savePending(_ crumbs: [Crumb]) {
        // Bound the on-disk queue so a permanently-signed-out device can't grow it unbounded.
        let capped = Array(crumbs.suffix(200))
        if let data = try? JSONEncoder().encode(capped) { UserDefaults.standard.set(data, forKey: pendingKey) }
    }

    // MARK: - Env strings

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let appBuild: String = {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        return "\(short) (\(build))"
    }()
    private static let os: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
}
