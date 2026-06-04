//
//  ESPNService.swift
//  NWSLApp
//
//  Thin HTTP client around ESPN's unofficial NWSL endpoints.
//  See CLAUDE.md → "Data Source" — this API is not officially supported,
//  so we decode defensively (see Scoreboard.swift) and surface typed errors.
//

import Foundation

enum ESPNServiceError: Error {
    case badStatus(Int)
    case decoding(Error)
    case badURL
}

struct ESPNService {
    var session: URLSession = .shared
    // Force-unwrap is safe: the string is a compile-time constant valid URL.
    // If a future edit makes it invalid, this crashes on first launch in dev — the right time to catch it.
    private let base = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/usa.nwsl/")!

    // When `year` is provided, requests the full season via
    // `?dates=YYYY0101-YYYY1231&limit=500` — the form the API probe confirmed
    // returns the entire season (the default response caps at 100 events).
    func fetchScoreboard(year: Int? = nil) async throws -> Scoreboard {
        let endpoint = base.appendingPathComponent("scoreboard")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ESPNServiceError.badURL
        }
        if let year {
            components.queryItems = [
                URLQueryItem(name: "dates", value: "\(year)0101-\(year)1231"),
                URLQueryItem(name: "limit", value: "500"),
            ]
        }
        guard let url = components.url else {
            throw ESPNServiceError.badURL
        }

        return try await fetch(Scoreboard.self, from: url)
    }

    // Fetches the league's club directory from the `teams` endpoint and returns
    // the flattened, alphabetically-sorted active clubs (see Club.swift).
    func fetchTeams() async throws -> [Club] {
        let url = base.appendingPathComponent("teams")
        return try await fetch(TeamsResponse.self, from: url).clubs
    }

    // Shared GET-and-decode: one place for the status check and typed-error
    // wrapping, generic over whatever Decodable an endpoint returns.
    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ESPNServiceError.badStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ESPNServiceError.decoding(error)
        }
    }
}
