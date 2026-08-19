//
//  CommunityResultsView.swift
//  NWSLApp
//
//  The NYT-style "how everyone did" panel — SHARED by NWSL Trivia + Know Her Game
//  (docs §11b), the leaderboard REPLACEMENT for the quiz games. Per question: the prompt, one
//  community line ("47 out of 50 fans nailed this"), and a bar per option showing what everyone
//  picked. Shown from the FIRST responder — a live board that grows (the honest "1 fan played" IS
//  the live-stats hook); a raw count can't overstate at small N the way a bare percentage can.
//  (Until 2026-07-22 percentages were withheld entirely below 25 responders — owner ruling: showing
//  the potential is what brings players back. Nothing is hidden at low scale; don't re-add a gate.)
//  Reveal timing is server-decided — the one thing still gated (`!revealed`).
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
//  97%, so I was right"). Nothing on the screen said what YOU picked. Your own option now carries a
//  red ✗ (when wrong) and a "your pick" tag, against the correct option's green ✓. Marks are
//  shape-different (✓/✗/○) AND text-labelled, never color alone — the color-blind half of the
//  pre-release a11y gate.
//
//  ⚠️ THE MARKS ARE THE WHOLE EXPLANATION — keep the per-question header to TWO lines (prompt +
//  community count). Two things were built here and then deliberately CUT, both owner calls; don't
//  reintroduce either as an "improvement":
//   • A "You said Green — the answer was Blue" verdict line. It was load-bearing only while option
//     labels truncated to one line; once they went full-width (stacked layout, below) it restated
//     what the ✗/✓ marks already show, on every question.
//   • A flavor line on a rare correct answer ("only 12% got this"). On a screen already dense with
//     bars, per-question commentary is noise, not delight.
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
                Text("Community").dsFont(13).foregroundStyle(Color.dsFgSecondary)
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
            honest("Results reveal after today's game closes. Check back tomorrow.", retry: false)
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
            Text(label).dsFont(13).foregroundStyle(Color.dsFgSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // One question's community breakdown: the prompt, the raw "N out of M fans nailed this" count,
    // and a bar per option showing what everyone picked (your own marked). Two header lines, no more —
    // see the ⚠️ note at the top of the file for what was cut and why.
    @ViewBuilder
    private func questionBreakdown(_ q: QuestionInfo, _ data: QuizResults.Question?, showPercent: Bool) -> some View {
        let total = data?.total ?? 0
        let correct = data?.correctCount ?? 0
        VStack(alignment: .leading, spacing: 8) {
            Text(q.prompt)
                .dsFont(16, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.nailedLine(correct: correct, total: total))
                .dsFont(13, weight: .semibold)
                .foregroundStyle(accent)
            // STACKED: each option's full text on its own line, its bar beneath. The bars still share
            // a common left edge (so their lengths stay comparable — the whole job of a bar), but they
            // now get the row's FULL width instead of whatever a label column leaves over.
            //
            // ⚠️ The spacing carries this layout. The gap inside an option (label → its own bar) must
            // stay clearly TIGHTER than the gap between options, or the bars stop reading as belonging
            // to the label above them and the block turns to mush. 5pt inside, 14pt between.
            VStack(alignment: .leading, spacing: 14) {
                ForEach(q.options.indices, id: \.self) { i in
                    optionRow(label: q.options[i], count: data?.count(forOption: i) ?? 0,
                              total: total, isCorrect: i == q.correctIndex,
                              isYourPick: i == q.yourPick, showPercent: showPercent)
                }
            }
            // The "learn about her" payoff — this is the REWARD of a KHG quiz, so it reads as the
            // takeaway, not fine print (owner, 2026-08-04): an accent lightbulb cue + full-size white
            // text on a subtle accent tile, in place (no card reorder). It used to be 12pt gray dead-last,
            // the least-visible thing on a game built around learning. Trivia passes `revealFact == nil`,
            // so this is KHG-only; the tile wears the caller's `accent`.
            if let fact = q.revealFact, !fact.isEmpty {
                // ⚠️ ONE concatenated Text, NOT an HStack (regression fix 2026-08-04). The lightbulb
                // used to be a separate `Image` in an `HStack` beside a `.fixedSize` Text — the HStack
                // then reported the text's full UNWRAPPED width as its ideal, which propagated past the
                // card's frame and let the results ScrollView pan horizontally (owner-caught; invisible
                // in a screenshot because it still rendered wrapped). Inlining the symbol keeps this a
                // single wrapping Text — the same shape as the plain fact line that shipped fine.
                (Text(Image(systemName: "lightbulb.fill")).foregroundStyle(accent)
                    + Text("  \(fact)").foregroundStyle(Color.dsFgPrimary))
                    .dsFont(15)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.dsBgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The one community line under each question: "47 out of 50 fans nailed this".
    ///
    /// ⚠️ RAW COUNT ONLY — do NOT re-add a leading percentage (owner, 2026-07-29). This read
    /// "94% · 47 of 50 fans nailed this" for a week, and that percentage was a DUPLICATE: `correctCount`
    /// is by definition the fans who picked the correct option, so it's the same number the correct
    /// option's own bar already prints a few rows down. Ten questions per recap, each printing one
    /// statistic twice.
    ///
    /// This does NOT revive the pre-2026-07-22 low-N gate, and must not be "fixed" back into one. That
    /// gate WITHHELD data (no percentage below 25 responders); this shows the count at every N, which is
    /// the more honest of the two numbers — a bare "67%" can overstate at 3 responders, "2 out of 3
    /// fans" cannot. Per-option percentages are untouched. Nothing is hidden at low scale.
    ///
    /// Pure + `static` so it's unit-testable without a view.
    static func nailedLine(correct: Int, total: Int) -> String {
        guard total > 0 else { return "No answers yet" }
        return "\(correct) out of \(total) \(total == 1 ? "fan" : "fans") nailed this"
    }

    /// One option: its mark + FULL label on the first line, its bar + percentage on the second.
    ///
    /// ⚠️ SIZED FOR A PHONE (2026-07-28). The bar was 60x6 with an 11pt non-scaling percentage while
    /// the label took the flexible width — the element you're meant to compare across options was the
    /// smallest thing in the row. It's now 10pt tall, `.dsFont` percentages, and (2026-07-29) the full
    /// row width.
    ///
    /// ⚠️ STACKED, NOT SIDE-BY-SIDE (2026-07-29). The label used to be a single truncating line in its
    /// own grid column: Know Her Game and Trivia options are SENTENCES, so "Sitting on the fi…" was
    /// routine — on a review of a round you didn't play, with no verdict line to fall back on, the
    /// correct answer was simply unreadable. Stacking fixes that AND roughly doubles the bar (it no
    /// longer competes with a label column for width). The cost is height on short numeric/True-False
    /// options, accepted deliberately: one layout for every question beats a per-question switch, which
    /// is the same inconsistency the GK-donut cut removed from Predict.
    ///
    /// Three states: the CORRECT option (green ✓), YOUR pick when wrong (red ✗), everything else
    /// (hollow dim ○) — shape and text, never color alone.
    private func optionRow(label: String, count: Int, total: Int,
                           isCorrect: Bool, isYourPick: Bool, showPercent: Bool) -> some View {
        let fraction = total > 0 ? Double(count) / Double(total) : 0
        let isWrongPick = isYourPick && !isCorrect
        let pct = Int((fraction * 100).rounded())

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: isCorrect ? "checkmark.circle.fill"
                                : isWrongPick ? "xmark.circle.fill" : "circle")
                    .dsFont(15)
                    .foregroundStyle(isCorrect ? Color.dsSuccess
                                     : isWrongPick ? Color.dsError : Color.dsFgTertiary)
                // "your pick" rides the label as concatenated text rather than a sub-line, so it wraps
                // with the sentence and costs no extra height.
                (Text(label)
                 + Text(isYourPick ? "  ·  your pick" : "").foregroundStyle(Color.dsFgSecondary))
                    .dsFont(15)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.dsBgCard)
                        Capsule().fill(isCorrect ? Color.dsSuccess.opacity(0.7)
                                       : isWrongPick ? Color.dsError.opacity(0.6) : accent.opacity(0.5))
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 10)

                // Percent, safe unanchored HERE because the line above the block spells out the count
                // ("67% · 2 of 3 fans nailed this") and the summary row carries the responder total.
                // A minimum width keeps the bars' right edges aligned down the block.
                Text(showPercent ? "\(pct)%" : "\(count)")
                    .dsFont(13, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(minWidth: 42, alignment: .trailing)
            }
            // Indent the bar to the label TEXT, not the mark, so the ✓/✗/○ marks stay a clean scannable
            // column down the left edge.
            .padding(.leading, 21)
        }
        // One option = one fact for VoiceOver, rather than four fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)\(isCorrect ? ", correct answer" : "")\(isYourPick ? ", your pick" : ""): \(pct) percent, \(count) of \(total)")
    }

    @ViewBuilder
    private func honest(_ message: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).dsFont(16).foregroundStyle(Color.dsFgSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                Button("Try again") { Task { await load() } }
                    .dsFont(13, weight: .semibold)
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
