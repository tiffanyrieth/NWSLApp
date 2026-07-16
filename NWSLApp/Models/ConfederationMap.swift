//
//  ConfederationMap.swift
//  NWSLApp
//
//  Country → confederation → competition-feed scoping (the 2026-07-16 polling-efficiency fix).
//
//  Following ANY national team used to fan the scoreboard poll out to ALL 15 competition feeds
//  every tick (~17 proxy calls per 30s during live windows — the single most wasteful behavior
//  in the app). But a country can only ever appear in (a) the GLOBAL feeds — friendlies (which
//  is also where cross-confederation invitationals like the SheBelieves Cup live), the World
//  Cup/Olympics, and the inter-confederation qualifying playoff — plus (b) its OWN
//  confederation's championship + qualifying feeds. Zambia can never appear in the UEFA Women's
//  Euro; polling it for ZAM followers was pure waste.
//
//  `scopedFeeds(forFollowedCodes:)` is the pure selector MatchStore uses: global feeds + the
//  union of each followed country's confederation feeds (ZAM → ~7 feeds, not 15). Coverage is
//  the FULL FIFA membership (not just the curated 16) because the Browse-all directory is
//  data-driven from ESPN — a user can follow any covered country. An UNMAPPED code fails open:
//  ALL feeds + the code reported back so MatchStore emits a Diagnostics breadcrumb (NO SILENT
//  FAILURES) — coverage can degrade to the old cost, never to a missing fixture.
//
//  Maintenance: a new followable country = one code in its confederation's list below. A new
//  competition feed = an entry in `NationalTeamFeed.all` (Competition.swift) + a `scope` tag
//  here + the proxy/watcher slug lists. Full system doc: docs/national-teams.md.
//

import Foundation

/// FIFA's six regional confederations. Membership essentially never changes (a handful of
/// moves per decade), so a static table is safe; the fail-open fallback covers surprises.
enum Confederation: CaseIterable {
    case uefa       // Europe
    case concacaf   // North/Central America + Caribbean
    case conmebol   // South America
    case caf        // Africa
    case afc        // Asia
    case ofc        // Oceania (no ESPN women's feed today → OFC followers get the globals)
}

enum ConfederationMap {
    /// FIFA code → confederation, full FIFA membership (~210). Codes are FIFA's (the same
    /// 3-letter abbreviation ESPN puts on national-team competitors, e.g. "ZAM", "MWI").
    static let byCode: [String: Confederation] = {
        var map: [String: Confederation] = [:]
        let members: [(Confederation, [String])] = [
            (.uefa, [
                "ALB", "AND", "ARM", "AUT", "AZE", "BLR", "BEL", "BIH", "BUL", "CRO",
                "CYP", "CZE", "DEN", "ENG", "EST", "FRO", "FIN", "FRA", "GEO", "GER",
                "GIB", "GRE", "HUN", "ISL", "IRL", "ISR", "ITA", "KAZ", "KOS", "LVA",
                "LIE", "LTU", "LUX", "MLT", "MDA", "MNE", "NED", "MKD", "NIR", "NOR",
                "POL", "POR", "ROU", "RUS", "SMR", "SCO", "SRB", "SVK", "SVN", "ESP",
                "SWE", "SUI", "TUR", "UKR", "WAL",
            ]),
            (.concacaf, [
                "AIA", "ATG", "ARU", "BAH", "BRB", "BLZ", "BER", "VGB", "CAN", "CAY",
                "CRC", "CUB", "CUW", "DMA", "DOM", "SLV", "GRN", "GUA", "GUY", "HAI",
                "HON", "JAM", "MEX", "MSR", "NCA", "PAN", "PUR", "SKN", "LCA", "VIN",
                "SUR", "TRI", "TCA", "USA", "VIR", "GRL",
            ]),
            (.conmebol, [
                "ARG", "BOL", "BRA", "CHI", "COL", "ECU", "PAR", "PER", "URU", "VEN",
            ]),
            (.caf, [
                "ALG", "ANG", "BEN", "BOT", "BFA", "BDI", "CMR", "CPV", "CTA", "CHA",
                "COM", "CGO", "COD", "CIV", "DJI", "EGY", "EQG", "ERI", "SWZ", "ETH",
                "GAB", "GAM", "GHA", "GUI", "GNB", "KEN", "LES", "LBR", "LBY", "MAD",
                "MWI", "MLI", "MTN", "MRI", "MAR", "MOZ", "NAM", "NIG", "NGA", "RWA",
                "STP", "SEN", "SEY", "SLE", "SOM", "RSA", "SSD", "SDN", "TAN", "TOG",
                "TUN", "UGA", "ZAM", "ZIM",
            ]),
            (.afc, [
                "AFG", "AUS", "BHR", "BAN", "BHU", "BRU", "CAM", "CHN", "TPE", "GUM",
                "HKG", "IND", "IDN", "IRN", "IRQ", "JPN", "JOR", "KGZ", "KUW", "LAO",
                "LBN", "MAC", "MAS", "MDV", "MNG", "MYA", "NEP", "PRK", "OMA", "PAK",
                "PLE", "PHI", "QAT", "KSA", "SGP", "KOR", "SRI", "SYR", "TJK", "THA",
                "TLS", "TKM", "UAE", "UZB", "VIE", "YEM",
            ]),
            (.ofc, [
                "ASA", "COK", "FIJ", "KIR", "NCL", "NZL", "PNG", "SAM", "SOL", "TAH",
                "TGA", "TUV", "VAN",
            ]),
        ]
        for (confed, codes) in members {
            for code in codes { map[code] = confed }
        }
        return map
    }()

