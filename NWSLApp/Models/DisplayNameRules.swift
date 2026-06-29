//
//  DisplayNameRules.swift
//  NWSLApp
//
//  Pure rules for the leaderboard display name + the Fan Zone gate decision, kept in ONE
//  place so the entry field (`DisplayNameEntry`), the store (`AuthStore.updateDisplayName`),
//  and the gate modifier (`fanZoneGate`) can't drift apart — and so they're unit-testable
//  without spinning up a View or a Supabase client. No UI, no state, no I/O.
//

import Foundation

/// Validation + normalization for a display name. A name is the user's leaderboard identity,
/// so the rules are deliberately small and shared: trim whitespace, require 2–20 characters.
enum DisplayNameRules {
    static let minLength = 2
    static let maxLength = 20

    /// True when `raw` is submittable: 2–20 characters after trimming. Drives the entry CTA.
    static func isValid(_ raw: String) -> Bool {
        let count = raw.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (minLength...maxLength).contains(count)
    }

    /// The stored form: trimmed and capped to `maxLength`. Nil when empty after trimming
    /// (the one case `AuthStore.updateDisplayName` refuses — the UI already blocks length < 2).
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }
}

/// What a Fan Zone ranked action should do when the user triggers it, from auth state alone.
/// `hasChosenName` (signed in + a CONFIRMED name) is what lets an unconfirmed Apple name still
/// route through the name step instead of silently passing onto a public leaderboard.
enum FanZoneGateDecision: Equatable {
    case runNow        // signed in + confirmed name → proceed immediately, no sheet
    case nameStep      // signed in but name not confirmed → confirm it first
    case signInStep    // signed out → sign in, then confirm a name

    static func resolve(isSignedIn: Bool, hasChosenName: Bool) -> FanZoneGateDecision {
        if isSignedIn && hasChosenName { return .runNow }
        return isSignedIn ? .nameStep : .signInStep
    }
}
