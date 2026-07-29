//
//  DebugPredictSeed.swift
//  NWSLApp
//
//  TEMP — DEV-ONLY PREVIEW SCAFFOLD. Added 2026-07-28 so the redesigned Predict results screen can be
//  reviewed without waiting for a match you predicted to finish. Whole file is `#if DEBUG`; it is
//  compiled out of Release entirely.
//
//  WHY IT EXISTS: the results screen needs a SUBMITTED prediction on a SETTLED match. In normal use
//  that's a multi-day loop — submit, wait for kickoff, wait for full time — which is a terrible way
//  to iterate on a design. Launch with `-debugPredictResult` and it seeds one against the most recent
//  finished fixture of a followed club.
//
//  WHAT'S REAL vs SYNTHETIC (this matters when judging what you see):
//   • REAL — the match, the club, the final score, and the ACTUAL starting XI, fetched live from
//     `/summary` through the ordinary path. The pitch, the derivation and the breakdown all run on
//     genuine data, so what renders is what a real result renders.
//   • SYNTHETIC — your "prediction". It's built FROM the real XI with deliberate errors planted, so
//     all three node states appear: two players swapped across bands (amber), one starter replaced by
//     a bench player (red, plus a missed starter), and a scoreline that's wrong but the right result
//     so the "Right result" partial shows.
//   • SYNTHETIC — the community distribution, injected CLIENT-SIDE only. Nothing is written to
//     `predict_pick_counts`; the real aggregate stays clean. Without this the community layer would
//     correctly hide itself at zero submissions and there'd be nothing to review.
//
//  ⚠️ IT MUST NEVER TOUCH THE SERVER. A seeded score is fake, and `prediction_scores` /
//  `predict_season_bests` are max-merged — a fake value pushed once would raise the real row and
//  could never be lowered again. So `isActive` also gates OFF every Predict server write (see the
//  guards in PredictXIViewModel.loadLeaderboards and PredictResultViewModel). Local state only.
//
//  TO REMOVE: delete this file and the four `DebugPredictSeed` references it names above.
//

#if DEBUG
import Foundation

enum DebugPredictSeed {

