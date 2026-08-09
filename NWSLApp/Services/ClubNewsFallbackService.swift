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

    /// One club's news source, from the proxy `/club-news/sources` directory. `deviceFallback` marks
    /// the clubs the Worker's datacenter IP is blocked from (CHI/POR) — the only ones whose health
    /// the app reports back (via `/club-news/device-report`) so the admin Status tab can verify them.
    /// Optional so an older cached `/sources` response (missing the field) still decodes.
    struct Source: Decodable { let abbr: String; let kind: String; let url: String; let deviceFallback: Bool? }

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
        // Device-fetchable sources: an RSS feed (CHI) or a news INDEX whose SSR HTML carries the
        // article link + title + date (POR/Webflow). Both parse fully proxy-side from what the
        // device fetches — no per-article scraping. (`fallback`/`api` clubs never need this.)
        let targets = sources.filter { gaps.contains($0.abbr) && ($0.kind == "rss" || $0.kind == "index") }
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
            // (URLSession follows the site's redirects). ⚠️ UA = iOS SAFARI, never Chrome: the old
            // desktop-Chrome disguise BACKFIRED — chicagostars.com's WAF 403s requests claiming
            // Chrome without Chrome's real TLS fingerprint (curl-reproduced 2026-08-08: Chrome UA
            // 403, iOS Safari UA / no UA 200; POR unaffected either way). An iPhone claiming
            // Safari is the honest, fingerprint-consistent identity for this device.
            var feedReq = URLRequest(url: feedURL)
            feedReq.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent")
            let (body, feedResp) = try await session.data(for: feedReq)
            let feedCode = (feedResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(feedCode), !body.isEmpty else {
                // A non-2xx here on a device-fallback club is the URL-MOVED signal (the whole point of
                // the beacon) — report it loudly instead of the old silent return.
                await reportHealth(src, ok: false, count: 0, error: "feed HTTP \(feedCode)")
                return []
            }

            // Hand the bytes to the proxy to parse with the club's strategy.
            var normReq = URLRequest(url: normalizeURL)
            normReq.httpMethod = "POST"
            normReq.httpBody = body
            let (data, normResp) = try await session.data(for: normReq)
            let normCode = (normResp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(normCode) else {
                await reportHealth(src, ok: false, count: 0, error: "normalize HTTP \(normCode)")
                return []
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cards = (try? decoder.decode([ContentCard].self, from: data)) ?? []
            // 0 cards from a 200 = the site loaded but its structure changed (parser found nothing) —
            // also a health signal, not success.
            await reportHealth(src, ok: !cards.isEmpty, count: cards.count, error: cards.isEmpty ? "0 cards parsed" : nil)
            return cards
        } catch {
            // No silent failure — but it's a fallback, so it degrades to press, never breaks Home.
            Diagnostics.shared.record(.apiFailure, "club-news device fallback \(src.abbr): \(error.localizedDescription)")
            await reportHealth(src, ok: false, count: 0, error: error.localizedDescription)
            return []
        }
    }

    /// Report a device-fetch RESULT to the proxy so the admin Status tab can verify this club.
    /// Only the known device-fallback clubs (CHI/POR) — the proxy rejects the rest — and best-effort
    /// (a failed report never affects Home). Fire-and-forget: the caller doesn't wait on delivery.
    private func reportHealth(_ src: Source, ok: Bool, count: Int, error: String?) async {
        guard src.deviceFallback == true, let url = AppConfig.clubNewsDeviceReportURL() else { return }
        var payload: [String: Any] = ["abbr": src.abbr, "ok": ok, "count": count]
        if let error { payload["error"] = error }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody
        _ = try? await session.data(for: req)
    }

    /// Health-sweep the device-fallback clubs (CHI/POR) REGARDLESS of who's followed, so the admin
    /// Status tab has a fresh beacon per club even if nobody follows them. Reuses the display fetch
    /// (which reports inside) and discards the cards. `skip` = clubs already fetched this load by
    /// `supplementaryCards`, to avoid a double fetch. Throttle the CALLER (this does the work every
    /// time). Best-effort; never throws.
    func runDeviceHealthSweep(skip: Set<String> = []) async {
        guard let sources = await loadSources() else { return }
        let targets = sources.filter { $0.deviceFallback == true && !skip.contains($0.abbr) }
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask { _ = await deviceFetchAndNormalize(target) }
            }
            for await _ in group {}
        }
    }
}
