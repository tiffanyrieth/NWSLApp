//
//  PredictResultViewModel.swift
//  NWSLApp
//
//  Everything the Predict the XI results screen needs: the fetched answer key, the community
//  distribution, the graded real XI, the superlative line — and the line-by-line reveal.
//  Reworked 2026-07-28 (owner review): the pitch now shows the REAL lineup marked with what you
//  called, and the community layer lives in per-band panels of ranked ownership bars.
//
//  ⚠️ THE REVEAL LIVES HERE, NOT IN THE VIEW. It's a cancellable sequence with real ordering rules,
//  which makes it logic rather than layout: keeping it in the VM means `skip` genuinely cancels,
//  and the sequence is unit-testable through the injected `sleep` seam.
//
//  ⚠️ NOTHING HERE WRITES A SCORE. `recordScore` feeds `scoredMatchCount`, the denominator of
//  `avg_points`, which is what the season board ranks on — a stray write from a results screen
//  would quietly corrupt every user's rank.
//

import SwiftUI

@Observable
@MainActor
final class PredictResultViewModel {

    enum Phase { case loading, loaded, failed }

    private(set) var phase: Phase = .loading
    private(set) var detail: PredictXIViewModel.MatchResultDetail?
    private(set) var community: PredictCommunity?
    /// The real XI in lineup order, each starter marked called/missed.
    private(set) var starters: [PredictStarterResult] = []
    /// Your picks who didn't start.
    private(set) var busts: [PredictBust] = []
    private(set) var standouts: PredictStandouts = .none
    private(set) var superlative: String?
    /// The actual formation, when ESPN's string parses — drives the pitch rows.
    private(set) var actualFormation: Formation?

    // MARK: - Band panels ("How <club> fans picked")

    /// One expandable panel per line of the real XI.
    struct BandPanel: Identifiable, Equatable {
        struct Entry: Identifiable, Equatable {
            let athleteID: String
            let name: String
            let share: Double
            /// False for a popular pick who did NOT start — the crowd's wrong call, struck through.
            let started: Bool
            let called: Bool
            var id: String { athleteID }
        }

        let group: PositionGroup
        var id: PositionGroup { group }
        /// Ownership bars, starters first (lineup order), then the crowd's wrong calls by share.
        ///
        /// ⚠️ BARS FOR EVERY LINE, goalkeeper included (owner call, 2026-07-28). A GK donut was
        /// built and cut: slot 0's shares DO sum to 100% (each fan picks exactly one keeper), so a
        /// donut was mathematically honest there — but only there, and one line rendering
        /// differently from the other three was exactly the inconsistency this screen's review
        /// removed everywhere else. Bars need no sum-to-100 property, so one format serves all.
        let entries: [Entry]
    }

    private(set) var bandPanels: [BandPanel] = []

    // MARK: - Reveal

    private(set) var revealedBands: Set<PositionGroup> = []
    private(set) var contentShown = false
    private(set) var isRevealing = false

    /// The scoring breakdown's staggered reveal (game-feel pass): how many breakdown rows have landed,
    /// and the running total that counts up as each one arrives. The view gates each row on the index and
    /// shows `runningScoreTotal` on the Total line. Reduce Motion / VoiceOver jump straight to the end.
    private(set) var revealedScoreLines = 0
    private(set) var runningScoreTotal = 0
    /// The breakdown rows' point values, in the SAME order the results view renders them, so the stagger
    /// and running total stay in lockstep with the rows. Set at load.
    private var scoreLinePoints: [Int] = []

    /// GK → attack: builds toward the front line, where the contested picks are.
    private static let bandOrder: [PositionGroup] = [.gk, .def, .mid, .fwd]

    private var revealTask: Task<Void, Never>?
    private let sleep: (Duration) async -> Void

    private let communityService = PredictCommunityService()
    private let leaderboardService: PredictLeaderboardService

    init(sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         leaderboardService: PredictLeaderboardService = PredictLeaderboardService()) {
        self.sleep = sleep
        self.leaderboardService = leaderboardService
    }

    // No `deinit` cancel: deinit is nonisolated and can't touch @MainActor state. Not needed —
    // the reveal task captures `self` weakly and the view cancels in `.onDisappear`.

    // MARK: - Load

