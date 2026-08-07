import Testing
import Foundation
@testable import FindlyKit

/// specs/009-device-runtime.md §7 — the persisted half of the disclosure gate.
///
/// Acknowledgement MUST survive relaunch (a user who has already read the explanation should not
/// re-read it every launch), which is the opposite of the banner's dismissal — that one is
/// deliberately session-only. The two live in different places for exactly that reason.
@Suite struct PermissionDisclosureStateStoringTests {

    @Test func nothingIsAcknowledgedInitially() {
        let store = InMemoryPermissionDisclosureStore()

        #expect(store.isAcknowledged(.foreground) == false)
        #expect(store.isAcknowledged(.background) == false)
    }

    @Test func acknowledgingOneKindDoesNotAcknowledgeTheOther() {
        // 003 §11.2: the background ask is a SEPARATE, later request with its own rationale.
        // Collapsing them into one flag would silently skip the background disclosure — the exact
        // screen Play's background-location review looks for.
        let store = InMemoryPermissionDisclosureStore()

        store.acknowledge(.foreground)

        #expect(store.isAcknowledged(.foreground))
        #expect(store.isAcknowledged(.background) == false)
    }

    @Test func acknowledgementIsIdempotent() {
        let store = InMemoryPermissionDisclosureStore()

        store.acknowledge(.background)
        store.acknowledge(.background)

        #expect(store.isAcknowledged(.background))
    }

    @Test func clearForgetsEverything() {
        // Part of the account-deletion local wipe (specs/008 §4.4): a new user on this device must
        // see the disclosure again — it is consent, not a device-level preference.
        let store = InMemoryPermissionDisclosureStore()
        store.acknowledge(.foreground)
        store.acknowledge(.background)

        store.clear()

        #expect(store.isAcknowledged(.foreground) == false)
        #expect(store.isAcknowledged(.background) == false)
    }

    // MARK: - Decline (I31, mirrors A25 — 009 §7's "answered" state includes "Not now")

    @Test func nothingIsDeclinedInitially() {
        let store = InMemoryPermissionDisclosureStore()

        #expect(store.isDeclined(.foreground) == false)
        #expect(store.isDeclined(.background) == false)
    }

    @Test func decliningOneKindDoesNotDeclineTheOther() {
        let store = InMemoryPermissionDisclosureStore()

        store.decline(.foreground)

        #expect(store.isDeclined(.foreground))
        #expect(store.isDeclined(.background) == false)
    }

    @Test func declineIsIdempotent() {
        let store = InMemoryPermissionDisclosureStore()

        store.decline(.background)
        store.decline(.background)

        #expect(store.isDeclined(.background))
    }

    @Test func declineAndAcknowledgeAreIndependentFlags() {
        // Declining must not also record an acknowledgement, and vice versa — the two states drive
        // different `PermissionFlowPolicy` decisions and conflating them was the exact class of bug
        // A25's round-1 Major 1 found (a dead-end banner button from collapsing distinct states).
        let store = InMemoryPermissionDisclosureStore()

        store.decline(.foreground)

        #expect(store.isAcknowledged(.foreground) == false)
    }

    @Test func clearDeclinedForgetsOnlyTheGivenKindsDecline() {
        // Used when the banner's explicit "reopen the disclosure" action fires (009 §7, A25/I31) —
        // must not also fabricate an acknowledgement that was never given, and must not touch the
        // other kind's decline.
        let store = InMemoryPermissionDisclosureStore()
        store.decline(.foreground)
        store.decline(.background)

        store.clearDeclined(.foreground)

        #expect(store.isDeclined(.foreground) == false)
        #expect(store.isDeclined(.background), "clearing one kind's decline must not clear the other's")
        #expect(store.isAcknowledged(.foreground) == false, "clearing a decline must not fabricate an acknowledgement")
    }

    @Test func clearForgetsDeclinesToo() {
        // I31 (mirrors A25's Major 2): the decline state is part of the same account-deletion local
        // wipe as acknowledgement — a different user on this device must see the disclosure again.
        let store = InMemoryPermissionDisclosureStore()
        store.decline(.foreground)
        store.decline(.background)

        store.clear()

        #expect(store.isDeclined(.foreground) == false)
        #expect(store.isDeclined(.background) == false)
    }

    @Test func userDefaultsStore_persistsAcrossInstances() {
        // The real implementation, exercised against an isolated suite so it cannot collide with
        // the app's own defaults or another test.
        let suiteName = "PermissionDisclosureStateStoringTests.persist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        UserDefaultsPermissionDisclosureStore(defaults: defaults).acknowledge(.foreground)

        let reloaded = UserDefaultsPermissionDisclosureStore(defaults: defaults)
        #expect(reloaded.isAcknowledged(.foreground))
        #expect(reloaded.isAcknowledged(.background) == false)
    }

    @Test func userDefaultsStore_declinePersistsAcrossInstancesAndSurvivesRelaunch() {
        // The crux of I31: a fresh process (the exact shape of a cold launch/relaunch) must still
        // see a prior decline — this is what makes the disclosure stop auto-re-presenting on ANY
        // future launch, not just for the rest of one session.
        let suiteName = "PermissionDisclosureStateStoringTests.declinePersist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        UserDefaultsPermissionDisclosureStore(defaults: defaults).decline(.background)

        let reloaded = UserDefaultsPermissionDisclosureStore(defaults: defaults)
        #expect(reloaded.isDeclined(.background))
        #expect(reloaded.isDeclined(.foreground) == false)
        #expect(reloaded.isAcknowledged(.background) == false, "decline must not be stored as/read back as acknowledgement")
    }

    @Test func userDefaultsStore_clearDeclinedPersistsAcrossInstances() {
        let suiteName = "PermissionDisclosureStateStoringTests.clearDeclinedPersist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        UserDefaultsPermissionDisclosureStore(defaults: defaults).decline(.foreground)

        UserDefaultsPermissionDisclosureStore(defaults: defaults).clearDeclined(.foreground)

        let reloaded = UserDefaultsPermissionDisclosureStore(defaults: defaults)
        #expect(reloaded.isDeclined(.foreground) == false)
    }

    @Test func userDefaultsStore_clearAlsoDropsDeclines() {
        let suiteName = "PermissionDisclosureStateStoringTests.clearAllPersist"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsPermissionDisclosureStore(defaults: defaults)
        store.acknowledge(.foreground)
        store.decline(.background)

        store.clear()

        let reloaded = UserDefaultsPermissionDisclosureStore(defaults: defaults)
        #expect(reloaded.isAcknowledged(.foreground) == false)
        #expect(reloaded.isDeclined(.background) == false)
    }
}
