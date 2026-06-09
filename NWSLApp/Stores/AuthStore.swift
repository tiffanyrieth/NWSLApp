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

    private let client = SupabaseManager.client

    /// Raw nonce stashed between request-config and completion (the request
    /// carries its SHA256; Supabase needs the raw value to verify).
    private var currentNonce: String?

    /// Rehydrate the session on launch. The Supabase SDK persists the session to
    /// the keychain itself, so this just asks for the stored one — no custom token
    /// storage. `try?`: no stored session simply means signed-out (currentUser nil).
    func restoreSession() async {
        currentUser = try? await client.auth.session.user
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
            let name = Self.displayName(from: credential.fullName)
            await upsertProfile(userID: session.user.id, displayName: name)
        }
    }

    /// Sign out of Supabase. Leaves local follows (UserDefaults) intact — the app
    /// stays personalized while signed out; only server sync stops.
    func signOut() async {
        try? await client.auth.signOut()
        currentUser = nil
    }

    // MARK: - Profile

    /// Create-or-update the user's `profiles` row. Only writes `display_name` when
    /// we actually have one (Apple gives it once), so a later sign-in with no name
    /// can't clobber a name captured on the first. Non-fatal on failure: the auth
    /// user exists regardless; the profile row is a convenience.
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
            print("[AuthStore] profile upsert failed: \(error)")
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
