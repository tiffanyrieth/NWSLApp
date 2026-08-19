//
//  BroadcastInfo.swift
//  NWSLApp
//
//  The "How to Watch" broadcast database. Per partner: a canonical name, a one-line note, an access
//  class + label, and the rows the "Find it" expansion reveals.
//
//  ⚠️ CONTENT IS OWNED BY THE DESIGN HANDOFF — "How to Watch v2 — Broadcast Update" (2026-08-03).
//  Every note, access label and row below is verbatim from it. Do NOT add rows, prices, warnings or
//  re-phrasings; the handoff's "What NOT to do" is explicit: no prices, no "NOT on X" negativity, no
//  emoji, no information overload (one service/device + one short line).
//
//  WHY THE FEATURE EXISTS (owner, first-hand). The card used to render NOTHING for CBSSN — the lookup
//  was an exact-string dictionary and the view had no else-branch. The app being SILENT is what sent
//  her to Reddit for an hour, where she then found misleading advice. The defect was absence, not
//  misinformation, and the bar for every entry here is: good enough that a fan never leaves for Reddit.
//
//  TWO CLASSES, same UI, different expansion content:
//   • Class 1 (free) — rows are DEVICES. The barrier is finding the app/channel.
//   • Class 2 (subscription) — rows are SERVICE OPTIONS. The barrier is knowing who carries it.
//
//  Resolution is an ORDERED, normalized match (`resolve`), never an exact dictionary hit — ESPN sends
//  free text that drifts ("CBSSN", "ESPN2", "ESPN Deportes"). An unrecognized partner returns nil and
//  the CARD STILL RENDERS an honest unknown state (see HowToWatchCard) — never silence again.
//

import SwiftUI

struct BroadcastInfo {
    let name: String
    /// Brand color — resolved from the canonical `BroadcastBrand` source so it can never
    /// drift from the schedule/match chip color.
    var color: Color { BroadcastBrand.color(for: name) }
    /// One-line availability note.
    let note: String
    /// Free vs subscription, and the label shown beside the chip.
    let access: BroadcastAccess
    /// The "Find it" rows — devices (Class 1) or services (Class 2).
    let devices: [Device]

    struct Device: Identifiable {
        /// ⚠️ Keyed on the LABEL, never `UUID()`. The unknown-broadcaster path constructs a value, and
        /// fresh ids on every body pass would re-create each `ForEach` row and break the expand
        /// animation.
        var id: String { device }
        let device: String
        let steps: String
    }

