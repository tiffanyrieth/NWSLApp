//
//  NWSLLiveActivityBundle.swift
//  NWSLLiveActivity — the WidgetKit extension hosting the V2 Live Activity.
//
//  Entry point for the extension. Only the Live Activity (MatchLiveActivity) ships for now; home/lock
//  widgets can be added to this bundle later. The Activity is driven entirely by ActivityKit content
//  state pushed from the watcher — no networking, no image download (that's V1's NSE). Silent always.
//

import SwiftUI
import WidgetKit

@main
struct NWSLLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MatchLiveActivity()
    }
}
