//
//  FeedPreferencesStore.swift
//  NWSLApp
//
//  The Feed's content preferences: which content types to show (reporter posts /
//  article links) and which sources to mute. Like FollowingStore, this is shared
//  app-wide state persisted to UserDefaults and injected via `.environment`, so
//  the Feed list (FeedViewModel) and the Sources sheet (FeedSourcesView) read and
//  write the same settings.
//
//  These preferences filter the existing (TEMP seed) Feed today and will keep
//  working unchanged when a real content backend lands — they act on FeedItems,
//  not on the source of those items.
//

import Foundation

@Observable
final class FeedPreferencesStore {
    /// Show reporter posts (Bluesky/Twitter) in the Feed. Defaults to on.
    var showReporterPosts: Bool { didSet { defaults.set(showReporterPosts, forKey: postsKey) } }
    /// Show article links (The Athletic, ESPN, …) in the Feed. Defaults to on.
    var showArticleLinks: Bool { didSet { defaults.set(showArticleLinks, forKey: articlesKey) } }

    /// Source names the user has muted (matches FeedItem.sourceName). Mutate via
    /// `setMuted(_:_:)` so persistence stays in sync.
    private(set) var mutedSources: Set<String>

    /// The chip the Feed opens to (the `ContentFilter.rawValue`, e.g. "all" /
    /// "reporters"). Stored as a raw string so this store needn't depend on the
    /// view model's enum; the Feed maps it back. Defaults to "all".
    var defaultFeedFilter: String { didSet { defaults.set(defaultFeedFilter, forKey: defaultFilterKey) } }

