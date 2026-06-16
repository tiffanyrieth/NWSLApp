//
//  BrowseAllTeamsView.swift
//  NWSLApp
//
//  "Browse all national teams" — pushed from the Competitions view. A searchable
//  list over the full `NationalTeam.all` set (the featured grid is just the head of
//  it), so a user can find a team that isn't one of the eight featured cards. Each
//  row mirrors the grid card's controls: a Follow/Following pill and — once
//  following — a match-alert bell, both backed by the same stores (FollowingStore +
//  TeamAlertStore, keyed by FIFA code). The list is data-driven: adding a team is one
//  more `NationalTeam.all` entry, no code change here.
//

import SwiftUI

struct BrowseAllTeamsView: View {
    @Environment(FollowingStore.self) private var following
    @Environment(TeamAlertStore.self) private var teamAlerts
    @State private var query = ""

    private var results: [NationalTeam] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return NationalTeam.all }
        return NationalTeam.all.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.code.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if results.isEmpty {
                    Text("No teams match “\(query)”.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(results) { row($0) }
                }
            }
            .padding(16)
        }
        .background(Color.dsBgGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search by name or code")
        .navigationContextLabel("National Teams")
    }

    private func row(_ team: NationalTeam) -> some View {
        let isFollowing = following.isFollowing(nationalTeam: team)
        return HStack(spacing: 12) {
            Text(team.code)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(isFollowing ? Color.dsAccent : Color.dsFgSecondary)
                .frame(width: 36, height: 36)
                .background(isFollowing ? Color.dsAccent.opacity(0.15) : Color.dsBgTertiary,
                            in: RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
            Text(team.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.dsFgPrimary)
            Spacer(minLength: 8)
            if isFollowing { bell(for: team) }
            followPill(for: team, isFollowing: isFollowing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .stroke(isFollowing ? Color.dsAccent.opacity(0.35) : .clear, lineWidth: 1)
        )
    }

    private func followPill(for team: NationalTeam, isFollowing: Bool) -> some View {
        Button { toggleFollow(team) } label: {
            Text(isFollowing ? "★ Following" : "☆ Follow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFollowing ? Color.dsAccent : Color.dsFgSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isFollowing ? Color.dsAccent.opacity(0.12) : Color.dsBgTertiary, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Unfollow \(team.name)" : "Follow \(team.name)")
    }

    private func bell(for team: NationalTeam) -> some View {
        let on = teamAlerts.alertsEnabled(for: team.code)
        return Button { teamAlerts.toggle(for: team.code) } label: {
            Image(systemName: on ? "bell.fill" : "bell")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
                .frame(width: 34, height: 33)
                .background(on ? Color.dsAccentMuted : Color.dsBgTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Turn off match alerts for \(team.name)"
                               : "Turn on match alerts for \(team.name)")
    }

    private func toggleFollow(_ team: NationalTeam) {
        let wasFollowing = following.isFollowing(nationalTeam: team)
        following.toggle(nationalTeam: team)
        // Unfollowing drops its alerts too — alerts require following.
        if wasFollowing { teamAlerts.clearAlerts(for: team.code) }
    }
}

#Preview {
    NavigationStack {
        BrowseAllTeamsView()
            .environment(FollowingStore())
            .environment(TeamAlertStore())
    }
}
