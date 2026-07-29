//
//  PredictResultViewModel.swift
//  NWSLApp
//
//  Everything the Predict the XI results screen needs: the fetched answer key, the community
//  distribution, the graded real XI, the superlative line — and the line-by-line reveal.
//  Reworked 2026-07-28 (owner review): the pitch now shows the REAL lineup marked with what you
//  called, and the community layer lives in per-band panels (GK donut + ownership bars).
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
        let entries: [Entry]
        /// Goalkeeper only: the true parts-of-a-whole split at slot 0 (every fan picks exactly one
        /// keeper, so shares sum to ~100%). nil for outfield bands, where a donut would lie —
        /// each fan picks 2–3 per line, so ownership doesn't sum to 100.
        let donut: [DonutSegment]?

        struct DonutSegment: Identifiable, Equatable {
            let athleteID: String?   // nil = the "others" remainder
            let name: String
            let share: Double
            var id: String { athleteID ?? "others" }
        }
    }

    private(set) var bandPanels: [BandPanel] = []

    // MARK: - Reveal

    private(set) var revealedBands: Set<PositionGroup> = []
    private(set) var contentShown = false
    private(set) var isRevealing = false
    private(set) var revealIsOptIn = false

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

        phase = .loaded
        prepareReveal(store: store, reduceMotion: reduceMotion, voiceOver: voiceOver)
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

            return BandPanel(group: group, entries: entries,
                             donut: group == .gk ? goalkeeperDonut(fetched: fetched) : nil)
        }
    }

    /// Slot 0's split as donut segments: top keepers by count + one "Other picks" remainder so the
    /// arcs always close to 100% even on partial data.
    private func goalkeeperDonut(fetched: PredictXIViewModel.MatchResultDetail) -> [BandPanel.DonutSegment]? {
        guard let community, community.submissions > 0 else { return nil }
        let slotCounts = community.countsForSlot(0)
        guard !slotCounts.isEmpty else { return nil }

        var segments: [BandPanel.DonutSegment] = slotCounts.prefix(4).map {
            BandPanel.DonutSegment(athleteID: $0.playerID,
                                   name: fetched.names[$0.playerID] ?? "Player",
                                   share: Double($0.count) / Double(community.submissions))
        }
        let counted = slotCounts.prefix(4).reduce(0) { $0 + $1.count }
        let remainder = community.submissions - counted
        if remainder > 0 {
            segments.append(BandPanel.DonutSegment(
                athleteID: nil, name: "Other picks",
                share: Double(remainder) / Double(community.submissions)))
        }
        return segments
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

    private func prepareReveal(store: PredictionStore, reduceMotion: Bool, voiceOver: Bool) {
        guard !reduceMotion, !voiceOver else {
            revealIsOptIn = true
            finishReveal()
            return
        }
        guard store.shouldAutoPlayReveal() else {
            revealIsOptIn = true
            finishReveal()
            return
        }
        store.noteRevealAutoPlayed()
        startReveal()
    }

    func startReveal() {
        revealTask?.cancel()
        revealedBands = []
        contentShown = false
        isRevealing = true
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
        }
    }

    func skipReveal() {
        revealTask?.cancel()
        revealTask = nil
        withAnimation(.easeInOut(duration: 0.2)) { finishReveal() }
    }

    func replayReveal() { startReveal() }

    /// Cancel on disappear — a leaked task would go on mutating a torn-down view model.
    func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func finishReveal() {
        revealedBands = Set(PositionGroup.allCases)
        contentShown = true
        isRevealing = false
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
