//
//  SuperfanDetailView.swift
//  NWSLApp
//
//  The Superfan Zone (Fan Zone v2, Priority #3) — a cross-game stats hub opened by tapping the Superfan
//  card. Community-family surface. Your season total, your competitive TIER + percentile (computed from a
//  count query across qualifying fans — SuperfanService), a per-game points BREAKDOWN, and "YOUR BEST
//  MOMENTS" (personal highlights from each game). Season-scoped to the CURRENT year — never combines years.
//
//  Honest at low scale: the tier/percentile shows only once the user qualifies (≥2 games) AND enough fans
//  do; before that, a "building your Superfan season" line — no fake rank. Every best moment renders only
//  if its data exists (zero fabrication).
//

import SwiftUI

struct SuperfanDetailView: View {
    @Environment(PredictionStore.self) private var predict
    @Environment(BracketStore.self) private var bracket
    @Environment(TriviaStore.self) private var trivia
    @Environment(KnowHerGameStore.self) private var knowHer
    @Environment(AuthStore.self) private var auth

    @State private var standing: SuperfanStanding?
    @State private var didLoad = false

    /// Superfan's own accent is system blue (the rosette/score) — NOT a game color (design §2).
    private let accent = Color.dsAccent
    private var season: Int { AppConfig.currentSeasonYear }

