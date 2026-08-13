//
//  QuizResultsDecodingTests.swift
//  NWSLAppTests
//
//  Guards the `QuizResults` decoder against the sparse `revealed:false` payload. Before
//  the custom decoder, Swift's synthesized Decodable threw `keyNotFound` on the missing
//  aggregate keys → the "how everyone did" panel showed a false "couldn't load" every day
//  a fan played Daily Trivia. These pin both the sparse (not-yet-revealed) and full shapes.
//

import Foundation
import Testing
@testable import NWSLApp

struct QuizResultsDecodingTests {
    private func decode(_ json: String) throws -> QuizResults {
        try JSONDecoder().decode(QuizResults.self, from: Data(json.utf8))
    }

    @Test func decodesSparseNotYetRevealedPayload() throws {
        // Exactly what the proxy returns for a still-open Trivia day.
        let r = try decode(#"{"game":"trivia","editionKey":"2026-07-10","revealed":false}"#)
        #expect(r.revealed == false)
        #expect(r.responders == 0)
        #expect(r.showPercent == false)
        #expect(r.avgCorrect == nil)
        #expect(r.questions.isEmpty)
    }

    @Test func decodesFullRevealedPayload() throws {
        let json = #"""
        {"game":"trivia","editionKey":"2026-07-09","revealed":true,"responders":30,
         "showPercent":true,"avgCorrect":3.4,
         "questions":[{"questionId":"q001","total":30,"correctCount":21,"optionCounts":{"0":21,"1":6,"2":2,"3":1}}]}
        """#
        let r = try decode(json)
        #expect(r.revealed == true)
        #expect(r.responders == 30)
        #expect(r.showPercent == true)
        #expect(r.avgCorrect == 3.4)
        #expect(r.questions.count == 1)
        #expect(r.questions.first?.correctCount == 21)
        #expect(r.questions.first?.count(forOption: 0) == 21)
        #expect(r.questions.first?.count(forOption: 3) == 1)
    }

    @Test func decodesRevealedButEmptyBoard() throws {
        // Know Her is always revealed; a brand-new edition has zero responders.
        let r = try decode(#"{"game":"knowher","editionKey":"x","revealed":true,"responders":0,"showPercent":false,"avgCorrect":null,"questions":[]}"#)
        #expect(r.revealed == true)
        #expect(r.responders == 0)
        #expect(r.questions.isEmpty)
    }

    // MARK: - reconstruct (cross-device played-set, Gap 3)

    @Test func reconstructGroupsOwnRowsByEditionWithScoreAndPicks() {
        let rows = [
            QuizResultsService.AnswerRow(editionKey: "2026-R05", questionID: "q0", selectedIndex: 1, isCorrect: true),
            QuizResultsService.AnswerRow(editionKey: "2026-R05", questionID: "q1", selectedIndex: 2, isCorrect: false),
            QuizResultsService.AnswerRow(editionKey: "2026-R05", questionID: "q2", selectedIndex: 0, isCorrect: true),
            QuizResultsService.AnswerRow(editionKey: "2026-R06", questionID: "q0", selectedIndex: 3, isCorrect: true),
        ]
        let byKey = Dictionary(uniqueKeysWithValues: QuizResultsService.reconstruct(rows).map { ($0.editionKey, $0) })
        #expect(byKey["2026-R05"]?.total == 3)
        #expect(byKey["2026-R05"]?.correct == 2)           // Σ is_correct, not the row count
        #expect(byKey["2026-R05"]?.picks["q1"] == 2)       // the exact option chosen, by question id
        #expect(byKey["2026-R06"]?.total == 1)
        #expect(byKey["2026-R06"]?.correct == 1)
        #expect(byKey["2026-R06"]?.picks["q0"] == 3)
    }

    @Test func reconstructOfNoRowsIsEmpty() {
        #expect(QuizResultsService.reconstruct([]).isEmpty)
    }
}
