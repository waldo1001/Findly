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

    /// specs/009 §3.4 / §7 "Ongoing visibility" (H12, I62) — iOS shows the blue background-location
    /// indicator wherever background updates are allowed (parity with Android's persistent
    /// foreground-service notification).
    @Test func showsBackgroundLocationIndicator_trueWhereverBackgroundUpdatesAreAllowed() {
        for authorization in [LocationAuthorization.always, .whenInUse, .notDetermined, .denied] {
            #expect(
                BackgroundLocationPolicy.showsBackgroundLocationIndicator(for: authorization)
                    == BackgroundLocationPolicy.allowsBackgroundLocationUpdates(for: authorization)
            )
        }
        #expect(BackgroundLocationPolicy.showsBackgroundLocationIndicator(for: .always) == true)
    }

    @Test func shouldMonitorSignificantChangesAndVisits_trueOnlyForAlways() {
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .always) == true)
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .whenInUse) == false)
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .notDetermined) == false)
        #expect(BackgroundLocationPolicy.shouldMonitorSignificantChangesAndVisits(for: .denied) == false)
    }
}
