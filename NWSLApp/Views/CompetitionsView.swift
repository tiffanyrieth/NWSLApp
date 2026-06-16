//
//  CompetitionsView.swift
//  NWSLApp
//
//  "Competitions" — reached from the "Follow competitions ›" row at the bottom of the
//  Teams tab. The opt-in extensions that make the app more than NWSL: the CONCACAF W
//  Champions Cup (a club competition — one global toggle that folds your followed
//  clubs' continental matches into the Schedule's "My teams") and women's national
//  teams (followable entities whose matches weave into "My teams" alongside clubs).
//
//  Per the Competitions feature handoff. Everything turned on here folds into "My
//  teams" — there is no separate schedule chip. Following a national team reveals a
//  per-team alert bell (reusing TeamAlertStore, keyed by FIFA code) that toggles
//  directly, exactly like a club bell; "Browse all national teams" opens the full set.
//

import SwiftUI

struct CompetitionsView: View {
    @Environment(FollowingStore.self) private var following
    // National-team alert bells share the club alert store (keyed by FIFA code).
    @Environment(TeamAlertStore.self) private var teamAlerts

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Go beyond the league. Anything you turn on here folds into My teams on your schedule.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                section("CLUB COMPETITIONS") {
                    championsCupRow
                }

                section("NATIONAL TEAMS") {
                    Text("Follow your national team. Their matches appear in My teams alongside your clubs.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(NationalTeam.featured) { nationalTeamCard($0) }
                    }
                    browseAllRow
                }
            }
            .padding(16)
        }
        .background(Color.dsBgGrouped)
        .navigationContextLabel("Competitions")
    }

    // MARK: - Club competitions

    private var championsCupRow: some View {
        let on = following.isConcacafFollowed
        return HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 17))
                .foregroundStyle(on ? Color.dsSuccess : Color.dsFgSecondary)
                .frame(width: 36, height: 36)
                .background(Color.dsBgTertiary, in: RoundedRectangle(cornerRadius: DS.radiusSm))
            VStack(alignment: .leading, spacing: 2) {
                Text("Concacaf W Champions Cup")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                Text("Adds your clubs' Champions Cup matches to My teams.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { following.isConcacafFollowed },
                                     set: { following.setConcacafFollowed($0) }))
                .labelsHidden()
                .tint(Color.dsSuccess)
        }
        .padding(14)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // MARK: - National teams

    private func nationalTeamCard(_ team: NationalTeam) -> some View {
        let isFollowing = following.isFollowing(nationalTeam: team)
        return VStack(spacing: 9) {
            Text(team.code)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isFollowing ? Color.dsAccent : Color.dsFgSecondary)
                .frame(width: 44, height: 44)
                .background(isFollowing ? Color.dsAccent.opacity(0.15) : Color.dsBgTertiary,
                            in: RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
            Text(team.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsFgPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .center)
            followControlRow(for: team)
        }
        .padding(EdgeInsets(top: 16, leading: 12, bottom: 13, trailing: 12))
        .frame(maxWidth: .infinity)
        .background(cardBackground(isFollowing: isFollowing))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .stroke(isFollowing ? Color.dsAccent.opacity(0.4) : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    // Follow pill (flex) + — once following — a match-alert bell, mirroring the NWSL
    // club card (alerts require following, so the bell only appears when followed).
    private func followControlRow(for team: NationalTeam) -> some View {
        let isFollowing = following.isFollowing(nationalTeam: team)
        return HStack(spacing: 7) {
            Button { toggleFollow(team) } label: {
                Text(isFollowing ? "★ Following" : "☆ Follow")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFollowing ? Color.dsAccent : Color.dsFgSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isFollowing ? Color.dsAccent.opacity(0.12) : Color.dsBgTertiary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFollowing ? "Unfollow \(team.name)" : "Follow \(team.name)")
            if isFollowing { nationalTeamBell(for: team) }
        }
    }

    private func nationalTeamBell(for team: NationalTeam) -> some View {
        let on = teamAlerts.alertsEnabled(for: team.code)
        // Direct toggle — same as a club bell. Never requests iOS permission (that's
        // the hub's job); the Teams-tab coach mark covers the education.
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
        // Unfollowing drops its alerts too — alerts require following (same rule as
        // clubs, which TeamAlertSyncCoordinator enforces for the NWSL set).
        if wasFollowing { teamAlerts.clearAlerts(for: team.code) }
    }

    // "Browse all national teams ›" → the full searchable set.
    private var browseAllRow: some View {
        NavigationLink { BrowseAllTeamsView() } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                Text("Browse all national teams")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.dsAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardBackground(isFollowing: Bool) -> some View {
        if isFollowing {
            // Accent-blue wash (national teams have no brand color) — mirrors the NWSL
            // club card's team-color bloom.
            ZStack {
                Color.dsBgCard
                RadialGradient(colors: [Color.dsAccent.opacity(0.17), .clear],
                               center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: 90)
            }
        } else {
            Color.dsBgCard
        }
    }

    // MARK: - Shared

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).trackedCaps(size: 11, tracking: 0.6, weight: .semibold, color: .dsFgTertiary)
            content()
        }
    }
}

#Preview {
    NavigationStack {
        CompetitionsView()
            .environment(FollowingStore())
            .environment(TeamAlertStore())
    }
}
