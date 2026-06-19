//
//  GameCenterManager.swift
//  NWSLApp
//
//  The one Game Center (GameKit) bridge — a @MainActor @Observable singleton,
//  modelled on PushBridge. A singleton is the deliberate exception to the app's
//  "inject everything" rule: there is exactly one local player, the
//  authenticateHandler is a process-global callback, and UIKit presentation needs
//  a main-actor sink that can't be threaded through SwiftUI environment.
//
//  Game Center is PURELY ADDITIVE on top of the real Supabase leaderboards: the
//  local UserDefaults stores + Supabase remain the source of truth. EVERY call is
//  best-effort and silently no-ops when the player isn't authenticated (Simulator
//  with no Game Center account, offline, or signed out) — Game Center never blocks
//  gameplay and never surfaces an error to the user.
//
//  `import GameKit` is confined to this file so the MVVM layers (Models/Stores/
//  ViewModels/Views) stay GameKit-free; they call through this manager.
//

import Foundation
import GameKit
import UIKit

@MainActor
@Observable
final class GameCenterManager {
    static let shared = GameCenterManager()
    private init() {}

    /// Whether the local player is signed in to Game Center. Drives the ProfileView
    /// entry point and gates every submission.
    private(set) var isAuthenticated = false

    /// Guards `authenticate()` so the handler is installed exactly once even though
    /// it's now triggered lazily from every Fan Zone / Game Center entry point (the
    /// three game screens + the Profile leaderboards strip) rather than at launch.
    private var didStartAuthentication = false

    // MARK: - Authentication

    /// Install GKLocalPlayer's auth handler. Triggered lazily the first time the user
    /// reaches a Fan Zone game or the Game Center dashboard — NOT at app launch — so
    /// the Game Center sign-in banner only appears when it's contextually relevant.
    /// Idempotent: safe to call from several entry points; only the first installs.
    /// GameKit invokes the closure as auth resolves: it may hand back a sign-in view
    /// controller to present, an error, or simply leave `isAuthenticated` set.
    func authenticate() {
        guard !didStartAuthentication else { return }
        didStartAuthentication = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                self.present(viewController)            // Apple's sign-in sheet
                return
            }
            if let error {
                #if DEBUG
                print("[GameCenter] auth error: \(error.localizedDescription)")
                #endif
                self.isAuthenticated = false
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    // MARK: - Submissions (best-effort; silent no-op when unauthenticated)

    /// Submit a score to one leaderboard. Fire-and-forget; a failure is non-fatal (GC is
    /// additive) but NOT silent — it's flagged via telemetry so a wrong ASC id / offline /
    /// unlinked-account failure reaches the owner instead of vanishing.
    func submit(_ value: Int, to leaderboardID: String) {
        guard isAuthenticated else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID])
            } catch {
                Diagnostics.shared.record(.apiFailure, "GC submit \(leaderboardID): \(error.localizedDescription)")
            }
        }
    }

    /// Report an achievement as earned (100% by default). GKAchievement.report is
    /// server-idempotent — re-reporting a completed one is harmless and never lowers
    /// a higher prior percent — so callers fire-and-forget with no local bookkeeping.
    func report(_ achievementID: String, percent: Double = 100) {
        guard isAuthenticated else { return }
        let achievement = GKAchievement(identifier: achievementID)
        achievement.percentComplete = percent
        achievement.showsCompletionBanner = true
        Task {
            do { try await GKAchievement.report([achievement]) }
            catch { Diagnostics.shared.record(.apiFailure, "GC report \(achievementID): \(error.localizedDescription)") }
        }
    }

    // MARK: - Cross-game sync (push everything; re-eval cross-game achievements)

    /// Push all four leaderboards from the current store state and re-evaluate the
    /// achievements that can be derived from durable state. Called on auth success,
    /// on foreground, and after a game commits — so the boards self-heal after an
    /// offline session. The combined Superfan total + "Played All 3" + streak
    /// milestones live here (they need cross-store data the per-screen hooks lack).
    func syncAll(trivia: TriviaStore, predict: PredictionStore, bracket: BracketStore) {
        guard isAuthenticated else { return }

        submit(trivia.bestStreak, to: GameCenterID.Leaderboard.triviaStreak)
        submit(predict.seasonPoints, to: GameCenterID.Leaderboard.predictSeasonPoints)
        submit(bracket.points, to: GameCenterID.Leaderboard.bracketTotalPoints)
        submit(GameCenterScores.superfanTotal(
                    triviaTotalCorrect: trivia.totalCorrect,
                    predictSeasonPoints: predict.seasonPoints,
                    bracketPoints: bracket.points),
               to: GameCenterID.Leaderboard.superfanTotal)

        if predict.hasPredicted { report(GameCenterID.Achievement.firstPrediction) }
        if trivia.bestStreak >= 7  { report(GameCenterID.Achievement.triviaStreak7) }
        if trivia.bestStreak >= 30 { report(GameCenterID.Achievement.triviaStreak30) }
        if bracket.points > 0 { report(GameCenterID.Achievement.bracketRoundWon) }
        if GameCenterScores.playedAllThree(
                playedTrivia: trivia.lastCompletedDay != nil,
                hasPredicted: predict.hasPredicted,
                playedBracket: bracket.hasPlayed) {
            report(GameCenterID.Achievement.playedAllThree)
        }
    }

    // MARK: - Presentation

    /// Open the native Game Center dashboard (leaderboards + achievements). Uses
    /// GKAccessPoint — the modern replacement for the deprecated
    /// GKGameCenterViewController — so it presents itself, no UIViewController
    /// plumbing. A no-op when the player isn't signed in (ProfileView shows that).
    func showDashboard() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) { }
    }

    /// Present GameKit's sign-in VC from the active window's top controller. Called
    /// from the auth handler, which fires after the UI is up.
    func present(_ viewController: UIViewController) {
        guard let top = Self.topViewController() else { return }
        top.present(viewController, animated: true)
    }

    /// The frontmost view controller of the active foreground scene.
    static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let keyWindow = windows.first(where: \.isKeyWindow) ?? windows.first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
