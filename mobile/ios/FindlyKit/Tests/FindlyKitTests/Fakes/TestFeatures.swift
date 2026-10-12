@testable import FindlyKit

/// specs/001-api-contract.md §9 — a canned free-plan `features` object for building fake
/// `Envelope<T>` responses in tests (the synthesized memberwise inits below are only reachable
/// via `@testable import`, matching production code where clients only ever decode these types
/// from JSON, never construct them).
enum TestFeatures {
    static let free = Features(
        subscriptionStatus: "free",
        limits: PlanLimits(maxDevices: 10, maxGeofences: 20, historyDays: 90, minSyncIntervalMinutes: 5, locateRequestsPerDay: 100),
        flags: PlanFlags(pushToLocate: true, geofencing: true, historyReplay: true)
    )

    static func envelope<T: Decodable>(_ data: T) -> Envelope<T> {
        Envelope(data: data, features: free)
    }

    /// I66 — a fixture for asserting the group date picker's horizon comes from `features`.
    static func envelope<T: Decodable>(_ data: T, maxGroupDurationDays: Int?) -> Envelope<T> {
        let l = free.limits
        let limits = PlanLimits(
            maxDevices: l.maxDevices, maxGeofences: l.maxGeofences, historyDays: l.historyDays,
            minSyncIntervalMinutes: l.minSyncIntervalMinutes, locateRequestsPerDay: l.locateRequestsPerDay,
            maxOwnedGroups: l.maxOwnedGroups, maxJoinedGroups: l.maxJoinedGroups, maxGroupMembers: l.maxGroupMembers,
            maxGroupDurationDays: maxGroupDurationDays, groupGraceDays: l.groupGraceDays
        )
        return Envelope(data: data, features: Features(subscriptionStatus: free.subscriptionStatus, limits: limits, flags: free.flags))
    }

    /// specs/010-app-shell-and-screen-ux.md §4.2 — a fixture for asserting the sync-interval
    /// dropdown's floor comes from `features`, not a call-site literal.
    static func envelope<T: Decodable>(_ data: T, minSyncIntervalMinutes: Int) -> Envelope<T> {
        var limits = free.limits
        limits = PlanLimits(
            maxDevices: limits.maxDevices, maxGeofences: limits.maxGeofences, historyDays: limits.historyDays,
            minSyncIntervalMinutes: minSyncIntervalMinutes, locateRequestsPerDay: limits.locateRequestsPerDay,
            maxOwnedGroups: limits.maxOwnedGroups, maxJoinedGroups: limits.maxJoinedGroups, maxGroupMembers: limits.maxGroupMembers,
            maxGroupDurationDays: limits.maxGroupDurationDays, groupGraceDays: limits.groupGraceDays
        )
        let features = Features(subscriptionStatus: free.subscriptionStatus, limits: limits, flags: free.flags)
        return Envelope(data: data, features: features)
    }
}
