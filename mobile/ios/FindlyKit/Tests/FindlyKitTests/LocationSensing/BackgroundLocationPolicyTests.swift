import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §3.4 (I50 fix 1 + fix 3) — `allowsBackgroundLocationUpdates` and
/// SLC/visit-monitoring eligibility MUST both be `true` exactly when authorization is `.always`,
/// and `false` for every other `LocationAuthorization` case (the root cause of every silent iOS
/// background capture per the amended spec — the property defaults to `false`, and CoreLocation
/// withholds standard-service updates in the background without it).
struct BackgroundLocationPolicyTests {

    @Test func allowsBackgroundLocationUpdates_trueOnlyForAlways() {
        #expect(BackgroundLocationPolicy.allowsBackgroundLocationUpdates(for: .always) == true)
        #expect(BackgroundLocationPolicy.allowsBackgroundLocationUpdates(for: .whenInUse) == false)
        #expect(BackgroundLocationPolicy.allowsBackgroundLocationUpdates(for: .notDetermined) == false)
        #expect(BackgroundLocationPolicy.allowsBackgroundLocationUpdates(for: .denied) == false)
    }

    @Test func shouldMonitorSignificantChangesAndVisits_trueOnlyForAlways() {
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .always) == true)
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .whenInUse) == false)
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .notDetermined) == false)
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .denied) == false)
    }
}
