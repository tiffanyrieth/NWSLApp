//
//  AchievementService.swift
//  NWSLApp
//
//  The Supabase client for `user_achievements` (Competitive Redesign, PR4). Awards are DETECTED
//  client-side (per game) and written here; the write is idempotent — `ignoreDuplicates` issues
//  `INSERT … ON CONFLICT DO NOTHING`, so the same game commit firing detection twice never duplicates a
//  badge (and it needs only the INSERT grant, since an earned achievement is permanent — never updated).
//  Best-effort like the other Fan Zone services (logs to Diagnostics, never throws to the UI).
//

import Foundation
import Supabase

/// An earned badge for the "Your Best Moments" list.
struct EarnedAchievement: Identifiable, Equatable {
    let achievement: Achievement
    let earnedAt: Date
    /// The flavor detail from `metadata` ("10/10 on Sandy MacIver"), or nil → the default description.
    let detail: String?
    var id: String { achievement.rawValue }

    var description: String { detail ?? achievement.defaultDescription }
}

struct AchievementService {
    private var client: SupabaseClient { SupabaseManager.client }

    /// Award a set of achievements (each with an optional card detail). Idempotent — already-earned badges
    /// are silently ignored. No-op for an empty set. Best-effort.
    func award(_ awards: [(achievement: Achievement, detail: String?)], seasonYear: Int, userID: UUID) async {
        guard !awards.isEmpty else { return }
        let rows = awards.map { a in
            AchievementRow(user_id: userID, achievement_key: a.achievement.rawValue,
                           season_year: seasonYear,
                           metadata: a.detail.map { ["detail": $0] })
        }
        do {
            try await client.from("user_achievements")
                .upsert(rows, onConflict: "user_id,achievement_key,season_year", ignoreDuplicates: true)
                .execute()
        } catch {
            Diagnostics.shared.record(.apiFailure, "achievement award: \(error.localizedDescription)")
        }
    }

    /// The user's earned achievements this season, newest first (empty on failure / signed out — never
    /// fabricated). Unknown keys (a future badge this build doesn't know) are dropped, not crashed.
    func earned(userID: UUID, seasonYear: Int) async -> [EarnedAchievement] {
        do {
            let rows: [EarnedRow] = try await client.from("user_achievements")
                .select("achievement_key,earned_at,metadata")
                .eq("user_id", value: userID)
                .eq("season_year", value: seasonYear)
                .order("earned_at", ascending: false)
                .execute()
                .value
            return rows.compactMap { row in
                guard let achievement = Achievement(rawValue: row.achievement_key) else { return nil }
                return EarnedAchievement(achievement: achievement, earnedAt: row.earned_at,
                                         detail: row.metadata?["detail"])
            }
        } catch {
            Diagnostics.shared.record(.apiFailure, "achievement read: \(error.localizedDescription)")
            return []
        }
    }
}

private struct AchievementRow: Encodable {
    let user_id: UUID
    let achievement_key: String
    let season_year: Int
    let metadata: [String: String]?
}
private struct EarnedRow: Decodable {
    let achievement_key: String
    let earned_at: Date
    let metadata: [String: String]?
}
