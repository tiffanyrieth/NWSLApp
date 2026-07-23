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
//  Mostly WRITE-ONLY — the device owns intent. The one READ (`fetchPreferences`) exists
//  for a single case: a REINSTALL, where the fresh install has no toggles at all and the
//  server row is the user's last known selection (NotificationSyncCoordinator's restore
//  step). Everything else stays device-authoritative.
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

    /// Read back the user's saved row — `nil` when they've never had one (a brand-new account).
    /// ONLY used by the reinstall restore (a device with no local choices); the device is the
    /// source of truth everywhere else, so this must never become a general "pull on launch".
    /// RLS scopes the select to the caller; `schema.sql` already carries both the policy and the
    /// `grant select … to authenticated` (without the grant this 42501s — RLS ≠ privilege).
    func fetchPreferences(userID: UUID) async throws -> NotificationPreferencesSnapshot? {
        let rows: [NotificationPreferencesReadRow] = try await client
            .from("notification_preferences")
            .select()
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        return rows.first?.snapshot
    }
}

// The read twin of the write row. Separate type because the write side is `Encodable` with a
// `user_id` we supply — here every flag is decoded and the id is irrelevant (RLS already scoped it).
private struct NotificationPreferencesReadRow: Decodable {
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

    var snapshot: NotificationPreferencesSnapshot {
        NotificationPreferencesSnapshot(
            dayBefore: day_before,
            lineupPosted: lineup_posted,
            kickoff: kickoff,
            goals: goals,
            halftime: halftime,
            fullTime: full_time,
            substitutions: substitutions,
            fanZoneRounds: fan_zone_rounds,
            playerSpotlight: player_spotlight,
            liveActivitiesEnabled: live_activities_enabled
        )
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
