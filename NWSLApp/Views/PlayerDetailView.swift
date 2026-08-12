//
//  PlayerDetailView.swift
//  NWSLApp
//
//  Pushed when a player card in the Teams → Squad grid is tapped. It shows the
//  roster bio (jersey, position, age, height, nationality) and a season stat block
//  (appearances, goals/assists or, for keepers, clean sheets/saves).
//
//  The stat numbers are real ESPN Core API season totals (ESPNService.seasonStats),
//  passed in from TeamDetailView. They match the team-leaders board on
//  TeamDetailView, which is derived from the same lines.
//

import SwiftUI

struct PlayerDetailView: View {
    let athlete: Athlete
    /// The club's ESPN color hex, threaded down from TeamDetailView so the
    /// monogram matches the squad card the user tapped.
    let accentHex: String?
    /// The player's real season stats, threaded from TeamDetailView. nil only in
    /// the brief window before the roster/stats finish loading, or if the stats
    /// fetch couldn't reach this athlete (best-effort).
    let stats: PlayerSeasonStats?
    /// The season the stats are for, e.g. "NWSL SEASON 2026" (`AppConfig.seasonStatsLabel`). Names
    /// the competition because this page is also reached from NATIONAL-TEAM lineups, where the
    /// numbers are still the player's NWSL record — see that helper.
    let seasonLabel: String
    /// Second stat block for a NATIONAL-TEAM context: the player's line in THAT tournament
    /// (e.g. "WOMEN'S AFRICA CUP OF NATIONS 2026"). Rendered ABOVE the NWSL block — you tapped
    /// her in this tournament, so this tournament answers first. nil on every club path.
    var tournamentStats: PlayerSeasonStats? = nil
    var tournamentLabel: String? = nil

