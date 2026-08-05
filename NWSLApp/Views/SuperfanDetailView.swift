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
    @State private var seasonHistory: [SeasonHistoryEntry] = []
    @State private var achievements: [EarnedAchievement] = []
    @State private var didLoad = false
    @State private var showHowItWorks = false
    /// Bumped on each open so the Spotlight shows a different item every visit (its whole "never the same
    /// twice" hook). Persisted so it survives across launches.
    @AppStorage("superfan.spotlight.rotation") private var spotlightRotation = 0

    private var season: Int { AppConfig.currentSeasonYear }

    // Derived from the merged counts.
    private var total: Int { SuperfanScoring.total(counts: counts) }
    private var breakdown: SuperfanBreakdown { SuperfanScoring.breakdown(counts: counts) }

    /// The DISPLAYED score/tier apply the tier-floor lock: never below a tier you've earned this season
    /// (`season_history.peak_score`). `max(total, …)` guards a peak row that hasn't been written yet.
    private var seasonPeak: Int { max(total, seasonHistory.first { $0.seasonYear == season }?.peakScore ?? 0) }
    private var displayTotal: Int { SuperfanScoring.displayScore(counts: counts, seasonPeak: seasonPeak) }
    private var tier: SuperfanTier { SuperfanTier.forScore(displayTotal) }

    /// The rotating "what we noticed" item, built entirely from cheap local signals (see SuperfanSpotlight).
    private var spotlightItem: SuperfanSpotlight.Item? {
        SuperfanSpotlight.pick(.init(
            total: displayTotal,
            breakdown: breakdown,
            playersLearned: PlayersLearnedStore.count(season: season),
            bestPredictStarters: predict.seasonBests.hasMatchBaseline ? predict.seasonBests.bestMatchStarters : nil,
            recentAchievement: achievements.max(by: { $0.earnedAt < $1.earnedAt })?.achievement.title,
            gamesPlayed: counts.gamesPlayed), rotation: spotlightRotation)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                spotlightSection
                playersLearnedSection
                breakdownSection
                howSuperfanWorks
                bestMomentsSection
                seasonHistorySection
                gameCenterLink
            }
            .padding(20)
        }
        .background(Color.dsBgGrouped)
        .nativeBackButton(title: "Superfan")
        .task { spotlightRotation &+= 1; await load() }
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
        // ⚠️ NO Game Center authenticate() here (removed 2026-08-03, when the Home card became
        // always-visible). This screen is now one tap from a brand-new user's Home, and authenticating
        // on load would greet them with Apple's Game Center sign-in sheet before they have played
        // anything. `openLeaderboards()` still authenticates on TAP — the moment they actually ask for
        // a leaderboard, which is the point at which that prompt makes sense.
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

        // ⚠️ GUARD THE WRITES, NEVER THE READ. `submit` is read-merge-write-and-return and its return
        // value IS this screen's data — a returning user's whole season lives in it. Guarding the call
        // would leave them staring at an empty breakdown. So a device with nothing local ADOPTS
        // read-only, and only a device with something to contribute writes.
        if local == .zero {
            counts = await service.savedCounts(userID: userID, season: String(season))
        } else {
            counts = await service.submit(counts: local, season: String(season),
                                          userID: userID, displayName: auth.displayName)
        }
        // Mirror the adopted server-merged counts so network-free surfaces (the Home card, the
        // Game Center submit) show the SAME score as this screen — the 25-vs-46 mismatch fix.
        // Merged with what's cached: `submit` hands back the caller's own counts when the network
        // fails, and saving that verbatim is how a cached 62 silently became a 25.
        SuperfanCountsCache.save(counts.merged(with: SuperfanCountsCache.load(season: season)),
                                 season: season)
        let total = SuperfanScoring.total(counts: counts)
        // Keep the current season's record book row current (peak monotonic), then read the arc.
        // Skipped at zero: a never-played user would otherwise get a `season_history` row that renders
        // as "2026 · Fan · Current" — an empty shell for a season they haven't played.
        if total > 0 {
            await service.submitSeasonHistory(seasonYear: season, score: total, userID: userID)
        }
        seasonHistory = await service.seasonHistory(userID: userID)
        // Detect + award any store-derivable achievements, then read the earned set for "Your Best Moments".
        await AchievementDetector.checkCumulative(predict: predict, bracket: bracket, trivia: trivia,
                                                  knowHer: knowHer, userID: userID, season: season)
        achievements = await AchievementService().earned(userID: userID, seasonYear: season)
    }

    // MARK: - Hero (tier badge + score + progress to next tier)

    private var hero: some View {
        VStack(spacing: 14) {
            TierBadge(tier: tier, size: 80)
            Text("SUPERFAN · \(String(season)) SEASON")
                .dsFont(11, weight: .bold).tracking(1.5).foregroundStyle(.secondary)
            // Score + tier NAME together, so the number is never read without knowing which tier it is.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(displayTotal)").dsFont(48, weight: .heavy, design: .rounded).foregroundStyle(.primary)
                Text(tier.label).dsFont(20, weight: .bold).foregroundStyle(tier.color)
            }
            // The full 4-rung LADDER (Fan → Rising → All-Star → MVP), the current rung lit + emphasized —
            // so where you stand reads at a glance and All-Star can never look like the floor (owner-caught).
            tierLadder(current: tier)
            Text(TierProgress(score: displayTotal).caption)
                .dsFont(13, weight: .semibold).foregroundStyle(tier.color)
        }
        .frame(maxWidth: .infinity).padding(.top, 8)
    }

    private func tierLadder(current: SuperfanTier) -> some View {
        let rungs: [SuperfanTier] = [.fan, .rising, .allStar, .mvp]
        let currentIdx = rungs.firstIndex(of: current) ?? 0
        return HStack(spacing: 8) {
            ForEach(Array(rungs.enumerated()), id: \.offset) { idx, t in
                let reached = idx <= currentIdx
                let isCurrent = idx == currentIdx
                VStack(spacing: 5) {
                    Capsule()
                        .fill(reached ? t.color : Color.dsBgTertiary)
                        .frame(height: isCurrent ? 8 : 5)
                    Text(t.label)
                        .dsFont(isCurrent ? 12 : 11, weight: isCurrent ? .bold : .regular)
                        .foregroundStyle(isCurrent ? t.color : (reached ? Color.dsFgSecondary : Color.dsFgTertiary))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4).padding(.top, 2)
    }

    // MARK: - Spotlight (the rotating "what we noticed" hook)

    @ViewBuilder
    private var spotlightSection: some View {
        if let item = spotlightItem {
            let tint = spotlightTint(item.tone)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.icon)
                    .dsFont(20).foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.headline).dsFont(16, weight: .bold).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let d = item.detail {
                        Text(d).dsFont(13).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // ⚠️ Bound the wrapping text column so its `.fixedSize` ideal width can't widen the row and
                // let the scroll pan sideways (the KHG-results drag bug, 2026-08-04). Frame + Spacer both.
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func spotlightTint(_ tone: SuperfanSpotlight.Item.Tone) -> Color {
        switch tone {
        case .celebratory: return .dsSuccess
        case .nudge:       return .dsAccent
        case .playful:     return .dsWarning
        case .info:        return .dsFgSecondary
        }
    }

    // MARK: - Players Learned (the collection anchor)

    private var learned: [LearnedPlayer] { PlayersLearnedStore.load(season: season) }

    @ViewBuilder
    private var playersLearnedSection: some View {
        if !learned.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .dsFont(13).foregroundStyle(Color.dsGameSpotlight)
                    Text("PLAYERS LEARNED").dsFont(11, weight: .bold).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(learned.count)").dsFont(14, weight: .heavy, monospacedDigit: true)
                        .foregroundStyle(Color.dsGameSpotlight)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 12)], alignment: .leading, spacing: 14) {
                    ForEach(learned) { playerStamp($0) }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func playerStamp(_ p: LearnedPlayer) -> some View {
        let ring = Color.teamColor(for: p.teamAbbr, liftOnDark: true, fallback: .dsGameSpotlight)
        return VStack(spacing: 5) {
            PlayerHeadshot(athleteID: p.athleteId, size: 52) {
                ZStack {
                    Circle().fill(ring.opacity(0.25))
                    Text(initials(p.name)).dsFont(15, weight: .bold).foregroundStyle(ring)
                }
            }
            .overlay(Circle().stroke(ring, lineWidth: 2))
            Text(lastName(p.name)).dsFont(11).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func lastName(_ full: String) -> String { full.split(separator: " ").last.map(String.init) ?? full }
    private func initials(_ full: String) -> String {
        full.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    // MARK: - Breakdown (per-channel: accuracy + engagement)

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
        case .bracket: return ("trophy.fill", .dsGameBracket, "The Bracket")
        case .khg:     return ("person.fill.questionmark", .dsGameSpotlight, "Know Her Game")
        case .trivia:  return ("brain.head.profile", .dsGameTrivia, "NWSL Trivia")
        }
    }

    private func breakdownRow(_ game: SuperfanGame) -> some View {
        let m = meta(game)
        let contribution = breakdown.contribution(for: game)
        let accuracy = breakdown.channel(for: game).accuracyRatio
        let engagement = breakdown.channel(for: game).engagementPoints
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
                Text(played
                     ? "\(Int((accuracy * 100).rounded()))% accuracy" + (engagement > 0 ? " · +\(engagement) engaged" : "")
                     : "Not played yet")
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
                .frame(height: 10)
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

    // MARK: - How Superfan works (collapsible explainer — Batch-2 Fix 4E)

    /// A collapsed "How Superfan works ›" card so a new user can decode the score / tier / breadth rule
    /// without guessing. Tokens only; the tier bands mirror `SuperfanTier` exactly.
    private var howSuperfanWorks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showHowItWorks.toggle() } } label: {
                HStack {
                    Text("How Superfan works").dsFont(14, weight: .semibold).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showHowItWorks ? "chevron.up" : "chevron.right")
                        .dsFont(13).foregroundStyle(.tertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showHowItWorks {
                VStack(alignment: .leading, spacing: 12) {
                    explainerParagraph("What it measures",
                        "One score for how well-rounded AND how engaged you are across all four Fan Zone games.")
                    explainerParagraph("How the score works",
                        "Each game is a channel worth up to 25 — 20 for accuracy (how well you called it) plus 5 for showing up (a forgiving bonus that builds as you keep playing and never punishes a single miss). Four channels, so 100 is the max. One game alone caps you at 25 — the top of the scale is earned across all four, and it's meant to be hard.")
                    explainerParagraph("You never lose ground",
                        "Once you reach a tier — Rising, All-Star, MVP — your score won't drop below it for the rest of the season. A rough round can't knock you back down.")
                    tierLegend
                    explainerParagraph("Season & history",
                        "Tiers reset each season, but the highest tier you reach is saved for good in Season History below.")
                    explainerParagraph("Your Best Moments",
                        "Badges you earn for specific feats across the games — a perfect quiz, a called upset, a full lineup.")
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14))
            }
        }
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func explainerParagraph(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).dsFont(13, weight: .bold).foregroundStyle(.primary)
            Text(body).dsFont(13).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The four tier bands with their colors — mirrors `SuperfanTier` (Fan 0–24 … MVP 75–100).
    private var tierLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The tiers").dsFont(13, weight: .bold).foregroundStyle(.primary)
            tierRow(.fan, "0–24", "just getting started")
            tierRow(.rising, "25–49", "building across games")
            tierRow(.allStar, "50–74", "strong across multiple games")
            tierRow(.mvp, "75–100", "elite across the full Fan Zone")
        }
    }

    private func tierRow(_ tier: SuperfanTier, _ range: String, _ blurb: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tier.symbol).font(.system(size: 12)).foregroundStyle(tier.color)
                .frame(width: 18)
            Text(tier.label).dsFont(13, weight: .semibold).foregroundStyle(.primary)
                .frame(width: 58, alignment: .leading)
            Text(range).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(tier.color)
                .frame(width: 52, alignment: .leading)
            // Wraps rather than truncates: after three fixed-width columns this one has ~200pt, and at
            // accessibility text sizes "strong across multiple games" clipped to "strong across
            // multiple…" — the half of the row that explains the tier. A shrink-to-fit floor only
            // delayed it. (Verified in-sim at accessibility-medium, 2026-07-29.)
            Text(blurb).dsFont(12).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Your Best Moments (earned achievements — PR4)

    /// The achievements list. HIDDEN ENTIRELY when there are none (owner rule: a section shows real badges
    /// or doesn't appear — never an empty grid). Shows the 5 most recent + a "+N more" tail.
    @ViewBuilder
    private var bestMomentsSection: some View {
        if !achievements.isEmpty {
            let shown = Array(achievements.prefix(5))
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR BEST MOMENTS").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
                ForEach(shown) { earned in achievementCard(earned) }
                if achievements.count > shown.count {
                    Text("+\(achievements.count - shown.count) more")
                        .dsFont(12, weight: .semibold).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func achievementCard(_ earned: EarnedAchievement) -> some View {
        let color = earned.achievement.color
        return HStack(spacing: 12) {
            Image(systemName: earned.achievement.symbol).font(.system(size: 16)).foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(earned.achievement.title).dsFont(14, weight: .bold).foregroundStyle(.primary)
                Text(earned.description).dsFont(12).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(Color.dsBgCard).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Season history (the permanent record book across seasons)

    @ViewBuilder
    private var seasonHistorySection: some View {
        if !seasonHistory.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SEASON HISTORY").dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
                ForEach(seasonHistory) { entry in
                    let isCurrent = entry.seasonYear == season
                    HStack(spacing: 12) {
                        TierBadge(tier: entry.peakTier, size: 28)
                        Text(String(entry.seasonYear)).dsFont(14, weight: .semibold).foregroundStyle(.primary)
                        Spacer()
                        Text(isCurrent ? "\(entry.peakTier.label) · Current"
                                       : "\(entry.peakTier.label) · \(entry.peakScore)")
                            .dsFont(12, weight: isCurrent ? .bold : .regular)
                            .foregroundStyle(isCurrent ? entry.peakTier.color : Color.dsFgSecondary)
                    }
                    .padding(12).frame(maxWidth: .infinity)
                    .background(isCurrent ? entry.peakTier.color.opacity(0.14) : Color.dsBgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCurrent ? entry.peakTier.color.opacity(0.3) : Color.clear, lineWidth: 1))
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