    /// Resolve a broadcast label to its guide, or nil when we genuinely don't know it.
    static func info(for broadcast: String?) -> BroadcastInfo? {
        guard let raw = broadcast?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }
        return resolve(raw)
    }

    /// ⚠️ ORDER IS LOAD-BEARING — specific before general (the handoff calls this out too). Traps:
    ///   • `CBSSN` does NOT contain "cbs sports network", so both tokens are needed, and both must
    ///     precede the generic `cbs` case.
    ///   • `espn deportes` / `espn+` / `espn2` must all precede plain `espn`.
    ///   • ION is matched TOKEN-EXACT. A bare `contains("ion")` matches "Univision" — and the app
    ///     folds ~15 women's national-team feeds into the schedule, so that is not hypothetical.
    ///   • `nwsl+` before a bare `nwsl`, or "NWSL Championship on CBS" resolves to the streamer.
    static func resolve(_ raw: String) -> BroadcastInfo? {
        let n = raw.lowercased()
        func has(_ s: String) -> Bool { n.contains(s) }

        if n == "ion" || n.hasPrefix("ion ") || has("iontelevision") || has("ion television")
            || has("scripps") { return ion }

        // ⚠️ Golazo BEFORE the "cbs sports" check. "CBS Sports Golazo Network" contains "cbs sports",
        // but Golazo is a FREE FAST channel, not the paid cable CBSSN — resolving it to CBSSN would
        // paint a free channel with a SUBSCRIPTION badge, the exact fabricated-paywall this feature
        // exists to prevent. The design handoff carries no Golazo entry, so route it to the honest
        // unknown card (nil → no badge) rather than a wrong answer. NWSL doesn't currently air on
        // Golazo, so this is defensive, but the cost of a wrong free/paid claim is high.
        if has("golazo") { return nil }
        if has("cbssn") || has("cbs sports") { return cbssn }
        if has("paramount") { return paramount }
        if has("cbs") { return cbs }

        if has("deportes") { return espnDeportes }
        if has("espn+") || has("espn plus") || has("espn select") { return espnPlus }
        if has("espn2") { return espn2 }
        if has("espn") { return espn }
        if has("abc") { return abc }

        if has("nwsl+") || has("nwsl plus") || n == "nwsl" { return nwslPlus }
        if has("victory") { return victoryPlus }
        if has("prime") || has("amazon") { return primeVideo }

        return nil
    }

    // MARK: - Class 1 — free (device-focused steps)

    private static let ion = BroadcastInfo(
        name: "ION",
        note: "Free to watch on ION.",
        access: .free(label: "Free over-the-air"),
        devices: [
            .init(device: "Roku", steps: "Search \"Scripps\" or \"ION\" in Channel Store. \"ION\" alone may show wrong results, try \"Scripps News\" first"),
            .init(device: "Fire TV", steps: "Search \"ION\" in the Fire TV app store"),
            .init(device: "Samsung TV", steps: "Available in Samsung TV Plus free channels. Check your channel guide"),
            .init(device: "Phone / PC", steps: "Go to iontelevision.com or use the ION app"),
        ])

    /// ⚠️ Dormant, deliberately (handoff: "Don't remove Victory+"). Costs nothing in code and
    /// future-proofs a return, even years out.
    private static let victoryPlus = BroadcastInfo(
        name: "Victory+",
        note: "Free streaming, no subscription needed.",
        access: .free(label: "Free app"),
        devices: [
            .init(device: "Roku", steps: "Search \"Victory Plus\" spelled out. The \"Victory+\" result is a different (church) app"),
            .init(device: "Fire TV", steps: "Search \"Victory Plus\" in the app store"),
            .init(device: "Phone / Tablet", steps: "Download \"Victory+\" from the App Store or Play Store"),
            .init(device: "PC / Laptop", steps: "Go to victoryplus.com and create a free account"),
        ])

    private static let nwslPlus = BroadcastInfo(
        name: "NWSL+",
        note: "NWSL's own streaming platform, free to use.",
        access: .free(label: "Free app"),
        devices: [
            .init(device: "Phone / Tablet", steps: "Download the NWSL app from App Store or Play Store"),
            .init(device: "PC / Laptop", steps: "Go to plus.nwslsoccer.com"),
            .init(device: "Roku / Fire TV", steps: "Search \"NWSL\" in the app store"),
        ])

    private static let abc = BroadcastInfo(
        name: "ABC",
        note: "Free on ABC with an antenna. Also available through the ESPN app.",
        access: .free(label: "Free over-the-air"),
        devices: [
            .init(device: "TV / Antenna", steps: "Tune to your local ABC channel"),
            .init(device: "Roku / Fire TV", steps: "Open the ESPN app. ABC sports are available there"),
            .init(device: "Phone / Tablet", steps: "Open the ESPN app and look for the live game"),
            .init(device: "PC / Laptop", steps: "Go to espn.com/watch"),
        ])

    private static let cbs = BroadcastInfo(
        name: "CBS",
        note: "Free on CBS broadcast TV with an antenna.",
        access: .free(label: "Free over-the-air"),
        devices: [
            .init(device: "TV / Antenna", steps: "Tune to your local CBS channel"),
            .init(device: "Roku / Fire TV", steps: "Open the Paramount+ app and search \"NWSL\""),
            .init(device: "Phone / Tablet", steps: "Open the Paramount+ app or CBSSports.com"),
            .init(device: "PC / Laptop", steps: "Go to paramountplus.com and search \"NWSL\""),
        ])

    // MARK: - Class 2 — subscription (service options)

    private static let cbssn = BroadcastInfo(
        name: "CBS Sports Network",
        note: "CBS Sports Network, available through live TV streaming services.",
        access: .paid(label: "Live TV subscription"),
        devices: [
            .init(device: "YouTube TV", steps: "Included in the base plan"),
            .init(device: "Hulu + Live TV", steps: "Included in the live TV plan"),
            .init(device: "Fubo", steps: "Included in Fubo plans"),
            .init(device: "DirecTV Stream", steps: "Included in the MySports package"),
        ])

    private static let espn = BroadcastInfo(
        name: "ESPN",
        note: "Available on ESPN through cable or the ESPN app.",
        access: .paid(label: "Cable / ESPN app"),
        devices: espnServices)

    private static let espn2 = BroadcastInfo(
        name: "ESPN2",
        note: "Available on ESPN2 through cable or the ESPN standalone app.",
        access: .paid(label: "Cable / ESPN app"),
        devices: espnServices)

    /// Shared by ESPN and ESPN2 — the handoff lists one table for both.
    private static let espnServices: [Device] = [
        .init(device: "ESPN Unlimited", steps: "Standalone streaming, includes all ESPN channels"),
        .init(device: "YouTube TV", steps: "Included in the base plan"),
        .init(device: "Hulu + Live TV", steps: "Included in the live TV plan"),
        .init(device: "Fubo", steps: "Included in Fubo plans"),
        .init(device: "DirecTV Stream", steps: "Included in most plans"),
        .init(device: "Sling TV", steps: "Included in Sling Orange"),
    ]

    private static let espnDeportes = BroadcastInfo(
        name: "ESPN Deportes",
        note: "ESPN's Spanish-language channel, available through cable or the ESPN app.",
        access: .paid(label: "Cable / ESPN app"),
        devices: [
            .init(device: "ESPN Unlimited", steps: "Standalone streaming, includes ESPN Deportes"),
            .init(device: "YouTube TV", steps: "Available with the Spanish Plus add-on"),
            .init(device: "Fubo", steps: "Available with the Latino add-on"),
            .init(device: "DirecTV Stream", steps: "Available in select packages"),
        ])

    private static let espnPlus = BroadcastInfo(
        name: "ESPN+",
        note: "Streaming on the ESPN app.",
        access: .paid(label: "ESPN streaming"),
        devices: [
            .init(device: "ESPN Select", steps: "ESPN's base streaming plan"),
            .init(device: "ESPN Unlimited", steps: "Includes Select plus all ESPN channels"),
            .init(device: "Disney Bundle", steps: "Available bundled with Disney+ and Hulu"),
        ])

    private static let paramount = BroadcastInfo(
        name: "Paramount+",
        note: "Streaming on Paramount+.",
        access: .paid(label: "Subscription"),
        devices: [
            .init(device: "Roku / Fire TV", steps: "Open the Paramount+ app → Live TV → NWSL"),
            .init(device: "Phone / Tablet", steps: "Open the Paramount+ app and look for Live"),
            .init(device: "PC / Laptop", steps: "Go to paramountplus.com → Live"),
        ])

    private static let primeVideo = BroadcastInfo(
        name: "Prime Video",
        note: "Streaming with an Amazon Prime membership.",
        access: .paid(label: "Prime membership"),
        devices: [
            .init(device: "Roku / Fire TV", steps: "Open Prime Video → search \"NWSL\" → select the live match"),
            .init(device: "Smart TV", steps: "Open the Prime Video app → search \"NWSL\""),
            .init(device: "Phone / Tablet", steps: "Open the Prime Video app → search \"NWSL\""),
            .init(device: "PC / Laptop", steps: "Go to primevideo.com → search \"NWSL\""),
        ])
}

