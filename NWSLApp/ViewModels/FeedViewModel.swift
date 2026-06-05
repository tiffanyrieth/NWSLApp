//
//  FeedViewModel.swift
//  NWSLApp
//
//  Owns the Feed tab's state. Two inputs come together here:
//   • the feed items (today a TEMP curated seed from FeedContentProvider; later
//     a real Bluesky/news backend), and
//   • the user's followed clubs — resolved by fetching the club directory, the
//     same pattern Home/Schedule use, because FollowingStore stores IDs only and
//     the filter chips need each club's short name + color.
//
//  Everything the view shows is DERIVED here: the filter chips (All + one per
//  followed team + League) and the items visible for the selected chip. The view
//  passes in the shared FollowingStore (mirroring HomeViewModel) rather than the
//  store being owned here, since following is app-wide state.
//
//  Filtering rules (per the design spec):
//   • All    — everything from followed teams + league-wide news, newest first.
//   • <team> — only items tagged to that team (incl. multi-team items).
//   • League — only league-wide news (power rankings, expansion, rule changes).
//

import Foundation

@Observable
final class FeedViewModel {
    /// idle/loading/loaded/error for the CLUB DIRECTORY fetch (used to build the
    /// per-team chips). The items themselves come from the seed provider and
    /// don't have a failure path today.
    enum State {
        case idle
        case loading
        case loaded([Club])
        case error(String)
    }

    /// Which chip is selected. `.team` carries the club abbreviation, the same
    /// key FeedTeamTag uses, so chip ↔ item matching is a simple string compare.
    enum Filter: Hashable {
        case all
        case team(String)   // club abbreviation
        case league
    }

    /// A filter chip to render: its filter and label (clean text, no dot — the
    /// chip label and the cards' own team dots already identify the team).
    struct Chip: Identifiable, Hashable {
        let filter: Filter
        let label: String
        var id: Filter { filter }
    }

    private(set) var clubsState: State = .idle
    private(set) var allItems: [FeedItem] = []
    var selectedFilter: Filter = .all

    private let service: ESPNService
    private let content: FeedContentProvider

    init(
        service: ESPNService = ESPNService(),
        content: FeedContentProvider = FeedContentProvider()
    ) {
        self.service = service
        self.content = content
    }

    /// Load the seed items, then the club directory for the chips.
    func load() async {
        allItems = (await content.items())
            .sorted { $0.timestamp > $1.timestamp }   // newest first
        await loadClubs()
    }

    func loadClubs() async {
        clubsState = .loading
        do {
            clubsState = .loaded(try await service.fetchTeams())
        } catch {
            clubsState = .error(message(for: error))
        }
    }

    private var clubs: [Club] {
        if case .loaded(let clubs) = clubsState { return clubs }
        return []
    }

    /// Followed clubs, in the directory's alphabetical order.
    func followedClubs(_ following: FollowingStore) -> [Club] {
        clubs.filter { following.followedIDs.contains($0.id) }
    }

    // MARK: - Chips

    /// All + one chip per followed team + League.
    func chips(_ following: FollowingStore) -> [Chip] {
        var chips: [Chip] = [Chip(filter: .all, label: "All")]
        for club in followedClubs(following) {
            chips.append(Chip(
                filter: .team(club.abbreviation),
                label: club.shortName ?? club.displayName
            ))
        }
        chips.append(Chip(filter: .league, label: "League"))
        return chips
    }

    // MARK: - Filtered items

    /// Items visible for the current `selectedFilter`, already newest-first.
    /// The base set is always scoped to the user's world — their followed teams
    /// plus league-wide news — so the Feed never shows content about clubs they
    /// don't follow.
    func items(_ following: FollowingStore) -> [FeedItem] {
        let followed = Set(followedClubs(following).map(\.abbreviation))
        switch selectedFilter {
        case .all:
            return allItems.filter { $0.isLeague || isFollowed($0, followed) }
        case .league:
            return allItems.filter { $0.isLeague }
        case .team(let abbreviation):
            return allItems.filter { item in
                item.teams.contains { $0.abbreviation == abbreviation }
            }
        }
    }

    /// True if any of the item's tagged teams is one the user follows.
    private func isFollowed(_ item: FeedItem, _ followed: Set<String>) -> Bool {
        item.teams.contains { followed.contains($0.abbreviation) }
    }

    // MARK: - Helpers

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code)). Pull to retry."
        case ESPNServiceError.decoding:
            return "Couldn't read the teams response. Pull to retry."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load the Feed. Check your connection and pull to retry."
        }
    }
}
