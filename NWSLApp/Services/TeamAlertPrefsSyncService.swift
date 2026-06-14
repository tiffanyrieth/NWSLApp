//
//  TeamAlertPrefsSyncService.swift
//  NWSLApp
//
//  The Supabase data client for `team_alert_preferences` — per-team match-alert
//  ON/OFF (QOL v2). A plain `struct` of typed async calls, no UI, no state,
//  RLS-scoped per user. One row per (user, team); the match-watcher Worker reads
//  these (service-role) to decide which of a team's followers to push.
//
//  Per-team is just on/off now — WHAT to send is the global `notification_preferences`
//  row (NotificationPrefsSyncService). So this carries a single `alerts_enabled` flag.
//

import Foundation
import Supabase

struct TeamAlertPrefsSyncService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Upsert one team's on/off (insert-or-replace on the (user_id, team_id) key).
    func push(teamID: String, enabled: Bool, userID: UUID) async throws {
        try await client
            .from("team_alert_preferences")
            .upsert(TeamAlertRow(user_id: userID, team_id: teamID, alerts_enabled: enabled),
                    onConflict: "user_id,team_id")
            .execute()
    }

    /// The user's alert-enabled team ids (sign-in reconcile / new-device restore).
    func fetchAll(userID: UUID) async throws -> Set<String> {
        let rows: [TeamAlertRow] = try await client
            .from("team_alert_preferences")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return Set(rows.filter(\.alerts_enabled).map(\.team_id))
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct TeamAlertRow: Codable {
    let user_id: UUID
    let team_id: String
    let alerts_enabled: Bool
}
