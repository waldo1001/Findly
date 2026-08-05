import Foundation
@testable import FindlyKit

/// A shared `LocationProviding` fake — `FixCaptureCoordinator`'s only collaborator that touches
/// CoreLocation in production (specs/009-device-runtime.md §12: "pure, unit-tested
/// decision/coordination logic... no platform framework in unit tests"). Used by
/// `FixCaptureCoordinatorTests` (indirectly, via its own local fake) and directly by
/// `LocationSyncRunnerTests`/`LocationRuntimeContainerTests`.
final class FakeLocationProviding: LocationProviding {
    var nextFix: Result<LocationFix, Error> = .failure(LocationProvidingError.notImplemented)

    /// specs/009 §7 — defaults to `.always` because these fakes stand in for a device whose user
    /// has already granted permission, which is the precondition every monitoring/capture test here
    /// is actually about. The protocol's own default is `.notDetermined` (correct for a real
    /// provider that has not asked yet), and inheriting that would make every such test silently
    /// assert the permission gate rather than the behaviour it was written for. Set it explicitly
    /// to exercise the gate itself.
    var authorization: LocationAuthorization = .always

    private(set) var requestSingleFixCalls: [FixSource] = []
    private(set) var startBackgroundMonitoringCallCount = 0
    private(set) var stopBackgroundMonitoringCallCount = 0

    func requestSingleFix(source: FixSource) async throws -> LocationFix {
        requestSingleFixCalls.append(source)
        return try nextFix.get()
    }

    func startBackgroundMonitoring(coordinator: FixCaptureCoordinator) {
        startBackgroundMonitoringCallCount += 1
    }

    func stopBackgroundMonitoring() {
        stopBackgroundMonitoringCallCount += 1
    }
}
