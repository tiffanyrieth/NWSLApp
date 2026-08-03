//
//  BroadcastInfo.swift
//  NWSLApp
//
//  The "How to Watch" broadcast database — per NWSL broadcast partner: a canonical name, a one-line
//  availability note, an access tier, and device-by-device "find it" steps.
//
//  ⚠️ WHY THIS FILE IS RESEARCH, NOT A LOOKUP TABLE (rewritten 2026-08-03).
//  The owner spent OVER AN HOUR trying to watch a Spirit match on CBSSN before concluding she
//  couldn't without a large subscription. On r/NWSL a fan reports paying **$120/month for Fubo** to
//  watch ION games before discovering ION is free almost everywhere. Those are the two failures this
//  card exists to prevent, and neither is solved by naming the channel — the channel name is the ONE
//  thing the user already has. What they lack is *"where do I actually tap on this device, and is
//  there a free path."* Every entry below is written to answer that.
//
//  The 2026 split (fan-compiled, r/NWSL): 240 matches — 160 FREE, 80 paid.
//    Free: ION 59 · NWSL+ (incl. the old Victory+ slate) 87 · CBS 11 · ABC 3
//    Paid: ESPN 30 · Prime 25 · CBSSN 25
//  CBSSN is the single largest paid block AND the one with no cheap path, which is why it gets the
//  bluntest copy in the file.
//
//  ⚠️ CORRECTIONS PAID FOR IN REAL TIME — do not "simplify" these back:
//   • **Paramount+ does NOT carry CBS Sports Network on ANY tier.** Premium ($13.99) adds your live
//     local CBS *station*, which covers the 11 CBS-network matches and NONE of the 25 CBSSN ones.
//     The previous copy told CBS/CBSSN viewers to "open the Paramount+ app" — that sends someone to
//     buy the wrong subscription and still miss the match.
//   • **Sling does not carry CBSSN either.** A fan bought a $5 Sling day pass to find that out.
//   • **An antenna is not guaranteed.** It depends on tower distance and obstructions; fans are
//     explicit that "it might not work." Tell people to CHECK, don't promise.
//   • **NWSL+ posts full replays a few days later.** This is the genuine answer for a match you
//     cannot get live, and it was missing entirely.
//
//  Resolution is an ORDERED, normalized match (`resolve`), never an exact dictionary hit — ESPN sends
//  free text that drifts ("CBSSN", "CBS Sports Network", "ESPN2", "ESPN Deportes"). An unrecognized
//  partner returns `nil` and the CARD STILL RENDERS an honest unknown state; it never silently
//  vanishes (that was the CBSSN bug) and it never invents steps.
//

import SwiftUI

struct BroadcastInfo {
    let name: String
    /// Brand color — resolved from the canonical `BroadcastBrand` source so it can never
    /// drift from the schedule/match chip color.
    var color: Color { BroadcastBrand.color(for: name) }
    /// One-line availability note.
    let note: String
    /// What it costs to get in. Drives the badge on BOTH surfaces (see `BroadcastAccess`).
    let access: BroadcastAccess
    /// Per-device "how to find it" steps.
    let devices: [Device]

    struct Device: Identifiable {
        /// ⚠️ Keyed on the device LABEL, never `UUID()`. A resolver that constructs a value (the
        /// unknown-broadcaster card does) would otherwise hand `ForEach` fresh ids on every body
        /// pass, re-creating each row and breaking the expand animation.
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

    /// ⚠️ ORDER IS LOAD-BEARING — specific before general, or a general rule swallows a channel.
    /// The traps, each real:
    ///   • `CBSSN` does NOT contain "cbs sports network", so BOTH tokens are needed.
    ///   • A bare `cbs sports` rule would swallow **CBS Sports Golazo Network**, a different channel.
    ///   • `espn+` / `espn2` / `espn deportes` must all precede plain `espn`.
    ///   • ION is matched TOKEN-EXACT. A bare `contains("ion")` matches **"Univision"** — and since
    ///     the app now folds ~15 women's national-team feeds into the schedule, that is not
    ///     hypothetical. It would paint a Univision match with an ION chip and a FREE badge.
    ///   • `nwsl+` before `nwsl`, or "NWSL Championship on CBS" resolves to the streaming service.
    static func resolve(_ raw: String) -> BroadcastInfo? {
        let n = raw.lowercased()
        func has(_ s: String) -> Bool { n.contains(s) }

        // ── ION, token-exact (see the Univision trap above) ────────────────────────────────
        if n == "ion" || n.hasPrefix("ion ") || has("iontelevision") || has("ion television")
            || has("ion plus") || has("scripps") { return ion }

        // ── CBS family, most specific first ───────────────────────────────────────────────
        if has("golazo") { return golazo }
        if has("cbssn") || has("cbs sports network") { return cbssn }
        if has("paramount") { return paramount }
        if has("cbs") { return cbs }

        // ── ESPN family, most specific first ──────────────────────────────────────────────
        if has("deportes") { return espnDeportes }
        if has("espn+") || has("espn plus") { return espnPlus }
        if has("espn2") || has("espnu") || has("espn") { return espn }
        if has("abc") { return abc }

        // ── Streaming ─────────────────────────────────────────────────────────────────────
        if has("nwsl+") || has("nwsl plus") || n == "nwsl" { return nwslPlus }
        if has("victory") { return victoryRetired }
        if has("prime") || has("amazon") { return primeVideo }

        return nil
    }

