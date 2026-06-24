//
//  CompetitionFollowMigrationTests.swift
//  NWSLAppTests
//
//  The one-time fold of the pre-Competitions onboarding's curated competition slugs
//  (USWNT / WC / CONCACAF / Olympics / SheBelieves) into the real follow model:
//  USWNT + SheBelieves → follow the USA national team; CONCACAF → the Champions Cup
//  toggle; WC + Olympics dropped (no home yet). Runs once on FollowingStore.init, then
//  clears the legacy key so later launches no-op. Isolated UserDefaults suite per test.
//

import Foundation
import Testing
@testable import NWSLApp

struct CompetitionFollowMigrationTests {

    private let legacyKey = "followedCompetitionIDs"

    private func isolatedDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func migratesUSWNTToUSANationalTeam() {
        let defaults = isolatedDefaults("test.compmig.uswnt")
        defaults.set(["uswnt"], forKey: legacyKey)

        let store = FollowingStore(defaults: defaults)

        #expect(store.followedNationalTeams.contains("USA"))
        #expect(store.isConcacafFollowed == false)
        // Legacy key cleared so the migration is one-time.
        #expect((defaults.stringArray(forKey: legacyKey) ?? []).isEmpty)
    }

    @Test func migratesConcacafToToggle() {
        let defaults = isolatedDefaults("test.compmig.concacaf")
        defaults.set(["concacaf-w-champions"], forKey: legacyKey)

        let store = FollowingStore(defaults: defaults)

        #expect(store.isConcacafFollowed)
        #expect(store.followedNationalTeams.isEmpty)
    }

    @Test func sheBelievesAlsoMapsToUSA() {
        let defaults = isolatedDefaults("test.compmig.sheb")
        defaults.set(["shebelieves-cup"], forKey: legacyKey)

        let store = FollowingStore(defaults: defaults)

        #expect(store.followedNationalTeams.contains("USA"))
    }

    @Test func dropsUnmappableAndIsIdempotent() {
        let defaults = isolatedDefaults("test.compmig.drop")
        defaults.set(["womens-world-cup", "olympics"], forKey: legacyKey)

        let store = FollowingStore(defaults: defaults)

        // WC + Olympics have no home yet → nothing followed, key cleared.
        #expect(store.followedNationalTeams.isEmpty)
        #expect(store.isConcacafFollowed == false)
        #expect((defaults.stringArray(forKey: legacyKey) ?? []).isEmpty)

        // A second construction over the now-cleared defaults is a no-op (idempotent).
        let again = FollowingStore(defaults: defaults)
        #expect(again.followedNationalTeams.isEmpty)
    }

    @Test func competitionFollowKeysReflectModel() {
        let defaults = isolatedDefaults("test.compmig.keys")
        let store = FollowingStore(defaults: defaults)
        store.toggle(nationalTeam: NationalTeam.team(code: "USA")!)
        store.setConcacafFollowed(true)

        #expect(store.competitionFollowKeys == ["nt:USA", "concacaf"])
    }

    @Test func replaceCompetitionFollowKeysIsAuthoritative() {
        let defaults = isolatedDefaults("test.compmig.replace")
        let store = FollowingStore(defaults: defaults)
        store.toggle(nationalTeam: NationalTeam.team(code: "USA")!)
        store.setConcacafFollowed(true)

        // Device-authoritative mirror: the set becomes EXACTLY the new keys — USA is
        // dropped (not in the new set), BRA added, and the Cup turned off (no "concacaf").
        store.replaceCompetitionFollowKeys(["nt:BRA"])

        #expect(store.followedNationalTeams == ["BRA"])
        #expect(!store.isConcacafFollowed)
    }
}
