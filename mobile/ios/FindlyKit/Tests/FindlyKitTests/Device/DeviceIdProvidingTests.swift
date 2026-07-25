import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §5, specs/001 §1.4 — a fresh UUIDv4 per signed-in user, stable across
/// calls for the same user.
struct DeviceIdProvidingTests {

    @Test func issuesAStableIdForTheSameUser() {
        var counter = 0
        let provider = InMemoryDeviceIdProvider(generateUUID: { counter += 1; return "generated-\(counter)" })

        let first = provider.deviceId(forUserId: "u1")
        let second = provider.deviceId(forUserId: "u1")

        #expect(first == second)
        #expect(first == "generated-1")
    }

    @Test func issuesAFreshIdWhenTheUserChanges() {
        var counter = 0
        let provider = InMemoryDeviceIdProvider(generateUUID: { counter += 1; return "generated-\(counter)" })

        let forU1 = provider.deviceId(forUserId: "u1")
        let forU2 = provider.deviceId(forUserId: "u2")

        #expect(forU1 != forU2)
        #expect(forU1 == "generated-1")
        #expect(forU2 == "generated-2")
    }

    @Test func clearDeviceId_forcesAFreshIdOnNextCall() {
        var counter = 0
        let provider = InMemoryDeviceIdProvider(generateUUID: { counter += 1; return "generated-\(counter)" })

        let before = provider.deviceId(forUserId: "u1")
        provider.clearDeviceId(forUserId: "u1")
        let after = provider.deviceId(forUserId: "u1")

        #expect(before != after)
    }
}
