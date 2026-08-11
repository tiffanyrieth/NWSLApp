//
//  NationalTeamDetailView.swift
//  NWSLApp
//
//  A country's team page — the browse surface behind a tapped national-team card
//  (owner decision 2026-07-31, reversing the earlier no-browse boundary; docs/national-teams.md §0).
//
//  ⚠️ THE TRUST MODEL IS DELIBERATELY DIFFERENT FROM CLUBS. The squad is fetched LIVE from
//  ESPN at view time, as-is: no proxy layer, no last-known-good, no nightly verification, no
//  overrides, nothing stored. NWSL rosters get that machinery because the app has a second
//  source and club pages to appeal to; ~100 federations have neither, and the owner's accepted
//  trade is "we show what ESPN says." Do not add caching or cross-checks here without
//  reopening that decision. The one promise kept is HONESTY: no squad from any feed → an
//  explicit empty state + retry, never a fabricated list.
//
//  Grammar mirrors TeamDetailView (the club page): identity header (flag hero + name), squad
//  grouped by position, tap-through to PlayerDetailView. The player page arrives via
//  LineupPlayerStatsView with the SOURCE FEED's slug, so a tapped player gets her tournament
//  stat line + her NWSL season block when she has one — same enrichment as an NT match lineup.
//

import SwiftUI

struct NationalTeamDetailView: View {
    let team: NationalTeam

    @State private var squad: ESPNService.NationalSquad?
    @State private var state: LoadState = .loading
    private let service = ESPNService()

    private enum LoadState { case loading, loaded, unavailable }

    private var accent: Color { team.accentColor }
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                content
                    .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.dsBgGrouped)
        .nativeBackButton() // identity-header screen: bare chevron, no title (UI rules)
        .task { await load() }
    }

    // MARK: - Header (flag hero — the country's crest-equivalent, rendered LARGE)

    private var header: some View {
        VStack(spacing: 10) {
            flagView
                .frame(width: 96, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: accent.opacity(0.5), radius: 18)
            Text(team.name)
                .dsFont(24, weight: .heavy)
                .foregroundStyle(Color.dsFgPrimary)
            Text(team.code)
                .dsFont(13, weight: .heavy)
                .tracking(1.2)
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            LinearGradient(colors: [accent.opacity(0.25), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// Bundled vector flag, same source as NationalTeamCard (zero network, present on first
    /// frame). A not-yet-bundled nation degrades to a code block in the accent color.
    @ViewBuilder
    private var flagView: some View {
        if let img = AssetRefreshService.override(flag: team.code.uppercased())
            ?? UIImage(named: "Flags/\(team.code.uppercased())") {
            Image(uiImage: img).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.2))
                Text(team.code).dsFont(20, weight: .heavy).foregroundStyle(accent)
            }
        }
    }

    // MARK: - Squad

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .padding(.top, 60)
        case .unavailable:
            // Honest absence — covers both "ESPN publishes no squad for this country" and a
            // failed request (the feed iteration can't distinguish them without extra plumbing).
            // Never fabricated, never a blank screen; retry covers the transient half.
            RetryStateView(message: "No squad available right now. ESPN may not publish one for \(team.name) — match lineups still appear on match days.") {
                state = .loading
                Task { await load() }
            }
            .padding(.top, 40)
        case .loaded:
            if let squad {
                squadContent(squad)
            }
        }
    }

    private func squadContent(_ result: ESPNService.NationalSquad) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            // Which competition feed supplied this list — the honest twin of the club page's
            // "Roster as of …" line. Squads differ per feed (a tournament feed carries only its
            // registered squad), so naming the source keeps a Zambia list of 26 explicable
            // against a WAFCON lineup of 23.
            Text("Squad · \(result.feed.label)")
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
            ForEach(Roster.grouped(result.squad.athletes)) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label)
                        .dsFont(13, weight: .bold).tracking(0.3)
                        .foregroundStyle(accent)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(group.athletes) { athlete in
                            NavigationLink {
                                LineupPlayerStatsView(ref: LineupPlayerRef(
                                    athlete: athlete,
                                    clubID: nil,                       // a country id would 404 the club-roster route
                                    accentHex: team.brandHex,
                                    leagueSlug: result.feed.slug,
                                    competitionLabel: result.feed.label
                                ))
                            } label: {
                                playerCard(athlete)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // Mirrors TeamDetailView's squad cell: headshot/initials circle, name + jersey.
    // NWSL players show real headshots (the headshot map covers only NWSL athletes —
    // a photo here literally means "she plays in NWSL"); everyone else gets a monogram.
    private func playerCard(_ athlete: Athlete) -> some View {
        HStack(spacing: 11) {
            PlayerHeadshot(athleteID: athlete.id, size: 42) {
                ZStack {
                    Circle().fill(accent.opacity(0.16))
                    Text(initials(for: athlete))
                        .dsFont(15, weight: .bold)
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                .frame(width: 42, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(athlete.shortName ?? athlete.name)
                    .dsFont(15.5, weight: .semibold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let jersey = athlete.jersey {
                    Text("#\(jersey)")
                        .dsFont(13)
                        .foregroundStyle(Color.dsFgSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd))
    }

    private func initials(for athlete: Athlete) -> String {
        let parts = athlete.name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    // MARK: - Load

    private func load() async {
        guard squad == nil else { return } // a success sticks for the visit; retry re-enters via the button
        if let result = await service.nationalTeamSquad(code: team.code) {
            squad = result
            state = .loaded
        } else {
            // Distinguish "ESPN has no squad" from "we couldn't ask": nationalTeamSquad
            // swallows per-feed errors while iterating, so a fully-offline device also lands
            // here. Offline → retry affordance; online-but-empty → the honest empty state.
            state = .unavailable
        }
    }
}
