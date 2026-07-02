//
//  NationalTeamCard.swift
//  NWSLApp
//
//  One national-team grid card, shared by the Competitions hub's featured grid and the
//  "Browse all national teams" grid so both read identically (they used to be two
//  divergent layouts — a grid card and a flat list row). It mirrors the NWSL club card
//  (`TeamsView.teamCard`): a flag with a soft country-color halo as the visual anchor,
//  the FIFA code below it as text confirmation (the crest+abbreviation pattern), the
//  full name, then a Follow pill + — once followed — a match-alert bell. Followed teams
//  get the same team-color radial wash + border treatment, here keyed by the country's
//  curated brand color since national teams have no ESPN brand color.
//
//  Reads FollowingStore + TeamAlertStore from the environment (both injected at the
//  NavigationStack root), so the two grids just lay out `NationalTeamCard($0)`.
//

import SwiftUI

struct NationalTeamCard: View {
    let team: NationalTeam

    @Environment(FollowingStore.self) private var following
    // National-team alert bells share the club alert store (keyed by FIFA code).
    @Environment(TeamAlertStore.self) private var teamAlerts
    // Bell → shared cascade + Tier-2 sign-in intercept + toast (scoped in by CompetitionsView).
    @Environment(NotificationPreferencesStore.self) private var notifications
    @Environment(AuthStore.self) private var auth
    @Environment(MatchAlertPresenter.self) private var alertPresenter

    // Flag dimensions scale with Dynamic Type (capped at the root), like the club crest —
    // the flag is hero content paired with the FIFA code + name, so it grows with the text.
    @ScaledMetric(relativeTo: .body) private var flagWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var flagHeight: CGFloat = 36

    init(_ team: NationalTeam) { self.team = team }

    private var isFollowing: Bool { following.isFollowing(nationalTeam: team) }
    private var accent: Color { team.accentColor }

    var body: some View {
        VStack(spacing: 9) {
            flag
            Text(team.code)
                .dsFont(12, weight: .heavy)
                .tracking(0.4)
                .foregroundStyle(accent)
            Text(team.name)
                .dsFont(14, weight: .semibold)
                .foregroundStyle(Color.dsFgPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .lineSpacing(1)
                // Keep long names (or large text) within two lines rather than spilling
                // a third line that misaligns the grid; scale down instead.
                .minimumScaleFactor(0.8)
                // Reserve two lines so flag (above) + controls (below) stay vertically
                // aligned across 1- and 2-line names, centered like the club card.
                .frame(minHeight: 35, alignment: .center)
            controlRow
        }
        .padding(EdgeInsets(top: 18, leading: 12, bottom: 13, trailing: 12))
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .stroke(isFollowing ? accent.opacity(0.4) : .clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl))
    }

    // The bundled vector flag (`Flags/<FIFA>`), rendered on the first frame with ZERO
    // network so the Competitions grid is complete the instant it opens. Nil only if a
    // newly-added nation hasn't been bundled yet → the CachedThumbnail network path covers it.
    private var bundledFlag: UIImage? {
        let key = team.code.uppercased()
        // Cached post-rebrand override first, then the bundled vector flag.
        return AssetRefreshService.override(flag: key) ?? UIImage(named: "Flags/\(key)")
    }

    // Real flag with a soft country-color halo behind it (a blurred color block, NOT a
    // drop shadow — keeps the app's no-shadow rule), mirroring the crest's halo. A
    // hairline keeps white-edged flags (Japan) defined on the dark card; on a load miss
    // it falls back to a country-color block so the mark never goes blank.
    private var flag: some View {
        flagImage
        .frame(width: flagWidth, height: flagHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(accent.opacity(0.22))
                .blur(radius: 14)
        )
    }

    // Bundled vector flag first (no network); the live flagcdn flag is the fallback for a
    // not-yet-bundled nation, and a country-color block if even that misses.
    @ViewBuilder
    private var flagImage: some View {
        if let bundledFlag {
            Image(uiImage: bundledFlag)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            CachedThumbnail(url: team.flagURL) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isFollowing {
            // Country-color wash blooming from behind the flag, over the base card —
            // the club card's team-color bloom, keyed by the national brand color.
            ZStack {
                Color.dsBgCard
                RadialGradient(
                    colors: [accent.opacity(0.17), .clear],
                    center: UnitPoint(x: 0.5, y: 0.32),
                    startRadius: 0, endRadius: 115
                )
            }
        } else {
            Color.dsBgCard
        }
    }

    // Follow/Following pill (flexes to fill) + a match-alert bell that only appears once
    // followed (alerts require following), mirroring the NWSL club card's control row.
    private var controlRow: some View {
        HStack(spacing: 7) {
            followPill
            if isFollowing { bell }
        }
        .padding(.top, 2)
    }

    private var followPill: some View {
        Button { toggleFollow() } label: {
            HStack(spacing: 5) {
                Image(systemName: isFollowing ? "star.fill" : "star")
                    .dsFont(11)
                    .foregroundStyle(isFollowing ? Color.dsFollowStar : Color.dsFgSecondary)
                Text(isFollowing ? "Following" : "Follow")
                    .dsFont(12.5, weight: .semibold)
                    .foregroundStyle(isFollowing ? Color.dsFgPrimary : Color.dsFgSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isFollowing ? Color.dsBgTertiary : Color.clear)
            .overlay(Capsule().stroke(isFollowing ? .clear : Color.dsFgQuaternary, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Unfollow \(team.name)" : "Follow \(team.name)")
    }

    private var bell: some View {
        let on = teamAlerts.alertsEnabled(for: team.code)
        // Same shared flow as a club bell: ON cascades the default bundle (first time) + intercepts
        // sign-in when signed out + shows the toast (CompetitionsView hosts the toast/sheet).
        return Button {
            alertPresenter.requestToggle(key: team.code, turnOn: !on, isSignedIn: auth.isSignedIn,
                                         alerts: teamAlerts, prefs: notifications)
        } label: {
            Image(systemName: on ? "bell.fill" : "bell")
                .dsFont(13, weight: .medium)
                .foregroundStyle(on ? Color.dsAccent : Color.dsFgSecondary)
                .frame(width: 36, height: 32)
                .background(on ? Color.dsAccentMuted : Color.dsBgTertiary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Turn off match alerts for \(team.name)"
                               : "Turn on match alerts for \(team.name)")
    }

    private func toggleFollow() {
        let wasFollowing = isFollowing
        following.toggle(nationalTeam: team)
        // Unfollowing drops its alerts too — alerts require following (same rule as
        // clubs, enforced for the NWSL set by TeamAlertSyncCoordinator).
        if wasFollowing { teamAlerts.clearAlerts(for: team.code) }
    }
}

#Preview {
    let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    return ScrollView {
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(NationalTeam.featured) { NationalTeamCard($0) }
        }
        .padding(16)
    }
    .background(Color.dsBgGrouped)
    .environment(FollowingStore())
    .environment(TeamAlertStore())
}
