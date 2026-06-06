//
//  PredictionStore.swift
//  NWSLApp
//
//  Durable Predict the XI state — Home's Module 3 "Play", game 3 (per
//  Reference/Design/games-design-spec.md §"Game 3: Predict the XI"). Like
//  TriviaStore / BracketStore, this is shared app state (the user's picks + their
//  season points persist across launches and surface on more than one screen — the
//  game itself and the Home Play card), so it lives in Stores/ and is injected
//  app-wide via `.environment` in RootTabView, not owned by a single view.
//
//  Persistence is UserDefaults (the spec: "local scoring … stored locally for the
//  demo"). It holds only what must outlive a session: the user's pick per question
//  and a cached season-points snapshot so the Home card can show a total without
//  loading + scoring the whole slate. The match slate, the open/settled state, and
//  the scoring itself are NOT here — those are derived in PredictXIViewModel (the
//  store can't know "now," which decides what's locked).
//
//  Locking is enforced by the caller: a question's match locks at kickoff, which
//  only the view model can compute, so `setPick` takes a `locked` flag and refuses
//  a write once the match has kicked off (mirrors BracketStore guarding its own
//  locked rounds). `seasonPoints` is a snapshot the view model pushes after it
//  scores the settled matches — the store doesn't compute it.
//

import Foundation

@Observable
final class PredictionStore {
    /// question id → chosen option id (the user's prediction). Persisted as JSON.
    private(set) var picks: [String: String]

    /// Cached total points across all settled matches — a snapshot the view model
    /// writes after scoring, so the Home card can show it without re-scoring.
    private(set) var seasonPoints: Int

    private let defaults: UserDefaults

    private enum Key {
        static let picks = "predict.picks"
        static let seasonPoints = "predict.seasonPoints"
    }

    /// `defaults` is injectable so tests/previews use an isolated store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.picks = Self.decodePicks(defaults.data(forKey: Key.picks))
        self.seasonPoints = defaults.integer(forKey: Key.seasonPoints)
    }

    // MARK: - Derived

    /// True once any prediction has been made (drives the Home card's "Predict now"
    /// vs points copy).
    var hasPredicted: Bool { !picks.isEmpty }

    func pick(for questionID: String) -> String? { picks[questionID] }

    // MARK: - Mutation

    /// Record (or change) a prediction. `locked` is the caller's verdict on whether
    /// the question's match has kicked off; a locked match refuses the write so a
    /// settled pick can't be edited after the fact.
    func setPick(questionID: String, optionID: String, locked: Bool) {
        guard !locked else { return }
        picks[questionID] = optionID
        persist()
    }

    /// Adopt the latest scored total from the view model (called after scoring the
    /// settled matches). Kept separate from picks so the Home card reads one scalar.
    func updateSeasonPoints(_ points: Int) {
        guard points != seasonPoints else { return }
        seasonPoints = points
        persist()
    }

    /// Clear every prediction (and the cached total) — the demo's "Reset
    /// predictions" so the slate can be replayed.
    func reset() {
        picks = [:]
        seasonPoints = 0
        persist()
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(encodePicks(), forKey: Key.picks)
        defaults.set(seasonPoints, forKey: Key.seasonPoints)
    }

    private func encodePicks() -> Data? {
        try? JSONEncoder().encode(picks)
    }

    private static func decodePicks(_ data: Data?) -> [String: String] {
        guard let data, let picks = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return picks
    }
}
