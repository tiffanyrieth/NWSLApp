//
//  HowToWatchCard.swift
//  NWSLApp
//
//  Future-match "How to Watch" section (design handoff `MatchDetailParts.jsx` →
//  `HowToWatch`): an expandable card for the match's broadcast partner. Collapsed
//  it shows the service icon tile + name + a one-line note; tapping "Find it"
//  reveals device-by-device steps (Roku, Fire TV, phone, …) from BroadcastInfo.
//  Renders nothing for an unrecognized partner.
//

import SwiftUI

struct HowToWatchCard: View {
    let broadcast: String?
    @State private var expanded = false

    private var info: BroadcastInfo? { BroadcastInfo.info(for: broadcast) }

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 10) {
                Text("How to Watch").trackedCaps()
                card(info)
            }
        }
    }

    private func card(_ info: BroadcastInfo) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                header(info)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(info.devices) { device in
                        deviceRow(device, accent: info.color)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private func header(_ info: BroadcastInfo) -> some View {
        HStack(spacing: 12) {
            // Brand-colored icon tile.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(info.color)
                Text("📺").font(.system(size: 16))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.dsFgPrimary)
                Text(info.note)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(expanded ? "Hide" : "Find it")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .foregroundStyle(info.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func deviceRow(_ device: BroadcastInfo.Device, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(device.device)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.dsFgPrimary)
                .frame(width: 100, alignment: .leading)
            Text(device.steps)
                .font(.system(size: 13))
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
        HowToWatchCard(broadcast: "Victory+")
            .padding()
    }
    .background(Color.dsBgPrimary)
}