/// What it costs to get in, plus the label shown beside the chip.
///
/// ⚠️ **TRI-STATE, deliberately — the handoff's snippet uses `(free: Bool, label: String)`.** With a
/// Bool, an unrecognized channel falls to `false` and renders a confident **SUBSCRIPTION** badge for
/// something we have never heard of — possibly a free over-the-air channel. That is a fabricated
/// paywall, and the banned "fallback indistinguishable from success". `unknown` renders NO badge and
/// NO label. For every string the handoff specifies the result is identical to its spec.
enum BroadcastAccess: Equatable {
    case free(label: String)
    case paid(label: String)
    case unknown

    var isFree: Bool { if case .free = self { return true }; return false }

    /// Badge text, or nil when we don't know and must not guess.
    var badge: String? {
        switch self {
        case .free:    return "FREE"
        case .paid:    return "SUBSCRIPTION"
        case .unknown: return nil
        }
    }

    /// The compact form for dense rows (Home's Coming Up).
    var shortBadge: String? {
        switch self {
        case .free:    return "FREE"
        case .paid:    return "SUB"
        case .unknown: return nil
        }
    }

    /// The line beside the chip ("Free over-the-air", "Live TV subscription", …).
    var label: String? {
        switch self {
        case .free(let l), .paid(let l): return l
        case .unknown:                   return nil
        }
    }

    /// ⚠️ THE ONE SOURCE OF TRUTH. Match Detail and Home's Coming Up used to answer this from two
    /// separate substring tables that DISAGREED — ABC read SUBSCRIPTION on one screen and FREE on the
    /// other (FREE is correct; it's over the air), and any "CBS Sports*" string read FREE on Home
    /// while it needs a paid live-TV package. Both surfaces now call this.
    static func of(_ broadcast: String?) -> BroadcastAccess {
        BroadcastInfo.info(for: broadcast)?.access ?? .unknown
    }
}
