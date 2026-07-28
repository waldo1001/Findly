import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §5 — backs the "every app update" trigger: remembers, per signed-in
/// user, which `appVersion` was last successfully registered.
struct AppVersionRegistrationTrackingTests {

    @Test func noEntryYet_returnsNil() {
        let tracker = InMemoryAppVersionRegistrationTracker()
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == nil)
    }

    @Test func setThenGet_roundTrips() {
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.0.0")
    }

    @Test func keyedPerUser_independently() {
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        tracker.setLastRegisteredAppVersion("2.0.0", forUserId: "u2")
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.0.0")
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u2") == "2.0.0")
    }

    @Test func overwritingUpdatesTheStoredValue() {
        let tracker = InMemoryAppVersionRegistrationTracker()
        tracker.setLastRegisteredAppVersion("1.0.0", forUserId: "u1")
        tracker.setLastRegisteredAppVersion("1.0.1", forUserId: "u1")
        #expect(tracker.lastRegisteredAppVersion(forUserId: "u1") == "1.0.1")
    }
}
