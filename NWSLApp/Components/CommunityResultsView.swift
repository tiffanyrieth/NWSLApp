//
//  CommunityResultsView.swift
//  NWSLApp
//
//  The NYT-style "how everyone did" panel — SHARED by NWSL Trivia + Know Her Game
//  (docs §11b), the leaderboard REPLACEMENT for the quiz games. Shows the community
//  average, per-question "% who got it right", and what everyone picked. Honest at every N by
//  showing BOTH numbers together ("67% · 2 of 3 fans nailed this") rather than either/or: the
//  percentage can't overstate because its denominator is right beside it, and a first player sees
//  the real shape of the panel instead of waiting for a crowd. (Until 2026-07-22 percentages were
//  withheld below 25 responders — owner ruling: showing the potential is what brings players back.)
//  Shown from the FIRST responder — a live board that grows (the honest "1 fan played" IS the
//  live-stats hook). Reveal timing is server-decided — the one thing still gated (`!revealed`).
//
//  The caller passes a flat list of its questions (prompt + options + correct index) so this
//  one component renders both games' models. It fetches the aggregate from the proxy edge
//  cache via QuizResultsService — never a live DB aggregation.
//

import SwiftUI

struct CommunityResultsView: View {
    /// A game-agnostic question descriptor the caller builds from its own model.
    struct QuestionInfo: Identifiable {
        let id: String
        let prompt: String
        let options: [String]
        let correctIndex: Int
        /// The one-line "learn" payoff shown under the breakdown (Know Her Game's revealFact). Optional
        /// so Trivia can omit it (→ no extra line); this is where the fun-fact delight lives now that the
        /// standalone answer-recap list is gone.
        let revealFact: String?

        init(id: String, prompt: String, options: [String], correctIndex: Int, revealFact: String? = nil) {
            self.id = id
            self.prompt = prompt
            self.options = options
            self.correctIndex = correctIndex
            self.revealFact = revealFact
        }
    }

    let game: String          // "trivia" | "knowher"
    let editionKey: String
    let questions: [QuestionInfo]
    var accent: Color = .dsGameSpotlight
    /// The in-flight answer-write from a just-finished session. `load()` awaits it before fetching so the
    /// player's own answers are counted in the community numbers they see (no "0 fans played" flash on the
    /// screen they just earned). nil on re-entry / last-week review — fetch immediately.
    var pendingWrite: Task<Void, Never>? = nil

    private let service = QuizResultsService()
    @State private var results: QuizResults?
    @State private var loadState: LoadState = .loading

    private enum LoadState { case loading, loaded, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill").foregroundStyle(accent)
                Text("How everyone did").dsFont(17, weight: .semibold)
                Spacer()
                Text("Community").dsFont(12).foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsBgCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: editionKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
        case .failed:
            honest("Couldn't load community results.", retry: true)
        case .loaded:
            if let results { loaded(results) } else { honest("Couldn't load community results.", retry: true) }
        }
    }

    @ViewBuilder
    private func loaded(_ r: QuizResults) -> some View {
        if !r.revealed {
            // Trivia, still-open day — the community breakdown reveals after it closes.
            honest("Results reveal after today's game closes — check back tomorrow.", retry: false)
        } else {
            // Always show the live breakdown once revealed — even at a single responder. Honest counts
            // ("1 fan played", "1 of 1 nailed this") ARE the payoff: the first player sees a real, live
            // stats board that grows as more fans play. (No "you're the first" gate — it hid exactly the
            // wow moment, and made the 2nd player who fetched a pre-write count also see the placeholder.)
            summaryRow(r)
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                ForEach(questions) { q in
                    questionBreakdown(q, r.questions.first { $0.questionId == q.id }, showPercent: r.showPercent)
                }
            }
        }
    }

    private func summaryRow(_ r: QuizResults) -> some View {
        HStack {
            statBlock(value: r.avgCorrect.map { String(format: "%.1f", $0) } ?? "—",
                      label: "average score")
            Divider().frame(height: 40)
            statBlock(value: "\(r.responders)", label: r.responders == 1 ? "fan played" : "fans played")
        }
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).dsFont(20, weight: .bold).foregroundStyle(accent)
            Text(label).dsFont(12).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // One question's community breakdown: the "got it right" line (count always; % at scale)
    // plus a small bar per option showing what everyone picked.
    @ViewBuilder
    private func questionBreakdown(_ q: QuestionInfo, _ data: QuizResults.Question?, showPercent: Bool) -> some View {
        let total = data?.total ?? 0
        let correct = data?.correctCount ?? 0
        VStack(alignment: .leading, spacing: 8) {
            Text(q.prompt)
                .dsFont(15, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            Text(gotItRightLine(correct: correct, total: total, showPercent: showPercent))
                .dsFont(12, weight: .semibold)
                .foregroundStyle(accent)
            ForEach(q.options.indices, id: \.self) { i in
                optionBar(label: q.options[i], count: data?.count(forOption: i) ?? 0,
                          total: total, isCorrect: i == q.correctIndex, showPercent: showPercent)
            }
            // The "learn about her" payoff, folded in here so it isn't a duplicate list at the bottom.
            if let fact = q.revealFact, !fact.isEmpty {
                Text(fact)
                    .dsFont(12).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dsBgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Percentage AND count, always. It used to be either/or — a bare "67% got it right" above 25
    /// responders, a bare count below. Showing both means the percentage is never unanchored from how
    /// many people it represents (so it can't overstate at small N), and the shape of the feature is
    /// visible from the very first responder instead of appearing only once a crowd arrives.
    /// `showPercent` is now vestigial server-side (the proxy sends it true from N=1) but is still
    /// honoured, so an older payload can't produce a misleading standalone percentage.
    private func gotItRightLine(correct: Int, total: Int, showPercent: Bool) -> String {
        guard total > 0 else { return "No answers yet" }
        let noun = total == 1 ? "fan" : "fans"
        guard showPercent else { return "\(correct) of \(total) \(noun) nailed this" }
        let pct = Int((Double(correct) / Double(total) * 100).rounded())
        return "\(pct)% · \(correct) of \(total) \(noun) nailed this"
    }

    private func optionBar(label: String, count: Int, total: Int, isCorrect: Bool, showPercent: Bool) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        return HStack(spacing: 10) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "circle")
                .dsFont(12)
                .foregroundStyle(isCorrect ? Color.dsSuccess : Color.dsFgTertiary)
            Text(label)
                .dsFont(12)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.dsBgTertiary)
                    Capsule().fill(isCorrect ? Color.dsSuccess.opacity(0.7) : accent.opacity(0.5))
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(width: 60, height: 6)
            // Percent per option, at any scale. Safe to show unanchored HERE because the line directly
            // above spells out the count ("67% · 2 of 3 fans nailed this") and the summary row carries
            // the responder total — so the reader always has the denominator in view.
            Text(showPercent ? "\(Int((fraction * 100).rounded()))%" : "\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func honest(_ message: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).dsFont(15).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                Button("Try again") { Task { await load() } }
                    .dsFont(12, weight: .semibold)
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        loadState = .loading
        // Let the just-finished session's answer-write land first, so the player is counted in the
        // numbers she's about to see (no "0 fans played" flash). No-op on re-entry (pendingWrite == nil).
        await pendingWrite?.value
        let r = await service.results(game: game, edition: editionKey)
        results = r
        loadState = r == nil ? .failed : .loaded
    }
}
