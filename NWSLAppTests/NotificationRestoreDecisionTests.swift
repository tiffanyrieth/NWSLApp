//
//  NotificationRestoreDecisionTests.swift
//  NWSLAppTests
//
//  `NotificationSyncCoordinator.decideRestore` — what a device does with the server's saved
//  `notification_preferences` row on sign-in. The bug this closes: after a REINSTALL the per-team
//  bells came back (TeamAlertSyncCoordinator has a restore branch) while the global alert TYPES did
//  not (the prefs service was push-only), leaving the banned "alerts on, nothing can ever fire"
//  state — and the sign-in push then overwrote the saved row with the fresh install's all-off
//  snapshot, destroying it.
//
//  The rules, in one place:
//   • This install already made a choice (sentinel set, or any toggle on) ⇒ DEVICE-AUTHORITATIVE.
//     A plain sign-out preserves both, so sign out → back in must never pull from the server.
//   • Fresh install + a saved row with something on ⇒ RESTORE IT VERBATIM (an off type stays off).
//   • Fresh install + nothing to restore, but a team bell is on ⇒ CASCADE the default bundle.
//   • Fresh install + nothing anywhere ⇒ do nothing (pure opt-in; never auto-enable).
//

import Foundation
import Testing
@testable import NWSLApp

struct NotificationRestoreDecisionTests {

    private func snapshot(
        dayBefore: Bool = false, lineupPosted: Bool = false, kickoff: Bool = false,
        goals: Bool = false, halftime: Bool = false, fullTime: Bool = false,
        substitutions: Bool = false, fanZoneRounds: Bool = false, playerSpotlight: Bool = false,
        liveActivitiesEnabled: Bool = false
    ) -> NotificationPreferencesSnapshot {
        NotificationPreferencesSnapshot(
            dayBefore: dayBefore, lineupPosted: lineupPosted, kickoff: kickoff, goals: goals,
            halftime: halftime, fullTime: fullTime, substitutions: substitutions,
            fanZoneRounds: fanZoneRounds, playerSpotlight: playerSpotlight,
            liveActivitiesEnabled: liveActivitiesEnabled)
    }

    private var allOff: NotificationPreferencesSnapshot { snapshot() }

    // MARK: - The reinstall (the reported bug)

    /// Reinstall + sign-in: nothing local, a real saved row → restore it, exactly as saved.
    @Test func reinstallRestoresTheSavedRowVerbatim() {
        let saved = snapshot(dayBefore: true, lineupPosted: true, kickoff: true, goals: false,
                             halftime: true, fullTime: true, liveActivitiesEnabled: true)
        let decision = NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: allOff, server: saved, teamBellsOn: 2)

