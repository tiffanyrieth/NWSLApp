//
//  SuperfanDetailView.swift
//  NWSLApp
//
//  The Superfan Zone — a cross-game stats hub opened by tapping the Superfan card. Since the Fan Zone
//  Competitive Redesign it shows the 0–100 accuracy economy: a big tier badge, the season score, a
//  progress bar to the next tier, and a per-game accuracy breakdown (each game contributes accuracy × 25).
//  Season-scoped to the CURRENT year — never combines years.
//
//  The score comes from per-game correct/attempted COUNTS assembled from the four stores
//  (SuperfanCounts.fromStores) and GREATEST-merged into the durable `superfan_scores` row on load/refresh
//  (SuperfanService.submit) — so a reinstall shows the server's preserved history, not an empty device.
//  The competitive TIER is the absolute score band (Fan/Rising/All-Star/MVP); the percentile STANDING
//  ("Top N% of N fans") is a separate rank query, shown when the server returns one.
//
//  NOTE: the full visual redesign (design handoff) lands with PR3; this is the data-correct foundation —
//  a real 0–100 score with the right tier. "Your Best Moments" stays the existing local-highlights list
//  (it renders only when there's real data — never an empty shell); PR4 replaces it with achievements.
//

import SwiftUI

struct SuperfanDetailView: View {
    @Environment(PredictionStore.self) private var predict
    @Environment(BracketStore.self) private var bracket
    @Environment(TriviaStore.self) private var trivia
    @Environment(KnowHerGameStore.self) private var knowHer
    @Environment(AuthStore.self) private var auth

    /// The merged (local ↔ server) per-game counts — the source of the score, tier, and breakdown.
    @State private var counts: SuperfanCounts = .zero
    @State private var standing: SuperfanStanding?
    @State private var didLoad = false

    private var season: Int { AppConfig.currentSeasonYear }

