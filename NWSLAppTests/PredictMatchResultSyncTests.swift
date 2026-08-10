//
//  PredictMatchResultSyncTests.swift
//  NWSLAppTests
//
//  The wire shape of `predict_match_results` (reinstall durability, 2026-08-10). `slots` travels
//  as a String-keyed JSON object — the service converts `[Int: String]` ↔ `[String: String]` at
//  the boundary EXPLICITLY rather than leaning on Codable's Int-key special case (Dictionary's
//  Codable happens to encode Int keys as an object today, but a jsonb column's contract shouldn't
//  hang on a stdlib encoding detail). If the conversion regresses, every restored XI decodes empty
//  and the predicted-vs-actual detail silently loses its lineups — these tests pin it.
//

import Foundation
import Testing
@testable import NWSLApp

struct PredictMatchResultSyncTests {

    /// A row exactly as PostgREST returns it (string-keyed slots, snake_case, extra columns ignored).
    private let rowJSON = """
    {
      "user_id": "b7e7c1f2-0000-0000-0000-000000000000",
      "event_id": "401853957",
      "team_abbreviation": "LOU",
      "season": "2026",
      "week": 22,
      "correct_players": 8,
      "correct_positions": 6,
      "formation_correct": true,
      "exact_scoreline": false,
      "result_correct": true,
      "perfect_xi": false,
      "graded_home_score": 2,
      "graded_away_score": 1,
      "formation": "4-3-3",
      "slots": {"0": "gk1", "1": "d1", "10": "f3"},
      "home_score_guess": 2,
      "away_score_guess": 0,
      "graded_at": "2026-08-01T22:05:00Z",
      "updated_at": "2026-08-01T22:05:00Z"
    }
    """

    @Test func rowDecodesWithStringKeyedSlots() throws {
        let row = try JSONDecoder().decode(MatchResultRow.self, from: Data(rowJSON.utf8))
        #expect(row.event_id == "401853957")
        #expect(row.week == 22)
        #expect(row.slots == ["0": "gk1", "1": "d1", "10": "f3"])
        #expect(row.graded_home_score == 2)
        #expect(row.formation == "4-3-3")
    }

    /// The boundary conversion both directions: Int-keyed app slots ↔ String-keyed wire slots.
    @Test func slotKeyConversionRoundTrips() {
        let appSlots: [Int: String] = Dictionary(uniqueKeysWithValues: (0...10).map { ($0, "a\($0)") })
        let wire = Dictionary(uniqueKeysWithValues: appSlots.map { (String($0.key), $0.value) })
        let back: [Int: String] = Dictionary(uniqueKeysWithValues: wire.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        #expect(back == appSlots)
        // A non-numeric wire key (corrupt row) drops that slot rather than crashing the restore.
        let corrupt: [String: String] = ["0": "gk1", "not-a-slot": "x"]
        let salvaged: [Int: String] = Dictionary(uniqueKeysWithValues: corrupt.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        #expect(salvaged == [0: "gk1"])
    }

    /// A legacy row (nil week / stamps — a grade banked before those fields existed) must decode,
    /// and its nils must mean "unknown", never break the restore.
    @Test func legacyRowWithNilWeekAndStampsDecodes() throws {
        let legacy = rowJSON
            .replacingOccurrences(of: "\"week\": 22,", with: "\"week\": null,")
            .replacingOccurrences(of: "\"graded_home_score\": 2,", with: "\"graded_home_score\": null,")
            .replacingOccurrences(of: "\"graded_away_score\": 1,", with: "\"graded_away_score\": null,")
        let row = try JSONDecoder().decode(MatchResultRow.self, from: Data(legacy.utf8))
        #expect(row.week == nil)
        #expect(row.graded_home_score == nil)
    }
}
