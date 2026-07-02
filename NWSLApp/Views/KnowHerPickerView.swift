//
//  KnowHerPickerView.swift
//  NWSLApp
//
//  Know Her Game — the multi-team picker (docs §3/§8 F4), shown from Home when the user
//  follows 2+ teams with a featured player this week (one team skips this and goes straight
//  to the intro). One row per followed team's player: tap to play (sign-in gated, like the
//  Predict open-fixture tap), a completed row dims and shows its score, no replay. The game
//  opens in a sheet so "Next player ›" can swap straight to another team's player.
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

    @State private var activePlayer: KnowHerPlayer?
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
        .background(Color(.systemGroupedBackground))
        .task {
            GameCenterManager.shared.authenticate()
            await store.loadIfNeeded(teams: teams)
        }
        .sheet(item: $activePlayer) { player in
            NavigationStack {
                KnowHerGameView(player: player, weekKey: store.weekKey ?? "") { next in
                    activePlayer = next   // "Next player ›" swaps the sheet to another team's player
                }
            }
        }
        .fanZoneGate(isRequested: $gateRequested, gameName: "Know Her Game") {
            activePlayer = pendingPlayer
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your players this week")
                        .font(.title2.weight(.bold))
                    Text("\(store.playedCount) of \(store.players.count) played")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(store.players) { player in
                    playerRow(player)
                }
            }
            .padding(20)
        }
    }

    private func playerRow(_ player: KnowHerPlayer) -> some View {
        let played = store.isPlayed(player)
        let teamColor = DesignTeamColors.displayHex(for: player.teamAbbreviation).map { Color(hex: $0) } ?? accent
        return Button {
            pendingPlayer = player
            gateRequested = true
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
                    Label("\(score)/\(player.questions.count)", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
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
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(played ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .disabled(played)   // completed → no replay (one attempt)
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
