//
//  TriviaSelectionTests.swift
//  NWSLAppTests
//
//  NWSL Trivia moved from a client-sliced flat pool to a proxy that serves each round's PRE-GROUPED
//  10 questions (roadmap #2), so the old `TriviaViewModel.roundSelection` slicer is gone. What matters
//  now is that `TriviaQuestion` decodes the new pipeline fields (scope/source/flavor/revealFact) FORWARD-
//  and BACKWARD-compatibly: a legacy payload without them still decodes, and an unknown value in a lenient
//  `String?` field never throws (the crash-the-whole-array trap the model comment warns about).
//

import Foundation
import Testing
@testable import NWSLApp

struct TriviaQuestionDecodingTests {

    private func decode(_ json: String) throws -> TriviaQuestion {
        try JSONDecoder().decode(TriviaQuestion.self, from: Data(json.utf8))
    }

    @Test func legacyPayloadDecodesWithNewFieldsNil() throws {
        // A v1 flat-pool question — no scope/source/flavor/revealFact.
        let q = try decode(#"""
        {"id":"q001","question":"Which club has won the most NWSL Championships?",
         "options":["A","B","C","D"],"correctIndex":2,"category":"leagueHistory","difficulty":"easy"}
        """#)
        #expect(q.id == "q001")
        #expect(q.scope == nil)
        #expect(q.source == nil)
        #expect(q.flavor == nil)
        #expect(q.revealFact == nil)
        #expect(q.isFunFact == false)
        #expect(q.correctAnswer == "C")
    }

    @Test func v2PayloadExposesTheNewFields() throws {
        let q = try decode(#"""
        {"id":"q123","question":"Which was the first NWSL stadium built specifically for a women's team?",
         "options":["A","B","C","D"],"correctIndex":0,"category":"venues","difficulty":"hard",
         "scope":"evergreen","source":"https://example.com/x","flavor":"funFact",
         "revealFact":"It opened in 2024 — the first of its kind."}
        """#)
        #expect(q.scope == "evergreen")
        #expect(q.source == "https://example.com/x")
        #expect(q.flavor == "funFact")
        #expect(q.isFunFact == true)
        #expect(q.revealFact?.isEmpty == false)
    }

    @Test func unknownFlavorDecodesLenientlyWithoutThrowing() throws {
        // The whole point of String? (not an enum): a value the app doesn't know must NOT crash-decode.
        let q = try decode(#"""
        {"id":"q9","question":"?","options":["A","B","C","D"],"correctIndex":1,
         "category":"rules","difficulty":"medium","flavor":"spicy"}
        """#)
        #expect(q.flavor == "spicy")
        #expect(q.isFunFact == false)
    }

    @Test func anArrayOfMixedV1AndV2Decodes() throws {
        let arr = try JSONDecoder().decode([TriviaQuestion].self, from: Data(#"""
        [{"id":"a","question":"?","options":["A","B","C","D"],"correctIndex":0,"category":"records","difficulty":"easy"},
         {"id":"b","question":"?","options":["A","B","C","D"],"correctIndex":3,"category":"teamHistory","difficulty":"hard","flavor":"funFact","scope":"seasonBound"}]
        """#.utf8))
        #expect(arr.count == 2)
        #expect(arr[0].isFunFact == false)
        #expect(arr[1].isFunFact == true)
    }
}
