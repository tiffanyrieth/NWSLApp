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

    /// Per-team leaderboard-rank baseline for the season card's "↑ N since last match" movement. Keyed by
    /// team abbr → the rank + the scored-match count AT that snapshot. The delta only advances when a NEW
    /// match has scored (scoredCount grew), so viewing the landing repeatedly never zeroes the movement —
    /// it reflects the LAST scored match and persists until the next. Local (the rank is server-derived,
    /// but "did my rank move" is a per-device read); a reinstall simply starts a fresh baseline.
    struct RankSnapshot: Codable, Equatable { let rank: Int; let scoredCount: Int }
    private(set) var rankSnapshotByTeam: [String: RankSnapshot]
    /// team → the rank delta from the most recent scored match (positive = climbed). Persisted so the card
    /// shows it durably between the match scoring and the next.
    private(set) var rankDeltaByTeam: [String: Int]

    /// Fixture ids whose result screen the user has actually seen — drives the "show a fresh result
    /// once, then it's history" routing (results redesign, 2026-07-28).
    ///
    /// ⚠️ PER FIXTURE, never per user and never per club. A single "last results seen" flag would
    /// mark all three of a weekend's results seen the moment the user opened one of them, and the
    /// other two reveals would be lost permanently.
    ///
    /// Local-only on purpose: it affects nothing ranked and nothing another user sees, so a server
    /// column per user per match would be storage with no reader. A reinstalled user re-watching one
    /// reveal is a non-event — the same accepted trade-off `BracketStore.lastResultsSeenRound` makes.
    private(set) var seenResultFixtureIDs: Set<String>

    /// Fixture ids whose picks have been counted into the community aggregate. A local fast-path
    /// only: the server's `(user_id, event_id)` mark is the real dedupe, so a wrong value here can
    /// cause at most a redundant no-op call, never a double count.
    private(set) var uploadedPickFixtureIDs: Set<String>

    /// Personal bests, season-scoped so a new March resets them.
    private(set) var seasonBests: PredictSeasonBests

    private let defaults: UserDefaults

    private enum Key {
        static let predictions = "predict.v2.predictions"
        static let scores = "predict.v2.scores"
        static let seasonPoints = "predict.v2.seasonPoints"
        static let rankSnapshots = "predict.v2.rankSnapshots"
        static let rankDeltas = "predict.v2.rankDeltas"
        static let seenResults = "predict.v2.seenResults"
        static let uploadedPicks = "predict.v2.uploadedPicks"
        static let seasonBests = "predict.v2.seasonBests"
    }

    /// `defaults` is injectable so tests/previews use an isolated store.
    init(defaults: UserDefaults = .standard, season: String = String(AppConfig.currentSeasonYear)) {
        self.defaults = defaults
        self.predictions = Self.decode([String: XIPrediction].self, defaults.data(forKey: Key.predictions)) ?? [:]
        self.scores = Self.decode([String: PredictionScore].self, defaults.data(forKey: Key.scores)) ?? [:]
        self.seasonPoints = defaults.integer(forKey: Key.seasonPoints)
        self.rankSnapshotByTeam = Self.decode([String: RankSnapshot].self, defaults.data(forKey: Key.rankSnapshots)) ?? [:]
        self.rankDeltaByTeam = Self.decode([String: Int].self, defaults.data(forKey: Key.rankDeltas)) ?? [:]
        self.seenResultFixtureIDs = Self.decode(Set<String>.self, defaults.data(forKey: Key.seenResults)) ?? []
        self.uploadedPickFixtureIDs = Self.decode(Set<String>.self, defaults.data(forKey: Key.uploadedPicks)) ?? []
        let storedBests = Self.decode(PredictSeasonBests.self, defaults.data(forKey: Key.seasonBests))
        self.seasonBests = storedBests?.season == season
            ? (storedBests ?? .empty(season: season))
            : .empty(season: season)
    }

    // MARK: - Reads

    /// True once any prediction exists (drives the Home card's "Predict now" vs
    /// points copy).
    var hasPredicted: Bool { !predictions.isEmpty }

    func prediction(for fixtureID: String) -> XIPrediction? { predictions[fixtureID] }
    func score(for fixtureID: String) -> PredictionScore? { scores[fixtureID] }

    /// Season points for ONE team — Σ of scored totals for fixtures of that team.
    /// The leaderboard is per-team (you're ranked among fans of YOUR club), so this
    /// breaks `seasonPoints` down by team. The fixtureID encodes the team, but we
    /// join through the persisted prediction's `teamAbbreviation` (the authoritative
    /// source) since predictions survive scoring (only `reset()` clears them).
    func points(forTeam abbreviation: String) -> Int {
        scores.reduce(0) { sum, entry in
            predictions[entry.key]?.teamAbbreviation == abbreviation ? sum + entry.value.total : sum
        }
    }

    /// How many of a team's predictions have been SCORED (a settled match graded). Drives the season
    /// card's accuracy denominator + the rank-movement "a new match scored" trigger.
    func scoredMatchCount(forTeam abbreviation: String) -> Int {
        scores.keys.reduce(0) { count, key in
            predictions[key]?.teamAbbreviation == abbreviation ? count + 1 : count
        }
    }

    /// Season lineup accuracy for ONE team, 0…1 — Σ correct XI players / (11 × scored matches). `nil`
    /// until at least one of that team's predictions has been scored (honest "no accuracy yet", never 0%
    /// faked). The Superfan economy uses the same numerator/denominator across all a user's teams; this is
    /// the per-club slice the season card shows.
    func accuracy(forTeam abbreviation: String) -> Double? {
        var correct = 0, matches = 0
        for (key, score) in scores where predictions[key]?.teamAbbreviation == abbreviation {
            correct += score.correctPlayers
            matches += 1
        }
        guard matches > 0 else { return nil }
        return Double(correct) / Double(matches * 11)
    }

    /// The rank movement to show for a team (positive = climbed, negative = dropped) — the change caused by
    /// the most recent scored match, or `nil` before there's a prior baseline. Read by the season card.
    func rankMovement(forTeam abbreviation: String) -> Int? { rankDeltaByTeam[abbreviation] }

    /// Record the team's CURRENT server rank (the view passes it after the board loads). The movement delta
    /// only advances when a NEW match has scored since the last snapshot — so repeated views don't zero it,
    /// and it reflects the last match until the next one lands. No baseline until ≥1 match has scored
    /// (movement is meaningless before the user is on the board with a real result).
    func recordRankSnapshot(team abbreviation: String, currentRank: Int) {
        let scored = scoredMatchCount(forTeam: abbreviation)
        guard scored >= 1 else { return }
        if let snap = rankSnapshotByTeam[abbreviation] {
            guard scored > snap.scoredCount else { return }   // no new match → keep the existing delta
            rankDeltaByTeam[abbreviation] = snap.rank - currentRank
            rankSnapshotByTeam[abbreviation] = RankSnapshot(rank: currentRank, scoredCount: scored)
        } else {
            rankSnapshotByTeam[abbreviation] = RankSnapshot(rank: currentRank, scoredCount: scored)
        }
        persist()
    }

    /// Distinct teams the user has earned scored points in — drives which per-team
    /// rows get pushed to Supabase.
    var scoredTeams: Set<String> {
        Set(scores.keys.compactMap { predictions[$0]?.teamAbbreviation })
    }

    /// Points earned for `team` in one soccer week — the ROUND-board value (a two-game week sums
    /// both fixtures, the owner rule). Pre-round-clock scores (nil soccerWeek) don't contribute.
    func points(forTeam abbreviation: String, week: Int) -> Int {
        scores.reduce(0) { sum, entry in
            guard predictions[entry.key]?.teamAbbreviation == abbreviation,
                  entry.value.soccerWeek == week else { return sum }
            return sum + entry.value.total
        }
    }

    /// The most recent soccer week with scored points for `team` (nil = no round-stamped score yet) —
    /// which round the "This round" board should show once the current week has no scores.
    func latestScoredWeek(forTeam abbreviation: String) -> Int? {
        scores.compactMap { entry -> Int? in
            guard predictions[entry.key]?.teamAbbreviation == abbreviation else { return nil }
            return entry.value.soccerWeek
        }.max()
    }

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
    ///
    /// ⚠️ THE DEADLINE IS CHECKED HERE, not only in the view (logic gate #3: gate the ACTION).
    /// It used to live in `XIPickerView`'s button, which meant a picker left open across the
    /// deadline could still commit — and once a lineup is public, a "prediction" is a lookup. Now
    /// every caller shares one gate, and the return value tells the caller whether it actually
    /// happened so a UI can't celebrate a commit that was refused.
    @discardableResult
    func submit(fixtureID: String, before deadline: Date, now: Date = Date()) -> Bool {
        guard now < deadline else { return false }
        guard var prediction = predictions[fixtureID],
              prediction.state == .draft,
              prediction.isComplete else { return false }
        prediction.state = .submitted
        predictions[fixtureID] = prediction
        persist()
        return true
    }

    // MARK: - Results seen / reveal / uploads (results redesign)

    func hasSeenResult(fixtureID: String) -> Bool { seenResultFixtureIDs.contains(fixtureID) }

    /// Monotonic by construction — an insert-only set, so a result can never become unseen and a
    /// reveal can never re-fire for a match the user already watched.
    func markResultSeen(fixtureID: String) {
        guard !seenResultFixtureIDs.contains(fixtureID) else { return }
        seenResultFixtureIDs.insert(fixtureID)
        persist()
    }

    /// Scored fixtures whose result the user hasn't opened yet, inside the same current+previous
    /// soccer-week window the results list renders. Home reads this to decide whether the Predict
    /// card should lead with "Match final".
    ///
    /// ⚠️ The card is a SIGNPOST, not a trigger. It routes into Predict, where the reveal plays
    /// because the result is unseen — the same code path, no second mechanism. A reveal must never
    /// fire on entering Home or the Fan Zone: someone opening the Fan Zone to play The Bracket
    /// should not be shown a Predict animation.
    func unseenScoredFixtureIDs(currentWeek: Int?) -> [String] {
        scores.compactMap { key, score in
            guard !seenResultFixtureIDs.contains(key), predictions[key] != nil else { return nil }
            if let currentWeek, let week = score.soccerWeek, week < currentWeek - 1 { return nil }
            return key
        }
    }

    func hasUploadedPicks(fixtureID: String) -> Bool { uploadedPickFixtureIDs.contains(fixtureID) }

    func markPicksUploaded(fixtureID: String) {
        guard !uploadedPickFixtureIDs.contains(fixtureID) else { return }
        uploadedPickFixtureIDs.insert(fixtureID)
        persist()
    }

    /// Raise the season's personal bests. Monotonic (`max`), mirroring the SQL `GREATEST` so a
    /// stale device can never lower one.
    func mergeSeasonBests(_ incoming: PredictSeasonBests) {
        let merged = seasonBests.merged(with: incoming)
        guard merged != seasonBests else { return }
        seasonBests = merged
        persist()
    }

    /// Drop seen/upload markers for fixtures the app can no longer render anyway. `resultItems` is
    /// windowed to the current + previous soccer week, so a marker older than that has no reader —
    /// this is the local twin of the 28-day pg_cron sweep, and it keeps both sets bounded rather
    /// than growing for every match ever played.
    func pruneStaleMarkers(currentWeek: Int?) {
        guard let currentWeek else { return }
        let live = Set(scores.compactMap { entry -> String? in
            guard let week = entry.value.soccerWeek else { return entry.key }  // unknowable → keep
            return week >= currentWeek - 1 ? entry.key : nil
        })
        // Keep markers for anything not yet scored too — an open fixture's upload marker matters.
        let keep = live.union(predictions.keys.filter { scores[$0] == nil })
        let seen = seenResultFixtureIDs.intersection(keep)
        let uploaded = uploadedPickFixtureIDs.intersection(keep)
        guard seen != seenResultFixtureIDs || uploaded != uploadedPickFixtureIDs else { return }
        seenResultFixtureIDs = seen
        uploadedPickFixtureIDs = uploaded
        persist()
    }

    /// Store a computed score and refresh the cached season total.
    func recordScore(_ score: PredictionScore, for fixtureID: String) {
        scores[fixtureID] = score
        seasonPoints = scores.values.reduce(0) { $0 + $1.total }
        persist()
    }

    /// Clear all local prediction state. Retained as a store capability (an account-delete teardown
    /// would want it), but it is deliberately NOT wired to any UI: the "Reset predictions" button that
    /// used to call this shipped ungated from #47, wiped history on one tap with no confirmation, and
    /// left the server's `prediction_scores` intact — so the season card claimed the user wasn't on the
    /// board while the leaderboard below still ranked them. Removed 2026-07-27; don't re-add a UI entry
    /// point without a confirmation AND a matching server-side reset.
    func reset() {
        predictions = [:]
        scores = [:]
        seasonPoints = 0
        rankSnapshotByTeam = [:]
        rankDeltaByTeam = [:]
        seenResultFixtureIDs = []
        uploadedPickFixtureIDs = []
        seasonBests = .empty(season: seasonBests.season)
        persist()
    }

    // MARK: - Helpers

    private func persist() {
        defaults.set(try? JSONEncoder().encode(predictions), forKey: Key.predictions)
        defaults.set(try? JSONEncoder().encode(scores), forKey: Key.scores)
        defaults.set(seasonPoints, forKey: Key.seasonPoints)
        defaults.set(try? JSONEncoder().encode(rankSnapshotByTeam), forKey: Key.rankSnapshots)
        defaults.set(try? JSONEncoder().encode(rankDeltaByTeam), forKey: Key.rankDeltas)
        defaults.set(try? JSONEncoder().encode(seenResultFixtureIDs), forKey: Key.seenResults)
        defaults.set(try? JSONEncoder().encode(uploadedPickFixtureIDs), forKey: Key.uploadedPicks)
        defaults.set(try? JSONEncoder().encode(seasonBests), forKey: Key.seasonBests)
    }

    /// Wipe all local Predict-the-XI progress on account deletion — resets the
    /// in-memory @Observable state AND persistence. The server per-team leaderboard
    /// rows are removed by the account-delete cascade; this clears the on-device cache
    /// so "delete account" truly forgets you.
    func resetForAccountDeletion() {
        predictions = [:]
        scores = [:]
        seasonPoints = 0
        rankSnapshotByTeam = [:]
        rankDeltaByTeam = [:]
        seenResultFixtureIDs = []
        uploadedPickFixtureIDs = []
        seasonBests = .empty(season: seasonBests.season)
        persist()
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    #if DEBUG
    /// Dev-only: drop one fixture's prediction + score entirely. Exists so the preview scaffold can
    /// clean up after itself — a seeded score left in the store would be pushed to the real
    /// leaderboard on the next NORMAL launch, and those rows are max-merged, so it could never be
    /// taken back down.
    func debugRemove(fixtureID: String) {
        guard predictions[fixtureID] != nil || scores[fixtureID] != nil else { return }
        predictions[fixtureID] = nil
        scores[fixtureID] = nil
        seenResultFixtureIDs.remove(fixtureID)
        uploadedPickFixtureIDs.remove(fixtureID)
        seasonPoints = scores.values.reduce(0) { $0 + $1.total }
        persist()
    }

    /// Dev-only: wipe Predict-the-XI progress (drafts, scores, banked season points)
    /// so `-resetOnboarding` simulates a brand-new install (see NWSLAppApp.init).
    /// Static + key-name-aware so it runs before any store instance exists.
    /// Local-only: the server per-team leaderboard rows are untouched and nothing
    /// syncs them back down, so the wipe sticks.
    ///
    /// Writes cleared SENTINELS rather than `removeObject` (see the note in
    /// FollowingStore.debugResetState — deletions don't reliably propagate against
    /// cfprefsd's snapshot at App.init in the Simulator; explicit writes do). The
    /// JSON-backed keys get an empty `Data()`, which `decode`'s `try?` falls back to
    /// `[:]` on — same fresh state as an absent key.
    static func debugResetState(defaults: UserDefaults = .standard) {
        defaults.set(Data(), forKey: Key.predictions)
        defaults.set(Data(), forKey: Key.scores)
        defaults.set(0, forKey: Key.seasonPoints)
        defaults.set(Data(), forKey: Key.rankSnapshots)
        defaults.set(Data(), forKey: Key.rankDeltas)
        defaults.set(Data(), forKey: Key.seenResults)
        defaults.set(Data(), forKey: Key.uploadedPicks)
        defaults.set(Data(), forKey: Key.seasonBests)
    }
    #endif
}
