import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §7 — I1 ships scaffolding only; these tests confirm the protocol seam
/// and its fakes behave predictably (no CoreLocation/BackgroundTasks required).
struct LocationSensingScaffoldingTests {

    @Test func noOpLocationProvider_requestSingleFix_throwsNotImplemented() async {
        let provider = NoOpLocationProvider()
        do {
            _ = try await provider.requestSingleFix()
            Issue.record("expected LocationProvidingError.notImplemented")
        } catch let error as LocationProvidingError {
            #expect(error == .notImplemented)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func noOpBackgroundSyncScheduler_isInert() {
        let scheduler = NoOpBackgroundSyncScheduler()
        // Should not crash or throw; there's nothing to assert beyond "calling these is safe".
        scheduler.scheduleNextSync()
        scheduler.cancelScheduledSync()
    }
}