    // MARK: - The partners

    /// 59 matches — the biggest FREE block, and the one people most often pay for by mistake.
    private static let ion = BroadcastInfo(
        name: "ION",
        note: "Free — no subscription needed. Several ways in.",
        access: .free,
        devices: [
            .init(device: "Antenna",
                  steps: "ION is free over the air. Check your channel at iontelevision.com/find-us — enter your ZIP for the local number. Reception depends on how close the tower is, so check before buying an antenna."),
            .init(device: "Roku",
                  steps: "Roku Channel → Live TV → ION. Don't search the Channel Store for \"ION\" — it returns the wrong results; \"Scripps\" works better."),
            .init(device: "Free apps",
                  steps: "Also carried free on Tubi, Pluto TV and Plex — search \"ION\" in any of them."),
            .init(device: "Fire TV",
                  steps: "Search \"ION\" in the app store, or use Tubi / Pluto TV."),
            .init(device: "Want to record it?",
                  steps: "A FREE Sling account can DVR the ION games — no paid tier needed."),
        ])

    /// 25 matches, no cheap path. The honest answer is the useful one.
    private static let cbssn = BroadcastInfo(
        name: "CBS Sports Network",
        note: "Cable channel — needs a live-TV package. There's no free or cheap way in.",
        access: .paid,
        devices: [
            .init(device: "⚠️ Not Paramount+",
                  steps: "Paramount+ does NOT carry CBS Sports Network on any tier, including Premium. Premium adds your local CBS station — a different channel. Sling doesn't carry it either."),
            .init(device: "Live TV services",
                  steps: "Carried on YouTube TV, Hulu + Live TV, Fubo and DirecTV. All are full live-TV packages, not add-ons."),
            .init(device: "Free alternative",
                  steps: "Can't justify a package for one match? Full replays post to NWSL+ free a few days later."),
        ])

    /// 11 matches. Free over the air, but streaming it needs the pricier Paramount+ tier.
    private static let cbs = BroadcastInfo(
        name: "CBS",
        note: "Free over the air. Streaming it needs Paramount+ Premium.",
        access: .free,
        devices: [
            .init(device: "Antenna",
                  steps: "Free on your local CBS channel with any antenna. Reception varies with tower distance and obstructions — worth checking before you buy."),
            .init(device: "⚠️ Paramount+ tier",
                  steps: "Only Paramount+ PREMIUM ($13.99) includes your live local CBS station. The cheaper Essential tier does NOT — you'd pay and still miss the match."),
            .init(device: "Live TV services",
                  steps: "YouTube TV, Hulu + Live TV, Fubo and DirecTV all carry CBS."),
            .init(device: "Free alternative",
                  steps: "Full replays post to NWSL+ free a few days later."),
        ])

    private static let paramount = BroadcastInfo(
        name: "Paramount+",
        note: "Streaming on Paramount+ (subscription required).",
        access: .paid,
        devices: [
            .init(device: "Roku / Fire TV", steps: "Open Paramount+ → Live TV → find the match."),
            .init(device: "Phone / Tablet", steps: "Open the Paramount+ app and look under Live."),
            .init(device: "PC / Laptop", steps: "Go to paramountplus.com → Live."),
            .init(device: "⚠️ Worth knowing",
                  steps: "Paramount+ does not include CBS Sports Network. If this match moves to CBSSN, a Paramount+ subscription won't reach it."),
        ])

    private static let golazo = BroadcastInfo(
        name: "CBS Sports Golazo Network",
        note: "Free ad-supported soccer channel from CBS Sports.",
        access: .free,
        devices: [
            .init(device: "Free apps", steps: "Carried free on Pluto TV, Tubi, Roku Channel and Samsung TV Plus — search \"Golazo\"."),
            .init(device: "Phone / PC", steps: "Also streams free at cbssports.com and in the CBS Sports app."),
            .init(device: "⚠️ Not the same as CBSSN", steps: "Golazo Network is a separate free channel from CBS Sports Network. A match listed on CBSSN will not be here."),
        ])

    /// 3 matches. FREE over the air — the app used to badge this as a subscription.
    private static let abc = BroadcastInfo(
        name: "ABC",
        note: "Free over the air on your local ABC station.",
        access: .free,
        devices: [
            .init(device: "Antenna", steps: "Free on your local ABC channel with any antenna. Reception depends on tower distance — check before buying."),
            .init(device: "Streaming", steps: "Also on the ESPN app (sign in with a TV provider), YouTube TV, Hulu + Live TV and Fubo."),
            .init(device: "Free alternative", steps: "Full replays post to NWSL+ free a few days later."),
        ])

