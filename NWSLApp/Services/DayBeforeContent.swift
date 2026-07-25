//
//  DayBeforeContent.swift
//  NWSLApp
//
//  The PURE content seam for the Tier-1 day-before (24h) match reminder — the title,
//  body, and image-card model, built with NO store / actor / UIKit dependency so it's
//  directly unit-testable (the same shape as FollowSyncCoordinator.resolveFollowOps /
//  NotificationSyncCoordinator.decideRestore). NotificationScheduler calls this to build
//  each reminder; DayBeforeCardRenderer turns the `card` model into the attachment image.
//
//  Framing (owner, 2026-07-24): the day-before notice is a HEADS-UP — "your team plays
//  tomorrow, at what time, how to watch." The opponent + home/away live on the card image,
//  NOT in the text; venue is dropped (low value here). See docs/notifications.md §1.
//

import Foundation

/// The render inputs for the day-before card — pure data, `Hashable` so it folds into the
/// scheduler's rebuild signature (an attachment-affecting change must retrigger a rebuild).
struct DayBeforeCardModel: Hashable {
    /// Event HOME side — always the LEFT of the card (soccer convention; matches every other
    /// app surface). Never reordered by which side the user follows.
    let homeAbbr: String
    /// Event AWAY side — always the RIGHT of the card.
    let awayAbbr: String
    /// Localized weekday, uppercased — e.g. "SAT".
    let dayLabel: String
    /// Localized kickoff time — "4:00 PM" (en_US) / "16:00" (24-hour locales).
    let timeLabel: String
    /// Broadcast channel name — e.g. "ESPN". `nil` omits the TV chip.
    let broadcast: String?
}

enum DayBeforeContent {
    /// The full built content for one reminder.
    struct Output: Hashable {
        /// "Spirit play tomorrow" — the notification title.
        let title: String
        /// "4:00 PM · ESPN" (or just "4:00 PM" when no broadcast) — the notification body.
        let body: String
        /// The image-card render model.
        let card: DayBeforeCardModel
    }

    /// Build the reminder content for `event`, with `followedAbbr` the side the user follows
    /// (used only to name the title's subject — the CARD is always home-left regardless).
    /// `locale`/`timeZone` are injectable for tests; production passes the device defaults.
    /// Returns `nil` when the event lacks a kickoff or either side's abbreviation (the scheduler
    /// already filters these; this stays defensive).
    static func make(event: Event, followedAbbr: String, clubs: [Club],
                     locale: Locale = .current, timeZone: TimeZone = .current) -> Output? {
        guard let kickoff = event.kickoff,
              let homeAbbr = event.homeCompetitor?.team?.abbreviation,
              let awayAbbr = event.awayCompetitor?.team?.abbreviation
        else { return nil }

        let title = "\(shortName(for: followedAbbr, in: event, clubs: clubs)) play tomorrow"

        let dayLabel = formatted(kickoff, template: "EEE", locale: locale, timeZone: timeZone)
            .uppercased(with: locale)
        // "jmm" = the locale-correct hour:minute form ("4:00 PM" in en_US, "16:00" in 24h locales).
        let timeLabel = formatted(kickoff, template: "jmm", locale: locale, timeZone: timeZone)

        let broadcast = event.broadcastName
        // Heads-up framing: time (+ how-to-watch) only. Opponent + venue deliberately dropped.
        let body = [timeLabel, broadcast].compactMap { $0 }.joined(separator: " · ")

        let card = DayBeforeCardModel(
            homeAbbr: homeAbbr, awayAbbr: awayAbbr,
            dayLabel: dayLabel, timeLabel: timeLabel, broadcast: broadcast
        )
        return Output(title: title, body: body, card: card)
    }

    /// The title's subject name for `abbr`. Owner-approved exception (2026-07-24) to the
    /// full-club-name rule: the SHORT name fixes the non-Pro title truncation. Chain:
    /// competitor `shortDisplayName` → club directory `shortName` → national-team name → abbr.
    /// `internal` (not private) so the fallback chain is directly testable.
    static func shortName(for abbr: String, in event: Event, clubs: [Club]) -> String {
        let competitor = [event.homeCompetitor, event.awayCompetitor]
            .compactMap { $0 }
            .first { $0.team?.abbreviation == abbr }
        if let short = competitor?.team?.shortDisplayName, !short.isEmpty { return short }
        if let short = clubs.first(where: { $0.abbreviation == abbr })?.shortName, !short.isEmpty { return short }
        if let nt = NationalTeam.team(code: abbr)?.name, !nt.isEmpty { return nt }
        return abbr
    }

    private static func formatted(_ date: Date, template: String,
                                  locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
