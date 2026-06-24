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
//  Identity: the teal `dsGameBracket` accent; player chips are team-ringed headshots
//  (PlayerHeadshot via PlayerDot), with a jersey-number monogram fallback when a
//  player's photo isn't on file.
//

import SwiftUI

struct BracketBattleView: View {
    @State private var viewModel = BracketViewModel()
    @Environment(BracketStore.self) private var store
    @Environment(ClubStore.self) private var clubs
    @Environment(AuthStore.self) private var auth

    @State private var stage: Stage = .intro
    @State private var gateRequested = false
    /// Result matchups the user has expanded to reveal the vote stats (collapsed by default).
    @State private var expandedMatchups: Set<String> = []
    @State private var expandedRounds: Set<BracketRound> = []
    @State private var expandedRules: Set<String> = []   // collapsible intro rule sections
    @State private var showFullBracket = false

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
        .nativeBackButton(title: "Bracket Battle")
        .background(Color.dsBgPrimary.ignoresSafeArea())
        .task {
            // Start Game Center auth here (a game screen) rather than at launch, so
            // the GC banner only shows when the user is about to play. Idempotent.
            GameCenterManager.shared.authenticate()
            if case .idle = viewModel.state {
                await viewModel.load(store: store, userID: auth.userID, displayName: auth.displayName)
            }
        }
        // Mandatory sign-in + display name to PLAY — gated at "Make your picks" (entry to
        // voting), so the submit downstream is always signed in. "Go back" cancels.
        .fanZoneGate(isRequested: $gateRequested, gameName: "Bracket Battle") { stage = .voting }
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
                overviewBody(banner: submittedBannerText)
            case .scored:
                resultsScreen
            }
        }
    }

    // MARK: - Screen 1: Edition Intro

    @ViewBuilder
    private var introScreen: some View {
        if let edition = viewModel.edition {
            // Flex column: the rules SCROLL in a bounded region; the "Let's Go" CTA is PINNED
            // below them (always reachable — a returning player never scrolls past the rules to
            // play), with "Good to know" pinned beneath the CTA. Matches the gating-flow mockup.
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Image(systemName: "trophy.fill").dsFont(34).foregroundStyle(accent)
                            Text(edition.themeLabel).dsFont(12, weight: .bold).tracking(2).foregroundStyle(accent)
                            Text(edition.title).dsFont(22, weight: .bold).foregroundStyle(.white)
                            Text("\(edition.entrants.count) players · \(viewModel.totalMatchups) brackets · \(edition.rounds.count) rounds")
                                .dsFont(13).foregroundStyle(Color.dsFgSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28).padding(.horizontal, 20)
                        .background(LinearGradient(colors: [accent.opacity(0.12), Color.dsMdCard], startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.35)))

                        rankedBanner(fanCount: edition.fanCount)
                        bracketFunnel(rounds: edition.rounds)
                        howItWorks
                        pointsTable(rounds: edition.rounds)
                        // Detailed rules = collapsible disclosures (collapsed by default) AFTER
                        // points, so the page stays short and detail is opt-in (updated mockup).
                        rulesDisclosure("qualifying", "Qualifying rounds & byes", Self.qualifyingRules)
                        rulesDisclosure("rounds", "How each round works", Self.roundRules)
                        Button { showFullBracket = true } label: {
                            Text("See the full bracket")
                                .dsFont(15, weight: .semibold).foregroundStyle(accent)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(accent.opacity(0.35), lineWidth: 1.5))
                        }
                        goodToKnow   // in the scroll (after "See the full bracket"), not pinned
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                }

                // The ONLY pinned element — gate trigger + subtext (current round · countdown,
                // "Voting open" in manual mode). Nothing below it, so there's no second scroll edge.
                VStack(spacing: 8) {
                    Button { gateRequested = true } label: { Text("Let's Go").primaryButtonLabel(accent) }
                    Text("\(edition.currentRound.title) · \(viewModel.closesInText ?? "Voting open")")
                        .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
            }
            .sheet(isPresented: $showFullBracket) {
                NavigationStack {
                    overviewBody(banner: nil)
                        .navigationTitle("The bracket so far")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { showFullBracket = false } }
                        }
                }
            }
        }
    }

    // Ranked callout near the top of the intro — establishes the stakes (a scored,
    // leaderboard game) before the rules. Uses the SF-Symbol trophy (no emoji in game UI).
    private func rankedBanner(fanCount: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill").dsFont(20).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(fanCount > 0 ? "Ranked — compete with \(fanCount.formatted()) fans" : "Ranked game")
                    .dsFont(14, weight: .bold).foregroundStyle(.white)
                Text("Climb the leaderboard. Track your accuracy in Your Stats.")
                    .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.3)))
    }

    // FAQ-style notes below the CTA — curious players find them, casual players aren't blocked.
    private var goodToKnow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Good to know")
            ForEach(Self.goodToKnowItems, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill").dsFont(5).foregroundStyle(accent).padding(.top, 6)
                    Text(item).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let goodToKnowItems = [
        "New edition every month with a fresh theme",
        "Top-seeded players get byes — they enter later in the bracket",
        "Miss a round? You can still play the rest (you just won't earn points for the ones you missed)",
        "No same-team matchups early — this is about the whole league",
    ]

    // A collapsible rule section (collapsed by default): a teal uppercase header + chevron that
    // expands to reveal the paragraphs. Keeps the intro short while the detail stays one tap away.
    private func rulesDisclosure(_ id: String, _ header: String, _ paragraphs: [String]) -> some View {
        let open = expandedRules.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if open { expandedRules.remove(id) } else { expandedRules.insert(id) }
            } label: {
                HStack {
                    sectionLabel(header)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .dsFont(12, weight: .semibold).foregroundStyle(accent)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(paragraphs, id: \.self) { p in
                        Text(p).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private static let qualifyingRules = [
        "128 players is too many to start all at once, so qualifying rounds trim the field to 64 before the main bracket begins.",
        "Some players get a bye — they sit out qualifying and enter later, once the field's already smaller. Byes are earned by seeding (minutes played, games started): the league's most-used players skip the early rounds, while lower-seeded players battle in from round 1. Same idea as the US Open Cup, where the top sides join in later rounds.",
        "So the draw isn't always fair-feeling — a big name can land a brutal bracket while a lesser-known player gets a clear runway. Seeding rewards the workload; it doesn't promise an easy path.",
    ]

    private static let roundRules = [
        "When a round opens, you'll see every matchup. Vote on all of them — you can't submit until each one has a pick.",
        "Once you submit, that round's picks are locked: no edits, no undo. Rounds stay open 1–2 days; when voting closes, the votes are tallied, winners revealed, points awarded, and the next round opens. Start to finish, an edition runs about 2–3 weeks.",
    ]

    private func bracketFunnel(rounds: [BracketRound]) -> some View {
        VStack(spacing: 6) {
            sectionLabel("Tournament bracket").frame(maxWidth: .infinity)
            ForEach(Array(rounds.enumerated()), id: \.element) { i, round in
                let widthFraction = max(0.12, 1.0 - Double(i) * (0.85 / Double(max(1, rounds.count - 1))))
                if round == .final {
                    Circle().fill(accent).frame(width: 32, height: 32)
                        .overlay(Image(systemName: "trophy.fill").dsFont(13).foregroundStyle(.white))
                    Text("FINAL · 1 winner").dsFont(10, weight: .bold).foregroundStyle(accent)
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
                        .dsFont(10, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
                    if round != rounds.last { Rectangle().fill(Color.dsFgQuaternary).frame(width: 2, height: 8) }
                }
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("How it works")
            ForEach(Array(Self.howItWorksSteps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").dsFont(12, weight: .bold).foregroundStyle(accent)
                        .frame(width: 22, height: 22).background(accent.opacity(0.12)).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).dsFont(14, weight: .bold).foregroundStyle(.white)
                        Text(step.body).dsFont(13).foregroundStyle(Color.dsFgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let howItWorksSteps: [(title: String, body: String)] = [
        ("See the matchups",
         "Each round shows you every head-to-head. Two players, one question. Read the theme and decide: who wins this one?"),
        ("Vote the question, not the jersey",
         "This isn't \"who's your favorite.\" If the theme is Best Goal Celebration, vote the better celebration — even if the other player is on your team. The question is the question."),
        ("Predict the crowd",
         "The community decides who advances. You score points when your pick matches the majority. Think a lesser-known player actually wins the matchup? Trust that read — the crowd might agree with you."),
        ("Lock it in",
         "Submit your picks for the round. Once submitted, they're locked — no edits, no undo. Results drop when voting closes, with vote percentages and your score."),
    ]

    private func pointsTable(rounds: [BracketRound]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Points")
            VStack(spacing: 10) {
                // Simplified to three tiers for onboarding — the full per-round breakdown
                // lives in the bracket overview / Your Stats.
                pointsTier("Early rounds", "+1")
                pointsTier("Round of 16 & Quarterfinals", "+2")
                pointsTier("Semifinals & Final", "+3")
                Divider().overlay(Color.dsFgQuaternary)
                HStack {
                    Text("Max possible (perfect bracket)").dsFont(13, weight: .semibold).foregroundStyle(.white)
                    Spacer()
                    Text("\(BracketScoring.maxPoints(rounds: rounds)) pts").dsFont(13, weight: .bold).foregroundStyle(accent)
                }
            }
            .padding(14).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 14))
            Text("Points increase each round — later picks are worth more because they're harder to predict")
                .dsFont(11).foregroundStyle(Color.dsFgSecondary).frame(maxWidth: .infinity)
            Text("This isn't a popularity contest — you're predicting who the crowd will pick, not who you like best. Your favorite might be the nicest person in the league, but if they're up against someone with serious stare-down energy, voting with your heart will cost you points.")
                .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private func pointsTier(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).dsFont(13).foregroundStyle(Color.dsFgSecondary)
            Spacer()
            Text(value).dsFont(13, weight: .bold).foregroundStyle(accent)
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
                        // A null close time = manual mode (round stays open until advanced) → "Voting open".
                        Text(viewModel.closesInText ?? "Voting open")
                            .dsFont(11).foregroundStyle(Color.dsFgSecondary)
                    }
                    PlayingAsBadge(accent: accent)   // Screen C — gated-in identity
                    VStack(spacing: 6) {
                        HStack {
                            Text("\(made) of \(total) picks made").dsFont(12).foregroundStyle(Color.dsFgSecondary)
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
            Image(systemName: "checkmark.circle.fill").dsFont(20).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("That's all \(viewModel.totalMatchups) — you're ready.").dsFont(14, weight: .bold).foregroundStyle(accent)
                Text("Save a draft to keep tinkering, or lock 'em in. Once they're in, there's no take-backs.")
                    .dsFont(12).foregroundStyle(Color.dsFgSecondary)
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
            Text("VS").dsFont(10, weight: .bold).tracking(1).foregroundStyle(Color.dsFgQuaternary).padding(.horizontal, 2)
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
                          accent: accentColor(e.teamAbbreviation), athleteID: e.id, size: 44, showLabels: false)
                Text(e.playerName).dsFont(13, weight: .semibold).foregroundStyle(.white).lineLimit(1)
                Text(e.teamAbbreviation).dsFont(10, weight: .semibold).foregroundStyle(Color.dsFgTertiary)
                if picked { Text("YOUR PICK ✓").dsFont(10, weight: .bold).foregroundStyle(accent) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 8)
            .background(picked ? accent.opacity(0.12) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(picked ? accent : .clear, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func submitBar(allMade: Bool, made: Int, total: Int) -> some View {
        let submitting = viewModel.submitState == .submitting
        return VStack(spacing: 10) {
            // Online-only: the write must ack before we lock in. A failure surfaces
            // here; the picks stay editable and the button retries.
            if viewModel.submitState == .failed {
                Text("Couldn't submit — tap to retry")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(Color.dsError)
                    .frame(maxWidth: .infinity)
            }
            Button {
                // Entry was gated (Make your picks → voting), so we're always signed in here.
                Task { await viewModel.submit(store: store, userID: auth.userID) }
            } label: {
                Text(submitting ? "Submitting…" : (allMade ? "Lock in my picks" : "Pick all \(total) first (\(made)/\(total))"))
                    .primaryButtonLabel(allMade ? accent : Color.dsBgTertiary, fg: allMade ? .white : Color.dsFgTertiary)
            }
            .disabled(!allMade || submitting)
            Button { stage = .intro } label: {
                Text("Save draft (edit later)")
                    .dsFont(15, weight: .semibold).foregroundStyle(accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(accent.opacity(0.35), lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        .background(LinearGradient(colors: [.clear, Color.dsBgPrimary], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Submitted state → straight into the bracket overview (with a banner)

    /// The post-submit confirmation shown inline atop the overview — no dead-end screen.
    private var submittedBannerText: String {
        let when = viewModel.closesInText.map { $0.replacingOccurrences(of: "Closes in ", with: "in ") } ?? "soon"
        return "Picks locked in — results drop when voting closes \(when)."
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
                        sectionLabel("\(result.round.title) — that's a wrap").foregroundStyle(accent)
                        Text("+\(pts)").dsFont(30, weight: .heavy).foregroundStyle(.white)
                        Text("You called \(correct) of \(result.matchups.count). \(heroVoiceLine(correct, result.matchups.count))")
                            .dsFont(13).foregroundStyle(Color.dsFgSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(20)
                    .background(LinearGradient(colors: [accent.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.35)))

                    shareButton(round: result.round, correct: correct, total: result.matchups.count, pts: pts)

                    if viewModel.flavor == .upsetClosest { upsetClosestCallout }

                    sectionLabel("How the league voted").frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(result.matchups) { m in resultCard(m, yourPick: picks[m.id]) }
                    leaderboardCard
                    fullLeaderboardLink

                    // The bracket journey lives right below the results (CONCEPT-v2).
                    Divider().overlay(Color.dsFgQuaternary).padding(.vertical, 4)
                    overviewContent(banner: nil)
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
        } else {
            overviewBody(banner: nil)
        }
    }

    /// A warm one-liner under the score, keyed to how well you read the crowd.
    private func heroVoiceLine(_ correct: Int, _ total: Int) -> String {
        let ratio = total > 0 ? Double(correct) / Double(total) : 0
        switch ratio {
        case 0.85...: return "You're basically the league hivemind."
        case 0.6..<0.85: return "You read the room nicely."
        case 0.4..<0.6: return "The bracket had other plans."
        default: return "Chaos won this round — regroup."
        }
    }

    // MARK: - Share your card (ImageRenderer → ShareLink)

    private func shareButton(round: BracketRound, correct: Int, total: Int, pts: Int) -> some View {
        let img = shareCardImage(round: round, correct: correct, total: total, pts: pts)
        return ShareLink(item: img, preview: SharePreview("My Bracket Battle card", image: img)) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").dsFont(14, weight: .semibold)
                Text("Share your card")
            }
            .dsFont(14, weight: .semibold).foregroundStyle(accent)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.35), lineWidth: 1.5))
        }
    }

    @MainActor private func shareCardImage(round: BracketRound, correct: Int, total: Int, pts: Int) -> Image {
        let renderer = ImageRenderer(content: shareCard(round: round, correct: correct, total: total, pts: pts))
        renderer.scale = 3
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "trophy.fill")
    }

    private func shareCard(round: BracketRound, correct: Int, total: Int, pts: Int) -> some View {
        VStack(spacing: 8) {
            Text(viewModel.edition?.themeLabel ?? "BRACKET BATTLE")
                .dsFont(13, weight: .bold).tracking(2).foregroundStyle(accent)
            Text(viewModel.edition?.title ?? "Bracket Battle")
                .dsFont(20, weight: .bold).foregroundStyle(.white)
            Text(round.title).dsFont(13).foregroundStyle(Color.dsFgSecondary)
            Text("\(correct)/\(total)").dsFont(52, weight: .heavy).foregroundStyle(.white).padding(.top, 4)
            Text("called right · +\(pts) pts").dsFont(13).foregroundStyle(Color.dsFgSecondary)
            Text("NWSL · Bracket Battle").dsFont(11, weight: .semibold).foregroundStyle(Color.dsFgTertiary).padding(.top, 6)
        }
        .padding(28).frame(width: 320)
        .background(LinearGradient(colors: [accent.opacity(0.18), Color.dsBgPrimary], startPoint: .top, endPoint: .bottom))
    }

    /// Collapsed by default — just who advanced + your call. The vote split stays
    /// hidden behind "See how the league voted" so you scan winners fast, then dig into
    /// the surprises. (% is never shown until you open it — and never during voting.)
    private func resultCard(_ m: BracketMatchup, yourPick: String?) -> some View {
        let aWon = m.communityWinnerID == m.entrantA.id
        let correct = yourPick != nil && yourPick == m.communityWinnerID
        let expanded = expandedMatchups.contains(m.id)
        let winnerName = m.entrant(m.communityWinnerID ?? "")?.playerName ?? "her"
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                resultSide(m.entrantA, won: aWon, isYour: yourPick == m.entrantA.id)
                Text("VS").dsFont(10, weight: .bold).foregroundStyle(Color.dsFgQuaternary).padding(.horizontal, 2)
                resultSide(m.entrantB, won: !aWon, isYour: yourPick == m.entrantB.id)
            }
            Text(correct ? "Nice — you had \(winnerName). +\(m.round.points)"
                 : (yourPick == nil ? "You sat this one out" : "Ouch — your pick went home"))
                .dsFont(11, weight: .semibold)
                .foregroundStyle(correct ? Color.dsSuccess : (yourPick == nil ? Color.dsFgTertiary : Color.dsError))
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded { expandedMatchups.remove(m.id) } else { expandedMatchups.insert(m.id) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(expanded ? "Hide the numbers" : "See how the league voted")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").dsFont(9, weight: .bold)
                }
                .dsFont(11, weight: .semibold).foregroundStyle(accent)
            }
            if expanded { voteStats(m, aWon: aWon) }
        }
        .padding(12).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func resultSide(_ e: BracketEntrant, won: Bool, isYour: Bool) -> some View {
        VStack(spacing: 5) {
            PlayerDot(name: e.playerName, jersey: e.jerseyNumber, teamAbbreviation: e.teamAbbreviation,
                      accent: accentColor(e.teamAbbreviation), athleteID: e.id, size: 40, showLabels: false)
            Text(e.playerName).dsFont(13, weight: won ? .bold : .medium)
                .foregroundStyle(won ? .white : Color.dsFgTertiary).strikethrough(!won).lineLimit(1)
            Text(e.teamAbbreviation + (isYour ? " · your pick" : ""))
                .dsFont(10, weight: .semibold).foregroundStyle(isYour ? accent : Color.dsFgTertiary)
            if won { Text("ADVANCES").dsFont(10, weight: .bold).foregroundStyle(Color.dsSuccess) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 8)
        .background(won ? accent.opacity(0.12) : .clear).opacity(won ? 1 : 0.55)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The "See stats" reveal: a donut of the community split, the legend, the vote
    /// count, and a CLOSE CALL / RUNAWAY badge for the drama.
    private func voteStats(_ m: BracketMatchup, aWon: Bool) -> some View {
        let splitA = m.splitAPercent ?? 50
        let winnerPct = m.winnerPercent ?? max(splitA, 100 - splitA)
        return VStack(spacing: 10) {
            voteDonut(splitA: splitA, aWon: aWon, centerPct: winnerPct)
            VStack(spacing: 4) {
                legendRow(m.entrantA, pct: splitA, winner: aWon)
                legendRow(m.entrantB, pct: 100 - splitA, winner: !aWon)
            }
            if let count = m.voteCount {
                Text("\(count.formatted()) fans voted").dsFont(11).foregroundStyle(Color.dsFgSecondary)
            }
            if winnerPct < 55 { dramaBadge("CLOSE CALL", Color.dsWarning) }
            else if winnerPct > 75 { dramaBadge("RUNAWAY", accent) }
        }
        .padding(.top, 4)
    }

    private func voteDonut(splitA: Int, aWon: Bool, centerPct: Int) -> some View {
        let aFrac = Double(min(max(splitA, 0), 100)) / 100
        return ZStack {
            Circle().trim(from: 0, to: aFrac)
                .stroke(aWon ? accent : Color.dsFgQuaternary, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: aFrac, to: 1)
                .stroke(aWon ? Color.dsFgQuaternary : accent, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(centerPct)%").dsFont(22, weight: .heavy).foregroundStyle(.white)
                Text("WON").dsFont(9, weight: .bold).tracking(1).foregroundStyle(Color.dsFgTertiary)
            }
        }
        .frame(width: 124, height: 124).padding(6)
    }

    private func legendRow(_ e: BracketEntrant, pct: Int, winner: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(winner ? accent : Color.dsFgQuaternary).frame(width: 8, height: 8)
            Text(e.playerName).dsFont(12, weight: winner ? .semibold : .regular).foregroundStyle(winner ? .white : Color.dsFgSecondary)
            Spacer()
            Text("\(pct)%").dsFont(12, weight: .semibold).foregroundStyle(winner ? accent : Color.dsFgTertiary)
        }
    }

    private func dramaBadge(_ text: String, _ color: Color) -> some View {
        Text(text).dsFont(10, weight: .heavy).tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.14)).clipShape(Capsule())
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("Leaderboard").padding(.bottom, 6)
            ForEach(viewModel.leaderboard) { row in
                HStack(spacing: 12) {
                    Text("\(row.rank)").dsFont(13, weight: .bold).foregroundStyle(row.isYou ? accent : Color.dsFgTertiary).frame(width: 32, alignment: .trailing)
                    Text(row.name).dsFont(14, weight: row.isYou ? .bold : .medium).foregroundStyle(row.isYou ? accent : .white)
                    Spacer()
                    Text("\(row.points) pts").dsFont(13, weight: .semibold).foregroundStyle(row.isYou ? accent : Color.dsFgSecondary)
                }
                .padding(.vertical, 8).padding(.horizontal, 4)
                .background(row.isYou ? accent.opacity(0.10) : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Entry point to the standalone Leaderboard (Rankings + Your Stats), pushed onto
    /// Home's NavigationStack from the results + overview.
    private var fullLeaderboardLink: some View {
        NavigationLink {
            BracketLeaderboardView(editionID: viewModel.edition?.id, myUserID: auth.userID,
                                   myName: auth.displayName ?? "You", myPoints: store.points)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.number").dsFont(13, weight: .semibold)
                Text("Full leaderboard & your stats").dsFont(14, weight: .semibold)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").dsFont(12, weight: .semibold)
            }
            .foregroundStyle(accent)
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Screen 5: Bracket Overview (the tournament story)

    /// Standalone scrollable overview — the post-submit landing, with a banner.
    @ViewBuilder
    private func overviewBody(banner: String?) -> some View {
        if viewModel.edition != nil {
            ScrollView {
                overviewContent(banner: banner)
                    .padding(.horizontal, 16).padding(.bottom, 32)
            }
            .background(Color.dsBgPrimary.ignoresSafeArea())
        }
    }

    /// The full bracket journey — every round as complete · active · upcoming so the
    /// user sees what already happened, what's live, and what's coming. No own
    /// ScrollView, so it also sits BELOW the results list.
    @ViewBuilder
    private func overviewContent(banner: String?) -> some View {
        if let edition = viewModel.edition {
            VStack(spacing: 16) {
                if let banner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").dsFont(18).foregroundStyle(accent)
                        Text(banner).dsFont(13, weight: .semibold).foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(12).background(accent.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.35)))
                }
                VStack(spacing: 4) {
                    Text(edition.themeLabel).dsFont(12, weight: .bold).tracking(2).foregroundStyle(accent)
                    Text("The bracket so far").dsFont(20, weight: .bold).foregroundStyle(.white)
                    Text("\(edition.entrants.count) in · \(edition.rounds.count) rounds · 1 left standing")
                        .dsFont(12).foregroundStyle(Color.dsFgSecondary)
                }.padding(.top, 4)

                if viewModel.flavor == .cinderella, let c = viewModel.cinderella, let seed = c.seed {
                    calloutCard(icon: "sparkles", title: "Cinderella watch",
                                body: "#\(seed) \(c.playerName) (\(c.teamAbbreviation)) is still dancing — nobody saw this run coming.")
                }

                // Legend: a dot + label per round, colored by status.
                HStack(spacing: 6) {
                    ForEach(edition.rounds, id: \.self) { round in
                        let st = edition.status(of: round)
                        HStack(spacing: 4) {
                            Circle().fill(statusColor(st)).frame(width: 6, height: 6)
                            Text(round.shortLabel).dsFont(10, weight: .bold).foregroundStyle(statusColor(st))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(st == .active ? accent.opacity(0.12) : Color.white.opacity(0.04))
                        .clipShape(Capsule())
                    }
                }
                ForEach(edition.rounds, id: \.self) { round in overviewRound(edition, round) }

                fullLeaderboardLink

                if viewModel.flavor == .nextEdition {
                    calloutCard(icon: "calendar", title: "What's next",
                                body: "Once this one crowns a champion, a fresh edition drops — new names, new chaos.")
                }
            }
        }
    }

    /// A warm flavor callout (upset / closest call / Cinderella / next edition).
    private func calloutCard(icon: String, title: String, body: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).dsFont(18).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(11, weight: .bold).tracking(0.5).textCase(.uppercase).foregroundStyle(accent)
                Text(body).dsFont(13).foregroundStyle(Color.dsFgSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.25)))
    }

    @ViewBuilder
    private var upsetClosestCallout: some View {
        VStack(spacing: 8) {
            if let upset = viewModel.biggestUpset {
                calloutCard(icon: "bolt.fill", title: "Biggest upset",
                            body: "\(upset.winner.playerName) sent \(upset.loser.playerName) home. The bracket is chaos and we're here for it.")
            }
            if let close = viewModel.closestCall {
                calloutCard(icon: "scalemass.fill", title: "Too close to call",
                            body: "\(close.matchup.entrantA.playerName) vs \(close.matchup.entrantB.playerName) came down to \(close.winnerPct)–\(100 - close.winnerPct). Brutal.")
            }
        }
    }

    private func overviewRound(_ edition: BracketEdition, _ round: BracketRound) -> some View {
        let status = edition.status(of: round)
        let ms = edition.matchups(in: round)
        let cap = 6
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(statusColor(status)).frame(width: 8, height: 8)
                sectionLabel(round.title).foregroundStyle(statusColor(status))
                Text(statusNote(status)).dsFont(10).foregroundStyle(Color.dsFgSecondary)
            }
            VStack(spacing: 8) {
                if ms.isEmpty {
                    // Upcoming — show the bracket structure ahead as TBD slots.
                    ForEach(0..<min(cap, round.matchupCount), id: \.self) { _ in tbdSlot }
                    if round.matchupCount > cap { overflowNote(round.matchupCount - cap) }
                } else {
                    let expanded = expandedRounds.contains(round)
                    ForEach(expanded ? Array(ms) : Array(ms.prefix(cap))) { m in overviewMatchup(m) }
                    if ms.count > cap {
                        Button {
                            if expanded { expandedRounds.remove(round) } else { expandedRounds.insert(round) }
                        } label: {
                            Text(expanded ? "Show less" : "+\(ms.count - cap) more")
                                .dsFont(11, weight: .semibold).foregroundStyle(accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 16)
            .overlay(Rectangle().fill(statusColor(status).opacity(0.3)).frame(width: 2), alignment: .leading)
        }
        .padding(.top, 4)
    }

    private func overflowNote(_ n: Int) -> some View {
        Text("+\(n) more").dsFont(11).foregroundStyle(Color.dsFgSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tbdSlot: some View {
        HStack(spacing: 10) {
            Text("TBD").dsFont(13, weight: .medium).foregroundStyle(Color.dsFgQuaternary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("VS").dsFont(10, weight: .bold).foregroundStyle(Color.dsFgQuaternary)
            Text("TBD").dsFont(13, weight: .medium).foregroundStyle(Color.dsFgQuaternary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.dsMdCard.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// A matchup row in the overview. Resolved rounds show winner (bold) + loser
    /// (struck through, dimmed) with each side's vote %; the active round shows the
    /// live pairing without a result yet.
    private func overviewMatchup(_ m: BracketMatchup) -> some View {
        let resolved = m.isResolved
        let aWon = resolved && m.communityWinnerID == m.entrantA.id
        let bWon = resolved && m.communityWinnerID == m.entrantB.id
        let aPct = m.splitAPercent
        return HStack(spacing: 10) {
            overviewSide(m.entrantA, won: aWon, lost: resolved && !aWon,
                         pct: resolved ? aPct : nil, alignTrailing: false)
            Text("VS").dsFont(10, weight: .bold).foregroundStyle(Color.dsFgQuaternary)
            overviewSide(m.entrantB, won: bWon, lost: resolved && !bWon,
                         pct: resolved ? aPct.map { 100 - $0 } : nil, alignTrailing: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.dsMdCard).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func overviewSide(_ e: BracketEntrant, won: Bool, lost: Bool, pct: Int?, alignTrailing: Bool) -> some View {
        HStack(spacing: 6) {
            if alignTrailing, let pct { pctText(pct, won: won) }
            Text(e.playerName)
                .dsFont(13, weight: won ? .bold : .medium)
                .foregroundStyle(lost ? Color.dsFgTertiary : .white).strikethrough(lost).lineLimit(1)
            if !alignTrailing, let pct { pctText(pct, won: won) }
        }
        .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
    }

    private func pctText(_ p: Int, won: Bool) -> some View {
        Text("\(p)%").dsFont(11, weight: won ? .bold : .regular)
            .foregroundStyle(won ? accent : Color.dsFgTertiary)
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy").dsFont(40).foregroundStyle(Color.dsFgTertiary)
            Text("Nothing live right now").dsFont(18, weight: .semibold).foregroundStyle(.white)
            Text("A fresh bracket drops soon — come back and we'll do it all again.").dsFont(14).foregroundStyle(Color.dsFgSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
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
        // Teal accent for a consistent Bracket section-header look (callers that need a
        // status-specific color, e.g. the overview round headers, override foregroundStyle).
        Text(text).dsFont(11, weight: .bold).tracking(1.2).textCase(.uppercase).foregroundStyle(accent)
    }

    private func statusColor(_ s: BracketEdition.RoundStatus) -> Color {
        switch s { case .complete: return Color.dsSuccess; case .active: return accent; case .upcoming: return Color.dsFgQuaternary }
    }
    private func statusNote(_ s: BracketEdition.RoundStatus) -> String {
        switch s {
        case .complete: return "· Complete"
        case .active: return "· Voting now" + (viewModel.closesInText.map { " · " + $0.replacingOccurrences(of: "Closes in ", with: "") + " left" } ?? "")
        case .upcoming: return "· Upcoming"
        }
    }
}

// A full-width pill button label in the bracket style.
private extension Text {
    func primaryButtonLabel(_ bg: Color, fg: Color = .white) -> some View {
        self.dsFont(16, weight: .semibold).foregroundStyle(fg)
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
