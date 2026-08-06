//
//  PredictLockedView.swift
//  NWSLApp
//
//  The locked wait — where a submitted Predict the XI entry lives until the result (2026-07-28).
//
//  ⚠️ WHY THIS SCREEN EXISTS. Submitting used to be a silent tap followed by nothing: "Locked in …
//  Tap to review" just reopened the picker in read-only mode, so the hours between submitting and
//  full time were empty. That gap is why the game read as filing a survey rather than entering a
//  contest. This gives the wait content, and gives locking in a payoff.
//
//  TWO STATES, driven by what is actually knowable rather than by a timer:
//   1. Sealed → the lock confirmation, your XI ON THE PITCH, and when things open.
//   2. Revealed (submissions closed) → where you went your own way, share, and the XI with
//      ownership bars (the row list, which is the only layout that can carry them).
//
//  ⚠️ NO "N of M FANS HAVE LOCKED IN" COUNTER (removed 2026-07-29, owner). It read confusingly at
//  small scale — "1 of 56 Washington Spirit fan has locked in" — and mixed two different populations:
//  the numerator was submissions for THIS fixture, the denominator was fans with ≥1 SCORED match this
//  season. It also wasn't pulling its weight: whether you're first or hundredth changes nothing about
//  your own sealed XI. Don't reintroduce it. (The privacy line still stands and always will: any
//  pre-close aggregate must be a COUNT, never per-person — exposing whether a SPECIFIC user has
//  submitted discloses someone else's activity and is permanently out of bounds.)
//
//  ⚠️ THE STATE COMES FROM THE SERVER, NOT THE CLOCK. `revealed` is decided by the proxy, which
//  knows kickoff and refuses to serve percentages early. A device clock could be wrong or set
//  forward deliberately; gating on it would hand out the consensus while people are still picking.
//

import Combine
import SwiftUI

struct PredictLockedView: View {
    let item: PredictXIViewModel.PredictionItem
    let viewModel: PredictXIViewModel

    @Environment(PredictionStore.self) private var store

    @State private var community: PredictCommunity?
    @State private var names: [String: String] = [:]
    /// athleteID → jersey number, for the pitch marker's fallback when a player has no headshot —
    /// the picker shows the number there, so this screen must too.
    @State private var jerseys: [String: String] = [:]
    @State private var isLoading = true
    @State private var now = Date()

    private let accent = Color.dsGamePredict
    /// A pick owned by fewer than a third of the club is a talking point.
    private let contrarianThreshold = 0.30
    /// A starter most of the club has that you don't is the other half of the argument.
    private let popularThreshold = 0.60

    private var prediction: XIPrediction? { item.prediction }
    private var revealed: Bool { community?.revealed == true }

