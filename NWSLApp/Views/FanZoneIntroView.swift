//
//  FanZoneIntroView.swift
//  NWSLApp
//
//  The optional, one-time "set up your Fan Zone profile" invite, shown the first time a
//  SIGNED-OUT player opens any Fan Zone game (Trivia / Predict / Bracket). It's an INVITATION,
//  not a wall: the game is right there behind the sheet, and "Maybe later" dismisses straight
//  into play. Signing in saves scores, puts you on the cross-fan leaderboards, and lets you
//  choose how your name appears; it also triggers Apple's Game Center opt-in (achievements +
//  avatar — Apple owns that flow). Tester feedback: present this up front so identity is set
//  before playing, but keep it skippable so a forced login never makes someone bounce.
//
//  Presentation is owned by the `.fanZoneIntro()` modifier (applied to each game in
//  HomeView.destination), gated one-time by `@AppStorage("fanZone.introSeen")` and never shown
//  to an already-signed-in player. Rollback = drop `.fanZoneIntro()` from the destinations and
//  delete this file; the at-submit sign-in prompts remain.
//

import AuthenticationServices
import SwiftUI

/// Process-lived flag: the user dismissed the up-front invite WITHOUT signing in, this app run.
/// The Trivia/Predict at-submit prompts check it so a skipper isn't shown a SECOND sign-in modal
/// in the same session (next launch, the contextual at-submit nudge returns).
@MainActor
final class FanZoneIntro {
    static let shared = FanZoneIntro()
    private init() {}
    var declinedThisSession = false
}

struct FanZoneIntroView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var draftName = ""
    /// After a successful sign-in we swap to the one-line "how should your name show?" step.
    @State private var showNameStep = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            if showNameStep { nameStep } else { introStep }
            Spacer(minLength: 0)
        }
        .padding(28)
        .presentationDetents([.medium])
        // Trigger Apple's Game Center opt-in (achievements + avatar) up front — idempotent,
        // and Apple presents/owns that UI. Independent of Sign in with Apple below.
        .task { GameCenterManager.shared.authenticate() }
    }

    // MARK: - Step 1: the invite

    private var introStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "gamecontroller.fill")
                .dsFont(48)
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 10) {
                Text("Set up your Fan Zone profile")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Sign in to save your scores, compete on the leaderboards, and choose how your name appears. You can always play without an account.")
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

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    auth.configureSignInRequest(request)
                } onCompletion: { result in
                    Task { await complete(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Maybe later") {
                    FanZoneIntro.shared.declinedThisSession = true
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: choose the leaderboard name (after sign-in)

    private var nameStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .dsFont(48)
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("How should your name show?")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("This is the name other fans see on the leaderboards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("Name", text: $draftName)
                .textInputAutocapitalization(.words)
                .multilineTextAlignment(.center)
                .font(.headline)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.dsBgCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button("Continue") {
                Task {
                    await auth.updateDisplayName(draftName)
                    dismiss()
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func complete(_ result: Result<ASAuthorization, Error>) async {
        do {
            try await auth.handleSignIn(result)
            draftName = auth.displayName ?? ""
            showNameStep = true     // advance to the name step rather than dismissing
        } catch {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            errorMessage = "Sign in didn't complete. You can try again later."
        }
    }
}

// MARK: - Presentation modifier

extension View {
    /// Show the one-time Fan Zone sign-in invite on first appearance — only to a signed-out
    /// player who hasn't seen it. One-time (persisted) and never shown to a signed-in user.
    /// Applied to each game in `HomeView.destination` (outside the game's own body, so it doesn't
    /// collide with the game's existing sheets).
    func fanZoneIntro() -> some View { modifier(FanZoneIntroModifier()) }
}

private struct FanZoneIntroModifier: ViewModifier {
    @Environment(AuthStore.self) private var auth
    @AppStorage("fanZone.introSeen") private var introSeen = false
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !introSeen else { return }
                if auth.isSignedIn { introSeen = true }   // already set up → never show
                else { show = true }
            }
            .sheet(isPresented: $show, onDismiss: { introSeen = true }) {
                FanZoneIntroView()
            }
    }
}
