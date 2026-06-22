//
//  FanZoneCard.swift
//  NWSLApp
//
//  Home Module 3 "Fan Zone" — the equal-weight game cards (design handoff
//  `Fan_UI_Improvements` → fz-components.jsx). Replaces the old featured + horizontal-
//  tile split (FeaturedGameCard + GameCard) with full-width STACKED cards so every
//  active game is visible without a swipe, each carrying richer live context: an
//  accent-tinted game icon, an opponent/round context line, an optional points/streak
//  badge, a status line, a countdown pill, a partial-completion progress bar, and a
//  green-check "submitted/done" state. A `SuperfanBanner` sits above them surfacing the
//  cross-game score.
//
//  The card is a dumb renderer: HomeView derives a `FanZoneCardModel` from the game
//  stores (PredictionStore / BracketStore / TriviaStore) and hands it in, so all the
//  game-state logic stays in one place and this file owns only layout. Each game keeps
//  its own accent color identity (predict pink / bracket teal / trivia indigo).
//

import SwiftUI

// MARK: - Card model

/// A flat description of one Fan Zone game card's rendered state, derived in HomeView
/// from the game stores. Keeping it a value type (not a pile of view params) lets the
/// view stay declarative and the state logic live next to the stores.
struct FanZoneCardModel {
    enum Game { case predict, bracket, trivia }

    /// Optional progress bar: `value` of `max` plus a caption ("4 of 11 players picked").
    struct Progress { let value: Int; let max: Int; let label: String }

    let game: Game
    let title: String
    var contextLine: String
    /// The accent status line ("68 season pts · 4/11 drafted"). Ignored when `doneLine`
    /// is set (the submitted/done state replaces the status + countdown + progress rows).
    var statusLine: String? = nil
    /// Optional points/streak badge, already formatted ("68", "7🔥").
    var badge: String? = nil
    /// Optional countdown text, already formatted ("2d 14h left", "New in 6h").
    var countdown: String? = nil
    /// Optional partial-completion bar.
    var progress: Progress? = nil
    /// When set, replaces status/countdown/progress with one green-check line
    /// ("Picks locked in — results drop in 18h" / "Done today · new questions in 6h").
    var doneLine: String? = nil
    /// Dims the whole card to 0.7 (the trivia completed-today state).
    var dimmed: Bool = false

    var accent: Color {
        switch game {
        case .predict: return .dsGamePredict
        case .bracket: return .dsGameBracket
        case .trivia:  return .dsGameTrivia
        }
    }

    /// iOS-native SF Symbol per game (replaces the prototype's inline SVG glyphs).
    var iconSystemName: String {
        switch game {
        case .predict: return "soccerball"
        case .bracket: return "trophy.fill"
        case .trivia:  return "brain.head.profile"
        }
    }
}

// MARK: - The card

