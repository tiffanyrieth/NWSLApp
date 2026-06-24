//
//  AccountDeletionService.swift
//  NWSLApp
//
//  Calls the privileged proxy route that PERMANENTLY deletes a user's account —
//  the Supabase auth user plus every per-user row (profile, follows, alerts,
//  notification prefs, device tokens, Fan Zone scores) via on-delete cascade.
//
//  Why a proxy route and not a direct Supabase call: deleting an auth user requires
//  the service-role key (the Auth Admin API), which the anon client key cannot do —
//  RLS lets a user delete their OWN table rows but NOT the `auth.users` row itself.
//  The Worker holds the service-role secret; the client sends its session JWT and the
//  Worker verifies it to derive the user id (never trusts a client-supplied id).
//
//  Fails LOUD: any non-2xx (or unreachable) throws, so the caller never reports a
//  successful "account deleted" when the server still has the data. This is the
//  opposite of the old TEMP stub, which signed out locally and silently kept the
//  account — a silent failure with App Store compliance risk.
//

import Foundation

enum AccountDeletionError: LocalizedError {
    case invalidResponse
    case server(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Couldn't reach the deletion service. Check your connection and try again."
        case .server(let status, _):
            return "Account deletion failed (HTTP \(status)). Your account was NOT deleted — try again."
        }
    }
}

struct AccountDeletionService {
    private var endpoint: URL {
        AppConfig.scoreboardProxyBase.appendingPathComponent("account/delete")
    }

    /// Delete the signed-in user's account server-side. `accessToken` is the Supabase
    /// session JWT — the Worker verifies it to identify the user. Throws on any non-2xx
    /// so the caller fails loud and never claims success on a partial/failed delete.
    func deleteAccount(accessToken: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccountDeletionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountDeletionError.server(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}
