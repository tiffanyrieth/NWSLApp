//
//  PredictResultViewModel.swift
//  NWSLApp
//
//  Everything the redesigned Predict the XI results screen needs: the fetched answer key, the
//  community distribution, the per-pick derivation, the superlative line — and the line-by-line
//  reveal (2026-07-28).
//
//  ⚠️ THE REVEAL LIVES HERE, NOT IN THE VIEW. It's a cancellable sequence with real ordering rules,
//  which makes it logic rather than layout: keeping it in the VM means `skip` genuinely cancels
//  (rather than racing a timer that fires anyway and re-hides a line the user already skipped to),
//  and it means the sequence is unit-testable through the injected `sleep` seam without a UI test.
//
//  ⚠️ NOTHING HERE WRITES A SCORE. The screen renders a match that is already scored and persisted;
//  it recomputes only PRESENTATION detail. That boundary matters more than it looks: `recordScore`
//  feeds `scoredMatchCount`, which is the denominator of `avg_points`, which is what the season
//  board ranks on — so a stray write from a results screen would quietly corrupt every user's rank.
//

import SwiftUI

@Observable
@MainActor
final class PredictResultViewModel {

    enum Phase { case loading, loaded, failed }

    private(set) var phase: Phase = .loading
    private(set) var detail: PredictXIViewModel.MatchResultDetail?
    private(set) var community: PredictCommunity?
    private(set) var picks: [PredictPickResult] = []
    private(set) var missed: [PredictMissedStarter] = []
    private(set) var standouts: PredictStandouts = .none
    private(set) var superlative: String?
    private(set) var consensusXI: [Int: String] = [:]
    private(set) var consensusCorrect: Int?

    // MARK: - Reveal

    /// Bands revealed so far. The pitch reads this; everything below the pitch waits for
    /// `contentShown`.
    private(set) var revealedBands: Set<PositionGroup> = []
    private(set) var contentShown = false
    /// True while a reveal is actually running — drives "Skip" vs "Replay" in the caption row.
    private(set) var isRevealing = false
    /// True when auto-play was suppressed, so Replay is promoted from a quiet link to a pill.
    private(set) var revealIsOptIn = false

    /// GK → attack. Dramatic on purpose: it builds toward the front line, where the contested picks
    /// are. Always four beats, even on a five-row formation — two "Midfield" beats would make the
    /// caption lie about which line is appearing.
    private static let bandOrder: [PositionGroup] = [.gk, .def, .mid, .fwd]

    private var revealTask: Task<Void, Never>?
    /// Injectable so tests step the sequence without waiting on a real clock.
    private let sleep: (Duration) async -> Void

    private let communityService = PredictCommunityService()
    private let leaderboardService: PredictLeaderboardService

    init(sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         leaderboardService: PredictLeaderboardService = PredictLeaderboardService()) {
        self.sleep = sleep
        self.leaderboardService = leaderboardService
    }

    // No `deinit { revealTask?.cancel() }`: deinit is nonisolated and can't touch @MainActor state.
    // It isn't needed either — the reveal task captures `self` WEAKLY, so it can't keep this object
    // alive, and the view cancels explicitly in `.onDisappear`.

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

        // Community is OPTIONAL: a sealed or unreachable distribution hides the percentage-driven
        // sections rather than failing the screen, so the result itself always renders.
        let season = String(AppConfig.currentSeasonYear)
        if let week = item.score?.soccerWeek {
            let request = PredictCommunityRequest(eventID: prediction.eventID,
                                                  team: prediction.teamAbbreviation,
                                                  week: week)
            let map = await communityService.distribution(season: season, fixtures: [request])
            let found = map[item.fixture.id]
            community = (found?.revealed == true) ? found : nil
        }

        picks = PredictResultDerivation.picks(for: prediction, against: actual,
                                              names: fetched.names, community: community)
        missed = PredictResultDerivation.missedStarters(for: prediction, against: actual,
                                                        names: fetched.names, community: community)
        standouts = PredictResultDerivation.standouts(picks: picks, missed: missed)

