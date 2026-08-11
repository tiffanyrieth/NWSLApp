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
//  Usage: `.fanZoneGate(isRequested: $flag, gameName: "The Bracket") { <run the action> }`.
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

/// The display-name text field + helper + CTA, reused by the gate and Profile so first-time setup and
/// later edits look + validate identically. Self-contained (2026-08-06): it runs a debounced
/// availability/filter check as you type (`AuthStore.checkDisplayName`) for live "available / taken /
/// not allowed" feedback, and saves via `AuthStore.updateDisplayName` — the atomic server guard that
/// enforces uniqueness + the filter and cascades the name onto the boards. It commits nothing locally
/// until the server confirms, surfaces a thrown `DisplayNameError` inline, and calls `onSaved` ONLY on
/// success (so the caller dismisses / advances the gate only when the name really took).
struct DisplayNameEntry: View {
    @Binding var draft: String
    let cta: String
    let accent: Color
    /// Runs only after the name SAVES successfully (dismiss the editor / advance the gate).
    let onSaved: () -> Void

    @Environment(AuthStore.self) private var auth

    private enum CheckState: Equatable { case idle, checking, available, error(DisplayNameError) }
    @State private var check: CheckState = .idle
    @State private var checkTask: Task<Void, Never>?
    @State private var saving = false
    @State private var saveError: String?

    /// 2–20 characters after trimming — see `DisplayNameRules` (shared with the store).
    private var isValid: Bool { DisplayNameRules.isValid(draft) }
    /// Block submit only on a KNOWN-bad name; an in-flight/absent check still lets you try — the save
    /// re-guards, so a flaky pre-check never traps a valid name.
    private var canSubmit: Bool {
        guard isValid, !saving else { return false }
        if case .error = check { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Username")
                .dsFont(12, weight: .medium)
                .foregroundStyle(Color.dsFgSecondary)
                .padding(.leading, 2)

            TextField("Enter a username…", text: $draft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { submit() }
                .dsFont(17)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgTertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
                .onChange(of: draft) { _, newValue in scheduleCheck(newValue) }

            statusLine
                .frame(minHeight: 16, alignment: .leading)   // reserve the line so the CTA doesn't jump

            Button(action: submit) {
                Text(saving ? "Saving…" : cta)
                    .dsFont(17, weight: .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canSubmit ? accent : Color.dsBgTertiary,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!canSubmit)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let saveError {
            statusLabel(saveError, color: Color.dsError, icon: "exclamationmark.circle.fill")
        } else {
            switch check {
            case .idle:
                Text("2–20 characters · visible to other players · change anytime in Profile")
                    .dsFont(12).foregroundStyle(Color.dsFgSecondary).padding(.leading, 2)
            case .checking:
                statusLabel("Checking…", color: Color.dsFgSecondary, icon: nil)
            case .available:
                statusLabel("That username's available", color: Color.dsSuccess, icon: "checkmark.circle.fill")
            case .error(let refusal):
                statusLabel(refusal.message, color: Color.dsError, icon: "exclamationmark.circle.fill")
            }
        }
    }

    private func statusLabel(_ text: String, color: Color, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).dsFont(12) }
            Text(text).dsFont(12)
        }
        .foregroundStyle(color)
        .padding(.leading, 2)
    }

    /// Debounced live check: cancel any in-flight check, wait, then ask the server. Advisory only —
    /// a nil (offline) leaves the line neutral; the save is the real guard.
    private func scheduleCheck(_ value: String) {
        saveError = nil
        checkTask?.cancel()
        guard DisplayNameRules.isValid(value) else { check = .idle; return }
        check = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let status = await auth.checkDisplayName(value)
            guard !Task.isCancelled, value == draft else { return }   // drop a stale response
            guard let status else { check = .idle; return }
            check = DisplayNameError.from(status: status).map(CheckState.error) ?? .available
        }
    }

    private func submit() {
        guard canSubmit else { return }
        saving = true
        saveError = nil
        Task {
            do {
                try await auth.updateDisplayName(draft)
                saving = false
                onSaved()
            } catch {
                saving = false
                let refusal = (error as? DisplayNameError) ?? .saveFailed
                // taken/blocked also refresh the inline status so the field itself flags the problem.
                if refusal == .taken || refusal == .blocked { check = .error(refusal) }
                saveError = refusal.message
            }
        }
    }
}