    var body: some View {
        let accent = Color.teamAccent(hex: accentHex)
        ScrollView {
            VStack(spacing: 0) {
                header(accent)

                VStack(spacing: 20) {
                    if !bioRows.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(bioRows.enumerated()), id: \.offset) { index, row in
                                HStack {
                                    Text(row.label).foregroundStyle(Color.dsFgSecondary)
                                    Spacer()
                                    Text(row.value).dsFont(16, weight: .medium).foregroundStyle(Color.dsFgPrimary)
                                }
                                .dsFont(16)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                if index < bioRows.count - 1 {
                                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                                }
                            }
                        }
                        .background(Color.dsBgCard)
                        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd))
                    }

                    if let tournamentStats, let tournamentLabel {
                        statsCard(tournamentStats, label: tournamentLabel)
                    }
                    if let stats {
                        statsCard(stats, label: seasonLabel)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.dsBgGrouped)
        // Bare ‹ chevron, no centered title — the full-bleed team-color header carries identity.
        // Transparent (not hidden) nav bar so the wash bleeds up behind it and edge-swipe survives.
        .nativeBackButton()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Full-bleed team-color header (mirrors TeamDetailView / MatchDetailView so a player
    // reads as belonging to their club — the crest/headshot sits over the club's color wash).

    private func header(_ accent: (fill: Color, on: Color)) -> some View {
        VStack(spacing: 12) {
            PlayerHeadshot(athleteID: athlete.id, size: 96, kind: .detail) {
                ZStack {
                    Circle().fill(accent.fill)
                    Text(monogram)
                        .dsFont(34, weight: .bold)
                        .foregroundStyle(accent.on)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(10)
                }
                .frame(width: 96, height: 96)
            }

            // ⚠️ Names here are NOT all "First Last". Reached from a national-team lineup,
            // this header renders whatever the federation registers — Egypt's WAFCON squad
            // carries the full patronymic chain ("Yassmin Mohamed Abdelaziz Hassanin"), and
            // ESPN's own payload genuinely repeats a token in "Maha Eldemerdash Eldemerdash
            // Shehata". With no horizontal bound those ran edge-to-edge, letters touching
            // both screen edges. Hence the explicit inset.
            //
            // ⚠️ Deliberately NO lineLimit and NO minimumScaleFactor: a name must WRAP, never
            // truncate or shrink. It's the one string on this screen that is a person's
            // identity, and "Yassmin Mohamed Abdelaziz…" is worse than three lines. It also
            // keeps the AX1 gate trivially satisfied — unlimited wrapping cannot lose a
            // character at any Dynamic Type size. Same for position ("Attacking Midfielder
            // Right" is a real ESPN value that needs two lines at AX1).
            VStack(spacing: 4) {
                Text(athlete.name)
                    .dsFont(22, weight: .bold)
                    .foregroundStyle(Color.dsFgPrimary)
                    .multilineTextAlignment(.center)
                if let position = athlete.positionName {
                    Text(position)
                        .dsFont(16)
                        .foregroundStyle(Color.dsFgSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(headerBackground(accent).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
        }
    }

    // Team-color diagonal wash over the dark match-detail panel gradient — the same recipe as
    // TeamDetailView.headerBackground (dsMdPanel base + accent 0.22→0.05 diagonal).
    private func headerBackground(_ accent: (fill: Color, on: Color)) -> some View {
        ZStack {
            LinearGradient(colors: [Color.dsMdPanel, Color.dsMdPanelBottom],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [accent.fill.opacity(0.26), accent.fill.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // Jersey number when present, otherwise initials — mirrors the squad card.
    private var monogram: String {
        if let jersey = athlete.jersey, !jersey.isEmpty { return jersey }
        let initials = athlete.name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "—" : initials
    }

    // The season stat block — grouped, position-aware sections (Attacking / Passing / Defending /
    // Discipline for outfield; Goalkeeping / Distribution for keepers) from ESPN's full stat set,
    // non-zero only. Falls back to the headline line when the full set isn't available.
    private func statsCard(_ stats: PlayerSeasonStats, label: String) -> some View {
        let sections = stats.seasonSections
        return VStack(alignment: .leading, spacing: 14) {
            Text(label)
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgSecondary)
            if sections.isEmpty {
                statsTable(statRows(stats))
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title.uppercased())
                            .dsFont(12, weight: .semibold)
                            .tracking(0.6)
                            .foregroundStyle(Color.dsFgSecondary)
                        statsTable(section.items.map { (label: $0.label, value: $0.value) })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A card of label→value rows, shared by each grouped section and the legacy fallback.
    private func statsTable(_ rows: [(label: String, value: String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.label).foregroundStyle(Color.dsFgSecondary)
                    Spacer()
                    Text(row.value).dsFont(15, weight: .semibold, monospacedDigit: true).foregroundStyle(Color.dsFgPrimary)
                }
                .dsFont(16)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                if index < rows.count - 1 {
                    Rectangle().fill(Color.dsSeparator).frame(height: 0.5)
                }
            }
        }
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd))
    }

    private func statRows(_ s: PlayerSeasonStats) -> [(label: String, value: String)] {
        if s.isGoalkeeper {
            return [
                ("Appearances", "\(s.appearances)"),
                ("Clean sheets", "\(s.cleanSheets)"),
                ("Saves", "\(s.saves)"),
                ("Goals against", "\(s.goalsAgainst)"),
                ("Minutes", "\(s.minutes)"),
            ]
        }
        return [
            ("Appearances", "\(s.appearances)"),
            ("Goals", "\(s.goals)"),
            ("Assists", "\(s.assists)"),
            ("Shots", "\(s.shots)"),
            ("Minutes", "\(s.minutes)"),
        ]
    }

    // Only the bio fields ESPN actually gave us, in a stable order.
    private var bioRows: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let jersey = athlete.jersey, !jersey.isEmpty { rows.append(("Jersey", "#\(jersey)")) }
        if let position = athlete.positionName { rows.append(("Position", position)) }
        if let age = athlete.age { rows.append(("Age", "\(age)")) }
        if let height = athlete.displayHeight { rows.append(("Height", height)) }
        if let citizenship = athlete.citizenship { rows.append(("Nationality", citizenship)) }
        return rows
    }
}

#Preview {
    NavigationStack {
        PlayerDetailView(athlete: Athlete(
            id: "1", name: "Trinity Rodman", shortName: "T. Rodman", jersey: "2",
            positionName: "Forward", positionAbbreviation: "F",
            age: 23, displayHeight: "5' 8\"", citizenship: "USA"
        ), accentHex: "C8102E", stats: PlayerSeasonStats(
            athleteID: "1", appearances: 18, minutes: 1540,
            goals: 9, assists: 4, shots: 41,
            saves: 0, cleanSheets: 0, goalsAgainst: 0, isGoalkeeper: false
        ), seasonLabel: AppConfig.seasonStatsLabel(year: 2026))
    }
}