        #expect(decision == .restore(saved))
        if case .restore(let restored) = decision {
            #expect(!restored.goals)     // the deliberately-off type survives the round trip
        }
    }

    /// Reinstall + sign-in with NO saved row (new account, or the row this bug already flattened),
    /// but restored team bells → cascade, so the bells can't sit on with every type off.
    @Test func reinstallWithBellsButNoSavedRowCascades() {
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: allOff, server: nil, teamBellsOn: 2) == .cascade)
    }

    /// An all-off saved row is indistinguishable from "never chose anything" — fall through to the
    /// bell invariant rather than restoring a row that would leave the user with nothing.
    @Test func allOffSavedRowWithBellsCascades() {
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: allOff, server: allOff, teamBellsOn: 1) == .cascade)
    }

    /// Reinstall, nothing saved, no bells → do NOTHING. Pure opt-in: a sign-in alone must never
    /// turn on a notification (owner rule, no dark patterns).
    @Test func reinstallWithNothingAnywhereDoesNothing() {
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: allOff, server: nil, teamBellsOn: 0) == .noRestore)
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: allOff, server: allOff, teamBellsOn: 0) == .noRestore)
    }

    // MARK: - Device-authoritative (must NOT pull from the server)

    /// The involuntary-sign-out contract: a sign-out PRESERVES the toggles + the sentinel, so
    /// signing back in restores the exact prior selection locally — no server pull, no re-cascade.
    @Test func returningUserIsDeviceAuthoritative() {
        let saved = snapshot(kickoff: true, goals: true, halftime: true, fullTime: true)
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: true, local: allOff, server: saved, teamBellsOn: 2) == .noRestore)
    }

    /// Any local toggle on ⇒ this install has state worth keeping, even if the sentinel somehow
    /// isn't set (a Tier-1-only user who turned on the day-before reminder without a bell).
    @Test func anyLocalToggleOnBlocksTheRestore() {
        let saved = snapshot(kickoff: true, goals: true)
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: snapshot(dayBefore: true), server: saved,
            teamBellsOn: 0) == .noRestore)
    }

    /// REGRESSION (sim-caught 2026-07-22): the restore must only ever engage on a device with
    /// NOTHING to lose. The first cut gated every prefs push behind "the restore finished for this
    /// identity", which blocked syncing for a whole session on a device that had real toggles — the
    /// user's newly-enabled alert types never reached Supabase, so the next reinstall found an empty
    /// row and fell through to the cascade. `needsRestore` (the sync-side gate) is exactly the
    /// `.noRestore` condition below, so any state that decides `.noRestore` also pushes freely.
    @Test func deviceWithStateNeverEngagesTheRestore() {
        let saved = snapshot(kickoff: true, goals: true)
        // Sentinel set, nothing on (the just-signed-out user): no restore ⇒ no gated push.
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: true, local: allOff, server: saved, teamBellsOn: 2) == .noRestore)
        // Toggles on, sentinel somehow clear: still device-authoritative.
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: false, local: snapshot(kickoff: true), server: saved,
            teamBellsOn: 2) == .noRestore)
    }

    /// Belt-and-braces: a device that has cascaded is never re-cascaded by the bell invariant,
    /// no matter how many bells come back.
    @Test func cascadedDeviceIsNotReCascaded() {
        #expect(NotificationSyncCoordinator.decideRestore(
            hasAppliedDefaults: true, local: allOff, server: nil, teamBellsOn: 5) == .noRestore)
    }
}

/// The bell → bundle invariant (`shouldCascadeBundle`).
///
/// ⚠️ Untested until 2026-08-03, and now load-bearing: with the bell RESTORE removed, bells arrive
/// only from a deliberate tap, so this predicate is the sole thing standing between "user turned a
/// bell on" and the banned state "bell reads ON but no server-push type is enabled, so nothing can
/// ever fire."
@Suite("Alert bundle cascade")
struct CascadeBundleTests {

    @Test func firstBellTapCascadesTheBundle() {
        // The canonical path: fresh device, user taps a team bell, no types set yet.
        #expect(NotificationSyncCoordinator.shouldCascadeBundle(
            hasAppliedDefaults: false, teamBellsOn: 1, anyServerPushEnabled: false))
    }

    @Test func noBellsMeansNoCascade() {
        // Nothing to apply types TO — this is the state a reinstall now lands in, and it must stay
        // quiet rather than enabling anything on its own.
        #expect(!NotificationSyncCoordinator.shouldCascadeBundle(
            hasAppliedDefaults: false, teamBellsOn: 0, anyServerPushEnabled: false))
    }

    @Test func neverCascadesOverAnExistingSelection() {
        // Signing in via a "Match updates" tap enables those columns without the sentinel. Blanket-
        // enabling Goals/Lineups/Live Activities on top would be the app choosing for the user.
        #expect(!NotificationSyncCoordinator.shouldCascadeBundle(
            hasAppliedDefaults: false, teamBellsOn: 1, anyServerPushEnabled: true))
    }

    @Test func neverCascadesTwice() {
        // Once applied, a user who deliberately turned types back OFF keeps their edits.
        #expect(!NotificationSyncCoordinator.shouldCascadeBundle(
            hasAppliedDefaults: true, teamBellsOn: 3, anyServerPushEnabled: false))
    }

    @Test func onboardingBellStillCascadesAtSignIn() {
        // The onboarding bell sets ONLY the Tier-1 day-before reminder by design, so no server-push
        // type is on — which is precisely why the predicate keys on `anyServerPushEnabled` rather
        // than `anyEnabled`. Reading it the other way would leave onboarding users with a bell and
        // no match alerts.
        #expect(NotificationSyncCoordinator.shouldCascadeBundle(
            hasAppliedDefaults: false, teamBellsOn: 1, anyServerPushEnabled: false))
    }
}
