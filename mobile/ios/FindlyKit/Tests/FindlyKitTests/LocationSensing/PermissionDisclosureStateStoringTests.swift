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
}
