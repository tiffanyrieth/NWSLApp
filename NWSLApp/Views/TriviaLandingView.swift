//
//  TriviaLandingView.swift
//  NWSLApp
//
//  NWSL Trivia — the LANDING PAGE (the KnowHerLandingView pattern, applied to the second community-family
//  game so the two front doors work identically; owner anti-drift rule). Every entry to Trivia lands here
//  first. Three persistent sections:
//    • This round  — Round N + "closes in Nd": play it, or re-open the live community recap once played.
//    • Last round  — the previous round's results: your score if you played it, and the community recap
//      either way (same rule as KHG's "Last round": sitting a round out doesn't hide how everyone did).
//    • How it works — the round rules, so the biweekly cadence reads as intentional, not a broken daily.
//
//  Trivia has ONE slate per round (no per-team split), so this is the single-column version of the KHG
//  landing: a hero card for the live round instead of player rows. Round math comes from the shared
//  FanZoneCadence (staggered biweekly against KHG); the store holds the played state + retention
//  (current + previous round only — which is exactly what this page shows, by design).
//

import SwiftUI

struct TriviaLandingView: View {
    @Environment(TriviaStore.self) private var store

    /// Which session sheet is open — the live round or the previous round's read-only recap.
    private enum ActiveEntry: Identifiable {
        case current
        case lastRound(Int)
        var id: String {
            switch self {
            case .current: return "current"
            case .lastRound(let r): return "prev-\(r)"
            }
        }
    }

    @State private var activeEntry: ActiveEntry?

    private let accent = Color.dsGameTrivia

    /// Plain-English round rules ("How it works") — the cadence contract, in fan language.
    private let rules = [
        "A fresh 10-question round every two weeks",
        "One attempt per round — points add to your Superfan total",
        "Play every round to build your streak",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                thisRoundSection
                if store.previousEditionKey != nil {
                    lastRoundSection
                }
                howItWorks
                Text("NWSL Trivia and Know Her Game take turns — one of them drops every week.")
                    .dsFont(11).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .nativeBackButton(title: "NWSL Trivia")
        .fanZonePlayingAs(accent: accent)
        .background(Color.dsBgGrouped)
        .sheet(item: $activeEntry) { entry in
            NavigationStack {
                switch entry {
                case .current:
                    TriviaRoundView()                       // play, or the live recap if already played
                case .lastRound(let round):
                    TriviaRoundView(entry: .review(round: round))
                }
            }
        }
    }

    // MARK: - This round

    private var thisRoundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("This round", round: store.currentRound)
            Button { activeEntry = .current } label: {
                HStack(spacing: 14) {
                    Image(systemName: "brain.head.profile")
                        .dsFont(22).foregroundStyle(accent)
                        .frame(width: 52, height: 52)
                        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("League knowledge, 10 questions")
                            .dsFont(17, weight: .semibold).foregroundStyle(.primary)
                        Text(store.hasPlayedCurrentRound ? "Played · \(closesLine)" : "New round · \(closesLine)")
                            .dsFont(15)
                            .foregroundStyle(store.hasPlayedCurrentRound ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
                    }
                    Spacer()
                    if let score = store.currentScore {
                        resultsBadge(score: score, total: 10)
                    } else {
                        HStack(spacing: 3) {
                            Text("Play").dsFont(15, weight: .semibold)
                            Image(systemName: "chevron.right").dsFont(11, weight: .bold)
                        }
                        .foregroundStyle(accent)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)   // a completed card stays tappable → the live community recap
            if store.streak > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").dsFont(13).foregroundStyle(.orange)
                    Text("\(store.streak)-round streak — play every round to keep it")
                        .dsFont(12).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// "Closes in 3d" / "Closes today" — the round's remaining window, from the shared cadence.
    private var closesLine: String {
        let days = max(0, Int(ceil(store.roundCloses.timeIntervalSince(Date()) / 86_400)))
        return days <= 1 ? "closes today" : "closes in \(days)d"
    }

    // MARK: - Last round

    private var lastRoundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionEyebrow("Last round", round: (store.currentRound ?? 1) - 1)
            Button {
                if let round = store.currentRound, round > 1 { activeEntry = .lastRound(round - 1) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .dsFont(16).foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color.dsBgTertiary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.previousScore != nil ? "Your score + how everyone did" : "See how everyone did")
                            .dsFont(15, weight: .semibold).foregroundStyle(.secondary)
                        Text(store.previousScore != nil ? "You played this round" : "You sat this one out")
                            .dsFont(12).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let score = store.previousScore {
                            Text("\(score)/10")
                                .dsFont(12, weight: .bold).foregroundStyle(accent.opacity(0.75))
                        }
                        HStack(spacing: 2) {
                            Text("Results").dsFont(11, weight: .semibold)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.dsBgCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Community results stay for one round after each round closes.")
                .dsFont(11).foregroundStyle(.tertiary)
        }
    }

    // MARK: - How it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW IT WORKS")
                .dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(accent)
            ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .dsFont(11, weight: .bold).foregroundStyle(accent)
                        .frame(width: 20, height: 20)
                        .background(accent.opacity(0.15), in: Circle())
                    Text(rule).dsFont(13).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Shared bits (KHG landing grammar)

    private func sectionEyebrow(_ title: String, round: Int?) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(.secondary)
            if let round, round > 0 {
                Text("Round \(round)")
                    .dsFont(11, weight: .bold).tracking(0.4).foregroundStyle(accent)
            }
            Spacer()
        }
    }

    private func resultsBadge(score: Int, total: Int) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(score)/\(total)").dsFont(15, weight: .bold).foregroundStyle(accent)
            HStack(spacing: 2) {
                Text("Results").dsFont(11, weight: .semibold)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        TriviaLandingView()
            .environment(TriviaStore())
            .environment(AuthStore())
    }
}