        if let community, let formation = Formation(raw: prediction.formation) {
            let slots = formation.slots.map(\.index)
            consensusXI = community.consensusXI(slots: slots)
            consensusCorrect = community.consensusCorrect(slots: slots,
                                                          actualStarterIDs: actual.starterIDs)
        }

        evaluateSuperlativeAndMergeBests(item: item, store: store, season: season)

        phase = .loaded
        prepareReveal(store: store, reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    /// ⚠️ ORDER IS LOAD-BEARING: the ladder is evaluated against the bests as they stood BEFORE this
    /// match, and only then is this match merged in. Merging first would make every result its own
    /// "best match of the season" and the praise would mean nothing on the day it's real.
    private func evaluateSuperlativeAndMergeBests(item: PredictXIViewModel.PredictionItem,
                                                 store: PredictionStore,
                                                 season: String) {
        let starters = PredictResultDerivation.startersCalled(picks)
        let previousBest = store.seasonBests.hasMatchBaseline ? store.seasonBests.bestMatchStarters : nil

        let perfectBands: [PredictSuperlative.PerfectBand] = PositionGroup.allCases.compactMap { group in
            let inBand = picks.filter { $0.slot.group == group }
            guard !inBand.isEmpty else { return nil }
            let allPerfect = inBand.allSatisfy { $0.state == .startedInBand }
            return allPerfect ? PredictSuperlative.PerfectBand(group: group, slots: inBand.count) : nil
        }

        var percentile: Double?
        if let rank = detail?.roundRank, let total = detail?.roundTotal, total > 1 {
            percentile = Double(total - rank) / Double(total) * 100
        }

        superlative = PredictSuperlative.forMatch(.init(
            startersCalled: starters,
            previousBestStarters: previousBest,
            consensusStarters: consensusCorrect,
            perfectBands: perfectBands,
            roundPercentile: percentile,
            clubName: detail?.clubName
        ))

        // Now raise the mark, locally and (best-effort) on the server.
        let bests = PredictSeasonBests(season: season, bestMatchStarters: starters, bestRoundStarters: 0)
        store.mergeSeasonBests(bests)
        let service = leaderboardService
        Task { await service.mergeSeasonBests(season: season, matchStarters: starters, roundStarters: 0) }
    }

    // MARK: - Reveal control

    private func prepareReveal(store: PredictionStore, reduceMotion: Bool, voiceOver: Bool) {
        // Reduce Motion and VoiceOver both land fully revealed. A staged reveal fights the rotor,
        // and a user who asked the system for less motion has already answered this question.
        guard !reduceMotion, !voiceOver else {
            revealIsOptIn = true
            finishReveal()
            return
        }
        guard store.shouldAutoPlayReveal() else {
            // Seen enough this season — land on the finished state and make Replay obvious.
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
                // ⚠️ REQUIRED: `sleep` swallows cancellation, so without this a skipped reveal would
                // keep firing its remaining beats and re-animate lines the user already skipped past.
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

    /// Cancel on disappear — a leaked task would go on mutating a view model whose screen is gone.
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

    var startersCalled: Int { PredictResultDerivation.startersCalled(picks) }
    var bandTallies: [(group: PositionGroup, started: Int, total: Int)] {
        PredictResultDerivation.bandTallies(picks)
    }

    /// The caption above the pitch: which line is landing right now, or the finished state.
    var revealCaption: String {
        guard isRevealing else { return "Your XI vs the real lineup" }
        guard let latest = Self.bandOrder.last(where: { revealedBands.contains($0) }) else {
            return "Revealing your XI…"
        }
        switch latest {
        case .gk: return "Goalkeeper"
        case .def: return "Defense"
        case .mid: return "Midfield"
        case .fwd: return "Attack"
        }
    }
}
