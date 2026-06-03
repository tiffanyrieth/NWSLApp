//
//  ScheduleView.swift
//  NWSLApp
//
//  Full-season NWSL schedule. Vertical list grouped by local day. On first
//  successful load, the list scrolls to today's section (or the next upcoming
//  matchday if today has no matches) so fans land on what's relevant instead
//  of the top of the list (months back).
//
//  Design rules honored:
//   #1 — no persistent overlays obscuring content (status badges live inside
//        the row; nav title is the standard NavigationStack title bar).
//   #2 — NavigationStack is in place so future detail pushes are reversible.
//

import SwiftUI

struct ScheduleView: View {
    @State private var viewModel = ScheduleViewModel()
    // Prevents pull-to-refresh from yanking the scroll position back to today.
    @State private var hasScrolledToToday = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedule")
                .refreshable { await viewModel.load() }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading schedule…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorView(message)
        case .loaded:
            loadedList
        }
    }

    private var loadedList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.sections) { section in
                    Section {
                        ForEach(section.events) { event in
                            MatchCard(event: event)
                        }
                    } header: {
                        Text(section.label)
                            .id(section.id)
                    }
                }
            }
            .onChange(of: viewModel.sections.first?.id) { _, _ in
                guard !hasScrolledToToday,
                      let target = viewModel.initialScrollSectionID else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                hasScrolledToToday = true
            }
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
    ScheduleView()
}
