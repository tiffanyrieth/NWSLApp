//
//  SignInPromptView.swift
//  NWSLApp
//
//  The single, skippable post-onboarding prompt: "save your picks across
//  devices." Presented once, ever, right after the user finishes the team
//  picker — the moment they've just invested effort, so "save your picks" has
//  obvious value (see Reference/Sessions/2026-06-09_supabase-accounts-setup §2).
//
//  Sign-in is entirely optional — "Not now" dismisses and the app works
//  identically on the local UserDefaults cache. We never nag: HomeView marks the
//  prompt seen when it presents this, so it can't reappear.
//
//  Uses Apple's official `SignInWithAppleButton` (required styling for App Store
//  compliance). AuthStore plugs into its two closures; on success the sheet
//  dismisses and FollowSyncCoordinator (watching AuthStore.currentUser) syncs the
//  freshly-picked follows up to Supabase.
//

import AuthenticationServices
import SwiftUI

struct SignInPromptView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 10) {
                Text("Save your picks across devices")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Sign in to keep your followed teams, game streaks, and alerts if you switch phones. You can always do this later.")
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
