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
//  ⚠️ Bars are sized for a HAND, not a preview (2026-07-28): flexible width, 10pt tall, `.dsFont`
//  percentages. They were 60x6 with an 11pt fixed percentage — the element you're meant to compare
//  across options was the smallest thing in the row. Shared by Trivia and Know Her Game, so this
//  fixes both.
//
//  ⚠️ YOUR ANSWER IS MARKED (2026-07-29, owner-reported). Until now the ONLY mark on the panel was a
//  green ✓ on the correct option — so a question you got WRONG rendered identically to one you got
//  right, and readers took the ✓ to be their own answer ("I picked B, and the row with the check says
//  97%, so I was right"). Nothing on the screen said what YOU picked. Now each question carries a
//  verdict line under the prompt (`verdictLine`) and your own option is marked in the grid: red ✗ when
//  it's wrong, plus a "your pick" sub-line either way. Marks are shape-different (✓/✗/○) AND
//  text-labelled, never color alone — the color-blind half of the pre-release a11y gate.
//
//  Deliberately NOT added (owner, same session): a flavor line on a rare correct answer ("only 12% got
//  this"). With 10–15 questions on one panel it's noise stacked on top of bars, not delight.
//
//  `yourPick` is OPTIONAL and nil is a real state — a last-round recap you never played, or an
//  edition played before the picks were persisted (a pre-2026-07-29 install, or any KHG edition on a
//  reinstalled device). Nil renders exactly the old panel: correct answer marked, no personal claims.
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
        /// The option THIS user picked, or nil when it isn't known (never played this edition; played it
        /// on a build/device that didn't persist picks). Nil ⇒ no verdict line and no "your pick" mark —
        /// the panel says nothing about the reader rather than guessing.
        let yourPick: Int?

        init(id: String, prompt: String, options: [String], correctIndex: Int,
             revealFact: String? = nil, yourPick: Int? = nil) {
            self.id = id
            self.prompt = prompt
            self.options = options
            self.correctIndex = correctIndex
            self.revealFact = revealFact
            self.yourPick = yourPick
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
            // YOUR result first, then the crowd's. Two lines with two distinct voices: this one is
            // success/error tinted (it's about you), the community line keeps the game accent.
            if let pick = q.yourPick,
               let verdict = Self.verdict(options: q.options, correctIndex: q.correctIndex, yourPick: pick) {
                let tint = verdict.gotIt ? Color.dsSuccess : Color.dsError
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: verdict.gotIt ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .dsFont(12)
                        .foregroundStyle(tint)
                    // Two tones in one paragraph: your pick tinted, the correction secondary. Text
                    // concatenation (not an HStack) so the halves wrap as ONE flowing paragraph.
                    (Text(verdict.mine).foregroundStyle(tint)
                     + Text(verdict.correction ?? "").foregroundStyle(Color.dsFgSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .dsFont(13, weight: .semibold)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(verdict.spoken)
            }
            Text(gotItRightLine(correct: correct, total: total, showPercent: showPercent))
                .dsFont(12, weight: .semibold)
                .foregroundStyle(accent)
            // A Grid so the bars share a common left edge — with each bar starting after its own
            // option label, differing label lengths give ragged edges and the lengths stop being
            // comparable, which is the whole job of a bar.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(q.options.indices, id: \.self) { i in
                    GridRow {
                        optionBar(label: q.options[i], count: data?.count(forOption: i) ?? 0,
                                  total: total, isCorrect: i == q.correctIndex,
                                  isYourPick: i == q.yourPick, showPercent: showPercent)
                    }
                }
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

    /// "How did I do" on one question — the thing the panel couldn't say before.
    ///
    /// Split into TWO parts so the view can render them in two tones. Full-strength red across both
    /// halves turned a bad round into a wall of red: 11 questions, each verdict wrapping to 3–4 lines,
    /// all shouting equally. `mine` (what you picked) carries the color because it's the scan anchor;
    /// `correction` (what was actually right) is secondary — present, readable, not shouting.
    struct Verdict: Equatable {
        /// "You said Green" — tinted success/error.
        let mine: String
        /// " — the answer was Blue", or nil when you got it right. A correct answer deliberately does
        /// NOT restate the same option twice; that padding stacks up over 10–15 questions.
        let correction: String?

        var gotIt: Bool { correction == nil }
        /// The whole line as one string, for VoiceOver (which shouldn't hear two fragments).
        var spoken: String { mine + (correction ?? "") }
    }

    /// Pure + `static` so it's unit-testable without a view. Returns nil on an out-of-range index — a
    /// defensive case (picks and questions are written together), and nil degrades to the no-verdict
    /// panel rather than rendering a dangling "You said ".
    static func verdict(options: [String], correctIndex: Int, yourPick: Int) -> Verdict? {
        guard options.indices.contains(yourPick), options.indices.contains(correctIndex) else { return nil }
        guard yourPick != correctIndex else { return Verdict(mine: "You said \(options[yourPick])", correction: nil) }
        return Verdict(mine: "You said \(options[yourPick])",
                       correction: " — the answer was \(options[correctIndex])")
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

    /// The four grid CELLS of one option row: mark · label · bar · percentage.
    ///
    /// ⚠️ SIZED FOR A PHONE (2026-07-28). This was a 60pt-wide, 6pt-tall bar with a `.caption2`
    /// (11pt, non-scaling) percentage, while the LABEL took all the flexible width — so the one
    /// element the reader is meant to compare across options was the smallest thing in the row.
    /// The bar now takes the leftover width and is 10pt tall, and the percentage uses `.dsFont` so
    /// Dynamic Type can scale it.
    ///
    /// Three row states (2026-07-29): the CORRECT option (green ✓), YOUR pick when it was wrong
    /// (red ✗), and everything else (hollow dim ○). Your pick also carries a "your pick" sub-line
    /// whether right or wrong — the same label/sub-line grammar as Predict's ownership bars
    /// ("didn't start"), so the two results screens read the same way.
    @ViewBuilder
    private func optionBar(label: String, count: Int, total: Int,
                           isCorrect: Bool, isYourPick: Bool, showPercent: Bool) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        let isWrongPick = isYourPick && !isCorrect

        Image(systemName: isCorrect ? "checkmark.circle.fill"
                        : isWrongPick ? "xmark.circle.fill" : "circle")
            .dsFont(14)
            .foregroundStyle(isCorrect ? Color.dsSuccess
                             : isWrongPick ? Color.dsError : Color.dsFgTertiary)
            .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .dsFont(13)
                .lineLimit(1)
            if isYourPick {
                Text("your pick").dsFont(11).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsBgCard)
                Capsule().fill(isCorrect ? Color.dsSuccess.opacity(0.7)
                               : isWrongPick ? Color.dsError.opacity(0.6) : accent.opacity(0.5))
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(minWidth: 70, maxWidth: .infinity)
        .frame(height: 10)
        .gridCellUnsizedAxes(.vertical)
        // One row = one fact for VoiceOver, rather than four fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)\(isCorrect ? ", correct answer" : "")\(isYourPick ? ", your pick" : ""): \(Int((fraction * 100).rounded())) percent, \(count) of \(total)")

        // Percent per option. Safe unanchored HERE because the line directly above spells out the
        // count ("67% · 2 of 3 fans nailed this") and the summary row carries the responder total.
        Text(showPercent ? "\(Int((fraction * 100).rounded()))%" : "\(count)")
            .dsFont(13, weight: .semibold, monospacedDigit: true)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
            .accessibilityHidden(true)
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
