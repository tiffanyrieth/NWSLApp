//
//  HowToWatchCard.swift
//  NWSLApp
//
//  Future-match "How to watch" card (design handoff `match-detail.jsx` →
//  `HowToWatch`): title + a FREE/SUBSCRIPTION badge, a broadcast color chip + an
//  access line, a one-line tip, and a "Find it" CTA that reveals the per-device
//  steps (the real accessibility feature — e.g. ION's "search Scripps, not ION",
//  Victory+'s "search Victory Plus spelled out", CBS's Paramount+ lock note). The
//  device steps come from BroadcastInfo.
//
//  ⚠️ IT ALWAYS RENDERS (2026-08-03). It used to return an empty body for an unrecognized partner,
//  which is why a CBSSN match showed NO how-to-watch card at all — the card silently vanished on
//  exactly the broadcaster people struggle with most. An unknown partner now gets an honest card
//  that says we don't have directions yet, with NO free/paid badge (guessing one would fabricate a
//  paywall) and a Diagnostics record so a new ESPN string reaches an engineer instead of being
//  normalized away forever.
//

import SwiftUI

struct HowToWatchCard: View {
    let broadcast: String?
    @State private var expanded = false

    private var info: BroadcastInfo? { BroadcastInfo.info(for: broadcast) }

    var body: some View {
        if let info {
            card(info)
        } else {
            unknownCard
        }
    }

    /// Honest state for a broadcaster we don't have directions for. Never invents steps, never
    /// guesses free-vs-paid — the two ways this could have failed dishonestly.
    private var unknownCard: some View {
        let name = broadcast?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            Text("How to watch")
                .dsFont(17, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
            if !name.isEmpty {
                BroadcastChip(name: name, small: false)
            }
            Text(name.isEmpty
                 ? "Broadcast details for this match haven't been announced yet."
                 : "We don't have step-by-step directions for \(name) yet. Full replays post to NWSL+ free a few days after each match.")
                .dsFont(13)
                .lineSpacing(3)
                .foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .task(id: name) {
            guard !name.isEmpty else { return }
            // Fail loud to the engineer, honestly to the user (CLAUDE.md no-silent-failures).
            Diagnostics.shared.record(.unexpectedEmpty, "how-to-watch unresolved broadcaster: \(name)")
        }
    }

    private func card(_ info: BroadcastInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("How to watch")
                        .dsFont(17, weight: .bold)
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer()
                    // No badge at all when access is unknown — never guess a paywall.
                    if let badge = info.access.badge {
                        Text(badge)
                            .dsFont(12, weight: .bold)
                            .tracking(0.5)
                            .foregroundStyle(info.access.isFree ? Color.dsSuccess : Color.dsFgSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(info.access.isFree ? Color.dsSuccess.opacity(0.16) : Color.dsBgTertiary,
                                        in: Capsule())
                    }
                }

                // Chip + the access label the handoff specifies ("Free over-the-air",
                // "Live TV subscription", …). No label when access is unknown.
                HStack(spacing: 10) {
                    BroadcastChip(name: broadcast ?? info.name, small: false)
                    if let label = info.access.label {
                        Text(label)
                            .dsFont(12.5)
                            .foregroundStyle(Color.dsFgSecondary)
                    }
                }

                Text(info.note)
                    .dsFont(13)
                    .lineSpacing(3)
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Hide steps" : "Find it")
                        .dsFont(15, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.dsAccent,
                                    in: RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // The verbatim per-device "find it" steps (the real feature).
            if expanded {
                VStack(spacing: 0) {
                    ForEach(info.devices) { device in
                        deviceRow(device)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func deviceRow(_ device: BroadcastInfo.Device) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(device.device)
                .dsFont(13, weight: .semibold)
                .foregroundStyle(Color.dsFgPrimary)
                .frame(width: 100, alignment: .leading)
            Text(device.steps)
                .dsFont(13)
                .foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.dsSeparator.opacity(0.6)).frame(height: 1)
        }
    }

}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            HowToWatchCard(broadcast: "ION")
            HowToWatchCard(broadcast: "CBSSN")        // the bug: used to render nothing
            HowToWatchCard(broadcast: "ABC")          // was badged SUBSCRIPTION; it's free OTA
            HowToWatchCard(broadcast: "Telemundo")    // unknown → honest card, no badge
        }
        .padding()
    }
    .background(Color.dsBgPrimary)
}
