//
//  NotificationAuthPromptView.swift
//  NWSLApp
//
//  The contextual, opt-in sign-in nudge for live (Tier 2 / server push) alerts.
//  Live game events — kickoff, goals, halftime, full-time — are sent from our
//  servers to the phone the moment they happen, so the server has to know which
//  device is yours: the APNs token + alert prefs live server-side, keyed to a
//  Supabase user (RLS-scoped, like follows). That makes sign-in a real requirement
//  for Tier 2 — but not a front-door gate. The app stays fully browseable and
//  Tier-1 local reminders work signed-out; this appears only when the user flips
//  on a live alert, with an honest "why" before the Apple sheet (the "Swift Alert"
//  pattern, not the "ESPN wall").
//
//  A half-sheet sign-in shape (Apple button + "Not now") — this is the Tier-2 push
//  prompt, SEPARATE from the Fan Zone gate (FanZoneGate, which is no-skip). v2 gate
//  contract: the toggle has NOT flipped yet — it stays off until sign-in succeeds.
//  On success we call `onSignedIn` (the caller flips the toggle on + requests iOS
//  permission), then dismiss. "Not now" leaves the toggle off — honest: a live alert
//  genuinely can't be delivered without an account, so we don't fake an on state.
//

import AuthenticationServices
import SwiftUI

struct NotificationAuthPromptView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    /// Invoked after sign-in succeeds, before dismiss — the caller flips the pending
    /// Tier-2 toggle on and requests notification permission. Defaults to a no-op so
    /// older call sites (if any) still compile.
    var onSignedIn: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .dsFont(52)
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 10) {
                Text("Live alerts need a sign-in")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("These run through Apple's notification system, which needs a signed-in account to know where to send them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    auth.configureSignInRequest(request)
                } onCompletion: { result in
                    Task { await complete(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Not now") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(false)
    }

    private func complete(_ result: Result<ASAuthorization, Error>) async {
        do {
            try await auth.handleSignIn(result)
            // Signed in — flip the pending toggle on + request permission (the
            // caller's job), then close. NotificationSyncCoordinator (watching
            // auth.userID) pushes prefs + registers the device token.
            onSignedIn()
            dismiss()
        } catch {
            // User-cancelled is expected — don't surface it as an error.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = "Sign in didn't complete. You can try again later."
        }
    }
}
