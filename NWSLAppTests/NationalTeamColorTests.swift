//
//  NationalTeamColorTests.swift
//  NWSLAppTests
//
//  Guards the national-team color parity added 2026-08-08: every NT the app can show
//  must resolve to a real color (not the neutral-gray fallback), matching the V2 Live
//  Activity — the bug was WAFCON cards (CIV/ALG/TAN…) rendering gray while NWSL washed,
//  which read as broken. Also locks the club-vs-national resolver split for the three
//  FIFA codes that collide with NWSL club abbreviations (CHI/DEN/POR).
//
//  ⚠️ These hexes mirror the watcher's NT_HEX (nwslapp-match-watcher/src/livestate.ts).
//  If a value here fails after a palette change, the two repos have drifted — resync them.
//

import Foundation
import Testing
@testable import NWSLApp

struct NationalTeamColorTests {

    // MARK: - The WAFCON codes that were rendering gray (the reported bug)

    @Test func previouslyGrayNationalTeamsNowResolve() {
        // None of these are followable NationalTeams or in the old 16-code opponent list,
        // so they resolved to nil (→ neutral gray) before the full NT_HEX sync.
        #expect(DesignTeamColors.nationalDisplayHex(for: "CIV") == "E89000")  // Côte d'Ivoire
        #expect(DesignTeamColors.nationalDisplayHex(for: "ALG") == "1E9E57")  // Algeria
        #expect(DesignTeamColors.nationalDisplayHex(for: "TAN") == "00A3DD")  // Tanzania
        #expect(DesignTeamColors.nationalDisplayHex(for: "RSA") == "1E9E57")  // South Africa
    }

    @Test func nonCollidingNTAlsoResolvesViaClubFirstPath() {
        // A non-colliding NT code must wash even through the club-first resolver, so an NT card
        // colors correctly regardless of whether isNational is threaded through.
        #expect(DesignTeamColors.displayHex(for: "CIV") == "E89000")
        #expect(DesignTeamColors.displayHex(for: "ALG") == "1E9E57")
    }

    // MARK: - The three collisions: FIFA code == NWSL club abbreviation

    @Test func collidingCodesResolveNationalFirstForNTMatches() {
        // In a national-team match the country must win.
        #expect(DesignTeamColors.nationalDisplayHex(for: "CHI") == "D42E12")  // Chile,   not Chicago
        #expect(DesignTeamColors.nationalDisplayHex(for: "DEN") == "D02A3E")  // Denmark, not Denver
        #expect(DesignTeamColors.nationalDisplayHex(for: "POR") == "DA291C")  // Portugal, not Portland
    }

    @Test func collidingCodesResolveClubFirstForClubMatches() {
        // The general (club-first) resolver still hands these to the NWSL clubs.
        #expect(DesignTeamColors.displayHex(for: "CHI") == "00A3E0")  // Chicago Stars
        #expect(DesignTeamColors.displayHex(for: "DEN") == "239E80")  // Denver Summit
        #expect(DesignTeamColors.displayHex(for: "POR") == "EF3340")  // Portland Thorns
    }

    @Test func caseInsensitiveAndUnknownCodes() {
        #expect(DesignTeamColors.nationalDisplayHex(for: "civ") == "E89000")   // lowercased
        #expect(DesignTeamColors.nationalDisplayHex(for: "ZZZ") == nil)        // unknown → gray
        #expect(DesignTeamColors.nationalDisplayHex(for: nil) == nil)
    }
}
