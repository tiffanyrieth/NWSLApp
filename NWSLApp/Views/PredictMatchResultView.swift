//
//  PredictMatchResultView.swift
//  NWSLApp
//
//  The per-match result for Predict the XI. Redesigned 2026-07-28: your predicted XI is laid out on
//  a pitch and revealed a line at a time, led by the number a fan would actually say out loud —
//  "8 of 11 starters" — with the community's picks alongside your own.
//
//  ⚠️ POINTS ARE THE ACCOUNTING, NOT THE HEADLINE. "46 of 88" is meaningful to a scoring function
//  and meaningless to a person; nobody posts it. Starters-called is the hero everywhere on this
//  screen and the point total is a supporting line, with the full model itemized in the breakdown.
//
//  ⚠️ PUSHED, NOT A SHEET (changed in the redesign). It used to be a `.sheet` with a "Done" button.
//  The reveal, the share affordance and the unseen-results routing all need a real screen with a
//  real back affordance, and a sheet's grabber competes with the pitch for the top of the view.
//
//  ⚠️ ARENA FAMILY. It previously used `dsBgGrouped`/`dsBgCard` — the COMMUNITY-family surfaces —
//  while Predict is COMPETITIVE (`.claude/rules/fan-zone.md`). Fixed here: page `dsBgPrimary`,
//  cards `dsMdCard`, matching the landing screen it's pushed from.
//
//  The actual lineup is NOT persisted (the store keeps only the derived score breakdown), so it's
//  re-fetched from `/summary` on appear. A fetch failure shows an honest retry, never a blank or a
//  guess — and never a partial reveal against a half-known answer key.
//

import SwiftUI

struct PredictMatchResultView: View {
    let item: PredictXIViewModel.PredictionItem
    /// The screen's owner VM (held as `@State` in PredictXIView, passed in — it's a reference type).
    let viewModel: PredictXIViewModel
    /// The next fixture still open for prediction, for the closing CTA. nil → a muted line, no button.
    var nextFixture: PredictionFixture?
    /// Called when the user leaves via the CTA, so the parent can route onward.
    var onPredictNext: ((PredictionFixture) -> Void)?

