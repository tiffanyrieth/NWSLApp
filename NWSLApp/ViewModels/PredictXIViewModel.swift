//
//  PredictXIViewModel.swift
//  NWSLApp
//
//  Owns one Predict the XI session — Fan Zone game 1 (0.3.9, LIVE). Same
//  idle/loading/loaded/error State shape as every other view model. The durable
//  state (predictions + scores) lives in PredictionStore; this view model owns the
//  DERIVED, time- and network-dependent slate:
//
//   • OPEN slate — each followed team's NEXT not-yet-started fixture, built from
//     the shared MatchStore + ClubStore + FollowingStore (no scoreboard re-fetch).
//     Always something to predict, even mid-break.
//   • SCORING — when a SUBMITTED prediction's match has settled, fetch its
//     `/summary`, build the `ActualResult`, run PredictionScoring, and record the
//     score (once — it's then cached in the store).
//   • Lazy ROSTER fetch for the picker, cached per team for the session.
//
//  Lock model (owner): submission closes at kickoff − 2h; only a deliberately
//  SUBMITTED prediction is ever scored (un-submitted drafts expire). "Now" decides
//  open vs closed, so it's resolved here against an injectable clock, never stored.
//

import Foundation

@Observable
final class PredictXIViewModel {
    enum State {
        case idle
        case loading
        case loaded
        case error(String)
    }

    /// One row of the slate — a fixture plus whatever the user has done with it.
    struct PredictionItem: Identifiable {
        let fixture: PredictionFixture
        let prediction: XIPrediction?
        let score: PredictionScore?
        let finalScore: (home: Int, away: Int)?
        let phase: Phase

        var id: String { fixture.id }

        enum Phase {
            case open        // editable / submittable (now < deadline)
            case closed      // deadline passed, never submitted — out for this match
            case submitted   // locked in, awaiting the result
            case scored      // settled + graded
        }
    }

    private(set) var state: State = .idle
    private(set) var upcomingFixtures: [PredictionFixture] = []

    private var eventsByID: [String: Event] = [:]
    private var clubsByAbbr: [String: Club] = [:]
    private var rostersByTeam: [String: [Athlete]] = [:]

    /// Real per-team standings fetched in `load`. One entry per active/scored team:
    /// the team's abbreviation and its ranked rows (you spliced in from your live
    /// local total). Empty until loaded.
    private(set) var leaderboards: [(team: String, rows: [LeaderboardRow])] = []

    /// The ROUND boards — one per team, for that team's most relevant soccer week (the current week
    /// once it has scores, else the latest scored week — "how did I do in Sunday's round"). The
    /// comp arena's second clock; `weekLabel` is the honest date-range label ("Jun 22–28").
    private(set) var roundBoards: [(team: String, week: Int, weekLabel: String, rows: [LeaderboardRow])] = []

    /// When the slate is EMPTY (a break week): the soonest followed-team fixture beyond the open
    /// window, so the paused state can name the reopen date. nil in-season or true offseason.
    private(set) var nextOpening: (team: String, kickoff: Date, opensAt: Date)?

    private let service: ESPNService
    private let leaderboardService: PredictLeaderboardService
    private let now: () -> Date

    /// The leaderboard season key (matches the Supabase column default). Single source of truth =
    /// `AppConfig.currentSeasonYear` (offseason-aware), so a new year advances everywhere at once.
    private static var currentSeason: String { String(AppConfig.currentSeasonYear) }

    init(service: ESPNService = ESPNService(),
         leaderboardService: PredictLeaderboardService = PredictLeaderboardService(),
         now: @escaping () -> Date = Date.init) {
        self.service = service
        self.leaderboardService = leaderboardService
        self.now = now
    }

    // MARK: - Loading

