import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §1.1 — the `source` → (accuracy tier, timeout) table. Pure, no
/// CoreLocation involved.
struct FixAccuracyPolicyTests {

    @Test func periodic_isBalancedWith30SecondTimeout() {
        #expect(FixAccuracyPolicy.tier(for: .periodic) == .balanced)
        #expect(FixAccuracyPolicy.timeout(for: .periodic) == 30)
    }

    @Test func locate_isHighWith30SecondTimeout() {
        #expect(FixAccuracyPolicy.tier(for: .locate) == .high)
        #expect(FixAccuracyPolicy.timeout(for: .locate) == 30)
    }

    @Test func geofence_isBalancedWith15SecondTimeout() {
        #expect(FixAccuracyPolicy.tier(for: .geofence) == .balanced)
        #expect(FixAccuracyPolicy.timeout(for: .geofence) == 15)
    }

    @Test func manual_isHighWith30SecondTimeout() {
        #expect(FixAccuracyPolicy.tier(for: .manual) == .high)
        #expect(FixAccuracyPolicy.timeout(for: .manual) == 30)
    }
}
