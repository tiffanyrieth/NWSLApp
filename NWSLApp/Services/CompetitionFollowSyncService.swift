//
//  CompetitionFollowSyncService.swift
//  NWSLApp
//
//  The Supabase data client for the `competition_follows` table — the competition
//  twin of FollowSyncService (clubs). Same shape: a dependency-free struct of typed
//  async calls, RLS-scoped to the signed-in user. The rows are namespaced follow
//  keys ("nt:USA" for a national team by FIFA code, "concacaf" for the Champions Cup
//  toggle), so one table carries both new followable kinds. No UI, no state.
//

import Foundation
import Supabase

struct CompetitionFollowSyncService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Every competition follow-key the user holds on the server (sync-down source).
    func fetchRemoteFollows(userID: UUID) async throws -> Set<String> {
        let rows: [Row] = try await client
            .from("competition_follows")
            .select("follow_key")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return Set(rows.map(\.follow_key))
    }

    /// Upsert the whole set in one call (sign-in push-up of the merged union).
    /// `onConflict` makes re-pushing existing rows idempotent. No-op when empty.
    func pushFollows(_ keys: Set<String>, userID: UUID) async throws {
        guard !keys.isEmpty else { return }
        let rows = keys.map { Insert(user_id: userID, follow_key: $0) }
        try await client
            .from("competition_follows")
            .upsert(rows, onConflict: "user_id,follow_key")
            .execute()
    }

    /// Add a single follow (ongoing sync-up).
    func addFollow(_ key: String, userID: UUID) async throws {
        try await client
            .from("competition_follows")
            .upsert(Insert(user_id: userID, follow_key: key), onConflict: "user_id,follow_key")
            .execute()
    }

    /// Remove a single follow (ongoing sync-up when the user unfollows).
    func removeFollow(_ key: String, userID: UUID) async throws {
        try await client
            .from("competition_follows")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("follow_key", value: key)
            .execute()
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct Row: Decodable {
    let follow_key: String
}

private struct Insert: Encodable {
    let user_id: UUID
    let follow_key: String
}
