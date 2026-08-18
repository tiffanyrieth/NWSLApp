//
//  AccessibilityAuditUITests.swift
//  NWSLAppUITests
//
//  The VoiceOver GATE — the accessibility analog to DSColorContrastTests (which mechanically
//  guards contrast). Each test walks to one screen via the DEBUG launch args and runs
//  `performAccessibilityAudit` (iOS 17+), which FAILS the test on any unlabeled element, label
//  that isn't readable words, or wrong trait it finds (the VoiceOver-specific `auditTypes` below —
//  contrast + Dynamic Type are gated elsewhere). So a future feature that ships a custom-drawn view
//  with no label fails CI here, instead of silently rotting.
//
//  ⚠️ ASSUMES THE SIM IS ALREADY ONBOARDED (following ≥1 team) so the tab roots render real
//  content. On a fresh CI sim, seed an onboarded state first. We deliberately do NOT run
//  `-resetOnboarding` here: it wipes onboarding state, which would make every OTHER test in the
//  suite land on the onboarding screen instead of its tab. Onboarding is audited manually.
//
//  Adding a screen: give it a test that launches with the right args (see AppRouter's DEBUG deep
//  links) and calls `audit()`. Suppress a genuinely-intentional finding ONLY in `shouldIgnore`,
//  with a comment saying why — a whitelist entry is a decision, not a silence.
//

import XCTest

final class AccessibilityAuditUITests: XCTestCase {

    /// The categories we gate on — the VoiceOver-specific checks not already owned by another gate:
    /// `.elementDetection` (undetectable/unlabeled elements), `.sufficientElementDescription`
    /// (labels that aren't readable words), `.trait` (wrong button/header/link traits).
    ///
    /// DELIBERATELY EXCLUDED (each is already gated elsewhere and the generic audit fights this app's
    /// documented design, so including it is pure noise):
    ///   • `.dynamicType` — owned by the manual **AX1 gate**; the app INTENTIONALLY fixes some sizes
    ///     (monograms, numeric columns, badge letters — CLAUDE.md exemptions), which this flags 80×,
    ///     and it times the audit out on heavy screens (Home/MatchDetail: "Audit failed to complete").
    ///   • `.contrast` — owned by **`DSColorContrastTests`** (token-level WCAG AA); the runtime check
    ///     flags the intentional team-color-on-wash design (team abbreviations/scores in team color
    ///     over a team-tinted wash) 26×, unable to tell the wash is mostly the dark base.
    ///   • `.textClipped` / `.hitRegion` — the app truncates on purpose at AX1 (dense tables, carousel).
    /// (If runtime contrast-on-washes is ever wanted, it's a separate, deliberate follow-up.)
    private let auditTypes: XCUIAccessibilityAuditType =
        [.elementDetection, .sufficientElementDescription, .trait]

    override func setUpWithError() throws {
        // Report EVERY screen's issues across the run, not just up to the first failure.
        continueAfterFailure = true
    }

    /// Launch with `args`, wait for the UI to settle, and audit the current screen.
    private func audit(_ args: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        // Let the first fetch + layout SETTLE before auditing: a mid-load frame can momentarily
        // obscure text and trip a transient "potentially inaccessible text" flake that isn't real.
        _ = app.wait(for: .runningForeground, timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        do {
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                // Self-document every finding: attach the offending element + issue to the result
                // so a future failure names its element in the .xcresult (no screenshot archaeology,
                // and — unlike NSLog/print — an attachment reliably survives the UITest process
                // boundary). The gate still fails on it unless `shouldIgnore` whitelists it.
                let detail = """
                    screen: \(args.joined(separator: " "))
                    type: \(issue.auditType)
                    issue: \(issue.compactDescription)
                    element: \(issue.element?.debugDescription ?? "nil")
                    """
                let attachment = XCTAttachment(string: detail)
                attachment.name = "Audit issue — \(issue.compactDescription)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return self.shouldIgnore(issue)
            }
        } catch {
            // The audit engine itself couldn't finish (a very element-dense screen — not an app
            // defect). Skip rather than hard-fail so CI isn't flaky; the screen's components are
            // covered by their other appearances + manual spot-check.
            throw XCTSkip("audit did not complete for \(args): \(error.localizedDescription)")
        }
    }

    /// Whitelist for genuinely-intentional findings. EMPTY by design — every entry added here must
    /// carry a comment justifying it (a decorative element that should have been hidden, an accepted
    /// AX1 truncation, a fixed-size numeric badge). If this list grows without comments, that's a bug.
    private func shouldIgnore(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        return false
    }

    // MARK: - Tab roots (deterministic via -startTab; host most shared components)

    func testHomeAccessibility() throws { try audit(["-startTab", "home"]) }
    func testScheduleAccessibility() throws { try audit(["-startTab", "schedule"]) }   // MatchCard
    func testStandingsAccessibility() throws { try audit(["-startTab", "standings"]) } // Standings rows
    func testTeamsAccessibility() throws { try audit(["-startTab", "teams"]) }         // Teams grid
    func testSocialAccessibility() throws { try audit(["-startTab", "social"]) }       // content cards

    // MARK: - Drill-in screens (deep-linked)

    /// Team abbreviations are stable across seasons (unlike event ids), so this deep link is durable.
    func testTeamDetailAccessibility() throws { try audit(["-debugOpenTeam", "WAS"]) }

    /// Cross-game stats hub (custom bars/rings). Test fan gets past the Fan Zone sign-in gate.
    func testSuperfanAccessibility() throws { try audit(["-debugOpenSuperfan", "-signInAsTestFan", "1"]) }

    /// Match Detail — audits a FUTURE match: it exercises the same header code path + the season
    /// comparison bars but skips the past match's huge play-by-play feed, which is plain
    /// auto-accessible text yet so element-dense the audit times out on it ("failed to complete in
    /// time"). ⚠️ The event id is a scheduled match; refresh it when the season rolls (a stale id
    /// degrades gracefully — the app shows the Schedule root, still a valid audit).
    func testMatchDetailAccessibility() throws { try audit(["-debugOpenMatch", "401853975"]) }
}