    func load(item: PredictXIViewModel.PredictionItem,
              parent: PredictXIViewModel,
              store: PredictionStore,
              auth: AuthStore,
              reduceMotion: Bool,
              voiceOver: Bool) async {
        phase = .loading
        guard let fetched = await parent.matchResultDetail(for: item, store: store, auth: auth),
              let prediction = item.prediction,
              let actual = fetched.actual else {
            phase = .failed
            return
        }
        detail = fetched
        actualFormation = actual.formation.flatMap(Formation.init(raw:))

        // Cache the round rank so the Home carousel + recent-result cards can show "3rd this round"
        // synchronously (it's a network read here). Local, pruned with the other recent-window markers.
        if let rank = fetched.roundRank { store.recordRoundRank(rank, forFixture: item.fixture.id) }

        // Community is OPTIONAL: sealed or unreachable hides the panels, never fails the screen.
        let season = String(AppConfig.currentSeasonYear)
        if let week = item.score?.soccerWeek {
            let request = PredictCommunityRequest(eventID: prediction.eventID,
                                                  team: prediction.teamAbbreviation,
                                                  week: week)
            let map = await communityService.distribution(season: season, fixtures: [request])
            let found = map[item.fixture.id]
            community = (found?.revealed == true) ? found : nil

            #if DEBUG
            // TEMP dev-only preview scaffold — a CLIENT-SIDE distribution so the community layer
            // can be reviewed before real submissions exist. Empty means nil OR zero submissions:
            // a finished match legitimately returns revealed-with-nothing-in-it.
            if (community?.submissions ?? 0) == 0, DebugPredictSeed.isActive {
                community = DebugPredictSeed.syntheticCommunity(
                    eventID: prediction.eventID, team: prediction.teamAbbreviation, week: week,
                    picks: prediction.slots, actualStarters: actual.starters.map(\.athleteID))
            }
            #endif
        }

        starters = PredictResultDerivation.starterResults(for: prediction, against: actual,
                                                          names: fetched.names, community: community)
        busts = PredictResultDerivation.busts(for: prediction, against: actual,
                                              names: fetched.names, community: community)
        standouts = PredictResultDerivation.standouts(starters: starters)
        bandPanels = buildBandPanels(fetched: fetched)

        evaluateSuperlativeAndMergeBests(prediction: prediction, store: store, season: season)

        // The breakdown rows' points, ordered exactly as the results view renders them — feeds the
        // staggered scoring reveal + running total.
        scoreLinePoints = Self.breakdownPoints(for: item.score ?? .zero)

        phase = .loaded
        prepareReveal(reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    /// The per-band community panels. Only built with real (or debug-injected) data — with no
    /// community, `bandPanels` stays empty and the whole section hides itself.
    private func buildBandPanels(fetched: PredictXIViewModel.MatchResultDetail) -> [BandPanel] {
        guard let community, community.submissions > 0 else { return [] }

        return PositionGroup.allCases.compactMap { group in
            let bandStarters = starters.filter { $0.group == group }
            guard !bandStarters.isEmpty else { return nil }

            var entries: [BandPanel.Entry] = bandStarters.map {
                BandPanel.Entry(athleteID: $0.athleteID, name: $0.name,
                                share: $0.communityShare ?? 0, started: true, called: $0.called)
            }

            // The crowd's wrong calls: players a meaningful share backed who did NOT start in this
            // band. Band attribution for a non-starter comes from the ROSTER (she has no lineup
            // position), which is the same grouping the picker sheet uses.
            let starterIDs = Set(starters.map(\.athleteID))
            let wrongCalls = community.playersByShare
                .filter { !starterIDs.contains($0.playerID) }
                .filter { fetched.groupsByID[$0.playerID] == group }
                .filter { $0.share >= 0.15 }
                .prefix(3)
                .map { candidate in
                    BandPanel.Entry(athleteID: candidate.playerID,
                                    name: fetched.names[candidate.playerID] ?? "Player",
                                    share: candidate.share, started: false,
                                    called: busts.contains { $0.athleteID == candidate.playerID })
                }
            entries.append(contentsOf: wrongCalls)

            return BandPanel(group: group, entries: entries)
        }
    }

    /// ⚠️ ORDER IS LOAD-BEARING: evaluate the ladder against the bests as they stood BEFORE this
    /// match, and only then merge this match in — else every match is its own "season best".
    private func evaluateSuperlativeAndMergeBests(prediction: XIPrediction,
                                                  store: PredictionStore,
                                                  season: String) {
        let called = PredictResultDerivation.startersCalled(starters)
        let previousBest = store.seasonBests.hasMatchBaseline ? store.seasonBests.bestMatchStarters : nil

        // "Perfect defense" = you called every starter in that line (the ladder's own 3+ floor
        // stops a lone keeper from firing it).
        let perfectBands: [PredictSuperlative.PerfectBand] = PredictResultDerivation.bandTallies(starters)
            .filter { $0.called == $0.total }
            .map { PredictSuperlative.PerfectBand(group: $0.group, slots: $0.total) }

        // The consensus-XI comparison still feeds the ladder even though its screen section was
        // cut in the owner review — "Beat the consensus XI" is computed, not displayed data.
        var consensusStarters: Int?
        if let community, let formation = Formation(raw: prediction.formation) {
            consensusStarters = community.consensusCorrect(
                slots: formation.slots.map(\.index),
                actualStarterIDs: Set(starters.map(\.athleteID)))
        }

        superlative = PredictSuperlative.forMatch(.init(
            startersCalled: called,
            previousBestStarters: previousBest,
            consensusStarters: consensusStarters,
            perfectBands: perfectBands
        ))

        let bests = PredictSeasonBests(season: season, bestMatchStarters: called, bestRoundStarters: 0)
        store.mergeSeasonBests(bests)
        #if DEBUG
        // A seeded result must never raise the real high-water mark — GREATEST can't be undone.
        guard !DebugPredictSeed.isActive else { return }
        #endif
        let service = leaderboardService
        Task { await service.mergeSeasonBests(season: season, matchStarters: called, roundStarters: 0) }
    }

    // MARK: - Reveal control
    //
    // ⚠️ NO skip, NO replay, NO auto-play budget (owner cut, second review). The reveal is ~3
    // seconds and appears only on this screen — it simply plays every time. The first build had a
    // 3-per-season budget with a promoted Replay pill (the handoff's degradation rule for a FORCED
    // animation); at three seconds the whole apparatus was more to look at than the animation.
    // Reduce Motion and VoiceOver still land fully revealed instantly.

    private func prepareReveal(reduceMotion: Bool, voiceOver: Bool) {
        guard !reduceMotion, !voiceOver else {
            finishReveal()
            return
        }
        startReveal()
    }

    private func startReveal() {
        revealTask?.cancel()
        revealedBands = []
        contentShown = false
        isRevealing = true
        revealedScoreLines = 0
        runningScoreTotal = 0
        revealTask = Task { [weak self] in
            guard let self else { return }
            for (index, band) in Self.bandOrder.enumerated() {
                await self.sleep(.milliseconds(index == 0 ? 650 : 780))
                // ⚠️ REQUIRED: `sleep` swallows cancellation; without this a skipped reveal keeps
                // firing its remaining beats.
                if Task.isCancelled { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                    _ = self.revealedBands.insert(band)
                }
            }
            await self.sleep(.milliseconds(420))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.48)) {
                self.contentShown = true
                self.isRevealing = false
            }
            // The scoring breakdown then lands line by line, the total counting up as each arrives —
            // the continuation of the pitch reveal (game-feel pass).
            await self.staggerScoreLines()
        }
    }

