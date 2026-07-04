//
//  DeviceTokenService.swift
//  NWSLApp
//
//  The Supabase data client for the `device_tokens` table — the APNs token half of
//  Tier 2 (server push). A direct sibling of FollowSyncService: a plain `struct` of
//  typed async calls, no UI, no state. Row-Level Security scopes every call to the
//  signed-in user; we pass `userID` explicitly so the upsert carries the right
//  owner and the delete filters cleanly.
//
//  Why a server-side token table at all: the match-watcher Worker can't ask a
//  phone for its token at goal-time — it needs the tokens already on record,
//  keyed to the users who follow the scoring team. This is where the app deposits
//  them.
//

import Foundation
import Supabase

struct DeviceTokenService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Register (or refresh) this device's APNs token for the user. Upsert on
    /// `(user_id, device_id)` so a rotated/reinstalled token REPLACES this device's row in place
    /// instead of accumulating a new row — while a second device (its own `device_id`) keeps its own
    /// row and still receives pushes. `device_id` is the Keychain-stable per-device UUID.
    func registerToken(_ token: String, userID: UUID) async throws {
        try await client
            .from("device_tokens")
            .upsert(
                DeviceTokenInsert(user_id: userID, device_id: DeviceIdentity.deviceID, token: token),
                onConflict: "user_id,device_id"
            )
            .execute()
    }

    /// Remove a token (e.g. on sign-out, so a shared device stops receiving the
    /// previous user's alerts). Best-effort like the rest of the sync path.
    func removeToken(_ token: String, userID: UUID) async throws {
        try await client
            .from("device_tokens")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("token", value: token)
            .execute()
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
// `platform` defaults to 'ios' in the table, so we don't send it.
private struct DeviceTokenInsert: Encodable {
    let user_id: UUID
    let device_id: String
    let token: String
}
