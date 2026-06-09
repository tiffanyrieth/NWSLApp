//
//  BroadcastLink.swift
//  NWSLApp
//
//  Maps an ESPN broadcast name (e.g. "Prime Video", "Paramount+", "ESPN") to the
//  streaming service's watch URL, so a match's 📺 label can become a tappable
//  "where to watch" link. The match between ESPN's free-text names and a partner
//  is fuzzy on purpose (ESPN labels drift), so we substring-match lowercased.
//
//  Returns nil for an unrecognized broadcaster — callers keep the label
//  non-tappable in that case rather than guessing a wrong destination.
//

import Foundation

enum BroadcastLink {
    static func url(for broadcastName: String) -> URL? {
        let name = broadcastName.lowercased()
        let destination: String?
        switch true {
        case name.contains("amazon"), name.contains("prime"):
            destination = "https://www.amazon.com/gp/video/storefront"
        case name.contains("paramount"):
            destination = "https://www.paramountplus.com/sports/"
        case name.contains("espn"), name.contains("abc"):
            destination = "https://www.espn.com/watch/"
        case name.contains("cbs"):
            destination = "https://www.cbssports.com/soccer/nwsl/"
        case name.contains("ion"):
            destination = "https://www.iontelevision.com/watch"
        case name.contains("victory"):
            destination = "https://www.victoryplus.com/"
        case name.contains("nwsl+"), name.contains("nwsl plus"):
            destination = "https://www.nwslsoccer.com/nwslplus"
        default:
            destination = nil
        }
        return destination.flatMap(URL.init(string:))
    }
}
