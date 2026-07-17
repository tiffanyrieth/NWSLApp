//
//  XIPickerViewModel.swift
//  NWSLApp
//
//  The in-flight Predict the XI picker session for ONE fixture — Fan Zone game 1
//  (0.3.9). Pure UI state (no networking of its own beyond a roster loader handed
//  in by PredictXIViewModel, so the per-team roster cache is shared): the chosen
//  formation, the slot → athlete assignments, and the predicted scoreline. It
//  hydrates from an existing draft/submitted prediction and converts back to an
//  `XIPrediction` for the store on save/submit.
//
//  A SUBMITTED prediction opens read-only (`readOnly`) — every mutator no-ops — so
//  a committed XI can be reviewed but never edited (the store guards too).
//

import Foundation

@Observable
final class XIPickerViewModel {
    enum RosterState { case idle, loading, loaded, empty }

    let fixture: PredictionFixture
    let readOnly: Bool

    private(set) var formation: Formation
    private(set) var slots: [Int: Athlete]      // slot index → chosen athlete
    private(set) var homeScore: Int
    private(set) var awayScore: Int

    private(set) var roster: [Athlete] = []
    private(set) var rosterState: RosterState = .idle

    private let existing: XIPrediction?
    private let loadRosterClosure: () async -> [Athlete]

    init(fixture: PredictionFixture,
         existing: XIPrediction?,
         loadRoster: @escaping () async -> [Athlete]) {
        self.fixture = fixture
        self.existing = existing
        self.loadRosterClosure = loadRoster
        self.readOnly = existing?.state == .submitted
        self.formation = Formation(raw: existing?.formation ?? Formation.default.raw) ?? .default
        self.slots = [:]
        self.homeScore = existing?.homeScoreGuess ?? 0
        self.awayScore = existing?.awayScoreGuess ?? 0
    }

    // MARK: - Loading

    /// Fetch the roster (shared cache via the closure) and resolve any saved slot
    /// ids → athletes. Idempotent.
    func load() async {
        guard rosterState == .idle else { return }
        rosterState = .loading
        let athletes = await loadRosterClosure()
        roster = athletes
        hydrateSlots(roster: athletes)
        rosterState = athletes.isEmpty ? .empty : .loaded
    }

    private func hydrateSlots(roster: [Athlete]) {
        guard let existing else { return }
        let byID = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        slots = existing.slots.reduce(into: [:]) { result, pair in
            if let athlete = byID[pair.value] { result[pair.key] = athlete }
        }
    }

    // MARK: - Derived

    /// All 11 slots filled — the gate on submitting.
    var isComplete: Bool { slots.count == 11 }
    var assignedCount: Int { slots.count }

    /// The match's home/away abbreviations (the scoreline is in match orientation,
    /// not "your team" orientation, so it scores against ESPN's home/away).
    var homeAbbreviation: String { fixture.isHome ? fixture.teamAbbreviation : fixture.opponentAbbreviation }
    var awayAbbreviation: String { fixture.isHome ? fixture.opponentAbbreviation : fixture.teamAbbreviation }

    /// Roster grouped for the picker sheet, with players already placed in OTHER
    /// slots removed and the tapped slot's OWN band led first (tap a GK slot → see
    /// keepers first), the rest following in FWD→MID→DEF→GK order. The full squad
    /// is offered for any slot — the band is a suggestion, and scoring rewards a
    /// correct player even out of position (only the +2 band bonus is slot-tied).
    func sheetGroups(excludingSlot slotIndex: Int) -> [Roster.PositionGroup] {
        let pickedElsewhere = Set(slots.filter { $0.key != slotIndex }.values.map(\.id))
        let groups = Roster.grouped(roster.filter { !pickedElsewhere.contains($0.id) })
        guard let leadTitle = formation.slot(at: slotIndex)?.group.sectionTitle else { return groups }
        // Stable partition: the slot's own band first, everything else in place.
        return groups.sorted { ($0.label == leadTitle ? 0 : 1) < ($1.label == leadTitle ? 0 : 1) }
    }

    func athlete(inSlot index: Int) -> Athlete? { slots[index] }

    // MARK: - Mutation (no-ops when read-only)

    func selectFormation(_ formation: Formation) {
        guard !readOnly, formation != self.formation else { return }
        self.formation = formation
        // All formations have the same 11 slot indices (0…10), so assignments
        // carry over; only the bands behind them change.
    }

    func assign(_ athlete: Athlete, to slotIndex: Int) {
        guard !readOnly else { return }
        slots = slots.filter { $0.value.id != athlete.id }   // a player holds one slot
        slots[slotIndex] = athlete
    }

    /// Beginner-friendly quick-fill: a RANDOM formation + a distinct random player in every
    /// slot. Truly random by design — position-blind, so a keeper can land up top; it's a
    /// starting point to tweak, not a suggestion. Leaves the predicted scoreline untouched.
    func autoPick() {
        guard !readOnly, !roster.isEmpty else { return }
        formation = Formation.common.randomElement() ?? formation
        let indices = formation.slots.map(\.index)
        let picks = roster.shuffled().prefix(indices.count)
        slots = Dictionary(uniqueKeysWithValues: zip(indices, picks))
    }

    func clear(_ slotIndex: Int) {
        guard !readOnly else { return }
        slots[slotIndex] = nil
    }

    func incrementHome() { guard !readOnly else { return }; homeScore = min(homeScore + 1, 20) }
    func decrementHome() { guard !readOnly else { return }; homeScore = max(homeScore - 1, 0) }
    func incrementAway() { guard !readOnly else { return }; awayScore = min(awayScore + 1, 20) }
    func decrementAway() { guard !readOnly else { return }; awayScore = max(awayScore - 1, 0) }

    // MARK: - Output

    /// Snapshot the session as a storable prediction (state preserved from the
    /// existing one; the store stamps draft/submitted).
    func toPrediction() -> XIPrediction {
        XIPrediction(
            fixtureID: fixture.id,
            eventID: fixture.eventID,
            teamAbbreviation: fixture.teamAbbreviation,
            formation: formation.raw,
            slots: slots.mapValues(\.id),
            homeScoreGuess: homeScore,
            awayScoreGuess: awayScore,
            state: existing?.state ?? .draft
        )
    }
}
