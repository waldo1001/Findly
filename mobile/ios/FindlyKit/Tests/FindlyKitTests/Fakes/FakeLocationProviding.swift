import Foundation
@testable import FindlyKit

/// A shared `LocationProviding` fake — `FixCaptureCoordinator`'s only collaborator that touches
/// CoreLocation in production (specs/009-device-runtime.md §12: "pure, unit-tested
/// decision/coordination logic... no platform framework in unit tests"). Used by
/// `FixCaptureCoordinatorTests` (indirectly, via its own local fake) and directly by
/// `LocationSyncRunnerTests`/`LocationRuntimeContainerTests`.
final class FakeLocationProviding: LocationProviding {
    var nextFix: Result<LocationFix, Error> = .failure(LocationProvidingError.notImplemented)
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