// MARK: - Display-name editor sheet (Profile + in-game "Playing as" tap)

/// The "edit your leaderboard name" sheet — the ONE editor used by Profile and by tapping
/// "Playing as {name}" in a game's nav. Wraps DisplayNameEntry with edit chrome; saves via
/// `AuthStore.updateDisplayName`. Seeded with the current name (no empty flash).
struct DisplayNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(currentName: String) { _draft = State(initialValue: currentName) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("This is how you appear on the Fan Zone leaderboards.")
                    .dsFont(13)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
                DisplayNameEntry(draft: $draft, cta: "Save", accent: Color.dsAccent) {
                    dismiss()   // only fires on a SUCCESSFUL save; errors stay inline in the field
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBgGrouped)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Username").dsFont(17, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - "Playing as {name}" badge (Screen C)

/// The "Playing as {name}" identity shown TOP-RIGHT in a game's nav bar once the player is
/// gated in (signed in + named), per the handoff's Screen C — "Playing as" in secondary, the
/// name in the game accent. Renders nothing when signed out, so a browsing player sees a clean nav.
struct PlayingAsBadge: View {
    @Environment(AuthStore.self) private var auth
    let accent: Color
    @State private var showEditor = false

    var body: some View {
        if auth.isSignedIn, auth.hasChosenName, let name = auth.displayName {
            Button { showEditor = true } label: {
                (Text("Playing as ").foregroundStyle(Color.dsFgSecondary)
                 + Text(name).foregroundStyle(accent).fontWeight(.semibold))
                    .dsFont(12)
                    // Take the width the full 2–20 char name needs — keep the nav bar
                    // from compressing/truncating it to one squeezed line.
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            // Tap to change your leaderboard name right here — the same editor as Profile.
            .sheet(isPresented: $showEditor) { DisplayNameEditorSheet(currentName: name) }
        }
    }
}

/// In-content variant of `PlayingAsBadge` — a right-aligned strip at the TOP of a game screen's
/// scroll content (below the nav bar). Keeps the "Playing as {name}" affordance OUT of the nav
/// bar, whose variable-width trailing item knocked the centered inline title off-center (the title
/// drifted per game — "Know Her Game" left, "NWSL Trivia" right, etc.). No reserved space when
/// signed out. Apply via `.fanZonePlayingAsHeader(accent:)`.
struct PlayingAsRow: View {
    @Environment(AuthStore.self) private var auth
    let accent: Color

