//
//  AuthStore.swift
//  NWSLApp
//
//  The account layer: Sign in with Apple → a Supabase user. Shared app-wide and
//  injected via `.environment()` like FollowingStore, so any surface (the
//  post-onboarding sign-in prompt now; a Settings screen later) can read the
//  signed-in state and drive sign-in.
//
//  `@MainActor` because it mutates `@Observable` state SwiftUI reads
//  (`currentUser`) across `await` boundaries — the same async-into-observable
//  shape as ClubStore.load(), made explicit. It deliberately knows NOTHING about
//  follows: FollowSyncCoordinator watches `currentUser` and does the follow
//  reconciliation, keeping the auth → follow dependency one-directional.
//
//  The UI uses SwiftUI's official `SignInWithAppleButton`, which owns the
//  ASAuthorization presentation. AuthStore plugs into its two closures:
//  `configureSignInRequest` (set scopes + the hashed nonce) and `handleSignIn`
//  (exchange the returned credential with Supabase). Apple requires a nonce — we
//  send SHA256(nonce) in the request and the raw nonce to Supabase, which checks
//  they correspond, binding the identity token to this sign-in.
//

import Auth   // explicit: the app's own `AuthError` below SHADOWS the SDK's — Auth.AuthError disambiguates
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import Supabase

enum AuthError: Error {
    case missingIdentityToken
    case missingNonce
    case unexpectedCredential
    case missingSession
}

@MainActor
@Observable
final class AuthStore {
    /// The signed-in Supabase user, or nil when signed out. Drives `isSignedIn`
    /// and is the signal FollowSyncCoordinator watches to run follow sync.
    private(set) var currentUser: User?

    var isSignedIn: Bool { currentUser != nil }

    /// The signed-in user's id, or nil. A convenience over `currentUser?.id` so
    /// callers (FollowSyncCoordinator) can watch/read it without importing the
    /// Supabase `User` type — keeps the follow path SDK-free.
    var userID: UUID? { currentUser?.id }

    /// The user's display name. Sourced from the server `profiles` table (the durable
    /// truth, fetched by `hydrateProfile()`) and cached in UserDefaults so the Profile
    /// screen can show it instantly on a normal launch without a round-trip. Nil only
    /// for a brand-new user with no name yet, or in the brief reinstall window before
    /// the first hydrate returns.
    private(set) var displayName: String?
    private static let nameKey = "auth.displayName"

    /// Whether the user has explicitly CHOSEN/confirmed their name (vs. it merely being
    /// present). An Apple-supplied name is present but NOT chosen — the user must confirm
    /// it at the gate before it reaches a public leaderboard. Mirrors `profiles.name_is_custom`
    /// server-side (so it survives reinstall); cached locally for an instant gate decision.
    private(set) var displayNameIsCustom: Bool
    private static let nameChosenKey = "auth.displayNameIsCustom"

    /// True once `hydrateProfile()` has finished (success OR failure) for this session.
    /// Lets the Profile header tell "name still loading" (show a placeholder) apart from
    /// "loaded, genuinely no name yet" (brand-new user) — avoiding a cold-launch flicker.
    private(set) var profileHydrated = false

    /// True once `restoreSession()` has run at launch (whether or not a session was found).
    /// The root gate uses it so we don't flash the onboarding picker before we even know
    /// if there's a signed-in user to restore follows for.
    private(set) var sessionRestoreAttempted = false

