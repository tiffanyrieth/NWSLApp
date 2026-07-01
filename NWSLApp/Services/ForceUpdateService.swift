//
//  ForceUpdateService.swift
//  NWSLApp
//
//  The launch-time forced-update gate. The app is online-only and talks to ESPN through the
//  proxy; when a backend/data-shape change ships, an old client can render broken data or hit a
//  now-incompatible route. This lets us retire old builds: the proxy's `GET /config` returns a
//  `minBuild`, and any installed build below it is walled off behind a non-dismissible "please
//  update" screen (see `ForceUpdateView`), pointed at TestFlight/the App Store.
//
//  FAIL OPEN (deliberate): any network failure, timeout, non-2xx, or decode error returns
//  "not required" — a working stale build beats a current build bricked because a config check
//  timed out while the proxy was down. We only ever BLOCK on a definitive "your build < minBuild".
//
//  The comparison is on the BUILD NUMBER (a monotonically increasing integer = CFBundleVersion),
//  never the marketing version string — a plain `<`, no semver parsing.
//

import Foundation

enum ForceUpdateService {
    private struct RemoteConfig: Decodable {
        let minVersion: String
        let minBuild: Int
    }

    /// This build's `CFBundleVersion` as an Int (e.g. 21). nil if unreadable → the gate fails open.
    static var currentBuild: Int? {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap(Int.init)
    }

    /// Returns `true` only when this build is CONFIRMED below the server's `minBuild` (→ block).
    /// Everything else — unreachable proxy, timeout, non-2xx, bad JSON, unreadable local build —
    /// returns `false` (allow). Short timeout so a slow/hung proxy can't delay launch.
    static func isUpdateRequired() async -> Bool {
        guard let url = configURLOrNil(), let build = currentBuild else { return false }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false // fail open on any non-2xx
            }
            let remote = try JSONDecoder().decode(RemoteConfig.self, from: data)
            return build < remote.minBuild
        } catch {
            // Fail open — but LOUD to the engineer (the gate silently not-checking is itself a
            // condition worth seeing; it never blocks the user).
            await Diagnostics.shared.record(.apiFailure, "force-update config check: \(error.localizedDescription)")
            return false
        }
    }

    private static func configURLOrNil() -> URL? { AppConfig.configURL() }
}
