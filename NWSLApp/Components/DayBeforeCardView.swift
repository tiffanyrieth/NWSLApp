//
//  DayBeforeCardView.swift
//  NWSLApp
//
//  The image tile for the Tier-1 day-before (24h) reminder — a match-card look rendered
//  OFFSCREEN by DayBeforeCardRenderer (SwiftUI ImageRenderer → PNG → UNNotificationAttachment)
//  and shown in the expanded notification. It is NOT app UI: it renders at a FIXED frame with
//  NO Dynamic Type (fixed-container exemption — `.font(.system)`, not `.dsFont`; @ScaledMetric has
//  no meaning offscreen), and crests resolve from the BUNDLE only (no network in a notification).
//
//  Layout (owner, 2026-07-24): home team LEFT, away RIGHT, no home/away labels (soccer convention,
//  matches every other app surface); LARGE crests (crests-prominent rule) with the abbreviation
//  beneath; a center stack of "TOMORROW" · kickoff day+time · a TV chip. Team-color wash bleeds
//  from both edges via the shared TeamWashBackground.
//

import SwiftUI

struct DayBeforeCardView: View {
    let model: DayBeforeCardModel

    /// 360×180 pt (2:1). Rendered @3x → 1080×540 px flat-color PNG (well under the attachment cap).
    /// The expanded notification shows the attachment at ~full content width (~358 pt on a 393 pt
    /// phone), so 360 pt renders ≈1:1; 180 pt of height fits an 84 pt crest + label per side and the
    /// 3-row center stack without dominating the lock screen.
    static let size = CGSize(width: 360, height: 180)

    var body: some View {
        ZStack {
            TeamWashBackground(
                base: .dsBgCard,
                home: Color.teamColor(for: model.homeAbbr),
                away: Color.teamColor(for: model.awayAbbr)
            )
            HStack(spacing: 0) {
                side(model.homeAbbr)
                Spacer(minLength: 8)
                center
                Spacer(minLength: 8)
                side(model.awayAbbr)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // No corner radius — iOS rounds the attachment itself; render full-bleed.
    }

    // MARK: One team side — large crest + abbreviation

    private func side(_ abbr: String) -> some View {
        VStack(spacing: 8) {
            crest(abbr)
                .frame(width: 84, height: 84)   // crests PROMINENT — the team's identity outranks the text
            Text(abbr)
                .font(.system(size: 14, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.dsFgPrimary)
        }
        .frame(width: 96)
    }

    @ViewBuilder
    private func crest(_ abbr: String) -> some View {
        if let mark = Self.mark(for: abbr) {
            Image(uiImage: mark).resizable().scaledToFit()
        } else {
            // A legitimately-unbundled side (e.g. a Champions Cup foreign club) — the TeamLogo
            // placeholder look, no network, no diag (not a "should-be-bundled" miss).
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.dsBgTertiary)
                .overlay(
                    Text(abbr)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Color.dsFgSecondary)
                )
        }
    }

    // MARK: Center — TOMORROW · day/time · TV chip

    private var center: some View {
        VStack(spacing: 6) {
            Text("TOMORROW")
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.dsFgSecondary)
            Text("\(model.dayLabel) \(model.timeLabel)")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.dsFgPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let broadcast = model.broadcast {
                Text(broadcast)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BroadcastBrand.color(for: broadcast))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BroadcastBrand.color(for: broadcast).opacity(0.16)))
            }
        }
    }

    // MARK: Bundled crest lookup (mirrors TeamLogo.bundledMark — network-free)

    /// Crest for an NWSL club (`Crests/<ABBR>`) or a women's national-team flag (`Flags/<FIFA>`),
    /// override-cache first. `nil` for a non-NWSL / non-national side → placeholder (never network).
    @MainActor
    private static func mark(for abbr: String) -> UIImage? {
        let key = abbr.uppercased()
        return AssetRefreshService.override(crest: key)
            ?? AssetRefreshService.override(flag: key)
            ?? UIImage(named: "Crests/\(key)")
            ?? UIImage(named: "Flags/\(key)")
    }
}

#Preview("Club · broadcast") {
    DayBeforeCardView(model: .init(homeAbbr: "WAS", awayAbbr: "POR",
                                   dayLabel: "SAT", timeLabel: "4:00 PM", broadcast: "ESPN"))
        .previewLayout(.sizeThatFits)
}

#Preview("Club · no broadcast") {
    DayBeforeCardView(model: .init(homeAbbr: "KC", awayAbbr: "LA",
                                   dayLabel: "SUN", timeLabel: "1:00 PM", broadcast: nil))
        .previewLayout(.sizeThatFits)
}

#Preview("National · flags") {
    DayBeforeCardView(model: .init(homeAbbr: "USA", awayAbbr: "MEX",
                                   dayLabel: "FRI", timeLabel: "7:30 PM", broadcast: "TNT"))
        .previewLayout(.sizeThatFits)
}
