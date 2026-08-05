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
    /// The team's last SUBMITTED XI (formation + slot→athleteID), used to pre-fill a FRESH fixture's
    /// picker so a regular tweaks 1–2 players instead of building 11 from scratch (task 17). Ignored
    /// when there's already an `existing` draft/submission for this fixture. The predicted SCORELINE is
    /// deliberately NOT carried — that's a per-match call, not a "usual lineup".
    private let savedLineup: (formation: String, slots: [Int: String])?
    private let loadRosterClosure: () async -> [Athlete]

    init(fixture: PredictionFixture,
         existing: XIPrediction?,
         savedLineup: (formation: String, slots: [Int: String])? = nil,
         loadRoster: @escaping () async -> [Athlete]) {
        self.fixture = fixture
        self.existing = existing
        self.savedLineup = savedLineup
        self.loadRosterClosure = loadRoster
        self.readOnly = existing?.state == .submitted
        // Formation: an existing draft wins, else the team's last submitted formation, else the default.
        self.formation = Formation(raw: existing?.formation ?? savedLineup?.formation ?? Formation.default.raw) ?? .default
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
        // An existing draft/submission for THIS fixture wins; otherwise seed from the team's last
        // submitted XI (task 17). Either way the ids are resolved against the CURRENT roster, so a
        // player who's since transferred out simply isn't in `byID` and that slot lands empty for the
        // user to fill — never a stale/ghost name.
        guard let source = existing?.slots ?? savedLineup?.slots else { return }
        let byID = Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        slots = source.reduce(into: [:]) { result, pair in
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

    /// Beginner-friendly quick-fill: a RANDOM formation + a distinct random player in every slot,
    /// **drawn from that slot's own position band** — keepers go in goal, defenders in defence, and
    /// so on. Still random within the band, so a squad with three keepers gives a different one each
    /// time you re-tap. Leaves the predicted scoreline untouched.
    ///
    /// ⚠️ CHANGED 2026-07-28 (owner, after living with it). This used to be POSITION-BLIND on
    /// purpose — "truly random, a keeper can land up top; a starting point to tweak, not a
    /// suggestion". In practice that made auto-pick something you had to undo rather than build on,
    /// so it now respects position. Don't revert it to blind on the strength of the old comment.
    ///
    /// The band comes from the same mapping the scorer uses (`PositionGroup`), so an auto-picked XI
    /// is banded exactly the way the +2 position bonus will judge it.
    func autoPick() {
        guard !readOnly, !roster.isEmpty else { return }
        formation = Formation.common.randomElement() ?? formation

        var byBand: [PositionGroup: [Athlete]] = [:]
        for athlete in roster { byBand[Self.band(of: athlete), default: []].append(athlete) }
        for band in byBand.keys { byBand[band]?.shuffle() }

        var assigned: [Int: Athlete] = [:]
        var used = Set<String>()
        var unfilled: [Formation.Slot] = []

        for slot in formation.slots {
            if let index = byBand[slot.group]?.firstIndex(where: { !used.contains($0.id) }) {
                let athlete = byBand[slot.group]![index]
                used.insert(athlete.id)
                assigned[slot.index] = athlete
            } else {
                unfilled.append(slot)
            }
        }

        // A band can genuinely run short — a random 5-3-2 against a squad carrying four defenders,
        // or a thin roster mid-season. Backfill rather than leave a hole: auto-pick's whole promise
        // is a COMPLETE XI you can then tweak, and a half-filled grid can't even be submitted.
        // Outfield slots take a non-keeper first, so a spare keeper is the last resort rather than
        // the first thing that lands up front — the exact outcome this change exists to avoid.
        if !unfilled.isEmpty {
            var spare = roster.filter { !used.contains($0.id) }.shuffled()
            for slot in unfilled {
                let preferred = slot.group == .gk
                    ? spare.firstIndex { Self.band(of: $0) == .gk }
                    : spare.firstIndex { Self.band(of: $0) != .gk }
                guard let index = preferred ?? (spare.isEmpty ? nil : spare.indices.first) else { break }
                let athlete = spare.remove(at: index)
                used.insert(athlete.id)
                assigned[slot.index] = athlete
            }
        }

        slots = assigned
    }

    /// An athlete's scoring band. Prefers the position ABBREVIATION ("G"/"CB"/"RW"), which is the
    /// reliable signal and the one `Athlete.isGoalkeeper` trusts; the display name is the fallback
    /// for the rare payload that omits it.
    private static func band(of athlete: Athlete) -> PositionGroup {
        if let abbreviation = athlete.positionAbbreviation, !abbreviation.isEmpty {
            return PositionGroup.from(abbreviation: abbreviation)
        }
        return PositionGroup.from(positionName: athlete.positionName)
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