    /// True when a non-empty display name is set. NOTE: not sufficient for the gate on its
    /// own — an unconfirmed Apple name satisfies this. The gate uses `hasChosenName`.
    var hasDisplayName: Bool {
        !(displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The Fan Zone gate's condition: signed in with a name the user has actually CONFIRMED.
    /// Keeps an unconfirmed Apple name from auto-passing onto a public leaderboard.
    var hasChosenName: Bool { displayNameIsCustom && hasDisplayName }

    init() {
        displayName = UserDefaults.standard.string(forKey: Self.nameKey)
        displayNameIsCustom = UserDefaults.standard.bool(forKey: Self.nameChosenKey)
    }

    private let client = SupabaseManager.client
    private let deletionService = AccountDeletionService()

    /// The long-lived auth-event listener (see `startAuthStateListener`). Held so a re-fired
    /// `.task` can't spawn a second listener.
    private var authListenerTask: Task<Void, Never>?

    /// Raw nonce stashed between request-config and completion (the request
    /// carries its SHA256; Supabase needs the raw value to verify).
    private var currentNonce: String?

    /// Guards against a second `handleSignIn` running while one is in flight. The
    /// `SignInWithAppleButton` flow normally serializes request→completion, so this is
    /// belt-and-suspenders — it closes the only theoretical double-invocation path (a
    /// concurrent completion clearing `currentNonce` mid-exchange → a spurious
    /// `.missingNonce` that reads as "sign in failed, try again"). Harmless if the
    /// observed sim double-sign-in is purely the simulator's first-run Apple-ID behavior.
    private var isSigningIn = false

    /// Rehydrate the session on launch. The Supabase SDK persists the session to
    /// the keychain itself, so this just asks for the stored one — no custom token
    /// storage. `try?`: no stored session simply means signed-out (currentUser nil).
    func restoreSession() async {
        defer { sessionRestoreAttempted = true }
        currentUser = try? await client.auth.session.user
        NotifTrace.shared.log("session-restore", currentUser != nil ? .ok : .skip,
            currentUser != nil ? "signed in" : "no stored session")
        // A restored session means buffered pre-sign-in breadcrumbs can now upload (keyed to this user).
        await NotifTrace.shared.flush()
        // Pull the display name + chosen flag from the server. UserDefaults was wiped on a
        // reinstall, so the local cache can't be trusted as the source — the server is.
        await hydrateProfile()
    }

    // MARK: - Session integrity (involuntary sign-out detection)

    /// Mirror Supabase auth events into `currentUser` for the app's lifetime. Parity +
    /// defense-in-depth for the involuntary-sign-out fix: an explicit `signOut()` on another
    /// code path, a `userDeleted`, or an expired `initialSession` all land here, so the UI can
    /// never keep showing a signed-in state the SDK has abandoned.
    ///
    /// ⚠️ Scope (verified against supabase-swift 2.47.0): `authStateChanges` emits `.signedOut`
    /// ONLY from an explicit `signOut()` call — a failed token refresh mid-run throws internally
    /// and emits NO event. So this listener alone cannot catch expiry-while-running; that case is
    /// `revalidateSession()`'s job (the foreground probe). Upside: the listener can't false-fire
    /// on a network blip — it only ever sees genuine terminations.
    ///
    /// Started once from RootTabView, AFTER `restoreSession()` (so the initial state is settled);
    /// idempotent via `authListenerTask`. The reduce step only assigns on a real identity change,
    /// so it never fights `restoreSession()`/`handleSignIn()`/`signOut()` writing the same value.
    func startAuthStateListener() {
        guard authListenerTask == nil else { return }
        authListenerTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                let reduced = Self.reduceUser(event: event, session: session, current: self.currentUser)
                if self.currentUser?.id != reduced?.id {
                    NotifTrace.shared.log("auth-event", .ok,
                        "\(event.rawValue) → \(reduced != nil ? "signed in" : "signed out")")
                    self.currentUser = reduced
                }
            }
        }
    }

    /// Pure event → user reduction (unit-tested). Conservative by design: events that should
    /// carry a session but don't keep the CURRENT user rather than signing out — only an
    /// explicit termination (or an expired initial session) yields nil.
    nonisolated static func reduceUser(event: AuthChangeEvent, session: Session?, current: User?) -> User? {
        switch event {
        case .signedIn, .tokenRefreshed, .userUpdated:
            return session?.user ?? current
        case .initialSession:
            // A stored session that is already expired (and couldn't refresh) is signed-out —
            // trusting it would recreate the exact stale-currentUser bug this fix removes.
            if let session, !session.isExpired { return session.user }
            return nil
        case .signedOut, .userDeleted:
            return nil
        case .passwordRecovery, .mfaChallengeVerified:
            return current   // not part of the SIWA flow; never a sign-out signal
        }
    }

    /// The foreground probe for the case the listener can't see: the session died while the app
    /// was running/backgrounded (refresh token expired or revoked). Called from RootTabView's
    /// `scenePhase == .active` handler. Asks the SDK for a valid session (it refreshes if needed)
    /// and nils `currentUser` ONLY on a definitive termination — a transient/offline failure
    /// leaves the session intact (it retries next foreground), so being in a tunnel never reads
    /// as "signed out".
    func revalidateSession() async {
        guard currentUser != nil else { return }
        do {
            _ = try await client.auth.session
        } catch {
            guard Self.isDefinitiveSignOut(error) else { return }
            // Fail LOUD: this is the involuntary sign-out moment. Nil-ing currentUser cascades —
            // NotificationSyncCoordinator observes it, sets the desync sentinel + telemetry, and
            // RootTabView presents the sign-in nudge.
            Diagnostics.shared.record(.apiFailure,
                "session revalidate: definitive termination — \(error.localizedDescription)")
            currentUser = nil
        }
    }

