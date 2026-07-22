//
//  BracketLeaderboardView.swift
//  NWSLApp
//
//  Bracket Battle — the standalone Leaderboard (Fan Zone game 2, v2). Pushed from the
//  Results screen / Bracket Overview onto Home's NavigationStack. Two tabs:
//   • Rankings  — this edition's standings (your-position banner + top-3 podium + full
//                 table), from real `bracket_scores` + `bracket_user_edition_stats`.
//   • Your Stats — the signed-in user's cross-edition history (totals, accuracy, best
//                 round, per-edition list), from `bracket_user_edition_stats`.
//
//  ZERO fabricated data (RULES.md #3): empty / solo / signed-out states render honestly
//  — "just you", "be the first", "sign in" — never padded counts or invented rivals.
//  Accuracy shows "—" until a pick is actually scored. Identity = the teal
//  `dsGameBracket` accent; no emoji in game UI (RULES.md #5).
//

import SwiftUI

struct BracketLeaderboardView: View {
    /// The active edition for the Rankings tab (nil → no live edition; Rankings shows
    /// its empty state and the screen opens on Your Stats).
    let editionID: String?
    let myUserID: UUID?
    let myName: String
    /// The user's live points in the active edition (spliced into the standings).
    let myPoints: Int

    @State private var tab: Tab = .rankings
    @State private var standings: [BracketStanding] = []   // the visible top rows
    @State private var you: BracketStanding?               // your own standing (real rank, even past the top)
    @State private var totalPlayers = 0                    // TRUE count for "of N" / percentile
    @State private var history: [BracketEditionStat] = []
    @State private var loaded = false

    /// The most recently COMPLETED edition — the Rankings tab can reopen it (owner's World Cup
    /// rule: the previous tournament's final table stays browsable; its votes are retained too,
    /// so its rounds remain inspectable elsewhere). nil until fetched / none completed yet.
    @State private var previousEdition: (id: String, title: String)?
    /// Which edition the Rankings tab is showing: false = the ACTIVE edition (live splice),
    /// true = the previous completed edition (server rows as-of close).
    @State private var showingPrevious = false

    private let service = BracketService()
    private let accent = Color.dsGameBracket

    enum Tab: String, CaseIterable { case rankings = "Rankings", yourStats = "Your Stats" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    switch tab {
                    case .rankings: rankingsTab
                    case .yourStats: yourStatsTab
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .background(Color.dsBgPrimary.ignoresSafeArea())
        .nativeBackButton(title: "Leaderboard")
        // Honest result when Game Center isn't signed in — never a silent dead tap (NO SILENT FAILURES).
        .alert("Game Center unavailable", isPresented: Binding(
            get: { GameCenterManager.shared.leaderboardsUnavailable },
            set: { if !$0 { GameCenterManager.shared.leaderboardsUnavailable = false } })
        ) {
            Button("OK", role: .cancel) { GameCenterManager.shared.leaderboardsUnavailable = false }
        } message: {
            Text("Sign in to Game Center in iOS Settings to view the leaderboards.")
        }
        .task {
            // The previous completed edition (may BE the shown edition when nothing is active).
            let previous = await service.lastCompletedEdition()
            if previous?.id != editionID { previousEdition = previous }
            // No live edition but a finished one exists → Rankings defaults to its final table
            // instead of a dead empty state (the "tournament is over, the records remain" read).
            if editionID == nil, previousEdition != nil { showingPrevious = true }
            if editionID == nil, previousEdition == nil { tab = .yourStats }
            await loadStandings()
            if let myUserID { history = await service.myEditionStats(userID: myUserID) }
            loaded = true
        }
    }

    /// (Re)load the Rankings rows for whichever edition the tab is showing. The ACTIVE edition
    /// splices the caller's live points; a PAST edition uses the banked server points (the table
    /// as it stood at close — stamped ranks agree with it).
    private func loadStandings() async {
        let target = showingPrevious ? previousEdition?.id : editionID
        guard let target else { standings = []; you = nil; totalPlayers = 0; return }
        var points = myPoints
        if showingPrevious, let myUserID {
            points = await service.myPoints(editionID: target, userID: myUserID)
        }
        let result = await service.standings(editionID: target, myUserID: myUserID, myName: myName, myPoints: points)
        standings = result.rows
        you = result.you
        totalPlayers = result.total
    }

    // MARK: - Rankings tab

    @ViewBuilder
    private var rankingsTab: some View {
        // Edition switcher — only when there are two editions to switch between.
        if editionID != nil, previousEdition != nil {
            editionSwitcher
        }
        if editionID == nil && previousEdition == nil {
            emptyCard("No active edition", "Rankings appear once a Bracket Battle is live.")
        } else if !loaded {
            loadingCard
        } else if standings.isEmpty && you == nil {
            emptyCard("Be the first in", "No picks have been scored yet — play a round to start the board.")
        } else {
            if let you { yourPositionBanner(you) }
            if standings.count >= 3 { podium }
            VStack(spacing: 0) {
                ForEach(standings) { standingRow($0) }
            }
            .padding(.vertical, 4)
            .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
            gameCenterCard
        }
    }

