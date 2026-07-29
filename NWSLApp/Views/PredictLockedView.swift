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
//  THREE STATES, driven by what is actually knowable rather than by a timer:
//   1. Sealed, aggregate not yet available → the lock confirmation and a plain reassurance line.
//   2. Sealed, aggregate available → "312 of 340 fans have locked in" and the promise, spelled out.
//   3. Revealed (submissions closed) → where you went your own way, share, and the XI with bars.
//
//  ⚠️ THE AGGREGATE IS THE ONLY THING SHOWN BEFORE THE CLOSE, AND IT IS NEVER PER-PERSON. A count
//  of how many fans have locked in creates urgency from a real number; exposing whether a SPECIFIC
//  user has submitted would disclose someone else's activity and is permanently out of bounds.
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
                } else {
                    sealedPanel
                }
                sectionLabel(revealed ? "YOUR XI VS THE BOARD" : "YOUR LOCKED XI")
                xiSummary
                if !revealed, !isLoading {
                    Text("How \(clubLabel) picked opens \(closeLabel).")
                        .dsFont(11).foregroundStyle(Color.dsFgTertiary)
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
        names = Dictionary(
            await viewModel.roster(forTeam: prediction.teamAbbreviation).map { ($0.id, $0.name) },
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
                VStack(alignment: .trailing, spacing: 1) {
                    Text(countdown).dsFont(15, weight: .heavy).foregroundStyle(tint)
                    Text("to kickoff").dsFont(10).foregroundStyle(Color.dsFgTertiary)
                }
            }
            // State 1: nothing to report yet. Say so plainly rather than showing an empty panel.
            if !revealed, community == nil, !isLoading {
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

    // MARK: - State 2: sealed, with the aggregate

    @ViewBuilder
    private var sealedPanel: some View {
        if let community, community.submissions > 0 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(community.submissions)").dsFont(20, weight: .heavy)
                    Text(lockedInCopy(community.submissions)).dsFont(13).foregroundStyle(.secondary)
                }
                if let total = boardSize, total >= community.submissions {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.dsBgTertiary)
                            Capsule().fill(accent)
                                .frame(width: geo.size.width * (Double(community.submissions) / Double(total)))
                        }
                    }
                    .frame(height: 5)
                }
                Text("Nobody sees anyone's XI until submissions close \(closeLabel) — then the whole board opens at once.")
                    .dsFont(11.5).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.dsMdCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
        }
    }

    /// ⚠️ The denominator is NOT guaranteed to exist. The only club-size number the app holds is
    /// `totalPredictors`, which counts fans with at least one SCORED match this season — so early in
    /// a season the count of people who've locked in can legitimately EXCEED it, and rendering
    /// "312 of 280" would be visibly wrong. When there's no credible denominator we simply state the
    /// real number on its own, which is honest and still creates the urgency.
    private var boardSize: Int? {
        guard let total = viewModel.standingByTeam[item.fixture.teamAbbreviation]?.total, total > 0 else { return nil }
        return total
    }

    private func lockedInCopy(_ submissions: Int) -> String {
        let fan = submissions == 1 ? "fan has" : "fans have"
        if let total = boardSize, total >= submissions {
            return "of \(total) \(clubLabel) \(fan) locked in"
        }
        return "\(clubLabel) \(fan) locked in"
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
                    .dsFont(11, weight: .bold).tracking(1.2).foregroundStyle(Color.dsWarning)
                ForEach(lines, id: \.self) { line in
                    Text(line).dsFont(13).foregroundStyle(Color.dsFgPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Right or wrong, these are the picks worth arguing about.")
                    .dsFont(11).foregroundStyle(.secondary).padding(.top, 2)
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
                            .dsFont(10, weight: .bold).tracking(0.8).foregroundStyle(Color.dsFgTertiary)
                        ForEach(rows, id: \.index) { slot in
                            summaryRow(slot)
                        }
                    }
                }
            }
            if revealed, let community {
                Text("Bars show how much of \(clubLabel) picked each player · \(community.submissions) prediction\(community.submissions == 1 ? "" : "s")")
                    .dsFont(10.5).foregroundStyle(Color.dsFgTertiary)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusLg, style: .continuous))
    }

    private func summaryRow(_ slot: Formation.Slot) -> some View {
        let id = prediction?.slots[slot.index]
        let share = id.flatMap { community?.share(forPlayer: $0) }
        let isContrarian = (share ?? 1) < contrarianThreshold
        return HStack(spacing: 10) {
            Text(slot.group.shortLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.dsFgQuaternary)
                .frame(width: 30, alignment: .leading)
            Text(id.flatMap { names[$0] } ?? "—")
                .dsFont(13, weight: isContrarian && revealed ? .bold : .medium)
                .foregroundStyle(isContrarian && revealed ? Color.dsWarning : Color.dsFgPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if revealed, let share {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.dsBgTertiary)
                        Capsule().fill(isContrarian ? Color.dsWarning : accent)
                            .frame(width: geo.size.width * share)
                    }
                }
                .frame(width: 56, height: 4)
                Text(PredictPitchView.percent(share))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isContrarian ? Color.dsWarning : Color.dsFgTertiary)
                    .frame(width: 30, alignment: .trailing)
            }
        }
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

    private var countdown: String {
        let seconds = item.fixture.kickoff.timeIntervalSince(now)
        guard seconds > 0 else { return "—" }
        let hours = Int(seconds) / 3600
        if hours >= 24 { return "\(hours / 24)d" }
        if hours >= 1 { return "\(hours)h" }
        return "\(max(1, Int(seconds) / 60))m"
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

    private static let closeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}