    /// Pure error classifier (unit-tested): does this error PROVE the session is dead?
    /// True only for the SDK's explicit dead-session signals; anything else (URLError, transport,
    /// decode, rate-limit) is treated as transient and must NOT sign the user out.
    /// Uses the SDK's own `AuthError.errorCode` accessor (it maps `.sessionMissing` →
    /// `.sessionNotFound`), so one code check covers both the thrown-enum and API shapes.
    /// ⚠️ `Auth.AuthError`, fully qualified: the app's local `AuthError` (top of this file)
    /// shadows the SDK's — an unqualified cast would match the WRONG type and never fire.
    nonisolated static func isDefinitiveSignOut(_ error: any Error) -> Bool {
        guard let authError = error as? Auth.AuthError else { return false }
        let deadSessionCodes: [Auth.ErrorCode] = [
            .sessionExpired, .sessionNotFound, .refreshTokenNotFound,
            .refreshTokenAlreadyUsed, .userNotFound, .userBanned,
        ]
        return deadSessionCodes.contains(authError.errorCode)
    }

    /// A Tier-2 write (alert toggle / unfollow) came back Postgres 42501 while `userID` was still
    /// cached ⇒ the request hit the DB as `anon` — the session had silently lapsed (dead token, no
    /// valid JWT attached) even though offline-first keeps `currentUser` set. Nudge a revalidation
    /// so a GENUINELY dead session is caught here (→ nils `currentUser` → the involuntary-sign-out
    /// nudge) instead of the write just failing quietly; a still-live session (transient anon
    /// window) makes `revalidateSession` a no-op. Cheap: guards on 42501 before touching the SDK.
    func revalidateIfUnauthorizedWrite(_ error: any Error) async {
        guard Self.isUnauthorizedWrite(error) else { return }
        await revalidateSession()
    }

    /// True when a PostgREST write was denied at the PRIVILEGE level (Postgres 42501,
    /// `insufficient_privilege`) — the tell that the request ran as `anon` (no valid session token),
    /// distinct from an RLS-policy denial (which returns rows/empty, not this error).
    nonisolated static func isUnauthorizedWrite(_ error: any Error) -> Bool {
        (error as? PostgrestError)?.code == "42501"
    }

    #if DEBUG
    /// `-simulateLostSession`: drop ONLY the local keychain session (before `restoreSession()`
    /// runs), leaving every UserDefaults toggle intact — reproduces exactly the field bug
    /// "signed out involuntarily, Tier-2 flags still stored". The deliberate-sign-out sentinel is
    /// NOT set (this simulates an involuntary lapse), so the nudge fires.
    func debugSimulateLostSession() async {
        try? await client.auth.signOut(scope: .local)
    }
    #endif

