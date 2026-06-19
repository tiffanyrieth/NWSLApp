//
//  HowToWatchCard.swift
//  NWSLApp
//
//  Future-match "How to watch" card (design handoff `match-detail.jsx` →
//  `HowToWatch`): title + a FREE/SUBSCRIPTION badge, a broadcast color chip + an
//  access line, a one-line tip, and a "Find it" CTA that reveals the per-device
//  steps (the real accessibility feature — e.g. ION's "search Scripps, not ION",
//  Victory+'s "search Victory Plus spelled out", CBS's Paramount+ lock note). The
//  device steps come verbatim from BroadcastInfo. Renders nothing for an
//  unrecognized partner.
//

import SwiftUI

struct HowToWatchCard: View {
    let broadcast: String?
    @State private var expanded = false

    private var info: BroadcastInfo? { BroadcastInfo.info(for: broadcast) }

    var body: some View {
        if let info {
            card(info)
        }
    }

    private func card(_ info: BroadcastInfo) -> some View {
        let access = Self.access(for: info.name)
        // Canonical broadcast color (handoff palette) — the same chip the schedule
        // card + match header use.
        let chipColor = BroadcastChip.color(for: broadcast ?? info.name)

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("How to watch")
                        .dsFont(17, weight: .bold)
                        .foregroundStyle(Color.dsFgPrimary)
                    Spacer()
                    Text(access.free ? "FREE" : "SUBSCRIPTION")
                        .dsFont(10.5, weight: .bold)
                        .tracking(0.5)
                        .foregroundStyle(access.free ? Color.dsSuccess : Color.dsFgSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(access.free ? Color.dsSuccess.opacity(0.16) : Color.dsBgTertiary,
                                    in: Capsule())
                }

                HStack(spacing: 10) {
                    BroadcastChip(name: broadcast ?? info.name, small: false)
                    Text(access.label)
                        .dsFont(12.5)
                        .foregroundStyle(Color.dsFgSecondary)
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

    // FREE/SUBSCRIPTION + a short access line, matching the mock's WATCH table.
    // (Kept here, not in the verbatim-ported BroadcastInfo DB.)
    private static func access(for name: String) -> (free: Bool, label: String) {
        let n = name.lowercased()
        switch true {
        case n.contains("ion"):       return (true, "Free over-the-air")
        case n.contains("victory"):   return (true, "Free app")
        case n.contains("cbs") && !n.contains("sports"): return (true, "Free over-the-air")
        case n.contains("cbs"):       return (false, "Cable / Paramount+")
        case n.contains("paramount"): return (false, "Subscription")
        case n.contains("espn"), n.contains("abc"): return (false, "Cable / ESPN+")
        case n.contains("prime"), n.contains("amazon"): return (false, "Prime subscription")
        case n.contains("nwsl"):      return (false, "Subscription")
        default:                      return (false, "Check local listings")
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            HowToWatchCard(broadcast: "ION")
            HowToWatchCard(broadcast: "Prime Video")
            HowToWatchCard(broadcast: "CBS")
        }
        .padding()
    }
    .background(Color.dsBgPrimary)
}
