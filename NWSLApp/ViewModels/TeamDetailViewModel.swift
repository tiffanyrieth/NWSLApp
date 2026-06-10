//
//  TeamDetailViewModel.swift
//  NWSLApp
//
//  Owns state for TeamDetailView's roster fetch. One call to ESPN's roster
//  endpoint returns a ClubSquad — the players plus the team profile (color,
//  standing line) that rides along — so this view model feeds the whole page:
//  the position-grouped squad grid AND the pinned header's standing line. Uses
//  the same idle/loading/loaded/error State enum as the other screens.
//

import Foundation

@Observable
final class TeamDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(ClubSquad)
        case error(String)
    }

    private(set) var state: State = .idle

    /// The club's social/community links, in display order; empty until loaded (or
    /// for a club with none). Drives the header's social row.
    private(set) var socialLinks: [SocialLink] = []

    /// Per-player season stats keyed by athlete id (real ESPN Core API data, via
    /// ESPNService.seasonStats). Powers the player pages' season block and the
    /// team-leaders board, which is derived from these same lines so the two agree.
    private(set) var seasonStats: [String: PlayerSeasonStats] = [:]

    /// The season the stats are for; surfaced to the player pages' "SEASON …" label.
    let seasonYear = AppConfig.currentSeasonYear
    var seasonLabel: String { "SEASON \(seasonYear)" }

    private let service: ESPNService
    private let socialLinksProvider: TeamSocialLinksProvider

    init(service: ESPNService = ESPNService(),
         socialLinksProvider: TeamSocialLinksProvider = TeamSocialLinksProvider()) {
        self.service = service
        self.socialLinksProvider = socialLinksProvider
    }

    func load(clubID: String) async {
        state = .loading
        do {
            let squad = try await service.fetchRoster(clubID: clubID)
            state = .loaded(squad)
            // Stats ride a best-effort second pass once the squad is known (they're
            // keyed by athlete id, so the roster must load first). The fetch is
            // non-throwing — a stats outage leaves the leaders empty but never
            // errors the page.
            let stats = await service.seasonStats(for: squad.athletes, year: seasonYear)
            seasonStats = Dictionary(uniqueKeysWithValues: stats.map { ($0.athleteID, $0) })
        } catch {
            state = .error(message(for: error))
        }
    }

    /// Loads the club's social links by abbreviation (the curated seed's join key).
    /// Separate from the roster fetch so the row can appear immediately — local seed
    /// data, no network — and recolor once the roster's accent arrives.
    func loadSocialLinks(abbreviation: String) async {
        socialLinks = await socialLinksProvider.links(for: abbreviation)?.links ?? []
    }

    /// The loaded squad, or nil until the roster has loaded.
    private var squad: ClubSquad? {
        if case .loaded(let squad) = state { return squad }
        return nil
    }

    /// The squad grouped by position (FWD → MID → DEF → GK); empty unless loaded.
    var positionGroups: [Roster.PositionGroup] {
        squad.map { Roster.grouped($0.athletes) } ?? []
    }

    /// The club's accent color hex for card/badge tinting (nil falls back to the
    /// app accent in Color.teamAccent).
    var accentColorHex: String? { squad?.colorHex }

    /// The header line, e.g. "4th in NWSL — 21 pts"; nil until loaded or when
    /// ESPN didn't provide a standing summary.
    var standingLine: String? { squad?.standingLine }

    /// The club's real W-D-L record string from the roster payload (e.g. "6-3-2"),
    /// used by the Stats tab's season summary. nil until loaded / when absent.
    var record: String? { squad?.record }

    /// Stats for one player, or nil before the roster (and thus stats) have loaded.
    func stats(for athlete: Athlete) -> PlayerSeasonStats? {
        seasonStats[athlete.id]
    }

    /// Top players in each category, derived from `seasonStats` (so the board and
    /// each player's page always agree). Top 3 with a non-zero value, ranked.
    var teamLeaders: TeamLeaders {
        guard let athletes = squad?.athletes, !seasonStats.isEmpty else {
            return TeamLeaders(topScorers: [], topAssists: [], topCleanSheets: [])
        }
        return TeamLeaders(
            topScorers: leaders(athletes) { $0.goals },
            topAssists: leaders(athletes) { $0.assists },
            topCleanSheets: leaders(athletes) { $0.cleanSheets }
        )
    }

    /// Rank athletes by a stat, keep the top 3 with a value > 0.
    private func leaders(_ athletes: [Athlete], by value: (PlayerSeasonStats) -> Int) -> [StatLeader] {
        athletes
            .compactMap { athlete -> StatLeader? in
                guard let stats = seasonStats[athlete.id] else { return nil }
                let v = value(stats)
                guard v > 0 else { return nil }
                return StatLeader(athleteID: athlete.id, name: athlete.shortName ?? athlete.name, value: v)
            }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0 }
    }

    private func message(for error: Error) -> String {
        switch error {
        case ESPNServiceError.badStatus(let code):
            return "ESPN returned an error (status \(code))."
        case ESPNServiceError.decoding:
            return "Couldn't read the roster response."
        case ESPNServiceError.badURL:
            return "Couldn't build the request. This is a bug — please report it."
        default:
            return "Couldn't load the roster. Check your connection."
        }
    }
}
