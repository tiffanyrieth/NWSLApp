//
//  DayBeforeCardRenderer.swift
//  NWSLApp
//
//  Renders the day-before reminder tile (DayBeforeCardView) to a PNG and wraps it as a
//  UNNotificationAttachment — the ON-DEVICE "pretty card" path (SwiftUI ImageRenderer, no
//  server, no NSE). Precedent: BracketBattleView's share-card render (ImageRenderer, scale 3).
//
//  NO SILENT FAILURES: on ANY failure (render nil, PNG encode nil, file write, attachment init)
//  it records a `.dayBeforeCardFailure` diagnostic and returns nil — the caller then schedules
//  the reminder TEXT-ONLY. The reminder is NEVER skipped because the image layer failed.
//

import SwiftUI
import UserNotifications

@MainActor
enum DayBeforeCardRenderer {

    /// Render `model` → PNG in a unique temp file → `UNNotificationAttachment`. `nil` on any
    /// failure (diagnostic emitted). On success the attachment MOVES the temp file into the
    /// notification store, so there's nothing to clean up.
    static func attachment(for model: DayBeforeCardModel, eventID: String) -> UNNotificationAttachment? {
        let renderer = ImageRenderer(content: DayBeforeCardView(model: model))
        renderer.scale = 3   // 360×180 pt @3x → 1080×540 px (BracketBattle precedent)

        guard let uiImage = renderer.uiImage else {
            Diagnostics.shared.record(.dayBeforeCardFailure, "\(eventID): render produced no image")
            return nil
        }
        guard let png = uiImage.pngData() else {
            Diagnostics.shared.record(.dayBeforeCardFailure, "\(eventID): PNG encode failed")
            return nil
        }

        // Unique path so concurrent/rebuilt renders never collide (the NSE temp-file pattern).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nwsl-dayBefore-\(eventID)-\(UUID().uuidString)")
            .appendingPathExtension("png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "nwsl.dayBefore.card", url: url)
        } catch {
            Diagnostics.shared.record(.dayBeforeCardFailure, "\(eventID): attach — \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)   // best-effort cleanup if the move never happened
            return nil
        }
    }
}
