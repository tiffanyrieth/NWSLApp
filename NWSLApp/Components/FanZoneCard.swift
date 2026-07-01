//
//  FanZoneCard.swift
//  NWSLApp
//
//  Home's top-of-feed "Fan Zone" — a single horizontal row of uniform, compact game
//  cards (design handoff `design_handoff_fanzone_home`). Replaces the earlier vertical
//  stack of full-width `FanZoneGameCard`s: the row leads the Home feed, scrolls
//  horizontally (two cards + a peek visible), and ends with a display-only Superfan
//  summary card once the user has a cross-game score.
//
//  Each card is a dumb renderer: HomeView derives a `FanZoneCardModel` from the game
//  stores (PredictionStore / BracketStore / TriviaStore) and hands it in, so all the
//  game-state logic stays in one place and this file owns only layout. The compact card
//  shows just icon + name + one context line + one accent status line — the richer
//  affordances (progress bar, season-points badge) live on each game's own screen now.
//  Each game keeps its accent identity (predict pink / bracket teal / trivia indigo).
//

import SwiftUI

// MARK: - Card model

/// A flat description of one Fan Zone game card's rendered state, derived in HomeView
/// from the game stores. Keeping it a value type (not a pile of view params) lets the
/// view stay declarative and the state logic live next to the stores.
struct FanZoneCardModel {
    enum Game { case predict, bracket, trivia }

    /// Optional progress bar: `value` of `max` plus a caption ("4 of 11 players picked").
    /// (Not rendered by the compact carousel card — kept so the HomeView state builders
    /// stay untouched; the progress affordance lives on each game's own screen.)
    struct Progress { let value: Int; let max: Int; let label: String }

    let game: Game
    let title: String
    var contextLine: String
    /// The rich status line ("68 season pts · 4/11 drafted") — no longer rendered by the
    /// compact card (it derives `compactStatus` instead). Kept so the builders are untouched.
    var statusLine: String? = nil
    /// Optional points/streak badge — not rendered by the compact card. Kept for the builders.
    var badge: String? = nil
    /// Optional countdown text, already formatted ("2d 14h left", "New in 6h"). The compact
    /// status uses it as Predict's deadline urgency line.
    var countdown: String? = nil
    /// Optional partial-completion bar — not rendered by the compact card. Kept for the builders.
    var progress: Progress? = nil
    /// When set, the game's current round/day is submitted/played — the compact status
    /// collapses to "Picks locked in" (predict/bracket) or "Done today" (trivia).
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

    /// iOS-native SF Symbol per game.
    var iconSystemName: String {
        switch game {
        case .predict: return "soccerball"
        case .bracket: return "trophy.fill"
        case .trivia:  return "brain.head.profile"
        }
    }

    /// The single accent status line for the compact carousel card — action-forward and
    /// honest, deliberately WITHOUT the points/picks counts (those richer affordances live
    /// on the game's own screen now). Predict surfaces the deadline countdown ("2d left")
    /// for urgency; Bracket/Trivia surface the action ("Vote now" / "Play now"); a
    /// submitted/played state collapses to "Picks locked in" / "Done today".
    var compactStatus: String {
        switch game {
        case .predict:
            if doneLine != nil { return "Picks locked in" }
            if let countdown { return countdown }
            return "Make your prediction"
        case .bracket:
            return doneLine != nil ? "Picks locked in" : "Vote now"
        case .trivia:
            return doneLine != nil ? "Done today" : "Play now"
        }
    }
}

// MARK: - The compact carousel card

/// One uniform, compact game card in the horizontal Fan Zone row (~152pt wide). A dumb
/// renderer: icon + name + context line + accent status line, over a per-game accent wash.
struct FanZoneCarouselCard: View {
    let model: FanZoneCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameIcon(systemName: model.iconSystemName, accent: model.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .dsFont(14, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(model.contextLine)
                    .dsFont(11)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            statusRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        // Per-game accent wash fading into the card fill (mockup: accent/15% → dsBgCard).
        .background(
            LinearGradient(
                colors: [model.accent.opacity(0.15), Color.dsBgCard],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(model.accent.opacity(0.2), lineWidth: 1)
        )
        .opacity(model.dimmed ? 0.7 : 1)
    }

    // Bottom-pinned accent status line + a small chevron affordance.
    private var statusRow: some View {
        HStack(spacing: 3) {
            Text(model.compactStatus)
                .dsFont(11, weight: .semibold)
                .foregroundStyle(model.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.right")
                .dsFont(9, weight: .bold)
                .foregroundStyle(model.accent)
        }
    }
}

// MARK: - Trailing Superfan card

/// The cross-game "Superfan" summary — the LAST card in the Fan Zone row (design decision:
/// zero added vertical height, sits right where the points are earned). Display-only: the
/// number is computed locally via `GameCenterScores.superfanTotal`; the actual Game Center
/// submission already happens in `GameCenterManager.syncAll`. Not tappable.
struct SuperfanCard: View {
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
        VStack(alignment: .leading, spacing: 8) {
            GameIcon(systemName: "rosette", accent: .dsAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Superfan").trackedCaps(size: 10, color: .dsFgSecondary)
                Text("\(total)")
                    .dsFont(24, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(Color.dsFgPrimary)
            }
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                breakdownDot(.dsGamePredict, predictPoints)
                breakdownDot(.dsGameBracket, bracketPoints)
                breakdownDot(.dsGameTrivia, triviaCorrect)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.dsBgCard, Color.dsBgTertiary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.dsFgQuaternary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Superfan score \(total)")
    }

    private func breakdownDot(_ color: Color, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(value)")
                .dsFont(11, weight: .semibold, monospacedDigit: true)
                .foregroundStyle(Color.dsFgSecondary)
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
            .fill(accent.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .dsFont(size * 0.5, weight: .semibold)
                    .foregroundStyle(accent)
            )
    }
}

// MARK: - Countdown formatting

/// A compact future-interval label ("2d 14h", "18h", "47m", "<1m") for the Fan Zone
/// countdown lines. Pure + `now`-injected so it's deterministic to unit-test. Callers
/// wrap it for context ("\(x) left", "New in \(x)", "results drop in \(x)"). Returns
/// nil for a past/now date so a stale deadline shows no countdown rather than "0m".
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
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
            FanZoneCarouselCard(model: FanZoneCardModel(
                game: .predict, title: "Predict the XI",
                contextLine: "WAS vs POR · Sat 7:30 PM",
                countdown: "2d 14h"
            ))
            FanZoneCarouselCard(model: FanZoneCardModel(
                game: .bracket, title: "Bracket Battle",
                contextLine: "Stare-Down · Round of 64"
            ))
            FanZoneCarouselCard(model: FanZoneCardModel(
                game: .trivia, title: "Daily Trivia",
                contextLine: "Done today · 4/5 correct",
                doneLine: "Done today", dimmed: true
            ))
            SuperfanCard(predictPoints: 68, bracketPoints: 22, triviaCorrect: 143)
        }
        .frame(height: 128)
        .padding(16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dsBgGrouped)
}