    private static let espn = BroadcastInfo(
        name: "ESPN",
        note: "On ESPN / ESPN2 — needs a TV provider or an ESPN plan.",
        access: .paid,
        devices: [
            .init(device: "⚠️ Which ESPN plan",
                  steps: "ESPN sells several tiers and the gap is wide (~$13 for the cheaper tier vs ~$30). Check which one carries live ESPN2 before subscribing."),
            .init(device: "Roku / Fire TV", steps: "Open the ESPN app → Live → find the NWSL match."),
            .init(device: "Phone / Tablet", steps: "ESPN app → search NWSL → tap the live match."),
            .init(device: "Live TV services", steps: "Included with YouTube TV, Hulu + Live TV, Fubo and DirecTV."),
        ])

    private static let espnPlus = BroadcastInfo(
        name: "ESPN+",
        note: "Streaming on ESPN+ (separate from cable ESPN).",
        access: .paid,
        devices: [
            .init(device: "⚠️ Not the same as ESPN",
                  steps: "ESPN+ is its own subscription. A cable/TV-provider ESPN login does not unlock ESPN+ matches, and vice versa."),
            .init(device: "Roku / Fire TV", steps: "Open the ESPN app → ESPN+ tab → find the match."),
            .init(device: "Phone / PC", steps: "ESPN app or espn.com → search NWSL."),
        ])

    private static let espnDeportes = BroadcastInfo(
        name: "ESPN Deportes",
        note: "Spanish-language broadcast on ESPN Deportes.",
        access: .paid,
        devices: [
            .init(device: "⚠️ Spanish commentary", steps: "This listing is the Spanish-language feed. The same match is usually also on an English ESPN channel."),
            .init(device: "TV provider", steps: "ESPN Deportes on your cable or live-TV package."),
            .init(device: "Phone / PC", steps: "ESPN app → set language to Spanish → find the match."),
        ])

    /// Free, ad-supported — and the fallback for anything you can't get live.
    private static let nwslPlus = BroadcastInfo(
        name: "NWSL+",
        note: "The league's own platform — free, ad-supported.",
        access: .free,
        devices: [
            .init(device: "Phone / Tablet", steps: "Download \"NWSL\" from the App Store / Play Store and register — it's free."),
            .init(device: "PC / Laptop", steps: "Go to plus.nwslsoccer.com and register."),
            .init(device: "TV", steps: "Search \"NWSL\" on Roku, Fire TV, Apple TV, Google TV, LG, Samsung or Vizio."),
            .init(device: "⭐ Replays",
                  steps: "Full replays of matches from every broadcaster post here a few days later — the free way to catch anything you couldn't watch live."),
            .init(device: "Outside the US?",
                  steps: "International coverage differs, and some matches shown elsewhere in the US aren't available abroad."),
        ])

    /// ⚠️ Kept deliberately. ESPN's feed may still carry the string for a while, and a user seeing a
    /// Victory+ chip needs to be told WHY it won't work — not dropped to a generic unknown card.
    private static let victoryRetired = BroadcastInfo(
        name: "Victory+",
        note: "Victory+ no longer carries NWSL. This match moved to NWSL+.",
        access: .free,
        devices: [
            .init(device: "What happened",
                  steps: "The NWSL ended its Victory+ deal in July 2026. Every match that was on Victory+ is now on NWSL+, free."),
            .init(device: "Watch on NWSL+",
                  steps: "Download \"NWSL\" from the App Store / Play Store, or go to plus.nwslsoccer.com. Free, no subscription."),
        ])

    private static let primeVideo = BroadcastInfo(
        name: "Prime Video",
        note: "Included with an Amazon Prime membership.",
        access: .paid,
        devices: [
            .init(device: "Roku / Fire TV", steps: "Open Prime Video → search \"NWSL\" → select the live match."),
            .init(device: "Smart TV", steps: "Open the Prime Video app → search \"NWSL\"."),
            .init(device: "Phone / Tablet", steps: "Prime Video app → search \"NWSL\"."),
            .init(device: "PC / Laptop", steps: "Go to primevideo.com → search \"NWSL\"."),
        ])
}

/// What it costs to get in.
///
/// ⚠️ **TRI-STATE, deliberately — not a `Bool`.** The old pair was `(free: Bool, label: String)` with
/// an unknown broadcaster defaulting to `false`, which rendered a confident **SUBSCRIPTION** badge for
/// a channel we had never heard of — possibly a free over-the-air one. That is a fabricated paywall,
/// and the banned "silent fallback indistinguishable from success." `unknown` renders NO badge.
enum BroadcastAccess {
    case free
    case paid
    case unknown

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

    /// ⚠️ THE ONE SOURCE OF TRUTH. Match Detail and Home's Coming Up used to answer this from two
    /// separate substring tables that DISAGREED — ABC read SUBSCRIPTION on one screen and FREE on the
    /// other (FREE is correct; it's over the air), and any "CBS Sports*" string read FREE on Home
    /// while the real answer is a paid cable package. Both surfaces now call this.
    static func of(_ broadcast: String?) -> BroadcastAccess {
        BroadcastInfo.info(for: broadcast)?.access ?? .unknown
    }
}