    static func confederation(for code: String) -> Confederation? {
        byCode[code.uppercased()]
    }
}

extension NationalTeamFeed {
    /// Which countries a feed can ever contain. `.global` feeds admit any country — friendlies
    /// (incl. cross-confederation invitationals like SheBelieves/Pinatar, which ESPN carries in
    /// or alongside the friendlies pipeline), the World Cup + Olympics, and the
    /// inter-confederation qualifying playoff. `.confed` feeds only ever field their own region.
    enum Scope: Equatable {
        case global
        case confed(Confederation)
    }

    var scope: Scope {
        switch slug {
        case "concacaf.w.gold", "concacaf.womens.championship", "fifa.w.concacaf.olympicsq":
            return .confed(.concacaf)
        case "uefa.weuro", "uefa.w.nations", "fifa.wworldq.uefa":
            return .confed(.uefa)
        case "afc.w.asian.cup":
            return .confed(.afc)
        case "caf.w.nations":
            return .confed(.caf)
        case "conmebol.america.femenina":
            return .confed(.conmebol)
        default:
            // fifa.friendly.w, fifa.shebelieves, fifa.wwc, fifa.w.olympics, fifa.wwcq.ply,
            // global.pinatar_cup — and, deliberately, any FUTURE slug not yet tagged here:
            // an untagged feed is polled for everyone (fail open), never silently skipped.
            return .global
        }
    }

    /// The feeds worth polling for a followed-country set: the globals + the union of each
    /// country's confederation feeds. Pure (unit-tested); the caller emits a Diagnostics
    /// breadcrumb for any `unmapped` code (which fails OPEN to all feeds so coverage can only
    /// degrade to the old cost, never to a missed fixture). Empty follows → no feeds (callers
    /// already guard, but the truthful answer is "nothing to fetch").
    static func scopedFeeds(forFollowedCodes codes: Set<String>) -> (feeds: [NationalTeamFeed], unmapped: [String]) {
        guard !codes.isEmpty else { return ([], []) }
        var confeds: Set<Confederation> = []
        var unmapped: [String] = []
        for code in codes {
            if let confed = ConfederationMap.confederation(for: code) {
                confeds.insert(confed)
            } else {
                unmapped.append(code)
            }
        }
        if !unmapped.isEmpty { return (all, unmapped.sorted()) }
        let feeds = all.filter { feed in
            switch feed.scope {
            case .global: return true
            case .confed(let confed): return confeds.contains(confed)
            }
        }
        return (feeds, [])
    }
}
