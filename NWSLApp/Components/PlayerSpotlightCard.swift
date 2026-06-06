//
//  PlayerSpotlightCard.swift
//  NWSLApp
//
//  Home's Module 2 ("Get to know your players") — the Option B "mini profile"
//  card from Reference/Design/spotlight-design-spec.md. One per followed team:
//  a "Player of the week" label, jersey badge, name, "Position · Team", a 2-3
//  sentence bio blurb (the hook that sells the player before you tap), and a
//  video thumbnail with a play icon + source attribution.
//
//  This is a plain label view — the WHOLE card is wrapped in a NavigationLink in
//  HomeView that pushes PlayerSpotlightView (where the video opens). So the
//  thumbnail's play badge signals "there's a video inside," not a direct link.
//  Written-only spotlights (no video) hide the thumbnail and show a "Read full
//  profile" cue instead.
//
//  TEMP (no team-color source on Home): the jersey badge uses the app accent
//  (Color.teamAccent(hex: nil)) and the thumbnail is a DESIGNED crest tile, not a
//  fetched image — Home fetches neither rosters (for the club color) nor per-post
//  media. When a content backend lands, pass the club hex for a true team-colored
//  badge and swap the tile for a real AsyncImage thumbnail.
//

import SwiftUI

struct PlayerSpotlightCard: View {
    let spotlight: PlayerSpotlight
    /// Resolved from the followed Club directory by abbreviation (crest + name).
    let club: Club?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Player of the week")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 14) {
                jerseyBadge
                VStack(alignment: .leading, spacing: 3) {
                    Text(spotlight.playerName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text("\(spotlight.position) · \(teamName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // The hook — sells the player on the scroll, like an IG caption.
            Text(spotlight.bioBlurb)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            if spotlight.videoURL != nil {
                videoPreview
            } else {
                readProfileCue
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Jersey badge

    private var jerseyBadge: some View {
        let accent = Color.teamAccent(hex: nil)   // TEMP: no Club hex — app accent
        return ZStack {
            Circle().fill(accent.fill)
            Text("\(spotlight.jerseyNumber)")
                .font(.title2.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(accent.on)
        }
        .frame(width: 52, height: 52)
    }

    // MARK: - Video preview (designed tile — see file note)

    private var videoPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    if let title = spotlight.videoTitle {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if let source = spotlight.videoSource {
                        Text("via \(source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var thumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemGray5), Color(.systemGray4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            TeamLogo(urlString: club?.logoURL, size: 56)
                .opacity(0.9)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 4)
        }
        .frame(height: 168)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Written-only cue (no video)

    private var readProfileCue: some View {
        HStack(spacing: 4) {
            Text("Read full profile")
                .fontWeight(.semibold)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(Color.accentColor)
    }

    private var teamName: String {
        club?.shortName ?? club?.displayName ?? spotlight.teamAbbreviation
    }
}
