import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §1.1's accuracy table / 001 §6.3 (I52 review round 2, finding 3) —
/// `SystemLocationProvider.didUpdateLocations` resumed EVERY pending `requestSingleFix` caller with
/// whatever the platform delivered, no matter how coarse. That was harmless before the §1.3
/// presence session existed (the manager was only ever used for one-shot captures), but presence
/// keeps the SAME `CLLocationManager` continuously updating at kilometre accuracy, so a delivery
/// now routinely arrives while a high-accuracy (`.locate`/`.manual`) caller is ALSO pending —
/// including CoreLocation's immediate cached delivery right after a `desiredAccuracy` write. This
/// pure, CoreLocation-free policy is what `SystemLocationProvider` now consults before resuming.
struct PendingFixDeliveryPolicyTests {

    @Test func noHighAccuracyCallerPending_acceptsEvenAKilometreAccurateDelivery() {
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: .balanced, horizontalAccuracyMeters: 3000) == true)
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: nil, horizontalAccuracyMeters: 3000) == true)
    }

    @Test func highAccuracyCallerPending_rejectsAKilometreAccurateDelivery() {
        // The concrete hazard finding 3 names: a LOCATE_REQUEST fulfilled with a ~3 km presence fix.
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: .high, horizontalAccuracyMeters: 3000) == false)
    }

    @Test func highAccuracyCallerPending_acceptsAGenuinelyAccurateDelivery() {
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: .high, horizontalAccuracyMeters: 10) == true)
    }

    @Test func highAccuracyCallerPending_acceptsABalancedClassDelivery_100m() {
        // specs/009 §1.1: `.balanced` is "~100 m" — a genuine balanced-tier delivery must never be
        // wrongly rejected just because a high-accuracy caller also happens to be pending.
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: .high, horizontalAccuracyMeters: 100) == true)
    }

    @Test func highAccuracyCallerPending_boundaryIsInclusive() {
        let threshold = PendingFixDeliveryPolicy.highAccuracyThresholdMeters
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: .high, horizontalAccuracyMeters: threshold) == true)
        #expect(PendingFixDeliveryPolicy.shouldResumePendingFixes(highestPendingTier: .high, horizontalAccuracyMeters: threshold + 0.1) == false)
    }
}
