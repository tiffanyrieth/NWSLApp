//
//  BracketBattleView.swift
//  NWSLApp
//
//  Bracket Battle — the LIVE community-voting tournament (Fan Zone game 2, 0.3.9).
//  Pushed from the Home "Fan Zone" card, so it rides Home's NavigationStack. A
//  themed edition pulls a large pool of qualifying players from ESPN, seeds them
//  into a 64 → 6-round bracket, and each round the COMMUNITY votes who advances;
//  you score by predicting the crowd, on real Supabase tallies (offline-sample
//  fallback). Implements the Claude Design 5-screen reference (Bracket Battle
//  Reference.html): Edition Intro · Voting · Save/Submit · Results · Bracket
//  Overview — here as one phase-driven flow rather than five tabs.
//
//  Identity: the teal `dsGameBracket` accent; player chips are jersey-number
//  monograms (PlayerDot), team-ringed — the permanent no-headshots reality.
//

import SwiftUI

struct BracketBattleView: View {
    @State private var viewModel = BracketViewModel()
    @Environment(BracketStore.self) private var store
    @Environment(ClubStore.self) private var clubs
    @Environment(AuthStore.self) private var auth

    @State private var stage: Stage = .intro
    @State private var showSignIn = false
    @State private var showOverview = false

    private enum Stage { case intro, voting }
    private let accent = Color.dsGameBracket

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading the bracket…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                errorView(message)
            case .loaded:
                loadedContent
            }
        }
        .navigationContextLabel("Bracket Battle")
        .background(Color.dsBgPrimary.ignoresSafeArea())
        .toolbar {
            if viewModel.edition != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showOverview = true } label: { Image(systemName: "list.bullet.indent") }
                        .tint(accent)
                }
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load(store: store, userID: auth.userID, displayName: auth.displayName)
            }
        }
        .sheet(isPresented: $showSignIn) { SignInPromptView() }
        .sheet(isPresented: $showOverview) {
            NavigationStack { overviewScreen }
        }
    }

    // MARK: - Routing by round phase

    @ViewBuilder
    private var loadedContent: some View {
        if viewModel.edition == nil {
            emptyState
        } else {
            switch viewModel.phase(store: store) {
            case .open, .closed:
                if stage == .intro { introScreen } else { votingScreen }
            case .submitted:
                submittedScreen
            case .scored:
                resultsScreen
            }
        }
    }

    // MARK: - Screen 1: Edition Intro

    @ViewBuilder
    private var introScreen: some View {
        if let edition = viewModel.edition {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(edition.emoji).font(.system(size: 40))
                        Text(edition.themeLabel).font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(accent)
                        Text(edition.title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                        Text("\(edition.entrants.count) players · \(viewModel.totalMatchups) brackets · \(edition.rounds.count) rounds")
                            .font(.system(size: 13)).foregroundStyle(Color.dsFgSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28).padding(.horizontal, 20)
                    .background(LinearGradient(colors: [accent.opacity(0.12), Color.dsMdCard], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.35)))

                    bracketFunnel(rounds: edition.rounds)
                    howItWorks
                    pointsTable(rounds: edition.rounds)

                    Button { stage = .voting } label: { Text("Make your picks").primaryButtonLabel(accent) }
                    Text("\(edition.fanCount.formatted()) fans are already in")
                        .font(.system(size: 12)).foregroundStyle(Color.dsFgTertiary).frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
            }
        }
    }

    private func bracketFunnel(rounds: [BracketRound]) -> some View {
        VStack(spacing: 6) {
            sectionLabel("Tournament bracket").frame(maxWidth: .infinity)
            ForEach(Array(rounds.enumerated()), id: \.element) { i, round in
                let widthFraction = max(0.12, 1.0 - Double(i) * (0.85 / Double(max(1, rounds.count - 1))))
                if round == .final {
                    Circle().fill(accent).frame(width: 32, height: 32).overlay(Text("🏆").font(.system(size: 14)))
                    Text("FINAL · 1 winner").font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 3) {
                            ForEach(0..<round.matchupCount, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.25 + Double(i) * 0.1))
                            }
                        }
                        .frame(width: geo.size.width * widthFraction).frame(maxWidth: .infinity)
                    }
                    .frame(height: 18)
                    Text("\(round.title) · \(round.matchupCount) matchups")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.dsFgTertiary)
                    if round != rounds.last { Rectangle().fill(Color.dsFgQuaternary).frame(width: 2, height: 8) }
                }
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("How it works")
            ForEach(Array(Self.howItWorksSteps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                        .frame(width: 22, height: 22).background(accent.opacity(0.12)).clipShape(Circle())
                    Text(text).font(.system(size: 14)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let howItWorksSteps = [
        "Every qualifying player enters — stars, bench, depth. Seeded by stats into head-to-head brackets.",
        "Vote on EVERY matchup. Don't recognize a name? Research her stats. That's part of the game.",
        "Community majority decides who advances. Each round is open 2–3 days.",
        "The deeper it goes, the harder the picks — and the more they're worth.",
    ]

    private func pointsTable(rounds: [BracketRound]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Points")
            VStack(spacing: 10) {
                ForEach(rounds, id: \.self) { round in
                    HStack {
                        Text("Correct pick (\(round.title))").font(.system(size: 13)).foregroundStyle(Color.dsFgSecondary)
                        Spacer()
                        Text("+\(round.points)").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                    }
                }
                Divider().overlay(Color.dsFgQuaternary)
                HStack {
                    Text("Max possible (perfect bracket)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text("\(BracketScoring.maxPoints(rounds: rounds)) pts").font(.system(size: 13, weight: .bold)).foregroundStyle(accent)
                }
            }
            .padding(14).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Points increase each round — later picks are worth more because they're harder to predict")
                .font(.system(size: 11)).foregroundStyle(Color.dsFgTertiary).frame(maxWidth: .infinity)
        }
    }

    // MARK: - Screens 2 + 3: Voting + Save/Submit

    private var votingScreen: some View {
        let round = viewModel.currentRound ?? .roundOf64
        let made = viewModel.picksMade(store: store)
        let total = viewModel.totalMatchups
        let allMade = viewModel.allPicksMade(store: store)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        sectionLabel("\(round.title) · \(viewModel.edition?.themeLabel.capitalized ?? "")").foregroundStyle(accent)
                        Spacer()
                        if let closes = viewModel.closesInText {
                            Text(closes).font(.system(size: 11)).foregroundStyle(Color.dsFgTertiary)
                        }
                    }
                    VStack(spacing: 6) {
                        HStack {
                            Text("\(made) of \(total) picks made").font(.system(size: 12)).foregroundStyle(Color.dsFgSecondary)
                            Spacer()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.dsBgTertiary)
                                Capsule().fill(accent).frame(width: geo.size.width * (total > 0 ? Double(made) / Double(total) : 0))
                            }
                        }.frame(height: 5)
                    }
                    if allMade { allPickedBanner }
                    ForEach(viewModel.currentMatchups) { m in matchupVoteCard(m, round: round) }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            submitBar(allMade: allMade, made: made, total: total)
        }
    }

    private var allPickedBanner: some View {
        HStack(spacing: 10) {
            Text("✅").font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text("All \(viewModel.totalMatchups) picks made!").font(.system(size: 14, weight: .bold)).foregroundStyle(accent)
                Text("Save as draft or submit now. Once submitted, picks are locked forever.")
                    .font(.system(size: 12)).foregroundStyle(Color.dsFgSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(accent.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.35)))
    }

    private func matchupVoteCard(_ m: BracketMatchup, round: BracketRound) -> some View {
        let pick = store.pick(matchupID: m.id, in: round)
        return HStack(spacing: 0) {
            choiceButton(m, m.entrantA, picked: pick == m.entrantA.id)
            Text("VS").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Color.dsFgQuaternary).padding(.horizontal, 2)
            choiceButton(m, m.entrantB, picked: pick == m.entrantB.id)
        }
        .padding(6).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func choiceButton(_ m: BracketMatchup, _ e: BracketEntrant, picked: Bool) -> some View {
        Button {
            viewModel.setPick(matchup: m, entrantID: e.id, store: store)
        } label: {
            VStack(spacing: 6) {
                PlayerDot(name: e.playerName, jersey: e.jerseyNumber, teamAbbreviation: e.teamAbbreviation,
                          accent: accentColor(e.teamAbbreviation), size: 44, showLabels: false)
                Text(e.playerName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(e.teamAbbreviation).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.dsFgTertiary)
                if picked { Text("YOUR PICK ✓").font(.system(size: 10, weight: .bold)).foregroundStyle(accent) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 8)
            .background(picked ? accent.opacity(0.12) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(picked ? accent : .clear, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func submitBar(allMade: Bool, made: Int, total: Int) -> some View {
        VStack(spacing: 10) {
            Button {
                if auth.isSignedIn { Task { await viewModel.submit(store: store, userID: auth.userID) } } else { showSignIn = true }
            } label: {
                Text(allMade ? "Submit picks (locked forever)" : "Submit picks (\(made)/\(total))")
                    .primaryButtonLabel(allMade ? accent : Color.dsBgTertiary, fg: allMade ? .white : Color.dsFgTertiary)
            }
            .disabled(!allMade)
            Button { stage = .intro } label: {
                Text("Save draft (edit later)")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(accent.opacity(0.35), lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        .background(LinearGradient(colors: [.clear, Color.dsBgPrimary], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Submitted state

    private var submittedScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(accent)
            Text("Picks locked in").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text("Your \(viewModel.currentRound?.title ?? "round") picks are submitted. Results drop when voting closes — \(viewModel.closesInText?.lowercased() ?? "soon").")
                .font(.system(size: 14)).foregroundStyle(Color.dsFgSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button { showOverview = true } label: { Text("View bracket").primaryButtonLabel(accent) }.padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Screen 4: Results

    @ViewBuilder
    private var resultsScreen: some View {
        if let result = viewModel.completedResults() {
            let picks = store.picks(for: result.round)
            let correct = BracketScoring.correctCount(picks: picks, matchups: result.matchups)
            let pts = store.score(for: result.round) ?? BracketScoring.roundPoints(picks: picks, matchups: result.matchups)
            ScrollView {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        sectionLabel("\(result.round.title) Complete").foregroundStyle(accent)
                        Text("+\(pts) pts").font(.system(size: 28, weight: .heavy)).foregroundStyle(.white)
                        Text("\(correct) of \(result.matchups.count) correct").font(.system(size: 13)).foregroundStyle(Color.dsFgSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .background(LinearGradient(colors: [accent.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.35)))

                    sectionLabel("Your picks vs community").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(result.matchups) { m in resultCard(m, yourPick: picks[m.id]) }
                    leaderboardCard
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
        } else {
            submittedScreen
        }
    }

    private func resultCard(_ m: BracketMatchup, yourPick: String?) -> some View {
        let splitA = m.splitAPercent ?? 50
        let aWon = m.communityWinnerID == m.entrantA.id
        let correct = yourPick != nil && yourPick == m.communityWinnerID
        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                resultSide(m.entrantA, won: aWon, pct: splitA, isYour: yourPick == m.entrantA.id)
                Text("VS").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.dsFgQuaternary).padding(.horizontal, 2)
                resultSide(m.entrantB, won: !aWon, pct: 100 - splitA, isYour: yourPick == m.entrantB.id)
            }
            HStack(spacing: 3) {
                Rectangle().fill(aWon ? accent : Color.dsFgQuaternary).frame(maxWidth: .infinity).layoutPriority(Double(max(1, splitA)))
                Rectangle().fill(aWon ? Color.dsFgQuaternary : accent).frame(maxWidth: .infinity).layoutPriority(Double(max(1, 100 - splitA)))
            }
            .frame(height: 4).padding(.horizontal, 10)
            Text(correct ? "✓ You picked the winner · +\(m.round.points) pts" : (yourPick == nil ? "— You didn't vote" : "✗ Your pick was eliminated"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(correct ? Color.dsSuccess : (yourPick == nil ? Color.dsFgTertiary : Color.dsError))
                .padding(.bottom, 8)
        }
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resultSide(_ e: BracketEntrant, won: Bool, pct: Int, isYour: Bool) -> some View {
        VStack(spacing: 5) {
            PlayerDot(name: e.playerName, jersey: e.jerseyNumber, teamAbbreviation: e.teamAbbreviation,
                      accent: accentColor(e.teamAbbreviation), size: 40, showLabels: false)
            Text(e.playerName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text("\(pct)%\(isYour ? " · You" : "")").font(.system(size: 13, weight: .bold)).foregroundStyle(won ? accent : Color.dsFgTertiary)
            if won { Text("ADVANCES ✓").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.dsSuccess) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 8)
        .background(won ? accent.opacity(0.12) : .clear).opacity(won ? 1 : 0.6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Leaderboard").padding(.bottom, 6)
            ForEach(viewModel.leaderboard) { row in
                HStack(spacing: 12) {
                    Text("\(row.rank)").font(.system(size: 13, weight: .bold)).foregroundStyle(row.isYou ? accent : Color.dsFgTertiary).frame(width: 32, alignment: .trailing)
                    Text(row.name).font(.system(size: 14, weight: row.isYou ? .bold : .medium)).foregroundStyle(row.isYou ? accent : .white)
                    Spacer()
                    Text("\(row.points) pts").font(.system(size: 13, weight: .semibold)).foregroundStyle(row.isYou ? accent : Color.dsFgSecondary)
                }
                .padding(.vertical, 8).padding(.horizontal, 4)
                .background(row.isYou ? accent.opacity(0.10) : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Screen 5: Bracket Overview

    @ViewBuilder
    private var overviewScreen: some View {
        if let edition = viewModel.edition {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("\(edition.themeLabel) · 2026").font(.system(size: 12, weight: .bold)).tracking(2).foregroundStyle(accent)
                        Text("Bracket Overview").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                        Text("\(edition.entrants.count) entrants → \(edition.rounds.count) rounds → 1 winner")
                            .font(.system(size: 12)).foregroundStyle(Color.dsFgSecondary)
                    }.padding(.vertical, 12)

                    HStack(spacing: 6) {
                        ForEach(edition.rounds, id: \.self) { round in
                            Text(round.shortLabel).font(.system(size: 10, weight: .bold))
                                .foregroundStyle(statusColor(edition.status(of: round)))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(edition.status(of: round) == .active ? accent.opacity(0.12) : Color.white.opacity(0.04))
                                .clipShape(Capsule())
                        }
                    }
                    ForEach(edition.rounds, id: \.self) { round in overviewRound(edition, round) }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(Color.dsBgPrimary.ignoresSafeArea())
            .navigationContextLabel("Bracket")
        }
    }

    private func overviewRound(_ edition: BracketEdition, _ round: BracketRound) -> some View {
        let status = edition.status(of: round)
        let ms = edition.matchups(in: round)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(statusColor(status)).frame(width: 8, height: 8)
                sectionLabel(round.title).foregroundStyle(statusColor(status))
                Text(statusNote(status)).font(.system(size: 10)).foregroundStyle(Color.dsFgTertiary)
            }
            VStack(spacing: 8) {
                if ms.isEmpty {
                    Text("Opens after the current round").font(.system(size: 12)).foregroundStyle(Color.dsFgTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(ms.prefix(6)) { m in overviewMatchup(m) }
                    if ms.count > 6 {
                        Text("Showing 6 · \(ms.count) matchups total").font(.system(size: 11)).foregroundStyle(Color.dsFgTertiary)
                    }
                }
            }
            .padding(.leading, 16)
            .overlay(Rectangle().fill(statusColor(status).opacity(0.3)).frame(width: 2), alignment: .leading)
        }
    }

    private func overviewMatchup(_ m: BracketMatchup) -> some View {
        let aWon = m.communityWinnerID == m.entrantA.id
        let bWon = m.communityWinnerID == m.entrantB.id
        return HStack(spacing: 10) {
            overviewName(m.entrantA, won: aWon, lost: m.isResolved && !aWon)
            Text("VS").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.dsFgQuaternary)
            overviewName(m.entrantB, won: bWon, lost: m.isResolved && !bWon)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func overviewName(_ e: BracketEntrant, won: Bool, lost: Bool) -> some View {
        Text(e.playerName)
            .font(.system(size: 13, weight: won ? .bold : .medium))
            .foregroundStyle(lost ? Color.dsFgTertiary : .white).strikethrough(lost)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🏆").font(.system(size: 44))
            Text("No active bracket").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            Text("A new edition opens soon — check back.").font(.system(size: 14)).foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't load the bracket").font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(Color.dsFgSecondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load(store: store) } }.tint(accent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func accentColor(_ abbr: String) -> Color { clubs.club(forAbbreviation: abbr)?.accentColor ?? .gray }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).tracking(1.2).textCase(.uppercase).foregroundStyle(Color.dsFgSecondary)
    }

    private func statusColor(_ s: BracketEdition.RoundStatus) -> Color {
        switch s { case .complete: return Color.dsSuccess; case .active: return accent; case .upcoming: return Color.dsFgQuaternary }
    }
    private func statusNote(_ s: BracketEdition.RoundStatus) -> String {
        switch s {
        case .complete: return "· Complete"
        case .active: return "· Voting now" + (viewModel.closesInText.map { " · " + $0.replacingOccurrences(of: "Closes in ", with: "") + " left" } ?? "")
        case .upcoming: return "· Opens after current round"
        }
    }
}

// A full-width pill button label in the bracket style.
private extension Text {
    func primaryButtonLabel(_ bg: Color, fg: Color = .white) -> some View {
        self.font(.system(size: 16, weight: .semibold)).foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

#Preview {
    NavigationStack {
        BracketBattleView()
            .environment(BracketStore())
            .environment(ClubStore())
            .environment(AuthStore())
    }
}
