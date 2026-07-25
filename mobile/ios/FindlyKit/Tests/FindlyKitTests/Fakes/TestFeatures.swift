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
}
