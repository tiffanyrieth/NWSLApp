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
        // Pull the display name + chosen flag from the server. UserDefaults was wiped on a
        // reinstall, so the local cache can't be trusted as the source — the server is.
        await hydrateProfile()
    }

    /// Configure the Apple ID request — called from SignInWithAppleButton's
    /// `onRequest`. Generates a fresh nonce, stashes the raw value, and sends its
    /// hash with the request.
    func configureSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
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

            // Apple returns the user's name only on the FIRST authorization, ever —
            // capture it now or never. Upsert keyed on the user id (= auth.uid()).
            // We do NOT mark it `name_is_custom`: an Apple name is present but unconfirmed,
            // so the gate still asks the user to confirm it before it hits a leaderboard.
            let name = Self.displayName(from: credential.fullName)
            if let name {
                displayName = name
                UserDefaults.standard.set(name, forKey: Self.nameKey)
            }
            await upsertProfile(userID: session.user.id, displayName: name)
            // Then pull the authoritative profile (covers the "Keychain wiped → re-sign-in"
            // case: Apple returns no name, but the server still has it + the chosen flag).
            await hydrateProfile()
        }
    }

    /// Sign out of Supabase. Leaves local follows (UserDefaults) intact — the app
    /// stays personalized while signed out; only server sync stops.
    func signOut() async {
        try? await client.auth.signOut()
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
        // Server-side data is gone — now drop the local identity + session.
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

    private static func displayName(from name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: name)
        return formatted.isEmpty ? nil : formatted
    }
}
