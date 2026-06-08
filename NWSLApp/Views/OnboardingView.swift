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
    // zero friction. The rows are real follow toggles (mirroring the club rows),
    // backed by FollowingStore.followedCompetitionIDs. Following one is remembered
    // but doesn't change the Schedule yet (it's NWSL-only) — that's the larger
    // competition-aware-schedule work in CLAUDE.md's What's-Next.
    private var internationalSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showCompetitions) {
                ForEach(FollowedCompetition.all) { competition in
                    competitionRow(competition)
                }
            } label: {
                Label("Also follow international competitions", systemImage: "globe")
            }
        }
    }

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

    private var bottomBar: some View {
        VStack(spacing: 6) {
            followButton

            Text("You can always change this later")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // The follow CTA progresses outline → filled as teams are picked. The empty
    // state uses an explicit accent *outline* (visible border, no fill) so it
    // reads as a not-yet-active button — the old disabled `.borderedProminent`
    // gray capsule with muted centered text looked like a search bar. We draw the
    // border ourselves rather than leaning on `.bordered` + `.disabled`, whose
    // system dimming washes the tint back to gray. Filled blue once ≥1 team is
    // selected; the empty action is a no-op so onboarding still needs a pick.
    // `.controlSize(.regular)` keeps it tappable without eating a full row.
    @ViewBuilder
    private var followButton: some View {
        let title = followCount == 0
            ? "Follow your teams"
            : "Follow \(followCount) team\(followCount == 1 ? "" : "s")"

        if followCount == 0 {
            Button {} label: {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Select at least one team to continue")
        } else {
            Button {
                following.completeOnboarding()
                dismiss()
            } label: {
                Text(title)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
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
