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

    /// EVERY team id with a row for this user, regardless of on/off. The mirror
    /// reconcile needs this to prune rows the device no longer wants — both stale
    /// `true` ghosts (a team un-followed via uninstall) and leftover `false` clutter
    /// — so the table converges to exactly the device's ON set.
    func fetchAllTeamIDs(userID: UUID) async throws -> Set<String> {
        let rows: [TeamIDRow] = try await client
            .from("team_alert_preferences")
            .select("team_id")
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return Set(rows.map(\.team_id))
    }

    /// Hard-delete one team's row (mirror prune). We delete rather than set
    /// `alerts_enabled = false` so the table stays clean — one row per team the
    /// user actually wants alerts for, nothing else.
    func delete(teamID: String, userID: UUID) async throws {
        try await client
            .from("team_alert_preferences")
            .delete()
            .eq("user_id", value: userID.uuidString)
            .eq("team_id", value: teamID)
            .execute()
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct TeamAlertRow: Codable {
    let user_id: UUID
    let team_id: String
    let alerts_enabled: Bool
}

// team_id-only projection for the prune fetch (selecting just one column means the
// full TeamAlertRow can't decode — its other fields aren't in the response).
private struct TeamIDRow: Decodable {
    let team_id: String
}
