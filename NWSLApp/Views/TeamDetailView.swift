//
//  TeamDetailView.swift
//  NWSLApp
//
//  A club's page, pushed from the Teams directory. A pinned header (crest +
//  name + the same Follow star used in the Teams list, so toggling here reflects
//  everywhere) sits above a segmented sub-tab bar — Overview · Schedule · Squad —
//  and only the selected section scrolls. This replaces the old single long
//  scroll (header → full schedule → roster) where reaching the roster meant
//  scrolling past the whole season; every reference app (Athletic/MLS/NWSL)
//  fronts the team page with sub-tabs instead, so the roster is one tap away.
//
//  Sections, top to bottom:
//   • Overview — the glanceable default: next match + recent result, derived
//     from the shared MatchStore via Event.statusState (no extra fetch, no date
//     math). This is the "when's the next game / what was the score" use case.
//   • Schedule — that club's matches split into Upcoming / Results.
//   • Squad — the roster from ESPN's roster endpoint, grouped by position.
//
//  No NavigationStack of its own: it's pushed onto the Teams tab's stack, so the
//  back affordance comes for free (UI rule: every drilled-in view is reversible).
//  The roster loads independently of the schedule, so a roster failure never
//  blanks the header + Overview/Schedule that already rendered.
//

import SwiftUI

struct TeamDetailView: View {
    let club: Club

    @State private var viewModel = TeamDetailViewModel()
    @Environment(FollowingStore.self) private var following
    @Environment(MatchStore.self) private var matchStore

    // Named TeamSection (not Section) to avoid shadowing SwiftUI's Section view,
    // which the Schedule/Squad lists below use.
    private enum TeamSection: String, CaseIterable, Hashable {
        case overview = "Overview"
        case schedule = "Schedule"
        case squad = "Squad"
    }

    @State private var section: TeamSection = .overview

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Section", selection: $section) {
                ForEach(TeamSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            // Each branch owns its own scroll view, so switching tabs swaps the
            // scrollable content beneath the pinned header above.
            switch section {
            case .overview: overviewSection
            case .schedule: scheduleSection
            case .squad: squadSection
            }
        }
        .navigationTitle(club.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The schedule slice reuses the shared season store. If a user lands
            // here before Schedule has loaded it, kick the load; otherwise reuse
            // what's already there. Then load this club's roster.
            if case .idle = matchStore.state { await matchStore.load() }
            await viewModel.load(clubID: club.id)
        }
    }

    // MARK: - Header (pinned)

    private var header: some View {
        HStack(spacing: 16) {
            TeamLogo(urlString: club.logoURL, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(club.displayName)
                    .font(.title2.weight(.bold))
                if !club.abbreviation.isEmpty {
                    Text(club.abbreviation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            followButton
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var followButton: some View {
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
        } label: {
            Image(systemName: isFollowing ? "star.fill" : "star")
                .foregroundStyle(isFollowing ? .yellow : .secondary)
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        let matches = matchStore.matches(for: club)
        // matches(for:) is sorted ascending by kickoff, so "next" is the first
        // upcoming (prefer a live one) and "recent" is the last completed.
        let nextMatch = matches.first(where: { $0.statusState == "in" })
            ?? matches.first(where: { $0.statusState == "pre" })
        let recentMatch = matches.last(where: { $0.statusState == "post" })

        ScrollView {
            if matches.isEmpty {
                scheduleEmptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if let nextMatch {
                        labeledMatch(nextMatch.statusState == "in" ? "Live now" : "Next match", nextMatch)
                    }
                    if let recentMatch {
                        labeledMatch("Recent result", recentMatch)
                    }
                    if nextMatch == nil && recentMatch == nil {
                        Text("No matches found for this club.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    Button {
                        section = .schedule
                    } label: {
                        Label("Full schedule", systemImage: "calendar")
                    }
                    .padding(.top, 4)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func labeledMatch(_ label: String, _ event: Event) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.headline)
            MatchCard(event: event)
        }
    }

    // MARK: - Schedule (Upcoming / Results)

    @ViewBuilder
    private var scheduleSection: some View {
        let matches = matchStore.matches(for: club)
        let upcoming = matches.filter { $0.statusState != "post" }     // pre + in, soonest first
        let results = Array(matches.filter { $0.statusState == "post" }.reversed()) // most recent first

        List {
            if matches.isEmpty {
                Section { scheduleEmptyState }
            } else {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { matchRow($0) }
                    }
                }
                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { matchRow($0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func matchRow(_ event: Event) -> some View {
        MatchCard(event: event)
            // Let the card's own surface sit on the grouped background instead
            // of an inset List row.
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var scheduleEmptyState: some View {
        switch matchStore.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .error(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        case .loaded:
            // Loaded, but nothing matched this club — surfaces the abbreviation
            // join breaking rather than hiding it (see MatchStore.matches).
            Text("No matches found for this club.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Squad (roster)

    @ViewBuilder
    private var squadSection: some View {
        List {
            switch viewModel.state {
            case .idle, .loading:
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            case .error(let message):
                Section {
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await viewModel.load(clubID: club.id) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
            case .loaded:
                ForEach(viewModel.positionGroups) { group in
                    Section(group.label) {
                        ForEach(group.athletes) { athlete in
                            PlayerRow(athlete: athlete)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(club: Club(
            id: "21422",
            displayName: "Angel City FC",
            abbreviation: "LA",
            logoURL: nil
        ))
    }
    .environment(FollowingStore())
    .environment(MatchStore())
}