    private func yourPositionBanner(_ you: BracketStanding) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.18))
                Text("#\(you.rank)").dsFont(17, weight: .heavy, monospacedDigit: true).foregroundStyle(accent)
            }
            .frame(width: 52, height: 52)
            .overlay(Circle().strokeBorder(accent.opacity(0.5), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text("Your rank").trackedCaps(color: accent)
                Text(rankSubtitle(you)).dsFont(13).foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(you.points)").dsFont(22, weight: .heavy, monospacedDigit: true).foregroundStyle(Color.dsFgPrimary)
                Text("pts").dsFont(11).foregroundStyle(Color.dsFgTertiary)
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [accent.opacity(0.14), Color.dsMdCard], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.35)))
    }

    private func rankSubtitle(_ you: BracketStanding) -> String {
        var parts: [String] = []
        if let acc = you.accuracy { parts.append("\(pct(acc)) accurate") }
        // Percentile / "of N" reflects the TRUE total player count, not the capped list.
        if totalPlayers >= 5 {
            let p = max(1, Int((Double(you.rank) / Double(totalPlayers) * 100).rounded(.up)))
            parts.append("top \(p)% of \(totalPlayers)")
        } else {
            parts.append("of \(totalPlayers)")
        }
        return parts.joined(separator: " · ")
    }

    // Top-3 podium: 1st tallest in the center, 2nd left, 3rd right (bars scaled to 1st).
    private var podium: some View {
        let top = Array(standings.prefix(3))
        let maxPts = max(top.map(\.points).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 10) {
            if top.count > 1 { podiumColumn(top[1], height: 56, maxPts: maxPts) }
            podiumColumn(top[0], height: 78, maxPts: maxPts)
            if top.count > 2 { podiumColumn(top[2], height: 40, maxPts: maxPts) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func podiumColumn(_ s: BracketStanding, height: CGFloat, maxPts: Int) -> some View {
        let frac = CGFloat(s.points) / CGFloat(maxPts)
        return VStack(spacing: 6) {
            Text(s.name).dsFont(11, weight: .semibold).foregroundStyle(s.isYou ? accent : .dsFgPrimary)
                .lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth: 84)
            Text("\(s.points)").dsFont(13, weight: .heavy, monospacedDigit: true).foregroundStyle(s.isYou ? accent : Color.dsFgSecondary)
            RoundedRectangle(cornerRadius: 6)
                .fill(s.isYou ? accent : accent.opacity(0.45))
                .frame(width: 64, height: max(14, height * max(frac, 0.2)))
                .overlay(alignment: .top) {
                    Text("\(s.rank)").dsFont(13, weight: .heavy).foregroundStyle(Color.dsFgPrimary).padding(.top, 4)
                }
        }
    }

    private func standingRow(_ s: BracketStanding) -> some View {
        HStack(spacing: 12) {
            Text("\(s.rank)").dsFont(13, weight: .bold, monospacedDigit: true)
                .foregroundStyle(s.isYou ? accent : Color.dsFgTertiary).frame(width: 30, alignment: .trailing)
            Text(s.name).dsFont(14, weight: s.isYou ? .bold : .medium)
                .foregroundStyle(s.isYou ? accent : .dsFgPrimary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(s.accuracy.map(pct) ?? "—").dsFont(12, monospacedDigit: true)
                .foregroundStyle(Color.dsFgSecondary).frame(width: 48, alignment: .trailing)
            Text("\(s.points)").dsFont(13, weight: .semibold, monospacedDigit: true)
                .foregroundStyle(s.isYou ? accent : .dsFgPrimary).frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(s.isYou ? accent.opacity(0.10) : .clear)
    }

    // MARK: - Your Stats tab

    @ViewBuilder
    private var yourStatsTab: some View {
        if myUserID == nil {
            emptyCard("Sign in to track your stats", "Your points, accuracy, and edition history live here once you sign in.")
        } else if !loaded {
            loadingCard
        } else if history.isEmpty {
            emptyCard("No stats yet", "Play an edition and your totals, accuracy, and best rounds will show up here.")
        } else {
            let totalPts = history.reduce(0) { $0 + $1.points }
            let totalCorrect = history.reduce(0) { $0 + $1.correct }
            let totalPicks = history.reduce(0) { $0 + $1.total }
            let avgAcc: Double? = totalPicks > 0 ? Double(totalCorrect) / Double(totalPicks) : nil
            let bestEdition = history.map(\.points).max() ?? 0
            let best = history.compactMap { e in e.bestRoundAccuracy.map { (e, $0) } }.max { $0.1 < $1.1 }
            // Streak (consecutive correct picks within an edition): longest = lifetime best
            // across editions; current = the live (incomplete) edition's run, else 0.
            let longestStreak = history.map(\.longestStreak).max() ?? 0
            let currentStreak = history.first(where: { !$0.isComplete })?.currentStreak ?? 0

            VStack(spacing: 4) {
                Text("\(totalPts)").dsFont(42, weight: .heavy, monospacedDigit: true).foregroundStyle(Color.dsFgPrimary)
                Text("total points · across \(history.count) edition\(history.count == 1 ? "" : "s")")
                    .dsFont(12).foregroundStyle(Color.dsFgSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)

            // 2×2 grid — all tally-backed (accuracy + consecutive-correct streaks). "Best
            // round" + edition count surface below / in the header.
            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                statTile("Avg accuracy", avgAcc.map(pct) ?? "—")
                statTile("Current streak", "\(currentStreak)")
                statTile("Best edition", "\(bestEdition) pts")
                statTile("Longest streak", "\(longestStreak)")
            }

            if let best, let label = roundLabel(best.0.bestRoundRaw) {
                bestRoundCallout(label: label, accuracy: best.1)
            }

            Text("Edition history").trackedCaps().frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            VStack(spacing: 10) { ForEach(history) { editionHistoryRow($0) } }

            gameCenterCard
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).dsFont(28, weight: .heavy, monospacedDigit: true).foregroundStyle(Color.dsFgPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).dsFont(11).foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dsBgTertiary).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func bestRoundCallout(label: String, accuracy: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your best round").trackedCaps(color: accent)
                Spacer()
                Text("\(label) · \(pct(accuracy))").dsFont(13, weight: .bold).foregroundStyle(Color.dsFgPrimary)
            }
            statBar(fraction: accuracy)
        }
        .padding(16)
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.35)))
    }

    private func editionHistoryRow(_ e: BracketEditionStat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.themeLabel).trackedCaps(size: 10, color: accent)
                    Text(e.title).dsFont(14, weight: .semibold).foregroundStyle(Color.dsFgPrimary).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Text(e.isComplete ? "Final" : "In progress")
                    .dsFont(10, weight: .bold).foregroundStyle(e.isComplete ? Color.dsFgTertiary : accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((e.isComplete ? Color.dsFgTertiary : accent).opacity(0.14), in: Capsule())
            }
            if e.maxPoints > 0 { statBar(fraction: Double(e.points) / Double(e.maxPoints)) }
            HStack {
                Text(e.maxPoints > 0 ? "\(e.points) / \(e.maxPoints) pts" : "\(e.points) pts")
                    .dsFont(12, weight: .semibold).foregroundStyle(Color.dsFgSecondary)
                Spacer()
                if let acc = e.accuracy { Text("\(pct(acc)) accurate").dsFont(12).foregroundStyle(Color.dsFgTertiary) }
            }
            // The competitive line: where you FINISHED, World-Cup-style — survives forever even
            // after the edition's per-vote detail is pruned (rank stamped at close by the engine).
            // Absent (not invented) for editions closed before stamping existed.
            if e.isComplete, let rank = e.finalRank, let field = e.fieldSize {
                HStack(spacing: 5) {
                    Image(systemName: "flag.checkered").dsFont(11).foregroundStyle(accent)
                    Text("Finished #\(rank) of \(field)")
                        .dsFont(12, weight: .bold).foregroundStyle(accent)
                }
            }
        }
        .padding(14)
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// "Current | <previous title> (final)" — which edition's table Rankings shows. Only rendered
    /// when both exist. Switching reloads (a past edition's rows are the banked as-of-close table).
    private var editionSwitcher: some View {
        HStack(spacing: 8) {
            switcherTab("Current", isOn: !showingPrevious) {
                guard showingPrevious else { return }
                showingPrevious = false
                Task { await loadStandings() }
            }
            switcherTab("\(previousEdition?.title ?? "Previous") · Final", isOn: showingPrevious) {
                guard !showingPrevious else { return }
                showingPrevious = true
                Task { await loadStandings() }
            }
            Spacer()
        }
    }

    private func switcherTab(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .dsFont(12, weight: .semibold)
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? accent.opacity(0.2) : Color.dsBgTertiary.opacity(0.5))
                .foregroundStyle(isOn ? accent : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared pieces

    private var gameCenterCard: some View {
        Button { GameCenterManager.shared.openLeaderboards() } label: {
            HStack(spacing: 12) {
                Image(systemName: "rosette").dsFont(18).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Game Center").dsFont(14, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                    Text("Compare with players everywhere").dsFont(11).foregroundStyle(Color.dsFgSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
            }
            .padding(16)
            .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyCard(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).dsFont(16, weight: .bold).foregroundStyle(Color.dsFgPrimary)
            Text(subtitle).dsFont(13).foregroundStyle(Color.dsFgSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).padding(.horizontal, 20)
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var loadingCard: some View {
        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    /// A thin accent progress bar (0…1, clamped).
    private func statBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsBgTertiary)
                Capsule().fill(accent).frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// Round label for the best-round display — gracefully "—" for a round code this
    /// build doesn't know (e.g. a qualifying code before the BracketRound qualifying
    /// cases merge), so the screen never shows a blank.
    private func roundLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        return BracketRound(rawValue: raw)?.shortLabel ?? "—"
    }
}
