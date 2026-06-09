//
//  TeamsViewModel.swift
//  NWSLApp
//
//  Owns state for TeamsView (and reused by OnboardingView): exposes the league's
//  club directory. The directory itself now lives in the shared ClubStore
//  (injected app-wide — one fetch, many readers; see CLAUDE.md What's-Next #15),
//  so this view model is a thin reader over it. The view's existing
//  idle/loading/loaded/error switch and `clubs` accessor are unchanged — they now
//  proxy the store.
//

import Foundation

@Observable
final class TeamsViewModel {
    // Handed in by the view from the environment before the first load (a SwiftUI
    // `@State` view model can't read the environment at init). Until it's wired,
    // the screen reads as `.idle`.
    var clubStore: ClubStore?

    /// Proxy the shared store's state so the view's switch over
    /// idle/loading/loaded/error is unchanged.
    var state: ClubStore.State { clubStore?.state ?? .idle }

    /// The loaded clubs (empty unless the store is `.loaded`).
    var clubs: [Club] { clubStore?.clubs ?? [] }

    func load() async {
        await clubStore?.load()
    }
}
