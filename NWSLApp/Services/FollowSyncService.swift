//
//  FollowSyncService.swift
//  NWSLApp
//
//  The Supabase data client for the `follows` table — the networking twin of
//  ESPNService, but talking to our per-user backend instead of ESPN. No UI, no
//  state: just typed async calls. Row-Level Security on the table means every
//  call is implicitly scoped to the signed-in user (a user can only read/write
//  rows where `user_id = auth.uid()`); we still pass `userID` explicitly so
//  inserts carry the right owner and deletes/selects filter cleanly.
//
//  A plain `struct` of async methods (default-constructible, like ESPNService) —
//  no actor needed, it touches no shared mutable state, just awaits the SDK.
//

import Foundation
import Supabase

struct FollowSyncService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// All team IDs the user follows on the server (sync-down / restore source).
    func fetchRemoteFollows(userID: UUID) async throws -> Set<String> {
        let rows: [FollowRow] = try await client
            .from("follows")
            .select("team_id")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return Set(rows.map(\.team_id))
    }

    /// Upsert the whole set in one call (sign-in push-up of the merged union).
    /// `onConflict` makes re-pushing existing rows idempotent. No-op when empty.
    func pushFollows(_ ids: Set<String>, userID: UUID) async throws {
        guard !ids.isEmpty else { return }
        let rows = ids.map { FollowInsert(user_id: userID, team_id: $0) }
        try await client
            .from("follows")
            .upsert(rows, onConflict: "user_id,team_id")
            .execute()
    }

    /// Add a single follow (ongoing sync-up when the user follows a club).
    func addFollow(_ id: String, userID: UUID) async throws {
        try await client
            .from("follows")
            .upsert(FollowInsert(user_id: userID, team_id: id), onConflict: "user_id,team_id")
            .execute()
    }

    /// Remove a single follow (ongoing sync-up when the user unfollows a club).
    func removeFollow(_ id: String, userID: UUID) async throws {
        try await client
            .from("follows")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("team_id", value: id)
            .execute()
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct FollowRow: Decodable {
    let team_id: String
}

private struct FollowInsert: Encodable {
    let user_id: UUID
    let team_id: String
}
