//
//  CompetitionsView.swift
//  NWSLApp
//
//  A standalone "Follow competitions" screen, reachable from the bottom of the
//  Teams tab. International competitions are offered (collapsed) during
//  onboarding, but a user who skips them there previously had no way back in —
//  this screen is that path.
//
//  It's a thin surface over the same FollowingStore competition API the
//  onboarding rows use (`toggle`/`isFollowing` for FollowedCompetition), so the
//  two stay perfectly in sync. The list is the static curated set
//  (`FollowedCompetition.all`) — no network, no view model needed.
//
//  Following a competition is remembered but doesn't change the Schedule yet
//  (it's NWSL-only) — that's the larger competition-aware-schedule work in
//  CLAUDE.md's What's-Next. The footer says so, matching the onboarding copy.
//

import SwiftUI

struct CompetitionsView: View {
    @Environment(FollowingStore.self) private var following

    var body: some View {
        List {
            Section {
                ForEach(FollowedCompetition.all) { competition in
                    competitionRow(competition)
                }
            } header: {
                Text("Follow international competitions to keep them on your radar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                Text("Saved to your follows. Competition fixtures aren't in the schedule yet — that's coming.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Competitions")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Mirrors OnboardingView.competitionRow so the two follow surfaces look and
    // behave identically — a whole-row plain button that toggles the follow.
    private func competitionRow(_ competition: FollowedCompetition) -> some View {
        let isFollowing = following.isFollowing(competition)
        return Button {
            following.toggle(competition)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: competition.systemImage)
                    .foregroundStyle(isFollowing ? Color.accentColor : Color.secondary)
                    .frame(width: 32)
                Text(competition.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: isFollowing ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isFollowing ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Unfollow \(competition.name)" : "Follow \(competition.name)")
    }
}

#Preview {
    NavigationStack {
        CompetitionsView()
            .environment(FollowingStore())
    }
}
