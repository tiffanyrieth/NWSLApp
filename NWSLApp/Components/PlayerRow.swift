//
//  PlayerRow.swift
//  NWSLApp
//
//  One player in a club's roster: a monogram avatar + name + a compact details
//  line (position · age · height · nationality, whichever ESPN provides).
//
//  No photo on purpose: ESPN's NWSL roster feed returns a null headshot for
//  every athlete (verified against the live endpoint), so instead of a broken
//  image we show a jersey-number monogram — the same neutral-placeholder spirit
//  as TeamLogo. This is a deliberate, permanent choice for this league, not a
//  TODO; if a future data source carries NWSL headshots, swap the avatar here.
//

import SwiftUI

struct PlayerRow: View {
    let athlete: Athlete

    var body: some View {
        HStack(spacing: 12) {
            JerseyAvatar(jersey: athlete.jersey, name: athlete.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(athlete.name)
                    .font(.body)
                if let details = detailLine {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // "G · 31 · 5' 10" · USA" — only the parts ESPN gave us, joined by dots.
    private var detailLine: String? {
        var parts: [String] = []
        if let position = athlete.positionAbbreviation { parts.append(position) }
        if let age = athlete.age { parts.append("\(age)") }
        if let height = athlete.displayHeight { parts.append(height) }
        if let citizenship = athlete.citizenship { parts.append(citizenship) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A round avatar standing in for a (non-existent) player photo: the jersey
/// number when present, otherwise the player's initials.
private struct JerseyAvatar: View {
    let jersey: String?
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)   // the name beside it identifies the player
    }

    private var label: String {
        if let jersey, !jersey.isEmpty { return jersey }
        let initials = name
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
            .map(String.init)
            .joined()
        return initials.isEmpty ? "—" : initials
    }
}

#Preview {
    List {
        PlayerRow(athlete: Athlete(
            id: "1", name: "Hannah Seabert", jersey: "13",
            positionName: "Goalkeeper", positionAbbreviation: "G",
            age: 31, displayHeight: "5' 10\"", citizenship: "USA"
        ))
        PlayerRow(athlete: Athlete(
            id: "2", name: "Alyssa Thompson", jersey: nil,
            positionName: "Forward", positionAbbreviation: "F",
            age: 21, displayHeight: nil, citizenship: "USA"
        ))
    }
}
