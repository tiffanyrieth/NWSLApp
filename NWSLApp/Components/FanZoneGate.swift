//
//  FanZoneGate.swift
//  NWSLApp
//
//  The MANDATORY sign-in + display-name gate for Fan Zone games. The model: browse the
//  rules/fixtures freely, but the moment you ACT (make your picks / make a prediction /
//  submit your first trivia answer) you must be signed in with a chosen display name, so
//  your score actually counts on the leaderboard. There is no skip — the only escape is
//  "Go back", which cancels the action and returns you to browsing. This replaces the old
//  skippable model (FanZoneIntroView's one-time invite + an at-submit "Not now" prompt),
//  under which users could fully play and submit signed-out and their results went nowhere.
//
//  Usage: `.fanZoneGate(isRequested: $flag, gameName: "Bracket Battle") { <run the action> }`.
//  Flip `isRequested` true when the user acts; `onAuthorized` runs exactly once they're
//  signed in AND named — immediately (no sheet) if they already are; otherwise after the
//  Sign-in → Display-name steps complete. Backing out never runs `onAuthorized`.
//
//  The display-name field (`DisplayNameEntry`) is shared with the Profile editor so the
//  first-time setup and later edits look + validate identically.
//

import AuthenticationServices
import SwiftUI

// MARK: - Shared display-name entry (gate's name step + Profile editor)

/// The display-name text field + helper + CTA, reused by the gate and Profile. Required:
/// the CTA disables on an empty/whitespace name. Saving routes through
/// `AuthStore.updateDisplayName` (trims, 20-char cap, UserDefaults + `profiles` upsert).
struct DisplayNameEntry: View {
    @Binding var draft: String
    let cta: String
    let accent: Color
    let onSubmit: () -> Void

    private var isValid: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display name")
                .dsFont(12, weight: .medium)
                .foregroundStyle(Color.dsFgSecondary)
                .padding(.leading, 2)

            TextField("Enter a name…", text: $draft)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { if isValid { onSubmit() } }
                .dsFont(17)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgTertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))

            Text("Max 20 characters · visible to other players · change anytime in Profile")
                .dsFont(12)
                .foregroundStyle(Color.dsFgTertiary)
                .padding(.leading, 2)

            Button(action: onSubmit) {
                Text(cta)
                    .dsFont(17, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(isValid ? accent : Color.dsBgTertiary,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!isValid)
            .padding(.top, 4)
        }
    }
}

// MARK: - "Playing as {name}" badge (Screen C)

/// A subtle accent line shown in a game once the player is gated in (signed in + named),
/// per the handoff's "Playing as {displayName}" Screen C. Renders nothing when signed out.
struct PlayingAsBadge: View {
    @Environment(AuthStore.self) private var auth
    let accent: Color

