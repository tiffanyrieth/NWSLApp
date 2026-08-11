//
//  PredictShareCard.swift
//  NWSLApp
//
//  The shareable Predict the XI artifact (2026-07-28). Two moments, one card:
//   • PRE-KICKOFF — your XI, once submissions have closed. "My picks, we'll see." This is the better
//     of the two moments: the lineup is still an argument rather than a result, which is exactly
//     what people reply to.
//   • POST-MATCH — the same XI with ✓/✗ and the score.
//
//  A lineup is a far better conversation object than a score, because people disagree about specific
//  players. That's the whole reason this exists — the meaning of the game lives outside the app, in
//  the group chat and the subreddit thread, and this is the object that travels there.
//
//  ⚠️ RENDERED ONCE, NOT PER BODY EVALUATION. The Bracket's share button calls its renderer inline
//  in `body`, so a scale-3 `ImageRenderer` pass runs on every re-render of that screen. Here the
//  render happens in a `.task` (once per view identity) into `@State`, and the ShareLink appears
//  only when the image is ready. Don't "simplify" this back to an inline call.
//

import SwiftUI

// MARK: - The renderable card

struct PredictShareCard: View {
    enum Kind { case preKickoff, postMatch }

    struct Row: Identifiable {
        let band: String
        let name: String
        /// nil pre-kickoff; true = started, false = didn't, for the post-match version.
        let marker: Bool?
        var id: String { band + name }
    }

    let kind: Kind
    let teamAbbr: String
    let opponentAbbr: String
    let formation: Formation
    let rows: [Row]
    /// The big line — a predicted scoreline pre-kickoff, "8 of 11" after.
    let headline: String
    let subhead: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("PREDICT THE XI")
                    .font(.system(size: 11, weight: .bold)).tracking(1.2)
                    .foregroundStyle(accent)
                Spacer()
                Text("\(teamAbbr) vs \(opponentAbbr)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(subhead).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(formation.raw).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        if let marker = row.marker {
                            Image(systemName: marker ? "checkmark" : "xmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(marker ? Color.dsSuccess : Color.dsError)
                                .frame(width: 12)
                        }
                        Text(row.band)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 28, alignment: .leading)
                        Text(row.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }

            Text("NWSL · Predict the XI")
                .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(
            LinearGradient(colors: [accent.opacity(0.20), .dsBgPrimary],
                           startPoint: .top, endPoint: .bottom)
        )
        .background(Color.dsBgPrimary)
    }
}

// MARK: - The share affordance

/// Renders `card` to an image ONCE, then offers it through a `ShareLink`.
struct PredictShareLink: View {
    let card: PredictShareCard
    let label: String
    let accent: Color

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image,
                          preview: SharePreview("My Predict the XI", image: image)) {
                    shareLabel
                }
            } else {
                // Rendering is near-instant, but never show a share control that would hand off
                // nothing — a share sheet with a missing attachment is worse than a half-second wait.
                shareLabel.opacity(0.5)
            }
        }
        .task { await render() }
    }

    private var shareLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up").dsFont(15)
            Text(label).dsFont(15, weight: .bold)
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSm, style: .continuous)
                .strokeBorder(accent.opacity(0.5), lineWidth: 1)
        )
    }

    @MainActor
    private func render() async {
        guard image == nil else { return }
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage { image = Image(uiImage: ui) }
    }
}
