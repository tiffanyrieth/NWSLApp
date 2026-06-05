//
//  PlayerDetailView.swift
//  NWSLApp
//
//  Pushed when a player card in the Teams → Squad grid is tapped. The full
//  player profile (per-player stats, season totals) is a future build — that
//  data isn't in the endpoints we map yet — so this is an INTENTIONAL placeholder
//  (flagged in the File Map), not a blank screen: it shows the bio we already
//  have from the roster (jersey, position, age, height, nationality) and a clean
//  "stats coming soon" panel so the tap lands somewhere deliberate.
//
//  When the player-stats endpoint is mapped, the placeholder panel below becomes
//  the real stats section; everything else here stays.
//

import SwiftUI

struct PlayerDetailView: View {
    let athlete: Athlete
    /// The club's ESPN color hex, threaded down from TeamDetailView so the
    /// monogram matches the squad card the user tapped.
    let accentHex: String?

    var body: some View {
        let accent = Color.teamAccent(hex: accentHex)
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(accent.fill)
                    Text(monogram)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(accent.on)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(10)
                }
                .frame(width: 96, height: 96)

                VStack(spacing: 4) {
                    Text(athlete.name)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let position = athlete.positionName {
                        Text(position)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !bioRows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(bioRows.enumerated()), id: \.offset) { index, row in
                            HStack {
                                Text(row.label).foregroundStyle(.secondary)
                                Spacer()
                                Text(row.value).fontWeight(.medium)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            if index < bioRows.count - 1 { Divider() }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Intentional placeholder — see file header.
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Player stats coming soon")
                        .font(.headline)
                    Text("Goals, assists, appearances and more will live here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(athlete.shortName ?? athlete.name)
        .navigationBarTitleDisplayMode(.inline)
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
        ), accentHex: "C8102E")
    }
}
