//
//  LineupPlayerStatsView.swift
//  NWSLApp
//
//  Tapping a player on the match-lineup pitch (CombinedPitchView / FormationPitchView)
//  pushes this, which shows the SAME PlayerDetailView as Teams → team → player — full
//  roster bio (age / height / nationality / position) AND her season stats.
//
//  The match lineup only carries id / name / jersey / position, so we fetch the team
//  ROSTER (where the bio fields live), find her by id, and pull her season stats from
//  the cached per-athlete fetch. The bridged match Athlete (`asAthlete`) shows instantly
//  as the header and is the honest fallback if the roster can't be reached / doesn't
//  list her (never a blank screen).
//

import SwiftUI

/// A navigable reference to a pitch player: the bridged (match) Athlete for an instant
/// header + fallback, the team's ESPN club id (to fetch her full roster bio + stats), and
/// the accent hex. Pushed via `.navigationDestination(for: LineupPlayerRef.self)`.
struct LineupPlayerRef: Hashable {
    let athlete: Athlete
    let clubID: String?
    let accentHex: String?
}

extension MatchPlayer {
    /// Bridge a match-lineup player to the roster `Athlete` PlayerDetailView expects.
    /// Nil when ESPN gave no athlete id (we can't fetch stats or identify her).
    var asAthlete: Athlete? {
        guard let id = athlete?.id, !id.isEmpty else { return nil }
        return Athlete(
            id: id,
            name: athlete?.displayName ?? athlete?.shortName ?? athlete?.lastName ?? "—",
            shortName: athlete?.shortName,
            jersey: jersey,
            positionName: position?.name ?? position?.displayName,
            positionAbbreviation: position?.abbreviation,
            age: nil,
            displayHeight: nil,
            citizenship: nil
        )
    }
}

/// Loads the tapped player's full roster record + season stats, then renders the shared
/// PlayerDetailView. Header shows instantly from the match data; bio + stats fill in when
/// the (cached) fetches return. Degrades honestly — a roster/stats miss keeps the match
/// identity and logs to Diagnostics rather than failing silently.
struct LineupPlayerStatsView: View {
    let ref: LineupPlayerRef

    @State private var rosterAthlete: Athlete?
    @State private var stats: PlayerSeasonStats?
    @State private var squadColorHex: String?
    private let service = ESPNService()

    /// The full roster Athlete once loaded (age/height/nationality), else the match one.
    private var athlete: Athlete { rosterAthlete ?? ref.athlete }

    var body: some View {
        PlayerDetailView(
            athlete: athlete,
            accentHex: ref.accentHex ?? squadColorHex,
            stats: stats,
            seasonLabel: "SEASON \(AppConfig.currentSeasonYear)"
        )
        .task { await load() }
    }

    private func load() async {
        // Guard each piece on its own nil-state rather than a single latch: a disrupted or
        // failed first fetch must be able to RETRY on the next appearance instead of latching a
        // permanently blank card (the transient-blank-stats hardening, 2026-07-21). `.task` runs
        // once per appearance, so a success sticks and won't refetch.

        // Full bio (age/height/nationality/position) lives in the TEAM ROSTER — the same
        // fetch Teams → team uses. Find her by id; a miss keeps the match identity.
        if rosterAthlete == nil, let clubID = ref.clubID {
            do {
                let squad = try await service.fetchRoster(clubID: clubID)
                rosterAthlete = squad.athletes.first { $0.id == ref.athlete.id }
                squadColorHex = squad.colorHex
            } catch {
                Diagnostics.shared.record(.apiFailure,
                    "lineup player roster \(clubID): \(error.localizedDescription)")
            }
        }
        // Her season stats — cached per-athlete fetch. A nil result (failed/disrupted) is retried
        // on reappear; seasonStats logs a genuine failure so a blank card is diagnosable.
        if stats == nil {
            stats = await service.seasonStats(for: [athlete]).first
        }
    }
}
