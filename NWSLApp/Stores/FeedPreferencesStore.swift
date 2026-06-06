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

    private let defaults: UserDefaults
    private let postsKey = "feedShowReporterPosts"
    private let articlesKey = "feedShowArticleLinks"
    private let mutedKey = "feedMutedSources"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` so an unset preference defaults to on (a fresh install
        // shows everything), rather than `bool(forKey:)`'s false.
        self.showReporterPosts = defaults.object(forKey: postsKey) as? Bool ?? true
        self.showArticleLinks = defaults.object(forKey: articlesKey) as? Bool ?? true
        self.mutedSources = Set(defaults.stringArray(forKey: mutedKey) ?? [])
    }

    func isMuted(_ source: String) -> Bool {
        mutedSources.contains(source)
    }

    func setMuted(_ source: String, _ muted: Bool) {
        if muted {
            mutedSources.insert(source)
        } else {
            mutedSources.remove(source)
        }
        defaults.set(Array(mutedSources), forKey: mutedKey)
    }
}