    @Environment(PredictionStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var model = PredictResultViewModel()
    @State private var showConsensus = false

    private let accent = Color.dsGamePredict

    private var score: PredictionScore { item.score ?? .zero }
    private var prediction: XIPrediction? { item.prediction }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                switch model.phase {
                case .loading:
                    loadingRow
                case .failed:
                    RetryStateView(title: "Couldn't load the lineup",
                                   message: "We couldn't reach the match details. Check your connection and try again.") {
                        await load()
                    }
                case .loaded:
                    revealCaptionRow
                    pitch
                    belowThePitch
                }
            }
            .padding(20)
            .fanZonePlayingAsHeader(accent: accent)
        }
        .background(Color.dsBgPrimary)
        .nativeBackButton(title: "Match result")
        .task { await load() }
        // A reveal task that outlives its screen would go on mutating a torn-down view model.
        .onDisappear { model.cancelReveal() }
    }

    private func load() async {
        await model.load(item: item, parent: viewModel, store: store, auth: auth,
                         reduceMotion: reduceMotion, voiceOver: voiceOver)
        // Mark seen only once the result actually RENDERED. Marking on appear would burn the
        // one-time reveal on a failed fetch, and the user would never get it back.
        if case .loaded = model.phase { store.markResultSeen(fixtureID: item.fixture.id) }
    }

    // MARK: - Header

    private var header: some View {
        let f = item.fixture
        let homeAbbr = f.isHome ? f.teamAbbreviation : f.opponentAbbreviation
        let awayAbbr = f.isHome ? f.opponentAbbreviation : f.teamAbbreviation
        return VStack(spacing: 8) {
            Text("RESULTS\(model.detail?.weekLabel.map { " · \($0.uppercased())" } ?? "")")
                .dsFont(11, weight: .bold).tracking(1.2).foregroundStyle(accent)
            HStack(spacing: 14) {
                crestColumn(homeAbbr)
                VStack(spacing: 3) {
                    if let final = item.finalScore {
                        Text("\(final.home)–\(final.away)").dsFont(24, weight: .heavy, monospacedDigit: true)
                        Text("FT").dsFont(11, weight: .bold).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 72)
                crestColumn(awayAbbr)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func crestColumn(_ abbr: String) -> some View {
        VStack(spacing: 6) {
            TeamLogo(urlString: viewModel.club(forAbbreviation: abbr)?.logoURL, teamAbbreviation: abbr, size: 44)
            Text(abbr).font(.caption.weight(.bold))
                .foregroundStyle(Color.teamColor(for: abbr, liftOnDark: true, fallback: accent))
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading the lineup…").dsFont(13).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    // MARK: - Reveal caption + pitch

    /// One non-wrapping row: what's being revealed on the left, the control on the right.
    private var revealCaptionRow: some View {
        HStack(spacing: 8) {
            Text(model.revealCaption.uppercased())
                .dsFont(12, weight: .bold).tracking(0.6)
                .foregroundStyle(model.isRevealing ? accent : Color.dsFgSecondary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            if model.isRevealing {
                Button("Skip") { model.skipReveal() }
                    .dsFont(12, weight: .semibold)
                    .foregroundStyle(Color.dsFgSecondary)
                    .fixedSize()
            } else {
                Button { model.replayReveal() } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                        .dsFont(12, weight: .semibold)
                        .foregroundStyle(accent)
                        .fixedSize()
                }
                // When auto-play was suppressed (Reduce Motion, VoiceOver, or the fourth-plus view
                // of the season), promote Replay from a quiet link to an obvious pill — otherwise
                // the animation becomes undiscoverable for exactly the people who opted out of it.
                .modifier(ReplayPillStyle(enabled: model.revealIsOptIn, accent: accent))
            }
        }
    }

    @ViewBuilder
    private var pitch: some View {
        if let prediction, let formation = Formation(raw: prediction.formation) {
            PredictPitchView(formation: formation,
                             picks: model.picks,
                             revealedBands: model.revealedBands,
                             accent: accent)
        }
    }

    // MARK: - Everything below the pitch

    private var belowThePitch: some View {
        VStack(alignment: .leading, spacing: 18) {
            summaryCard
            rankLine
            callSummary
            breakdownSection
            standoutSection
            yourXISection
            missedSection
            consensusSection
            shareRow
            nextMatchCTA
        }
        .opacity(model.contentShown ? 1 : 0)
        .offset(y: model.contentShown ? 0 : 10)
        // Deliberately NOT removed from the hierarchy while hidden: the content stays in the
        // accessibility tree throughout, so VoiceOver never has to wait out an animation to read
        // the result. Only the visuals are staged.
        .allowsHitTesting(model.contentShown)
    }

    // MARK: - Performance summary

    private var summaryCard: some View {
        VStack(spacing: 6) {
            ScoreRing(fraction: CGFloat(model.startersCalled) / 11,
                      accent: accent,
                      size: 110,
                      animated: true) {
                VStack(spacing: 0) {
                    Text("\(model.startersCalled)").dsFont(28, weight: .heavy).foregroundStyle(Color.dsFgPrimary)
                    Text("of 11").dsFont(11).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.startersCalled) of 11 starters called")

            Text("+\(score.total) pts this match")
                .dsFont(18, weight: .bold).foregroundStyle(Color.dsSuccess)
            Text("\(score.correctPositions) in the right position")
                .dsFont(13).foregroundStyle(.secondary)

            if let line = model.superlative {
                Text(line).dsFont(12, weight: .bold).foregroundStyle(accent)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20).padding(.horizontal, 16)
        .background(
            LinearGradient(colors: [accent.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
        )
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Round rank
    //
    // ⚠️ ROUND-SCOPED, and that's the finest rank that exists. A match has no leaderboard of its own
    // — it sits inside a soccer-week round — so there is deliberately no per-match rank and no
    // per-match rank delta here.
    //
    // The population is always stated ("#12 of 340"), per the rank-display rule: "#12" alone can't
    // distinguish 12 of 14 from 12 of 3,000. The "next rung" half of that rule is applied on the
    // landing season card, where the neighbouring rows are already fetched and the gap is a real
    // number belonging to a real person. It is NOT applied here, because this rank comes from a
    // COUNT query with no neighbouring row to name — and inventing a target would be fabricated data.

    @ViewBuilder
    private var rankLine: some View {
        if let d = model.detail, let rank = d.roundRank, d.roundTotal > 0 {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").dsFont(13).foregroundStyle(accent)
                Text("This round: #\(rank) of \(d.roundTotal)\(d.weekLabel.map { " · \($0)" } ?? "")")
                    .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
        }
    }

    // MARK: - Your calls (formation + scoreline)

    @ViewBuilder
    private var callSummary: some View {
        if let p = prediction, let d = model.detail, let final = item.finalScore {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("YOUR CALLS")
                callRow(title: "Formation",
                        you: p.formation,
                        actual: d.actualFormation ?? "—",
                        correct: score.formationCorrect,
                        partial: nil)
                callRow(title: "Final score",
                        you: "\(p.homeScoreGuess)–\(p.awayScoreGuess)",
                        actual: "\(final.home)–\(final.away)",
                        correct: score.exactScoreline,
                        partial: score.resultCorrect ? "Right result" : nil)
            }
        }
    }

    private func callRow(title: String, you: String, actual: String, correct: Bool, partial: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(correct ? Color.dsSuccess : Color.dsFgTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsFont(14, weight: .semibold)
                if let partial, !correct {
                    Text(partial).dsFont(11, weight: .semibold).foregroundStyle(accent)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("You: \(you)").dsFont(12).foregroundStyle(.secondary)
                Text("Actual: \(actual)").dsFont(12, weight: .semibold)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    // MARK: - Point breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("POINT BREAKDOWN")
            breakdownRow("Correct players", detail: "\(score.correctPlayers)/11",
                         points: score.playersPoints, earned: score.correctPlayers > 0)
            breakdownRow("Right position", detail: "\(score.correctPositions)",
                         points: score.positionsPoints, earned: score.correctPositions > 0)
            breakdownRow("Formation", detail: score.formationCorrect ? "Correct" : "Missed",
                         points: score.formationPoints, earned: score.formationCorrect)
            breakdownRow("Exact score", detail: score.exactScoreline ? "Nailed it" : "Missed",
                         points: score.scorelinePoints, earned: score.exactScoreline)
            breakdownRow("Result (W/D/L)", detail: score.resultCorrect ? "Correct" : "Missed",
                         points: score.resultPoints, earned: score.resultCorrect)
            // Only when earned — an unearned Perfect XI row reads as a rebuke every single match.
            if score.perfectXI {
                breakdownRow("Perfect XI bonus", detail: "All 11!", points: score.perfectPoints, earned: true)
            }
            HStack {
                Text("Total").dsFont(15, weight: .bold)
                Spacer()
                Text("\(score.total) of \(PredictionScore.maxPerMatch)")
                    .dsFont(15, weight: .heavy).foregroundStyle(accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 11)
        }
    }

    private func breakdownRow(_ title: String, detail: String, points: Int, earned: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: earned ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(earned ? Color.dsSuccess : .secondary)
            Text(title).dsFont(15, weight: .semibold)
            Spacer()
            Text(detail).dsFont(12).foregroundStyle(.secondary)
            Text(earned ? "+\(points)" : "+0")
                .font(.caption.weight(.bold))
                .foregroundStyle(earned ? accent : .secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    // MARK: - Standout picks
    //
    // Computed, never authored — and omitted entirely when the community data isn't there to
    // support them, rather than shown with a placeholder percentage.

    @ViewBuilder
    private var standoutSection: some View {
        if model.standouts.hit != nil || model.standouts.miss != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("STANDOUT PICKS")
                if let hit = model.standouts.hit, let share = hit.communityShare {
                    standoutCard(icon: "star.circle.fill", tint: .dsSuccess,
                                 title: "Biggest hit · \(hit.name)",
                                 body: "Only \(PredictPitchView.percent(share)) of \(clubLabel) had her starting. You did.")
                }
                if let miss = model.standouts.miss, let share = miss.communityShare {
                    standoutCard(icon: "xmark.circle.fill", tint: .dsError,
                                 title: "Biggest miss · \(miss.name)",
                                 body: "She started and \(PredictPitchView.percent(share)) of \(clubLabel) had her in. You left her out.")
                }
            }
        }
    }

    private func standoutCard(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).dsFont(20).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(13, weight: .bold)
                Text(body).dsFont(12).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Your XI, grouped by line

    private var yourXISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("YOUR XI")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.bandTallies, id: \.group) { tally in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(bandTitle(tally.group).uppercased())
                                .dsFont(11, weight: .bold).tracking(0.8).foregroundStyle(Color.dsFgTertiary)
                            Spacer()
                            Text("\(tally.started)/\(tally.total)")
                                .dsFont(11, weight: .bold)
                                .foregroundStyle(tally.started == tally.total ? Color.dsSuccess : Color.dsFgSecondary)
                        }
                        ForEach(model.picks.filter { $0.slot.group == tally.group }) { pick in
                            pickRow(pick)
                        }
                    }
                }
                // ⚠️ `submissions > 0`, not just non-nil. A FINISHED match with nobody's predictions in
                // it comes back revealed-but-empty, and the bar explainer then rendered over a list
                // with no bars at all ("· 0 predictions"). Caught in-sim 2026-07-28.
                if let community = model.community, community.submissions > 0 {
                    Text("Bars show how much of \(clubLabel) picked each player · \(community.submissions) prediction\(community.submissions == 1 ? "" : "s")")
                        .dsFont(10.5).foregroundStyle(Color.dsFgTertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background(Color.dsMdCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        }
    }

    private func pickRow(_ pick: PredictPickResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pick.state.started ? "checkmark.circle.fill" : "xmark.circle")
                .dsFont(13)
                .foregroundStyle(stateColor(pick.state))
                .frame(width: 16)
            Text(pick.slot.group.shortLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.dsFgQuaternary)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pick.name)
                        .dsFont(13, weight: .medium)
                        .foregroundStyle(pick.state.started ? Color.dsFgPrimary : Color.dsFgSecondary)
                        .strikethrough(!pick.state.started)
                        .lineLimit(1)
                    if case .startedOffBand(let actual) = pick.state {
                        Text("started in \(actual.shortLabel)")
                            .dsFont(11, weight: .semibold).foregroundStyle(Color.dsWarning)
                    }
                }
                if let share = pick.communityShare {
                    shareBar(share, tint: pick.state.started ? Color.dsSuccess : Color.dsFgQuaternary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func shareBar(_ share: Double, tint: Color) -> some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dsBgTertiary)
                    Capsule().fill(tint).frame(width: geo.size.width * share)
                }
            }
            .frame(height: 4)
            Text(PredictPitchView.percent(share))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsFgTertiary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Also started — you missed
    //
    // Its OWN section, unbound from any slot. An actual starter you missed has no counterpart among
    // your picks: the player who really started at right-back may be someone you played in midfield,
    // in which case she's a HIT. Putting these under a struck-through pick would imply a
    // slot-for-slot substitution the scorer never performs.

    @ViewBuilder
    private var missedSection: some View {
        if !model.missed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("ALSO STARTED — YOU MISSED")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.missed) { starter in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.down.circle").dsFont(13).foregroundStyle(accent).frame(width: 16)
                            Text(starter.group.shortLabel)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.dsFgQuaternary)
                                .frame(width: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(starter.name).dsFont(13, weight: .medium).lineLimit(1)
                                if let share = starter.communityShare { shareBar(share, tint: accent) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14)
                .background(Color.dsMdCard)
                .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
            }
        }
    }

    // MARK: - Community consensus XI
    //
    // Behind an explicit tap, so it MAY state that the crowd did better than you — that's factual
    // data the user asked to see. The no-deficit rule applies only to the superlative slot, which
    // the user doesn't opt into.

    @ViewBuilder
    private var consensusSection: some View {
        if let community = model.community, community.submissions > 0, !model.consensusXI.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showConsensus.toggle() }
                } label: {
                    HStack {
                        Text("\(clubLabel)'s consensus XI").dsFont(13, weight: .semibold)
                            .foregroundStyle(Color.dsFgPrimary)
                        Spacer()
                        Text(showConsensus ? "Hide" : "Show").dsFont(11, weight: .bold).foregroundStyle(accent)
                        Image(systemName: showConsensus ? "chevron.up" : "chevron.down")
                            .dsFont(11).foregroundStyle(accent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .frame(maxWidth: .infinity)
                    .background(Color.dsMdCard)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showConsensus {
                    VStack(alignment: .leading, spacing: 8) {
                        if let correct = model.consensusCorrect {
                            Text("The XI the most fans picked. The crowd got \(correct) of 11 starters.")
                                .dsFont(12).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(consensusByBand, id: \.group) { row in
                            HStack(alignment: .top, spacing: 8) {
                                Text(bandTitle(row.group).uppercased())
                                    .dsFont(10, weight: .bold).tracking(0.6)
                                    .foregroundStyle(Color.dsFgTertiary)
                                    .frame(width: 68, alignment: .leading)
                                Text(row.names.joined(separator: " · "))
                                    .dsFont(12).foregroundStyle(Color.dsFgPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("From \(community.submissions) prediction\(community.submissions == 1 ? "" : "s")")
                            .dsFont(10.5).foregroundStyle(Color.dsFgTertiary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.dsMdCard)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
                }
            }
        }
    }

    private var consensusByBand: [(group: PositionGroup, names: [String])] {
        guard let prediction, let formation = Formation(raw: prediction.formation) else { return [] }
        return PositionGroup.allCases.compactMap { group in
            let names = formation.slots
                .filter { $0.group == group }
                .compactMap { model.consensusXI[$0.index] }
                .compactMap { model.detail?.names[$0] }
            return names.isEmpty ? nil : (group, names)
        }
    }

    // MARK: - Share
    //
    // The second share moment (the first is pre-kickoff, on the locked-wait screen): the same XI,
    // now with ✓/✗ and the score.

    @ViewBuilder
    private var shareRow: some View {
        if let prediction, let formation = Formation(raw: prediction.formation) {
            PredictShareLink(
                card: PredictShareCard(
                    kind: .postMatch,
                    teamAbbr: item.fixture.teamAbbreviation,
                    opponentAbbr: item.fixture.opponentAbbreviation,
                    formation: formation,
                    rows: model.picks.map {
                        PredictShareCard.Row(band: $0.slot.group.shortLabel,
                                             name: $0.name,
                                             marker: $0.state.started)
                    },
                    // Starters called leads the share card too — it's the sentence that travels.
                    headline: "\(model.startersCalled) of 11",
                    subhead: "starters called · \(score.total) pts",
                    accent: accent),
                label: "Share your result",
                accent: accent)
        }
    }

    // MARK: - Next match

    @ViewBuilder
    private var nextMatchCTA: some View {
        if let next = nextFixture {
            VStack(spacing: 8) {
                // `.filled` is hardwired to the app's blue accent; `.gradient` is how a Fan Zone
                // game tints a CTA with its own colour without re-rolling the button.
                DSButton("Next up: \(next.teamAbbreviation) vs \(next.opponentAbbreviation) — predict now",
                         style: .gradient(AnyShapeStyle(accent))) {
                    onPredictNext?(next)
                }
                Text("Locks \(Self.lockFormatter.string(from: next.deadline))")
                    .dsFont(11).foregroundStyle(.secondary)
            }
        } else {
            // Hide-when-empty: a disabled button promising something that isn't there is worse than
            // an honest line.
            Text("Next fixture opens soon")
                .dsFont(12).foregroundStyle(Color.dsFgTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private var clubLabel: String {
        model.detail?.clubName ?? item.fixture.teamAbbreviation
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).dsFont(11, weight: .bold).tracking(1.2).foregroundStyle(.secondary)
    }

    private func bandTitle(_ group: PositionGroup) -> String {
        switch group {
        case .gk: return "Goalkeeper"
        case .def: return "Defense"
        case .mid: return "Midfield"
        case .fwd: return "Attack"
        }
    }

    private func stateColor(_ state: PredictPickResult.State) -> Color {
        switch state {
        case .startedInBand: return .dsSuccess
        case .startedOffBand: return .dsWarning
        case .didNotStart: return .dsError
        }
    }

    private static let lockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}

/// Promotes the Replay control to a bordered pill when the reveal didn't auto-play.
private struct ReplayPillStyle: ViewModifier {
    let enabled: Bool
    let accent: Color

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(accent.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))
        } else {
            content
        }
    }
}
