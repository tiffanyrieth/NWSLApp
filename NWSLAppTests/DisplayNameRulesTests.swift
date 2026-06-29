//
//  DisplayNameRulesTests.swift
//  NWSLAppTests
//
//  Pure-logic tests for the shared display-name rules and the Fan Zone gate decision
//  (Models/DisplayNameRules.swift). These guard the two behaviors the account/display-name
//  fix hinges on: name validation/normalization (2–20, trimmed, capped) and the gate routing
//  that keeps an UNCONFIRMED name (e.g. an Apple-supplied one) from auto-passing onto a board.
//

import Foundation
import Testing
@testable import NWSLApp

struct DisplayNameRulesTests {

    // MARK: - Validation (drives the entry-field CTA)

    @Test func rejectsTooShortAndEmpty() {
        #expect(DisplayNameRules.isValid("") == false)
        #expect(DisplayNameRules.isValid("   ") == false)      // whitespace-only
        #expect(DisplayNameRules.isValid("a") == false)        // 1 char < min
        #expect(DisplayNameRules.isValid(" a ") == false)      // trims to 1
    }

    @Test func acceptsWithinRange() {
        #expect(DisplayNameRules.isValid("Jo"))                // exactly min (2)
        #expect(DisplayNameRules.isValid("Riveter"))
        #expect(DisplayNameRules.isValid("12345678901234567890"))   // exactly max (20)
    }

    @Test func rejectsOverMax() {
        #expect(DisplayNameRules.isValid("123456789012345678901") == false)   // 21 chars
    }

    // MARK: - Normalization (the stored form)

    @Test func normalizesTrimAndCap() {
        #expect(DisplayNameRules.normalized("  Spirit Fan  ") == "Spirit Fan")
        // Capped to 20 characters.
        #expect(DisplayNameRules.normalized("123456789012345678901234")?.count == 20)
        // Empty / whitespace-only → nil (refused by the store).
        #expect(DisplayNameRules.normalized("") == nil)
        #expect(DisplayNameRules.normalized("   ") == nil)
    }

    // MARK: - Gate decision (hasChosenName transitions)

    @Test func gateRoutesSignedOutToSignIn() {
        #expect(FanZoneGateDecision.resolve(isSignedIn: false, hasChosenName: false) == .signInStep)
        // hasChosenName can't be true while signed out, but the routing still prioritizes sign-in.
        #expect(FanZoneGateDecision.resolve(isSignedIn: false, hasChosenName: true) == .signInStep)
    }

    @Test func gateRoutesSignedInUnconfirmedToNameStep() {
        // Signed in with a present-but-unconfirmed name (e.g. an Apple name) → must confirm first.
        #expect(FanZoneGateDecision.resolve(isSignedIn: true, hasChosenName: false) == .nameStep)
    }

    @Test func gateRunsImmediatelyWhenConfirmed() {
        #expect(FanZoneGateDecision.resolve(isSignedIn: true, hasChosenName: true) == .runNow)
    }
}
