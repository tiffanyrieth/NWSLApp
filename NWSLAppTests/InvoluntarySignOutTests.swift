//
//  InvoluntarySignOutTests.swift
//  NWSLAppTests
//
//  The involuntary-sign-out fix (2026-07-16): a lapsed Supabase session must never leave the
//  Notifications screen showing Tier-2 toggles ON (the "silent failure that looks like success"
//  field bug). Pure-logic coverage of the three seams:
//   1. AuthStore.reduceUser — the auth-event → currentUser reduction (listener).
//   2. AuthStore.isDefinitiveSignOut — dead-session vs transient error classification (probe).
//   3. NotificationDisplayGate.displayedTier2 — the display half of "shown ON ⟹ signed in".
//   4. NotificationSyncCoordinator's signed-out desync sentinel (set / deliberate-suppressed /
//      no-intent-no-flag / persists).
//  The sentinel-CLEAR paths (sign-in success / explicit sign-out) live inside AuthStore's SIWA
//  flow and are exercised in the sim verification (they need a real ASAuthorization).
//

import Auth   // explicit: the app's local `AuthError` shadows the SDK's — Auth.AuthError disambiguates
import Foundation
import Supabase
import Testing
@testable import NWSLApp

// MARK: - Fixtures

private func makeUser(id: UUID = UUID()) -> User {
    User(
        id: id, appMetadata: [:], userMetadata: [:], aud: "authenticated",
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
}

private func makeSession(user: User, expiresAt: TimeInterval) -> Session {
    Session(
        accessToken: "test-access", tokenType: "bearer", expiresIn: 3600,
        expiresAt: expiresAt, refreshToken: "test-refresh", user: user)
}

private func isolated(_ suite: String) -> UserDefaults {
    // Force-unwrap safe: a named suite in the test host always constructs.
    let d = UserDefaults(suiteName: suite)!
    d.removePersistentDomain(forName: suite)
    return d
}

// MARK: - 1. reduceUser (auth-event reduction)

struct AuthStoreReduceUserTests {

    @Test func signedInAdoptsSessionUser() {
        let user = makeUser()
        let session = makeSession(user: user, expiresAt: Date().timeIntervalSince1970 + 3600)
        let reduced = AuthStore.reduceUser(event: .signedIn, session: session, current: nil)
        #expect(reduced?.id == user.id)
    }

    @Test func tokenRefreshedKeepsSessionUser() {
        let user = makeUser()
        let session = makeSession(user: user, expiresAt: Date().timeIntervalSince1970 + 3600)
        let reduced = AuthStore.reduceUser(event: .tokenRefreshed, session: session, current: makeUser())
        #expect(reduced?.id == user.id)
    }

    /// Conservative rule: a session-carrying event that arrives WITHOUT a session keeps the
    /// current user — only explicit terminations sign out.
    @Test func signedInWithNilSessionKeepsCurrent() {
        let current = makeUser()
        let reduced = AuthStore.reduceUser(event: .signedIn, session: nil, current: current)
        #expect(reduced?.id == current.id)
    }

    @Test func initialSessionValidAdopts() {
        let user = makeUser()
        let session = makeSession(user: user, expiresAt: Date().timeIntervalSince1970 + 3600)
        let reduced = AuthStore.reduceUser(event: .initialSession, session: session, current: nil)
        #expect(reduced?.id == user.id)
    }

    /// The stale-currentUser trap: an EXPIRED initial session must read signed-out, not
    /// resurrect the dead identity.
    @Test func initialSessionExpiredIsNil() {
        let session = makeSession(user: makeUser(), expiresAt: 0)   // 1970 — long dead
        #expect(AuthStore.reduceUser(event: .initialSession, session: session, current: makeUser()) == nil)
    }

    @Test func initialSessionMissingIsNil() {
        #expect(AuthStore.reduceUser(event: .initialSession, session: nil, current: makeUser()) == nil)
    }

    @Test func signedOutIsNil() {
        #expect(AuthStore.reduceUser(event: .signedOut, session: nil, current: makeUser()) == nil)
    }

    @Test func userDeletedIsNil() {
        #expect(AuthStore.reduceUser(event: .userDeleted, session: nil, current: makeUser()) == nil)
    }

    /// Events outside the SIWA flow never act as a sign-out signal.
    @Test func unrelatedEventsKeepCurrent() {
        let current = makeUser()
        #expect(AuthStore.reduceUser(event: .passwordRecovery, session: nil, current: current)?.id == current.id)
        #expect(AuthStore.reduceUser(event: .mfaChallengeVerified, session: nil, current: current)?.id == current.id)
    }
}

// MARK: - 2. isDefinitiveSignOut (error classification)

struct AuthStoreSignOutClassifierTests {

    private func apiError(_ code: Auth.ErrorCode) -> Auth.AuthError {
        // Force-unwrap safe: a literal URL + fixed args always construct in the test host.
        let response = HTTPURLResponse(
            url: URL(string: "https://example.supabase.co")!, statusCode: 400,
            httpVersion: nil, headerFields: nil)!
        return .api(message: "test", errorCode: code, underlyingData: Data(), underlyingResponse: response)
    }

    @Test func sessionMissingIsDefinitive() {
        #expect(AuthStore.isDefinitiveSignOut(Auth.AuthError.sessionMissing))
    }

    @Test func deadSessionApiCodesAreDefinitive() {
        for code: Auth.ErrorCode in [.sessionExpired, .sessionNotFound, .refreshTokenNotFound,
                                     .refreshTokenAlreadyUsed, .userNotFound, .userBanned] {
            #expect(AuthStore.isDefinitiveSignOut(apiError(code)), "\(code) should be definitive")
        }
    }

    /// The rule that keeps a tunnel from reading as a sign-out: transport errors are transient.
    @Test func offlineIsTransient() {
        #expect(!AuthStore.isDefinitiveSignOut(URLError(.notConnectedToInternet)))
        #expect(!AuthStore.isDefinitiveSignOut(URLError(.timedOut)))
    }

    @Test func unrelatedApiCodeIsTransient() {
        #expect(!AuthStore.isDefinitiveSignOut(apiError(.init("over_request_rate_limit"))))
    }
}

// MARK: - 3. Display gate

struct NotificationDisplayGateTests {

    @Test func storedOnSignedOutDisplaysOff() {
        #expect(!NotificationDisplayGate.displayedTier2(true, signedIn: false))
    }

    @Test func storedOnSignedInDisplaysOn() {
        #expect(NotificationDisplayGate.displayedTier2(true, signedIn: true))
    }

    @Test func storedOffAlwaysDisplaysOff() {
        #expect(!NotificationDisplayGate.displayedTier2(false, signedIn: true))
        #expect(!NotificationDisplayGate.displayedTier2(false, signedIn: false))
    }
}

// MARK: - 4. Desync sentinel (coordinator reconcile)

@MainActor
struct Tier2SentinelTests {

    /// Build the pieces on an isolated suite: prefs with stored Tier-2 intent, a signed-out
    /// auth store, and the coordinator wired to the same isolated defaults.
    private func makeWorld(suite: String, tier2On: Bool)
        -> (defaults: UserDefaults, coordinator: NotificationSyncCoordinator)
    {
        let defaults = isolated(suite)
        let prefs = NotificationPreferencesStore(defaults: defaults)
        if tier2On { prefs.kickoff = true; prefs.goals = true }
        let coordinator = NotificationSyncCoordinator(
            auth: AuthStore(),                       // fresh → signed out
            preferences: prefs,
            teamAlerts: TeamAlertStore(defaults: defaults),
            defaults: defaults)
        return (defaults, coordinator)
    }

    @Test func signedOutWithIntentSetsSentinel() {
        let (defaults, coordinator) = makeWorld(suite: "test.sentinel.set", tier2On: true)
        coordinator.start()   // signed-out sync pass → reconcile
        #expect(defaults.bool(forKey: SignOutSentinels.tier2WasOnAtSignOut))
    }

    @Test func sentinelSurvivesFreshRead() {
        let suite = "test.sentinel.persist"
        let (_, coordinator) = makeWorld(suite: suite, tier2On: true)
        coordinator.start()
        // A separate handle on the same suite (≈ next launch) still reads it.
        #expect(UserDefaults(suiteName: suite)!.bool(forKey: SignOutSentinels.tier2WasOnAtSignOut))
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
    }

    /// The owner's no-double-loop rule: a deliberate sign-out never flags.
    @Test func deliberateSignOutSuppresses() {
        let (defaults, coordinator) = makeWorld(suite: "test.sentinel.deliberate", tier2On: true)
        defaults.set(true, forKey: SignOutSentinels.deliberateSignOut)
        coordinator.start()
        #expect(!defaults.bool(forKey: SignOutSentinels.tier2WasOnAtSignOut))
    }

    /// No stored intent → nothing is broken → no flag (a fresh install never nags).
    @Test func noIntentNoSentinel() {
        let (defaults, coordinator) = makeWorld(suite: "test.sentinel.nointent", tier2On: false)
        coordinator.start()
        #expect(!defaults.bool(forKey: SignOutSentinels.tier2WasOnAtSignOut))
    }

    /// Per-team bell intent counts as Tier-2 intent even with every global type off.
    @Test func teamBellAloneSetsSentinel() {
        let defaults = isolated("test.sentinel.teams")
        let teamAlerts = TeamAlertStore(defaults: defaults)
        teamAlerts.setAlertsEnabled(true, for: "20907")
        let coordinator = NotificationSyncCoordinator(
            auth: AuthStore(),
            preferences: NotificationPreferencesStore(defaults: defaults),
            teamAlerts: teamAlerts,
            defaults: defaults)
        coordinator.start()
        #expect(defaults.bool(forKey: SignOutSentinels.tier2WasOnAtSignOut))
    }
}