    var body: some View {
        if auth.isSignedIn, auth.hasDisplayName, let name = auth.displayName {
            Text("Playing as \(name)")
                .dsFont(12, weight: .semibold)
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - The gate sheet (Sign in → Display name)

struct FanZoneGateSheet: View {
    enum Step: String, Identifiable { case signIn, name; var id: String { rawValue } }

    let gameName: String
    /// Called when the user finishes (signed in + named) — the modifier flips its
    /// `completed` flag; the sheet then dismisses itself and the modifier runs the action.
    let onComplete: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var draftName: String
    @State private var errorMessage: String?
    @State private var saving = false

    init(gameName: String, startAt: Step, prefilledName: String, onComplete: @escaping () -> Void) {
        self.gameName = gameName
        self.onComplete = onComplete
        _step = State(initialValue: startAt)
        _draftName = State(initialValue: prefilledName)
    }

    var body: some View {
        VStack(spacing: 22) {
            switch step {
            case .signIn: signInStep
            case .name:   nameStep
            }
        }
        .padding(28)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(true)   // no swipe-away — choose "Go back" or sign in
        // Trigger Apple's Game Center opt-in alongside (achievements + avatar); idempotent.
        .task { GameCenterManager.shared.authenticate() }
    }

    // Step A — no-skip sign-in
    private var signInStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .dsFont(44)
                .foregroundStyle(Color.dsGameBracket)
            VStack(spacing: 10) {
                Text("Sign in to play")
                    .dsFont(24, weight: .bold)
                    .multilineTextAlignment(.center)
                Text("\(gameName) is a ranked game — your picks are scored against the league. Sign in so your points count on the leaderboard.")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .dsFont(20)
                    .foregroundStyle(Color.dsGameBracket)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your score. Your rank. Real competition.")
                        .dsFont(13, weight: .semibold).foregroundStyle(.white)
                    Text("See how you stack up against every fan in the league.")
                        .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color.dsGameBracket.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.dsGameBracket.opacity(0.25)))

            if let errorMessage {
                Text(errorMessage)
                    .dsFont(13)
                    .foregroundStyle(Color.dsError)
                    .multilineTextAlignment(.center)
            }

            SignInWithAppleButton(.signIn) { request in
                auth.configureSignInRequest(request)
            } onCompletion: { result in
                Task { await handleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button("Go back to rules") { dismiss() }   // cancels the action — NOT a skip-and-play
                .dsFont(15, weight: .semibold)
                .foregroundStyle(Color.dsFgSecondary)
        }
    }

    // Step B — required display name
    private var nameStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .dsFont(48)
                .foregroundStyle(Color.dsSuccess)
            VStack(spacing: 8) {
                Text("You're in! Choose your name.")
                    .dsFont(22, weight: .bold)
                    .multilineTextAlignment(.center)
                Text("This is how you'll appear on the leaderboard. Make it good — other fans will see this.")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
            }
            DisplayNameEntry(draft: $draftName,
                             cta: saving ? "Saving…" : "Let's go",
                             accent: Color.dsGameBracket) {
                Task { await saveName() }
            }
            Text("A display name is required to play ranked games")
                .dsFont(11)
                .foregroundStyle(Color.dsFgTertiary)
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            try await auth.handleSignIn(result)
            // Always confirm/choose the name after a fresh sign-in (Apple's value prefills).
            draftName = auth.displayName ?? ""
            step = .name
        } catch {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            errorMessage = "Sign in didn't complete. Try again."
        }
    }

    private func saveName() async {
        guard !saving else { return }
        saving = true
        await auth.updateDisplayName(draftName)
        saving = false
        onComplete()
        dismiss()
    }
}

// MARK: - The gate modifier

extension View {
    /// Gate a Fan Zone action behind mandatory sign-in + a chosen display name. Flip
    /// `isRequested` true when the user acts; `onAuthorized` runs once they're signed in
    /// AND named (immediately, no sheet, if they already are). Backing out cancels.
    func fanZoneGate(isRequested: Binding<Bool>, gameName: String,
                     onAuthorized: @escaping () -> Void) -> some View {
        modifier(FanZoneGateModifier(isRequested: isRequested, gameName: gameName,
                                     onAuthorized: onAuthorized))
    }
}

private struct FanZoneGateModifier: ViewModifier {
    @Binding var isRequested: Bool
    let gameName: String
    let onAuthorized: () -> Void

    @Environment(AuthStore.self) private var auth
    @State private var step: FanZoneGateSheet.Step?
    @State private var completed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                if auth.isSignedIn && auth.hasDisplayName {
                    isRequested = false
                    onAuthorized()                       // already ready — run now, no sheet
                } else {
                    step = auth.isSignedIn ? .name : .signIn
                }
            }
            .sheet(item: $step, onDismiss: {
                isRequested = false
                if completed { completed = false; onAuthorized() }
            }) { startAt in
                FanZoneGateSheet(gameName: gameName, startAt: startAt,
                                 prefilledName: auth.displayName ?? "") {
                    completed = true
                }
            }
    }
}
