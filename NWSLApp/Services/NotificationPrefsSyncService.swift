//
//  NotificationPrefsSyncService.swift
//  NWSLApp
//
//  The Supabase data client for the `notification_preferences` table — the prefs
//  half of Tier 2 (server push). Sibling of FollowSyncService / DeviceTokenService:
//  a plain `struct` of typed async calls, no UI, no state, RLS-scoped per user.
//
//  The match-watcher Worker reads this row to decide whether to send (a user with
//  `goals` off gets no goal push), so the app mirrors the nine Profile toggles up
//  here. One row per user (user_id is the primary key), upserted whole.
//

import Foundation
import Supabase

struct NotificationPrefsSyncService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Push the whole nine-flag snapshot to the user's row (insert-or-replace on
    /// the user_id primary key). The app is the source of truth for intent, so a
    /// whole-row upsert is simplest and idempotent.
    func pushPreferences(_ snapshot: NotificationPreferencesSnapshot, userID: UUID) async throws {
        try await client
            .from("notification_preferences")
            .upsert(NotificationPreferencesRow(snapshot, userID: userID), onConflict: "user_id")
            .execute()
    }
}

// snake_case to match the Postgres column names exactly (PostgREST maps 1:1).
private struct NotificationPreferencesRow: Encodable {
    let user_id: UUID
    let day_before: Bool
    let lineup_posted: Bool
    let kickoff: Bool
    let goals: Bool
    let halftime: Bool
    let full_time: Bool
    let substitutions: Bool
    let fan_zone_rounds: Bool
    let player_spotlight: Bool
    let live_activities_enabled: Bool

    init(_ snapshot: NotificationPreferencesSnapshot, userID: UUID) {
        user_id = userID
        day_before = snapshot.dayBefore
        lineup_posted = snapshot.lineupPosted
        kickoff = snapshot.kickoff
        goals = snapshot.goals
        halftime = snapshot.halftime
        full_time = snapshot.fullTime
        substitutions = snapshot.substitutions
        fan_zone_rounds = snapshot.fanZoneRounds
        player_spotlight = snapshot.playerSpotlight
        live_activities_enabled = snapshot.liveActivitiesEnabled
    }
}
