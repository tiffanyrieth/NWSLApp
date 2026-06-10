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
//  Reuses SignInPromptView's half-sheet shape (Apple button + "Not now"). The
//  toggle has already flipped on and persisted intent locally; signing in just
//  lets that intent reach the server so the alert can actually be delivered.
//  Declining leaves the toggle on but undelivered — honest, not broken.
//

import AuthenticationServices
import SwiftUI

struct NotificationAuthPromptView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 10) {
                Text("Sign in for live alerts")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Live game alerts are sent from our servers to your phone the moment they happen — so we need to know it's your device. Sign in with Apple keeps it private; we only store your team follows and alert settings.")
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
            // Signed in — NotificationSyncCoordinator (watching auth.userID) now
            // pushes prefs + registers the device token. Close the sheet.
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