    // Season-scoped per-game values (the Superfan total never combines years).
    private var predictPts: Int { predict.seasonPoints }
    private var bracketPts: Int { bracket.points }
    private var triviaPts: Int { trivia.seasonCorrect }
    private var knowHerPts: Int { knowHer.seasonPoints(year: season) }
    private var total: Int {
        GameCenterScores.superfanTotal(triviaTotalCorrect: triviaPts, predictSeasonPoints: predictPts,
                                       bracketPoints: bracketPts, knowHerPoints: knowHerPts)
    }
    private var gamesPlayed: Int {
        [predict.hasPredicted, bracket.hasPlayed, trivia.totalAnswered > 0,
         knowHer.playedInSeason(year: season)].filter { $0 }.count
    }
    /// Tier/percentile once the user qualifies (≥2 games) and we have a server standing. Deliberately
    /// NOT gated on how many OTHER fans qualify (owner ruling 2026-07-22): a first or second player has
    /// to see the shape of the feature or there's nothing to come back for. `gamesPlayed >= 2` stays —
    /// that's about the user's OWN participation and its `buildingLine` copy is actionable.
    private var showsTier: Bool {
        gamesPlayed >= 2 && standing != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                breakdownSection
                if showsTier { tierProgression }
                bestMomentsSection
                gameCenterLink
            }
            .padding(20)
        }
        .background(Color.dsBgGrouped)
        .nativeBackButton(title: "Superfan")
        .task { await load() }
        // A real retry for the "couldn't load your standing" state — the copy promises the gesture,
        // so the gesture has to exist (NO SILENT FAILURES: never offer a dead affordance).
        .refreshable { await syncStanding() }
        // Honest result when Game Center isn't signed in — never a silent dead tap (NO SILENT FAILURES),
        // mirroring ProfileView. Bound to the GC singleton's @Observable flag.
        .alert("Game Center unavailable", isPresented: Binding(
            get: { GameCenterManager.shared.leaderboardsUnavailable },
            set: { if !$0 { GameCenterManager.shared.leaderboardsUnavailable = false } })
        ) {
            Button("OK", role: .cancel) { GameCenterManager.shared.leaderboardsUnavailable = false }
        } message: {
            Text("Sign in to Game Center in iOS Settings to view the leaderboards.")
        }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        GameCenterManager.shared.authenticate()
        await syncStanding()
    }

    /// Push the season total, then read back the standing. Split out of `load()` (which fires once) so
    /// pull-to-refresh can genuinely re-run it. Signed out → no server standing; local totals + best
    /// moments still show.
    private func syncStanding() async {
        guard let userID = auth.userID else { return }
        let service = SuperfanService()
        await service.submit(total: total, gamesPlayed: gamesPlayed,
                             season: String(season), userID: userID, displayName: auth.displayName)
        standing = await service.standing(season: String(season), total: total)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 8) {
            if showsTier, let s = standing {
                let tier = s.tier
                HStack(spacing: 6) {
                    Image(systemName: tier.symbol).font(.system(size: 13))
                    Text(tier.label.uppercased()).dsFont(12, weight: .bold)
                }
                .foregroundStyle(tier.color)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(tier.color.opacity(0.16), in: Capsule())
            }
            Text("SUPERFAN · \(String(season)) SEASON")
                .dsFont(11, weight: .bold).tracking(1).foregroundStyle(.secondary)
            Text("\(total)")
                .dsFont(44, weight: .heavy, design: .rounded).foregroundStyle(.primary)
            if showsTier, let s = standing {
                Text(s.standingText)
                    .dsFont(13).foregroundStyle(.secondary)
            } else {
                Text(buildingLine)
                    .dsFont(13).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    /// The remaining no-tier cases. None of them is "not enough fans yet" any more — that gate is gone,
    /// so with ≥2 games played a missing tier can only mean we have no server standing. Those are two
    /// different truths and they get two different lines: signed out is a state the user can act on,
    /// a failed count read is our problem, not theirs.
    private var buildingLine: String {
        if gamesPlayed < 2 { return "Play a couple of Fan Zone games to earn your Superfan tier." }
        return auth.isSignedIn
            ? "Couldn't load your standing — pull to refresh."
            : "Sign in to see where you rank."
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BREAKDOWN").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
            breakdownRow("sportscourt.fill", .dsGamePredict, "Predict the XI", predictPts, "Season points")
            breakdownRow("trophy.fill", .dsGameBracket, "Bracket Battle", bracketPts, "This edition")
            breakdownRow("brain.head.profile", .dsGameTrivia, "NWSL Trivia", triviaPts, "Correct answers")
            breakdownRow("person.fill.questionmark", .dsGameSpotlight, "Know Her Game", knowHerPts,
                         "\(knowHer.seasonEditionsPlayed(year: season)) rounds played")
        }
    }

    private func breakdownRow(_ symbol: String, _ color: Color, _ name: String, _ points: Int, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).dsFont(14, weight: .semibold).foregroundStyle(.primary)
                Text(detail).dsFont(11).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(points)").dsFont(18, weight: .heavy, design: .rounded).foregroundStyle(color)
                Text("pts").dsFont(9).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tier progression

    private var tierProgression: some View {
        let tiers = SuperfanTier.allCases
        let currentIndex = standing.flatMap { tiers.firstIndex(of: $0.tier) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("TIER").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { i, tier in
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(i <= currentIndex ? tier.color : Color.dsBgTertiary)
                                .frame(width: 28, height: 28)
                            Image(systemName: tier.symbol).font(.system(size: 12))
                                .foregroundStyle(i <= currentIndex ? Color.white : Color.dsFgTertiary)
                        }
                        Text(tier.label)
                            .dsFont(9, weight: i == currentIndex ? .bold : .regular)
                            .foregroundStyle(i == currentIndex ? tier.color : Color.dsFgTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Your best moments (local highlights, zero-fabrication)

    private struct Moment: Identifiable {
        let symbol: String; let color: Color; let title: String; let value: String
        var id: String { title }
    }

    private var bestMoments: [Moment] {
        var out: [Moment] = []
        let bestXI = predict.scores.values.map(\.correctPlayers).max() ?? 0
        if predict.scores.values.contains(where: \.perfectXI) {
            out.append(.init(symbol: "sportscourt.fill", color: .dsGamePredict, title: "Predict the XI",
                             value: "Perfect XI — all 11 right!"))
        } else if bestXI > 0 {
            out.append(.init(symbol: "sportscourt.fill", color: .dsGamePredict, title: "Predict the XI",
                             value: "Best: \(bestXI) of 11 players right"))
        }
        if bracketPts > 0 {
            out.append(.init(symbol: "trophy.fill", color: .dsGameBracket, title: "Bracket Battle",
                             value: "\(bracketPts) points this edition"))
        }
        let editions = knowHer.seasonEditionsPlayed(year: season)
        if editions > 0 {
            out.append(.init(symbol: "person.fill.questionmark", color: .dsGameSpotlight, title: "Know Her Game",
                             value: "\(editions) player\(editions == 1 ? "" : "s") learned this season"))
        }
        if trivia.bestStreak > 0 {
            out.append(.init(symbol: "brain.head.profile", color: .dsGameTrivia, title: "NWSL Trivia",
                             value: "Longest streak: \(trivia.bestStreak) day\(trivia.bestStreak == 1 ? "" : "s")"))
        }
        return out
    }

    @ViewBuilder
    private var bestMomentsSection: some View {
        let moments = bestMoments
        if !moments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR BEST MOMENTS").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
                ForEach(moments) { m in
                    HStack(spacing: 12) {
                        Image(systemName: m.symbol).font(.system(size: 15)).foregroundStyle(m.color)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).dsFont(13, weight: .semibold).foregroundStyle(.primary)
                            Text(m.value).dsFont(12).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12).frame(maxWidth: .infinity)
                    .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Game Center

    private var gameCenterLink: some View {
        Button { GameCenterManager.shared.openLeaderboards() } label: {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 15)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Game Center").dsFont(13, weight: .semibold).foregroundStyle(.primary)
                    Text("Compare with players everywhere").dsFont(11).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
