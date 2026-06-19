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
//  It's the full-screen first-open gate: RootTabView renders it (in its own
//  NavigationStack) IN PLACE OF the whole TabView while `FollowingStore.hasOnboarded`
//  is false, so there is NO tab bar and onboarding can't be skipped by tapping a tab.
//  Tapping "Follow N teams" calls `completeOnboarding()`, which flips RootTabView to
//  the TabView. It also `dismiss()`es (a harmless no-op in the gate path) so the same
//  view still works when re-presented as a sheet from Home's "edit teams" empty state.
//
//  Reuses TeamsViewModel for the club fetch (identical need: the directory) and
//  the shared FollowingStore for the toggles — the picks made here are the same
//  follows the Teams tab shows.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = TeamsViewModel()
    @Environment(FollowingStore.self) private var following
    // The shared club directory (injected in RootTabView); the view model reads
    // its state/clubs through this.
    @Environment(ClubStore.self) private var clubStore
    // The shared Home content store — warmed the instant a team is picked so Home is
    // already populated by the time onboarding finishes (no first-paint loading flash).
    @Environment(HomeContentStore.self) private var homeContent
    @Environment(\.dismiss) private var dismiss

    private var followCount: Int { following.followedIDs.count }

    var body: some View {
        content
            .navigationTitle("Make it yours")
            .navigationBarTitleDisplayMode(.large)
            .task {
                viewModel.clubStore = clubStore
                if case .idle = clubStore.state { await viewModel.load() }
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
            // The intro rides a BORDERLESS row (not a section header): List headers
            // render with reduced/vibrant prominence that compounds on `.secondary`
            // and pushes it below readable contrast, so we keep it as normal row
            // content where `.secondary` renders at its true secondaryLabel tone.
            // Hierarchy is bold nav title → readable subtitle → smaller caption,
            // established by SIZE + spacing (not by dimming the caption).
            Section {
                introBlock
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))
            }

            Section {
                ForEach(viewModel.clubs) { row(for: $0) }
            }

            internationalSection
        }
        .listStyle(.insetGrouped)
        // Persistent bottom bar: the running follow count + reassurance, always
        // visible above the list (and above the tab bar).
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Follow teams to see their matches, news, and more across the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Clarifier that preempts the "will following spam me with alerts?" hesitation —
            // following only feeds Home; alerts are opt-in and managed separately in Teams.
            // Smaller than the subtitle but kept at .secondary so it stays legible.
            Text("Following isn't the same as game notifications. Turn those on anytime in the Teams tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                // Guarantee full wrapping (never truncate) on the smallest screens (SE/mini).
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for club: Club) -> some View {
        // The whole row toggles follow here (no navigation in onboarding), so a
        // single plain button over the row is all we need.
        let isFollowing = following.isFollowing(club)
        return Button {
            following.toggle(club)
            // Warm Home's content for the current selection (debounced) so it's ready by
            // the time onboarding finishes — re-warms as the selection changes.
            homeContent.warm(following: following, clubStore: clubStore)
        } label: {
            HStack(spacing: 12) {
                TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 32)
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

    // A quiet pointer, not a toggle list: international competitions (national teams
    // + the Champions Cup) are followed in their own hub (Teams → Follow competitions),
    // which is the designed flow. Onboarding stays focused on picking clubs; this just
    // tells a new fan the rest exists. (The old inert competition toggles lived here.)
    private var internationalSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Following a national team?")
                        .foregroundStyle(.primary)
                    Text("Add national teams + the Champions Cup later in Teams → Follow competitions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
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
            .environment(ClubStore())
            .environment(HomeContentStore())
    }
}
