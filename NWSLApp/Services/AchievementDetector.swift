//
//  AchievementDetector.swift
//  NWSLApp
//
//  Client-side achievement detection (Competitive Redesign, PR4). Two entry points, both idempotent (the
//  award write no-ops on an already-earned badge), so calling them broadly is safe:
//
//   • `checkCumulative` reads the four durable stores + the weekly-play ledger — it catches every badge
//     that's a "have you ever…" over saved state (First Blood, Well-Rounded, Streak Master, Lineup Oracle,
//     Perfect Round, Know It All, Iron Fan). Called when the Superfan screen loads (all stores in hand),
//     so a badge shows the moment the fan next checks their Best Moments.
//   • `checkBracket` reads a LOADED edition (matchups + seeds + the user's picks) for the two upset badges
//     (Dark Horse, Upset Royalty) — those need per-round matchup data the store doesn't cache. Called when
//     Bracket Battle loads its edition.
//
//  Detection is store-derived rather than a per-commit event, on purpose: it's simpler, has one code path
//  per badge, and can't miss an award that a fragile completion hook would (the badge twin of "derive,
//  don't duplicate"). Weekly play IS recorded per-commit (FanZoneActivity) since that can't be
//  reconstructed after the fact.
//

import Foundation

enum AchievementDetector {

    /// Award every store-derivable badge the user now qualifies for. Best-effort; no-op when signed out.
    static func checkCumulative(predict: PredictionStore, bracket: BracketStore, trivia: TriviaStore,
                                knowHer: KnowHerGameStore, userID: UUID, season: Int,
                                now: Date = Date()) async {
        var awards: [(achievement: Achievement, detail: String?)] = []

        let playedAny = predict.hasPredicted || bracket.hasPlayed || trivia.hasEverPlayed
            || knowHer.playedInSeason(year: season)
        if playedAny { awards.append((.firstBlood, nil)) }

        let gamesWithPoints = [predict.seasonPoints > 0, bracket.points > 0,
                               trivia.seasonCorrect > 0, knowHer.seasonPoints(year: season) > 0]
            .filter { $0 }.count
        if Achievement.isWellRounded(gamesWithSeasonPoints: gamesWithPoints) {
            awards.append((.wellRounded, nil))
        }

        if Achievement.isStreakMaster(triviaRoundStreak: trivia.bestStreak) {
            awards.append((.streakMaster, "\(trivia.bestStreak) rounds in a row"))
        }

        let bestXI = predict.scores.values.map(\.correctPlayers).max() ?? 0
        if Achievement.isLineupOracle(correctPlayers: bestXI) {
            awards.append((.lineupOracle, "\(bestXI) of 11 starters in a match"))
        }

        if knowHer.hasPerfectRound() { awards.append((.perfectRound, nil)) }

        if Achievement.isKnowItAll(playersScored8Plus: knowHer.distinctPlayersScored(atLeast: Achievement.knowItAllScore)) {
            awards.append((.knowItAll, nil))
        }

        if Achievement.isIronFan(consecutiveWeeksPlayed: FanZoneActivity.consecutiveWeeksPlayed(now: now)) {
            awards.append((.ironFan, nil))
        }

        await AchievementService().award(awards, seasonYear: season, userID: userID)
    }

    /// Award the two upset badges from a loaded edition (per-round matchup seeds + the user's picks).
    static func checkBracket(edition: BracketEdition, store: BracketStore, userID: UUID, season: Int) async {
        var bestUpsetsInARound = 0
        var bestUpsetRound: BracketRound?
        var hasBigUpset = false

        for round in edition.rounds where round < edition.currentRound {
            let matchups = edition.matchups(in: round)
            guard matchups.contains(where: { $0.isResolved }) else { continue }
            var upsets = 0
            for m in matchups {
                guard let winnerID = m.communityWinnerID,
                      store.pick(matchupID: m.id, in: round) == winnerID,   // the user called this winner
                      let winner = m.entrant(winnerID) else { continue }
                let loser = winner.id == m.entrantA.id ? m.entrantB : m.entrantA
                if Achievement.isUpsetWin(pickedWinner: true, winnerSeed: winner.seed, loserSeed: loser.seed) {
                    upsets += 1
                }
                if Achievement.isBigUpsetWin(pickedWinner: true, winnerSeed: winner.seed, loserSeed: loser.seed) {
                    hasBigUpset = true
                }
            }
            if upsets > bestUpsetsInARound { bestUpsetsInARound = upsets; bestUpsetRound = round }
        }

        var awards: [(achievement: Achievement, detail: String?)] = []
        if Achievement.isDarkHorse(upsetWins: bestUpsetsInARound) {
            let name = bestUpsetRound.map { $0.displayName(in: edition.rounds) } ?? "a round"
            awards.append((.darkHorse, "\(bestUpsetsInARound) upsets in \(name)"))
        }
        if hasBigUpset { awards.append((.upsetRoyalty, nil)) }
        await AchievementService().award(awards, seasonYear: season, userID: userID)
    }
}
