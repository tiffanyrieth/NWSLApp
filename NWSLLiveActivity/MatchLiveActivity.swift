//
//  MatchLiveActivity.swift
//  NWSLLiveActivity
//
//  The four surfaces of the V2 Live Activity (spec §01): lock-screen banner + Dynamic Island
//  compact / expanded / minimal. Native SwiftUI rendered from `MatchActivityAttributes.ContentState`
//  — no server image, no buzz. Crests are the REAL bundled badges (this extension carries its own
//  copy of the crest asset catalog); the colored ring is only the fallback when a crest is missing.
//
//  Clock: while the phase's clock runs, the minute is an AUTO-ADVANCING timer anchored at
//  `clockAnchor` (the virtual-kickoff instant = now − elapsed), so it ticks locally with no push.
//  Otherwise it shows `staticLabel` (pre-match time / HT / FT). (Running clock reads mm:ss; whole-
//  minute "67'" would need per-minute pushes — Design confirm. See the plan's clock decision.)
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Temporal palette (matches the app's DesignSystem state colors)
private enum LA {
    static let live = Color(hex: "FF453A")
    static let clock = Color(hex: "FF9F0A")
    static let final = Color(hex: "30D158")
    static let kickoff = Color(hex: "64D2FF")
    static let panel = Color(hex: "14151C")
    static let fg2 = Color.white.opacity(0.55)
}

private extension MatchActivityAttributes.Phase {
    var pillText: String {
        switch self {
        case .pre: return "SOON"
        case .live: return "● LIVE"
        case .halftime: return "HT"
        case .extraTime: return "● LIVE"
        case .penalties: return "PENS"
        case .fulltime: return "FT"
        }
    }
    var pillColor: Color {
        switch self {
        case .pre: return LA.kickoff
        case .live, .extraTime, .penalties: return LA.live
        case .halftime: return LA.clock
        case .fulltime: return LA.final
        }
    }
}

// MARK: - The Live Activity
struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            // Lock-screen / banner surface.
            LockScreenBanner(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    teamColumn(abbr: a.homeAbbr, hex: a.homeColorHex)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    teamColumn(abbr: a.awayAbbr, hex: a.awayColorHex)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        pill(s.phase)
                        Text("\(s.homeScore) – \(s.awayScore)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        minuteView(s, font: .system(size: 11, weight: .semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(a.competition)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(LA.fg2)
                        Spacer()
                        if let scorer = s.lastScorer {
                            Text(scorer).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        } else if let b = s.broadcast {
                            Text(b).font(.system(size: 10, weight: .semibold)).foregroundStyle(LA.fg2)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    CrestBadge(abbr: a.homeAbbr, hex: a.homeColorHex, size: 18)
                    Text("\(s.homeScore)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Text("\(s.awayScore)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    CrestBadge(abbr: a.awayAbbr, hex: a.awayColorHex, size: 18)
                }
            } minimal: {
                // Minimal (second concurrent Activity): the leading team's score in its color.
                Text("\(s.homeScore)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(hex: a.homeColorHex))
            }
            .keylineTint(s.phase.pillColor)
        }
    }

    // Expanded-region team column (crest + abbreviation).
    private func teamColumn(abbr: String, hex: String) -> some View {
        VStack(spacing: 4) {
            CrestBadge(abbr: abbr, hex: hex, size: 28)
            Text(abbr).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
        }
    }

    private func pill(_ phase: MatchActivityAttributes.Phase) -> some View {
        Text(phase.pillText)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(phase.pillColor)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(phase.pillColor.opacity(0.18), in: Capsule())
    }

    @ViewBuilder
    private func minuteView(_ s: MatchActivityAttributes.ContentState, font: Font) -> some View {
        if s.phase.isClockRunning, let epoch = s.clockStartEpoch {
            // Auto-advancing local clock — no push needed to tick.
            Text(timerInterval: Date(timeIntervalSince1970: epoch)...Date.distantFuture, countsDown: false)
                .font(font.monospacedDigit())
                .foregroundStyle(LA.clock)
                .frame(maxWidth: 56)
        } else if let label = s.staticLabel {
            Text(label).font(font).foregroundStyle(LA.clock)
        }
    }
}

// MARK: - Lock-screen banner
private struct LockScreenBanner: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                team(attributes.homeAbbr, attributes.homeColorHex)
                Spacer()
                VStack(spacing: 3) {
                    Text(state.phase.pillText)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(state.phase.pillColor)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(state.phase.pillColor.opacity(0.18), in: Capsule())
                    Text(scoreText)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    minute
                }
                Spacer()
                team(attributes.awayAbbr, attributes.awayColorHex)
            }
            HStack {
                Text(attributes.competition)
                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                if let scorer = state.lastScorer {
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: attributes.homeColorHex)).frame(width: 5, height: 5)
                        Text(scorer).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                }
                if let b = state.broadcast {
                    Spacer().frame(width: 10)
                    Text(b).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
        .padding(14)
    }

    private var scoreText: String {
        state.phase == .pre ? "vs" : "\(state.homeScore) – \(state.awayScore)"
    }

    @ViewBuilder
    private var minute: some View {
        if state.phase.isClockRunning, let epoch = state.clockStartEpoch {
            Text(timerInterval: Date(timeIntervalSince1970: epoch)...Date.distantFuture, countsDown: false)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(LA.clock)
                .frame(maxWidth: 60)
        } else if let label = state.staticLabel {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(LA.clock)
        }
    }

    private func team(_ abbr: String, _ hex: String) -> some View {
        HStack(spacing: 8) {
            CrestBadge(abbr: abbr, hex: hex, size: 36)
            Text(abbr).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Crest (real bundled badge; colored ring + abbreviation only as fallback)
struct CrestBadge: View {
    let abbr: String
    let hex: String
    let size: CGFloat

    var body: some View {
        if let img = UIImage(named: "Crests/\(abbr.uppercased())") {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(abbr)
                .font(.system(size: size * 0.32, weight: .heavy))
                .foregroundStyle(Color(hex: hex))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color(hex: hex), lineWidth: max(1.5, size / 18)))
        }
    }
}

// MARK: - Hex → Color (the widget can't see the app's Color extensions; minimal local copy)
extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
