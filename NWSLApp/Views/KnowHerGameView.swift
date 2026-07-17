//
//  KnowHerGameView.swift
//  NWSLApp
//
//  Know Her Game — the weekly "how well do you know this player?" quiz that replaces the
//  passive Player Spotlight (docs/know-her-game.md). Mirrors DailyTriviaView's shape
//  (intro → question → result) with the amber "spotlight" accent, the player's team color
//  tinting the photo, tap-to-answer with an immediate correct/incorrect reveal + ~1.2s
//  auto-advance, and a feel-good result that surfaces one missed fact + the community
//  breakdown (NOT a competitive leaderboard — docs §11).
//
//  One attempt, no partial saves: quitting mid-game (the back chevron) discards; a completed
//  edition banks its score in KnowHerGameStore and shows the locked result with no replay.
//

import SwiftUI

struct KnowHerGameView: View {
    /// How the screen was entered. `.play` = the normal intro→question→result flow. `.review` = a
    /// read-only revisit opened from the picker (a completed current-week player, or ANY last-week
    /// player) — never shows the intro/questions, and never writes (a closed edition can't be replayed).
    enum Entry { case play, review }

    let player: KnowHerPlayer
    let weekKey: String
    var entry: Entry = .play
    /// Supplied by the multi-team picker so the result can offer "Next player ›". Nil when
    /// pushed for a single followed team (the result then offers "Back to Fan Zone").
    var onPlayNext: ((KnowHerPlayer) -> Void)? = nil

    @Environment(KnowHerGameStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: KnowHerGameViewModel
    @State private var started = false
    @State private var gateRequested = false
    /// The just-finished session's community answer-write, handed to CommunityResultsView so it waits
    /// for the write before fetching (the player sees her own answers counted). nil in `.review`.
    @State private var writeTask: Task<Void, Never>?

    private let accent = Color.dsGameSpotlight

    init(player: KnowHerPlayer, weekKey: String, entry: Entry = .play, onPlayNext: ((KnowHerPlayer) -> Void)? = nil) {
        self.player = player
        self.weekKey = weekKey
        self.entry = entry
        self.onPlayNext = onPlayNext
        _viewModel = State(initialValue: KnowHerGameViewModel(player: player, weekKey: weekKey))
    }

    /// The player's team color, tinting the photo ring + team tag (docs §12).
    private var teamColor: Color {
        DesignTeamColors.displayHex(for: player.teamAbbreviation).map { Color(hex: $0) } ?? accent
    }

    var body: some View {
        Group {
            if entry == .review {
                // Read-only revisit (completed current player, or any last-week player) — straight to
                // the result screen; no intro, no questions, no write.
                resultView(showRecap: false)
            } else if viewModel.isFinished {
                resultView(showRecap: true)
            } else if store.isPlayed(editionKey: viewModel.editionKey) {
                resultView(showRecap: false)
            } else if started {
                questionView
            } else {
                introView
            }
        }
        .nativeBackButton(title: "Know Her Game")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { PlayingAsBadge(accent: accent) } }
        .background(Color(.systemGroupedBackground))
        .task { GameCenterManager.shared.authenticate() }
        // Gate sign-in + display name at "Start the challenge", so the completion write is
        // always signed in. "Go back" cancels.
        .fanZoneGate(isRequested: $gateRequested, gameName: "Know Her Game") {
            started = true
        }
    }

    // MARK: - Intro (F2)