    // Derived from the merged counts.
    private var total: Int { SuperfanScoring.total(counts: counts) }
    private var tier: SuperfanTier { SuperfanTier.forScore(total) }
    private var breakdown: SuperfanBreakdown { SuperfanScoring.breakdown(counts: counts) }
    private var gamesPlayed: Int { counts.gamesPlayed }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                breakdownSection
                bestMomentsSection
                gameCenterLink
            }
            .padding(20)
        }
        .background(Color.dsBgGrouped)
        .nativeBackButton(title: "Superfan")
        .task { await load() }
        .refreshable { await syncStanding() }
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
        // Local counts first so the score renders immediately (even signed out), then merge with server.
        counts = localCounts()
        GameCenterManager.shared.authenticate()
        await syncStanding()
    }

    /// The device's current per-game counts.
    private func localCounts() -> SuperfanCounts {
        SuperfanCounts.fromStores(season: season, predict: predict, bracket: bracket,
                                  trivia: trivia, knowHer: knowHer)
    }

    /// Merge local counts into the server row (reinstall-safe), adopt the merged result, then read back the
    /// percentile standing. Signed out → local counts only; no server standing.
    private func syncStanding() async {
        let local = localCounts()
        guard let userID = auth.userID else { counts = local; return }
        let service = SuperfanService()
        counts = await service.submit(counts: local, season: String(season),
                                      userID: userID, displayName: auth.displayName)
        standing = await service.standing(season: String(season), total: SuperfanScoring.total(counts: counts))
    }

    // MARK: - Hero (tier badge + score + progress to next tier)

    private var hero: some View {
        let progress = TierProgress(score: total)
        return VStack(spacing: 12) {
            TierBadge(tier: tier, size: 80)
            Text("SUPERFAN · \(String(season)) SEASON")
                .dsFont(11, weight: .bold).tracking(1.5).foregroundStyle(.secondary)
            Text("\(total)")
                .dsFont(48, weight: .heavy, design: .rounded).foregroundStyle(.primary)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.dsBgTertiary)
                        Capsule().fill(tier.color)
                            .frame(width: max(0, geo.size.width * progress.fraction))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(tier.label).dsFont(11).foregroundStyle(.tertiary)
                    Spacer()
                    if let next = tier.next { Text(next.label).dsFont(11).foregroundStyle(.tertiary) }
                }
                Text(progress.caption).dsFont(13, weight: .semibold).foregroundStyle(tier.color)
            }
            .padding(.horizontal, 8)

            standingLine
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    /// The percentile line under the score — shown when we have a server standing and the user qualifies
    /// (≥2 games); otherwise an honest, actionable prompt. Separate from the tier (which the score gives).
    @ViewBuilder
    private var standingLine: some View {
        if let s = standing, gamesPlayed >= 2 {
            Text(s.standingText).dsFont(13).foregroundStyle(.secondary)
        } else if gamesPlayed < 2 {
            Text("Play a couple of Fan Zone games to build your Superfan season.")
                .dsFont(13).foregroundStyle(.secondary).multilineTextAlignment(.center)
        } else if auth.isSignedIn {
            Text("Couldn't load your standing — pull to refresh.")
                .dsFont(13).foregroundStyle(.secondary).multilineTextAlignment(.center)
        } else {
            Text("Sign in to see where you rank.")
                .dsFont(13).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: - Breakdown (per-game accuracy × 25)

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BREAKDOWN").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
            ForEach(SuperfanGame.allCases) { game in
                breakdownRow(game)
            }
        }
    }

    /// View-layer game metadata (SuperfanGame is pure — no SwiftUI). Reuses the shared `dsGame*` accents.
    private func meta(_ game: SuperfanGame) -> (symbol: String, color: Color, name: String) {
        switch game {
        case .predict: return ("sportscourt.fill", .dsGamePredict, "Predict the XI")
        case .bracket: return ("trophy.fill", .dsGameBracket, "Bracket Battle")
        case .khg:     return ("person.fill.questionmark", .dsGameSpotlight, "Know Her Game")
        case .trivia:  return ("brain.head.profile", .dsGameTrivia, "NWSL Trivia")
        }
    }

    private func breakdownRow(_ game: SuperfanGame) -> some View {
        let m = meta(game)
        let contribution = breakdown.contribution(for: game)
        let accuracy = breakdown.accuracy(for: game)
        let played = counts.pair(for: game).total > 0
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: m.symbol).font(.system(size: 16)).foregroundStyle(m.color)
                    .frame(width: 28, height: 28)
                    .background(m.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(m.name).dsFont(14, weight: .semibold).foregroundStyle(.primary)
                Spacer()
                // No unlock gate (owner ruling): every game shows its contribution from play #1; before the
                // first play there's simply nothing to show yet.
                Text(played ? "\(Int((accuracy * 100).rounded()))% accuracy" : "Not played yet")
                    .dsFont(12).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.dsBgTertiary)
                        Capsule().fill(m.color)
                            .frame(width: max(0, geo.size.width * (contribution / SuperfanGame.maxContribution)))
                    }
                }
                .frame(height: 5)
                Text("\(oneDecimal(contribution)) / 25")
                    .font(.system(size: 13, weight: .bold, design: .rounded))   // fixed numeric column
                    .foregroundStyle(m.color)
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - Your best moments (local highlights, zero-fabrication — replaced by achievements in PR4)

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
        if bracket.points > 0 {
            out.append(.init(symbol: "trophy.fill", color: .dsGameBracket, title: "Bracket Battle",
                             value: "\(bracket.points) points this edition"))
        }
        let editions = knowHer.seasonEditionsPlayed(year: season)
        if editions > 0 {
            out.append(.init(symbol: "person.fill.questionmark", color: .dsGameSpotlight, title: "Know Her Game",
                             value: "\(editions) player\(editions == 1 ? "" : "s") learned this season"))
        }
        if trivia.bestStreak > 0 {
            out.append(.init(symbol: "brain.head.profile", color: .dsGameTrivia, title: "NWSL Trivia",
                             value: "Longest streak: \(trivia.bestStreak) round\(trivia.bestStreak == 1 ? "" : "s")"))
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
                Image(systemName: "gamecontroller.fill").font(.system(size: 15)).foregroundStyle(Color.dsAccent)
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