    /// Build the slate from the shared stores, then score any submitted prediction
    /// whose match has now settled. Reads live data — but a thin/empty MatchStore
    /// simply yields an empty slate (a friendly "no upcoming matches" state), never
    /// an error.
    func load(matches: MatchStore, clubs: ClubStore, following: FollowingStore,
              store: PredictionStore, auth: AuthStore) async {
        state = .loading

        clubsByAbbr = Dictionary(clubs.clubs.map { ($0.abbreviation, $0) }, uniquingKeysWith: { first, _ in first })
        eventsByID = Dictionary(matches.events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        upcomingFixtures = buildUpcoming(matches: matches, clubs: clubs, following: following)
        nextOpening = upcomingFixtures.isEmpty
            ? findNextOpening(matches: matches, clubs: clubs, following: following)
            : nil

        await scoreSettledSubmissions(store: store)
        await loadLeaderboards(store: store, auth: auth)

        // Game Center: push the (cross-team) season-points total. Best-effort,
        // no-ops when not signed in to Game Center. Additive on top of Supabase.
        await MainActor.run {
            GameCenterManager.shared.submit(store.seasonPoints, to: GameCenterID.Leaderboard.predictSeasonPoints)
        }

        state = .loaded
    }

    /// Each followed team's next match WITHIN the active window (28 days) → a
    /// PredictionFixture, soonest first. Beyond that horizon the team contributes
    /// nothing, so a long break empties the slate and the game hides (the same gate
    /// Home uses). Following both sides of a match yields two fixtures.
    private func buildUpcoming(matches: MatchStore, clubs: ClubStore, following: FollowingStore) -> [PredictionFixture] {
        let horizon = now().addingTimeInterval(PredictionFixture.activeWindow)
        var fixtures: [PredictionFixture] = []
        for id in following.followedIDs {
            guard let club = clubs.club(id: id) else { continue }
            let next = matches.matches(for: club).first { event in
                guard let kickoff = event.kickoff else { return false }
                return kickoff > now() && kickoff <= horizon
            }
            if let event = next, let fixture = fixture(from: event, yourTeam: club.abbreviation) {
                fixtures.append(fixture)
            }
        }
        return fixtures.sorted { $0.kickoff < $1.kickoff }
    }

    /// The paused-state read (an international break / deep offseason): when the slate is empty, the
    /// SOONEST followed-team fixture beyond the 28-day horizon — so the screen can say honestly when
    /// predictions reopen ("opens Jun 12" = kickoff − the active window) instead of a dead empty state.
    /// nil when there is no future fixture at all (true offseason; the Home gate hides the game).
    private func findNextOpening(matches: MatchStore, clubs: ClubStore,
                                 following: FollowingStore) -> (team: String, kickoff: Date, opensAt: Date)? {
        var soonest: (team: String, kickoff: Date, opensAt: Date)?
        for id in following.followedIDs {
            guard let club = clubs.club(id: id) else { continue }
            let next = matches.matches(for: club).first { ($0.kickoff ?? .distantPast) > now() }
            guard let kickoff = next?.kickoff else { continue }
            if kickoff < (soonest?.kickoff ?? .distantFuture) {
                soonest = (club.abbreviation, kickoff, kickoff.addingTimeInterval(-PredictionFixture.activeWindow))
            }
        }
        return soonest
    }

    /// For each submitted-but-unscored prediction whose match has finished, fetch
    /// `/summary`, build the answer key, score it, and persist. Best-effort: a
    /// failed fetch just retries on the next load.
    private func scoreSettledSubmissions(store: PredictionStore) async {
        for fixtureID in store.submittedAwaitingScore {
            guard let prediction = store.prediction(for: fixtureID),
                  let event = eventsByID[prediction.eventID],
                  isFinished(event),
                  let homeScore = event.homeCompetitor?.score.flatMap({ Int($0) }),
                  let awayScore = event.awayCompetitor?.score.flatMap({ Int($0) }) else { continue }

            let isHome = prediction.teamAbbreviation == event.homeCompetitor?.team?.abbreviation
            do {
                let summary = try await service.fetchSummary(eventID: prediction.eventID)
                if let actual = ActualResult.make(from: summary, isHome: isHome,
                                                  homeScore: homeScore, awayScore: awayScore) {
                    var score = PredictionScoring.score(prediction, against: actual)
                    // Stamp the fixture's soccer week — the round-board key (a 2-game week's
                    // fixtures share a week, so their totals sum into one round row).
                    score.soccerWeek = event.kickoff.flatMap { FanZoneCadence.soccerWeek(for: $0) }
                    store.recordScore(score, for: fixtureID)
                }
            } catch {
                // Leave it unscored; the next load tries again (proxy caches the
                // finished summary, so the retry is cheap). NOT silent — flag it so a
                // persistent scoring outage (a team's points never landing) surfaces.
                Diagnostics.shared.record(.apiFailure, "predict scoring \(fixtureID): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Slate (the view reads these against the live store)

    /// Upcoming fixtures, with the user's current prediction + phase. Sorted soonest
    /// first.
    func openItems(store: PredictionStore) -> [PredictionItem] {
        upcomingFixtures.map { fixture in
            let prediction = store.prediction(for: fixture.id)
            let phase: PredictionItem.Phase
            if prediction?.state == .submitted {
                phase = .submitted
            } else if now() < fixture.deadline {
                phase = .open
            } else {
                phase = .closed
            }
            return PredictionItem(fixture: fixture, prediction: prediction,
                                  score: nil, finalScore: nil, phase: phase)
        }
    }

    /// Scored predictions, most recently played first.
    func resultItems(store: PredictionStore) -> [PredictionItem] {
        store.scores.keys.compactMap { fixtureID -> PredictionItem? in
            guard let prediction = store.prediction(for: fixtureID),
                  let event = eventsByID[prediction.eventID],
                  let fixture = fixture(from: event, yourTeam: prediction.teamAbbreviation) else { return nil }
            let final: (home: Int, away: Int)? = {
                guard let h = event.homeCompetitor?.score.flatMap({ Int($0) }),
                      let a = event.awayCompetitor?.score.flatMap({ Int($0) }) else { return nil }
                return (h, a)
            }()
            return PredictionItem(fixture: fixture, prediction: prediction,
                                  score: store.score(for: fixtureID), finalScore: final, phase: .scored)
        }
        .sorted { $0.fixture.kickoff > $1.fixture.kickoff }
    }

    // MARK: - Roster (lazy, cached per team)

    /// The followed team's squad for the picker, fetched once per session. A failed
    /// fetch returns an empty roster (the picker shows its own retry).
    func roster(forTeam abbreviation: String) async -> [Athlete] {
        if let cached = rostersByTeam[abbreviation] { return cached }
        guard let club = clubsByAbbr[abbreviation] else { return [] }
        do {
            let squad = try await service.fetchRoster(clubID: club.id)
            rostersByTeam[abbreviation] = squad.athletes
            return squad.athletes
        } catch {
            Diagnostics.shared.record(.apiFailure, "predict roster \(abbreviation): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Mutation

    func reset(store: PredictionStore) { store.reset() }

    // MARK: - Club lookup

    func club(forAbbreviation abbreviation: String) -> Club? { clubsByAbbr[abbreviation] }

    /// Short, chip-friendly club name (falls back to the abbreviation offline).
    func teamLabel(_ abbreviation: String) -> String {
        let club = clubsByAbbr[abbreviation]
        return club?.shortName ?? club?.displayName ?? abbreviation
    }

    // MARK: - Leaderboard (REAL, per-team via Supabase — Spirit fans vs Spirit fans)

    struct LeaderboardRow: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let points: Int
        let isYou: Bool
        /// True for the "You" row shown UNDER a divider because you rank past the
        /// visible top (`rank` is then your real position, e.g. 412). The view draws
        /// the separator; a normal in-window "You" row keeps this false.
        var isBelowFold: Bool = false
    }

    /// Fetch the real per-team standings and build a board for each team the user is
    /// actively predicting (in the slate) or has scored in. Signed-in users first
    /// push their fresh per-team totals to Supabase (best-effort); then everyone
    /// reads the world-readable standings and we splice the user's LIVE local total
    /// in (fresher than any just-written row). No fabricated rivals — a sparse board
    /// (just you) early on is the honest state.
    private func loadLeaderboards(store: PredictionStore, auth: AuthStore) async {
        let season = Self.currentSeason

        if let userID = auth.userID {
            for team in store.scoredTeams {
                await leaderboardService.upsertScore(
                    teamAbbreviation: team, points: store.points(forTeam: team),
                    displayName: auth.displayName, userID: userID, season: season)
                // The round twin: push this team's week sums for the retained window (current +
                // previous — anything older is pruned server-side, so pushing it would be waste).
                if let currentWeek = FanZoneCadence.currentSoccerWeek() {
                    for week in [currentWeek - 1, currentWeek] where week >= 1 {
                        let weekPoints = store.points(forTeam: team, week: week)
                        if weekPoints > 0 {
                            await leaderboardService.upsertRoundScore(
                                teamAbbreviation: team, week: week, points: weekPoints,
                                displayName: auth.displayName, userID: userID, season: season)
                        }
                    }
                }
            }
        }

        // Boards to show: the teams you're predicting now (slate, soonest first) plus
        // any extra team you've scored in.
        var teams = upcomingFixtures.map(\.teamAbbreviation)
        for team in store.scoredTeams where !teams.contains(team) { teams.append(team) }

        var boards: [(team: String, rows: [LeaderboardRow])] = []
        var rounds: [(team: String, week: Int, weekLabel: String, rows: [LeaderboardRow])] = []
        for team in teams {
            let standings = await leaderboardService.standings(teamAbbreviation: team, season: season)
            // Only the signed-in user gets a "You" row — and only they need a rank lookup.
            var trueRank: Int?
            if auth.userID != nil {
                trueRank = await leaderboardService.rank(
                    teamAbbreviation: team, season: season, points: store.points(forTeam: team))
            }
            boards.append((team: team, rows: rankedRows(
                team: team, standings: standings, trueRank: trueRank, store: store, auth: auth,
                points: store.points(forTeam: team))))

            // The round board: the current week once it has any of MY scores, else my latest scored
            // week (the just-finished round — "did I beat them Sunday"). No round-stamped score yet →
            // no round board for this team (honest absence, not an empty fabrication).
            if let week = roundBoardWeek(team: team, store: store) {
                let weekPoints = store.points(forTeam: team, week: week)
                let roundStandings = await leaderboardService.roundStandings(
                    teamAbbreviation: team, season: season, week: week)
                var roundTrueRank: Int?
                if auth.userID != nil {
                    roundTrueRank = await leaderboardService.roundRank(
                        teamAbbreviation: team, season: season, week: week, points: weekPoints)
                }
                rounds.append((team: team, week: week, weekLabel: FanZoneCadence.weekLabel(week: week),
                               rows: rankedRows(team: team, standings: roundStandings,
                                                trueRank: roundTrueRank, store: store, auth: auth,
                                                points: weekPoints)))
            }
        }
        leaderboards = boards
        roundBoards = rounds
    }

    /// Which soccer week a team's round board shows: the current week if I have scored points in it,
    /// else my most recent scored week (retention keeps current + previous server-side, and my own
    /// weeks always include anything I can rank in). nil = nothing round-stamped yet.
    private func roundBoardWeek(team: String, store: PredictionStore) -> Int? {
        guard let latest = store.latestScoredWeek(forTeam: team) else { return nil }
        return latest
    }

    /// Build a team's display board: the fetched top-`visibleLimit` rivals with the
    /// signed-in user spliced in at their TRUE position — inline when they're within
    /// the window, or as a below-fold "You" row (honest real rank) when they aren't.
    /// The user's own server row is dropped; we show their fresher local total instead.
    private func rankedRows(team: String, standings: [PredictLeaderboardService.Standing],
                            trueRank: Int?, store: PredictionStore, auth: AuthStore,
                            points: Int) -> [LeaderboardRow] {
        let myID = auth.userID?.uuidString
        let myName = auth.displayName ?? "You"
        let myPoints = points   // season total OR one week's sum — the caller picks the clock
        let rivals = standings.filter { $0.userID != myID }

        switch LeaderboardRanking.placement(trueRank: trueRank, cappedRivalCount: rivals.count) {
        case .none:
            // Signed out: just the top rivals, no "You" row.
            return rivals.enumerated().map {
                LeaderboardRow(rank: $0 + 1, name: $1.name, points: $1.points, isYou: false)
            }
        case .inline(let slot):
            // Insert "You" at your slot, then number sequentially and cap to the window.
            var names = rivals.map { (name: $0.name, points: $0.points, isYou: false) }
            names.insert((name: myName, points: myPoints, isYou: true), at: min(slot, names.count))
            return names.prefix(LeaderboardRanking.visibleLimit).enumerated().map {
                LeaderboardRow(rank: $0 + 1, name: $1.name, points: $1.points, isYou: $1.isYou)
            }
        case .belowFold(let realRank):
            // Top of the board, then a separated "You" row at your real rank.
            var rows = rivals.prefix(LeaderboardRanking.visibleLimit).enumerated().map {
                LeaderboardRow(rank: $0 + 1, name: $1.name, points: $1.points, isYou: false)
            }
            rows.append(LeaderboardRow(rank: realRank, name: myName, points: myPoints,
                                       isYou: true, isBelowFold: true))
            return rows
        }
    }

    // MARK: - Helpers

    /// Build a fixture for the given side of an event (nil if the team isn't in it
    /// or the kickoff/abbreviations are missing).
    private func fixture(from event: Event, yourTeam abbreviation: String) -> PredictionFixture? {
        guard let kickoff = event.kickoff,
              let home = event.homeCompetitor?.team?.abbreviation,
              let away = event.awayCompetitor?.team?.abbreviation,
              home == abbreviation || away == abbreviation else { return nil }
        let isHome = home == abbreviation
        return PredictionFixture(
            eventID: event.id,
            teamAbbreviation: abbreviation,
            opponentAbbreviation: isHome ? away : home,
            isHome: isHome,
            kickoff: kickoff
        )
    }

    /// A match is scoreable once ESPN marks it final (or, defensively, kickoff is
    /// well past and a score is present).
    private func isFinished(_ event: Event) -> Bool {
        if event.statusState == "post" { return true }
        if let kickoff = event.kickoff { return kickoff < now().addingTimeInterval(-3 * 3600) }
        return false
    }
}
