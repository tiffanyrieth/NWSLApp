//
//  OnboardingView.swift
//  NWSLApp
//
//  First-open onboarding — "Make it yours": pick the teams you follow. One
//  screen, one purpose (per the Home design spec). A single alphabetical list
//  of every club (no grid, no search — 16-20 teams scroll faster than they
//  type), each row a whole-row follow toggle. A persistent bottom bar shows the
//  running "Follow N teams" count and the "you can always change this later"
//  reassurance.
//
//  It rides the Home tab's NavigationStack (rendered in place of the hub while
//  `FollowingStore.hasOnboarded` is false) rather than a full-screen cover, so
//  the tab bar stays visible from the start — signaling depth, per the spec.
//  Tapping "Follow N teams" calls `completeOnboarding()`, which flips Home to
//  the hub. It also `dismiss()`es so the same view works when re-presented as a
//  sheet from Home's empty state.
//
//  Reuses TeamsViewModel for the club fetch (identical need: the directory) and
//  the shared FollowingStore for the toggles — the picks made here are the same
//  follows the Teams tab shows.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = TeamsViewModel()
    @State private var showCompetitions = false
    @Environment(FollowingStore.self) private var following
    @Environment(\.dismiss) private var dismiss

    private var followCount: Int { following.followedIDs.count }

    var body: some View {
        content
            .navigationTitle("Make it yours")
            .navigationBarTitleDisplayMode(.large)
            .task {
                if case .idle = viewModel.state { await viewModel.load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading teams…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message)
        case .loaded:
            picker
        }
    }

    private var picker: some View {
        List {
            Section {
                ForEach(viewModel.clubs) { row(for: $0) }
            } header: {
                Text("Follow your teams to get their next matches, news, and everything that matters to you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }

            internationalSection
        }
        .listStyle(.insetGrouped)
        // Persistent bottom bar: the running follow count + reassurance, always
        // visible above the list (and above the tab bar).
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private func row(for club: Club) -> some View {
        // The whole row toggles follow here (no navigation in onboarding), so a
        // single plain button over the row is all we need.
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
        } label: {
            HStack(spacing: 12) {
                TeamLogo(urlString: club.logoURL, size: 32)
                Text(club.displayName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: isFollowing ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isFollowing ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "Unfollow \(club.displayName)" : "Follow \(club.displayName)")
    }

    // Collapsed-by-default international competitions — invisible to new fans,
    // zero friction. TEMP (placeholder): the rows are intentional "coming soon"
    // markers, NOT wired to follow, because FollowingStore tracks club IDs only.
    // Following competitions needs its own data model (a Competition type + a
    // follow set) — build that, then make these toggle like the club rows.
    private var internationalSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showCompetitions) {
                ForEach(internationalCompetitions, id: \.self) { name in
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 32)
                        Text(name)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } label: {
                Label("Also follow international competitions", systemImage: "globe")
            }
        }
    }

    private let internationalCompetitions = [
        "USWNT",
        "CONCACAF W Champions League",
        "Women's World Cup",
        "Another national team",
    ]

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button {
                following.completeOnboarding()
                dismiss()
            } label: {
                Text(followCount == 0
                     ? "Follow your teams"
                     : "Follow \(followCount) team\(followCount == 1 ? "" : "s")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(followCount == 0)

            Text("You can always change this later")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        OnboardingView()
            .environment(FollowingStore())
    }
}
