//
//  NationalTeamDirectoryStore.swift
//  NWSLApp
//
//  Backs the "Browse all national teams" list with a DATA-DRIVEN set instead of a
//  hand-maintained one: the proxy `/national-teams` route returns the union of ESPN's
//  women's national-team coverage (FIFA code + name + ESPN flag href), so the list reflects
//  real coverage and picks up future ESPN additions with no app release.
//
//  The browse-all set = the curated FEATURED teams (always present, with their bundled vector
//  flags + curated colors) merged with everything ESPN covers (data-driven, ESPN flags). Online
//  -only: a failed fetch surfaces an honest error+retry (the view never shows a blank or an
//  endless spinner). Featured + browse-all flags stay UNBUNDLED beyond the eight — download + cache.
//

import Foundation

@MainActor
@Observable
final class NationalTeamDirectoryStore {
    enum State {
        case idle
        case loading
        case loaded([NationalTeam])
        case failed
    }

    private(set) var state: State = .idle

    /// Load the directory once. Re-entry while loaded is a no-op; a prior failure can retry.
    func load() async {
        if case .loaded = state { return }
        state = .loading
        guard let url = AppConfig.nationalTeamsURL() else {
            Diagnostics.shared.record(.apiFailure, "national-teams url")
            state = .failed
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            state = .loaded(merge(try JSONDecoder().decode([DTO].self, from: data)))
        } catch {
            Diagnostics.shared.record(.apiFailure, "national-teams")
            state = .failed
        }
    }

    /// One pure A-Z list (USA in normal position, no pinning). Curated featured teams win on a
    /// code clash so they keep their bundled vector flag + curated color; everyone else ESPN
    /// covers comes in as a `discovered` team (ESPN flag).
    private func merge(_ dtos: [DTO]) -> [NationalTeam] {
        let featured = NationalTeam.featured
        let featuredCodes = Set(featured.map(\.code))
        let discovered = dtos
            .filter { !featuredCodes.contains($0.code.uppercased()) }
            .map { NationalTeam(discoveredCode: $0.code, name: $0.name, flag: $0.flag) }
        return (featured + discovered)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct DTO: Decodable {
        let code: String
        let name: String
        let flag: String
    }
}