    /// Reveal the breakdown rows one at a time after the content settles, adding each line's points to
    /// the running total as it lands. Cancellation-safe (checks between beats).
    private func staggerScoreLines() async {
        await sleep(.milliseconds(800))   // let the summary + rank settle before the ledger fills in
        for index in scoreLinePoints.indices {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.32)) {
                revealedScoreLines = index + 1
                runningScoreTotal += scoreLinePoints[index]
            }
            await sleep(.milliseconds(400))
        }
    }

    /// The breakdown rows' point values in render order (Correct players, Right position, Formation,
    /// Exact score, Result, then the Perfect XI bonus only when earned).
    static func breakdownPoints(for score: PredictionScore) -> [Int] {
        var points = [score.playersPoints, score.positionsPoints, score.formationPoints,
                      score.scorelinePoints, score.resultPoints]
        if score.perfectXI { points.append(score.perfectPoints) }
        return points
    }

    /// Cancel on disappear — a leaked task would go on mutating a torn-down view model.
    func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func finishReveal() {
        revealedBands = Set(PositionGroup.allCases)
        contentShown = true
        isRevealing = false
        // No stagger under Reduce Motion / VoiceOver — land on the final state.
        revealedScoreLines = scoreLinePoints.count
        runningScoreTotal = scoreLinePoints.reduce(0, +)
    }

    // MARK: - Derived reads for the view

    var startersCalled: Int { PredictResultDerivation.startersCalled(starters) }

    /// The caption above the pitch: which line is landing right now, or the finished state.
    var revealCaption: String {
        guard isRevealing else { return "The real lineup vs your picks" }
        guard let latest = Self.bandOrder.last(where: { revealedBands.contains($0) }) else {
            return "Revealing the lineup…"
        }
        switch latest {
        case .gk: return "Goalkeeper"
        case .def: return "Defense"
        case .mid: return "Midfield"
        case .fwd: return "Attack"
        }
    }
}
