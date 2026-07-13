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
import LiveActivityContract
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
                // Slightly-navy base under the team wash (matches dsMdPanel), replacing the
                // old flat black — the team-color gradient rides on top inside the banner.
                .activityBackgroundTint(LA.panel.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    teamColumn(abbr: a.homeAbbr, hex: a.homeColorHex, isNational: a.isNational ?? false)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    teamColumn(abbr: a.awayAbbr, hex: a.awayColorHex, isNational: a.isNational ?? false)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        pill(s.phase)
                        // Pre-match honesty: "vs", not a fabricated 0 – 0 (parity with the
                        // lock screen's scoreText — a score that doesn't exist yet isn't shown).
                        Text(s.phase == .pre ? "vs" : "\(s.homeScore) – \(s.awayScore)")
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
                // Pre-match honesty (owner call, matches FIFA/The Athletic): before kickoff the
                // island shows just the crests — a "0" for a match that hasn't started reads as
                // a live 0–0, which is a lie.
                HStack(spacing: 3) {
                    CrestBadge(abbr: a.homeAbbr, hex: a.homeColorHex, size: 18, isNational: a.isNational ?? false)
                    if s.phase != .pre {
                        Text("\(s.homeScore)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    }
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    if s.phase != .pre {
                        Text("\(s.awayScore)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    }
                    CrestBadge(abbr: a.awayAbbr, hex: a.awayColorHex, size: 18, isNational: a.isNational ?? false)
                }
            } minimal: {
                // Minimal (second concurrent Activity): the leading team's score in its color —
                // pre-match, its crest instead (same honesty rule as compact).
                if s.phase == .pre {
                    CrestBadge(abbr: a.homeAbbr, hex: a.homeColorHex, size: 16, isNational: a.isNational ?? false)
                } else {
                    Text("\(s.homeScore)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(hex: a.homeColorHex))
                }
            }
            .keylineTint(s.phase.pillColor)
        }
    }

    // Expanded-region team column (crest/flag + abbreviation).
    private func teamColumn(abbr: String, hex: String, isNational: Bool = false) -> some View {
        VStack(spacing: 4) {
            CrestBadge(abbr: abbr, hex: hex, size: 28, isNational: isNational)
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
        if s.phase.isClockRunning, let stoppage = s.stoppageDisplay {
            // Added time: the watcher pushes a static "90'+2'" each minute (the self-ticking timer can't
            // format football stoppage). Takes priority over the mm:ss clock while present.
            Text(stoppage).font(font).foregroundStyle(LA.clock)
        } else if s.phase.isClockRunning, let epoch = s.clockStartEpoch {
            // Auto-advancing local clock — no push needed to tick. showsHours:false keeps it mm:ss past
            // 60:00 (the 68th minute reads "68:12", not "1:08:12") — a match clock never rolls to hours.
            Text(timerInterval: Date(timeIntervalSince1970: epoch)...Date.distantFuture, countsDown: false, showsHours: false)
                .font(font.monospacedDigit())
                .foregroundStyle(LA.clock)
                .frame(maxWidth: 56)
        } else if s.phase != .fulltime, let label = s.staticLabel {
            // At full-time the top pill already shows "FT" — don't repeat it in the clock slot.
            Text(label).font(font).foregroundStyle(LA.clock)
        }
    }
}

// MARK: - Lock-screen banner
private struct LockScreenBanner: View {
    let attributes: MatchActivityAttributes
    let state: MatchActivityAttributes.ContentState

    var body: some View {
        ZStack {
            teamWash
            VStack(spacing: 8) {
            // Top-aligned so each side's scorer column grows DOWNWARD under its team while the
            // center score block stays put — the FIFA/match-thread layout (home events left,
            // away events right) the owner asked for.
            HStack(alignment: .top) {
                sideColumn(
                    abbr: attributes.homeAbbr, hex: attributes.homeColorHex,
                    scorers: state.homeScorers, reds: state.homeRedCards, alignment: .leading,
                    isNational: attributes.isNational ?? false
                )
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
                sideColumn(
                    abbr: attributes.awayAbbr, hex: attributes.awayColorHex,
                    scorers: state.awayScorers, reds: state.awayRedCards, alignment: .trailing,
                    isNational: attributes.isNational ?? false
                )
            }
            HStack {
                Text(attributes.competition)
                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                // Legacy fallback: an OLD watcher payload has no per-side lists, so the single
                // last-scorer line keeps working. (Text only — the old 5×5 dot was hardcoded to
                // the HOME color regardless of who scored, which was quietly wrong.)
                if !hasSideDetail, let scorer = state.lastScorer {
                    Text(scorer).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                }
                if let b = state.broadcast {
                    Spacer().frame(width: 10)
                    Text(b).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white.opacity(0.45))
                }
            }
            }
            .padding(14)
        }
    }

    /// True when the watcher sent per-side detail — the footer's single-line fallback stands
    /// down so the same scorer isn't shown twice.
    private var hasSideDetail: Bool {
        state.homeScorers?.isEmpty == false || state.awayScorers?.isEmpty == false
            || (state.homeRedCards ?? 0) > 0 || (state.awayRedCards ?? 0) > 0
    }

    // Team-color wash: home color bleeds from the left edge, away from the right — the
    // SAME gradient stops as the schedule cards (MatchCard.swift), punched from 0.18 to
    // 0.28 because the lock-screen banner sits over varied wallpapers and needs more
    // presence than an in-app card. Reads the static team hexes on `attributes`.
    private var teamWash: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: attributes.homeColorHex).opacity(0.28), location: 0.0),
                .init(color: Color(hex: attributes.homeColorHex).opacity(0.0),  location: 0.34),
                .init(color: Color(hex: attributes.awayColorHex).opacity(0.0),  location: 0.66),
                .init(color: Color(hex: attributes.awayColorHex).opacity(0.28), location: 1.0),
            ],
            startPoint: UnitPoint(x: 0, y: 0.42),
            endPoint: UnitPoint(x: 1, y: 0.58)
        )
    }

    private var scoreText: String {
        state.phase == .pre ? "vs" : "\(state.homeScore) – \(state.awayScore)"
    }

    @ViewBuilder
    private var minute: some View {
        if state.phase.isClockRunning, let stoppage = state.stoppageDisplay {
            Text(stoppage).font(.system(size: 11, weight: .semibold)).foregroundStyle(LA.clock)
        } else if state.phase.isClockRunning, let epoch = state.clockStartEpoch {
            Text(timerInterval: Date(timeIntervalSince1970: epoch)...Date.distantFuture, countsDown: false, showsHours: false)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(LA.clock)
                .frame(maxWidth: 60)
        } else if state.phase != .fulltime, let label = state.staticLabel {
            // At full-time the top pill already shows "FT" — don't repeat it in the clock slot.
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(LA.clock)
        }
    }

    /// One side of the banner: crest + abbreviation (+ red-card rects), with that side's scorer
    /// lines stacked underneath. Home is leading-aligned, away trailing — mirroring a match
    /// thread's home-left / away-right event columns.
    private func sideColumn(
        abbr: String, hex: String, scorers: [String]?, reds: Int?, alignment: HorizontalAlignment,
        isNational: Bool = false
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 8) {
                // Crest is PROMINENT by design — it's the team's identity (players/fans lift the
                // crest to their chest), and it outranks the abbreviation. Never shrink it toward
                // an "icon" size; if anything it should read as big as the space allows (à la The
                // Athletic's national-team flags). 48pt here dominates the 14pt abbr intentionally.
                CrestBadge(abbr: abbr, hex: hex, size: 48, isNational: isNational)
                Text(abbr).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                if let reds, reds > 0 {
                    // Red-card marker(s): the app's card language (EventTimelineRow.cardRect —
                    // a filled rounded rect, never an SF symbol), scaled to sit beside the abbr.
                    HStack(spacing: 2) {
                        ForEach(0..<min(reds, 2), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(LA.live)
                                .frame(width: 8, height: 11)
                        }
                    }
                }
            }
            if let scorers, !scorers.isEmpty {
                VStack(alignment: alignment, spacing: 2) {
                    // Index-keyed: two goals by one player can render the same line when ESPN
                    // omits the minute, and duplicate \.self IDs would drop one.
                    ForEach(Array(scorers.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Crest / flag (real bundled badge; colored ring + abbreviation only as fallback)
struct CrestBadge: View {
    let abbr: String
    let hex: String
    let size: CGFloat
    /// National-team match → render the FIFA-code FLAG instead of a club crest (USWNT V2). Both asset
    /// sets are bundled in the WIDGET's own catalog (it can't read the app target's). Default false.
    var isNational: Bool = false

    var body: some View {
        if isNational {
            flagBadge
        } else {
            crestBadge
        }
    }

    // National-team FLAG — mirrors the app's canonical flag grammar (NationalTeamCard.flag): a
    // rectangular mark at the ~52×36 ratio (width = size, height = size·0.69), FILLED, rounded-6
    // continuous clip + a white hairline so white-edged flags (Japan) stay defined on the dark card.
    // Flags are PNG in the widget catalog (Live Activity image-memory budget — SVG is app-only).
    @ViewBuilder private var flagBadge: some View {
        let h = size * 0.69
        if let img = UIImage(named: "Flags/\(abbr.uppercased())") {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
        } else {
            // Load miss → a country-color block in the same flag shape (never blank).
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: hex).opacity(0.85))
                .frame(width: size, height: h)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    // Club CREST — the reference standard, UNTOUCHED: prominent, square, fit; colored ring + abbr fallback.
    @ViewBuilder private var crestBadge: some View {
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