    /// True when the app was launched with `-debugPredictResult`.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-debugPredictResult")
    }

    private static let seededKey = "predict.debug.seededFixtures"

    /// ⚠️ THE FOOTGUN THIS CLOSES. A seeded score lives in UserDefaults like any other, so the next
    /// launch WITHOUT the flag would treat it as genuine and `loadLeaderboards` would push it to
    /// `prediction_scores` — a max-merged table, so a fake total could never be lowered again.
    /// Every normal launch therefore purges whatever the scaffold left behind, BEFORE any push.
    static func purgeIfInactive(store: PredictionStore) {
        guard !isActive else { return }
        let seeded = UserDefaults.standard.stringArray(forKey: seededKey) ?? []
        guard !seeded.isEmpty else { return }
        for fixtureID in seeded { store.debugRemove(fixtureID: fixtureID) }
        UserDefaults.standard.removeObject(forKey: seededKey)
    }

    private static func remember(_ fixtureID: String) {
        var seeded = UserDefaults.standard.stringArray(forKey: seededKey) ?? []
        guard !seeded.contains(fixtureID) else { return }
        seeded.append(fixtureID)
        UserDefaults.standard.set(seeded, forKey: seededKey)
    }

    /// Seed a submitted + scored prediction for the most recent finished fixture among `events`.
    /// No-op when inactive, when nothing has finished, or when that fixture already has a prediction
    /// (so re-launching doesn't churn it and the reveal state stays reviewable).
    static func seed(events: [Event],
                     teams: Set<String>,
                     fetchSummary: (String) async throws -> MatchSummary,
                     store: PredictionStore) async {
        guard isActive else { return }

        // Most recent finished fixture involving a followed club.
        let candidates = events.compactMap { event -> (event: Event, team: String, kickoff: Date)? in
            guard event.status?.type?.state == "post", let kickoff = event.kickoff else { return nil }
            let home = event.homeCompetitor?.team?.abbreviation
            let away = event.awayCompetitor?.team?.abbreviation
            guard let team = [home, away].compactMap({ $0 }).first(where: { teams.contains($0) }) else { return nil }
            return (event, team, kickoff)
        }
        guard let target = candidates.max(by: { $0.kickoff < $1.kickoff }) else { return }

        let fixtureID = PredictionFixture.fixtureID(eventID: target.event.id, team: target.team)
        guard store.prediction(for: fixtureID) == nil else { return }

        guard let homeScore = target.event.homeCompetitor?.score.flatMap({ Int($0) }),
              let awayScore = target.event.awayCompetitor?.score.flatMap({ Int($0) }),
              let summary = try? await fetchSummary(target.event.id) else { return }

        let isHome = target.team == target.event.homeCompetitor?.team?.abbreviation
        guard let actual = ActualResult.make(from: summary, isHome: isHome,
                                             homeScore: homeScore, awayScore: awayScore) else { return }

        let formation = Formation(raw: actual.formation ?? "") ?? .default
        var slots: [Int: String] = [:]
        for slot in formation.slots {
            // Match the real XI band for band where we can, so the "errors" below are the only ones.
            let inBand = actual.starters.filter { $0.group == slot.group }
                .map(\.athleteID)
                .filter { !slots.values.contains($0) }
            let fallback = actual.starters.map(\.athleteID).filter { !slots.values.contains($0) }
            guard let pick = inBand.first ?? fallback.first else { continue }
            slots[slot.index] = pick
        }

        // Plant the errors. Two cross-band swaps → two AMBER nodes; one bench player → a RED node
        // plus an entry in "Also started — you missed".
        if let defSlot = formation.slots.first(where: { $0.group == .def })?.index,
           let midSlot = formation.slots.first(where: { $0.group == .mid })?.index,
           let a = slots[defSlot], let b = slots[midSlot] {
            slots[defSlot] = b
            slots[midSlot] = a
        }
        if let fwdSlot = formation.slots.last(where: { $0.group == .fwd })?.index {
            let benched = (summary.homeRoster?.substitutes ?? []) + (summary.awayRoster?.substitutes ?? [])
            let starterIDs = actual.starterIDs
            if let sub = benched.compactMap({ $0.athlete?.id }).first(where: { !starterIDs.contains($0) }) {
                slots[fwdSlot] = sub
            }
        }

        // A wrong scoreline that still calls the right result, so the partial-credit row renders.
        let (homeGuess, awayGuess) = homeScore == awayScore
            ? (homeScore + 1, awayScore + 1)
            : (homeScore > awayScore ? (homeScore + 1, awayScore) : (homeScore, awayScore + 1))

        let prediction = XIPrediction(
            fixtureID: fixtureID, eventID: target.event.id, teamAbbreviation: target.team,
            formation: formation.raw, slots: slots,
            homeScoreGuess: homeGuess, awayScoreGuess: awayGuess, state: .draft)

        store.saveDraft(prediction)
        store.submit(fixtureID: fixtureID, before: .distantFuture)
        var score = PredictionScoring.score(prediction, against: actual)
        score.soccerWeek = FanZoneCadence.soccerWeek(for: target.kickoff)
        store.recordScore(score, for: fixtureID)
        remember(fixtureID)
    }

    /// A plausible client-side distribution so the community layer renders. Built AROUND the real XI
    /// and the user's seeded picks so the standout cards have something true-shaped to say:
    /// one contrarian hit at 14%, one heavily-owned starter the user missed at 83%, the rest mid-band.
    static func syntheticCommunity(eventID: String, team: String, week: Int,
                                   picks: [Int: String], actualStarters: [String]) -> PredictCommunity {
        var counts: [PredictCommunity.Pick: Int] = [:]
        let submissions = 412
        let ordered = picks.sorted { $0.key < $1.key }
        for (offset, entry) in ordered.enumerated() {
            // Spread 40%…95%, with the LAST pick deliberately low so it reads as a gutsy call.
            let pct = offset == ordered.count - 1 ? 14 : min(95, 40 + offset * 6)
            counts[.init(playerID: entry.value, slot: entry.key)] = submissions * pct / 100
        }
        // A widely-backed starter the user left out → the "biggest miss" card.
        let missed = actualStarters.filter { !picks.values.contains($0) }
        for (offset, id) in missed.enumerated() {
            counts[.init(playerID: id, slot: 10 - offset)] = submissions * (offset == 0 ? 83 : 44) / 100
        }
        return PredictCommunity(eventID: eventID, team: team, week: week, revealed: true,
                                closesAt: nil, submissions: submissions, counts: counts)
    }
}
#endif
