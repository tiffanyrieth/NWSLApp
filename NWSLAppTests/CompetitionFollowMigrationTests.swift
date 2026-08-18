//
//  CompetitionFollowMigrationTests.swift
//  NWSLAppTests
//
//  The one-time fold of the pre-Competitions onboarding's curated competition slugs
//  (USWNT / WC / CONCACAF / Olympics / SheBelieves) into the real follow model:
//  USWNT + SheBelieves → follow the USA national team; WC + Olympics + the retired
//  CONCACAF slug dropped (CONCACAF is now always-on core schedule content, no toggle).
//  Runs once on FollowingStore.init, then clears the legacy key so later launches no-op.
//  Isolated UserDefaults suite per test.
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
        // Legacy key cleared so the migration is one-time.
        #expect((defaults.stringArray(forKey: legacyKey) ?? []).isEmpty)
    }

    @Test func dropsRetiredConcacafSlug() {
        // The old `concacaf-w-champions` slug drove a CONCACAF follow TOGGLE that no longer
        // exists — CONCACAF is always-on core schedule content. The slug is now dropped
        // like WWC/Olympics (nothing followed), and the legacy key is still cleared.
        let defaults = isolatedDefaults("test.compmig.concacaf")
        defaults.set(["concacaf-w-champions"], forKey: legacyKey)

        let store = FollowingStore(defaults: defaults)

        #expect(store.followedNationalTeams.isEmpty)
        #expect((defaults.stringArray(forKey: legacyKey) ?? []).isEmpty)
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
        #expect((defaults.stringArray(forKey: legacyKey) ?? []).isEmpty)

        // A second construction over the now-cleared defaults is a no-op (idempotent).
        let again = FollowingStore(defaults: defaults)
        #expect(again.followedNationalTeams.isEmpty)
    }

    @Test func competitionFollowKeysReflectModel() {
        let defaults = isolatedDefaults("test.compmig.keys")
        let store = FollowingStore(defaults: defaults)
        store.toggle(nationalTeam: NationalTeam.team(code: "USA")!)

        #expect(store.competitionFollowKeys == ["nt:USA"])
    }

    @Test func replaceCompetitionFollowKeysIsAuthoritative() {
        let defaults = isolatedDefaults("test.compmig.replace")
        let store = FollowingStore(defaults: defaults)
        store.toggle(nationalTeam: NationalTeam.team(code: "USA")!)

        // Device-authoritative mirror: the set becomes EXACTLY the new keys — USA is
        // dropped (not in the new set), BRA added.
        store.replaceCompetitionFollowKeys(["nt:BRA"])

        #expect(store.followedNationalTeams == ["BRA"])
    }

    @Test func replaceCompetitionFollowKeysIgnoresRetiredConcacafKey() {
        // An existing user's stale server row may still carry the retired "concacaf" key.
        // It must decode into nothing (not crash, not resurrect a toggle) — only "nt:" keys
        // are honored. The stale row is pruned server-side on the next reconcile.
        let defaults = isolatedDefaults("test.compmig.staleconcacaf")
        let store = FollowingStore(defaults: defaults)

        store.replaceCompetitionFollowKeys(["nt:USA", "concacaf"])

        #expect(store.followedNationalTeams == ["USA"])
        #expect(store.competitionFollowKeys == ["nt:USA"])
    }
}
