import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §7, specs/009-device-runtime.md §1/§7 — I10 replaced the I1 scaffolding
/// this file used to describe with real implementations (`SystemLocationProvider`,
/// `SystemBackgroundSyncScheduler`, both `#if os(iOS)`-gated). What remains testable on every host
/// (incl. this macOS session, no simulator) is the protocol seam + its no-op fakes.
///
/// **I53 — `@MainActor`.** `NoOpLocationProvider` conforms to `LocationProviding`, now `@MainActor`;
/// this suite calls its methods directly and synchronously (not through an already-`await`ed actor
/// seam like most other `LocationProviding` consumers), so the suite itself must be main-isolated.
@MainActor
struct LocationSensingScaffoldingTests {

    @Test func noOpLocationProvider_requestSingleFix_throwsNotImplemented() async {
        let provider = NoOpLocationProvider()
        do {
            _ = try await provider.requestSingleFix(source: .periodic)
            Issue.record("expected LocationProvidingError.notImplemented")
        } catch let error as LocationProvidingError {
            #expect(error == .notImplemented)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func noOpLocationProvider_backgroundMonitoring_isInert() {
        let provider = NoOpLocationProvider()
        let queue = FixQueue()
        let coordinator = FixCaptureCoordinator(provider: provider, queue: queue, isPaused: { false }, isPermissionGranted: { true })
        // Should not crash or throw; there's nothing to assert beyond "calling these is safe".
        provider.startBackgroundMonitoring(coordinator: coordinator)
        provider.stopBackgroundMonitoring()
    }

    @Test func noOpBackgroundSyncScheduler_isInert() {
        let scheduler = NoOpBackgroundSyncScheduler()
        // Should not crash or throw; there's nothing to assert beyond "calling these is safe".
        scheduler.scheduleNextSync()
        scheduler.cancelScheduledSync()
    }
}
