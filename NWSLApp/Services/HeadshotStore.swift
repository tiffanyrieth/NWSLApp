//
//  HeadshotStore.swift
//  NWSLApp
//
//  The session-scoped player-headshot map: ESPN athlete id → NWSL player GUID. ESPN serves
//  no NWSL headshots, but nwslsoccer.com does (keyed by an opaque GUID); the proxy's
//  `/headshots` route name-matches the two id systems on a weekly cron. This store fetches
//  that map ONCE per launch and answers a synchronous `guid(forAthleteID:)` so any player
//  avatar can swap its jersey-number monogram for the real photo (`PlayerHeadshot`).
//
//  Singleton, mirroring the `ImageCache` precedent (a deliberate architecture exception):
//  the avatar call sites are leaf components (PlayerCard, PitchDot, PlayerDot, picker slots)
//  that aren't in the environment, so threading an injected store through all of them is
//  heavy for a read-only ~400-entry map. `@Observable` so a view that rendered a monogram
//  before the map arrived re-renders with the photo once `load()` completes; `@MainActor`
//  so the dictionary is only ever touched from the main actor (views read it during body).
//
//  Best-effort by design: any failure (offline, route empty before the first cron, decode
//  error) leaves the map empty, and every avatar simply keeps its monogram. It never throws
//  to the UI and never blocks a view.
//

import Foundation
import Observation

@MainActor
@Observable
final class HeadshotStore {
    static let shared = HeadshotStore()

    /// ESPN athlete id → NWSL GUID. Empty until `load()` succeeds.
    private(set) var map: [String: String] = [:]

    // Guards against a second fetch if `load()` is called again (e.g. .task re-fires on a
    // scene change). The map is stable for a session, so one successful load is enough.
    private var didLoad = false

    private init() {}

    /// The NWSL GUID for an ESPN athlete id, or nil when unmapped (no match yet, or the map
    /// hasn't loaded) — the caller then keeps its monogram.
    func guid(forAthleteID athleteID: String?) -> String? {
        guard let athleteID else { return nil }
        return map[athleteID]
    }

    /// Fetch the headshot map once. Called from `RootTabView`'s launch task so the map is warm
    /// before any squad grid appears. Silently no-ops on failure (avatars stay monograms).
    func load() async {
        guard !didLoad, let url = AppConfig.headshotsMapURL() else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Diagnostics.shared.record(.apiFailure, "headshots map: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            map = decoded
            didLoad = true
        } catch {
            // Best-effort: leave the map empty (avatars stay monograms); a later launch retries.
            // NOT silent — flag it so a broken headshots pipeline is visible to the owner.
            Diagnostics.shared.record(.apiFailure, "headshots map: \(error.localizedDescription)")
        }
    }
}
