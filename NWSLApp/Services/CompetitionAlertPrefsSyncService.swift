//
//  CompetitionAlertPrefsSyncService.swift
//  NWSLApp
//
//  The Supabase data client for `competition_alert_preferences` — per-national-team match-alert
//  ON/OFF. The national-team twin of TeamAlertPrefsSyncService, keyed by `follow_key` ("nt:USA")
//  instead of an ESPN club id (national teams don't fit the club-id-keyed table — see the schema
//  comment). One row per (user, follow_key); the match-watcher reads these (service-role) when it
//  polls the national-team ESPN feeds and fans a NT event out by FIFA code.
//
//  WHAT to send is still the global `notification_preferences` row — this carries only the on/off.
//

import Foundation
import Supabase

struct CompetitionAlertPrefsSyncService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Upsert one national team's on/off (insert-or-replace on the (user_id, follow_key) key).
    func push(followKey: String, enabled: Bool, userID: UUID) async throws {
        try await client
            .from("competition_alert_preferences")
            .upsert(CompetitionAlertRow(user_id: userID, follow_key: followKey, alerts_enabled: enabled),
                    onConflict: "user_id,follow_key")
            .execute()
    }

    /// The user's alert-enabled follow keys (sign-in reconcile / new-device restore).
    func fetchAll(userID: UUID) async throws -> Set<String> {
        let rows: [CompetitionAlertRow] = try await client
            .from("competition_alert_preferences")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return Set(rows.filter(\.alerts_enabled).map(\.follow_key))
    }

    /// EVERY follow key with a row for this user, on/off — the reconcile prunes rows the device no
    /// longer wants so the table converges to exactly the device's ON set (mirrors the club service).
    func fetchAllKeys(userID: UUID) async throws -> Set<String> {
        let rows: [FollowKeyRow] = try await client
            .from("competition_alert_preferences")
            .select("follow_key")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return Set(rows.map(\.follow_key))
    }

    /// Hard-delete one national team's row (mirror prune) — a clean table, one row per wanted team.
    func delete(followKey: String, userID: UUID) async throws {
        try await client
            .from("competition_alert_preferences")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("follow_key", value: followKey)
            .execute()
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct CompetitionAlertRow: Codable {
    let user_id: UUID
    let follow_key: String
    let alerts_enabled: Bool
}

private struct FollowKeyRow: Decodable {
    let follow_key: String
}
