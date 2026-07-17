//
//  KnowHerPickerView.swift
//  NWSLApp
//
//  Know Her Game — the multi-team picker (docs §3/§8 F4), shown from Home when the user
//  follows 2+ teams with a featured player this week (a one-team fan skips this UNLESS there's a
//  "Last week" section to show — see HomeView.knowHerDestination). One row per followed team's player:
//  tap to play (sign-in gated, like the Predict open-fixture tap); a COMPLETED row stays tappable and
//  re-opens the result recap (score + live community results — no replay). Below this week, a "Last
//  week" section surfaces the prior edition's finished community results (regardless of whether you
//  played them). The game opens in a sheet so "Next player ›" can swap straight to another team's player.
//
//  Mirrors PredictXIView's list → fanZoneGate → sheet structure; the pool + played state
//  live in the shared KnowHerGameStore.
//

import SwiftUI

struct KnowHerPickerView: View {
    /// The followed-team abbreviations (Home computes them for the gate too), so the picker
    /// can (re)load the pool if reached before Home warmed it.
    let teams: [String]

    @Environment(KnowHerGameStore.self) private var store
    @Environment(AuthStore.self) private var auth

    /// Which player the result sheet is showing + from which week. `.current` opens the game (or its
    /// result recap if already played); `.lastWeek` always opens a read-only review of a closed edition.
    private enum ActiveEntry: Identifiable {
        case current(KnowHerPlayer)
        case lastWeek(KnowHerPlayer)
        var id: String {
            switch self {
            case .current(let p): return "cur-\(p.id)"
            case .lastWeek(let p): return "prev-\(p.id)"
            }
        }
    }

    @State private var activeEntry: ActiveEntry?
    @State private var pendingPlayer: KnowHerPlayer?
    @State private var gateRequested = false

    private let accent = Color.dsGameSpotlight

    var body: some View {
        Group {
            switch store.loadState {
            case .idle, .loading:
                ProgressView("Loading this week's players…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            case .loaded:
                loadedContent
            }
        }
        .nativeBackButton(title: "Know Her Game")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { PlayingAsBadge(accent: accent) } }
        .background(Color.dsBgGrouped)
        .task {
            GameCenterManager.shared.authenticate()
            await store.loadIfNeeded(teams: teams)
        }
        .sheet(item: $activeEntry) { entry in
            NavigationStack {
                switch entry {
                case .current(let player):
                    // Already played → read-only recap; not yet → play it. (The gate has already run
                    // for an unplayed tap, so the user is signed in either way.)
                    KnowHerGameView(player: player, weekKey: store.weekKey ?? "",
                                    entry: store.isPlayed(player) ? .review : .play) { next in
                        activeEntry = .current(next)   // "Next player ›" swaps to another team's player
                    }
                case .lastWeek(let player):
                    // Closed edition — review-only (final community numbers, your score if you played).
                    KnowHerGameView(player: player, weekKey: store.previousWeekKey ?? "", entry: .review)
                }
            }
        }
        .fanZoneGate(isRequested: $gateRequested, gameName: "Know Her Game") {
            if let pendingPlayer { activeEntry = .current(pendingPlayer) }
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Singular when following one team (never "players" for a one-team fan). No "N of M
                // played" count — it reads oddly at "1 of 1", and misleads once this screen also hosts
                // last week's finished games below.
                Text(store.players.count == 1 ? "Your player this week" : "Your players this week")
                    .font(.title2.weight(.bold))

                ForEach(store.players) { player in
                    playerRow(player)
                }

                if store.hasPreviousWeek {
                    lastWeekSection
                }
            }
            .padding(20)
        }
    }

    // MARK: This week

    private func playerRow(_ player: KnowHerPlayer) -> some View {
        let played = store.isPlayed(player)
        let teamColor = DesignTeamColors.displayHex(for: player.teamAbbreviation).map { Color(hex: $0) } ?? accent
        return Button {
            if played {
                activeEntry = .current(player)   // straight to the result recap (already signed in)
            } else {
                pendingPlayer = player
                gateRequested = true             // sign-in gate for a first play
            }
        } label: {
            HStack(spacing: 14) {
                KnowHerPlayerAvatar(player: player, ring: teamColor, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.playerName).font(.headline).foregroundStyle(.primary)
                    Text("\(player.position) · \(player.teamAbbreviation.uppercased())")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if played, let score = store.score(for: player) {
                    resultsBadge(score: score, total: player.questions.count)
                } else {
                    HStack(spacing: 3) {
                        Text("Play").font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)   // completed rows stay tappable → revisit results (no replay; the game
                               // view opens .review, which never re-runs the questions)
    }

    /// Completed-row affordance: the score in the game's amber + a "Results ›" cue (replaces the old
    /// green "done" checkmark — a completed row is a doorway to the live community results, not a dead end).
    private func resultsBadge(score: Int, total: Int) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(score)/\(total)").font(.subheadline.weight(.bold)).foregroundStyle(accent)
            HStack(spacing: 2) {
                Text("Results").font(.caption2.weight(.semibold))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Last week (community results grace window)

    private var lastWeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().fill(Color.dsSeparator).frame(height: 1)
                Text("LAST WEEK")
                    .font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(Color.dsSeparator).frame(height: 1)
            }
            .padding(.top, 4)

            ForEach(store.previousPlayers) { player in
                lastWeekRow(player)
            }

            Text("Community results stay for one week after each edition closes.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func lastWeekRow(_ player: KnowHerPlayer) -> some View {
        let editionKey = player.editionKey(weekKey: store.previousWeekKey ?? "")
        let score = store.score(editionKey: editionKey)
        let teamColor = DesignTeamColors.displayHex(for: player.teamAbbreviation).map { Color(hex: $0) } ?? accent
        return Button {
            activeEntry = .lastWeek(player)
        } label: {
            HStack(spacing: 12) {
                KnowHerPlayerAvatar(player: player, ring: teamColor.opacity(0.6), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.playerName).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(player.position) · \(player.teamAbbreviation.uppercased())")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let score {
                        Text("\(score)/\(player.questions.count)")
                            .font(.caption.weight(.bold)).foregroundStyle(accent.opacity(0.75))
                    }
                    HStack(spacing: 2) {
                        Text("Results").font(.caption2.weight(.semibold))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            Button("Try again") { Task { await store.loadIfNeeded(teams: teams, force: true) } }
                .buttonStyle(.borderedProminent).tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
