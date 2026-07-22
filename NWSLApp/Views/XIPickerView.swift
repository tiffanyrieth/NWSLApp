//
//  XIPickerView.swift
//  NWSLApp
//
//  The Predict the XI picker — Fan Zone game 1 (0.3.9). Presented as a sheet from
//  PredictXIView for one fixture. You choose a formation (which lays out 11 slots
//  on a pitch-styled grid), tap a slot to pick a player from the team's roster,
//  and set the final scoreline. Save a draft anytime; Submit (only when all 11 are
//  filled) locks it in — after which the sheet opens read-only.
//
//  All session state lives in XIPickerViewModel; this view persists drafts/commits
//  straight to PredictionStore (injected app-wide), so the parent slate updates via
//  observation when the sheet dismisses.
//

import SwiftUI

struct XIPickerView: View {
    let fixture: PredictionFixture
    let accent: Color
    let homeAbbr: String
    let awayAbbr: String
    private let clubLookup: (String) -> Club?

    @State private var picker: XIPickerViewModel
    @State private var activeSlot: SlotRef?
    @State private var didSubmit = false   // double-tap guard for the one-way submit
    @Environment(PredictionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Identifiable wrapper so a slot index can drive `.sheet(item:)`.
    private struct SlotRef: Identifiable { let id: Int }

    init(fixture: PredictionFixture,
         existing: XIPrediction?,
         accent: Color,
         homeAbbr: String,
         awayAbbr: String,
         loadRoster: @escaping () async -> [Athlete],
         club: @escaping (String) -> Club?) {
        self.fixture = fixture
        self.accent = accent
        self.homeAbbr = homeAbbr
        self.awayAbbr = awayAbbr
        self.clubLookup = club
        _picker = State(wrappedValue: XIPickerViewModel(fixture: fixture, existing: existing, loadRoster: loadRoster))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch picker.rosterState {
                case .idle, .loading:
                    ProgressView("Loading the squad…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    emptyRoster
                case .loaded:
                    content
                }
            }
            .background(Color.dsBgPrimary)
            .navigationTitle("\(picker.fixture.teamAbbreviation) XI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(picker.readOnly ? "Done" : "Cancel") { dismiss() }
                }
            }
            // "Playing as {name}" as a right-aligned strip BELOW the nav bar — consistent with every
            // other Fan Zone game (Bracket/Trivia/Know Her). The old trailing ToolbarItem was the lone
            // holdout that rendered it as a nav-bar pill and pushed the centered title off-center.
            .fanZonePlayingAs(accent: accent)
        }
        .task { await picker.load() }
        .sheet(item: $activeSlot) { ref in
            rosterSheet(for: ref.id)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                if picker.readOnly { submittedBanner }
                formationSection
                pitchGrid
                scorelineSection
                if !picker.readOnly { footerButtons }
            }
            .padding(20)
        }
    }

    private var submittedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(accent)
            Text("Submitted — locked in. Awaiting the result.")
                .dsFont(15, weight: .semibold)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Formation

    private var formationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FORMATION").dsFont(12, weight: .bold).foregroundStyle(.secondary)
                Spacer()
                if !picker.readOnly {
                    // Quick-fill helper: random formation + random XI (score untouched). Re-tap
                    // to re-roll. Placed here because it also sets the formation.
                    Button {
                        withAnimation(.snappy) { picker.autoPick() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "wand.and.stars")
                            Text("Auto-pick")
                        }
                        .dsFont(13, weight: .semibold)
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Formation.common) { formation in
                        let selected = formation == picker.formation
                        Button { picker.selectFormation(formation) } label: {
                            Text(formation.raw)
                                .dsFont(15, weight: .semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selected ? accent : Color.dsMdCard)
                                .foregroundStyle(selected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(picker.readOnly)
                    }
                }
            }
        }
    }

    // MARK: - Pitch grid

    private var pitchGrid: some View {
        VStack(spacing: 16) {
            ForEach(picker.formation.displayRows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(picker.formation.displayRows[rowIndex]) { slot in
                        slotCell(slot)
                    }
                }
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.dsPitch, .dsPitchBottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.dsPitchLine, lineWidth: 1)
        )
    }

    private func slotCell(_ slot: Formation.Slot) -> some View {
        let athlete = picker.athlete(inSlot: slot.index)
        return Button {
            activeSlot = SlotRef(id: slot.index)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let athlete {
                        // Filled slot → the player's headshot, jersey-number monogram fallback.
                        PlayerHeadshot(athleteID: athlete.id, size: 46) {
                            ZStack {
                                Circle().fill(accent)
                                Text(athlete.jersey ?? "—")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 46, height: 46)
                        }
                    } else {
                        // Empty slot → the "add" affordance.
                        ZStack {
                            Circle().fill(Color.white.opacity(0.14))
                            Image(systemName: "plus").foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 46, height: 46)
                    }
                }
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                Text(athlete.map { lastName($0) } ?? slot.group.shortLabel)
                    .font(.caption2.weight(athlete != nil ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(athlete != nil ? 1 : 0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
        .disabled(picker.readOnly)
    }

    private func lastName(_ athlete: Athlete) -> String {
        athlete.shortName ?? athlete.name.split(separator: " ").last.map(String.init) ?? athlete.name
    }

    // MARK: - Scoreline

    private var scorelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FINAL SCORE").dsFont(12, weight: .bold).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                scoreStepper(abbr: homeAbbr, value: picker.homeScore,
                             onDec: picker.decrementHome, onInc: picker.incrementHome)
                Text("–").dsFont(22, weight: .bold).foregroundStyle(.secondary)
                scoreStepper(abbr: awayAbbr, value: picker.awayScore,
                             onDec: picker.decrementAway, onInc: picker.incrementAway)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dsMdCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func scoreStepper(abbr: String, value: Int, onDec: @escaping () -> Void, onInc: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Text(abbr).dsFont(12, weight: .bold)
            HStack(spacing: 14) {
                stepButton("minus", action: onDec)
                Text("\(value)")
                    .dsFont(28, weight: .heavy, monospacedDigit: true)
                    .frame(minWidth: 28)
                stepButton("plus", action: onInc)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(picker.readOnly ? .secondary : accent)
                .frame(width: 34, height: 34)
                .background(Color.dsMdPanelBottom)
                .clipShape(Circle())
        }
        .disabled(picker.readOnly)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 10) {
            Button {
                guard !didSubmit else { return }          // double-tap guard (submit is one-way)
                // Deadline re-check: the open-fixture card blocks ENTERING a closed fixture, but if the
                // deadline (kickoff−2h) passes while this sheet is open, don't LOCK IN a late prediction
                // that would still be scored. Save the draft so nothing's lost, then close.
                guard fixture.deadline.timeIntervalSinceNow > 0 else {
                    store.saveDraft(picker.toPrediction())
                    dismiss()
                    return
                }
                didSubmit = true
                store.saveDraft(picker.toPrediction())   // persist the latest as a draft…
                store.submit(fixtureID: fixture.id)       // …then flip it to submitted (one-way)
                // Game Center (additive): "First Prediction" — idempotent, so firing
                // on every submit is harmless. No-ops when not signed in.
                GameCenterManager.shared.report(GameCenterID.Achievement.firstPrediction)
                // Entry was gated (open-fixture tap), so we're signed in: the prediction is
                // locked and the per-team leaderboard push happens when it's later scored.
                dismiss()
            } label: {
                Text(picker.isComplete ? "Submit & lock in" : "Pick all 11 to submit (\(picker.assignedCount)/11)")
                    .dsFont(17, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(picker.isComplete ? accent : Color.dsMdPanelBottom)
                    .foregroundStyle(picker.isComplete ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!picker.isComplete)

            Button {
                store.saveDraft(picker.toPrediction())
                dismiss()
            } label: {
                Text("Save draft")
                    .dsFont(17, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(accent)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accent, lineWidth: 1.5)
                    )
            }
        }
    }

    // MARK: - Roster sheet

    private func rosterSheet(for slotIndex: Int) -> some View {
        NavigationStack {
            List {
                ForEach(picker.sheetGroups(excludingSlot: slotIndex)) { group in
                    Section(group.label) {
                        ForEach(group.athletes) { athlete in
                            Button {
                                picker.assign(athlete, to: slotIndex)
                                activeSlot = nil
                            } label: {
                                athleteRow(athlete, selected: picker.athlete(inSlot: slotIndex)?.id == athlete.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if picker.athlete(inSlot: slotIndex) != nil {
                    Section {
                        Button("Clear this slot", role: .destructive) {
                            picker.clear(slotIndex)
                            activeSlot = nil
                        }
                    }
                }
            }
            .navigationTitle("Choose player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSlot = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func athleteRow(_ athlete: Athlete, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(athlete.jersey ?? "—")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(athlete.name).dsFont(15, weight: .semibold)
                if let position = athlete.positionName {
                    Text(position).dsFont(11).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
            }
        }
        // Full-row hit target. The row is a `.buttonStyle(.plain)` Button label, which hit-tests only
        // the OPAQUE content (the name/jersey/checkmark) — the Spacer and empty area were dead, so only
        // the player's name was tappable. The List cell's background isn't the label's. (Tap-target audit.)
        .contentShape(Rectangle())
    }

    private var emptyRoster: some View {
        RetryStateView(title: "Couldn't load the squad",
                       message: "Check your connection and try again.",
                       icon: "person.3.sequence") { await picker.load() }
    }
}
