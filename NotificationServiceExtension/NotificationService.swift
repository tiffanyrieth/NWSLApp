import UserNotifications
import UIKit   // NSValue(cgRect:) lives in UIKit's geometry additions on iOS
import os

/// Rich-notification attachment extension.
///
/// iOS shows the app icon + title/subtitle/body for free, but the crest-and-score
/// visual is a separate image file that must be *attached* to the notification. The
/// system wakes this extension for any push carrying `mutable-content: 1`; we read
/// the server-rendered match-card URL from the payload, download it, and attach it
/// before the notification is shown.
///
/// The extension is a separate process and cannot reach the app's in-memory
/// `Diagnostics` ring, so `os.Logger` is the diagnostics spine here. Per the app-wide
/// no-silent-failures rule, every failure is logged — but we ALWAYS deliver the
/// text-only notification rather than dropping the push, so a failed image download
/// degrades honestly to plain text instead of vanishing.
final class NotificationService: UNNotificationServiceExtension {

    private static let log = Logger(
        subsystem: "com.tiffanyrieth.nwslapp.NWSLApp.NotificationService",
        category: "NSE"
    )

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let mutable = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttemptContent = mutable

        guard let bestAttemptContent = mutable else {
            // Couldn't get a mutable copy — pass the original through untouched.
            contentHandler(request.content)
            return
        }

        // The watcher sets `imageUrl` to the match-card (or crest) render endpoint.
        guard let urlString = bestAttemptContent.userInfo["imageUrl"] as? String,
              let url = URL(string: urlString) else {
            // No image to attach (e.g. a future text-only push) — not a failure.
            Self.log.debug("No imageUrl in payload; delivering text-only.")
            contentHandler(bestAttemptContent)
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            // Whatever happens below, deliver SOMETHING — never drop the notification.
            defer { contentHandler(bestAttemptContent) }

            if let error {
                Self.log.error("Attachment download failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let tempURL else {
                Self.log.error("Attachment download returned no file.")
                return
            }

            let ext = Self.fileExtension(for: url, response: response)
            let fileManager = FileManager.default
            let destURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try fileManager.moveItem(at: tempURL, to: destURL)
                // For a goal the watcher sends a `thumbnailRect`; use it to crop the COLLAPSED
                // banner thumbnail to the scoring team's crest (instead of a shrunk whole-card).
                // Absent (non-goals) → nil → iOS's default whole-image thumbnail (unchanged).
                let options = Self.thumbnailOptions(from: bestAttemptContent.userInfo)
                let attachment = try UNNotificationAttachment(identifier: "matchcard", url: destURL, options: options)
                bestAttemptContent.attachments = [attachment]
            } catch {
                Self.log.error("Building attachment failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // The system is about to kill us — deliver the best we have (text-only if the
        // image didn't finish downloading) rather than letting the push disappear.
        Self.log.error("NSE time expired; delivering best-attempt (text-only) content.")
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    /// A `thumbnailRect` in the payload (normalized `[x, y, w, h]`, sent for goals) crops the
    /// attachment's COLLAPSED thumbnail to the scoring team's crest. `nil` when the key is
    /// absent/malformed → iOS uses the whole image (the prior behavior for non-goal pushes).
    private static func thumbnailOptions(from userInfo: [AnyHashable: Any]) -> [String: Any]? {
        guard let raw = userInfo["thumbnailRect"] as? [Any], raw.count == 4 else { return nil }
        let r = raw.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard r.count == 4 else { return nil }
        let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
        return [UNNotificationAttachmentOptionsThumbnailClippingRectKey: NSValue(cgRect: rect)]
    }

    /// Pick a file extension so `UNNotificationAttachment` can infer the media type.
    private static func fileExtension(for url: URL, response: URLResponse?) -> String {
        let pathExt = url.pathExtension.lowercased()
        if !pathExt.isEmpty { return pathExt }
        switch (response?.mimeType ?? "").lowercased() {
        case "image/png":  return "png"
        case "image/jpeg": return "jpg"
        case "image/gif":  return "gif"
        default:           return "png"
        }
    }
}