    var body: some View {
        if auth.isSignedIn, auth.hasChosenName {
            HStack(spacing: 0) {
                Spacer()
                PlayingAsBadge(accent: accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            // Small: the scroll content it sits above brings its own top padding.
            .padding(.bottom, 4)
        }
    }
}

extension View {
    /// Put the "Playing as {name}" chip at the top of a Fan Zone game screen's SCROLL CONTENT —
    /// apply to the outermost view INSIDE the `ScrollView`, after that content's own padding.
    ///
    /// It scrolls away with the content by design. It was a `safeAreaInset` (pinned below the nav
    /// bar), which insets the scroll view's safe area but lets the content scroll UNDER it — so
    /// headlines and body text visibly passed behind the chip on every game screen. It's an identity
    /// stamp, not a control, so it has no reason to persist; putting it in the content also avoids a
    /// permanent opaque band reading as a second toolbar. Still out of the nav bar, so the centered
    /// `nativeBackButton` title stays centered.
    /// `accent` is optional so a surface that deliberately omits the chip (a modal read of a game,
    /// e.g. Bracket's "See the full bracket" sheet) can say so at the call site without branching
    /// its whole view body.
    func fanZonePlayingAsHeader(accent: Color?) -> some View {
        VStack(spacing: 0) {
            if let accent { PlayingAsRow(accent: accent) }
            self
        }
    }
}

// MARK: - The gate sheet (Sign in → Display name)

struct FanZoneGateSheet: View {
    enum Step: String, Identifiable { case signIn, name; var id: String { rawValue } }

    let gameName: String
    /// The tapped game's accent, so the gate tints to that game (not a hardcoded teal).
    let accent: Color
    /// Called when the user finishes (signed in + named) — the modifier flips its
    /// `completed` flag; the sheet then dismisses itself and the modifier runs the action.
    let onComplete: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var draftName: String
    @State private var errorMessage: String?

    init(gameName: String, accent: Color, startAt: Step, prefilledName: String, onComplete: @escaping () -> Void) {
        self.gameName = gameName
        self.accent = accent
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
                .foregroundStyle(accent)
            VStack(spacing: 10) {
                Text("Sign in to play")
                    .dsFont(24, weight: .bold)
                    .multilineTextAlignment(.center)
                Text("\(gameName) is scored. Sign in so your results count — on the leaderboards and in the community stats.")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .dsFont(20)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your results count.")
                        .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                    Text("Your points on the leaderboards, your answers in the community stats — see how you compare across the league.")
                        .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.25)))

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
                Text("You're in! Pick a username.")
                    .dsFont(22, weight: .bold)
                    .multilineTextAlignment(.center)
                Text("This is how you'll appear across Fan Zone — leaderboards and community stats. Make it good — other fans will see this.")
                    .dsFont(15)
                    .foregroundStyle(Color.dsFgSecondary)
                    .multilineTextAlignment(.center)
            }
            DisplayNameEntry(draft: $draftName, cta: "Let's go", accent: accent) {
                onComplete()   // fires only on a SUCCESSFUL save; a taken/blocked name stays inline
                dismiss()
            }
            Text("A username is required to play Fan Zone games")
                .dsFont(12)
                .foregroundStyle(Color.dsFgSecondary)
        }
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            try await auth.handleSignIn(result)
            // Require a username after a fresh sign-in. New users start blank (we don't pull a name
            // from Apple); a returning user's chosen username is prefilled so they can keep or edit it.
            draftName = auth.displayName ?? ""
            step = .name
        } catch {
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            errorMessage = "Sign in didn't complete. Try again."
        }
    }
}

// MARK: - The gate modifier

extension View {
    /// Gate a Fan Zone action behind mandatory sign-in + a chosen display name. Flip
    /// `isRequested` true when the user acts; `onAuthorized` runs once they're signed in
    /// AND named (immediately, no sheet, if they already are). Backing out cancels.
    /// `accent` tints the gate to the tapped game (defaults to the app accent).
    func fanZoneGate(isRequested: Binding<Bool>, gameName: String, accent: Color = .dsAccent,
                     onAuthorized: @escaping () -> Void) -> some View {
        modifier(FanZoneGateModifier(isRequested: isRequested, gameName: gameName,
                                     accent: accent, onAuthorized: onAuthorized))
    }
}

private struct FanZoneGateModifier: ViewModifier {
    @Binding var isRequested: Bool
    let gameName: String
    let accent: Color
    let onAuthorized: () -> Void

    @Environment(AuthStore.self) private var auth
    @State private var step: FanZoneGateSheet.Step?
    @State private var completed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                switch FanZoneGateDecision.resolve(isSignedIn: auth.isSignedIn,
                                                   hasChosenName: auth.hasChosenName) {
                case .runNow:
                    isRequested = false
                    onAuthorized()                       // already ready — run now, no sheet
                case .nameStep:
                    // Signed in but name not yet CONFIRMED (e.g. an unconfirmed Apple name) → the
                    // name step still runs so it's confirmed before it reaches a leaderboard.
                    step = .name
                case .signInStep:
                    step = .signIn
                }
            }
            .sheet(item: $step, onDismiss: {
                isRequested = false
                if completed { completed = false; onAuthorized() }
            }) { startAt in
                FanZoneGateSheet(gameName: gameName, accent: accent, startAt: startAt,
                                 prefilledName: auth.displayName ?? "") {
                    completed = true
                }
            }
    }
}
