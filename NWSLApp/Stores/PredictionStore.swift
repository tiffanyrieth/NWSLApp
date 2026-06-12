//
//  PredictionStore.swift
//  NWSLApp
//
//  Durable Predict the XI state — Fan Zone game 1 (0.3.9, LIVE). Like
//  TriviaStore / BracketStore, this is shared app state (the user's predictions +
//  their season points persist across launches and surface on more than one
//  screen — the game and the Home "Play" card), so it lives in Stores/ and is
//  injected app-wide via `.environment` in RootTabView, not owned by a view.
//
//  It holds two dictionaries keyed by fixtureID ("{eventID}-{teamAbbr}"): the
//  user's `XIPrediction` (draft or submitted) and, once a match has settled, the
//  `PredictionScore` the view model computed from the real lineup. `seasonPoints`
//  is derived (Σ of scored totals) and cached so the Home card reads one scalar
//  without re-scoring. The match slate, lock/deadline state, and the scoring
//  itself are NOT here — those need "now" and the network, which live in
//  PredictXIViewModel.
//
//  Persistence is UserDefaults JSON under `predict.v2.*` keys (the old card-game
//  `predict.picks`/`predict.seasonPoints` are abandoned, not migrated — demo data
//  with no real user value). Submitting is one-way: a submitted prediction refuses
//  further edits (mirrors BracketStore guarding locked rounds), so a committed
//  read can't be quietly changed after the fact.
//

import Foundation

@Observable
final class PredictionStore {
    /// fixtureID → the user's prediction (draft or submitted). Persisted as JSON.
    private(set) var predictions: [String: XIPrediction]

    /// fixtureID → the graded result, written once a settled match is scored.
    private(set) var scores: [String: PredictionScore]

    /// Cached season total (Σ of every scored prediction) — what the Home card and
    /// ProfileView read. Recomputed whenever a score is recorded.
    private(set) var seasonPoints: Int

    private let defaults: UserDefaults

    private enum Key {
        static let predictions = "predict.v2.predictions"
        static let scores = "predict.v2.scores"
        static let seasonPoints = "predict.v2.seasonPoints"
    }

    /// `defaults` is injectable so tests/previews use an isolated store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.predictions = Self.decode([String: XIPrediction].self, defaults.data(forKey: Key.predictions)) ?? [:]
        self.scores = Self.decode([String: PredictionScore].self, defaults.data(forKey: Key.scores)) ?? [:]
        self.seasonPoints = defaults.integer(forKey: Key.seasonPoints)
    }

    // MARK: - Reads

    /// True once any prediction exists (drives the Home card's "Predict now" vs
    /// points copy).
    var hasPredicted: Bool { !predictions.isEmpty }

    func prediction(for fixtureID: String) -> XIPrediction? { predictions[fixtureID] }
    func score(for fixtureID: String) -> PredictionScore? { scores[fixtureID] }

    /// Fixture ids that are submitted but not yet scored — the view model fetches
    /// `/summary` for these once their match has settled.
    var submittedAwaitingScore: [String] {
        predictions.values
            .filter { $0.state == .submitted && scores[$0.fixtureID] == nil }
            .map(\.fixtureID)
    }

    // MARK: - Mutation

    /// Save (or replace) a draft. A submitted prediction is locked — the write is
    /// refused so a committed XI can't be edited.
    func saveDraft(_ prediction: XIPrediction) {
        guard predictions[prediction.fixtureID]?.state != .submitted else { return }
        var draft = prediction
        draft.state = .draft
        predictions[prediction.fixtureID] = draft
        persist()
    }

    /// Commit a complete prediction. One-way: only a complete, not-yet-submitted
    /// prediction can be submitted, and never un-submitted.
    func submit(fixtureID: String) {
        guard var prediction = predictions[fixtureID],
              prediction.state == .draft,
              prediction.isComplete else { return }
        prediction.state = .submitted
        predictions[fixtureID] = prediction
        persist()
    }

    /// Store a computed score and refresh the cached season total.
    func recordScore(_ score: PredictionScore, for fixtureID: String) {
        scores[fixtureID] = score
        seasonPoints = scores.values.reduce(0) { $0 + $1.total }
        persist()
    }

    /// Clear everything — the "Reset predictions" replay.
    func reset() {
        predictions = [:]
        scores = [:]
        seasonPoints = 0
        persist()
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(try? JSONEncoder().encode(predictions), forKey: Key.predictions)
        defaults.set(try? JSONEncoder().encode(scores), forKey: Key.scores)
        defaults.set(seasonPoints, forKey: Key.seasonPoints)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
