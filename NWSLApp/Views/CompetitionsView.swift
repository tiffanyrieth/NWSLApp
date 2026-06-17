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
                    championsCupCard
                }

                section("NATIONAL TEAMS") {
                    Text("Follow your national team. Their matches appear in My teams alongside your clubs.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(NationalTeam.featured) { NationalTeamCard($0) }
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

    // Elevated to the Teams-tab card weight: a real content card (radiusXl, generous
    // padding) with a tinted trophy medallion that lights up when the competition is on
    // — not a basic settings row.
    private var championsCupCard: some View {
        let on = following.isConcacafFollowed
        return HStack(spacing: 13) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 19))
                .foregroundStyle(on ? Color.dsSuccess : Color.dsFgSecondary)
                .frame(width: 44, height: 44)
                .background(on ? Color.dsSuccess.opacity(0.16) : Color.dsBgTertiary,
                            in: RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(16)
        .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .stroke(on ? Color.dsSuccess.opacity(0.35) : .clear, lineWidth: 1)
        )
    }

    // MARK: - National teams

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