    /// Configure the Apple ID request — called from SignInWithAppleButton's
    /// `onRequest`. Generates a fresh nonce, stashes the raw value, and sends its
    /// hash with the request.
    func configureSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        // Email only — we deliberately do NOT request the user's name. The leaderboard identity is a
        // user-chosen USERNAME (Fan Zone gate), never their real name (privacy: a username isn't
        // identifying, and pre-filling "First Last" invites publishing a real name in one tap).
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(nonce)
    }

    /// Handle the button's completion — exchange the Apple credential with
    /// Supabase. On success, publishes `currentUser` and upserts the profile row.
    /// Throws on failure (the caller decides whether to surface it — user
    /// cancellation is expected and shouldn't read as an error).
    func handleSignIn(_ result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .failure(let error):
            throw error
        case .success(let authorization):
            // Ignore a duplicate completion while an exchange is already running, so a second
            // call can't clear `currentNonce` out from under the first (→ spurious .missingNonce).
            guard !isSigningIn else { return }
            isSigningIn = true
            defer { isSigningIn = false }
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.unexpectedCredential
            }
            guard let rawNonce = currentNonce else {
                throw AuthError.missingNonce
            }
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AuthError.missingIdentityToken
            }

            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
            )
            currentNonce = nil
            currentUser = session.user

            // Signed in — both involuntary-sign-out sentinels are moot now: the desync (if any)
            // is healed, and a prior deliberate sign-out no longer suppresses future detection.
            UserDefaults.standard.removeObject(forKey: SignOutSentinels.tier2WasOnAtSignOut)
            UserDefaults.standard.removeObject(forKey: SignOutSentinels.deliberateSignOut)

            // SIWA revocation (App Store guideline 5.1.1(v)): trade Apple's short-lived
            // authorizationCode (~5-min TTL) for a refresh_token, stored server-side via the
            // proxy, so account deletion can later revoke the Apple credential. Fire-and-forget
            // — the code expires fast and there's no point retrying a dead code; a miss just
            // means "no revocation token until next sign-in" (the account works regardless), so
            // we NEVER block or fail sign-in over it. Log every failure to Diagnostics.
            if let codeData = credential.authorizationCode,
               let authCode = String(data: codeData, encoding: .utf8) {
                let accessToken = session.accessToken
                let userID = session.user.id
                Task {
                    do {
                        try await AppleTokenExchangeService().exchange(
                            authorizationCode: authCode, userID: userID, accessToken: accessToken)
                    } catch {
                        Diagnostics.shared.record(.apiFailure, "apple token exchange: \(error.localizedDescription)")
                    }
                }
            } else {
                Diagnostics.shared.record(.apiFailure, "apple token exchange: missing authorizationCode")
            }

            // Flush a push-to-start token captured before this session existed. The Live Activity
            // observers run from app launch (before sign-in), so a brand-new user's token was seen but
            // skipped (no session yet); register it now rather than waiting for the next launch.
            LiveActivityManager.shared.userDidSignIn()

            // A fresh sign-in means the V1 device token (if already delivered) can now upsert, and any
            // buffered pre-sign-in breadcrumbs can upload. The coordinator observes `currentUser` too,
            // but nudge explicitly so registration doesn't wait on the next launch/foreground.
            NotifTrace.shared.log("sign-in", .ok, "handleSignIn")
            await NotifTrace.shared.flush()

            // We deliberately do NOT pull a name from Apple — the leaderboard identity is a
            // user-CHOSEN username (set at the Fan Zone gate), never their real name. Ensure the
            // profiles row exists (id only; `display_name` untouched, so a returning user's chosen
            // username is never clobbered), then hydrate the authoritative profile so that returning
            // user's username is restored (the server row survives reinstall). A brand-new user has
            // no username yet → stays nil → the gate requires one before any ranked play.
            await upsertProfile(userID: session.user.id, displayName: nil)
            await hydrateProfile()
        }
    }

    /// Sign out of Supabase. Leaves local follows (UserDefaults) intact — the app
    /// stays personalized while signed out; only server sync stops.
    func signOut() async {
        // Mark this sign-out DELIBERATE *before* the session drops, so the desync reconcile
        // (which fires the moment currentUser goes nil) knows not to nag — the user chose this,
        // they already know. Also clear any earlier desync flag: it's been acknowledged by intent.
        UserDefaults.standard.set(true, forKey: SignOutSentinels.deliberateSignOut)
        UserDefaults.standard.removeObject(forKey: SignOutSentinels.tier2WasOnAtSignOut)
        // scope: .local — sign out THIS device only. supabase-swift's default (.global) revokes the
        // user's refresh tokens SERVER-SIDE for EVERY device, so a routine sign-out on one install
        // would involuntarily sign the user out everywhere (iPhone sign-out killing an iPad session;
        // and, during testing, a sim/USB sign-out killing the TestFlight session — revalidateSession
        // then correctly detects the dead session and re-prompts). deleteAccount() keeps .global on
        // purpose (the account is gone → every session should die).
        try? await client.auth.signOut(scope: .local)
        currentUser = nil
    }

    /// Permanently delete the account: the Supabase auth user AND every per-user row
    /// (profile, follows, alerts, notification prefs, device tokens, Fan Zone scores),
    /// via the privileged proxy route (`AccountDeletionService`). The client can't do
    /// this directly — deleting an `auth.users` row needs the service-role key.
    ///
    /// Fails LOUD: throws (with telemetry) on any error, so the UI never reports a
    /// successful delete while the server still holds the data. On success it drops the
    /// local identity + session; the caller (ProfileView) then wipes the rest of the
    /// on-device app state AFTER this returns, so a failure leaves everything intact.
    func deleteAccount() async throws {
        guard let accessToken = try? await client.auth.session.accessToken else {
            // No live session → can't authenticate the privileged delete. Surface it
            // rather than pretend we deleted anything.
            Diagnostics.shared.record(.apiFailure, "account delete: no active session")
            throw AuthError.missingSession
        }
        do {
            try await deletionService.deleteAccount(accessToken: accessToken)
        } catch {
            Diagnostics.shared.record(.apiFailure, "account delete: \(error.localizedDescription)")
            throw error
        }
        // Server-side data is gone — now drop the local identity + session. A delete is as
        // deliberate as a sign-out gets: suppress the desync nudge the same way.
        UserDefaults.standard.set(true, forKey: SignOutSentinels.deliberateSignOut)
        UserDefaults.standard.removeObject(forKey: SignOutSentinels.tier2WasOnAtSignOut)
        try? await client.auth.signOut()
        currentUser = nil
        displayName = nil
        displayNameIsCustom = false
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        UserDefaults.standard.removeObject(forKey: Self.nameChosenKey)
    }

    // MARK: - Profile

    /// One row of the `profiles` table — the durable home of the display name + chosen flag.
    private struct ProfileRow: Decodable {
        let display_name: String?
        let name_is_custom: Bool?
    }

    /// The shape of an explicit "user chose their name" write. All fields present, so the
    /// upsert sets `name_is_custom = true` alongside the name in one round-trip.
    private struct ProfileNameChoice: Encodable {
        let id: String
        let display_name: String
        let name_is_custom: Bool
    }

    /// Fetch the authoritative display name + chosen flag from the server and refresh the
    /// local cache. This is the fix for "name reverts to Member after reinstall": UserDefaults
    /// is wiped on reinstall, so the server (written at sign-in) is the only durable source.
    /// Called on BOTH auth paths — `restoreSession()` (Keychain survived) and `handleSignIn()`
    /// (Keychain wiped → re-sign-in). `profileHydrated` flips in a `defer` so the header's
    /// loading state resolves even when the fetch fails (offline) — never a stuck placeholder.
    func hydrateProfile() async {
        defer { profileHydrated = true }
        guard let userID = currentUser?.id else { return }
        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select("display_name, name_is_custom")
                .eq("id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            if let name = row.display_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: Self.nameKey)
            }
            let custom = row.name_is_custom ?? false
            displayNameIsCustom = custom
            UserDefaults.standard.set(custom, forKey: Self.nameChosenKey)
        } catch {
            // Non-fatal (we fall back to the cached value) but NOT silent — a persistent
            // failure (e.g. a missing RLS GRANT) would otherwise silently lose the name.
            Diagnostics.shared.record(.apiFailure, "profile hydrate: \(error.localizedDescription)")
        }
    }

    /// Create-or-update the user's `profiles` row. Only writes `display_name` when
    /// we actually have one (Apple gives it once), so a later sign-in with no name
    /// can't clobber a name captured on the first. Never touches `name_is_custom` here
    /// (it stays the column default `false` for a new row, and is preserved on conflict),
    /// so an Apple-supplied name is recorded but NOT marked confirmed. Non-fatal on
    /// failure: the auth user exists regardless; the profile row is a convenience.
    private func upsertProfile(userID: UUID, displayName: String?) async {
        do {
            if let displayName {
                try await client.from("profiles")
                    .upsert(["id": userID.uuidString, "display_name": displayName])
                    .execute()
            } else {
                try await client.from("profiles")
                    .upsert(["id": userID.uuidString])
                    .execute()
            }
        } catch {
            // Non-fatal (auth still succeeded), but NOT silent: a failed profile upsert means
            // the display name never persisted server-side — flag it for the owner.
            Diagnostics.shared.record(.apiFailure, "profile upsert: \(error.localizedDescription)")
        }
    }

    /// Change how the user's name appears on the leaderboards. Trims + caps length, marks the
    /// name CONFIRMED (`name_is_custom = true`, locally + server-side), and upserts the Supabase
    /// `profiles` row. The user's own row reflects it on the next board load; other players see it
    /// after the user's next submit. (Length cap + trim only — no profanity filter yet; revisit
    /// before public launch.)
    ///
    /// Note: we mark it confirmed even when the text is UNCHANGED — the user reaching this from the
    /// gate with a prefilled Apple name is explicitly confirming it, so the gate must not re-fire.
    /// (Only the empty case early-returns; `DisplayNameEntry` already blocks that in the UI.)
    func updateDisplayName(_ newName: String) async {
        guard let capped = DisplayNameRules.normalized(newName) else { return }
        displayName = capped
        displayNameIsCustom = true
        UserDefaults.standard.set(capped, forKey: Self.nameKey)
        UserDefaults.standard.set(true, forKey: Self.nameChosenKey)
        guard let userID = currentUser?.id else { return }
        do {
            try await client.from("profiles")
                .upsert(ProfileNameChoice(id: userID.uuidString, display_name: capped, name_is_custom: true))
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "display name update: \(error.localizedDescription)")
        }
    }

    // MARK: - Nonce helpers (standard Apple + OIDC pattern)

    /// Random URL-safe nonce. The hashed form rides in the Apple request; the raw
    /// form goes to Supabase, which checks they correspond — binds the token to us.
    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            // fatalError (not a force-unwrap): a failed CSPRNG is unrecoverable and
            // must not silently produce a weak nonce — fail loud in dev.
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate secure nonce. SecRandomCopyBytes failed: \(status)")
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

}
