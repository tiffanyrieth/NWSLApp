//
//  Date+RelativeAgo.swift
//  NWSLApp
//
//  One shared "2h ago" formatter for the content cards. Extracted from the old
//  FeedCard (which kept a private RelativeDateTimeFormatter) because five of the
//  seven card variants show a relative timestamp and a single cached formatter is
//  both cheaper (RelativeDateTimeFormatter allocation isn't free) and consistent.
//

import Foundation

extension Date {
    /// A short relative label for how long ago this date was ("2h ago", "3d ago").
    var relativeAgo: String {
        Self.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated   // "2h ago"
        return f
    }()
}
