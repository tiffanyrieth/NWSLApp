//
//  PredictMatchResultView.swift
//  NWSLApp
//
//  The per-match result for Predict the XI. Reworked 2026-07-28 after the owner's first-pass
//  review; the rules that came out of it govern this whole file:
//
//  ⚠️ THE PITCH IS THE REAL XI (owner call). The moment is seeing the actual lineup and how much of
//  it you called — green ✓ called, red ✗ missed, nothing else. Your picks who sat are one quiet
//  line, not a section, and "Also started — you missed" no longer exists: a starter you missed is
//  simply a red node on the pitch.
//
//  ⚠️ EVERY NUMBER IS LABELED (owner rule: an unexplained number is an apple on a pitch — a reader
//  should never have to guess "40% of what?"). The ring says what it counts, the rank row is a
//  sentence, the legend explains the marks, and community percentages appear ONLY inside the
//  expandable band panels, each with its own explanation. Nothing floats.
//
//  ⚠️ ONE ACCOUNTING, NOT TWO. The old "Your calls" cards restated what the point breakdown already
//  showed; they're merged — the breakdown rows carry the You/Actual detail inline, so a single
//  section fully explains the total.
//
//  ⚠️ POINTS ARE THE ACCOUNTING, NOT THE HEADLINE. Starters-called leads everywhere; the point
//  total supports it. Pushed screen, arena family, actual lineup re-fetched from `/summary` on
//  appear (never persisted) — a fetch failure shows an honest retry, never a partial reveal.
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
                    pitchLegend
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
        // Mark seen only once the result actually RENDERED — a failed fetch must not burn the
        // one-time reveal.
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
        // The two-team club-color wash — the SAME treatment every match-results surface wears
        // (schedule cards, the Predict landing's fixture/result cards), so this screen reads as
        // part of the app rather than its own thing (owner branding + anti-drift call).
        .background { TeamWashBackground(base: .dsMdCard, home: teamColor(homeAbbr), away: teamColor(awayAbbr)) }
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
    }

    private func teamColor(_ abbreviation: String) -> Color {
        Color.teamColor(for: abbreviation, liftOnDark: true, fallback: .dsFgSecondary)
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

    // MARK: - Pitch

    /// The caption naming what's landing. No Skip, no Replay (owner cut, second review): the
    /// reveal is ~3 seconds and appears only here — controls for it were more chrome than the
    /// animation is long. It simply plays each time (Reduce Motion / VoiceOver land revealed).
    private var revealCaptionRow: some View {
        Text(model.revealCaption.uppercased())
            .dsFont(12, weight: .bold).tracking(0.6)
            .foregroundStyle(model.isRevealing ? accent : Color.dsFgSecondary)
            .lineLimit(1).truncationMode(.tail)
    }

    private var pitch: some View {
        PredictPitchView(starters: model.starters,
                         formation: model.actualFormation,
                         revealedBands: model.revealedBands)
    }

    /// The legend + your busts. Every mark on the pitch is explained here, per the labeling rule.
    @ViewBuilder
    private var pitchLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                legendDot(color: .dsSuccess, symbol: "checkmark", text: "you called her")
                legendDot(color: .dsError, symbol: "xmark", text: "you missed her")
            }
            if !model.busts.isEmpty {
                Text("Your pick\(model.busts.count == 1 ? "" : "s") who didn't start: \(model.busts.map(\.name).joined(separator: ", "))")
                    .dsFont(12.5).foregroundStyle(Color.dsFgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(model.contentShown ? 1 : 0)
    }

    private func legendDot(color: Color, symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Color.dsBgPrimary)
                .frame(width: 15, height: 15)
                .background(Circle().fill(color))
            Text(text).dsFont(12.5).foregroundStyle(Color.dsFgSecondary)
        }
    }

    // MARK: - Everything below the pitch

    private var belowThePitch: some View {
        VStack(alignment: .leading, spacing: 18) {
            summaryCard
            rankRow
            breakdownSection
            standoutSection
            fanPicksSection
            shareRow
            nextMatchCTA
        }
        .opacity(model.contentShown ? 1 : 0)
        .offset(y: model.contentShown ? 0 : 10)
        // Content stays in the a11y tree throughout — VoiceOver never waits out an animation.
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
            .accessibilityLabel("You called \(model.startersCalled) of the 11 starters")

            // The ring's own label — "10 of 11" must never float unexplained.
            Text("starters called").dsFont(12, weight: .semibold).foregroundStyle(.secondary)

            Text("+\(score.total) pts this match")
                .dsFont(18, weight: .bold).foregroundStyle(Color.dsSuccess)
                .padding(.top, 2)
            Text("\(score.correctPositions) of your \(score.correctPlayers) were in the right line")
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

    // MARK: - Rank
    //
    // A full sentence (owner rule), round-scoped — a match has no leaderboard of its own; the
    // soccer-week round is the finest rank that exists, so there is deliberately no per-match rank.

    @ViewBuilder
    private var rankRow: some View {
        if let d = model.detail, let rank = d.roundRank, d.roundTotal > 0 {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").dsFont(13).foregroundStyle(accent)
                Text("Ranked #\(rank) of \(d.roundTotal) \(clubLabel) fans\(d.weekLabel.map { " · \($0)" } ?? "")")
                    .dsFont(13, weight: .semibold).foregroundStyle(Color.dsFgPrimary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
        }
    }

    // MARK: - Point breakdown (the ONE accounting — You/Actual detail lives inline)

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("HOW YOUR \(score.total) POINTS ADD UP")
            breakdownRow("Correct players", detail: "\(score.correctPlayers) of 11 starters called",
                         points: score.playersPoints, earned: score.correctPlayers > 0)
            breakdownRow("Right position", detail: "\(score.correctPositions) of your \(score.correctPlayers) in the right line",
                         points: score.positionsPoints, earned: score.correctPositions > 0)
            breakdownRow("Formation", detail: youActual(prediction?.formation, model.detail?.actualFormation),
                         points: score.formationPoints, earned: score.formationCorrect)
            breakdownRow("Exact score", detail: youActual(scoreGuess, finalScoreText),
                         points: score.scorelinePoints, earned: score.exactScoreline)
            breakdownRow("Result (win / draw / loss)",
                         detail: score.resultCorrect ? "You called the right result" : "Missed",
                         points: score.resultPoints, earned: score.resultCorrect)
            // Only when earned — an unearned Perfect XI row reads as a rebuke every single match.
            if score.perfectXI {
                breakdownRow("Perfect XI bonus", detail: "All 11!", points: score.perfectPoints, earned: true)
            }
            HStack {
                Text("Total").dsFont(15, weight: .bold)
                Spacer()
                Text("\(score.total) of \(PredictionScore.maxPerMatch) possible")
                    .dsFont(15, weight: .heavy).foregroundStyle(accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 11)
        }
    }

    private var scoreGuess: String? {
        prediction.map { "\($0.homeScoreGuess)–\($0.awayScoreGuess)" }
    }

    private var finalScoreText: String? {
        item.finalScore.map { "\($0.home)–\($0.away)" }
    }

    private func youActual(_ you: String?, _ actual: String?) -> String {
        "You \(you ?? "—") · Actual \(actual ?? "—")"
    }

    private func breakdownRow(_ title: String, detail: String, points: Int, earned: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: earned ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(earned ? Color.dsSuccess : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(15, weight: .semibold)
                Text(detail).dsFont(12).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(earned ? "+\(points)" : "+0")
                .font(.callout.weight(.bold))
                .foregroundStyle(earned ? accent : .secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    // MARK: - Standout picks

    @ViewBuilder
    private var standoutSection: some View {
        if model.standouts.hit != nil || model.standouts.upset != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("STANDOUT PICKS")
                if let hit = model.standouts.hit, let share = hit.communityShare {
                    standoutCard(icon: "star.circle.fill", tint: .dsSuccess,
                                 title: "Gutsy call · \(hit.name)",
                                 body: "Only \(PredictPitchView.percent(share)) of \(clubLabel) fans had her starting. You did.")
                }
                if let upset = model.standouts.upset, let share = upset.communityShare {
                    standoutCard(icon: "exclamationmark.circle.fill", tint: .dsError,
                                 title: "Biggest upset · \(upset.name)",
                                 body: "She started and \(PredictPitchView.percent(share)) of \(clubLabel) fans had her in. You left her out.")
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

    // MARK: - How the fans picked (per-band, always visible)
    //
    // Presented open (owner call, second review — hiding it behind four "See how fans picked"
    // taps just made everyone tap four times). Labeled ONCE for the whole section: the subtitle
    // says where the numbers come from and what the bars mean, so no percentage floats.

    @ViewBuilder
    private var fanPicksSection: some View {
        if !model.bandPanels.isEmpty, let community = model.community {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("HOW \(clubLabel.uppercased()) FANS PICKED")
                Text("From \(community.submissions) fans' predictions · bars show the % of fans who had her in their XI")
                    .dsFont(12.5).foregroundStyle(Color.dsFgTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.bandPanels) { panel in
                    bandPanelCard(panel)
                }
            }
        }
    }

    /// ⚠️ A `Grid`, not a stack of HStacks. Bars have to share a common LEFT EDGE to be comparable —
    /// with each bar simply starting after its own name, "Tara Rudd" got a bar beginning further
    /// left than "Gabrielle Carle" and the ragged edges made the lengths impossible to read against
    /// each other, which is the entire job of a bar. Grid sizes the name column to the widest name
    /// in the panel, so every bar in a line starts and ends at the same x.
    private func bandPanelCard(_ panel: PredictResultViewModel.BandPanel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bandTitle(panel.group).uppercased())
                .dsFont(12, weight: .bold).tracking(0.8).foregroundStyle(Color.dsFgTertiary)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                ForEach(panel.entries) { entry in
                    GridRow { barRow(entry) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusMd, style: .continuous))
    }

    /// One ownership bar. A non-starter the crowd backed renders struck through — the crowd's
    /// wrong call is half the fun.
    /// ⚠️ SIZED FOR A PHONE, NOT A PREVIEW (owner, 2026-07-28). This started as a 4pt bar in a fixed
    /// 70pt slot with an 11pt fixed-size percentage — legible in a design tool on a desktop, squinty
    /// in a hand. The bar is now 10pt tall and FLEXIBLE (it takes the row's leftover width, roughly
    /// doubling on a real device), and the percentage is `.dsFont` so it scales with Dynamic Type
    /// instead of staying pinned at 11pt. Same fix is owed to Know Her Game's community bars —
    /// logged in docs/roadmap.md rather than done here.
    /// The four grid CELLS of one row: mark · name · bar · percentage. Returned bare (no HStack,
    /// no Spacer) so `Grid` can align them into columns across the panel.
    @ViewBuilder
    private func barRow(_ entry: PredictResultViewModel.BandPanel.Entry) -> some View {
        Image(systemName: entry.started
              ? (entry.called ? "checkmark.circle.fill" : "xmark.circle")
              : "minus.circle")
            .dsFont(15)
            .foregroundStyle(entry.started ? (entry.called ? Color.dsSuccess : Color.dsError) : Color.dsFgQuaternary)
            .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 0) {
            Text(entry.name)
                .dsFont(14, weight: .medium)
                .foregroundStyle(entry.started ? Color.dsFgPrimary : Color.dsFgTertiary)
                .strikethrough(!entry.started)
                .lineLimit(1)
            if !entry.started {
                Text("didn't start").dsFont(11).foregroundStyle(Color.dsFgTertiary)
            }
        }
        .accessibilityHidden(true)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsBgTertiary)
                Capsule().fill(entry.started ? accent : Color.dsFgQuaternary)
                    .frame(width: geo.size.width * min(1, entry.share))
            }
        }
        .frame(minWidth: 60, maxWidth: .infinity)
        .frame(height: 10)
        .gridCellUnsizedAxes(.vertical)
        // The bar and its percentage are one fact; VoiceOver reads the whole row once, from here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name)\(entry.started ? "" : ", didn't start"): picked by \(PredictPitchView.percent(entry.share)) of fans")

        Text(PredictPitchView.percent(entry.share))
            .dsFont(14, weight: .semibold, monospacedDigit: true)
            .foregroundStyle(Color.dsFgSecondary)
            .gridColumnAlignment(.trailing)
            .accessibilityHidden(true)
    }

    // MARK: - Share

    @ViewBuilder
    private var shareRow: some View {
        if let formation = model.actualFormation ?? prediction.flatMap({ Formation(raw: $0.formation) }) {
            PredictShareLink(
                card: PredictShareCard(
                    kind: .postMatch,
                    teamAbbr: item.fixture.teamAbbreviation,
                    opponentAbbr: item.fixture.opponentAbbreviation,
                    formation: formation,
                    rows: model.starters.map {
                        PredictShareCard.Row(band: $0.group.shortLabel,
                                             name: $0.name,
                                             marker: $0.called)
                    },
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
                // `.gradient` is how a Fan Zone game tints a CTA with its own colour.
                DSButton("Next up: \(next.teamAbbreviation) vs \(next.opponentAbbreviation) — predict now",
                         style: .gradient(AnyShapeStyle(accent))) {
                    onPredictNext?(next)
                }
                Text("Locks \(Self.lockFormatter.string(from: next.deadline))")
                    .dsFont(11).foregroundStyle(.secondary)
            }
        } else {
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

    private static let lockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}
