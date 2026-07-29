//
//  PredictCommunityService.swift
//  NWSLApp
//
//  Both halves of Predict the XI's community aggregate (results redesign, 2026-07-28):
//  the WRITE that counts a submitted XI, and the READ that returns the distribution once
//  submissions close.
//
//  ⚠️ THEY GO TO DIFFERENT PLACES, ON PURPOSE.
//
//  WRITE → Supabase directly, as the signed-in user, through a SECURITY DEFINER RPC. It needs the
//  user's identity (to dedupe one submission per person per match) and Supabase API calls are
//  unmetered, while Cloudflare requests are the app's scarce resource. The RPC counts the picks and
//  discards them — no lineup is ever stored, so `docs/fan-zone.md` §3's "never uploaded" holds.
//
//  READ → the proxy, because the read is DEADLINE-GATED and Postgres cannot enforce that gate: it
//  has no idea when kickoff is. The proxy does (from its own edge-cached `/summary`), it fails
//  closed, and it edge-caches the frozen post-close answer so a whole club's fans reading the same
//  match collapse to one upstream call.
//
//  Every failure is best-effort and LOUD to the engineer, honest to the user: the local submit
//  always stands on its own, and an unavailable distribution hides the community sections rather
//  than rendering zeros that would read as fact.
//

import Foundation
import Supabase

@Observable
final class PredictCommunityService {

    // MARK: - Write

    private struct RecordPicksParams: Encodable {
        let p_season: String
        let p_week: Int
        let p_event_id: String
        let p_team: String
        let p_picks: [Pick]

        struct Pick: Encodable {
            let player_id: String
            let slot: Int
        }
    }

    /// Count a submitted XI into the club's aggregate.
    ///
    /// Returns true when the call reached the server successfully — NOT whether it incremented.
    /// A repeat submission returns `false` from the RPC and is a correct no-op, so the caller marks
    /// it uploaded either way; the point of the local marker is only to stop re-calling.
    ///
    /// ⚠️ Idempotency is SERVER-SIDE (a `(user_id, event_id)` primary key), not a local flag. That
    /// is what makes a retry, a fast double-tap, a lost response, and a reinstall-and-resubmit all
    /// safe — a device-side "already sent" boolean would have been wrong in exactly those cases.
    @discardableResult
    func recordPicks(_ prediction: XIPrediction, season: String, week: Int) async -> Bool {
        let picks = prediction.slots
            .sorted { $0.key < $1.key }
            .map { RecordPicksParams.Pick(player_id: $0.value, slot: $0.key) }
        // The RPC refuses anything that isn't a complete XI; don't spend a round trip to be told so.
        guard picks.count == 11 else { return false }

        do {
            try await SupabaseManager.client
                .rpc("predict_record_picks", params: RecordPicksParams(
                    p_season: season, p_week: week,
                    p_event_id: prediction.eventID, p_team: prediction.teamAbbreviation,
                    p_picks: picks))
                .execute()
            return true
        } catch {
            // Not silent: a persistent failure means every community percentage in the app is being
            // computed from a short count, which would look like working software.
            Diagnostics.shared.record(.apiFailure,
                "predict community write \(prediction.fixtureID): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Read

    /// Fetch the distribution for one or more fixtures. Keyed by fixtureID in the result.
    ///
    /// A fixture that is sealed (before the close) comes back with `revealed == false` and only its
    /// submission count — that is the normal pre-deadline state, not an error. A fixture missing
    /// from the response entirely is returned as `.unavailable`, which renders identically: no
    /// community sections at all.
    func distribution(season: String, fixtures: [PredictCommunityRequest]) async -> [String: PredictCommunity] {
        guard !fixtures.isEmpty,
              let url = AppConfig.predictCommunityURL(
                season: season,
                fixtures: fixtures.map { "\($0.eventID):\($0.team):\($0.week)" })
        else { return [:] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Diagnostics.shared.record(.apiFailure, "predict community read HTTP \(code)")
                return [:]
            }
            let decoded = try JSONDecoder().decode(PredictCommunityResponse.self, from: data)
            var out: [String: PredictCommunity] = [:]
            for fixture in decoded.fixtures ?? [] {
                let key = PredictionFixture.fixtureID(eventID: fixture.event, team: fixture.team)
                out[key] = fixture.domain()
            }
            return out
        } catch {
            Diagnostics.shared.record(.apiFailure, "predict community read: \(error.localizedDescription)")
            return [:]
        }
    }
}

/// One fixture to ask about. `week` is the soccer week the aggregate is keyed by — the app owns the
/// cadence anchor, so the client supplies it rather than the proxy recomputing it.
struct PredictCommunityRequest: Equatable {
    let eventID: String
    let team: String
    let week: Int
}