    private var introView: some View {
        ScrollView {
            VStack(spacing: 20) {
                KnowHerPlayerAvatar(player: player, ring: teamColor, size: 108)
                    .padding(.top, 8)
                Text(player.teamAbbreviation.uppercased())
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(teamColor.opacity(0.18))
                    .foregroundStyle(teamColor)
                    .clipShape(Capsule())
                VStack(spacing: 4) {
                    Text(player.playerName).font(.title.weight(.bold)).multilineTextAlignment(.center)
                    Text("\(player.position) · #\(player.jerseyNumber)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(player.tagline)
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)

                metaRow
                    .padding(.vertical, 4)

                Button {
                    gateRequested = true
                } label: {
                    Text("Start the challenge")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        // Dark ink on the light amber Spotlight accent — white here is ~1.9:1 (fails
                        // the 3:1 large-text floor); black on #F5A623 is ~11:1. Keeps the amber identity.
                        .background(accent).foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("A fresh player each week — one of your followed teams. Points add to your Superfan total.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            .padding(20)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 0) {
            metaItem("\(player.questions.count)", "questions")
            Divider().frame(height: 32)
            metaItem("Weekly", "new player")
            Divider().frame(height: 32)
            metaItem("\(player.questions.count)", "max points")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metaItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline).foregroundStyle(accent)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Question (F3)

    @ViewBuilder
    private var questionView: some View {
        if let question = viewModel.currentQuestion {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    progressHeader(question)
                    HStack(spacing: 12) {
                        KnowHerPlayerAvatar(player: player, ring: teamColor, size: 56)
                        Text(question.prompt)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 12) {
                        ForEach(question.options.indices, id: \.self) { index in
                            optionRow(question: question, index: index)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func progressHeader(_ question: KnowHerQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Question \(viewModel.questionNumber) of \(viewModel.questionCount)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(question.category.label.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(accent.opacity(0.14)).foregroundStyle(accent)
                    .clipShape(Capsule())
            }
            // Progress dots — one per question, filled through the current.
            HStack(spacing: 6) {
                ForEach(0..<viewModel.questionCount, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.questionNumber ? accent : Color(.systemGray5))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    private func optionRow(question: KnowHerQuestion, index: Int) -> some View {
        let style = optionStyle(question: question, index: index)
        return Button {
            answer(index)
        } label: {
            HStack(spacing: 14) {
                Text(question.isTrueFalse ? (index == 0 ? "T" : "F") : letter(index))
                    .font(.subheadline.weight(.bold))
                    .frame(width: 26, height: 26)
                    .background(style.badgeFill).foregroundStyle(style.badgeText)
                    .clipShape(Circle())
                Text(question.options[index])
                    .font(.body).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let icon = style.trailingIcon {
                    Image(systemName: icon).foregroundStyle(style.borderColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.fill)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(style.borderColor, lineWidth: style.borderWidth))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRevealed)
    }

    // MARK: - Result (F5)

    private func resultView(showRecap: Bool) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                if hasBankedScore {
                    // You played this one → your score up top.
                    scoreCircle.padding(.top, 12)
                    VStack(spacing: 8) {
                        Text(feelGoodTitle).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        if let missed = missedFact {
                            Text(missed).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal)
                        }
                    }
                    if bankedScore > 0 {
                        Text("+\(bankedScore) points")
                            .font(.headline).foregroundStyle(accent)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(accent.opacity(0.14)).clipShape(Capsule())
                    }
                } else {
                    // A last-week player you never played → no personal score; lead with her identity,
                    // then the community numbers (the whole reason you tapped in).
                    unplayedHeader.padding(.top, 12)
                }

                CommunityResultsView(game: "knowher", editionKey: viewModel.editionKey,
                                     questions: communityQuestions, accent: accent,
                                     pendingWrite: writeTask)

                resultCTA
            }
            .padding(20)
        }
    }

    /// Identity header for a last-week player the user never played (no score circle to show).
    private var unplayedHeader: some View {
        VStack(spacing: 10) {
            KnowHerPlayerAvatar(player: player, ring: teamColor, size: 88)
            Text(player.playerName).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text("\(player.position) · \(player.teamAbbreviation.uppercased())")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("You didn't play this one — here's how everyone did.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
        }
    }

    private var scoreCircle: some View {
        ZStack {
            Circle().stroke(accent.opacity(0.18), lineWidth: 10).frame(width: 132, height: 132)
            Circle()
                .trim(from: 0, to: scoreFraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 132, height: 132)
            VStack(spacing: 2) {
                Text("\(bankedScore)/\(player.questions.count)")
                    .dsFont(34, weight: .heavy, design: .rounded).foregroundStyle(accent)
                Text("correct").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultCTA: some View {
        // A revisit (from the picker) dismisses back to the player list. A just-finished play offers the
        // next unplayed player (multi-team) or a return to Fan Zone.
        if entry == .review {
            Button { dismiss() } label: {
                ctaLabel("Back to your players", systemImage: nil)
            }.buttonStyle(.plain)
        } else if let next = nextUnplayed, let onPlayNext {
            Button { onPlayNext(next) } label: {
                ctaLabel("Next player", systemImage: "arrow.right")
            }.buttonStyle(.plain)
        } else {
            Button { dismiss() } label: {
                ctaLabel("Back to Fan Zone", systemImage: nil)
            }.buttonStyle(.plain)
        }
    }

    private func ctaLabel(_ text: String, systemImage: String?) -> some View {
        HStack(spacing: 8) {
            Text(text)
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
        // Dark ink on the light amber Spotlight accent (see startChallenge button) — white fails contrast.
        .background(accent).foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Actions

    /// Tap-to-answer: lock + reveal immediately, then auto-advance (~1.2s). Guarded so a
    /// second tap during the reveal is ignored.
    private func answer(_ index: Int) {
        guard !viewModel.isRevealed else { return }
        viewModel.select(index)
        viewModel.submit()
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                if viewModel.isLastQuestion { finishFlow() } else { viewModel.advance() }
            }
        }
    }

    /// Bank the score, write the community answers, flip to the result. Double-tap guarded.
    private func finishFlow() {
        guard !viewModel.isFinished else { return }
        viewModel.finish()
        store.recordCompletion(editionKey: viewModel.editionKey, weekKey: weekKey, correct: viewModel.score)
        // Signed in (gated at Start) → persist the per-question answers to the community aggregate.
        if let userID = auth.userID {
            let answers = viewModel.communityAnswers()
            let edition = viewModel.editionKey
            // Hold the write Task so the result screen's community panel awaits it before fetching —
            // the player then sees her own answers counted, not a pre-write "0 fans played".
            writeTask = Task {
                await QuizResultsService().upsert(game: "knowher", editionKey: edition,
                    answers: answers, userID: userID, season: String(AppConfig.currentSeasonYear))
            }
        }
    }

    // MARK: - Derived

    /// Whether there's a personal score to show — the just-finished session, or a banked score for THIS
    /// edition (keyed by the view's own weekKey, so a last-week revisit reads the right edition). False
    /// for a last-week player the user never played → the result screen skips the score circle.
    private var hasBankedScore: Bool { viewModel.isFinished || store.score(editionKey: viewModel.editionKey) != nil }
    /// Score to display: the just-played session score, or the banked score on a locked re-open.
    private var bankedScore: Int { viewModel.isFinished ? viewModel.score : (store.score(editionKey: viewModel.editionKey) ?? viewModel.score) }
    private var scoreFraction: CGFloat {
        let total = player.questions.count
        return total > 0 ? CGFloat(bankedScore) / CGFloat(total) : 0
    }
    private var percent: Int {
        let total = player.questions.count
        return total > 0 ? Int((Double(bankedScore) / Double(total) * 100).rounded()) : 0
    }
    private var feelGoodTitle: String {
        switch percent {
        case 90...: return "You really know her! 💛"
        case 70..<90: return "You know your stuff!"
        case 50..<70: return "Getting to know her"
        default: return "We all start somewhere 🌱"
        }
    }
    /// A missed fact to surface (the "learn" payoff) — the first wrong answer's reveal, if any.
    private var missedFact: String? {
        guard viewModel.isFinished else { return nil }
        for (q, pick) in zip(viewModel.questions, viewModel.picks) where pick != q.correctIndex {
            return q.revealFact ?? "Answer: \(q.correctAnswer)"
        }
        return nil
    }
    private var nextUnplayed: KnowHerPlayer? {
        store.unplayedPlayers.first { $0.id != player.id }
    }
    private var communityQuestions: [CommunityResultsView.QuestionInfo] {
        // Carry the revealFact so the "learn about her" payoff rides each question's community breakdown
        // (the standalone answer-recap list was removed as a duplicate).
        player.questions.map { .init(id: $0.id, prompt: $0.prompt, options: $0.options,
                                     correctIndex: $0.correctIndex, revealFact: $0.revealFact) }
    }

    private func letter(_ index: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        return index < letters.count ? letters[index] : ""
    }

    // MARK: - Option styling (correct=green, wrong pick=red — mirrors DailyTriviaView)

    private struct OptionStyle {
        var fill: Color; var borderColor: Color; var borderWidth: CGFloat
        var badgeFill: Color; var badgeText: Color; var trailingIcon: String?
    }

    private func optionStyle(question: KnowHerQuestion, index: Int) -> OptionStyle {
        let base = Color(.secondarySystemGroupedBackground)
        let isSelected = viewModel.selectedIndex == index
        let isCorrect = index == question.correctIndex

        if !viewModel.isRevealed {
            return OptionStyle(fill: base, borderColor: Color(.systemGray4), borderWidth: 1,
                               badgeFill: Color(.systemGray5), badgeText: .secondary, trailingIcon: nil)
        }
        if isCorrect {
            return OptionStyle(fill: Color.green.opacity(0.14), borderColor: .green, borderWidth: 2,
                               badgeFill: .green, badgeText: .white, trailingIcon: "checkmark")
        }
        if isSelected {
            return OptionStyle(fill: Color.red.opacity(0.12), borderColor: .red, borderWidth: 2,
                               badgeFill: .red, badgeText: .white, trailingIcon: "xmark")
        }
        return OptionStyle(fill: base, borderColor: Color(.systemGray5), borderWidth: 1,
                           badgeFill: Color(.systemGray5), badgeText: .secondary, trailingIcon: nil)
    }
}

// MARK: - Player avatar

/// A circular player headshot with a team-color ring, monogram fallback while the NWSL
/// CDN photo resolves (or when the player has none). Reuses HeadshotStore + ImageCache,
/// like PlayerSpotlightCard.
struct KnowHerPlayerAvatar: View {
    let player: KnowHerPlayer
    let ring: Color
    var size: CGFloat = 72

    @State private var image: UIImage?

    private var photoURL: URL? {
        guard let guid = HeadshotStore.shared.guid(forAthleteID: player.espnAthleteId) else { return nil }
        return AppConfig.headshotImageURL(guid: guid, size: size >= 96 ? .detail : .card)
    }

    var body: some View {
        ZStack {
            Circle().fill(ring.opacity(0.18))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(monogram).font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(ring)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(ring, lineWidth: 2))
        .task(id: photoURL) { await resolve() }
    }

    private var monogram: String {
        let parts = player.playerName.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "?" : initials.uppercased()
    }

    private func resolve() async {
        guard let url = photoURL else { image = nil; return }
        if let hit = ImageCache.shared.cached(url) { image = hit; return }
        image = await ImageCache.shared.image(for: url)
    }
}
