//
//  CompetitionsView.swift
//  NWSLApp
//
//  "Competitions" — reached from the "Follow competitions ›" row at the bottom of the
//  Teams tab. Follow women's national teams (followable entities whose matches weave into
//  "My teams" alongside clubs). CONCACAF W Champions Cup is NOT here anymore — an NWSL
//  club's continental matches are core schedule content, always shown in the Schedule
//  overview for everyone (no opt-in), so the old toggle was retired.
//
//  National teams turned on here fold into "My teams" — there is no separate schedule chip.
//  (National teams ARE browsable since 2026-07-31 — a card taps through to NationalTeamDetailView.)
//  The National Teams section is ONE inline, searchable, DATA-DRIVEN A-Z list
//  (`NationalTeamDirectoryStore` → proxy `/national-teams`, real ESPN coverage) — there is no
//  separate "Browse all" screen. The search bar sits UNDER the section header, scoped to the
//  list below it.
//

import SwiftUI

struct CompetitionsView: View {
    @Environment(FollowingStore.self) private var following

    @State private var store = NationalTeamDirectoryStore()
    @State private var query = ""
    // National-team bells share the same cascade + sign-in intercept + toast as club bells
    // (MatchAlertPresenter, scoped into the cards below). `showHub` pushes the Notifications hub
    // when the toast's "Customize alerts" is tapped.
    @State private var alertPresenter = MatchAlertPresenter()
    @State private var showHub = false

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Follow your national team. Any team you turn on here folds into My teams on your schedule.")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                section("NATIONAL TEAMS") {
                    Text("Follow your national team. Their matches appear in My teams alongside your clubs.")
                        .dsFont(13.5)
                        .foregroundStyle(Color.dsFgSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    searchField
                    nationalTeamsContent
                }
            }
            .padding(16)
        }
        // Scope the shared presenter to this screen's national-team cards so their bells drive it.
        .environment(alertPresenter)
        .background(Color.dsBgGrouped)
        .nativeBackButton(title: "Competitions")
        .task { await store.load() }
        // Same bell affordances as the Teams tab: the confirmation toast + the Tier-2 sign-in intercept.
        .matchAlertToast(alertPresenter) { showHub = true }
        .sheet(isPresented: $alertPresenter.showAuthPrompt, onDismiss: { alertPresenter.cancelPending() }) {
            NotificationAuthPromptView(onSignedIn: { alertPresenter.onSignedIn() })
        }
        .navigationDestination(isPresented: $showHub) { NotificationsView() }
    }

    // MARK: - National teams (inline, searchable, data-driven)

    // Scoped to the national-teams list below it — deliberately NOT a `.searchable` nav-bar field,
    // which would read as searching the whole screen.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .dsFont(15)
                .foregroundStyle(Color.dsFgSecondary)
            TextField("Search by name or code", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .dsFont(16)
                .foregroundStyle(Color.dsFgPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsFont(16)
                        .foregroundStyle(Color.dsFgSecondary)
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
                    .dsFont(15)
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
            Text(title).trackedCaps(size: 11, tracking: 0.6, weight: .semibold, color: .dsFgSecondary)
            content()
        }
    }

    private var loadingView: some View {
        ProgressView("Loading teams…")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private var retryView: some View {
        RetryStateView(message: "Couldn't load teams. Tap to retry", style: .inline) {
            await store.load()
        }
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
            Text(title).trackedCaps(size: 11, tracking: 0.6, weight: .semibold, color: .dsFgSecondary)
            content()
        }
    }
}

#Preview {
    NavigationStack {
        CompetitionsView()
            .environment(FollowingStore())
            .environment(TeamAlertStore())
            .environment(NotificationPreferencesStore())
            .environment(AuthStore())
    }
}