    /// Ticks the kickoff countdown once a minute — cheap, and the number is only meaningful to the
    /// minute anyway.
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                lockedCard
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                } else if revealed {
                    contrarianPanel
                    shareRow
                }
                sectionLabel(revealed ? "YOUR XI VS THE BOARD" : "YOUR LOCKED XI")
                // Before the reveal there are no ownership numbers to show, so the XI is just
                // your XI — and it gets the same field the picker and the results screen use.
                // After the reveal the row list earns its place: it carries the ownership bars,
                // which are the entire point of "vs the board" and can't live on a pitch.
                if revealed {
                    xiSummary
                } else {
                    pitch
                }
                if !revealed, !isLoading {
                    VStack(spacing: 3) {
                        Text("How \(clubLabel) picked opens \(closeLabel).")
                        Text("Your score is posted after full time.")
                    }
                    .dsFont(12).foregroundStyle(Color.dsFgTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .fanZonePlayingAsHeader(accent: accent)
        }
        .background(Color.dsBgPrimary)
        .nativeBackButton(title: "Locked in")
        .task { await load() }
        .onReceive(clock) { now = $0 }
    }

    private func load() async {
        guard let prediction else { isLoading = false; return }
        let roster = await viewModel.roster(forTeam: prediction.teamAbbreviation)
        names = Dictionary(roster.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        jerseys = Dictionary(roster.compactMap { a in a.jersey.map { (a.id, $0) } },
                             uniquingKeysWith: { first, _ in first })
        if let week = FanZoneCadence.soccerWeek(for: item.fixture.kickoff) {
            let service = PredictCommunityService()
            let map = await service.distribution(
                season: String(AppConfig.currentSeasonYear),
                fixtures: [PredictCommunityRequest(eventID: prediction.eventID,
                                                   team: prediction.teamAbbreviation,
                                                   week: week)])
            community = map[item.fixture.id]
        }
        isLoading = false
    }

    // MARK: - The locked card

    private var lockedCard: some View {
        let tint = revealed ? accent : Color.dsSuccess
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .dsFont(15).foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tint.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Locked in").dsFont(15, weight: .bold)
                    if let p = prediction {
                        Text("\(p.formation) · you called it \(p.homeScoreGuess)–\(p.awayScoreGuess)")
                            .dsFont(12).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                // Once kickoff has passed there is no countdown left — it rendered "— to kickoff",
                // which reads as missing data on a match that's actually in progress.
                VStack(alignment: .trailing, spacing: 1) {
                    if hasKickedOff {
                        Text("LIVE").dsFont(15, weight: .heavy).foregroundStyle(Color.dsStateLive)
                        Text("underway").dsFont(12).foregroundStyle(Color.dsFgTertiary)
                    } else {
                        Text(countdown).dsFont(15, weight: .heavy).foregroundStyle(tint)
                        Text("to kickoff").dsFont(12).foregroundStyle(Color.dsFgTertiary)
                    }
                }
            }
            // Sealed: say it plainly. This used to be gated on the aggregate being absent, because a
            // panel underneath carried the reassurance when it was present; that panel is gone, so
            // the line now shows whenever the board is still sealed.
            if !revealed, !isLoading {
                Text("Your picks are sealed. Nothing to do now but wait.")
                    .dsFont(12, weight: .semibold).foregroundStyle(Color.dsSuccess)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1.5)
        )
    }

    // MARK: - Your XI, on the pitch

    /// ⚠️ THE PITCH, NOT A LIST (owner, 2026-07-29). This screen used to render the sealed XI as a
    /// plain text list of eleven names — "a generic text version of your picks that is harsh to read",
    /// on a game whose other two screens (the picker and the result) both draw a proper field. The app
    /// already owns the pretty format; the wait screen should use it.
    ///
    /// Deliberately built from `Formation.displayRowGroups` + `predictPitchChrome()` — the SAME row
    /// source and the SAME field modifier as `XIPickerView.pitchGrid` and `PredictPitchView`. That
    /// shared modifier is the anti-drift seam (owner rule, 2026-07-28): three screens draw this field,
    /// and they must not diverge.
    @ViewBuilder
    private var pitch: some View {
        if let raw = prediction?.formation, let formation = Formation(raw: raw) {
            VStack(spacing: 16) {
                // Identifiable ROW VALUES, never `ForEach(indices)` — that crashed the picker
                // out-of-bounds when a row count shrank (see Formation.DisplayRow).
                ForEach(formation.displayRowGroups) { rowGroup in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(rowGroup.slots) { slot in
                            pitchCell(slot)
                        }
                    }
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .predictPitchChrome()
        } else {
            // No parseable formation ⇒ no field to draw. Fall back to the row list rather than an
            // empty green rectangle: the XI is the content, the pitch is the presentation.
            xiSummary
        }
    }

    /// One pitch marker: headshot (position-band monogram fallback) + surname, mirroring the picker's
    /// filled slot so a locked XI looks like the XI you just built.
    private func pitchCell(_ slot: Formation.Slot) -> some View {
        let id = prediction?.slots[slot.index]
        return VStack(spacing: 5) {
            PlayerHeadshot(athleteID: id, size: 46) {
                ZStack {
                    Circle().fill(accent)
                    // Jersey number, exactly like the picker's filled slot — falling back to the
                    // position band only when the roster carries no number.
                    Text(id.flatMap { jerseys[$0] } ?? slot.group.shortLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
            }
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            Text(surname(of: id) ?? slot.group.shortLabel)
                .dsFont(12, weight: .semibold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 62)
    }

    /// Surname only — full names don't fit a 62pt marker, and the picker shows surnames too.
    private func surname(of athleteID: String?) -> String? {
        guard let athleteID, let full = names[athleteID] else { return nil }
        return full.split(separator: " ").last.map(String.init) ?? full
    }

    // MARK: - State 3: crowd revealed

    @ViewBuilder
    private var contrarianPanel: some View {
        let lines = contrarianLines
        // Render NOTHING rather than an empty state — a panel headed "where you went your own way"
        // with nothing under it says the opposite of what it means.
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHERE YOU WENT YOUR OWN WAY")
                    .dsFont(12, weight: .bold).tracking(1.2).foregroundStyle(Color.dsWarning)
                ForEach(lines, id: \.self) { line in
                    Text(line).dsFont(13).foregroundStyle(Color.dsFgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Right or wrong, these are the picks worth arguing about.")
                    .dsFont(12).foregroundStyle(.secondary).padding(.top, 2)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsWarning.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous)
                    .strokeBorder(Color.dsWarning.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var contrarianLines: [String] {
        guard let community, let prediction else { return [] }
        let picked = prediction.pickedAthleteIDs
        var lines: [String] = []
        for pick in community.contrarians(among: Array(picked), below: contrarianThreshold).prefix(3) {
            let name = names[pick.playerID] ?? "your pick"
            lines.append("You're one of \(PredictPitchView.percent(pick.share)) starting \(name).")
        }
        for omission in community.highOwnershipOmissions(notPicked: picked, above: popularThreshold).prefix(2) {
            let name = names[omission.playerID] ?? "a starter"
            lines.append("\(PredictPitchView.percent(omission.share)) have \(name) starting. You don't.")
        }
        return lines
    }

    @ViewBuilder
    private var shareRow: some View {
        if let prediction, let formation = Formation(raw: prediction.formation) {
            PredictShareLink(
                card: PredictShareCard(
                    kind: .preKickoff,
                    teamAbbr: prediction.teamAbbreviation,
                    opponentAbbr: item.fixture.opponentAbbreviation,
                    formation: formation,
                    rows: shareRows(formation: formation),
                    headline: "\(prediction.homeScoreGuess)–\(prediction.awayScoreGuess)",
                    subhead: "My XI · we'll see",
                    accent: accent),
                label: "Share your XI",
                accent: accent)
        }
    }

    private func shareRows(formation: Formation) -> [PredictShareCard.Row] {
        formation.slots.compactMap { slot in
            guard let id = prediction?.slots[slot.index] else { return nil }
            return PredictShareCard.Row(band: slot.group.shortLabel,
                                        name: names[id] ?? "Player",
                                        marker: nil)
        }
    }

    // MARK: - The XI summary

    private var xiSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PositionGroup.allCases, id: \.self) { group in
                let rows = slots(in: group)
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bandTitle(group).uppercased())
                            .dsFont(12, weight: .bold).tracking(0.8).foregroundStyle(Color.dsFgTertiary)
                        ForEach(rows, id: \.index) { slot in
                            summaryRow(slot)
                        }
                    }
                }
            }
            if revealed, let community {
                Text("Bars show how much of \(clubLabel) picked each player · \(community.submissions) prediction\(community.submissions == 1 ? "" : "s")")
                    .dsFont(12).foregroundStyle(Color.dsFgTertiary)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    /// One picked player: NAME ON ITS OWN LINE, bar full-width beneath it.
    ///
    /// ⚠️ The name is NOT inline with the bar (2026-08-01). It used to be
    /// `HStack { band · name · Spacer · bar · % }`, which made every bar START wherever that
    /// player's name happened to end — so "Claudia Martínez" and "Tara Rudd" produced bars of
    /// different lengths for the SAME share, and the block couldn't be compared down the column.
    /// This is the identical fix the two community games already carry; the layout mirrors
    /// `CommunityResultsView.optionRow` so every "how everyone picked" surface reads the same way.
    /// It also lets a long name WRAP instead of truncating, which is what AX1 needs.
    private func summaryRow(_ slot: Formation.Slot) -> some View {
        let id = prediction?.slots[slot.index]
        let share = id.flatMap { community?.share(forPlayer: $0) }
        let isContrarian = (share ?? 1) < contrarianThreshold
        let name = id.flatMap { names[$0] } ?? "—"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(slot.group.shortLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.dsFgQuaternary)
                    .frame(width: 30, alignment: .leading)
                Text(name)
                    .dsFont(13, weight: isContrarian && revealed ? .bold : .medium)
                    .foregroundStyle(isContrarian && revealed ? Color.dsWarning : Color.dsFgPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if revealed, let share {
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.dsBgTertiary)
                            Capsule().fill(isContrarian ? Color.dsWarning : accent)
                                .frame(width: max(2, geo.size.width * share))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
                    // A minimum width (not a fixed one) keeps the right edges aligned down the
                    // block while still scaling with Dynamic Type.
                    Text(PredictPitchView.percent(share))
                        .dsFont(12, weight: .semibold, monospacedDigit: true)
                        .foregroundStyle(isContrarian ? Color.dsWarning : Color.dsFgTertiary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                // Indent the bar to the NAME, not the band chip, so GK/DEF/MID/FWD stay a clean
                // scannable column down the left edge (chip 30 + HStack spacing 10).
                .padding(.leading, 40)
            }
        }
        // One player = one fact for VoiceOver, rather than three fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(band: slot.group.shortLabel, name: name, share: share, isContrarian: isContrarian))
    }

    /// "DEF, Tara Rudd: picked by 100 percent" — plus the contrarian flag when it's showing.
    /// Pre-reveal there is no share to read, so it stops at the name.
    private func accessibilityText(band: String, name: String, share: Double?, isContrarian: Bool) -> String {
        guard revealed, let share else { return "\(band), \(name)" }
        let pct = Int((share * 100).rounded())
        return "\(band), \(name): picked by \(pct) percent\(isContrarian ? ", a contrarian pick" : "")"
    }

    private func slots(in group: PositionGroup) -> [Formation.Slot] {
        guard let raw = prediction?.formation, let formation = Formation(raw: raw) else { return [] }
        return formation.slots.filter { $0.group == group }
    }

    // MARK: - Helpers

    private var clubLabel: String {
        viewModel.club(forAbbreviation: item.fixture.teamAbbreviation)?.displayName
            ?? item.fixture.teamAbbreviation
    }

    /// The close time as the server reported it when available — never the device clock.
    private var closeLabel: String {
        let date = community?.closesAt ?? item.fixture.deadline
        return Self.closeFormatter.string(from: date)
    }

    /// Ticks with `now` (the 60s clock), so the card flips to LIVE without a reload.
    private var hasKickedOff: Bool { item.fixture.kickoff <= now }

    private var countdown: String {
        let seconds = item.fixture.kickoff.timeIntervalSince(now)
        guard seconds > 0 else { return "—" }
        let hours = Int(seconds) / 3600
        if hours >= 24 { return "\(hours / 24)d" }
        if hours >= 1 { return "\(hours)h" }
        return "\(max(1, Int(seconds) / 60))m"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).dsFont(12, weight: .bold).tracking(1.2).foregroundStyle(.secondary)
    }

    private func bandTitle(_ group: PositionGroup) -> String {
        switch group {
        case .gk: return "Goalkeeper"
        case .def: return "Defense"
        case .mid: return "Midfield"
        case .fwd: return "Attack"
        }
    }

    private static let closeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}
