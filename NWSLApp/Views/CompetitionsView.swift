//
//  CompetitionsView.swift
//  NWSLApp
//
//  "Competitions" — reached from the "Follow competitions ›" row at the bottom of the
//  Teams tab. The opt-in extensions that make the app more than NWSL: the CONCACAF W
//  Champions Cup (a club competition — one global toggle that folds your followed clubs'
//  continental matches into the Schedule's "My teams") and women's national teams
//  (followable entities whose matches weave into "My teams" alongside clubs).
//
//  Everything turned on here folds into "My teams" — there is no separate schedule chip,
//  and national teams (like the Champions Cup) get NO detail page; following just folds
//  fixtures in. The National Teams section is ONE inline, searchable, DATA-DRIVEN A-Z list
//  (`NationalTeamDirectoryStore` → proxy `/national-teams`, real ESPN coverage) — there is no
//  separate "Browse all" screen. The search bar sits UNDER the section header, scoped to the
//  list below it (not the Champions Cup toggle above).
//

import SwiftUI

struct CompetitionsView: View {
    @Environment(FollowingStore.self) private var following

    @State private var store = NationalTeamDirectoryStore()
    @State private var query = ""

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
                    searchField
                    nationalTeamsContent
                }
            }
            .padding(16)
        }
        .background(Color.dsBgGrouped)
        .navigationContextLabel("Competitions")
        .task { await store.load() }
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

    // MARK: - National teams (inline, searchable, data-driven)

    // Scoped to the national-teams list below it — deliberately NOT a `.searchable` nav-bar field,
    // which would read as searching the whole screen (incl. the Champions Cup toggle above).
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.dsFgSecondary)
            TextField("Search by name or code", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .foregroundStyle(Color.dsFgPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.dsFgTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.dsBgCard, in: Capsule())
    }

    // While searching → one filtered A-Z result list (Suggested hidden). Otherwise → a
    // SUGGESTED shortcut (the curated/bundled teams, USA first) ABOVE the full A-Z list, which
    // still includes those teams in their normal positions (the iOS "Frequently Used" pattern —
    // the two headers make the repeat read as intentional).
    @ViewBuilder
    private var nationalTeamsContent: some View {
        if isSearching {
            searchResults
        } else {
            VStack(alignment: .leading, spacing: 16) {
                subSection("SUGGESTED") { teamGrid(NationalTeam.featured) }
                subSection("ALL NATIONAL TEAMS") { allTeams }
            }
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // The data-driven A-Z list (honest states). The Suggested grid above it is static + bundled,
    // so it renders instantly even while this is still loading.
    @ViewBuilder
    private var allTeams: some View {
        switch store.state {
        case .idle, .loading: loadingView
        case .failed:         retryView
        case .loaded(let teams): teamGrid(teams)
        }
    }

    // Searching filters the full A-Z list; needs it loaded, so it carries the same honest states.
    @ViewBuilder
    private var searchResults: some View {
        switch store.state {
        case .idle, .loading: loadingView
        case .failed:         retryView
        case .loaded(let teams):
            let results = filter(teams)
            if results.isEmpty {
                Text("No teams match “\(query)”.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                teamGrid(results)
            }
        }
    }

    private func teamGrid(_ teams: [NationalTeam]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(teams) { NationalTeamCard($0) }
        }
    }

    @ViewBuilder
    private func subSection<Content: View>(_ title: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).trackedCaps(size: 11, tracking: 0.6, weight: .semibold, color: .dsFgTertiary)
            content()
        }
    }

    private var loadingView: some View {
        ProgressView("Loading teams…")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private var retryView: some View {
        VStack(spacing: 10) {
            Text("Couldn't load teams — tap to retry")
                .font(.system(size: 13))
                .foregroundStyle(Color.dsFgSecondary)
            Button("Try again") { Task { await store.load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func filter(_ teams: [NationalTeam]) -> [NationalTeam] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return teams }
        return teams.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.code.localizedCaseInsensitiveContains(q)
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
