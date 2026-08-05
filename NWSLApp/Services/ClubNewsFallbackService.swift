//
//  ClubNewsFallbackService.swift
//  NWSLApp
//
//  Phase 2b — the DYNAMIC device-IP fallback for Home club news. Some club sites block the
//  proxy's Cloudflare datacenter IP (CHI today; any club could start tomorrow), so the proxy
//  returns no OFFICIAL news for them and they fall back to third-party press. This service
//  closes that gap from the DEVICE's residential IP: for any followed club with no official
//  news card, it fetches the club's own feed locally and hands the bytes to the proxy to
//  normalize (the proxy owns the parsing — the app stays thin). It's driven purely by "did the
//  proxy return official news for this club" — no hardcoded per-club list — so it SELF-HEALS:
//  the moment the proxy can serve a club officially again, this finds no gap and does nothing.
//

import Foundation

struct ClubNewsFallbackService {
    var session: URLSession = .shared

    /// One club's news source, from the proxy `/club-news/sources` directory.
    struct Source: Decodable { let abbr: String; let kind: String; let url: String }

    /// For each followed club with NO official (sourceType `.club`) news card in `existing`,
    /// device-fetch its RSS source and normalize it via the proxy. Additive + best-effort:
    /// any per-club failure is skipped (that club just keeps its press fallback). Returns the
    /// supplementary official cards to merge into Home.
    func supplementaryCards(existing: [ContentCard], followed: Set<String>) async -> [ContentCard] {
        guard !followed.isEmpty else { return [] }
        let officialCards: [ContentCard] = existing.filter {
            $0.layout == .newsArticle && $0.resolvedSourceType == .club
        }
        let hasOfficial: Set<String> = Set(officialCards.compactMap { $0.teamAbbreviation })
        let gaps: Set<String> = followed.subtracting(hasOfficial)
        guard !gaps.isEmpty, let sources = await loadSources() else { return [] }
        // Only clubs with a device-fetchable RSS source (the clean case the proxy normalize
        // supports today). An index-blocked club (POR) needs per-article scraping its own site
        // also blocks, so it isn't attempted — it stays on press fallback.
        let targets = sources.filter { gaps.contains($0.abbr) && $0.kind == "rss" }
        guard !targets.isEmpty else { return [] }

        var out: [ContentCard] = []
        await withTaskGroup(of: [ContentCard].self) { group in
            for target in targets {
                group.addTask { await deviceFetchAndNormalize(target) }
            }
            for await cards in group { out.append(contentsOf: cards) }
        }
        return out
    }

    private func loadSources() async -> [Source]? {
        guard let url = AppConfig.clubNewsSourcesURL() else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return try JSONDecoder().decode([Source].self, from: data)
        } catch {
            return nil
        }
    }

    private func deviceFetchAndNormalize(_ src: Source) async -> [ContentCard] {
        guard let feedURL = URL(string: src.url),
              let normalizeURL = AppConfig.clubNewsNormalizeURL(abbr: src.abbr) else { return [] }
        do {
            // The DEVICE's residential IP fetches the club feed the Worker is blocked from
            // (URLSession follows the site's redirects). A browser-ish UA in case the club's
            // WordPress blocks obvious bots.
            var feedReq = URLRequest(url: feedURL)
            feedReq.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
                forHTTPHeaderField: "User-Agent")
            let (body, feedResp) = try await session.data(for: feedReq)
            guard (feedResp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
                  !body.isEmpty else { return [] }

            // Hand the bytes to the proxy to parse with the club's strategy.
            var normReq = URLRequest(url: normalizeURL)
            normReq.httpMethod = "POST"
            normReq.httpBody = body
            let (data, normResp) = try await session.data(for: normReq)
            guard (normResp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return [] }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode([ContentCard].self, from: data)) ?? []
        } catch {
            // No silent failure — but it's a fallback, so it degrades to press, never breaks Home.
            Diagnostics.shared.record(.apiFailure, "club-news device fallback \(src.abbr): \(error.localizedDescription)")
            return []
        }
    }
}