struct FanZoneGameCard: View {
    let model: FanZoneCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if let doneLine = model.doneLine {
                doneRow(doneLine)
            } else {
                statusRow
                if let progress = model.progress { progressRow(progress) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Subtle accent wash fading into the card fill (handoff: accent/8% → dsBgCard).
        .background(
            LinearGradient(
                colors: [model.accent.opacity(0.08), Color.dsBgCard],
                startPoint: .topLeading, endPoint: .center
            )
        )
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous)
                .strokeBorder(model.accent.opacity(0.15), lineWidth: 1)
        )
        // 3px solid accent left edge (the color-block motif), drawn over the hairline.
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: DS.radiusXxl, bottomLeadingRadius: DS.radiusXxl,
                bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous
            )
            .fill(model.accent)
            .frame(width: 3)
        }
        .opacity(model.dimmed ? 0.7 : 1)
    }

    // Row 1: icon + title/context + optional badge + chevron.
    private var headerRow: some View {
        HStack(spacing: 10) {
            GameIcon(systemName: model.iconSystemName, accent: model.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .dsFont(15, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                Text(model.contextLine)
                    .dsFont(12)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            if let badge = model.badge {
                Text(badge)
                    .dsFont(13, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(model.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(model.accent.opacity(0.18), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgTertiary)
        }
    }

    // Row 2: accent status line + countdown pill.
    private var statusRow: some View {
        HStack(spacing: 8) {
            if let status = model.statusLine {
                Text(status)
                    .dsFont(12, weight: .semibold)
                    .foregroundStyle(model.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            if let countdown = model.countdown {
                CountdownPill(label: countdown, accent: model.accent)
            }
        }
    }

    // Row 3 (optional): the partial-completion bar + caption.
    private func progressRow(_ progress: FanZoneCardModel.Progress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MiniProgressBar(value: progress.value, max: progress.max, accent: model.accent)
            Text(progress.label)
                .dsFont(10)
                .foregroundStyle(Color.dsFgTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // The submitted/done line. Green for an active "locked in" state; secondary when the
    // card is dimmed (trivia done-for-today) so it reads as settled, not celebratory.
    private func doneRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .dsFont(13)
                .foregroundStyle(Color.dsSuccess)
            Text(text)
                .dsFont(12, weight: .semibold)
                .foregroundStyle(model.dimmed ? Color.dsFgSecondary : Color.dsSuccess)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

/// A 32pt accent-tinted rounded square holding the game's SF Symbol.
struct GameIcon: View {
    let systemName: String
    let accent: Color
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(accent.opacity(0.13))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .dsFont(size * 0.5, weight: .semibold)
                    .foregroundStyle(accent)
            )
    }
}

/// The countdown pill: accent dot + label on a faint accent capsule.
struct CountdownPill: View {
    let label: String
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text(label)
                .dsFont(10, weight: .bold)
                .foregroundStyle(accent)
                .tracking(0.3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(accent.opacity(0.10), in: Capsule())
        .fixedSize()
    }
}

/// A 4pt progress bar — tertiary track, accent fill, fraction clamped to 0…1.
struct MiniProgressBar: View {
    let value: Int
    let max: Int
    let accent: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsBgTertiary)
                Capsule().fill(accent).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: height)
    }

    private var fraction: CGFloat {
        guard max > 0 else { return 0 }
        return Swift.min(Swift.max(CGFloat(value) / CGFloat(max), 0), 1)
    }
}

/// The cross-game "Superfan" summary banner above the game cards. Display-only — the
/// number is computed locally via `GameCenterScores.superfanTotal`; the actual Game
/// Center submission already happens in `GameCenterManager.syncAll`.
struct SuperfanBanner: View {
    let predictPoints: Int
    let bracketPoints: Int
    let triviaCorrect: Int

    private var total: Int {
        GameCenterScores.superfanTotal(
            triviaTotalCorrect: triviaCorrect,
            predictSeasonPoints: predictPoints,
            bracketPoints: bracketPoints
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Superfan Score").trackedCaps()
                Spacer(minLength: 8)
                Text("\(total)")
                    .dsFont(18, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(Color.dsFgPrimary)
            }
            HStack(spacing: 12) {
                breakdown(dot: .dsGamePredict, "\(predictPoints) predict")
                breakdown(dot: .dsGameBracket, "\(bracketPoints) bracket")
                breakdown(dot: .dsGameTrivia, "\(triviaCorrect) trivia")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.dsBgCard, Color.dsBgTertiary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXxl, style: .continuous)
                .strokeBorder(Color.dsFgQuaternary, lineWidth: 1)
        )
    }

    private func breakdown(dot: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(text)
                .dsFont(11)
                .foregroundStyle(Color.dsFgSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Countdown formatting

/// A compact future-interval label ("2d 14h", "18h", "47m", "<1m") for the Fan Zone
/// countdown pills. Pure + `now`-injected so it's deterministic to unit-test. Callers
/// wrap it for context ("\(x) left", "New in \(x)", "results drop in \(x)"). Returns
/// nil for a past/now date so a stale deadline shows no pill rather than "0m".
func compactCountdown(to target: Date, from now: Date = Date()) -> String? {
    let seconds = Int(target.timeIntervalSince(now))
    guard seconds > 0 else { return nil }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
    if hours > 0 { return "\(hours)h" }
    if minutes > 0 { return "\(minutes)m" }
    return "<1m"
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 10) {
            SuperfanBanner(predictPoints: 68, bracketPoints: 22, triviaCorrect: 143)
            FanZoneGameCard(model: FanZoneCardModel(
                game: .predict, title: "Predict the XI",
                contextLine: "WAS vs POR · Sat 7:30 PM",
                statusLine: "68 season pts · 4/11 drafted",
                badge: "68", countdown: "2d 14h left",
                progress: .init(value: 4, max: 11, label: "4 of 11 players picked — tap to finish")
            ))
            FanZoneGameCard(model: FanZoneCardModel(
                game: .bracket, title: "Bracket Battle",
                contextLine: "Stare-Down Edition · Round of 64",
                badge: "22",
                doneLine: "Picks locked in — results drop in 18h"
            ))
            FanZoneGameCard(model: FanZoneCardModel(
                game: .trivia, title: "Daily Trivia",
                contextLine: "4/5 correct today",
                badge: "7🔥",
                doneLine: "Done today · new questions in 6h",
                dimmed: true
            ))
        }
        .padding(16)
    }
    .background(Color.dsBgGrouped)
}