    private let defaults: UserDefaults
    private let postsKey = "feedShowReporterPosts"
    private let articlesKey = "feedShowArticleLinks"
    private let mutedKey = "feedMutedSources"
    private let mutedHandlesKey = "feedMutedDefaultHandles"
    private let defaultFilterKey = "feedDefaultFilter"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` so an unset preference defaults to on (a fresh install
        // shows everything), rather than `bool(forKey:)`'s false.
        self.showReporterPosts = defaults.object(forKey: postsKey) as? Bool ?? true
        self.showArticleLinks = defaults.object(forKey: articlesKey) as? Bool ?? true
        self.mutedSources = Set(defaults.stringArray(forKey: mutedKey) ?? [])
        self.mutedDefaultHandles = Set(defaults.stringArray(forKey: "feedMutedDefaultHandles") ?? [])
        self.defaultFeedFilter = defaults.string(forKey: defaultFilterKey) ?? "all"
        self.addedReporters = defaults.data(forKey: addedReportersKey)
            .flatMap { try? JSONDecoder().decode([AddedReporter].self, from: $0) } ?? []
        self.addedPlayerBsky = defaults.data(forKey: "feedAddedPlayerBsky")
            .flatMap { try? JSONDecoder().decode([AddedReporter].self, from: $0) } ?? []
        self.unfollowedOwnTeamPlayers = Set(defaults.stringArray(forKey: unfollowedPlayersKey) ?? [])
        self.followedOtherTeamPlayers = Set(defaults.stringArray(forKey: followedPlayersKey) ?? [])
    }

    func isMuted(_ source: String) -> Bool {
        mutedSources.contains(source)
    }

    /// Bare Bluesky handles (no `@`) of muted sources — sent as `/feed`'s `muted=` param so the
    /// PROXY excludes a toggled-off default (and lets a same-handle user add resurface
    /// unfiltered — the layering table's row 4). Name-keyed mutes predating this set (and
    /// handle-less sources like news outlets) still filter locally via `mutedSources`.
    private(set) var mutedDefaultHandles: Set<String>

    func setMuted(_ source: String, handle: String? = nil, _ muted: Bool) {
        if muted {
            mutedSources.insert(source)
        } else {
            mutedSources.remove(source)
        }
        defaults.set(Array(mutedSources), forKey: mutedKey)
        if let bare = handle?.trimmingCharacters(in: .whitespaces).lowercased(),
           !bare.isEmpty {
            let key = bare.hasPrefix("@") ? String(bare.dropFirst()) : bare
            if muted { mutedDefaultHandles.insert(key) } else { mutedDefaultHandles.remove(key) }
            defaults.set(Array(mutedDefaultHandles), forKey: mutedHandlesKey)
        }
    }

    // MARK: - Phase 3: user-added reporters (Bluesky handles the user follows)

    /// A reporter/outlet the user added by Bluesky handle. `handle` is the bare handle (no
    /// `@`) — the key the `/feed` `handles=` param AND the Sources `muteKey` both use.
    struct AddedReporter: Codable, Identifiable, Hashable {
        let handle: String
        let displayName: String
        var id: String { handle }
    }

    /// Reporters the user added, persisted as JSON. A user CHOICE, so it stays device-local and
    /// never restores across a reinstall (THE RESTORE LINE) — like every other feed preference.
    private(set) var addedReporters: [AddedReporter] {
        didSet { defaults.set((try? JSONEncoder().encode(addedReporters)) ?? Data(), forKey: addedReportersKey) }
    }
    /// The bare handles to fan out on the `/feed` `handles=` param.
    var addedReporterHandles: [String] { addedReporters.map(\.handle) }

    func addReporter(_ reporter: AddedReporter) {
        guard !addedReporters.contains(where: { $0.handle == reporter.handle }) else { return }
        addedReporters.append(reporter)
    }
    func removeReporter(handle: String) { addedReporters.removeAll { $0.handle == handle } }
    func isReporterAdded(handle: String) -> Bool { addedReporters.contains { $0.handle == handle } }

    // MARK: - 2c: user-added PLAYER Bluesky accounts (the add-flow's reporter|player pick)

    /// Bluesky accounts the user added AS PLAYERS — routed to the Players chip, and (owner law)
    /// NEVER Haiku-filtered: a player's own posts need no relevance gate. Same shape + same
    /// device-local / no-restore stance as `addedReporters`.
    private(set) var addedPlayerBsky: [AddedReporter] {
        didSet { defaults.set((try? JSONEncoder().encode(addedPlayerBsky)) ?? Data(), forKey: addedPlayerBskyKey) }
    }
    /// Bare handles for the `/feed` `playerBsky=` param.
    var addedPlayerBskyHandles: [String] { addedPlayerBsky.map(\.handle) }

    func addPlayerBsky(_ player: AddedReporter) {
        guard !addedPlayerBsky.contains(where: { $0.handle == player.handle }) else { return }
        addedPlayerBsky.append(player)
    }
    func removePlayerBsky(handle: String) { addedPlayerBsky.removeAll { $0.handle == handle } }
    func isPlayerBskyAdded(handle: String) -> Bool { addedPlayerBsky.contains { $0.handle == handle } }

    // MARK: - Phase 3: player follows (beyond your teams)

    /// Own-team player IDs (IG handles) the user turned OFF (own-team players show by default).
    private(set) var unfollowedOwnTeamPlayers: Set<String>
    /// Other-team player IDs the user explicitly follows (the cross-team stars).
    private(set) var followedOtherTeamPlayers: Set<String>

    /// The cross-team player IDs to fan out on the `/feed` `players=` param (own-team players
    /// already arrive via the `teams=` scope, so only the opt-in cross-team ones are sent).
    var followedPlayerIDs: [String] { Array(followedOtherTeamPlayers) }

    /// Shown in the Feed? Own-team = on unless turned off; other-team = only if followed.
    func isPlayerFollowed(_ id: String, isOwnTeam: Bool) -> Bool {
        isOwnTeam ? !unfollowedOwnTeamPlayers.contains(id) : followedOtherTeamPlayers.contains(id)
    }
    func setPlayerFollowed(_ id: String, _ followed: Bool, isOwnTeam: Bool) {
        if isOwnTeam {
            if followed { unfollowedOwnTeamPlayers.remove(id) } else { unfollowedOwnTeamPlayers.insert(id) }
            defaults.set(Array(unfollowedOwnTeamPlayers), forKey: unfollowedPlayersKey)
        } else {
            if followed { followedOtherTeamPlayers.insert(id) } else { followedOtherTeamPlayers.remove(id) }
            defaults.set(Array(followedOtherTeamPlayers), forKey: followedPlayersKey)
        }
    }

    private let addedReportersKey = "feedAddedReporters"
    private let addedPlayerBskyKey = "feedAddedPlayerBsky"
    private let unfollowedPlayersKey = "feedUnfollowedOwnTeamPlayers"
    private let followedPlayersKey = "feedFollowedOtherTeamPlayers"
}
