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

    /// True once GameKit's auth handler has reached a DEFINITIVE outcome (signed in OR
    /// declined/error) — i.e. auth is no longer "still resolving". Used to tell a real
    /// timing race (a game finished before auth resolved) apart from the expected
    /// "this user has no Game Center" case, so we only emit telemetry for the former.
    private var authResolved = false

    /// Set when the user tapped Profile's 🏆 Leaderboards but auth wasn't resolved yet —
    /// open the dashboard as soon as auth lands (see `resolvePendingDashboard`).
    private var pendingDashboard = false

    /// True when the user tapped Leaderboards but Game Center isn't available (declined or
    /// no account). Drives an honest message in Profile instead of a silent dead tap; the
    /// view clears it on dismiss. (NO SILENT FAILURES — a tap must produce a visible result.)
    var leaderboardsUnavailable = false

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
                self.authResolved = true       // definitive: declined / unavailable
                self.resolvePendingDashboard()
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            self.authResolved = true           // definitive outcome reached
            self.resolvePendingDashboard()
        }
    }

    /// Open the native Game Center dashboard from Profile's 🏆 Leaderboards cell. Triggers
    /// auth ON TAP (not on Profile appear), so the GC sign-in banner only shows when the user
    /// actually asks for leaderboards. If auth is still resolving, the dashboard opens once it
    /// lands (`resolvePendingDashboard`); if it's already resolved-unavailable, we surface an
    /// honest message rather than a dead tap.
    func openLeaderboards() {
        if isAuthenticated { showDashboard(); return }
        if authResolved {                       // already tried, not signed in → be honest now
            leaderboardsUnavailable = true
            return
        }
        pendingDashboard = true
        authenticate()                          // installs the handler (idempotent) → banner on tap
    }

    /// Act on a queued Leaderboards tap once auth reaches a definitive outcome: open the
    /// dashboard if signed in, otherwise show the honest "unavailable" message.
    private func resolvePendingDashboard() {
        guard pendingDashboard else { return }
        pendingDashboard = false
        if isAuthenticated {
            showDashboard()
        } else {
            leaderboardsUnavailable = true
            Diagnostics.shared.record(.apiFailure, "GC leaderboards tapped: not authenticated")
        }
    }

    // MARK: - Submissions (best-effort; silent no-op when unauthenticated)

    /// Submit a score to one leaderboard. Fire-and-forget; a failure is non-fatal (GC is
    /// additive) but NOT silent — it's flagged via telemetry so a wrong ASC id / offline /
    /// unlinked-account failure reaches the owner instead of vanishing.
    func submit(_ value: Int, to leaderboardID: String) {
        guard isAuthenticated else {
            // Genuine race: a game finished before GC auth resolved. The foreground/auth-change
            // `syncAll` re-pushes current store state once it does, so this self-heals — but flag
            // it. (Skip telemetry when auth HAS resolved: that's just a user without Game Center.)
            if !authResolved {
                Diagnostics.shared.record(.apiFailure, "GC submit \(leaderboardID): auth not resolved yet")
            }
            return
        }
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
        guard isAuthenticated else {
            if !authResolved {
                Diagnostics.shared.record(.apiFailure, "GC report \(achievementID): auth not resolved yet")
            }
            return
        }
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
