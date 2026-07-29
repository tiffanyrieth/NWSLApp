//
//  Haptics.swift
//  NWSLApp
//
//  The app's haptic vocabulary. Introduced 2026-07-28 for Predict the XI's submit commit — before
//  this the app had NO haptics anywhere, so this is a new primitive and deliberately lands as a
//  named, shared set rather than a raw call at one call site. The next screen that wants one picks
//  from this list instead of inventing its own weight, which is how a codebase ends up with five
//  subtly different "tap" feedbacks.
//
//  WHY `.sensoryFeedback` AND NOT `UIImpactFeedbackGenerator`:
//   • Declarative and value-driven — it fires on a trigger CHANGE, so it can't double-fire on a
//     re-render the way an imperative `.impactOccurred()` inside a button action can.
//   • No generator lifecycle to manage (no `prepare()`, no retained instance, no UIKit import
//     inside a SwiftUI view) — it fits the app's SwiftUI/@Observable style.
//   • It respects the system haptics setting for free.
//   • Available since iOS 17; the app's floor is 17.2.
//
//  RESTRAINT IS THE POINT. Haptics earn their meaning by being rare: if everything buzzes, the
//  commit buzz stops meaning "this is final". Three intents, and a new one needs a reason.
//

import SwiftUI

extension SensoryFeedback {
    /// A one-way commit the user cannot undo — Predict's "Submit & lock in". Heavy on purpose: the
    /// weight IS the message, and it is the only heavy feedback in the app.
    static let dsCommit = SensoryFeedback.impact(weight: .heavy)

    /// Touch-down on an armed destructive-or-final control, paired with the press-scale. Lighter
    /// than the commit so the two read as "about to" and "done".
    static let dsArm = SensoryFeedback.impact(weight: .medium, intensity: 0.7)
}

extension View {
    /// The app's single haptic entry point. Fires when `trigger` changes value.
    ///
    /// Keeping every call behind one modifier means a future decision — a global "reduce haptics"
    /// preference, or muting them during a reveal — is one edit here rather than a hunt through
    /// views.
    func dsHaptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        sensoryFeedback(feedback, trigger: trigger)
    }
}
