//
//  BroadcastInfo.swift
//  NWSLApp
//
//  The "How to Watch" broadcast database — ported verbatim from the design
//  handoff (`MatchDetailParts.jsx` → `BROADCAST_INFO`). For each NWSL broadcast
//  partner: a service name, brand color, a one-line note, and device-by-device
//  "find it" steps (the friendly part — e.g. ION's "search Scripps, not ION").
//
//  Keyed by the broadcast label ESPN gives on an Event (`event.broadcastName`);
//  `info(for:)` resolves it (with a couple of aliases, e.g. "Amazon Prime" →
//  Prime Video). Returns nil for an unrecognized partner so the How-to-Watch
//  section simply doesn't render. Complements `BroadcastLink` (which maps a name
//  to a single watch URL); this carries the richer per-device guidance.
//

import SwiftUI

struct BroadcastInfo {
    let name: String
    /// Brand color for the service icon tile.
    let color: Color
    /// One-line availability note.
    let note: String
    /// Per-device "how to find it" steps.
    let devices: [Device]

    struct Device: Identifiable {
        let id = UUID()
        let device: String
        let steps: String
    }

    /// Resolve a broadcast label (ESPN's `broadcastName`) to its guide, or nil.
    static func info(for broadcast: String?) -> BroadcastInfo? {
        guard let broadcast else { return nil }
        return all[broadcast]
    }

    private static let all: [String: BroadcastInfo] = [
        "CBS": BroadcastInfo(
            name: "CBS", color: Color(hex: "#1A73E8"),
            note: "Available on CBS broadcast TV, CBS Sports Network, and Paramount+",
            devices: [
                .init(device: "TV / Antenna", steps: "Tune to your local CBS channel"),
                .init(device: "Roku / Fire TV", steps: "Open the Paramount+ app and search \"NWSL\""),
                .init(device: "Phone / Tablet", steps: "Open Paramount+ app or CBSSports.com"),
                .init(device: "PC / Laptop", steps: "Go to paramountplus.com and search \"NWSL\""),
            ]),
        "CBS Sports": BroadcastInfo(
            name: "CBS Sports", color: Color(hex: "#1A73E8"),
            note: "Available on CBS Sports Network and Paramount+",
            devices: [
                .init(device: "TV / Antenna", steps: "CBS Sports Network on your cable/streaming TV provider"),
                .init(device: "Roku / Fire TV", steps: "Open the Paramount+ app and search \"NWSL\""),
                .init(device: "Phone / Tablet", steps: "Open Paramount+ app or CBSSports.com"),
                .init(device: "PC / Laptop", steps: "Go to paramountplus.com and search \"NWSL\""),
            ]),
        "Paramount+": BroadcastInfo(
            name: "Paramount+", color: Color(hex: "#0064FF"),
            note: "Streaming on Paramount+ (subscription required)",
            devices: [
                .init(device: "Roku / Fire TV", steps: "Open Paramount+ app → Live TV → NWSL"),
                .init(device: "Phone / Tablet", steps: "Open the Paramount+ app and look for Live"),
                .init(device: "PC / Laptop", steps: "Go to paramountplus.com → Live"),
            ]),
        "ESPN": BroadcastInfo(
            name: "ESPN", color: Color(hex: "#D32F2F"),
            note: "Available on ESPN, ESPN2, ABC, and the ESPN App",
            devices: [
                .init(device: "TV / Cable", steps: "ESPN or ESPN2 on your cable/streaming TV provider"),
                .init(device: "Roku / Fire TV", steps: "Open the ESPN app and look for NWSL under Live"),
                .init(device: "Phone / Tablet", steps: "Open the ESPN app → search NWSL → tap the live game"),
                .init(device: "PC / Laptop", steps: "Go to espn.com/watch and find the NWSL match"),
            ]),
        "Prime Video": primeVideo,
        "Amazon Prime": primeVideo,   // alias
        "ION": BroadcastInfo(
            name: "ION", color: Color(hex: "#6B4EFF"),
            note: "Free to watch — available on Scripps/ION channels",
            devices: [
                .init(device: "Roku", steps: "Search \"Scripps\" or \"ION\" in Channel Store. Tip: searching \"ION\" alone may show wrong results — try \"Scripps News\" first"),
                .init(device: "Fire TV", steps: "Search \"ION\" in the Fire TV app store"),
                .init(device: "Samsung TV", steps: "ION is available in Samsung TV Plus free channels — check your channel guide"),
                .init(device: "Phone / PC", steps: "Go to iontelevision.com or use the Perplexity app for a free stream"),
            ]),
        "Victory+": BroadcastInfo(
            name: "Victory+", color: Color(hex: "#30D158"),
            note: "Free streaming — no subscription needed!",
            devices: [
                .init(device: "Roku", steps: "Search \"Victory Plus\" (not just \"Victory\" — that shows church services). Look for the soccer logo."),
                .init(device: "Fire TV", steps: "Search \"Victory Plus\" in the app store"),
                .init(device: "Phone / Tablet", steps: "Download \"Victory+\" from the App Store / Play Store"),
                .init(device: "PC / Laptop", steps: "Go to victoryplus.com and create a free account"),
            ]),
        "NWSL+": BroadcastInfo(
            name: "NWSL+", color: Color(hex: "#FF6B9D"),
            note: "NWSL's own streaming platform",
            devices: [
                .init(device: "Phone / Tablet", steps: "Download the NWSL app from App Store / Play Store"),
                .init(device: "PC / Laptop", steps: "Go to plus.nwslsoccer.com"),
                .init(device: "Roku / Fire TV", steps: "The NWSL app is available on most streaming devices — search \"NWSL\""),
            ]),
    ]

    private static let primeVideo = BroadcastInfo(
        name: "Prime Video", color: Color(hex: "#00A8E1"),
        note: "Streaming free with Amazon Prime membership",
        devices: [
            .init(device: "Roku / Fire TV", steps: "Open Prime Video → search \"NWSL\" → select the live match"),
            .init(device: "Smart TV", steps: "Open Prime Video app → search \"NWSL\""),
            .init(device: "Phone / Tablet", steps: "Open the Prime Video app → search \"NWSL\""),
            .init(device: "PC / Laptop", steps: "Go to primevideo.com → search \"NWSL\""),
        ])
}
