//
//  CommunityVerdictLineTests.swift
//  NWSLAppTests
//
//  The per-question "how did I do" line on the shared community results panel (Know Her Game +
//  NWSL Trivia). Before 2026-07-29 the panel marked only the CORRECT option, so a question you got
//  wrong rendered identically to one you got right — readers reasonably took the ✓ next to a 97%
//  bar to be their own answer. This line states both facts in words, which is the part that can't
//  be misread. Pure string logic, so it's tested here rather than in the sim.
//

import Foundation
import Testing
@testable import NWSLApp

struct CommunityVerdictLineTests {

    private let options = ["Pink", "Green", "Blue", "Purple"]

    @Test func wrongAnswerNamesBothYourPickAndTheAnswer() {
        // The owner's own report: picked Green (B), the answer was Blue (C).
        let v = CommunityResultsView.verdict(options: options, correctIndex: 2, yourPick: 1)
        #expect(v?.mine == "You said Green")
        #expect(v?.correction == " — the answer was Blue")
        #expect(v?.gotIt == false)
        // The two tinted halves must read as one sentence to VoiceOver, not two fragments.
        #expect(v?.spoken == "You said Green — the answer was Blue")
    }

    @Test func correctAnswerDoesNotRestateTheSameOptionTwice() {
        // "You said Blue — the answer was Blue" is padding, and it stacks up over 10–15 questions.
        let v = CommunityResultsView.verdict(options: options, correctIndex: 2, yourPick: 2)
        #expect(v?.mine == "You said Blue")
        #expect(v?.correction == nil)
        #expect(v?.gotIt == true)
        #expect(v?.spoken == "You said Blue")
    }

    @Test func outOfRangeIndicesProduceNoLine() {
        // Defensive: picks and questions are written together, so this shouldn't happen — but nil
        // degrades to the no-verdict panel, where a crash or a dangling "You said " would not.
        #expect(CommunityResultsView.verdict(options: options, correctIndex: 2, yourPick: 9) == nil)
        #expect(CommunityResultsView.verdict(options: options, correctIndex: 9, yourPick: 1) == nil)
        #expect(CommunityResultsView.verdict(options: [], correctIndex: 0, yourPick: 0) == nil)
    }

    @Test func longOptionTextIsCarriedVerbatim() {
        // Trivia options can be full sentences; the line must not truncate or reformat them (the view
        // wraps instead). This is also why the verdict line earns its place: the option labels in the
        // bar grid are single-line and DO truncate, so this is where the full text lives.
        let long = ["Rose Lavelle in the 2019 World Cup final", "Megan Rapinoe in the 2019 semi-final"]
        #expect(CommunityResultsView.verdict(options: long, correctIndex: 0, yourPick: 1)?.spoken
                == "You said Megan Rapinoe in the 2019 semi-final — the answer was Rose Lavelle in the 2019 World Cup final")
    }
}
