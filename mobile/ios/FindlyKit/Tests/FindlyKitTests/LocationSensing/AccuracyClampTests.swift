import Testing
@testable import FindlyKit

/// specs/001-api-contract.md §5.1 (I50 fix 7, Minor) — the backend enforces `accuracyM` in
/// `[0, 10000]`; a violation is a `400 VALIDATION_FAILED` that kills the WHOLE batch (a definitive
/// rejection, specs/001 §5.1). Two call sites can hand CoreLocation-reported accuracy straight to
/// `LocationFix.accuracyM` unvalidated: `CLVisit.horizontalAccuracy` (undocumented range - I50
/// extends visit monitoring, so this is new) and `CLLocation.horizontalAccuracy` (documented to go
/// negative when invalid - pre-existing, closed while in the file). Pure clamp, CoreLocation-free,
/// so it's testable on any host; the two real call sites are `SystemLocationProvider`'s `didVisit`
/// delegate callback and `CLLocation.toLocationFix`, both platform glue.
struct AccuracyClampTests {

    @Test func withinRange_isUnchanged() {
        #expect(AccuracyClamp.clamp(0) == 0)
        #expect(AccuracyClamp.clamp(10) == 10)
        #expect(AccuracyClamp.clamp(10_000) == 10_000)
    }

    @Test func negative_isClampedToZero() {
        // CLLocation.horizontalAccuracy is documented to go negative when the value is invalid.
        #expect(AccuracyClamp.clamp(-1) == 0)
    }

    @Test func aboveTheBackendCeiling_isClampedTo10000() {
        #expect(AccuracyClamp.clamp(10_001) == 10_000)
        #expect(AccuracyClamp.clamp(1_000_000) == 10_000)
    }
}
