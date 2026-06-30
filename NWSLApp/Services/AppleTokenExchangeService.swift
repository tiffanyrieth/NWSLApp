//
//  AppleTokenExchangeService.swift
//  NWSLApp
//
//  Forwards Apple's short-lived `authorizationCode` (from Sign in with Apple) to the
//  proxy, which exchanges it with Apple for a long-lived `refresh_token` and stores it
//  on the user's profile. That stored token is what lets account deletion REVOKE the
//  Apple credential (App Store guideline 5.1.1(v)) — without it, Apple keeps treating the
//  user as linked and a re-signup returns "existing user".
//
//  Why a proxy round-trip and not a direct Apple call: the exchange must be signed with
//  the SIWA `.p8` private key (an ES256 `client_secret` JWT). That key is a server secret
//  the app must never hold — the Worker signs; the app only relays the code + its session.
//
//  Fire-and-forget by design (see the call site in AuthStore.handleSignIn): the code
//  expires in ~5 minutes and there's no point retrying a dead code. A failure here just
//  means "no revocation token until the next sign-in" — the account works regardless — so
//  the caller logs it to Diagnostics and never blocks or fails sign-in over it.
//

import Foundation

enum AppleTokenExchangeError: LocalizedError {
    case invalidResponse
    case server(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Couldn't reach the Apple token-exchange service."
        case .server(let status, _):
            return "Apple token exchange failed (HTTP \(status))."
        }
    }
}

struct AppleTokenExchangeService {
    private var endpoint: URL {
        AppConfig.scoreboardProxyBase.appendingPathComponent("auth/apple-token-exchange")
    }

    private struct Body: Encodable {
        let authorizationCode: String
        let userId: String
    }

    /// Send the Apple authorization code + the caller's id to the proxy. `accessToken` is
    /// the Supabase session JWT — the Worker verifies it to identify the user (and that it
    /// matches `userID`). Throws on any non-2xx so the caller can log the failure.
    func exchange(authorizationCode: String, userID: UUID, accessToken: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Body(authorizationCode: authorizationCode, userId: userID.uuidString))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppleTokenExchangeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppleTokenExchangeError.server(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
