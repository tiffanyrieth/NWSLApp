//
//  ThesisView.swift
//  NWSLApp
//
//  The one-screen "thesis" shown between team selection and Home (First-Impression
//  Improvements, Change 3). After picking clubs, a new user is dropped into Home with no
//  framing — they see content but have no mental model for why it's there. This screen
//  gives that model in one sentence: "everything for your clubs, in one place." Not a
//  feature tour — one sentence, one button, one-way transition.
//
//  Presented as a fullScreenCover from OnboardingView; "Let's go →" is what actually
//  completes onboarding (calls the closure OnboardingView passes in), so the picker's
//  Continue button just opens this screen.
//

import SwiftUI

struct ThesisView: View {
    /// Followed clubs in picker order — drives the crest row + the brand-colored name list.
    let clubs: [Club]
    /// Teams with match alerts on (0 hides the alerts line).
    let alertCount: Int
    /// Completes onboarding + dismisses (passed by OnboardingView).
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            crestRow
                .padding(.bottom, 28)

            Text("You're all set.")
                .dsFont(30, weight: .bold)
                .foregroundStyle(Color.dsFgPrimary)
                .padding(.bottom, 14)

            thesisSentence
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            if alertCount > 0 {
                Label(
                    "Match alerts on for \(alertCount) team\(alertCount == 1 ? "" : "s")",
                    systemImage: "bell.fill"
                )
                .dsFont(14)
                .foregroundStyle(Color.dsFgTertiary)
                .padding(.top, 18)
            }

            Spacer(minLength: 0)

            // Same DSButton (filled, .regular) as the onboarding CTA — so the primary
            // action doesn't change style or size across the picker → thesis transition.
            DSButton("Let's go →", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsBgGrouped.ignoresSafeArea())
        .interactiveDismissDisabled() // one-way transition — no swipe-to-dismiss back to the picker
    }

    // Up to four brand-color crest circles. With more than four follows we show the first
    // four plus a "+N" chip so the row never overflows.
    private var crestRow: some View {
        let shown = Array(clubs.prefix(4))
        let extra = clubs.count - shown.count
        return HStack(spacing: -10) {
            ForEach(shown) { club in
                TeamLogo(urlString: club.logoURL, teamAbbreviation: club.abbreviation, size: 56)
                    .padding(5)
                    .background(Color.dsBgCard, in: Circle())
            }
            if extra > 0 {
                Text("+\(extra)")
                    .dsFont(17, weight: .bold)
                    .foregroundStyle(Color.dsFgSecondary)
                    .frame(width: 56, height: 56)
                    .background(Color.dsBgCard, in: Circle())
            }
        }
    }

    // "News, social, scores, and fan games for {names} — all in one place." with each club
    // name in its brand color. Names list with Oxford-comma grammar (1 / 2 / 3+); past four
    // names it collapses to "…and N more" so the sentence stays readable.
    private var thesisSentence: Text {
        let secondary = Color.dsFgSecondary
        var text = Text("News, social, scores, and fan games for ")
            .foregroundColor(secondary)

        let listed = Array(clubs.prefix(3))
        let remainder = clubs.count - listed.count

        for (index, club) in listed.enumerated() {
            if index > 0 {
                let isLastListed = index == listed.count - 1
                let separator: String
                if remainder > 0 {
                    separator = ", "
                } else if listed.count == 2 {
                    separator = " and "
                } else {
                    separator = isLastListed ? ", and " : ", "
                }
                text = text + Text(separator).foregroundColor(secondary)
            }
            text = text + Text(club.displayName)
                .foregroundColor(club.accentColor)
                .fontWeight(.semibold)
        }

        if remainder > 0 {
            text = text + Text(", and \(remainder) more").foregroundColor(secondary)
        }

        // `.callout` (~16pt) scales with Dynamic Type — concatenated colored Text can't use
        // the @ScaledMetric `.dsFont`, so a relative text style keeps it accessible.
        return (text + Text(" — all in one place.").foregroundColor(secondary))
            .font(.callout)
    }
}

#Preview {
    ThesisView(
        clubs: [],
        alertCount: 1,
        onContinue: {}
    )
}
